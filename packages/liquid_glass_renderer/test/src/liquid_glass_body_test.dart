import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

const _box = Size(120, 44);

LiquidGlassShapeFrame _frame({Rect? rect, double sx = 1, double sy = 1}) =>
    LiquidGlassShapeFrame(
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      rect: rect,
      scaleX: sx,
      scaleY: sy,
    );

void main() {
  test('a body in place has no transform and paints at the box', () {
    const body = LiquidGlassBody(_box);
    expect(body.toBox, isNull);
    expect(body.childToBox, isNull);
    expect(body.size, _box);
    expect(body.drawn, Offset.zero & _box);
    expect(body.childOffset, Offset.zero);
  });

  test('the body maps onto its drawn rect, the child centered on it', () {
    for (final (rect, sx, sy) in [
      (const Rect.fromLTWH(10, 4, 60, 30), 1.0, 1.0),
      (const Rect.fromLTWH(10, 4, 60, 30), 1.2, 0.9),
      (null, 1.15, 1.15),
      (const Rect.fromLTWH(-5, 0, 200, 44), 0.8, 1.3),
    ]) {
      final body = _frame(rect: rect, sx: sx, sy: sy).bodyIn(_box);
      final toBox = body.toBox ?? Matrix4.identity();
      expect(
        MatrixUtils.transformRect(toBox, Offset.zero & body.size),
        rectMoreOrLessEquals(body.drawn, epsilon: 1e-9),
      );
      final childCenter = MatrixUtils.transformPoint(
        toBox,
        _box.center(Offset.zero) + body.childOffset,
      );
      expect(childCenter.dx, moreOrLessEquals(body.drawn.center.dx));
      expect(childCenter.dy, moreOrLessEquals(body.drawn.center.dy));
      expect(
        MatrixUtils.transformPoint(
          body.childToBox ?? Matrix4.identity(),
          _box.center(Offset.zero),
        ),
        offsetMoreOrLessEquals(childCenter),
      );
    }
  });
}
