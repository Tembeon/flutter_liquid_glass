import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/motion/touch_glow.dart';
import 'package:apple_liquid_glass/src/renderer/adaptive.dart';
import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(GlassRenderer renderer, Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: GlassTheme(
    data: GlassThemeData(renderer: renderer),
    child: Center(child: child),
  ),
);

class _Counted extends StatefulWidget {
  const _Counted(this.builds);

  final List<int> builds;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  late final int id = widget.builds.length;

  @override
  Widget build(BuildContext context) {
    widget.builds.add(id);
    return const SizedBox(width: 100, height: 44);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  test('a capsule is a stadium in any box', () {
    final outline = GlassFrame.capsule.getOuterPath(
      const Rect.fromLTWH(0, 0, 100, 44),
    );
    expect(outline.contains(const Offset(2, 22)), isTrue);
    expect(outline.contains(const Offset(50, 1)), isTrue);
    expect(outline.contains(const Offset(3, 3)), isFalse);
    expect(outline.getBounds(), const Rect.fromLTWH(0, 0, 100, 44));
  });

  test('a frame draws its content where it draws the body', () {
    const size = Size(100, 40);
    const frame = GlassFrame(
      rect: Rect.fromLTWH(10, 0, 100, 40),
      scaleX: 1.2,
      scaleY: 0.5,
    );
    expect(
      frame.drawnIn(size),
      Rect.fromCenter(center: const Offset(60, 20), width: 120, height: 20),
    );
    final transform = frame.contentTransformIn(size)!;
    expect(
      MatrixUtils.transformRect(transform, Offset.zero & size),
      frame.drawnIn(size),
    );
    expect(const GlassFrame().contentTransformIn(size), isNull);
  });

  group('flat', () {
    testWidgets('a live surface repaints for a frame and never rebuilds', (
      tester,
    ) async {
      final frames = ValueNotifier(const GlassFrame());
      addTearDown(frames.dispose);
      final builds = <int>[];
      await tester.pumpWidget(
        _app(
          const GlassRenderer.flat(),
          GlassSurface.live(frame: frames, child: _Counted(builds)),
        ),
      );
      final body = tester.renderObject<RenderFlatGlass>(
        find.byElementPredicate(
          (element) =>
              element is RenderObjectElement &&
              element.renderObject is RenderFlatGlass,
        ),
      );
      expect(body.debugNeedsPaint, isFalse);
      frames.value = const GlassFrame(scaleX: 1.1, scaleY: 1.1);
      expect(body.debugNeedsPaint, isTrue);
      await tester.pump();
      expect(builds, [0]);
      expect(
        body,
        paints
          ..path(color: const Color(0x1A000000))
          ..path(color: const Color(0xD9FFFFFF)),
      );
    });

    testWidgets('a track has a fill only; a tint fills the body', (
      tester,
    ) async {
      expect(
        FlatGlassLook.of(GlassRole.track, const Glass.regular(), .light),
        const FlatGlassLook(fill: Color(0x33787880)),
      );
      final tinted = FlatGlassLook.of(
        GlassRole.control,
        const Glass.regular(tint: Color(0xFF0088FF)),
        .dark,
      );
      expect(tinted.fill, const Color(0xFF0088FF));
      expect(tinted.shadow, isNotNull);
      expect(
        FlatGlassLook.of(GlassRole.bar, const Glass.regular(), .light).shadow,
        isNull,
      );
    });
  });

  group('liquid', () {
    testWidgets('a lone surface draws on a glass layer of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('a group draws its members on one layer and blends them '
        'when they merge', (tester) async {
      Widget row(GlassMerge merge) => _app(
        const GlassRenderer.liquid(),
        GlassGroup(
          merge: merge,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSurface(child: SizedBox(width: 44, height: 44)),
              GlassSurface(child: SizedBox(width: 44, height: 44)),
            ],
          ),
        ),
      );
      await tester.pumpWidget(row(const GlassMerge.none()));
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNWidgets(2));
      expect(find.byType(LiquidGlassBlendGroup), findsNothing);
      await tester.pumpWidget(row(const GlassMerge.spacing(12)));
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(
        tester
            .widget<LiquidGlassBlendGroup>(find.byType(LiquidGlassBlendGroup))
            .blend,
        12,
      );
    });

