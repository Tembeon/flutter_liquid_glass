import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

// Impeller reuses an offscreen target only at exactly the same size, and
// allocating one stalls the frame (11-36 ms on a Pixel 10).
const _pixelBucket = 64;

@internal
extension SnapRectToPixels on Rect {
  /// This rect with every edge multiplied by [factor], for a logical rect in
  /// device pixels.
  Rect scaled(double factor) => Rect.fromLTRB(
    left * factor,
    top * factor,
    right * factor,
    bottom * factor,
  );

  Rect snapToPixels(double devicePixelRatio) {
    return Rect.fromLTRB(
      left.snapToPixel(devicePixelRatio: devicePixelRatio),
      top.snapToPixel(devicePixelRatio: devicePixelRatio),
      right.snapToPixel(devicePixelRatio: devicePixelRatio),
      bottom.snapToPixel(devicePixelRatio: devicePixelRatio),
    );
  }

  /// Expands this rect outward to multiples of 64 device pixels, for a
  /// render target that would otherwise change size every frame.
  Rect expandToPixelBuckets(double devicePixelRatio) {
    final logicalBucket = _pixelBucket / devicePixelRatio;
    return Rect.fromLTRB(
      (left / logicalBucket).floorToDouble() * logicalBucket,
      (top / logicalBucket).floorToDouble() * logicalBucket,
      (right / logicalBucket).ceilToDouble() * logicalBucket,
      (bottom / logicalBucket).ceilToDouble() * logicalBucket,
    );
  }
}

extension on double {
  double snapToPixel({required double devicePixelRatio}) {
    // Resolve half-pixel ties in the same direction on both sides of zero.
    // roundToDouble rounds ties away from zero, so moving an antialiased
    // matte across the origin changes its dimensions by a pixel. A retained
    // translated matte must match one rasterized at the destination.
    return (this * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;
  }
}
