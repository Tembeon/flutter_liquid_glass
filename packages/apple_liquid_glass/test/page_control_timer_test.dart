import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stories extends StatefulWidget {
  const _Stories({
    required this.timer,
    required this.picks,
    this.page = 0,
    super.key,
  });

  final GlassPageControlTimer timer;
  final List<int> picks;
  final int page;

  @override
  State<_Stories> createState() => _StoriesState();
}

class _StoriesState extends State<_Stories> {
  late int page = widget.page;
  double? shown;

  void show(int next) => setState(() => page = next);

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: GlassPageControl(
          count: 4,
          page: page,
          timer: widget.timer,
          style: GlassPageControlStyle(
            builder: (context, details) {
              shown = details.progress;
              return const SizedBox.expand();
            },
          ),
          onChanged: (next) {
            widget.picks.add(next);
            setState(() => page = next);
          },
        ),
      ),
    ),
  );
}

Future<void> _run(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds - 1e-9; t += 0.016) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

GlassPageControlTimer _timer(
  WidgetTester tester, {
  bool resets = false,
  bool Function(int page)? shouldAdvanceToPage,
}) {
  final timer = GlassPageControlTimer(
    duration: const Duration(milliseconds: 1500),
    resetsToInitialPageAfterEnd: resets,
    shouldAdvanceToPage: shouldAdvanceToPage,
  );
  addTearDown(timer.dispose);
  return timer;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a timer starts paused; running, it fills the current page '
      'over its duration and turns to the next, which starts empty', (
    tester,
  ) async {
    final timer = _timer(tester);
    final picks = <int>[];
    var heard = 0;
    timer.addListener(() => heard++);
    await tester.pumpWidget(_Stories(timer: timer, picks: picks));
    final state = tester.state<_StoriesState>(find.byType(_Stories));
    expect(timer.isRunning, isFalse);
    expect(state.shown, 0);
    await _run(tester, 0.5);
    expect(timer.progress, 0);
    timer.resume();
    await _run(tester, 0.75);
    expect(timer.progress, moreOrLessEquals(0.5, epsilon: 0.03));
    expect(state.shown, moreOrLessEquals(timer.progress, epsilon: 0.02));
    await _run(tester, 0.8);
    expect(picks, [1]);
    expect(timer.progress, lessThan(0.1));
    expect(heard, 1);
    timer.pause();
    final held = timer.progress;
    await _run(tester, 1);
    expect(timer.progress, held);
    expect(heard, 2);
  });

  testWidgets('past the last page it stops full, or goes on from the first '
      'with resetsToInitialPageAfterEnd', (tester) async {
    for (final resets in [false, true]) {
      MotionClock.debugReset();
      final timer = _timer(tester, resets: resets);
      final picks = <int>[];
      await tester.pumpWidget(
        _Stories(key: ValueKey(resets), timer: timer, picks: picks, page: 3),
      );
      timer.resume();
      await _run(tester, 1.6);
      if (resets) {
        expect(picks, [0]);
        expect(timer.isRunning, isTrue);
      } else {
        expect(picks, isEmpty);
        expect(timer.isRunning, isFalse);
        expect(timer.progress, 1);
      }
    }
  });

  testWidgets('a refused page stops the timer full; resuming asks again', (
    tester,
  ) async {
    var refuse = true;
    final asked = <int>[];
    final timer = _timer(
      tester,
      shouldAdvanceToPage: (page) {
        asked.add(page);
        return !refuse;
      },
    );
    final picks = <int>[];
    await tester.pumpWidget(_Stories(timer: timer, picks: picks));
    timer.resume();
    await _run(tester, 1.6);
    expect(asked, [1]);
    expect(picks, isEmpty);
    expect(timer.isRunning, isFalse);
    refuse = false;
    timer.resume();
    await _run(tester, 0.1);
    expect(asked, [1, 1]);
    expect(picks, [1]);
  });

  testWidgets('a duration changed while a page runs takes the next page', (
    tester,
  ) async {
    final timer = _timer(tester);
    final picks = <int>[];
    await tester.pumpWidget(_Stories(timer: timer, picks: picks));
    timer.resume();
    await _run(tester, 0.5);
    timer.duration = const Duration(milliseconds: 750);
    await _run(tester, 0.9);
    expect(picks, isEmpty);
    await _run(tester, 0.2);
    expect(picks, [1]);
    await _run(tester, 0.8);
    expect(picks, [1, 2]);
  });

  testWidgets('a page set from outside starts empty', (tester) async {
    final timer = _timer(tester);
    final picks = <int>[];
    await tester.pumpWidget(_Stories(timer: timer, picks: picks));
    timer.resume();
    await _run(tester, 1);
    final state = tester.state<_StoriesState>(find.byType(_Stories));
    state.show(3);
    await tester.pump();
    expect(timer.progress, lessThan(0.05));
    expect(timer.isRunning, isTrue);
  });
}
