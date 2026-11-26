@Tags(['macos_pixels', 'composer'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

// Glass on a path that draws one Gaussian and no fill (the backdrop
// filter, fake glass, an Impeller-blurred copy) against the same glass
// over a copy it blurs from levels and fills, its own recipe. One-sigma
// glass is drawn over a full-size copy Impeller blurs (`_oneSigma`), which
// draws what reading the backdrop draws (backdrop_underlay_frost_test) and
// lets one process draw every cell.
//
// `--dart-define=ONE_SIGMA_TABLE=<file>` sweeps every look, size, slider
// and display and writes the difference per cell to <file>, and
// `--dart-define=ONE_SIGMA_CROPS=<dir>` saves a light and a dark control
// at slider 0 over strokes, drawn both ways.

const _table = String.fromEnvironment('ONE_SIGMA_TABLE');
const _crops = String.fromEnvironment('ONE_SIGMA_CROPS');

const _key = ValueKey('screen');
const _margin = 64.0;
const _oneSigma = PlanPolicy(shaderFrost: false, maxCopyShare: 1);

enum _Look {
  regularLight('regular-light'),
  regularDark('regular-dark'),
  clear('clear');

  const _Look(this.label);

  final String label;

  LiquidGlassSettings settings(double slider) => this == clear
      ? LiquidGlassSettings.ios27Clear(sliderPosition: slider)
      : LiquidGlassSettings.ios27Regular(sliderPosition: slider);

  LiquidGlassAppearance get appearance => switch (this) {
    regularLight => const LiquidGlassAppearance.ios27Regular(
      brightness: Brightness.light,
    ),
    regularDark => const LiquidGlassAppearance.ios27Regular(
      brightness: Brightness.dark,
    ),
    clear => const LiquidGlassAppearance.ios27Clear(),
  };
}

enum _Backdrop { cells, strokes, photo }

Size _band(double side) => Size(2.5 * side + 2 * _margin, side + 2 * _margin);

Widget _scene(_Look look, double side, double slider) {
  final band = _band(side);
  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Stack(
        children: [
          for (final backdrop in _Backdrop.values) ...[
            Positioned(
              left: 0,
              top: band.height * backdrop.index,
              width: band.width,
              height: band.height,
              child: RepaintBoundary(
                child: CustomPaint(painter: _BackdropPainter(backdrop)),
              ),
            ),
            Positioned(
              left: _margin,
              top: band.height * backdrop.index + _margin,
              width: 2.5 * side,
              height: side,
              child: LiquidGlassLayer(
                settings: look.settings(slider),
                child: LiquidGlass(
                  shape: LiquidRoundedRectangle(radius: side / 2),
                  appearance: look.appearance,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.backdrop);

  final _Backdrop backdrop;

  @override
  void paint(Canvas canvas, Size size) {
    switch (backdrop) {
      case _Backdrop.cells:
        _cells(canvas, size);
      case _Backdrop.strokes:
        _strokes(canvas, size);
      case _Backdrop.photo:
        _photo(canvas, size);
    }
  }

  static void _cells(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF5A5A5A),
    );
    final light = Paint()..color = const Color(0xFFC8C8C8);
    for (var y = 0.0; y < size.height; y += 8) {
      for (
        var x = (y / 8).round().isEven ? 0.0 : 8.0;
        x < size.width;
        x += 16
      ) {
        canvas.drawRect(Rect.fromLTWH(x, y, 8, 8), light);
      }
    }
  }

  static void _strokes(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final ink = Paint()
      ..color = const Color(0xFF1C1C1E)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final random = Random(7);
    for (var y = 6.0; y < size.height - 6; y += 13) {
      var x = 4.0;
      while (x < size.width - 8) {
        final glyph = 4 + random.nextDouble() * 4;
        for (var i = 0; i < 2; i++) {
          final a = Offset(
            x + random.nextDouble() * glyph,
            y + random.nextDouble() * 9,
          );
          final b = Offset(
            x + random.nextDouble() * glyph,
            y + random.nextDouble() * 9,
          );
          canvas.drawLine(a, b, ink);
        }
        x += glyph + 1.5 + (random.nextInt(6) == 0 ? 5 : 0);
      }
    }
  }

  static void _photo(Canvas canvas, Size size) {
    const step = 6.0;
    final columns = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;
    final random = Random(11);
    final waves = [
      for (var octave = 0; octave < 5; octave++)
        for (var i = 0; i < 3; i++)
          (
            fx: (random.nextDouble() - 0.5) * 2 * pi / (240 / (1 << octave)),
            fy: (random.nextDouble() - 0.5) * 2 * pi / (240 / (1 << octave)),
            phase: random.nextDouble() * 2 * pi,
            amplitude: 1 / (1 << octave),
            channel: random.nextInt(3),
          ),
    ];
    Color at(double x, double y) {
      final rgb = [0.5, 0.45, 0.4];
      for (final w in waves) {
        rgb[w.channel] +=
            0.22 * w.amplitude * sin(w.fx * x + w.fy * y + w.phase);
        final shade = 0.12 * w.amplitude * sin(w.fx * x - w.fy * y + w.phase);
        for (var c = 0; c < 3; c++) {
          rgb[c] += shade;
        }
      }
      return Color.from(
        alpha: 1,
        red: rgb[0].clamp(0, 1),
        green: rgb[1].clamp(0, 1),
        blue: rgb[2].clamp(0, 1),
      );
    }

    final positions = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final p = Offset(column * step, row * step);
        positions.add(p);
        colors.add(at(p.dx, p.dy));
      }
    }
    for (var row = 0; row < rows - 1; row++) {
      for (var column = 0; column < columns - 1; column++) {
        final i = row * columns + column;
        indices.addAll([
          i,
          i + 1,
          i + columns,
          i + 1,
          i + columns + 1,
          i + columns,
        ]);
      }
    }
    canvas.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: indices,
      ),
      BlendMode.dst,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.backdrop != backdrop;
}

typedef _Difference = ({double faceMean, int faceP99, double rimMean});

final class _Frame {
  _Frame(this.bytes, this.width, this.dpr);

  final Uint8List bytes;
  final int width;
  final double dpr;
}

Future<_Frame> _draw(
  WidgetTester tester,
  _Look look,
  double side,
  double slider,
  double dpr,
) async {
  final band = _band(side);
  final size = Size(band.width, band.height * _Backdrop.values.length);
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_scene(look, side, slider));
  for (final layer
      in tester.allRenderObjects.whereType<RenderLiquidGlassLayer>()) {
    expect(layer.debugDrewOverCopy, isTrue);
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: dpr),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  final frame = _Frame(bytes.buffer.asUint8List(), image.width, dpr);
  image.dispose();
  return frame;
}

// Inside a stadium of [size] at [origin] by [inset] logical pixels.
bool _inside(Offset p, Offset origin, Size size, double inset) {
  final r = size.height / 2 - inset;
  if (r <= 0) return false;
  final local = p - origin;
  final x = local.dx.clamp(size.height / 2, size.width - size.height / 2);
  return (local - Offset(x, size.height / 2)).distance <= r;
}

_Difference _difference(
  _Frame a,
  _Frame b,
  double side,
  _Backdrop backdrop,
) {
  final band = _band(side);
  final origin = Offset(_margin, band.height * backdrop.index + _margin);
  final glass = Size(2.5 * side, side);
  final face = List.filled(256, 0);
  var rim = 0;
  var rimCount = 0;
  final top = (origin.dy * a.dpr).floor();
  final bottom = ((origin.dy + glass.height) * a.dpr).ceil();
  final left = (origin.dx * a.dpr).floor();
  final right = ((origin.dx + glass.width) * a.dpr).ceil();
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final p = Offset((x + 0.5) / a.dpr, (y + 0.5) / a.dpr);
      final inFace = _inside(p, origin, glass, 1);
      final inRim = !inFace && _inside(p, origin, glass, 0);
      if (!inFace && !inRim) continue;
      final i = (y * a.width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final d = (a.bytes[i + c] - b.bytes[i + c]).abs();
        if (inFace) {
          face[d]++;
        } else {
          rim += d;
          rimCount++;
        }
      }
    }
  }
  final count = face.fold(0, (s, n) => s + n);
  var sum = 0;
  var p99 = 0;
  var seen = 0;
  for (var d = 0; d < 256; d++) {
    sum += d * face[d];
    seen += face[d];
    if (seen <= count * 0.99) p99 = d + 1;
  }
  return (
    faceMean: sum / count,
    faceP99: min(p99, 255),
    rimMean: rimCount == 0 ? 0 : rim / rimCount,
  );
}

