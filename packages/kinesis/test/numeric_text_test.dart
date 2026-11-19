import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/src/widgets/motion_numeric_text.dart'
    show RenderMotionNumericText;
import 'package:kinesis/testing.dart';

List<Rect> _boxes(String text, {double left = 0}) => [
  for (var i = 0; i < text.runes.length; i++)
    Rect.fromLTWH(left + i * 10, 0, 10, 20),
];

double _width(String text) => text.runes.length * 10.0;

NumericTextMotion _motion(String text) =>
    NumericTextMotion(text, boxes: _boxes(text), width: _width(text));

extension on NumericTextMotion {
  void show(double t, String text, {double left = 0, bool? countsDown}) =>
      setText(
        t,
        text,
        boxes: _boxes(text, left: left),
        width: _width(text),
        countsDown: countsDown,
      );
}

String _shown(NumericTextFrame frame) => [
  for (final glyph in frame.glyphs)
    if (glyph.departure == null) glyph.character,
].join();

String _leaving(NumericTextFrame frame) => [
  for (final glyph in frame.glyphs)
    if (glyph.departure != null) glyph.character,
].join();

class _InPlace extends NumericTextTransition {
  const _InPlace();

  @override
  MotionPose poseAt(
    double progress, {
    required bool incoming,
    required int direction,
  }) => incoming ? MotionPose.identity : const MotionPose(opacity: 0);
}

