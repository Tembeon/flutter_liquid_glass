import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
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
      converter: MotionConverter.textStyle(
        startStyle,
        variationAxes: const ['wght'],
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
}
