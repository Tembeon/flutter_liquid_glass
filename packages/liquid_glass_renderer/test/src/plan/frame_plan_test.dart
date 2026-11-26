@Tags(['composer'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_frames.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:material_ui/material_ui.dart';

import '../plan_watch.dart';
import '../shared.dart';

Widget _page(List<Widget> over) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(
    children: [
      const ColoredBox(color: Color(0xFF204060), child: SizedBox.expand()),
      ...over,
    ],
  ),
);

Widget _faded(double opacity, Widget button) => Positioned.fill(
  child: Opacity(
    opacity: opacity,
    child: Stack(children: [button]),
  ),
);

Widget _button(double left, double top) => Positioned(
  left: left,
  top: top,
  width: 80,
  height: 40,
  child: const LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27Regular(),
    child: LiquidGlass(
      shape: LiquidRoundedSuperellipse(radius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

void main() {
  setUp(() {
    glassReadsCopies = true;
  });

  tearDown(() {
    glassReadsCopies = false;
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
      GlassFrames.debugRests = 0;
      tester.binding.scheduleFrame();
      await tester.pump();
      return GlassFrames.debugRests;
    }

    await restsOfAFrame();
    expect(await restsOfAFrame(), 1, reason: 'an empty frame');
    beside.value = 1;
    expect(await restsOfAFrame(), 1, reason: 'a repaint beside it');
    glassAt.value = 30;
    expect(await restsOfAFrame(), 0, reason: 'it moved');
  });

  group('a plan kept over a scroll', () {
    testWidgets('goes when shared glass starts to fade', (tester) async {
      if (skipProperGlassTests) return;
      final watch = PlanWatch();
      await tester.pumpWidget(
        _page([_faded(1, _button(10, 10)), _faded(1, _button(10, 80))]),
      );
      await tester.pump();
      expect(watch.last!.fates[1], isA<FollowFate>());
      await tester.pumpWidget(
        _page([_faded(1, _button(10, 10)), _faded(0.5, _button(10, 80))]),
      );
      final fate = watch.last!.fates[1];
      expect(fate, isA<LeadFate>());
      expect((fate as LeadFate).read.source, isNot(isA<SceneRead>()));
    });

    testWidgets('goes when content comes between shared glass', (tester) async {
      if (skipProperGlassTests) return;
      final watch = PlanWatch();
      Widget page(double boxLeft) => _page([
        _button(10, 10),
        Positioned(
          left: boxLeft,
          top: 80,
          width: 80,
          height: 40,
          child: const RepaintBoundary(
            child: ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
        _button(10, 80),
      ]);
      await tester.pumpWidget(page(300));
      await tester.pump();
      expect(watch.last!.fates[1], isA<FollowFate>());
      await tester.pumpWidget(page(10));
      expect(watch.last!.fates[1], isA<LeadFate>());
    });
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
