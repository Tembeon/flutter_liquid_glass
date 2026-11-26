@Tags(['composer'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _dpr = 3.0;

Future<SiteAsk> _askOf(
  WidgetTester tester,
  LiquidGlassSettings settings,
) async {
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: LiquidGlassLayer(
        settings: settings,
        child: const Center(
          child: SizedBox(
            width: 160,
            height: 80,
            child: LiquidGlass(
              shape: LiquidRoundedSuperellipse(radius: 20),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  await tester.pump();
  return tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet()
      .single
      .ask(const ViewPixels(_dpr));
}

double _farther(SiteAsk frosted, SiteAsk clear) =>
    clear.reads.left - frosted.reads.left;

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() => glassReadsCopies = false);

  testWidgets(
    'glass that blurs its copy from levels reads as far past clear glass as '
    'its blur reaches',
    (tester) async {
      final clear = await _askOf(
        tester,
        const LiquidGlassSettings(blur: 0),
      );
      final frosted = await _askOf(
        tester,
        const LiquidGlassSettings(blur: 3),
      );
      final need = frosted.look.need;

      expect(
        need.levels?.most,
        closeTo(3 * ImpellerBlur.deliveredFraction, 1e-9),
      );
      expect(_farther(frosted, clear), closeTo(need.reachAt(_dpr), 1e-9));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    "glass Impeller frosts reads as far past clear glass as Impeller's "
    'blur reaches',
    (tester) async {
      final clear = await _askOf(
        tester,
        const LiquidGlassSettings(
          blur: 0,
          lens: LensSettings(dispersion: 0.3),
        ),
      );
      final frosted = await _askOf(
        tester,
        const LiquidGlassSettings(
          blur: 12,
          lens: LensSettings(dispersion: 0.3),
        ),
      );

      expect(frosted.look.need.levels, isNull);
      expect(
        _farther(frosted, clear),
        closeTo(ImpellerBlur.reach(12, _dpr), 1e-9),
      );
    },
    skip: skipProperGlassTests,
  );
}
