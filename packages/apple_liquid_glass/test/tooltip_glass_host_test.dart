// Glass beside a tooltip keeps reading a copy of what lies under it, with
// the tooltip closed and open. Run with `flutter test --enable-impeller
// --enable-flutter-gpu`: without Impeller there is no glass to read.
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';

Widget _page() => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => GlassScope(
    renderer: const LiquidGlassRenderer(),
    child: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => ColoredBox(
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
                  left: 40,
                  top: 40,
                  child: GlassTooltip(
                    message: 'New letter',
                    child: SizedBox(
                      key: Key('button'),
                      width: 44,
                      height: 44,
                      child: ColoredBox(color: Color(0xFFF0A030)),
                    ),
                  ),
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

  testWidgets('glass beside a closed and an open tooltip reads a copy', (
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

    await tester.pumpWidget(_page());
    for (var i = 0; i < 3; i++) {
      await _frame(tester);
    }
    final closed = last!;
    expect(closed.reads, isNotEmpty);
    expect(
      closed.reads.map((read) => read.source),
      everyElement(isNot(GlassReadSource.backdrop)),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('button'))));
    for (var i = 0; i < 40; i++) {
      await _frame(tester);
    }
    expect(find.text('New letter'), findsOneWidget);
    final open = last!;
    expect(open.reads, isNotEmpty);
    expect(
      open.reads.map((read) => read.source),
      everyElement(isNot(GlassReadSource.backdrop)),
    );
  });
}