Future<Map<_Backdrop, _Difference>> _cell(
  WidgetTester tester,
  _Look look,
  double side,
  double slider,
  double dpr,
) async {
  final copy = await _draw(tester, look, side, slider, dpr);
  debugGlassPolicy = _oneSigma;
  final single = await _draw(tester, look, side, slider, dpr);
  debugGlassPolicy = const PlanPolicy();
  return {
    for (final backdrop in _Backdrop.values)
      backdrop: _difference(copy, single, side, backdrop),
  };
}

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() {
    glassReadsCopies = false;
    debugGlassPolicy = const PlanPolicy();
  });

  testWidgets('clear glass at slider 0 draws alike on both paths: neither '
      'blurs', (tester) async {
    addTearDown(tester.view.reset);
    final cell = await _cell(tester, _Look.clear, 63, 0, 3);
    for (final difference in cell.values) {
      expect(difference.faceMean, lessThanOrEqualTo(1));
    }
  }, skip: skipProperGlassTests);

  testWidgets('every look, size, slider and display, written to '
      'ONE_SIGMA_TABLE', (tester) async {
    addTearDown(tester.view.reset);
    final lines = [
      'look\tside\tslider\tdpr\tbackdrop\tface_mean\tface_p99\trim_mean',
    ];
    for (final look in _Look.values) {
      for (final side in [44.0, 63.0, 94.0, 118.0, 150.0, 200.0]) {
        for (final slider in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          for (final dpr in [3.0, 2.625]) {
            final cell = await _cell(tester, look, side, slider, dpr);
            for (final MapEntry(key: backdrop, value: d) in cell.entries) {
              lines.add(
                '${look.label}\t$side\t$slider\t$dpr\t${backdrop.name}\t'
                '${d.faceMean.toStringAsFixed(2)}\t${d.faceP99}\t'
                '${d.rimMean.toStringAsFixed(2)}',
              );
            }
          }
        }
      }
    }
    File(_table).writeAsStringSync('${lines.join('\n')}\n');
  }, skip: skipProperGlassTests || _table.isEmpty);

  testWidgets('a light and a dark control at slider 0 over strokes, saved '
      'to ONE_SIGMA_CROPS', (tester) async {
    addTearDown(tester.view.reset);
    const side = 44.0;
    const dpr = 3.0;
    final band = _band(side);
    final crop = Rect.fromLTWH(
      _margin - 12,
      band.height * _Backdrop.strokes.index + _margin - 12,
      2.5 * side + 24,
      side + 24,
    );
    for (final look in [_Look.regularLight, _Look.regularDark]) {
      for (final (name, policy) in [
        ('copy', const PlanPolicy()),
        ('one-sigma', _oneSigma),
      ]) {
        debugGlassPolicy = policy;
        await _draw(tester, look, side, 0, dpr);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_key),
        );
        final png = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: dpr);
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawImageRect(
            image,
            Rect.fromLTWH(
              crop.left * dpr,
              crop.top * dpr,
              crop.width * dpr,
              crop.height * dpr,
            ),
            Offset.zero & (crop.size * dpr),
            Paint(),
          );
          final cropped = await recorder.endRecording().toImage(
            (crop.width * dpr).round(),
            (crop.height * dpr).round(),
          );
          final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          cropped.dispose();
          return data!;
        });
        File('$_crops/${look.label}-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
  }, skip: skipProperGlassTests || _crops.isEmpty);
}
