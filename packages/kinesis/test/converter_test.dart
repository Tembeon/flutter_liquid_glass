import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

void main() {
  test('EdgeInsets, BorderRadius, and Alignment converters round-trip and '
      'interpolate', () {
    final insets = MotionValue<EdgeInsets>(EdgeInsets.zero);
    insets.animate(
      0,
      const EdgeInsets.fromLTRB(10, 20, 30, 40),
      animation: const TimingCurve.linear(duration: 1),
    );
    expect(insets.valueAt(0.5), const EdgeInsets.fromLTRB(5, 10, 15, 20));

    final radii = MotionValue<BorderRadius>(BorderRadius.zero);
    radii.animate(
      0,
      const BorderRadius.all(Radius.circular(20)),
      animation: const TimingCurve.linear(duration: 1),
    );
    expect(radii.valueAt(0.5), const BorderRadius.all(Radius.circular(10)));

    final align = MotionValue<Alignment>(Alignment.topLeft);
    align.animate(
      0,
      Alignment.bottomRight,
      animation: const TimingCurve.linear(duration: 1),
    );
    expect(align.valueAt(0.5), Alignment.center);
  });

  test(
    'TextStyleMotionConverter interpolates metrics, color, and FontVariation '
    'axes while preserving base properties',
    () {
      const base = TextStyle(
        fontFamily: 'SFPro',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: Color(0xFF000000),
        decoration: TextDecoration.underline,
        fontVariations: [FontVariation('wght', 400), FontVariation('GRAD', 0)],
      );
      const target = TextStyle(
        fontFamily: 'SFPro',
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: Color(0xFFFFFFFF),
        decoration: TextDecoration.underline,
        fontVariations: [
          FontVariation('wght', 800),
          FontVariation('GRAD', 100),
        ],
      );
      final style = MotionValue<TextStyle>(
        base,
        converter: const TextStyleMotionConverter(
          base,
          variationAxes: ['wght', 'GRAD'],
        ),
      );
      style.animate(
        0,
        target,
        animation: const TimingCurve.linear(duration: 1),
      );
      final mid = style.valueAt(0.5);
      expect(mid.fontFamily, 'SFPro');
      expect(mid.decoration, TextDecoration.underline);
      expect(mid.fontSize, closeTo(24, 1e-6));
      expect(mid.fontWeight, FontWeight.w600);
      expect(mid.letterSpacing, closeTo(1, 1e-6));
      expect(mid.color!.r, closeTo(0.5, 1e-2));
      expect(
        mid.fontVariations,
        containsAll([
          const FontVariation('wght', 600),
          const FontVariation('GRAD', 50),
        ]),
      );
    },
  );

  test('a TextStyle reads back every metric it wrote in its own place', () {
    const style = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      wordSpacing: 3,
      height: 1.25,
      decorationThickness: 2,
      color: Color.from(alpha: 0.75, red: 0.2, green: 0.4, blue: 0.6),
    );
    const converter = TextStyleMotionConverter(TextStyle());
    final slots = List<double>.filled(converter.dimensions, 0);
    converter.write(style, slots);
    expect(converter.read(slots), style);
  });

  test('a TextStyle keeps the fields neither it nor the base sets unset', () {
    final style = MotionValue<TextStyle>(const TextStyle(fontSize: 14));
    final value = style.valueAt(0);
    expect(value.fontSize, 14);
    expect(value.color, isNull);
    expect(value.fontWeight, isNull);
    expect(value.letterSpacing, isNull);
    expect(value.height, isNull);
  });

  test('a TextStyle field set on one side takes its own value halfway', () {
    final style = MotionValue<TextStyle>(const TextStyle(fontSize: 14))
      ..animate(
        0,
        const TextStyle(fontSize: 18, height: 1.2),
        animation: const TimingCurve.linear(duration: 1),
      );
    expect(style.valueAt(0.25).height, isNull);
    expect(style.valueAt(0.25).fontSize, closeTo(15, 1e-9));
    expect(style.valueAt(0.75).height, closeTo(1.2, 1e-9));
    expect(style.valueAt(1).height, closeTo(1.2, 1e-9));
  });
}
