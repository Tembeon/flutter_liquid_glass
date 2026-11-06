// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass is
// drawn as on a device, and fake glass otherwise.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/testing.dart';

import '../shared.dart';

const _row = 44.0;

Widget _button(double left, double top, LiquidGlassSettings settings) =>
    Positioned(
      left: left,
      top: top,
      width: 44,
      height: 44,
      child: LiquidGlassLayer(
        settings: settings,
        child: const LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: 22),
          child: SizedBox.expand(),
        ),
      ),
    );

// A list scrolling under chrome: five buttons along the bottom over a list
// with [rows] rows, each its own colour.
Widget _screen(ScrollController controller, {int buttons = 5, int rows = 80}) {
  final settings = LiquidGlassSettings.ios27RegularLight();
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: controller,
              itemCount: rows,
              itemExtent: _row,
              itemBuilder: (_, i) => ColoredBox(
                color: Color(0xFF000000 | (i * 2654435761) & 0x7F7F7F),
              ),
            ),
          ),
          for (var i = 0; i < buttons; i++)
            _button(8 + i * 76.0, 700, settings),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() => GlassCopies.debugEnabledOverride = true);
  tearDown(() => GlassCopies.debugEnabledOverride = null);

  group('a frame nothing changed', () {
    testWidgets('makes no filter, picture or image and replays nothing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final report = await expectGlassBudget(
        tester,
        filtersBuilt: 0,
        picturesRecorded: 0,
        imagesDrawn: 0,
      );
      expect(report.layersReplayed, 0, reason: '$report');
      expect(report.repaintsAsked, 0, reason: '$report');
      expect(report.reads.first.changed, isFalse, reason: '$report');
    }, skip: skipProperGlassTests);
  });

  group('a scroll frame', () {
    testWidgets('makes no more filters than reads that changed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      for (var i = 0; i < 30; i++) {
        controller.jumpTo(i * 3);
        await tester.pump(const Duration(milliseconds: 16));
      }

      controller.jumpTo(100);
      final report = await expectGlassBudget(tester, liveReads: 0);
      final changed = report.reads.where((read) => read.changed).length;
      expect(
        report.filtersBuilt,
        lessThanOrEqualTo(changed),
        reason: '$report',
      );
      expect(report.repaintsAsked, 0, reason: '$report');
    }, skip: skipProperGlassTests);

    testWidgets('replays in proportion to what it shows, not to the list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<int> replayed(int rows) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_screen(controller, rows: rows));
        for (var i = 0; i < 12; i++) {
          controller.jumpTo(i * 3);
          await tester.pump(const Duration(milliseconds: 16));
        }
        controller.jumpTo(60);
        final report = await expectGlassBudget(tester);
        return report.layersReplayed;
      }

      expect(await replayed(2000), lessThanOrEqualTo(await replayed(40) + 2));
    }, skip: skipProperGlassTests);
  });

  group('the report', () {
    testWidgets('says what the frame read and made', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      await tester.pump();

      final report = await expectGlassBudget(tester);
      final text = '$report';
      expect(report.reads, isNotEmpty);
      expect(text, contains('reads ${report.reads.length}'));
      expect(text, contains('R0 '));
      expect(report.walk, isNot(Duration.zero));
    }, skip: skipProperGlassTests);

    testWidgets('names a layer type nobody registered', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = LiquidGlassSettings.ios27RegularLight();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Stack(
              children: [
                const Positioned.fill(child: _Foreign()),
                _button(8, 100, settings),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final report = await expectGlassBudget(tester, liveReads: 1);
      expect(
        report.notes.join('\n'),
        allOf(
          contains('_ForeignLayer (unregistered)'),
          contains('LiquidGlassUnderlay.registerLayer'),
        ),
      );
    }, skip: skipProperGlassTests);

    testWidgets('stops when nobody listens', (tester) async {
      final seen = <GlassFrameReport>[];
      void note(GlassFrameReport report) => seen.add(report);
      GlassFrameReport.addListener(note);
      GlassFrameReport.removeListener(note);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_screen(controller));
      await tester.pump();
      expect(seen, isEmpty);
    });

    testWidgets('shows over the app in an overlay', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        GlassPlanOverlay(child: _screen(controller)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('reads '), findsOneWidget);
    }, skip: skipProperGlassTests);
  });
}

class _ForeignLayer extends ContainerLayer {}

class _Foreign extends LeafRenderObjectWidget {
  const _Foreign();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderForeign();
}

class _RenderForeign extends RenderBox {
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushLayer(_ForeignLayer(), (context, offset) {}, offset);
  }
}
