import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/frame_meter.dart';
import 'package:apple_liquid_glass_example/home.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:flutter/widgets.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({
    this.settings = const GallerySettings(),
    this.notifier,
    this.home = const GalleryHome(),
    super.key,
  });

  /// The page the app opens on.
  final Widget home;

  final GallerySettings settings;

  /// Holds the settings instead of the app, for a caller that reads or
  /// changes them.
  final ValueNotifier<GallerySettings>? notifier;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final _settings = widget.notifier ?? ValueNotifier(widget.settings);

  @override
  void dispose() {
    if (widget.notifier == null) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GallerySettingsScope(
    notifier: _settings,
    child: ValueListenableBuilder(
      valueListenable: _settings,
      builder: (context, settings, _) => WidgetsApp(
        title: 'Liquid Glass',
        color: settings.accent.light,
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(routeSettings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: routeSettings),
        builder: (context, child) => GlassScope(
          renderer: settings.renderer.renderer,
          data: GlassThemeData(
            brightness: settings.brightness,
            primaryColor: settings.accent.color,
          ),
          child: GlassTraitsOverride(
            reduceTransparency: settings.reduceTransparency ? true : null,
            showBorders: settings.showBorders ? true : null,
            prefersCrossFade: settings.crossFade ? true : null,
            glassTintAmount: settings.glassTint,
            child: FrameMeter(
              shown: settings.frameMeter,
              child: const bool.fromEnvironment('GLASS_REPORT_OVERLAY')
                  ? LiquidGlassReportOverlay(
                      child: _Ambient(
                        child: GlassToaster(
                          child: _Posed(pose: settings.pose, child: child!),
                        ),
                      ),
                    )
                  : _Ambient(
                      child: GlassToaster(
                        child: _Posed(pose: settings.pose, child: child!),
                      ),
                    ),
            ),
          ),
        ),
        home: widget.home,
      ),
    ),
  );
}

/// The window as [pose] says, for every route of the app: the iPhone Duo's
/// column and status cluster on the right, a fold half open down the
/// middle, an iPad window's buttons or a desktop window's (glass-lab
/// spec/fold.md and spec/ipad-window.md).
class _Posed extends StatelessWidget {
  const _Posed({required this.pose, required this.child});

  final GalleryPose pose;
  final Widget child;

  static const double _column = 84;
  static const double _clusterHeight = 124;
  static const double _crease = 40;
  static const double _iPadButtons = 62;
  static const double _desktopButtons = 78;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final buttonsLine = media.padding.top + GlassWindowControls.rowCenter;
    final column = pose == GalleryPose.duoColumn;
    // One tree for every pose: the root navigator moved under other
    // parents would carry its semantics into the tree it left.
    return MediaQuery(
      data: switch (pose) {
        GalleryPose.duoColumn => media.copyWith(
          padding: media.padding.copyWith(top: 0, right: _column),
          viewPadding: media.viewPadding.copyWith(top: 0, right: _column),
        ),
        GalleryPose.halfOpen => media.copyWith(
          displayFeatures: [
            DisplayFeature(
              bounds: Rect.fromLTWH(
                (size.width - _crease) / 2,
                0,
                _crease,
                size.height,
              ),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
        _ => media,
      },
      child: GlassEnvironmentOverride(
        formFactor: switch (pose) {
          GalleryPose.duoColumn => GlassFormFactor.phone,
          GalleryPose.iPadWindow => GlassFormFactor.tablet,
          GalleryPose.desktopWindow => GlassFormFactor.desktop,
          _ => null,
        },
        windowControls: switch (pose) {
          GalleryPose.iPadWindow => GlassWindowControls(
            left: _iPadButtons,
            lineCenter: buttonsLine,
          ),
          GalleryPose.desktopWindow => GlassWindowControls(
            left: _desktopButtons,
            lineCenter: buttonsLine,
          ),
          _ => null,
        },
        barColumn: column
            ? const GlassBarColumn(
                side: GlassBarColumnSide.right,
                reservedWidth: _column,
              )
            : null,
        occlusions: column
            ? [Rect.fromLTWH(size.width - _column, 0, _column, _clusterHeight)]
            : null,
        child: child,
      ),
    );
  }
}

/// The text and icon style of everything the gallery draws itself.
class _Ambient extends StatelessWidget {
  const _Ambient({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: TextStyle(
      color: GlassDynamicColor.resolve(GlassColors.label, context),
    ),
    child: GlassDefaultTextStyle(
      role: GlassTextRole.body,
      child: IconTheme(
        data: IconThemeData(
          color: GlassDynamicColor.resolve(GlassColors.label, context),
          size: 22,
        ),
        child: child,
      ),
    ),
  );
}
