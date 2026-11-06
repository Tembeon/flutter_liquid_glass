@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: without
// Impeller there is no glass to read.
//
// Glass on a section's card reads the card's color, not the screen.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/composer/frame_report.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';

const _viewSize = Size(402, 400);
const _dpr = 3.0;

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

Widget _page(_CapturingView view, {required bool reads, required int key}) {
  Widget button = GlassButton(
    onPressed: () {},
    child: const SizedBox(width: 120, height: 20),
  );
  if (reads) button = GlassSolidBackdrop(color: null, child: button);
  return View(
    key: ValueKey(key),
    view: view,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: _viewSize, devicePixelRatio: _dpr),
        child: GlassTheme(
          data: const GlassThemeData(renderer: GlassRenderer.liquid()),
          child: ColoredBox(
            color: const Color(0xFFD02020),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: GlassListSection(
                  style: const GlassListStyle(
                    backgroundColor: WidgetStatePropertyAll(Color(0xFF2C2C2E)),
                  ),
                  children: [
                    SizedBox(height: 100, child: Center(child: button)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<(Uint8List, GlassFrameReport)> _draw(
  WidgetTester tester,
  _CapturingView view, {
  required bool reads,
}) async {
  GlassFrameReport? last;
  void listener(GlassFrameReport report) => last = report;
  GlassFrameReport.addListener(listener);
  addTearDown(() => GlassFrameReport.removeListener(listener));
  await tester.pumpWidget(
    _page(view, reads: reads, key: reads ? 1 : 0),
    wrapWithView: false,
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return (data.buffer.asUint8List(), last!);
}

void main() {
  setUp(() => GlassCopies.debugEnabledOverride = true);
  tearDown(() => GlassCopies.debugEnabledOverride = null);

  testWidgets('glass on a card reads nothing and looks the same', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(GlassRenderer.precache);
    final view = _CapturingView(tester);
    final (read, readReport) = await _draw(tester, view, reads: true);
    final (solid, solidReport) = await _draw(tester, view, reads: false);
    expect(readReport.reads, isNotEmpty);
    expect(solidReport.reads, isEmpty);

    var sum = 0;
    var max = 0;
    var inside = 0;
    final width = (_viewSize.width * _dpr).toInt();
    for (var y = 60 * 3; y < 240 * 3; y++) {
      for (var x = 40 * 3; x < 362 * 3; x++) {
        final at = (y * width + x) * 4;
        for (var c = 0; c < 3; c++) {
          final d = (read[at + c] - solid[at + c]).abs();
          sum += d;
          if (d > max) max = d;
        }
        inside++;
      }
    }
    expect(max, lessThan(40));
    expect(sum / (inside * 3), lessThan(2));
  });
}
