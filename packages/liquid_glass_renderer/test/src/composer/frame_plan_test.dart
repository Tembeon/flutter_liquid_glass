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

void main() {
  setUp(() {
    BackdropUnderlay.debugEnabledOverride = true;
  });

  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
  });

  testWidgets('joins three disjoint buttons on a real frame', (tester) async {
    if (skipProperGlassTests) return;
    var sites = 0;
    var reads = 0;
    GlassComposer.debugOnPlan = (form, plan) {
      sites = form.sites.length;
      reads = plan.reads.length;
    };
    addTearDown(() => GlassComposer.debugOnPlan = null);
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
    expect(sites, greaterThanOrEqualTo(3));
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass rests until something around it changes', (tester) async {
    if (skipProperGlassTests) return;
    final beside = ValueNotifier<int>(0);
    final glassAt = ValueNotifier<double>(10);
    addTearDown(beside.dispose);
    addTearDown(glassAt.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: glassAt,
              builder: (_, left, _) => _button(left, 10),
            ),
            Positioned(
              left: 10,
              top: 100,
              width: 40,
              height: 40,
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: beside,
                  builder: (_, value, _) => ColoredBox(
                    color: Color(0xFF000000 + value),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    Future<int> restsOfAFrame() async {
      GlassComposer.debugRests = 0;
      tester.binding.scheduleFrame();
      await tester.pump();
      return GlassComposer.debugRests;
    }

    await restsOfAFrame();
    expect(await restsOfAFrame(), 1, reason: 'an empty frame');
    beside.value = 1;
    expect(await restsOfAFrame(), 1, reason: 'a repaint beside it');
    glassAt.value = 30;
    expect(await restsOfAFrame(), 0, reason: 'it moved');
  });

  testWidgets('a scan walks only what the copies can reach', (tester) async {
    if (skipProperGlassTests) return;
    Future<int> entries() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              for (var i = 0; i < 40; i++)
                Positioned(
                  left: 0,
                  top: 200.0 + i * 10,
                  width: 100,
                  height: 10,
                  child: const RepaintBoundary(
                    child: ColoredBox(color: Color(0xFF102030)),
                  ),
                ),
              _button(10, 10),
            ],
          ),
        ),
      );
      UnderlayFrame.debugEntries = 0;
      tester.binding.scheduleFrame();
      await tester.pump();
      return UnderlayFrame.debugEntries;
    }

    final pruned = await entries();
    UnderlayFrame.debugPrunes = false;
    addTearDown(() => UnderlayFrame.debugPrunes = true);
    final full = await entries();
    expect(full, greaterThan(40));
    expect(pruned, lessThan(full - 39));
  });

  testWidgets('sees no sites once the glass is gone', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [_button(10, 10)]),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
