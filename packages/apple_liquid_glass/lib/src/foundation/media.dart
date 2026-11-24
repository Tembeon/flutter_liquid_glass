import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

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

  /// The insets a menu, popover or other floating layer keeps clear in the
  /// box whose `MediaQuery` [context] reads, the overlay it is laid out in:
  /// the safe area above the keyboard ([paddingAboveKeyboard]). A layer
  /// shown from a split view's column passes its overlay's context, as the
  /// column's `MediaQuery` describes the column.
  /// On a view that a hinge or fold splits
  /// (`MediaQueryData.displayFeatures`), they also keep the layer on the
  /// part of the view closest to [anchorPoint], its source's center in
  /// global coordinates, as `DisplayFeatureSubScreen` keeps a dialog to one
  /// part; without [anchorPoint], or with one on the band, on the left part,
  /// or the lower one where the band runs across, as UIKit does on the
  /// iPhone Duo half open in either reading direction (fold passport).
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
      anchorPoint: anchorPoint,
    );
  }

  /// The band that a hinge, or a fold half open, splits this view at from
  /// top to bottom with room on both sides, the leftmost if there are
  /// several, or null: the band UIKit puts a split view's border on and a
  /// sheet beside on the iPhone Duo half open (fold passport). A band
  /// across the view, or at its edge, splits nothing here.
  @internal
  Rect? get verticalBand {
    Rect? band;
    for (final feature in displayFeatures) {
      final bounds = feature.bounds;
      final separates =
          (feature.type == DisplayFeatureType.fold ||
              feature.type == DisplayFeatureType.hinge) &&
          (bounds.shortestSide > 0 ||
              feature.state == DisplayFeatureState.postureHalfOpened);
      if (!separates || bounds.height <= bounds.width) continue;
      if (bounds.left <= 0 || bounds.right >= size.width) continue;
      if (band == null || bounds.left < band.left) band = bounds;
    }
    return band;
  }

  /// [insets] grown, on a view that a hinge or fold splits
  /// ([displayFeatures]), to keep what lies inside them on the part of the
  /// view closest to [anchorPoint], in global coordinates, as
  /// `DisplayFeatureSubScreen` keeps a dialog to one part: without
  /// [anchorPoint], or with one on the band, the part holding the view's
  /// bottom left corner.
  @internal
  EdgeInsets onSubScreen(EdgeInsets insets, {Offset? anchorPoint}) {
    final whole = Offset.zero & size;
    final avoided = DisplayFeatureSubScreen.avoidBounds(this);
    if (avoided.isEmpty) return insets;
    final anchor =
        anchorPoint != null &&
            !avoided.any((bounds) => bounds.contains(anchorPoint))
        ? anchorPoint
        : whole.bottomLeft;
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
