// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';

import '../shared.dart';

Widget _button(double left, double top) => Positioned(
  left: left,
  top: top,
  width: 80,
  height: 40,
  child: LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27RegularLight(),
    child: const LiquidGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

Map<String, String> _census() {
  final words = GlassComposer.debugShadowCensus.take().split(' ');
  return {
    for (final word in words) word.split('=').first: word.split('=').last,
  };
}

void main() {
  setUp(() {
    BackdropUnderlay.debugEnabledOverride = true;
    GlassComposer.debugShadowPlan = true;
    GlassComposer.debugShadowCensus.take();
  });

  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
    GlassComposer.debugShadowPlan = false;
  });

  testWidgets('joins three disjoint buttons on a real frame', (tester) async {
    if (skipProperGlassTests) return;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            const ColoredBox(
              color: Color(0xFF204060),
              child: SizedBox.expand(),
            ),
            _button(10, 10),
            _button(10, 80),
            _button(10, 150),
          ],
        ),
      ),
    );
    await tester.pump();
    final census = _census();
    expect(int.parse(census['frames']!), greaterThan(0));
    expect(double.parse(census['sites']!), greaterThanOrEqualTo(3));
    expect(double.parse(census['reads']!), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sees no sites once the glass is gone', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [_button(10, 10)]),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    GlassComposer.debugShadowCensus.take();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
