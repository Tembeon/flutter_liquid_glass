import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';

void main() {
  test('an image blurred by up to 14 of its copy pixels is blurred by an '
      'image filter', () {
    ReadLayout layout(double? blur, {required int share}) => ReadLayout.resolve(
      devicePixelRatio: 3,
      askedShare: share,
      atScreen: false,
      reads: const Rect.fromLTWH(40, 60, 120, 80),
      screen: const Rect.fromLTWH(0, 0, 300, 400),
      clip: null,
      nestsGlass: false,
      shaderFrost: 0,
      frostLeftOut: 0,
      filter: null,
      imageBlur: blur,
    );

    expect(layout(null, share: 2).imageFilterBlurs, isFalse);
    expect(layout(0, share: 2).imageFilterBlurs, isTrue);
    expect(layout(9.3, share: 2).imageFilterBlurs, isTrue);
    expect(layout(9.4, share: 2).imageFilterBlurs, isFalse);
    expect(layout(8, share: 2).imageFilterBlurs, isTrue);
    expect(layout(8, share: 1).imageFilterBlurs, isFalse);
  });
}
