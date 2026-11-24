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

  /// The insets a menu, popover or other floating layer keeps clear around
  /// [context]: the safe area above the keyboard ([paddingAboveKeyboard]).
  /// On a view that a hinge or fold splits
  /// (`MediaQueryData.displayFeatures`), they also keep the layer on the
  /// part of the view closest to [anchorPoint], its source's center in
  /// global coordinates, as `DisplayFeatureSubScreen` keeps a dialog to one
  /// part; without [anchorPoint], on the part at the start of the reading
  /// direction.
  ///
  /// A window's buttons are not in the padding (`GlassWindowControls`), so
  /// a layer may reach the first row beside them.
  static EdgeInsets overlayPaddingOf(
    BuildContext context, {
    Offset? anchorPoint,
  }) {
    final media = MediaQuery.of(context);
    return media.onSubScreen(
      media.paddingAboveKeyboard,
      direction: Directionality.maybeOf(context) ?? TextDirection.ltr,
      anchorPoint: anchorPoint,
    );
  }

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
