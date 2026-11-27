import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';

WornAppearance _regular(Brightness brightness, double shortSide) =>
    LiquidGlassAppearance.ios27Regular(
      brightness: brightness,
    ).wear(Size(400, shortSide));

WornAppearance _clear(Brightness brightness, double shortSide) =>
    LiquidGlassAppearance.ios27Clear(
      brightness: brightness,
    ).wear(Size(400, shortSide));

// The slot, from 1, each of [glass] draws with.
List<double> _codes(List<WornAppearance> glass) {
  final slots = colorModelSlots(glass, glass.first);
  return [
    for (final appearance in glass)
      colorModelCode(appearance.colorModel, slots),
  ];
}

void main() {
  // A look includes the glass's size between 64 and 160 points, so a layer of
  // cards of four sizes wears four recipes. The final shader has three
  // slots: past them glass took the first slot's recipe, whatever it was.
  test('glass of a fourth size draws with the slot of the nearest size', () {
    final glass = [
      for (final side in [80.0, 100.0, 120.0, 140.0])
        _regular(Brightness.light, side),
    ];

    expect(overflowsColorModelSlots(glass), isTrue);
    expect(_codes(glass), [1, 2, 3, 3]);
  });

  test('a kind of glass past three sizes of another keeps a slot of its '
      'own', () {
    final glass = [
      _regular(Brightness.light, 80),
      _regular(Brightness.light, 100),
      _regular(Brightness.light, 120),
      _regular(Brightness.dark, 100),
    ];

    final codes = _codes(glass);
    expect(codes[3], isNot(codes[0]));
    expect(codes[3], isNot(codes[1]));
    expect(codes[3], isNot(codes[2]));
    expect(codes.toSet(), hasLength(3));
  });

  test('a fourth kind of glass draws with the kind of its brightness', () {
    final glass = [
      _regular(Brightness.light, 44),
      _regular(Brightness.dark, 44),
      _clear(Brightness.light, 44),
      _clear(Brightness.dark, 44),
    ];

    expect(_codes(glass), [1, 2, 3, 2]);
  });

  test('up to three looks keep their slots in order', () {
    final glass = [
      _regular(Brightness.light, 100),
      _regular(Brightness.light, 80),
      _regular(Brightness.dark, 100),
    ];

    expect(overflowsColorModelSlots(glass), isFalse);
    expect(_codes(glass), [1, 2, 3]);
  });

  test("three looks keep their slots whatever the layer's own look", () {
    final glass = [
      _regular(Brightness.light, 100),
      _regular(Brightness.light, 80),
      _regular(Brightness.dark, 100),
    ];
    final slots = colorModelSlots(glass, _clear(Brightness.dark, 44));

    expect(slots, hasLength(3));
    expect(
      [
        for (final worn in glass) colorModelCode(worn.colorModel, slots),
      ],
      [1, 2, 3],
    );
  });
}
