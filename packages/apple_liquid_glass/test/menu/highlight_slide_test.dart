import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The rect the open menu's highlight paints, in its card's content.
Rect? _highlight(WidgetTester tester) {
  final painters = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_HighlightPainter',
  );
  for (final element in painters.evaluate()) {
    final box = element.renderObject! as RenderCustomPaint;
    final recorder = _Recorder();
    box.painter!.paint(recorder, box.size);
    if (recorder.rect != null) return recorder.rect;
  }
  return null;
}

class _Recorder implements Canvas {
  Rect? rect;

  @override
  void drawRRect(RRect rrect, Paint paint) => rect = rrect.outerRect;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the highlight slides from row to row on a 0.12 s spring '
      '(menu button passport)', (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: Center(
          child: GlassMenuAnchor(
            menuChildren: [
              for (final title in ['Copy', 'Share', 'Rename'])
                GlassMenuItem(title: title, onPressed: () {}),
            ],
            builder: (context, controller, child) => GlassButton(
              key: const Key('button'),
              onPressed: controller.open,
              child: const Text('More'),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('button'))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.moveTo(tester.getCenter(find.text('Copy')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final copy = _highlight(tester)!;
    await gesture.moveTo(tester.getCenter(find.text('Share')));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final between = _highlight(tester)!;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final share = _highlight(tester)!;
    expect(share.top, greaterThan(copy.top));
    expect(between.top, greaterThan(copy.top));
    expect(between.top, lessThan(share.top));
    expect(share.height, copy.height);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
