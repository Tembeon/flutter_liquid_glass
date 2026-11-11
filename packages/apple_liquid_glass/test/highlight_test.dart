import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:apple_liquid_glass/src/surfaces/highlight.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _body = Size(120, 44);
const _screen = ValueKey('screen');

Widget _app(
  GlassRenderer renderer,
  Widget child, {
  bool highContrast = false,
  bool reduceMotion = false,
}) => MediaQuery(
  data: MediaQueryData(highContrast: highContrast),
  child: MotionTraitsOverride(
    traits: MotionTraits(reduceMotion: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: renderer,
        child: RepaintBoundary(
          key: _screen,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  ),
);

Widget _surface(
  WidgetStatesController states, {
  MotionSelection<GlassFrame>? frame,
  Color? focusColor,
}) => SizedBox.fromSize(
  size: _body,
  child: GlassSurface.live(
    frame: frame ?? MotionSelection(() => const GlassFrame()),
    states: states,
    focusColor: focusColor,
    child: const SizedBox.expand(),
  ),
);

/// The ring's color of an untinted body at standard contrast.
final _ring = GlassHighlights.ringColor(
  null,
  GlassColors.systemBlue.color,
  highContrast: false,
);

RenderGlassHighlight _box(WidgetTester tester) =>
    tester.renderObject<RenderGlassHighlight>(find.byType(GlassHighlightBox));

bool _near(Color a, Color b) =>
    (a.a - b.a).abs() < 1e-3 &&
    (a.r - b.r).abs() < 1e-3 &&
    (a.g - b.g).abs() < 1e-3 &&
    (a.b - b.b).abs() < 1e-3;

/// The paths [finder] fills in a color near [color].
List<Path> _filled(WidgetTester tester, Finder finder, Color color) {
  final found = <Path>[];
  expect(
    finder,
    paints..everything((method, arguments) {
      if (method != #drawPath) return true;
      final paint = arguments[1] as Paint;
      if (paint.style == PaintingStyle.fill && _near(paint.color, color)) {
        found.add(arguments[0] as Path);
      }
      return true;
    }),
  );
  return found;
}

/// The color of the screen at [at], relative to the body's top left.
Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screen),
  );
  final origin = tester.getTopLeft(find.byType(GlassSurface));
  final point = origin + at;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    final width = image.width;
    image.dispose();
    final i = (point.dy.floor() * width + point.dx.floor()) * 4;
    return data!.buffer.asUint8List().sublist(i, i + 4);
  });
  return Color.fromARGB(bytes![3], bytes[0], bytes[1], bytes[2]);
}

/// Whether [color] is bluish, as the ring is over white.
bool _blue(Color color) => color.b - color.r > 0.15;

/// The focus rings [finder] paints.
List<Path> _rings(WidgetTester tester, Finder finder) =>
    _filled(tester, finder, _ring);

/// Whether [finder] paints the hover response.
bool _hovers(WidgetTester tester, Finder finder) =>
    _filled(tester, finder, GlassHighlights.hoverColor).isNotEmpty;

