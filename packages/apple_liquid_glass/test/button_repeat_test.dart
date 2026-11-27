import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required VoidCallback onPressed, required bool repeats}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => GlassScope(
        renderer: const FlatGlassRenderer(),
        child: Center(
          child: GlassButton(
            onPressed: onPressed,
            repeats: repeats,
            child: const Text('More'),
          ),
        ),
      ),
    );

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a held button with repeats presses 0.5 s after the touch and '
      'every 0.5 s after, and its release presses nothing more', (
    tester,
  ) async {
    final times = <Duration>[];
    final start = tester.binding.clock.now();
    await tester.pumpWidget(
      _app(
        onPressed: () =>
            times.add(tester.binding.clock.now().difference(start)),
        repeats: true,
      ),
    );
    final down = tester.binding.clock.now().difference(start);
    final finger = await tester.startGesture(
      tester.getCenter(find.text('More')),
    );
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final seconds = [
      for (final t in times) (t - down).inMicroseconds / 1e6,
    ];
    expect(seconds.length, 5);
    for (final (i, s) in seconds.indexed) {
      expect(s, moreOrLessEquals(0.5 * (i + 1), epsilon: 0.02));
    }
  });

  testWidgets('without repeats a held button presses once, at its release', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(_app(onPressed: () => presses++, repeats: false));
    final finger = await tester.startGesture(
      tester.getCenter(find.text('More')),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(presses, 0);
    await finger.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(presses, 1);
  });

  testWidgets('a subtitle stands 1 point under the title in 13 point type, '
      "inside the medium button's 7 point insets (51 tall with UIKit's "
      'label heights, button passport)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => GlassScope(
          renderer: const FlatGlassRenderer(),
          child: Center(
            child: GlassButton.filled(
              onPressed: () {},
              subtitle: const Text('Sub'),
              child: const Text('Title'),
            ),
          ),
        ),
      ),
    );
    final title = tester.getRect(find.text('Title'));
    final subtitle = tester.getRect(find.text('Sub'));
    expect(subtitle.top - title.bottom, moreOrLessEquals(1, epsilon: 0.5));
    expect(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.text('Sub'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.fontSize,
      13,
    );
    expect(
      tester.getSize(find.byType(GlassButton)).height,
      moreOrLessEquals(
        7 + title.height + 1 + subtitle.height + 7,
        epsilon: 0.5,
      ),
    );
  });
}
