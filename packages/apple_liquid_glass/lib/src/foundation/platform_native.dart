import 'dart:ffi';
import 'dart:io';

import 'package:apple_liquid_glass/src/foundation/environment.dart';
import 'package:apple_liquid_glass/src/foundation/platform.dart';
import 'package:apple_liquid_glass/src/foundation/platform.g.dart';
import 'package:apple_liquid_glass/src/foundation/uikit.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:objective_c/objective_c.dart' as objc;

/// The reader of the platform the app runs on: UIKit on iOS, AppKit's
/// settings on macOS.
GlassPlatformReader createGlassPlatformReader() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return const GlassSilentPlatformReader();
  }
  if (Platform.isIOS) return _UIKitReader.instance;
  if (Platform.isMacOS) return _AppKitReader.instance;
  return const GlassSilentPlatformReader();
}

/// Reads the settings, and observes them from the first read on.
abstract base class _NativeReader extends ChangeNotifier
    implements GlassPlatformReader {
  bool _observing = false;

  // Flutter runs Dart on the main thread, which UIKit and AppKit require; an
  // app that turns that off gets the derived values.
  static bool get _onMainThread => glass_is_main_thread() != 0;

  @override
  GlassPlatformSettings readSettings() {
    if (!_onMainThread) return GlassPlatformSettings.none;
    if (!_observing) {
      _observing = true;
      glass_observe_settings(ObjCBlock_ffiVoid.listener(notifyListeners));
    }
    final tint = glass_tint_amount();
    return GlassPlatformSettings(
      reduceTransparency: _flag(glass_reduce_transparency()),
      showBorders: _flag(glass_show_borders()),
      prefersCrossFade: _flag(glass_prefers_cross_fade()),
      glassTintAmount: tint < 0 ? null : tint,
      prefersReducedResourceUsage: _flag(
        glass_prefers_reduced_resource_usage(),
      ),
    );
  }

  static bool? _flag(int value) => value < 0 ? null : value != 0;
}

final class _AppKitReader extends _NativeReader {
  _AppKitReader._();

  static final instance = _AppKitReader._();

  @override
  GlassPlatformReport read() => GlassPlatformReport.none;

  @override
  void setBarColumnBehavior(GlassBarColumnBehavior behavior) {}
}

/// One per isolate: UIKit keeps one hinge interaction on the Flutter view,
/// and one answer to the side column, for the whole app.
final class _UIKitReader extends _NativeReader {
  _UIKitReader._();

  static final instance = _UIKitReader._();

  static final _duo = objc.checkOSVersion(iOS: objc.Version(27, 1, 0));

  UIViewController? _controller;
  bool _hingeWatched = false;
  int _hingeStatus = UIHingeStatus.UIHingeStatusUnknown;

  UIViewController? _controllerOnMainThread() {
    if (!_NativeReader._onMainThread) return null;
    return _controller ??= _find();
  }

  static UIViewController? _find() {
    final engine = PlatformDispatcher.instance.engineId;
    var pointer = engine == null ? nullptr : glass_controller_of_engine(engine);
    if (pointer == nullptr) pointer = glass_controller_of_scenes();
    if (pointer == nullptr) return null;
    return UIViewController.fromPointer(
      pointer.cast(),
      retain: true,
      release: true,
    );
  }

