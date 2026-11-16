import 'dart:ui';

import 'package:meta/meta.dart';

/// A rect of the screen's device pixels whose edges lie on whole pixels.
///
/// Only [ViewPixels] rounds a logical rect into one, so a box is rounded once
/// and whatever is laid out from it counts whole pixels.
@internal
extension type const DeviceBox._(Rect rect) {
  /// The box at [rect], whose edges already lie on whole device pixels.
  DeviceBox.whole(this.rect)
    : assert(
        rect.left == rect.left.roundToDouble() &&
            rect.top == rect.top.roundToDouble() &&
            rect.right == rect.right.roundToDouble() &&
            rect.bottom == rect.bottom.roundToDouble(),
        '$rect does not lie on whole device pixels.',
      );

  /// The left edge, in device pixels.
  double get left => rect.left;

  /// The top edge, in device pixels.
  double get top => rect.top;

  /// The right edge, in device pixels.
  double get right => rect.right;

  /// The bottom edge, in device pixels.
  double get bottom => rect.bottom;

  /// The width, in device pixels.
  double get width => rect.width;

  /// The height, in device pixels.
  double get height => rect.height;

  /// The top left corner.
  Offset get topLeft => rect.topLeft;

  /// The size, in device pixels.
  Size get size => rect.size;

  /// Whether the box holds no pixel.
  bool get isEmpty => rect.isEmpty;

  /// The pixels both boxes hold.
  DeviceBox intersect(DeviceBox other) =>
      DeviceBox._(rect.intersect(other.rect));

  /// The box grown to whole cells of [step] device pixels along each side,
  /// on a grid anchored at the screen's origin.
  DeviceBox outTo(int step) => step == 1
      ? this
      : DeviceBox._(
          Rect.fromLTRB(
            (left / step).floorToDouble() * step,
            (top / step).floorToDouble() * step,
            (right / step).ceilToDouble() * step,
            (bottom / step).ceilToDouble() * step,
          ),
        );

  /// The pixels across the box of a copy whose pixels hold [step] device
  /// pixels along each side.
  (int, int) pixelsOn(int step) =>
      ((width / step).round(), (height / step).round());

  /// The box grown down to [bottom], a whole device pixel, or itself where
  /// it already reaches it.
  DeviceBox downTo(double bottom) => bottom <= this.bottom
      ? this
      : DeviceBox._(Rect.fromLTRB(left, top, right, bottom));
}

/// The screen's device pixels: the one ratio a frame's glass lays its copies
/// out at, and the only code that rounds a logical rect to them.
@internal
@immutable
final class ViewPixels {
  /// The pixels of a screen of [devicePixelRatio] device pixels a logical
  /// pixel.
  const ViewPixels(this.devicePixelRatio);

  /// The screen's device pixels per logical pixel.
  final double devicePixelRatio;

  /// [rect] (logical pixels) grown to whole cells of [step] device pixels
  /// along each side, on a grid anchored at the screen's origin.
  ///
  /// A rect laid out from a box and scaled back lands a hair off its pixels
  /// (837 / 2.625 * 2.625 is 836.999...); it stays on them, or covering it
  /// again would grow it by a pixel.
  DeviceBox cover(Rect rect, {int step = 1}) {
    final pixels = devicePixelRatio / step;
    return DeviceBox._(
      Rect.fromLTRB(
        (rect.left * pixels + 1e-6).floorToDouble() * step,
        (rect.top * pixels + 1e-6).floorToDouble() * step,
        (rect.right * pixels - 1e-6).ceilToDouble() * step,
        (rect.bottom * pixels - 1e-6).ceilToDouble() * step,
      ),
    );
  }

  /// [box] in logical pixels.
  Rect logical(DeviceBox box) => Rect.fromLTRB(
    box.left / devicePixelRatio,
    box.top / devicePixelRatio,
    box.right / devicePixelRatio,
    box.bottom / devicePixelRatio,
  );

  @override
  bool operator ==(Object other) =>
      other is ViewPixels && other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode => devicePixelRatio.hashCode;
}
