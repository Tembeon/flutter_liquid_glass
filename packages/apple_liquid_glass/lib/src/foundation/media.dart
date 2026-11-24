import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// What a glass overlay reads of the screen's insets.
extension GlassMediaQueryData on MediaQueryData {
  /// The bottom inset an overlay keeps clear: the larger of the safe area's
  /// and the keyboard's.
  double get bottomAboveKeyboard => math.max(padding.bottom, viewInsets.bottom);

  /// The safe area with its bottom grown to [bottomAboveKeyboard].
  EdgeInsets get paddingAboveKeyboard =>
      padding.copyWith(bottom: bottomAboveKeyboard);

  /// [insets] grown, on a view that a hinge or fold splits
  /// ([displayFeatures]), to keep what lies inside them on the part of the
  /// view closest to [anchorPoint], in global coordinates, as
  /// `DisplayFeatureSubScreen` keeps a dialog to one part: without
  /// [anchorPoint], the part at the start of [direction].
  @internal
  EdgeInsets onSubScreen(
    EdgeInsets insets, {
    required TextDirection direction,
    Offset? anchorPoint,
  }) {
    final whole = Offset.zero & size;
    final avoided = DisplayFeatureSubScreen.avoidBounds(this);
    if (avoided.isEmpty) return insets;
    final anchor =
        anchorPoint ??
        (direction == TextDirection.rtl ? whole.topRight : Offset.zero);
    Rect? part;
    var nearest = double.infinity;
    for (final screen in DisplayFeatureSubScreen.subScreensInBounds(
      whole,
      avoided,
    )) {
      final distance =
          (anchor -
                  Offset(
                    anchor.dx.clamp(screen.left, screen.right),
                    anchor.dy.clamp(screen.top, screen.bottom),
                  ))
              .distance;
      if (distance < nearest) {
        part = screen;
        nearest = distance;
      }
    }
    if (part == null) return insets;
    return EdgeInsets.fromLTRB(
      math.max(insets.left, part.left),
      math.max(insets.top, part.top),
      math.max(insets.right, whole.right - part.right),
      math.max(insets.bottom, whole.bottom - part.bottom),
    );
  }
}

/// The band at the top of a desktop window that holds the window's own
/// buttons when the app draws no title bar, which the app counts in the top
/// of `MediaQueryData.padding` so that its content stays clear of them.
///
/// Menus, popovers and the date picker's overlay cover the band, as a menu
/// covers a window's title bar: they keep clear of the top padding without
/// it ([overlayPaddingOf]). An app that merges such a band into the padding
/// names its [height] here, beside that padding and above its `Navigator`,
/// whose overlay the presentations are laid out in.
class GlassWindowBand extends InheritedWidget {
  /// Names a band [height] points tall at the top of the padding of
  /// [child].
  const GlassWindowBand({
    required this.height,
    required super.child,
    super.key,
  });

  /// How much of the top padding the band takes.
  final double height;

  /// The height of the band around [context], or 0 without a
  /// [GlassWindowBand].
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassWindowBand>()?.height ??
      0;

  /// The insets a menu, popover or other floating layer keeps clear around
  /// [context]: the safe area above the keyboard
  /// ([GlassMediaQueryData.paddingAboveKeyboard]) without the window band
  /// at its top. On a view that a hinge or fold splits
  /// (`MediaQueryData.displayFeatures`), they also keep the layer on the
  /// part of the view closest to [anchorPoint], its source's center in
  /// global coordinates, as `DisplayFeatureSubScreen` keeps a dialog to one
  /// part; without [anchorPoint], on the part at the start of the reading
  /// direction.
  static EdgeInsets overlayPaddingOf(
    BuildContext context, {
    Offset? anchorPoint,
  }) {
    final media = MediaQuery.of(context);
    final padding = media.paddingAboveKeyboard;
    return media.onSubScreen(
      padding.copyWith(top: math.max(0, padding.top - of(context))),
      direction: Directionality.maybeOf(context) ?? TextDirection.ltr,
      anchorPoint: anchorPoint,
    );
  }

  @override
  bool updateShouldNotify(GlassWindowBand oldWidget) =>
      oldWidget.height != height;
}
