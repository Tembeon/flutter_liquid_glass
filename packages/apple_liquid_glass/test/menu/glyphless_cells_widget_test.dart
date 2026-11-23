import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('with hidden glyphs a small cell shows its 17 point title in '
      '38 points and a medium cell centers its title', (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    GlassMenuItem item(String title) => GlassMenuItem(
      title: title,
      icon: const Icon(IconData(0x41), key: Key('glyph')),
      iconVisibility: GlassMenuIconVisibility.hidden,
      onPressed: () {},
    );
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
              GlassMenuSection(
                elementSize: GlassMenuElementSize.small,
                children: [item('Share'), item('Delete')],
              ),
              GlassMenuSection(
                elementSize: GlassMenuElementSize.medium,
                children: [item('Copy'), item('Move'), item('Pin')],
              ),
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
    await tester.tap(find.byKey(const Key('button')));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byKey(const Key('glyph')), findsNothing);
    final share = tester.renderObject<RenderParagraph>(find.text('Share'));
    expect(
      share.textScaler.scale(share.text.style!.fontSize!),
      closeTo(17, 1e-9),
    );
    expect(share.size.width, 38);
    expect(share.maxLines, 1);
    final copy = tester.renderObject<RenderParagraph>(find.text('Copy'));
    expect(copy.text.style!.fontSize, 12);
    final cell = tester.getRect(
      find
          .ancestor(of: find.text('Copy'), matching: find.byType(Positioned))
          .first,
    );
    expect(
      tester.getCenter(find.text('Copy')).dy,
      closeTo(cell.center.dy, 0.5),
    );
  });
}
