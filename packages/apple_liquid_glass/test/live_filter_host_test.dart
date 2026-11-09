@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: without
// Impeller there is no glass to read.
//
// Glass scrolled over a copy builds no live filter, and the live filter is up
// to date on the frame the plan turns to it.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';

const _viewSize = Size(300, 600);
const _dpr = 2.0;

class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _viewSize * _dpr;
    devicePixelRatio = _dpr;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      (_viewSize.width * _dpr).toInt(),
      (_viewSize.height * _dpr).toInt(),
    );
  }
}

Widget _row(int index) => SizedBox(
  height: 100,
  child: ColoredBox(
    color: index.isEven ? const Color(0xFF00C000) : const Color(0xFF0000C0),
    child: Center(
      child: SizedBox(
        width: 200,
        height: 60,
        child: LiquidGlassLayer(
          // Other highlights keep each in a read of its own.
          settings: LiquidGlassSettings.ios27RegularLight().copyWith(
            highlight: 0.1 + index / 100,
          ),
          child: const LiquidGlass(
            shape: LiquidRoundedSuperellipse(borderRadius: 20),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  ),
);

Widget _list(_CapturingView view, ScrollController controller, {Key? key}) =>
    View(
      key: key,
      view: view,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: controller,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: 40,
          itemBuilder: (_, index) => RepaintBoundary(child: _row(index)),
        ),
      ),
    );

Future<void> _loaded(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 200)),
);

// Flutter_tester's software Vulkan crashes under frames drawn back to back.
Future<void> _frame(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

Future<Uint8List> _pixels(WidgetTester tester, _CapturingView view) async {
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return data.buffer.asUint8List();
}

void main() {
  setUp(() => GlassCopies.debugEnabledOverride = true);
  tearDown(() {
    GlassCopies.debugEnabledOverride = null;
    GlassComposer.debugPolicy = const Policy();
  });

  testWidgets('glass scrolled over a copy builds no live filter', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_list(view, controller), wrapWithView: false);
    await _loaded(tester);
    await _frame(tester);

    GlassFrameReport? last;
    void listener(GlassFrameReport report) => last = report;
    GlassFrameReport.addListener(listener);
    addTearDown(() => GlassFrameReport.removeListener(listener));
    var offset = 0.0;
    for (var i = 0; i < 8; i++) {
      offset += 7;
      controller.jumpTo(offset);
      await _frame(tester);
    }
    final report = last!;
    final glass = report.reads.fold(0, (sum, read) => sum + read.glass);
    expect(glass, greaterThanOrEqualTo(5));
    expect(
      report.reads.map((r) => r.source),
      isNot(contains(GlassReadSource.live)),
    );
    // Each read's own filter, which follows the glass, and no more.
    expect(report.filtersBuilt, lessThanOrEqualTo(2 * report.reads.length));
  });

  testWidgets('the live filter follows glass scrolled while it read a copy', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _list(view, controller, key: const ValueKey('moved')),
      wrapWithView: false,
    );
    await _loaded(tester);
    await _frame(tester);
    for (var offset = 7.0; offset < 60; offset += 7) {
      controller.jumpTo(offset);
      await _frame(tester);
    }
    GlassComposer.debugPolicy = const Policy(copies: false);
    await _frame(tester);
    await _frame(tester);
    final moved = await _pixels(tester, view);

    final fresh = ScrollController(initialScrollOffset: 56);
    addTearDown(fresh.dispose);
    await tester.pumpWidget(
      _list(view, fresh, key: const ValueKey('fresh')),
      wrapWithView: false,
    );
    await _loaded(tester);
    await _frame(tester);
    await _frame(tester);
    final direct = await _pixels(tester, view);

    var off = 0;
    for (var i = 0; i < moved.length; i += 4) {
      if ((moved[i + 1] - direct[i + 1]).abs() > 12 ||
          (moved[i + 2] - direct[i + 2]).abs() > 12) {
        off++;
      }
    }
    expect(off / (moved.length / 4), lessThan(0.002));
  });
}
