import 'dart:ffi';
import 'dart:io';

import 'package:apple_liquid_glass/src/foundation/environment.dart';
import 'package:apple_liquid_glass/src/foundation/platform.dart';
import 'package:apple_liquid_glass/src/foundation/uikit.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:objective_c/objective_c.dart' as objc;

const _asset = 'package:apple_liquid_glass/apple_liquid_glass.dylib';

@Native<Int Function()>(symbol: 'glass_is_main_thread', assetId: _asset)
external int _isMainThread();

@Native<Pointer<Void> Function(Int64)>(
  symbol: 'glass_controller_of_engine',
  assetId: _asset,
)
external Pointer<Void> _controllerOfEngine(int identifier);

@Native<Pointer<Void> Function()>(
  symbol: 'glass_controller_of_scenes',
  assetId: _asset,
)
external Pointer<Void> _controllerOfScenes();

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: 'glass_install_hinge',
  assetId: _asset,
)
external void _installHinge(Pointer<Void> view, Pointer<Void> interaction);

@Native<Int Function(Pointer<Void>, Int64)>(
  symbol: 'glass_set_vertical_bar_behavior',
  assetId: _asset,
)
external int _setVerticalBarBehavior(Pointer<Void> controller, int behavior);

/// The reader of the platform the app runs on: UIKit on iOS.
GlassPlatformReader createGlassPlatformReader() =>
    Platform.isIOS ? _UIKitReader.instance : const GlassSilentPlatformReader();

/// One per isolate: UIKit keeps one hinge interaction on the Flutter view,
/// and one answer to the side column, for the whole app.
final class _UIKitReader extends ChangeNotifier implements GlassPlatformReader {
  _UIKitReader._();

  static final instance = _UIKitReader._();

  static final _duo = objc.checkOSVersion(iOS: objc.Version(27, 1, 0));

  UIViewController? _controller;
  bool _hingeWatched = false;
  int _hingeStatus = UIHingeStatus.UIHingeStatusUnknown;

  // Flutter runs Dart on the main thread, which UIKit requires; an app that
  // turns that off gets the derived values.
  UIViewController? _controllerOnMainThread() {
    if (_isMainThread() == 0) return null;
    return _controller ??= _find();
  }

  static UIViewController? _find() {
    final engine = PlatformDispatcher.instance.engineId;
    var pointer = engine == null ? nullptr : _controllerOfEngine(engine);
    if (pointer == nullptr) pointer = _controllerOfScenes();
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
    _installHinge(view.ref.pointer.cast(), interaction.ref.pointer.cast());
  }

  @override
  void setBarColumnBehavior(GlassBarColumnBehavior behavior) {
    final controller = _controllerOnMainThread();
    if (controller == null || !_duo) return;
    _setVerticalBarBehavior(controller.ref.pointer.cast(), switch (behavior) {
      GlassBarColumnBehavior.automatic => 0,
      GlassBarColumnBehavior.disabled => 1,
    });
  }
}
