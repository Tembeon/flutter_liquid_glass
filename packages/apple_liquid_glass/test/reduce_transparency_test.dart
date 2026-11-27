import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass_shown.dart';

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: GlassScope(
    renderer: const LiquidGlassRenderer(),
    child: GlassTraitsOverride(
      reduceTransparency: true,
      child: Center(child: child),
    ),
  ),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('under Reduce Transparency glass is drawn as iOS 27 draws it '
      'for the setting', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassSurface.live(
          frame: MotionSelection(() => const GlassFrame()),
          child: const SizedBox(width: 120, height: 44),
        ),
      ),
    );
    final glass = findShown(LiquidGlass);
    expect(glass, findsOneWidget);
    expect(
      LiquidGlassLayer.settingsOf(tester.element(glass)).reduceTransparency,
      isTrue,
    );
  });

  testWidgets('under Reduce Transparency a lifted lens stays flat: it is '
      'not measured there', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassSurface.live(
          role: GlassRole.lens,
          frame: MotionSelection(() => const GlassFrame(lift: 1)),
          child: const SizedBox(width: 110, height: 44),
        ),
      ),
    );
    expect(findShown(LiquidGlass), findsNothing);
  });
}
