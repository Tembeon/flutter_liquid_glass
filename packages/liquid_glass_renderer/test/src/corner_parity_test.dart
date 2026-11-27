@Tags(['macos_pixels'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('corner');
const _box = Rect.fromLTWH(45, 45, 120, 60);
const _radius = 16.0;
const _pixelRatio = 2.0;
const _view = Size(210, 150);

double _boxDistance(double x, double y) {
  final qx = (x - _box.center.dx).abs() - _box.width / 2 + _radius;
  final qy = (y - _box.center.dy).abs() - _box.height / 2 + _radius;
  final outside = math.sqrt(
    math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2),
  );
  return outside + math.min(math.max(qx, qy), 0) - _radius;
}

// The field of [_box] as an owner that fuses rounded boxes builds it: the
// exact distance, and a gradient that turns on a corner of [opticalRadius].
LiquidGlassField _field({required double opticalRadius}) {
  const step = 1.0;
  const margin = 4.0;
  final origin = _box.topLeft - const Offset(margin, margin);
  final columns = (_box.width + 2 * margin) ~/ step + 1;
  final rows = (_box.height + 2 * margin) ~/ step + 1;
  final halfMinor = math.min(_box.width, _box.height) / 2;
  final samples = Float32List(columns * rows * 4);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < columns; i++) {
      final x = origin.dx + i * step;
      final y = origin.dy + j * step;
      final sx = x < _box.center.dx ? -1.0 : 1.0;
      final sy = y < _box.center.dy ? -1.0 : 1.0;
      final ox = (x - _box.center.dx).abs() - _box.width / 2 + opticalRadius;
      final oy = (y - _box.center.dy).abs() - _box.height / 2 + opticalRadius;
      final length = math.sqrt(ox * ox + oy * oy);
      final (gx, gy) = ox > 0 && oy > 0
          ? (sx * ox / length, sy * oy / length)
          : ox > oy
          ? (sx, 0.0)
          : (0.0, sy);
      final at = (j * columns + i) * 4;
      samples[at] = _boxDistance(x, y);
      samples[at + 1] = gx;
      samples[at + 2] = gy;
      samples[at + 3] = halfMinor;
    }
  }
  return LiquidGlassField(
    samples: samples,
    columns: columns,
    rows: rows,
    origin: origin,
    step: step,
    edge: Path()
      ..addRRect(RRect.fromRectAndRadius(_box, const Radius.circular(_radius))),
  );
}

// The colour channels of [_box]'s top right corner, as far in as the turned
// corner reaches, at the pixels whose centres lie half a point or more
// inside its outline: the rim light, without the edge's antialiasing, which
// a field takes from its interpolated distance.
Future<List<int>> _corner(
  WidgetTester tester, {
  required bool fake,
  LiquidGlassField? field,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _key,
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.white,
                child: GridPaper(color: Colors.black, interval: 20),
              ),
            ),
            Positioned.fill(
              child: LiquidGlassLayer(
                settings: const LiquidGlassSettings.ios27Regular(),
                fake: fake,
                field: field,
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: _box,
                      child: const LiquidGlass(
                        shape: LiquidRoundedRectangle(radius: _radius),
                        appearance: LiquidGlassAppearance.ios27Regular(
                          brightness: Brightness.light,
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  final pixels = await boundaryPixels(
    tester,
    find.byKey(_key),
    pixelRatio: _pixelRatio,
  );
  final width = (_view.width * _pixelRatio).round();
  const reach = _radius * LiquidGlassField.opticalCornerScale;
  final rows = (
    (_box.top * _pixelRatio).floor(),
    ((_box.top + reach) * _pixelRatio).ceil(),
  );
  final columns = (
    ((_box.right - reach) * _pixelRatio).floor(),
    (_box.right * _pixelRatio).ceil(),
  );
  final channels = <int>[];
  for (var y = rows.$1; y < rows.$2; y++) {
    for (var x = columns.$1; x < columns.$2; x++) {
      final distance = _boxDistance(
        (x + 0.5) / _pixelRatio,
        (y + 0.5) / _pixelRatio,
      );
      if (distance > -0.5) continue;
      final at = (y * width + x) * 4;
      channels.addAll(pixels.sublist(at, at + 3));
    }
  }
  return channels;
}

void main() {
  // LiquidGlassField.opticalCornerScale promises that an owner who turns a
  // rounded box's gradient by it lights the corner as the shape drawn alone
  // does: real glass turns the shape's normals in its geometry, fake glass in
  // fake_glass_surface.frag, and a field's in the gradient its owner gives.
  // A field whose gradient does not turn lights the corner 32 levels off on
  // real glass and 22 on fake glass.
  for (final fake in [false, true]) {
    testWidgets('a field of a rounded box whose gradient turns by '
        'opticalCornerScale lights its corner as the shape does '
        '(${fake ? 'fake' : 'real'} glass)', (tester) async {
      tester.view
        ..physicalSize = _view * _pixelRatio
        ..devicePixelRatio = _pixelRatio;
      addTearDown(tester.view.reset);
      final shape = await _corner(tester, fake: fake);
      final turned = await _corner(
        tester,
        fake: fake,
        field: _field(
          opticalRadius: _radius * LiquidGlassField.opticalCornerScale,
        ),
      );
      final unturned = await _corner(
        tester,
        fake: fake,
        field: _field(opticalRadius: _radius),
      );
      expect(largestDifference(shape, turned), lessThanOrEqualTo(1));
      expect(largestDifference(shape, unturned), greaterThan(15));
    }, skip: !fake && skipProperGlassTests);
  }
}
