import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_field_image.dart';

const _turn = math.pi / 10;

LiquidGlassField _field() {
  const cols = 400;
  const rows = 200;
  final samples = Float32List(cols * rows * 4);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final at = (j * cols + i) * 4;
      final (x, y) = (i - 200.3, j - 99.7);
      final reach = math.sqrt(x * x + y * y);
      samples[at] = reach - 80;
      // The gradient turned by a fifth of a right angle, as an owner turns
      // one near a corner, so the image shows it read rather than derived.
      final (gx, gy) = reach > 0 ? (x / reach, y / reach) : (0.0, 0.0);
      samples[at + 1] = gx * math.cos(_turn) - gy * math.sin(_turn);
      samples[at + 2] = gx * math.sin(_turn) + gy * math.cos(_turn);
    }
  }
  return LiquidGlassField(
    samples: samples,
    columns: cols,
    rows: rows,
    origin: ui.Offset.zero,
    step: 1,
    edge: ui.Path()
      ..addOval(
        ui.Rect.fromCircle(center: const ui.Offset(200.3, 99.7), radius: 80),
      ),
  );
}

void main() {
  test('every texel holds its node: the distance in red, the direction of '
      "the field's own gradient in green and blue", () async {
    final field = _field();
    final LiquidGlassField(:samples, columns: cols, :rows) = field;
    expect(cols * rows, greaterThan(1 << 16));
    final images = FakeGlassFieldImage();
    addTearDown(images.dispose);
    final image = images.of(field);
    expect((image.width, image.height), (cols, rows));
    final bytes = (await image.toByteData())!.buffer.asUint8List();

    double distance(int i, int j) => samples[(j * cols + i) * 4];
    const span = fakeFieldInside + fakeFieldOutside;
    var worst = 0;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final gx = samples[(j * cols + i) * 4 + 1];
        final gy = samples[(j * cols + i) * 4 + 2];
        final length = math.sqrt(gx * gx + gy * gy);
        final expected = [
          ((distance(i, j) + fakeFieldInside) / span).clamp(0.0, 1.0),
          gx / length * 0.5 + 0.5,
          gy / length * 0.5 + 0.5,
          1.0,
        ];
        final at = (j * cols + i) * 4;
        for (var c = 0; c < 4; c++) {
          final error = (bytes[at + c] - expected[c] * 255).abs().round();
          worst = math.max(worst, error);
        }
      }
    }
    expect(worst, lessThanOrEqualTo(1));
  });

  test('the image is drawn again only for other samples', () {
    final field = _field();
    final images = FakeGlassFieldImage();
    addTearDown(images.dispose);
    final first = images.of(field);
    expect(
      images.of(
        LiquidGlassField(
          samples: field.samples,
          columns: field.columns,
          rows: field.rows,
          origin: field.origin + const ui.Offset(5, 5),
          step: field.step,
          edge: field.edge,
        ),
      ),
      same(first),
    );
    expect(images.of(_field()), isNot(same(first)));
  });
}
