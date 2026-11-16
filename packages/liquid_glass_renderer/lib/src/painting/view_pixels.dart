import 'dart:ui';

import 'package:meta/meta.dart';

/// A rect of the screen's device pixels whose edges lie on whole pixels.
///
/// Only [ViewPixels] rounds a logical rect into one, so a box is rounded once
/// and whatever is laid out from it counts whole pixels.
@internal
extension type const DeviceBox._(Rect rect) {
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

// Impeller reuses an offscreen target only at exactly the same size, and
// allocating one stalls the frame (11-36 ms on a Pixel 10).
const _pixelBucket = 64;

/// The screen's device pixels: the one ratio a frame's glass lays its copies
/// out at.
@internal
extension type const ViewPixels(double devicePixelRatio) {
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

  /// [rect] (logical pixels, in any space the screen's pixels are whole in)
  /// grown out to whole pixels.
  Rect outward(Rect rect) => logical(cover(rect));

  /// [size] (logical pixels) grown to whole pixels.
  Size whole(Size size) => Size(
    (size.width * devicePixelRatio).ceilToDouble() / devicePixelRatio,
    (size.height * devicePixelRatio).ceilToDouble() / devicePixelRatio,
  );

  /// [rect] (logical pixels, in any space the screen's pixels are whole in)
  /// with each edge moved to the nearest whole pixel.
  ///
  /// Half-pixel ties go the same way on both sides of zero: roundToDouble
  /// rounds them away from zero, so a matte moved across the origin would
  /// change size by a pixel, and a retained translated matte must match one
  /// rasterized at the destination.
  Rect nearest(Rect rect) => Rect.fromLTRB(
    _nearest(rect.left),
    _nearest(rect.top),
    _nearest(rect.right),
    _nearest(rect.bottom),
  );

  double _nearest(double edge) =>
      (edge * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;

  /// [rect] (logical pixels) grown outward to multiples of 64 device pixels,
  /// for a render target that would otherwise change size every frame.
  Rect bucket(Rect rect) {
    final logicalBucket = _pixelBucket / devicePixelRatio;
    return Rect.fromLTRB(
      (rect.left / logicalBucket).floorToDouble() * logicalBucket,
      (rect.top / logicalBucket).floorToDouble() * logicalBucket,
      (rect.right / logicalBucket).ceilToDouble() * logicalBucket,
      (rect.bottom / logicalBucket).ceilToDouble() * logicalBucket,
    );
  }
}
