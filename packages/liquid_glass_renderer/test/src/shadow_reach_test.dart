import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';

const _side = 400;

Future<Uint8List> _alphaOf(
  WidgetTester tester,
  Rect body,
  BoxShadow shadow,
) async {
  final recorder = ui.PictureRecorder();
  debugDisableShadows = false;
  try {
    Canvas(recorder).drawRRect(
      RRect.fromRectAndRadius(
        body.shift(shadow.offset).inflate(shadow.spreadRadius),
        const Radius.circular(20),
      ),
      shadow.toPaint(),
    );
  } finally {
    debugDisableShadows = true;
  }
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(() => picture.toImage(_side, _side)))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  final cases = <String, (Size, BoxShadow)>{
    for (final brightness in Brightness.values)
      for (final size in const [Size(120, 44), Size(200, 112), Size(220, 180)])
        '${brightness.name} ${size.height}': (
          size,
          LiquidGlassShadow.ios27Regular(brightness: brightness).castAt(size),
        ),
    'opaque': (
      const Size(200, 120),
      const BoxShadow(blurRadius: 20),
    ),
  };

  for (final MapEntry(key: name, value: (size, shadow)) in cases.entries) {
    testWidgets('a shadow shows nothing past its bounds ($name)', (
      tester,
    ) async {
      final body =
          Offset(
            (_side - size.width) / 2,
            (_side - size.height) / 2 - 20,
          ) &
          size;
      final bounds = glassShadowBounds(body, [shadow], 1);
      final alpha = await _alphaOf(tester, body, shadow);
      var past = 0;
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x++) {
          if (bounds.contains(Offset(x + 0.5, y + 0.5))) continue;
          final a = alpha[(y * _side + x) * 4 + 3];
          if (a > past) past = a;
        }
      }
      expect(past, lessThanOrEqualTo(1));
      expect(bounds.left, greaterThan(0));
      expect(bounds.bottom, lessThan(_side));
    });
  }

  test('a faint shadow reaches less far than a dark one of its blur', () {
    const body = Rect.fromLTWH(0, 0, 120, 44);
    final faint = const LiquidGlassShadow.ios27Regular(
      brightness: Brightness.light,
    ).castAt(body.size);
    final reach = body.left - glassShadowBounds(body, [faint], 1).left;
    expect(reach, closeTo(faint.blurSigma, 0.05 * faint.blurSigma));
    final opaque = faint.copyWith(color: const Color(0xFF000000));
    final opaqueReach = body.left - glassShadowBounds(body, [opaque], 1).left;
    expect(opaqueReach, closeTo(2.885 * faint.blurSigma, 0.01));
  });
}
