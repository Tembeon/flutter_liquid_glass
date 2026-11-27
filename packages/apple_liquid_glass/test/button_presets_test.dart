import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MediaQuery(
      data: MediaQueryData(platformBrightness: brightness),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          child: Center(child: child),
        ),
      ),
    );

int? _label(WidgetTester tester) => tester
    .widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Go'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    )
    .style
    .color
    ?.toARGB32();

PaintPattern _fills(Color color) => paints
  ..something(
    (method, arguments) => arguments.any(
      (argument) =>
          argument is Paint && argument.color.toARGB32() == color.toARGB32(),
    ),
  );

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a gray button fills with secondarySystemFill under a label '
      'in the label color, and dims both to 0.75 under a press', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(GlassButton.gray(onPressed: () {}, child: const Text('Go'))),
    );
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(GlassButton), _fills(const Color(0x29787880)));
    expect(_label(tester), 0xFF000000);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassButton)),
    );
    await tester.pump();
    expect(
      find.byType(GlassButton),
      _fills(const Color(0x29787880).withValues(alpha: 0x29 / 255 * 0.75)),
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a tinted button fills with the tint at 0.18 in light and 0.25 '
      'in dark under a tinted label; a filled one fills with the tint under '
      'white', (tester) async {
    await tester.pumpWidget(
      _app(GlassButton.tinted(onPressed: () {}, child: const Text('Go'))),
    );
    expect(
      find.byType(GlassButton),
      _fills(const Color(0xFF0088FF).withValues(alpha: 0x2E / 255)),
    );
    expect(_label(tester), 0xFF0088FF);
    await tester.pumpWidget(
      _app(
        GlassButton.tinted(onPressed: () {}, child: const Text('Go')),
        brightness: Brightness.dark,
      ),
    );
    expect(
      find.byType(GlassButton),
      _fills(const Color(0xFF0091FF).withValues(alpha: 0x40 / 255)),
    );
    await tester.pumpWidget(
      _app(GlassButton.filled(onPressed: () {}, child: const Text('Go'))),
    );
    expect(find.byType(GlassButton), _fills(const Color(0xFF0088FF)));
    expect(_label(tester), 0xFFFFFFFF);
  });

  testWidgets('a shape outlines the glass of a glass button, the fill of a '
      'filled one and the hover of a plain one in place of their defaults', (
    tester,
  ) async {
    const shape = LiquidRoundedSuperellipse(radius: 8);
    final style = GlassButton.styleFrom(shape: shape);
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassButton(onPressed: () {}, style: style, child: const Text('A')),
            GlassButton.filled(
              onPressed: () {},
              style: style,
              child: const Text('Go'),
            ),
            GlassButton.plain(
              onPressed: () {},
              style: style,
              child: const Text('C'),
            ),
          ],
        ),
      ),
    );
    final raws = tester.widgetList<RawGlassButton>(find.byType(RawGlassButton));
    expect(raws.map((raw) => raw.shape), everyElement(shape));
    final filled = find.ancestor(
      of: find.text('Go'),
      matching: find.byType(GlassButton),
    );
    expect(
      filled,
      paints..something(
        (method, arguments) =>
            method == #drawRSuperellipse &&
            (arguments.first as RSuperellipse).tlRadiusX == 8,
      ),
    );
    await tester.pumpWidget(
      _app(GlassButton.filled(onPressed: () {}, child: const Text('Go'))),
    );
    expect(
      find.byType(GlassButton),
      paints..something(
        (method, arguments) =>
            method == #drawRSuperellipse &&
            (arguments.first as RSuperellipse).tlRadiusX == 31 / 2,
      ),
    );
    expect(
      tester.widget<RawGlassButton>(find.byType(RawGlassButton)).shape,
      LiquidRoundedSuperellipse.capsule,
    );
  });

  testWidgets('a disabled gray, tinted or filled button draws '
      'tertiarySystemFill under a tertiaryLabel label', (tester) async {
    for (final button in const [
      GlassButton.gray(onPressed: null, child: Text('Go')),
      GlassButton.tinted(onPressed: null, child: Text('Go')),
      GlassButton.filled(onPressed: null, child: Text('Go')),
    ]) {
      await tester.pumpWidget(_app(button));
      expect(find.byType(GlassButton), _fills(const Color(0x1F767680)));
      expect(_label(tester), 0x4C3C3C43);
    }
  });

  testWidgets('a control size sets the text and the insets: small 15 point '
      'text 10 and 5 in, large 17 point text 20 and 15 in', (tester) async {
    Future<(Size, Size, double)> measure(GlassControlSize size) async {
      await tester.pumpWidget(
        _app(
          GlassButton.gray(
            onPressed: () {},
            style: GlassButton.styleFrom(controlSize: size),
            child: const Text('Go'),
          ),
        ),
      );
      return (
        tester.getSize(find.byType(GlassButton)),
        tester.getSize(find.text('Go')),
        tester
            .widget<RichText>(
              find.descendant(
                of: find.text('Go'),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .fontSize!,
      );
    }

    final (small, smallText, smallFont) = await measure(GlassControlSize.small);
    expect(smallFont, 15);
    expect(small.width, smallText.width + 20);
    expect(small.height, smallText.height + 10);
    final (large, largeText, largeFont) = await measure(GlassControlSize.large);
    expect(largeFont, 17);
    expect(large.width, largeText.width + 40);
    expect(large.height, largeText.height + 30);
  });

  testWidgets('a loading button shows a spinner before its text, or in '
      "place of an icon, and grows by the spinner's width", (tester) async {
    await tester.pumpWidget(
      _app(GlassButton.gray(onPressed: () {}, child: const Text('Go'))),
    );
    final idle = tester.getSize(find.byType(GlassButton)).width;
    await tester.pumpWidget(
      _app(
        GlassButton.gray(
          onPressed: () {},
          loading: true,
          child: const Text('Go'),
        ),
      ),
    );
    expect(find.byType(GlassActivityIndicator), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(
      tester.getSize(find.byType(GlassButton)).width,
      idle + tester.getSize(find.byType(GlassActivityIndicator)).width,
    );
    await tester.pumpWidget(
      _app(
        GlassButton(
          onPressed: () {},
          loading: true,
          child: const Icon(IconData(0xe000)),
        ),
      ),
    );
    expect(find.byType(GlassActivityIndicator), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });
}