void main() {
  group('NumericTextMotion', () {
    test('rolls only changed digits and keeps the rest in place', () {
      final motion = _motion(r'$1,239')..show(0, r'$1,240');

      final mid = motion.frameAt(0.05);
      expect(_shown(mid), r'$1,240');
      expect(_leaving(mid), '39');
      for (final glyph in mid.glyphs) {
        final changed = '3940'.contains(glyph.character);
        expect(glyph.arrival != null || glyph.departure != null, changed);
        if (glyph.arrival case final arrival?) {
          expect(arrival, inExclusiveRange(0, 1));
          expect(glyph.arrivalDirection, 1);
        }
        if (glyph.departure case final departure?) {
          expect(departure, inExclusiveRange(0, 1));
          expect(glyph.departureDirection, 1);
        }
      }

      motion.advance(2);
      final done = motion.frame;
      expect(done.settled, isTrue);
      expect(_shown(done), r'$1,240');
      expect(done.glyphs.map((glyph) => glyph.box), _boxes(r'$1,240'));
    });

    test('infers the roll and slides the width as digits come and go', () {
      final motion = _motion('10')..show(0, '9');
      expect(motion.frameAt(0).width, 20);
      final down = motion.frameAt(0.05);
      expect(_leaving(down), '10');
      expect(down.glyphs.every((glyph) => glyph.departureDirection <= 0), true);
      expect(down.glyphs.last.arrivalDirection, -1);
      expect(down.width, inExclusiveRange(10, 20));

      motion
        ..advance(2)
        ..show(2, '10');
      expect(motion.frameAt(2).width, 10);
      final up = motion.frameAt(2.05);
      expect(_shown(up), '10');
      expect(_leaving(up), '9');
      expect(up.glyphs.last.arrivalDirection, 1);
      motion.advance(4);
      expect(motion.frame.width, 20);
    });

    test('rolls in place under reduceMotion', () {
      final motion = _motion('5')
        ..traits = const MotionTraits(reduceMotion: true)
        ..show(0, '6');
      final mid = motion.frameAt(0.05);
      expect(mid.glyphs.first.departureDirection, 0);
      expect(mid.glyphs.last.arrivalDirection, 0);
    });

    test('a character that stays slides from its old box to its new one', () {
      final motion = _motion('a5')..show(0, 'a6', left: 30);
      NumericGlyph a(double t) =>
          motion.frameAt(t).glyphs.firstWhere((g) => g.character == 'a');
      expect(a(0).box.left, 0);
      expect(a(0.1).box.left, inExclusiveRange(0, 30));
      expect(a(0.1).arrival, isNull);
      motion.advance(2);
      expect(a(2).box.left, 30);
    });

    test('a change during a change carries on from what shows', () {
      final motion = _motion('11')..show(0, '12');
      final before = motion.frameAt(0.1);
      motion.show(0.1, '13');
      final after = motion.frameAt(0.1);

      final arriving = before.glyphs.firstWhere((g) => g.character == '2');
      final replaced = after.glyphs.firstWhere((g) => g.character == '2');
      expect(replaced.arrival, arriving.arrival);
      expect(replaced.box, arriving.box);
      expect(replaced.departure, 0);
      final leaving = before.glyphs.firstWhere((g) => g.departure != null);
      expect(
        after.glyphs.firstWhere((g) => g.character == leaving.character),
        leaving,
      );
      expect(after.width, before.width);
    });

    test('at most maxChanges changes run at once', () {
      final motion = _motion('0');
      for (var i = 1; i <= 20; i++) {
        motion.show(i * 0.01, '${i % 10}');
      }
      final frame = motion.frameAt(0.2);
      expect(
        frame.glyphs.length,
        lessThanOrEqualTo(1 + NumericTextMotion.maxChanges),
      );
      expect(_shown(frame), '0');
    });

    test('unanimated, the text shows at once', () {
      final motion = _motion('1')..show(0, '2');
      motion.setText(
        0.05,
        '345',
        boxes: _boxes('345'),
        width: 30,
        animated: false,
      );
      final frame = motion.frameAt(0.05);
      expect(frame.settled, isTrue);
      expect(_shown(frame), '345');
      expect(frame.width, 30);
    });
  });

  group('MotionNumericText', () {
    late ManualMotionClock clock;
    setUp(() => clock = ManualMotionClock());

    Widget app(
      String text, {
      Key? key,
      NumericTextTransition transition = const NumericTextTransition.roll(),
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: MotionClockScope(
        clock: clock,
        child: Center(
          child: RepaintBoundary(
            child: MotionNumericText(
              text,
              key: key,
              transition: transition,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: -1.6,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );

    RenderMotionNumericText text(WidgetTester tester) =>
        tester.renderObject(find.byType(MotionNumericText));

    Future<void> frames(WidgetTester tester, double from, double to) async {
      for (var t = from; t <= to + 1e-9; t += 1 / 60) {
        clock.advanceTo(t);
        await tester.pump();
      }
    }

    testWidgets('a change builds no widget per frame', (tester) async {
      await tester.pumpWidget(app('42'));
      await tester.pumpWidget(app('43'));
      final rebuilt = <Widget>[];
      debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      await frames(tester, 1 / 60, 0.25);
      debugOnRebuildDirtyWidget = null;
      expect(rebuilt, isEmpty);
      expect(text(tester).debugFrame.settled, isFalse);
    });

    testWidgets('the width slides from the old text to the new', (
      tester,
    ) async {
      await tester.pumpWidget(app('999'));
      final narrow = tester.getSize(find.byType(MotionNumericText)).width;
      await tester.pumpWidget(app('1,000'));
      expect(tester.getSize(find.byType(MotionNumericText)).width, narrow);
      await frames(tester, 1 / 60, 0.1);
      final mid = tester.getSize(find.byType(MotionNumericText)).width;
      expect(mid, greaterThan(narrow));
      await frames(tester, 0.1 + 1 / 60, 2);
      final settled = tester.getSize(find.byType(MotionNumericText));

      await tester.pumpWidget(app('1,000', key: const ValueKey('fresh')));
      expect(tester.getSize(find.byType(MotionNumericText)), settled);
      expect(mid, lessThan(settled.width));
    });

    testWidgets('a leaving digit is gone once it settles', (tester) async {
      await tester.pumpWidget(app('10'));
      await tester.pumpWidget(app('9'));
      await frames(tester, 1 / 60, 2);
      final frame = text(tester).debugFrame;
      expect(frame.settled, isTrue);
      expect(frame.glyphs.map((glyph) => glyph.character), ['9']);
    });

    testWidgets('changes in quick succession open few layers', (tester) async {
      await tester.pumpWidget(app('100'));
      var layers = 0;
      for (var i = 1; i <= 30; i++) {
        await tester.pumpWidget(app('${100 + i}'));
        clock.advanceTo(i / 120);
        await tester.pump();
        if (text(tester).debugLayers > layers) {
          layers = text(tester).debugLayers;
        }
      }
      expect(layers, lessThanOrEqualTo(2 * NumericTextMotion.maxChanges));
      expect(
        text(tester).debugFrame.glyphs.length,
        lessThanOrEqualTo(3 + 2 * NumericTextMotion.maxChanges),
      );
    });

    testWidgets('glyphs in place paint the pixels of the text at rest', (
      tester,
    ) async {
      Future<Uint8List> capture() async {
        final boundary = tester.renderObject(
          find.byType(RepaintBoundary).first,
        ) as RenderRepaintBoundary;
        late Uint8List pixels;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData();
          pixels = bytes!.buffer.asUint8List();
          image.dispose();
        });
        return pixels;
      }

      await tester.pumpWidget(app(r'$1,239', transition: const _InPlace()));
      await tester.pumpWidget(app(r'$1,240', transition: const _InPlace()));
      await frames(tester, 1 / 60, 0.05);
      expect(text(tester).debugFrame.settled, isFalse);
      final moving = await capture();
      await frames(tester, 0.05 + 1 / 60, 2);
      expect(text(tester).debugFrame.settled, isTrue);
      final resting = await capture();
      expect(moving, resting);
    });

    testWidgets('screen readers read the text', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app('42'));
      expect(find.bySemanticsLabel('42'), findsOneWidget);
      await tester.pumpWidget(app('43'));
      expect(find.bySemanticsLabel('43'), findsOneWidget);
      semantics.dispose();
    });
  });
}