  @override
  GlassPlatformReport read() => objc.autoReleasePool(() {
    final controller = _controllerOnMainThread();
    if (controller == null) return GlassPlatformReport.none;
    final view = controller.view;
    if (_duo && !_hingeWatched) _watchHinge(view);
    final traits = view.traitCollection;
    final bounds = _rectOf(view.bounds);
    final safeArea = view.safeAreaInsets;
    final pad =
        traits.userInterfaceIdiom ==
        UIUserInterfaceIdiom.UIUserInterfaceIdiomPad;
    return GlassPlatformReport.fromUIKit(
      formFactor: switch (traits.userInterfaceIdiom) {
        UIUserInterfaceIdiom.UIUserInterfaceIdiomPhone => GlassFormFactor.phone,
        UIUserInterfaceIdiom.UIUserInterfaceIdiomPad => GlassFormFactor.tablet,
        UIUserInterfaceIdiom.UIUserInterfaceIdiomMac => GlassFormFactor.desktop,
        _ => null,
      },
      horizontalSizeClass: _sizeClassOf(traits.horizontalSizeClass),
      verticalSizeClass: _sizeClassOf(traits.verticalSizeClass),
      barColumnSide: _duo ? _barColumnSideOf(view, traits) : null,
      size: bounds.size,
      safeArea: EdgeInsets.fromLTRB(
        safeArea.left,
        safeArea.top,
        safeArea.right,
        safeArea.bottom,
      ),
      occlusions: _duo
          ? _activeRegions(view, UIViewReservedRegionKind.occlusionRegionKind())
          : const [],
      activeDivisions: _duo
          ? _activeRegions(view, UIViewReservedRegionKind.divisionRegionKind())
          : const [],
      hingeFlat:
          _hingeStatus == UIHingeStatus.UIHingeStatusClosed ||
          _hingeStatus == UIHingeStatus.UIHingeStatusFullyOpen,
      windowRegions: pad
          ? _activeRegions(view, UIViewReservedRegionKind.occlusionRegionKind())
          : const [],
    );
  });

  static GlassSizeClass? _sizeClassOf(int sizeClass) => switch (sizeClass) {
    UIUserInterfaceSizeClass.UIUserInterfaceSizeClassCompact =>
      GlassSizeClass.compact,
    UIUserInterfaceSizeClass.UIUserInterfaceSizeClassRegular =>
      GlassSizeClass.regular,
    _ => null,
  };

  // The edge is leading or trailing in UIKit's direction, which is the
  // system language's, not the Directionality an app sets.
  static GlassBarColumnSide? _barColumnSideOf(
    UIView view,
    UITraitCollection traits,
  ) {
    final leading = switch (traits.verticalBarEdge) {
      UIVerticalBarEdge.UIVerticalBarEdgeLeading => true,
      UIVerticalBarEdge.UIVerticalBarEdgeTrailing => false,
      _ => null,
    };
    if (leading == null) return null;
    const rightToLeftDirection = UIUserInterfaceLayoutDirection
        .UIUserInterfaceLayoutDirectionRightToLeft;
    final rightToLeft =
        view.effectiveUserInterfaceLayoutDirection == rightToLeftDirection;
    return leading != rightToLeft
        ? GlassBarColumnSide.left
        : GlassBarColumnSide.right;
  }

  static List<Rect> _activeRegions(UIView view, UIViewReservedRegionKind kind) {
    final regions = view.reservedRegionsOfKind(
      kind,
      options:
          UIViewReservedRegionQueryOptions.UIViewReservedRegionQueryOptionsNone,
    );
    return [
      for (final object in regions.asDart())
        if (UIViewReservedRegion.as(object) case final region
            when region.isActive)
          _rectOf(region.frame),
    ];
  }

  static Rect _rectOf(objc.CGRect rect) => Rect.fromLTWH(
    rect.origin.x,
    rect.origin.y,
    rect.size.width,
    rect.size.height,
  );

  // The hinge moves at about 30 updates a second; only its status decides
  // anything, so only a new status is reported.
  void _watchHinge(UIView view) {
    _hingeWatched = true;
    final handler =
        ObjCBlock_ffiVoid_UIHingeInteraction_UIHingeInteractionUpdate.listener((
          _,
          update,
        ) {
          final status =
              update.hinge?.status ?? UIHingeStatus.UIHingeStatusUnknown;
          if (status == _hingeStatus) return;
          _hingeStatus = status;
          notifyListeners();
        });
    final interaction = UIHingeInteraction.alloc().initWithUpdateHandler(
      handler,
    );
    glass_install_hinge(
      view.ref.pointer.cast(),
      interaction.ref.pointer.cast(),
    );
  }

  @override
  void setBarColumnBehavior(GlassBarColumnBehavior behavior) {
    final controller = _controllerOnMainThread();
    if (controller == null || !_duo) return;
    glass_set_vertical_bar_behavior(
      controller.ref.pointer.cast(),
      switch (behavior) {
        GlassBarColumnBehavior.automatic => 0,
        GlassBarColumnBehavior.disabled => 1,
      },
    );
  }
}
