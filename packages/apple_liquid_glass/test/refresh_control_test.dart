import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(GlassRefreshCallback onRefresh) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          GlassSliverRefreshControl(onRefresh: onRefresh),
          SliverList.builder(
            itemCount: 40,
            itemBuilder: (context, i) =>
                SizedBox(key: ValueKey(i), height: 44, child: Text('Row $i')),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

double _top(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey(0))).dy;

Future<void> _settle(WidgetTester tester, [int frames = 90]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<TestGesture> _pull(WidgetTester tester, double by) async {
  final gesture = await tester.startGesture(const Offset(201, 300));
  for (var moved = 0.0; moved < by; moved += 20) {
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the content starts under the top inset', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(() async {}));
    expect(_top(tester), 62);
  });

  testWidgets('a short pull springs back without a refresh', (tester) async {
    await _phone(tester);
    var refreshes = 0;
    await tester.pumpWidget(_app(() async => refreshes++));
    expect(find.byType(GlassSliverRefreshControl), isNot(paints..rrect()));
    final gesture = await _pull(tester, 160);
    expect(_top(tester), greaterThan(62));
    expect(
      find.byType(GlassSliverRefreshControl),
      paints..rrect(),
      reason: 'the ticks come in with the pull',
    );
    await gesture.up();
    await _settle(tester);
    expect(refreshes, 0);
    expect(_top(tester), 62);
  });

  testWidgets('a long pull refreshes with the finger still down, the '
      'content rests under the control, and goes back once done', (
    tester,
  ) async {
    await _phone(tester);
    final done = Completer<void>();
    var refreshes = 0;
    await tester.pumpWidget(
      _app(() {
        refreshes++;
        return done.future;
      }),
    );
    final gesture = await _pull(tester, 700);
    expect(refreshes, 1, reason: 'before the finger lifts');
    await gesture.up();
    await _settle(tester);
    expect(_top(tester), moreOrLessEquals(62 + 60, epsilon: 0.5));

    done.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 165));
    expect(_top(tester), inExclusiveRange(62, 122));
    await _settle(tester, 30);
    expect(_top(tester), 62);
    expect(refreshes, 1);
  });

  testWidgets('done while the finger still holds the pull, the control '
      "gives its height back at once and the content doesn't jump", (
    tester,
  ) async {
    await _phone(tester);
    final done = Completer<void>();
    await tester.pumpWidget(_app(() => done.future));
    final gesture = await _pull(tester, 700);
    final held = _top(tester);
    done.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_top(tester), moreOrLessEquals(held, epsilon: 0.5));
    await gesture.up();
    await _settle(tester);
    expect(_top(tester), 62);
  });
}
