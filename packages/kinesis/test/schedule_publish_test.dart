import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/clock.dart';

class _Stepped implements MotionFollowed {
  _Stepped([this.onStep]);

  final void Function(double time)? onStep;
  final List<double> steps = [];

  @override
  bool stepTo(double time) {
    steps.add(time);
    onStep?.call(time);
    return true;
  }

  @override
  double? get wakeTime => null;

  @override
  void publish({required bool widgets}) {}

  @override
  bool get hasWidgetFollowers => false;
}

void main() {
  setUp(MotionClock.debugReset);
  tearDown(MotionClock.debugReset);

  test('a publish callback runs once, after the values stepped', () {
    final clock = ManualMotionClock();
    final driver = _Stepped();
    clock.follow(driver);
    final seen = <List<double>>[];
    clock.schedulePublish(() => seen.add(List.of(driver.steps)));
    clock.advanceTo(0.1);
    clock.advanceTo(0.2);
    expect(seen, [
      [0.1],
    ]);
  });

  test('a publish callback scheduled while publishing runs in that phase', () {
    final clock = ManualMotionClock();
    final heard = <String>[];
    void second() => heard.add('second');
    clock.schedulePublish(() {
      heard.add('first');
      clock.schedulePublish(second);
    });
    clock.advanceTo(0.1);
    expect(heard, ['first', 'second']);
  });

  test('a value commanded while publishing is drawn in that frame', () {
    final clock = ManualMotionClock();
    final title = MotionValue<double>(0, clock: clock);
    final heard = <double>[];
    void listener() => heard.add(title.value);
    title.addListener(listener);
    addTearDown(() => title.removeListener(listener));
    clock.schedulePublish(() => title.snap(clock.now, 1));
    clock.advanceTo(0.1);
    expect(heard, [1]);
  });

  test('a value a step commands is heard in that frame', () {
    final clock = ManualMotionClock();
    final value = MotionValue<double>(0, clock: clock);
    final heard = <double>[];
    void listener() => heard.add(value.value);
    value.addRenderListener(listener);
    addTearDown(() => value.removeRenderListener(listener));
    clock.follow(_Stepped((t) => value.snap(t, t)));
    clock.advanceTo(0.1);
    expect(heard, [0.1]);
  });

  test('a value a listener commands while values publish is heard in that '
      'frame', () {
    final clock = ManualMotionClock();
    final scroll = MotionValue<double>(0, clock: clock);
    final title = MotionValue<double>(0, clock: clock);
    final heard = <double>[];
    void follow() => title.snap(clock.now, scroll.value);
    void listener() => heard.add(title.value);
    scroll.addListener(follow);
    title.addListener(listener);
    addTearDown(() {
      scroll.removeListener(follow);
      title.removeListener(listener);
    });
    scroll.animate(0, 100, animation: const TimingCurve.linear(duration: 1));
    clock.advanceTo(0.1);
    expect(heard, [closeTo(10, 1e-9)]);
  });

  test('a value commanded before its turn in the frame is heard once', () {
    final clock = ManualMotionClock();
    final first = MotionValue<double>(0, clock: clock);
    final second = MotionValue<double>(0, clock: clock);
    final heard = <double>[];
    void command() => second.snap(clock.now, 50);
    void listener() => heard.add(second.value);
    first.addListener(command);
    second.addListener(listener);
    addTearDown(() {
      first.removeListener(command);
      second.removeListener(listener);
    });
    first.animate(0, 100, animation: const TimingCurve.linear(duration: 1));
    second.animate(0, 100, animation: const TimingCurve.linear(duration: 1));
    clock.advanceTo(0.1);
    expect(heard, [50]);
  });

  test('values that keep commanding each other are reported, and finish in '
      'the next frame', () {
    final clock = ManualMotionClock();
    final a = MotionValue<double>(0, clock: clock);
    final b = MotionValue<double>(0, clock: clock);
    void toB() => b.snap(clock.now, a.value + 1);
    void toA() => a.snap(clock.now, b.value + 1);
    a.addListener(toB);
    b.addListener(toA);
    addTearDown(() {
      a.removeListener(toB);
      b.removeListener(toA);
    });
    final errors = <FlutterErrorDetails>[];
    final reportError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = reportError);
    a.snap(0, 1);
    clock.advanceTo(0.1);
    expect(errors, hasLength(1));
    final reached = a.value;
    clock.advanceTo(0.2);
    expect(errors, hasLength(2));
    expect(a.value, greaterThan(reached));
  });

  test('a cancelled publish callback never runs', () {
    final clock = ManualMotionClock();
    var runs = 0;
    final cancel = clock.schedulePublish(() => runs++);
    cancel();
    clock.advanceTo(0.1);
    expect(runs, 0);
  });

  testWidgets('a publish callback a ticker asks for runs in its frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var runs = 0;
    var ticks = 0;
    final ticker = const TestVSync().createTicker((_) {
      ticks++;
      MotionClock.instance.schedulePublish(() => runs++);
    });
    addTearDown(ticker.dispose);
    unawaited(ticker.start());
    for (var i = 1; i <= 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(runs, ticks);
    }
    ticker.stop();
  });

  testWidgets('a publish callback asked for after the phases of a frame '
      'ran still runs in that frame', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final driver = _Stepped();
    MotionClock.instance.follow(driver);
    await tester.pump(const Duration(milliseconds: 16));
    final stepsBefore = driver.steps.length;
    var runs = 0;
    tester.binding.scheduleFrameCallback((_) {
      scheduleMicrotask(
        () => MotionClock.instance.schedulePublish(() => runs++),
      );
    });
    await tester.pump(const Duration(milliseconds: 16));
    expect(runs, 1);
    expect(driver.steps.length, stepsBefore + 2);
    expect(driver.steps.last, driver.steps[driver.steps.length - 2]);
    MotionClock.instance.unfollow(driver);
  });

  testWidgets('a publish callback outside a frame asks for one frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.hasScheduledFrame, isFalse);
    var runs = 0;
    MotionClock.instance.schedulePublish(() => runs++);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(runs, 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
