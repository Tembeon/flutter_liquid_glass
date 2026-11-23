import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/src/motion/changes.dart';
import 'package:kinesis/testing.dart';

void main() {
  testWidgets('MotionText animates TextStyle and FontVariation with zero '
      'widget rebuilds per frame', (tester) async {
    final clock = ManualMotionClock();
    const startStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFF000000),
      fontVariations: [FontVariation('wght', 400)],
    );
    const endStyle = TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      color: Color(0xFFFF0000),
      fontVariations: [FontVariation('wght', 800)],
    );
    final style = MotionValue<TextStyle>(
      startStyle,
      converter: const TextStyleMotionConverter(
        startStyle,
        variationAxes: ['wght'],
      ),
      clock: clock,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MotionClockScope(
          clock: clock,
          child: Center(child: MotionText('Hello', style: style)),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(MotionText),
    );
    expect(paragraph.text.style!.fontSize, 16);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    style.animate(
      0,
      endStyle,
      animation: const TimingCurve.linear(duration: 1),
    );
    clock.advanceTo(0.5);
    await tester.pump();

    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    expect(paragraph.text.style!.fontSize, closeTo(24, 1e-4));
    expect(
      paragraph.text.style!.fontVariations,
      contains(const FontVariation('wght', 600)),
    );
  });

  testWidgets('MotionText under a muted TickerMode keeps its style, and '
      'takes the current one when the same ticker runs again', (tester) async {
    final clock = ManualMotionClock();
    final style = MotionValue<TextStyle>(
      const TextStyle(fontSize: 16),
      converter: const TextStyleMotionConverter(TextStyle(fontSize: 16)),
      clock: clock,
    );
    Widget app({required bool enabled}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: Center(
          child: TickerMode(
            enabled: enabled,
            child: MotionText('Hello', style: style),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(enabled: false));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(MotionText),
    );
    style.snap(0, const TextStyle(fontSize: 32));
    clock.advanceTo(0.1);
    await tester.pump();
    expect(paragraph.text.style!.fontSize, 16);
    await tester.pumpWidget(app(enabled: true));
    expect(paragraph.text.style!.fontSize, 32);
  });

  testWidgets('MotionContentTransition cross-fades and removes outgoing on '
      'settle without mid-flight rebuilds', (tester) async {
    final clock = ManualMotionClock();
    Widget app(int count, {bool reduceMotion = false}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: MotionTraitsOverride(
          traits: MotionTraits(reduceMotion: reduceMotion),
          child: Center(
            child: MotionContentTransition(
              animation: const TimingCurve.linear(duration: 0.5),
              child: Text('$count', key: ValueKey<int>(count)),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(1));
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(app(2));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // Mid-flight frames should not rebuild widgets.
    clock.advanceTo(0.1);
    await tester.pump();
    clock.advanceTo(0.25);
    await tester.pump();
    expect(rebuilt, isEmpty);

    // At settle, outgoing is removed in a single rebuild.
    debugOnRebuildDirtyWidget = null;
    clock.advanceTo(0.6);
    await tester.pump();
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('MotionTransition respects custom alignment pivot', (
    tester,
  ) async {
    final scale = MotionValue<double>(2);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MotionTransition(
            alignment: Alignment.topLeft,
            scale: scale,
            child: const SizedBox(
              key: ValueKey('box'),
              width: 20,
              height: 20,
            ),
          ),
        ),
      ),
    );
    // Scaling 2x about topLeft keeps topLeft at (0, 0) instead of (-10, -10).
    expect(tester.getTopLeft(find.byKey(const ValueKey('box'))), Offset.zero);
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('box'))),
      const Offset(40, 40),
    );
  });

  testWidgets('MotionContentTransition keeps each child State from arrival '
      'to departure, and the leaving child takes no taps', (tester) async {
    final clock = ManualMotionClock();
    final inits = <String>[];
    final taps = <String>[];
    Widget app(String label, double size) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: Center(
          child: MotionContentTransition(
            animation: const TimingCurve.linear(duration: 0.5),
            child: _Probe(
              label,
              size,
              inits: inits,
              taps: taps,
              key: ValueKey(label),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app('a', 100));
    await tester.pumpWidget(app('b', 20));
    clock.advanceTo(0.25);
    await tester.pump();
    final corner = tester.getTopLeft(find.byKey(const ValueKey('a')));
    await tester.tapAt(corner + const Offset(5, 5));
    expect(taps, isEmpty);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('b'))));
    expect(taps, ['b']);

    for (var i = 16; i <= 60; i++) {
      clock.advanceTo(i / 60);
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('a')), findsNothing);
    expect(inits, ['a', 'b']);
  });

  group('MotionContentTransition changes', () {
    late ManualMotionClock clock;
    late List<String> inits;
    setUp(() {
      clock = ManualMotionClock();
      inits = [];
    });

    Widget app(
      String label,
      double width, {
      ContentTransition transition = const ContentTransition.fade(),
      Key? key,
      Widget Function(Widget host) around = _bare,
      Clip clipBehavior = Clip.none,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: Center(
          child: around(
            MotionContentTransition(
              transition: transition,
              animation: const TimingCurve.linear(duration: 0.5),
              clipBehavior: clipBehavior,
              child: _Probe(
                label,
                width,
                inits: inits,
                taps: const [],
                key: key ?? ValueKey(label),
              ),
            ),
          ),
        ),
      ),
    );

    Size size(WidgetTester tester) =>
        tester.getSize(find.byType(MotionContentTransition));

    Future<void> at(WidgetTester tester, double t) async {
      clock.advanceTo(t);
      await tester.pump();
    }

    testWidgets('under a muted TickerMode a change keeps nothing on the '
        'clock, and plays on when the ticker runs', (tester) async {
      clock = _WatchedClock();
      Widget muted(String label, {required bool enabled}) => app(
        label,
        20,
        around: (host) => TickerMode(enabled: enabled, child: host),
      );
      await tester.pumpWidget(muted('a', enabled: false));
      await tester.pumpWidget(muted('b', enabled: false));
      await at(tester, 0.1);
      expect((clock as _WatchedClock).busy, isFalse);
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
      await tester.pumpWidget(muted('b', enabled: true));
      expect((clock as _WatchedClock).busy, isTrue);
      await at(tester, 1);
      expect(find.byKey(const ValueKey('a')), findsNothing);
    });

    testWidgets('the size slides from the leaving child to the arriving one', (
      tester,
    ) async {
      await tester.pumpWidget(app('a', 100));
      await tester.pumpWidget(app('b', 20));
      expect(size(tester).width, 100);
      await at(tester, 0.25);
      expect(size(tester).width, closeTo(60, 1e-6));
      await at(tester, 0.6);
      expect(size(tester).width, 20);
      expect(find.byKey(const ValueKey('a')), findsNothing);
    });

    testWidgets('a change during a change keeps the leaving child', (
      tester,
    ) async {
      await tester.pumpWidget(app('a', 100));
      await tester.pumpWidget(app('b', 60));
      await at(tester, 0.1);
      final before = size(tester).width;
      await tester.pumpWidget(app('c', 20));
      expect(size(tester).width, closeTo(before, 1e-6));
      for (final label in ['a', 'b', 'c']) {
        expect(find.byKey(ValueKey(label)), findsOneWidget);
      }
      await at(tester, 0.3);
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
      await at(tester, 1);
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(find.byKey(const ValueKey('b')), findsNothing);
      expect(inits, ['a', 'b', 'c']);
      expect(size(tester).width, 20);
    });

    testWidgets('changes in quick succession keep few children', (
      tester,
    ) async {
      await tester.pumpWidget(app('0', 10));
      for (var i = 1; i <= 12; i++) {
        await tester.pumpWidget(app('$i', 10.0 + i));
        await at(tester, i / 120);
      }
      expect(
        find.byType(_Probe).evaluate().length,
        lessThanOrEqualTo(1 + MotionChanges.maxChanges),
      );
    });

    testWidgets('clipBehavior clips a child larger than the size', (
      tester,
    ) async {
      Iterable<ClipRectLayer> clips() =>
          tester.layers.whereType<ClipRectLayer>();
      await tester.pumpWidget(app('a', 100));
      await tester.pumpWidget(app('b', 20));
      await at(tester, 0.25);
      expect(clips(), isEmpty);

      await tester.pumpWidget(app('c', 100, clipBehavior: Clip.hardEdge));
      await at(tester, 2);
      await tester.pumpWidget(app('d', 20, clipBehavior: Clip.hardEdge));
      await at(tester, 2.25);
      final clip = clips().single;
      expect(clip.clipRect!.size, size(tester));
      await at(tester, 3);
      expect(clips(), isEmpty);
    });

    testWidgets('the size slides under a parent that measures it', (
      tester,
    ) async {
      Widget measured(Widget host) => IntrinsicWidth(
        child: SizedBox(height: 50, child: host),
      );
      await tester.pumpWidget(app('a', 100, around: measured));
      await tester.pumpWidget(app('b', 20, around: measured));
      await at(tester, 0.25);
      expect(size(tester).width, closeTo(60, 1e-6));
      await at(tester, 0.6);
      expect(size(tester).width, 20);
    });

    testWidgets('a child that comes back arrives anew beside the leaving one', (
      tester,
    ) async {
      await tester.pumpWidget(app('a', 40));
      await tester.pumpWidget(app('b', 40));
      await at(tester, 0.1);
      await tester.pumpWidget(app('a', 40));
      expect(find.byKey(const ValueKey('a')), findsNWidgets(2));
      await at(tester, 1);
      expect(find.byKey(const ValueKey('a')), findsOneWidget);
      expect(inits, ['a', 'b', 'a']);
    });

    testWidgets('a child with a GlobalKey that comes back keeps its State', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(app('a', 40, key: key));
      await tester.pumpWidget(app('b', 40));
      await at(tester, 0.1);
      await tester.pumpWidget(app('a', 40, key: key));
      expect(tester.takeException(), isNull);
      expect(find.byKey(key), findsOneWidget);
      await at(tester, 1);
      expect(inits, ['a', 'b']);
    });

    testWidgets('a baseline row measures it without laying it out', (
      tester,
    ) async {
      const style = TextStyle(fontSize: 20);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MotionClockScope(
            clock: clock,
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('x', style: TextStyle(fontSize: 40)),
                  MotionContentTransition(child: Text('y', style: style)),
                ],
              ),
            ),
          ),
        ),
      );
      final row = tester.renderObject<RenderBox>(find.byType(Row));
      expect(row.getDryLayout(const BoxConstraints()), row.size);
      final host = tester.renderObject<RenderBox>(
        find.byType(MotionContentTransition).first,
      );
      final text = tester.renderObject<RenderBox>(find.text('y'));
      const baseline = TextBaseline.alphabetic;
      final dry = host.getDryBaseline(host.constraints, baseline);
      expect(dry, isNotNull);
      expect(dry, text.getDryBaseline(host.constraints, baseline));
    });

    testWidgets('a transition of its own poses the content', (tester) async {
      await tester.pumpWidget(app('a', 40, transition: const _Turn()));
      await tester.pumpWidget(app('b', 40, transition: const _Turn()));
      await at(tester, 0.25);
      expect(
        tester.layers.whereType<MotionTransitionLayer>().where(
          (layer) => layer.debugAddsTransform,
        ),
        hasLength(2),
      );
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe(
    this.label,
    this.size, {
    required this.inits,
    required this.taps,
    super.key,
  });

  final String label;
  final double size;
  final List<String> inits;
  final List<String> taps;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.inits.add(widget.label);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => widget.taps.add(widget.label),
    child: SizedBox.square(dimension: widget.size),
  );
}

class _Turn extends ContentTransition {
  const _Turn();

  @override
  MotionPose poseAt(double progress, {required bool incoming}) =>
      MotionPose(rotation: (incoming ? 1 - progress : -progress) * 0.5);
}

Widget _bare(Widget host) => host;

class _WatchedClock extends ManualMotionClock {
  bool get busy => needsFrame;
}
