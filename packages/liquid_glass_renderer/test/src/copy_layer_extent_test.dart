// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the layer is
// sized as Impeller sizes it.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';

void main() {
  // A picture records with an R-tree, as a scene on macOS does, and sizes a
  // layer by those of a picture's draws that meet the clip. A blur clamped
  // at the layer's edge shows where the layer ends: past a square that fills
  // the layer it stays whole, inside a larger layer it fades.
  test(
    'a copy layer past the clip at its bottom right keeps its size',
    () async {
      const square = Rect.fromLTWH(0, 0, 10, 10);
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..clipRect(const Rect.fromLTWH(0, 0, 100, 100))
        ..saveLayer(
          null,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: 4,
              sigmaY: 4,
              tileMode: TileMode.clamp,
            ),
        )
        ..drawPicture(CornerRead.corners(const Size(140, 140)))
        ..drawRect(square, Paint()..color = const Color(0xFF00FF00))
        ..restore();
      final image = recorder.endRecording().toImageSync(100, 100);
      final bytes = (await image.toByteData())!;
      image.dispose();
      int alphaAt(int x, int y) => bytes.getUint8((y * 100 + x) * 4 + 3);

      expect(alphaAt(9, 9), lessThan(200));
      expect(alphaAt(30, 30), 0);
    },
  );
}
