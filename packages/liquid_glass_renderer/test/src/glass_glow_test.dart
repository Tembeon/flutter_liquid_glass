import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/effects/glass_glow.dart';

void main() {
  group('$GlassGlow', () {
    setUp(() {});

    const childKey = Key('child');
    const buttonKey = Key('button');

    group('gesture modes', () {
      testWidgets('listener mode responds to all pointer events', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: GlassGlowLayer(
              child: GlassGlow(
                child: Container(
                  key: childKey,
                  width: 100,
                  height: 100,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );

        final childFinder = find.byKey(childKey);
        expect(childFinder, findsOneWidget);

        // Tap on the child - should trigger glow effect
        await tester.tap(childFinder);
        await tester.pumpAndSettle();

        // The test passes if no exceptions are thrown
      });

      testWidgets('gestureDetector mode allows nested button to work', (
        tester,
      ) async {
        var buttonPressedCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: GlassGlowLayer(
              child: GlassGlow(
                gestureMode: GestureMode.gestureDetector,
                child: ElevatedButton(
                  key: buttonKey,
                  onPressed: () => buttonPressedCount++,
                  child: const Text('Press me'),
                ),
              ),
            ),
          ),
        );

        final buttonFinder = find.byKey(buttonKey);
        expect(buttonFinder, findsOneWidget);

        // Tap the button - should trigger button press, not glow effect
        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        expect(buttonPressedCount, 1);
      });

      testWidgets(
        'gestureDetector: no glow until pan wins over nested button',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: GlassGlowLayer(
                child: GlassGlow(
                  gestureMode: GestureMode.gestureDetector,
                  child: ElevatedButton(
                    key: buttonKey,
                    onPressed: () {},
                    child: const Text('Press me'),
                  ),
                ),
              ),
            ),
          );

          double glowAlpha() => tester
              .renderObject<RenderGlassGlowLayer>(
                find.byType(GlassGlowLayer),
              )
              .glowColor
              .a;

          expect(glowAlpha(), 0);

          final center = tester.getCenter(find.byKey(buttonKey));
          final gesture = await tester.startGesture(center);
          await tester.pump(const Duration(milliseconds: 100));
          expect(glowAlpha(), 0);

          await gesture.up();
          await tester.pumpAndSettle();
          expect(glowAlpha(), 0);
        },
      );

      testWidgets('gestureDetector mode with drag', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: GlassGlowLayer(
              child: GlassGlow(
                gestureMode: GestureMode.gestureDetector,
                child: Container(
                  key: childKey,
                  width: 100,
                  height: 100,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );

        final childFinder = find.byKey(childKey);
        expect(childFinder, findsOneWidget);

        // Drag on the child - should trigger glow effect
        final gesture = await tester.startGesture(
          tester.getCenter(childFinder),
        );
        await gesture.moveBy(const Offset(50, 0));
        await tester.pumpAndSettle();
        await gesture.up();

        // The test passes if no exceptions are thrown
      });
    });
  });
}
