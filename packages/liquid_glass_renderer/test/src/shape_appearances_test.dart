import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';

const _clear = WornAppearance.plain;
const _red = WornAppearance(
  tint: Color(0x40FF0000),
  visibility: 1,
  colorModel: WornColorModel.direct(brightness: Brightness.light),
);
const _faded = WornAppearance(
  tint: Color(0x00000000),
  visibility: 0.5,
  colorModel: WornColorModel.direct(brightness: Brightness.light),
);
const _fallback = WornAppearance(
  tint: Color(0x2000FF00),
  visibility: 1,
  colorModel: WornColorModel.direct(
    brightness: Brightness.light,
    saturation: 1.5,
  ),
);

void main() {
  test(
    "a layer's appearances are one, differ by tint, or differ otherwise",
    () {
      final none = ShapeAppearances.of(const [], _fallback);
      expect(none, isA<OneAppearance>());
      expect(none.face, _fallback);
      expect(none.shaded, [_fallback]);
      expect(none.kind, FinalShaderKind.single);

      final one = ShapeAppearances.of(const [_red, _red], _fallback);
      expect(one, isA<OneAppearance>());
      expect(one.face, _red);
      expect(one.shaded, [_red]);

      final tinted = ShapeAppearances.of(const [_clear, _red], _fallback);
      expect(tinted, isA<TintedAppearances>());
      expect(tinted.face, _clear);
      expect(tinted.shaded, [_clear, _red]);
      expect(tinted.kind, FinalShaderKind.tint);

      final mixed = ShapeAppearances.of(const [_clear, _faded], _fallback);
      expect(mixed, isA<MixedAppearances>());
      expect(mixed.face, _fallback);
      expect(mixed.shaded, [_clear, _faded]);
      expect(mixed.kind, FinalShaderKind.material);
    },
  );

  test('appearances are equal while their kind, face and shapes are', () {
    expect(
      ShapeAppearances.of(const [_clear, _red], _fallback),
      ShapeAppearances.of(const [_clear, _red], _fallback),
    );
    expect(
      ShapeAppearances.of(const [_clear, _red], _fallback),
      isNot(ShapeAppearances.of(const [_red, _clear], _fallback)),
    );
    expect(
      ShapeAppearances.of(const [_red], _fallback),
      isNot(ShapeAppearances.of(const [_red, _red], _fallback)),
    );
  });
}
