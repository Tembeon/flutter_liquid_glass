import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';

void main() {
  test('a backdrop filter no copy can replay asks for the backdrop alone, '
      'scaled or turned', () {
    for (final (place, toScreen) in [
      (const Scaled(2, 2), Matrix4.diagonal3Values(2, 2, 1)),
      (const Turned(), Matrix4.rotationZ(0.3)),
    ]) {
      final ask = backdropFilterAsk(
        clip: const Rect.fromLTWH(0, 0, 100, 40),
        place: place,
        toScreen: () => toScreen,
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        devicePixelRatio: 3,
        blendMode: BlendMode.srcOver,
        sigma: 4,
      );
      expect(ask.backdropOnly, isTrue, reason: '$place');
    }
    final shifted = backdropFilterAsk(
      clip: const Rect.fromLTWH(0, 0, 100, 40),
      place: const Shifted(Offset(10, 20)),
      toScreen: Matrix4.identity,
      filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      devicePixelRatio: 3,
      blendMode: BlendMode.srcOver,
      sigma: 4,
    );
    expect(shifted.backdropOnly, isFalse);
  });
}