    testWidgets('a touch lights the layer, in the layer of its group', (
      tester,
    ) async {
      final frames = ValueNotifier(const GlassFrame());
      addTearDown(frames.dispose);
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          GlassGroup(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlassSurface(child: SizedBox(width: 44, height: 44)),
                GlassSurface.live(
                  frame: frames,
                  child: const SizedBox(width: 100, height: 44),
                ),
              ],
            ),
          ),
        ),
      );
      LiquidGlassGlow? glow() => tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .live!
          .value
          .glow;
      expect(glow(), isNull);
      frames.value = const GlassFrame(
        glow: GlassTouchGlow(
          wash: 0.04,
          center: Offset(30, 22),
          radius: 20,
          spot: 0.3,
        ),
      );
      final lit = glow()!;
      expect(lit.bounds, const Rect.fromLTWH(44, 0, 100, 44));
      expect(lit.center, const Offset(74, 22));
      expect(lit.wash, 0.04);
      expect(lit.gain, closeTo(0.3 * TouchGlowMotion.spotGain(.light), 1e-9));
      frames.value = const GlassFrame();
      expect(glow(), isNull);
    });
  });

  group('liquid settings and rest', () {
    testWidgets('fake glass takes no glow; a lone clear surface and the '
        'dark appearance get their iOS 27 settings', (tester) async {
      final frames = ValueNotifier(const GlassFrame());
      addTearDown(frames.dispose);
      LiquidGlassLayerFrame layer() => tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .live!
          .value;
      await tester.pumpWidget(
        _app(
          const GlassRenderer.fake(),
          GlassSurface.live(
            frame: frames,
            child: const SizedBox(width: 100, height: 44),
          ),
        ),
      );
      frames.value = const GlassFrame(
        glow: GlassTouchGlow(
          wash: 0.04,
          center: Offset(30, 22),
          radius: 20,
          spot: 0.3,
        ),
      );
      await tester.pump();
      expect(layer().glow, isNull);

      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          const GlassSurface(
            glass: Glass.clear(),
            child: SizedBox(width: 100, height: 44),
          ),
        ),
      );
      expect(layer().settings, LiquidGlassSettings.ios27Clear());
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(platformBrightness: .dark),
          child: _app(
            const GlassRenderer.liquid(),
            const GlassSurface(child: SizedBox(width: 100, height: 44)),
          ),
        ),
      );
      expect(
        layer().settings,
        LiquidGlassSettings.ios27Regular(brightness: .dark),
      );
    });

    testWidgets('a still surface in place of a lifted live one draws at rest', (
      tester,
    ) async {
      final frames = ValueNotifier(
        const GlassFrame(scaleX: 1.2, scaleY: 1.2),
      );
      addTearDown(frames.dispose);
      LiquidGlassShapeFrame shape() =>
          tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value;
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          GlassSurface.live(
            frame: frames,
            child: const SizedBox(width: 100, height: 44),
          ),
        ),
      );
      expect(shape().scaleX, 1.2);
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(shape().scaleX, 1);
    });
  });

  testWidgets('flat content reports where it is drawn', (tester) async {
    final frames = ValueNotifier(const GlassFrame());
    addTearDown(frames.dispose);
    const key = Key('content');
    await tester.pumpWidget(
      _app(
        const GlassRenderer.flat(),
        GlassSurface.live(
          frame: frames,
          child: const SizedBox(key: key, width: 100, height: 44),
        ),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    final rest = box.localToGlobal(Offset.zero);
    frames.value = const GlassFrame(rect: Rect.fromLTWH(10, 0, 100, 44));
    expect(box.localToGlobal(Offset.zero), rest + const Offset(10, 0));
  });

  group('theme', () {
    testWidgets('a renderer switch rebuilds surfaces and keeps their '
        "content's state", (tester) async {
      final builds = <int>[];
      final frames = ValueNotifier(const GlassFrame());
      addTearDown(frames.dispose);
      Widget surface(GlassRenderer renderer) => _app(
        renderer,
        GlassSurface.live(frame: frames, child: _Counted(builds)),
      );
      await tester.pumpWidget(surface(const GlassRenderer.flat()));
      expect(find.byType(LiquidGlass), findsNothing);
      await tester.pumpWidget(surface(const GlassRenderer.liquid()));
      expect(find.byType(LiquidGlass), findsOneWidget);
      await tester.pumpWidget(surface(const GlassRenderer.fake()));
      expect(
        tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).fake,
        isTrue,
      );
      expect(builds.toSet(), {0});
    });

    testWidgets('the renderer aspect ignores a theme that keeps it', (
      tester,
    ) async {
      var reads = 0;
      final reader = Builder(
        builder: (context) {
          GlassTheme.rendererOf(context);
          reads++;
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        GlassTheme(data: const GlassThemeData(), child: reader),
      );
      await tester.pumpWidget(
        GlassTheme(
          data: const GlassThemeData(),
          child: reader,
        ),
      );
      expect(reads, 1);
      await tester.pumpWidget(
        GlassTheme(
          data: const GlassThemeData(renderer: GlassRenderer.flat()),
          child: reader,
        ),
      );
      expect(reads, 2);
    });

    testWidgets('adaptive draws the capable renderer until precache answers, '
        'then the one it picks', (tester) async {
      AdaptiveGlassRenderer.debugReset();
      addTearDown(AdaptiveGlassRenderer.debugReset);
      const renderer = GlassRenderer.adaptive(
        capable: GlassRenderer.liquid(),
        fallback: GlassRenderer.flat(),
      );
      await tester.pumpWidget(
        _app(
          renderer,
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(find.byType(LiquidGlass), findsOneWidget);
      final support = (await tester.runAsync(LiquidGlass.precache))!;
      await tester.pump();
      expect(
        find.byType(LiquidGlass),
        support.deviceClass == LiquidGlassDeviceClass.capable
            ? findsOneWidget
            : findsNothing,
      );
    });
  });
}