Future<void> _settle(WidgetTester tester, [int frames = 60]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  test('the hover rule is a pressed wash at half strength on the glow '
      'spring', () {
    expect(GlassHighlights.pressedWash, TouchGlowMotion.washOffset);
    expect(GlassHighlights.hoverGain, 0.5);
    expect(GlassHighlights.hoverColor.a, closeTo(0.025, 1e-6));
    expect(
      GlassHighlights.hoverSpring.response,
      FlexInteraction.glowSpring.response,
    );
    expect(
      GlassHighlights.hoverSpring.resolve(reduceMotion: true).isImmediate,
      isTrue,
    );
  });

  test("the ring's color is Cupertino's", () {
    final ring = GlassHighlights.ringColor(
      null,
      const Color(0xFF007AFF),
      highContrast: false,
    );
    final hsl = HSLColor.fromColor(ring);
    expect(hsl.alpha, closeTo(0.8, 1e-3));
    expect(hsl.lightness, closeTo(0.69, 1e-2));
    expect(hsl.saturation, closeTo(0.835, 1e-2));
    expect(hsl.hue, closeTo(211, 1));
    const given = Color(0x80FF0000);
    expect(
      GlassHighlights.ringColor(given, ring, highContrast: false),
      given,
    );
    expect(
      GlassHighlights.ringColor(given, ring, highContrast: true).a,
      1,
    );
  });

  group('the flat renderer', () {
    const renderer = FlatGlassRenderer();

    testWidgets('a focused body fills the ring outside its shape', (
      tester,
    ) async {
      final states = WidgetStatesController({WidgetState.focused});
      addTearDown(states.dispose);
      await tester.pumpWidget(_app(renderer, _surface(states)));
      final ring = _rings(tester, find.byType(GlassSurface)).single;
      for (final outside in [
        Offset(_body.width + 1.75, _body.height / 2),
        Offset(_body.width / 2, -1.75),
        Offset(-1.75, _body.height / 2),
      ]) {
        expect(ring.contains(outside), isTrue, reason: '$outside');
      }
      for (final off in [
        Offset(_body.width / 2, _body.height / 2),
        Offset(_body.width - 2, _body.height / 2),
        Offset(_body.width + 4, _body.height / 2),
      ]) {
        expect(ring.contains(off), isFalse, reason: '$off');
      }
    });

    testWidgets('the ring follows a moving, stretched frame without a '
        'rebuild', (tester) async {
      final states = WidgetStatesController({WidgetState.focused});
      addTearDown(states.dispose);
      final x = MotionValue<double>(0);
      final frame = MotionSelection(
        () => GlassFrame(
          rect: Rect.fromLTWH(x.value, 0, _body.width, _body.height),
          scaleX: 1.2,
        ),
      );
      await tester.pumpWidget(_app(renderer, _surface(states, frame: frame)));
      final built = tester.state(find.byType(GlassSurface));
      x.snap(x.clock.now, 30);
      await tester.pump();
      expect(tester.state(find.byType(GlassSurface)), same(built));
      final right = 30 + _body.width / 2 + _body.width * 0.6;
      final ring = _rings(tester, find.byType(GlassSurface)).single;
      expect(ring.contains(Offset(right + 1.75, _body.height / 2)), isTrue);
      expect(
        ring.contains(Offset(_body.width + 1.75, _body.height / 2)),
        isFalse,
      );
    });

    testWidgets('a transparent focus color draws no ring', (tester) async {
      final states = WidgetStatesController({WidgetState.focused});
      addTearDown(states.dispose);
      const none = Color(0x00000000);
      await tester.pumpWidget(
        _app(renderer, _surface(states, focusColor: none)),
      );
      final surface = find.byType(GlassSurface);
      expect(_rings(tester, surface), isEmpty);
      expect(_filled(tester, surface, none), isEmpty);
    });

    testWidgets('a hovered body takes the wash', (tester) async {
      final states = WidgetStatesController({WidgetState.hovered});
      addTearDown(states.dispose);
      await tester.pumpWidget(_app(renderer, _surface(states)));
      await _settle(tester);
      expect(_hovers(tester, find.byType(GlassSurface)), isTrue);
      states.update(WidgetState.hovered, false);
      await _settle(tester);
      expect(_hovers(tester, find.byType(GlassSurface)), isFalse);
    });
  });

  for (final renderer in const [
    FlatGlassRenderer(),
    LiquidGlassRenderer(),
    FakeGlassRenderer(),
  ]) {
    group('${renderer.runtimeType}', () {
      final outside = Offset(_body.width + 1.75, _body.height / 2);

      testWidgets('draws the ring outside a focused body only', (
        tester,
      ) async {
        final states = WidgetStatesController();
        addTearDown(states.dispose);
        await tester.pumpWidget(_app(renderer, _surface(states)));
        expect(_blue(await _pixel(tester, outside)), isFalse);
        states.update(WidgetState.focused, true);
        await tester.pump();
        expect(_blue(await _pixel(tester, outside)), isTrue);
        expect(
          _blue(await _pixel(tester, Offset(_body.width / 2, 22))),
          isFalse,
        );
        states.update(WidgetState.focused, false);
        await tester.pump();
        expect(_blue(await _pixel(tester, outside)), isFalse);
      });

      testWidgets('the ring follows a moving frame', (tester) async {
        final states = WidgetStatesController({WidgetState.focused});
        addTearDown(states.dispose);
        final x = MotionValue<double>(0);
        final frame = MotionSelection(
          () => GlassFrame(
            rect: Rect.fromLTWH(x.value, 0, _body.width, _body.height),
          ),
        );
        await tester.pumpWidget(_app(renderer, _surface(states, frame: frame)));
        expect(_blue(await _pixel(tester, outside)), isTrue);
        x.snap(x.clock.now, 30);
        await tester.pump();
        expect(_blue(await _pixel(tester, outside)), isFalse);
        expect(_blue(await _pixel(tester, outside.translate(30, 0))), isTrue);
      });

      testWidgets('Increase Contrast draws an opaque ring', (tester) async {
        final states = WidgetStatesController({WidgetState.focused});
        addTearDown(states.dispose);
        await tester.pumpWidget(
          _app(renderer, _surface(states), highContrast: true),
        );
        expect(_box(tester).focusColor.a, 1);
        expect(_near(_box(tester).focusColor, _ring), isFalse);
      });

      testWidgets('hover eases in and out', (tester) async {
        final states = WidgetStatesController();
        addTearDown(states.dispose);
        await tester.pumpWidget(_app(renderer, _surface(states)));
        final highlight = _box(tester).highlight;
        states.update(WidgetState.hovered, true);
        await tester.pump(_frame);
        await tester.pump(_frame);
        expect(highlight.hovered, inExclusiveRange(0, 0.9));
        await _settle(tester);
        expect(highlight.hovered, closeTo(1, 1e-3));
        states.update(WidgetState.hovered, false);
        await tester.pump(_frame);
        await tester.pump(_frame);
        expect(highlight.hovered, inExclusiveRange(0.1, 1));
        await _settle(tester);
        expect(highlight.hovered, 0);
      });

      testWidgets('under Reduce Motion hover switches at once', (
        tester,
      ) async {
        final states = WidgetStatesController();
        addTearDown(states.dispose);
        await tester.pumpWidget(
          _app(renderer, _surface(states), reduceMotion: true),
        );
        states.update(WidgetState.hovered, true);
        await tester.pump(_frame);
        expect(_box(tester).highlight.hovered, 1);
        states.update(WidgetState.hovered, false);
        await tester.pump(_frame);
        expect(_box(tester).highlight.hovered, 0);
      });
    });
  }

  testWidgets('a body without states paints exactly as before', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const FlatGlassRenderer(),
        SizedBox.fromSize(
          size: _body,
          child: const GlassSurface(child: SizedBox.expand()),
        ),
      ),
    );
    expect(find.byType(GlassHighlightBox), findsNothing);
  });
}
