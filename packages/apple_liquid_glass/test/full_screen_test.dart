import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

Widget _app({required ValueChanged<Object?> onResult}) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => GlassScope(
    renderer: const FlatGlassRenderer(),
    child: Navigator(
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (context, _, _) => Center(
          child: _Below(
            onTap: () => unawaited(
              showGlassFullScreen<String>(
                context,
                semanticLabel: 'Player',
                builder: (context) => const Center(child: Text('cover')),
              ).then(onResult),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _Below extends StatelessWidget {
  const _Below({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      GlassButton(onPressed: onTap, child: const Text('below'));
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the page slides up on the critically damped spring of '
      'response 0.344, the page below stops showing once covered, and a pop '
      'slides it down with the result', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Object? result = 'none';
    await tester.pumpWidget(_app(onResult: (value) => result = value));
    await tester.tap(find.text('below'));
    await tester.pump();
    double top() => tester
        .getTopLeft(
          find
              .ancestor(
                of: find.text('cover'),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .dy;
    final start = tester.binding.clock.now();
    await _frames(tester, 7);
    final t = tester.binding.clock.now().difference(start).inMicroseconds / 1e6;
    const omega = 2 * math.pi / 0.344;
    final expected = 874 * (1 + omega * t) * math.exp(-omega * t);
    expect(top(), moreOrLessEquals(expected, epsilon: 0.5));
    expect(find.text('below'), findsOneWidget);
    await _frames(tester, 60);
    expect(top(), moreOrLessEquals(0, epsilon: 0.1));
    expect(find.text('below'), findsNothing);
    expect(find.bySemanticsLabel('Player'), findsOneWidget);
    Navigator.of(tester.element(find.text('cover'))).pop('done');
    await _frames(tester, 2);
    expect(find.text('below'), findsOneWidget);
    expect(top(), greaterThan(0));
    await _frames(tester, 60);
    expect(find.text('cover'), findsNothing);
    expect(result, 'done');
  });

  testWidgets('over a glass page its bar stays put and shown while the '
      'page slides up and down, and a swipe from the edge does not close '
      'it', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: 62, bottom: 34)),
          child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        ),
        home: Builder(
          builder: (context) => GlassPageScaffold(
            navigationBar: GlassNavigationBar(
              title: const Text('Library'),
              trailing: [
                GlassBarItem(
                  icon: const SizedBox(key: Key('open'), width: 22, height: 22),
                  semanticLabel: 'Open',
                  onPressed: () => unawaited(
                    showGlassFullScreen<void>(
                      context,
                      builder: (context) => const Center(child: Text('cover')),
                    ),
                  ),
                ),
              ],
            ),
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
    await _frames(tester, 2);
    final title = tester.getRect(find.text('Library'));
    final item = tester.getRect(find.byKey(const Key('open')));
    await tester.tapAt(item.center);
    for (var i = 0; i < 20; i++) {
      await tester.pump(_frame);
      expect(tester.getRect(find.text('Library')), title);
      expect(tester.getRect(find.byKey(const Key('open'))), item);
    }
    await _frames(tester, 60);
    expect(find.text('cover'), findsOneWidget);
    final edge = await tester.startGesture(const Offset(2, 400));
    for (var x = 10.0; x <= 300; x += 10) {
      await edge.moveTo(Offset(x, 400));
      await tester.pump(_frame);
    }
    await edge.up();
    await _frames(tester, 60);
    expect(find.text('cover'), findsOneWidget);
    Navigator.of(tester.element(find.text('cover'))).pop();
    await _frames(tester, 2);
    for (var i = 0; i < 20; i++) {
      await tester.pump(_frame);
      expect(tester.getRect(find.text('Library')), title);
    }
    await _frames(tester, 60);
    expect(find.text('cover'), findsNothing);
  });
}
