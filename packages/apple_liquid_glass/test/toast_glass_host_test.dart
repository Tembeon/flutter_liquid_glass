// Glass beside a toast keeps reading a copy of what lies under it, with no
// toast and with one shown. Run with `flutter test --enable-impeller
// --enable-flutter-gpu`: without Impeller there is no glass to read.
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';

const _page = Key('page');

Widget _app() => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => GlassScope(
    renderer: const LiquidGlassRenderer(),
    child: GlassToaster(
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => ColoredBox(
              key: _page,
              color: const Color(0xFF204060),
              child: Stack(
                children: [
                  for (var i = 0; i < 8; i++)
                    Positioned(
                      left: 20,
                      top: 40.0 + i * 60,
                      child: const Text('Under the bar'),
                    ),
                  const Positioned(
                    left: 21,
                    right: 21,
                    bottom: 21,
                    height: 62,
                    child: GlassSurface(
                      role: GlassRole.bar,
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _frame(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
}

void main() {
  setUp(() {
    MotionClock.debugReset();
    glassReadsCopies = true;
  });
  tearDown(() => glassReadsCopies = false);

  testWidgets('glass beside no toast and beside a shown one reads a copy', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await tester.runAsync(precacheGlass);
    tester.view.physicalSize = const Size(402, 600) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    GlassFrameReport? last;
    void listener(GlassFrameReport report) => last = report;
    GlassFrameReports.addListener(listener);
    addTearDown(() => GlassFrameReports.removeListener(listener));

    await tester.pumpWidget(_app());
    for (var i = 0; i < 3; i++) {
      await _frame(tester);
    }
    final none = last!;
    expect(none.reads, isNotEmpty);
    expect(
      none.reads.map((read) => read.source),
      everyElement(isNot(GlassReadSource.backdrop)),
    );

    showGlassToast(
      context: tester.element(find.byKey(_page)),
      duration: null,
      builder: (context, toast) => const GlassToast(title: Text('Copied')),
    );
    for (var i = 0; i < 40; i++) {
      await _frame(tester);
    }
    expect(find.text('Copied'), findsOneWidget);
    final shown = last!;
    expect(shown.reads, isNotEmpty);
    expect(
      shown.reads.map((read) => read.source),
      everyElement(isNot(GlassReadSource.backdrop)),
    );
  });
}
