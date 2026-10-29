import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _list(
  MotionScrollObserver observer, {
  ScrollController? controller,
  int count = 50,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: NotificationListener<Notification>(
    onNotification: observer.handle,
    child: ListView(
      controller: controller,
      children: [
        for (var i = 0; i < count; i++) SizedBox(height: 50, child: Text('$i')),
      ],
    ),
  ),
);

void main() {
  testWidgets('a drag reads as dragging, its fling as decelerating, then '
      'idle', (tester) async {
    final observer = MotionScrollObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(_list(observer));
    await tester.pump();
    expect(observer.phase, MotionScrollPhase.idle);
    expect(observer.metrics!.pixels, 0);
    final phases = <MotionScrollPhase>[];
    observer.addListener(() {
      if (phases.isEmpty || phases.last != observer.phase) {
        phases.add(observer.phase);
      }
    });
    await tester.fling(find.byType(ListView), const Offset(0, -200), 2000);
    await tester.pumpAndSettle();
    expect(phases, [
      MotionScrollPhase.dragging,
      MotionScrollPhase.decelerating,
      MotionScrollPhase.idle,
    ]);
    expect(observer.metrics!.pixels, greaterThan(200));
    expect(observer.metrics!.hasContentDimensions, isTrue);
  });

  testWidgets('a drag released without a fling goes idle', (tester) async {
    final observer = MotionScrollObserver();
    addTearDown(observer.dispose);
    await tester.pumpWidget(_list(observer));
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(observer.phase, MotionScrollPhase.dragging);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(observer.phase, MotionScrollPhase.idle);
  });

  testWidgets('the app moving the content reads as programmatic', (
    tester,
  ) async {
    final observer = MotionScrollObserver();
    final controller = ScrollController();
    addTearDown(observer.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_list(observer, controller: controller));
    controller
        .animateTo(
          300,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        )
        .ignore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(observer.phase, MotionScrollPhase.programmatic);
    await tester.pumpAndSettle();
    expect(observer.phase, MotionScrollPhase.idle);
    expect(observer.metrics!.pixels, 300);
    expect(observer.position, same(controller.position));
  });

  testWidgets('only depth 0 is heard unless the predicate says otherwise', (
    tester,
  ) async {
    final outer = MotionScrollObserver();
    final inner = MotionScrollObserver(
      predicate: (notification) => notification.depth == 1,
    );
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NotificationListener<Notification>(
          onNotification: (n) => outer.handle(n) || inner.handle(n),
          child: SingleChildScrollView(
            child: SizedBox(
              height: 300,
              child: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 50; i++) const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    var outerHeard = 0;
    outer.addListener(() => outerHeard++);
    controller.jumpTo(120);
    await tester.pump();
    expect(inner.metrics!.pixels, 120);
    expect(outerHeard, 0);
  });

  testWidgets('new content reports its extents without a scroll', (
    tester,
  ) async {
    final observer = MotionScrollObserver();
    addTearDown(observer.dispose);
    Widget page(double height) => Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<Notification>(
        onNotification: observer.handle,
        child: SingleChildScrollView(child: SizedBox(height: height)),
      ),
    );
    await tester.pumpWidget(page(1000));
    await tester.pump();
    expect(observer.metrics!.maxScrollExtent, 400);
    await tester.pumpWidget(page(1400));
    await tester.pump();
    expect(observer.metrics!.maxScrollExtent, 800);
    expect(observer.phase, MotionScrollPhase.idle);
  });
}
