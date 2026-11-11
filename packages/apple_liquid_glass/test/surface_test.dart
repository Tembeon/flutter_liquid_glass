import 'dart:typed_data';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/foundation/glass.dart';
import 'package:apple_liquid_glass/src/liquid/adaptive.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:apple_liquid_glass/src/surfaces/flat.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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
    final outline = GlassShape.capsule.pathIn(
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

  for (final renderer in const [
    GlassRenderer.flat(),
    GlassRenderer.liquid(),
  ]) {
    testWidgets('${renderer.runtimeType}: a live body smaller than its box '
        'draws its content centered on the body', (tester) async {
      const body = Rect.fromLTWH(2, 2, 37, 24);
      await tester.pumpWidget(
        _app(
          renderer,
          SizedBox(
            width: 63,
            height: 28,
            child: GlassSurface.live(
              frame: MotionSelection(() => const GlassFrame(rect: body)),
              child: const Center(
                child: SizedBox.square(dimension: 10, key: Key('content')),
              ),
            ),
          ),
        ),
      );
      final box = tester.getTopLeft(find.byType(GlassSurface));
      expect(
        tester.getCenter(find.byKey(const Key('content'))),
        offsetMoreOrLessEquals(box + body.center),
      );
    });
  }

  group('flat', () {
    testWidgets('a live surface repaints for a frame and never rebuilds', (
      tester,
    ) async {
      final frames = _Frames(const GlassFrame());
      final builds = <int>[];
      await tester.pumpWidget(
        _app(
          const GlassRenderer.flat(),
          GlassSurface.live(frame: frames.selection, child: _Counted(builds)),
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
      await tester.pump();
      expect(builds, [0]);
      expect(
        body,
        paints
          ..rsuperellipse(color: const Color(0x1A000000))
          ..rsuperellipse(color: const Color(0xD9FFFFFF)),
      );
    });

    test('a track has a fill only; a tint, then the scheme, fills the '
        'body', () {
      const light = GlassTraits();
      const dark = GlassTraits(brightness: .dark);
      expect(
        FlatGlassLook.of(GlassRole.track, const Glass.regular(), light).fill,
        isSameColorAs(const Color(0x33787880)),
      );
      expect(
        FlatGlassLook.of(
          GlassRole.track,
          const Glass.regular(),
          const GlassTraits(highContrast: true),
        ).fill,
        isSameColorAs(const Color(0x47787880)),
      );
      final tinted = FlatGlassLook.of(
        GlassRole.control,
        const Glass.regular(tint: Color(0xFF0088FF)),
        dark,
        scheme: const GlassColorScheme(
          surfaces: {GlassRole.control: Color(0xFF123456)},
        ),
      );
      expect(tinted.fill, const Color(0xFF0088FF));
      expect(tinted.shadow, isSameColorAs(const Color(0x40000000)));
      final bar = FlatGlassLook.of(
        GlassRole.bar,
        const Glass.regular(),
        light,
        scheme: const GlassColorScheme(
          surfaces: {GlassRole.bar: Color(0xFF123456)},
        ),
      );
      expect(bar.fill, const Color(0xFF123456));
      expect(bar.rim, isSameColorAs(const Color(0x1F000000)));
      expect(bar.shadow, isNull);
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

    testWidgets('a resting lens or knob and a track draw flat', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSurface(
                role: GlassRole.lens,
                child: SizedBox(width: 60, height: 30),
              ),
              GlassSurface(
                role: GlassRole.track,
                child: SizedBox(width: 60, height: 30),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(LiquidGlass), findsNothing);
      expect(
        tester.allRenderObjects.whereType<RenderFlatGlass>().toSet(),
        hasLength(2),
      );
    });

    testWidgets('glass takes the Liquid Glass slider from the traits', (
      tester,
    ) async {
      for (final glass in [const Glass.regular(), const Glass.clear()]) {
        await tester.pumpWidget(
          _app(
            const GlassRenderer.liquid(),
            GlassTraitsOverride(
              glassTintAmount: 0.6,
              child: GlassSurface(
                glass: glass,
                child: const SizedBox(width: 60, height: 30),
              ),
            ),
          ),
        );
        final settings = tester
            .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
            .live!
            .value
            .settings;
        expect(settings.tintAmount, 0.6, reason: '$glass');
      }
    });

    testWidgets('a lifted lens shows what is under it smaller, by the '
        'measured amount of its control', (tester) async {
      for (final (part, shrink, rim) in [
        (GlassPart.tabBarLens, 0.16, 0.75),
        (null, 0.20, 1.0),
        (GlassPart.knob, 0.25, 1.0),
        (GlassPart.thumb, 0.0, 0.0),
      ]) {
        await tester.pumpWidget(
          _app(
            const GlassRenderer.liquid(),
            GlassSurface.live(
              role: GlassRole.lens,
              part: part,
              frame: MotionSelection(() => const GlassFrame(lift: 1)),
              child: const SizedBox(width: 60, height: 30),
            ),
          ),
        );
        final settings = tester
            .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
            .live!
            .value
            .settings;
        expect(
          settings.backdropShrink,
          moreOrLessEquals(shrink),
          reason: '$part',
        );
        expect(settings.backdropShrinkRim, rim, reason: '$part');
      }
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
      final frames = _Frames(const GlassFrame());
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          GlassGroup(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlassSurface(child: SizedBox(width: 44, height: 44)),
                GlassSurface.live(
                  frame: frames.selection,
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
      await tester.pump();
      final lit = glow()!;
      expect(lit.bounds, const Rect.fromLTWH(44, 0, 100, 44));
      expect(lit.center, const Offset(74, 22));
      expect(lit.wash, 0.04);
      expect(lit.gain, closeTo(0.3 * TouchGlowMotion.spotGain(.light), 1e-9));
      frames.value = const GlassFrame();
      await tester.pump();
      expect(glow(), isNull);
    });
  });

  group('liquid settings and rest', () {
    testWidgets('fake glass takes no glow; a lone clear surface and the '
        'dark appearance get their iOS 27 settings', (tester) async {
      final frames = _Frames(const GlassFrame());
      LiquidGlassLayerFrame layer() => tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .live!
          .value;
      await tester.pumpWidget(
        _app(
          const GlassRenderer.fake(),
          GlassSurface.live(
            frame: frames.selection,
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

    testWidgets('a group is clear glass while all its members are', (
      tester,
    ) async {
      LiquidGlassSettings layer() => tester
          .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .live!
          .value
          .settings;
      LiquidGlassSettings scope() => LiquidGlassSettings.of(
        tester.element(find.byType(SizedBox).first),
      );
      Widget group(GlassRenderer renderer, List<Glass> members) => _app(
        renderer,
        GlassGroup(
          merge: const GlassMerge.spacing(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final glass in members)
                GlassSurface(
                  glass: glass,
                  child: const SizedBox(width: 44, height: 44),
                ),
            ],
          ),
        ),
      );
      final clear = LiquidGlassSettings.ios27Clear();
      final regular = LiquidGlassSettings.ios27Regular(brightness: .light);
      for (final renderer in [
        const GlassRenderer.liquid(),
        const GlassRenderer.fake(),
      ]) {
        await tester.pumpWidget(
          group(renderer, const [Glass.clear(), Glass.clear()]),
        );
        expect(layer(), clear, reason: '$renderer');
        await tester.pump();
        expect(scope(), clear, reason: '$renderer');

        await tester.pumpWidget(
          group(renderer, const [Glass.clear(), Glass.regular()]),
        );
        expect(layer(), regular, reason: '$renderer');
        await tester.pump();
        expect(scope(), regular, reason: '$renderer');

        await tester.pumpWidget(group(renderer, const [Glass.clear()]));
        await tester.pump();
        expect(layer(), clear, reason: '$renderer');
        expect(scope(), clear, reason: '$renderer');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a still surface in place of a lifted live one draws at rest', (
      tester,
    ) async {
      final frames = _Frames(
        const GlassFrame(scaleX: 1.2, scaleY: 1.2),
      );
      LiquidGlassShapeFrame shape() =>
          tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value;
      await tester.pumpWidget(
        _app(
          const GlassRenderer.liquid(),
          GlassSurface.live(
            frame: frames.selection,
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

  testWidgets("a frame's opacity fades the glass on both renderers", (
    tester,
  ) async {
    final frames = _Frames(const GlassFrame(opacity: 0.25));
    Widget surface(GlassRenderer renderer) => _app(
      renderer,
      GlassSurface.live(
        frame: frames.selection,
        child: const SizedBox(width: 100, height: 44),
      ),
    );
    await tester.pumpWidget(surface(const GlassRenderer.liquid()));
    final liquid = tester
        .widget<LiquidGlass>(find.byType(LiquidGlass))
        .frame!
        .value;
    expect(liquid.appearance!.visibility, closeTo(0.25, 1e-9));
    await tester.pumpWidget(surface(const GlassRenderer.flat()));
    expect(
      tester.layers.whereType<OpacityLayer>().map((layer) => layer.alpha),
      contains(64),
    );
    frames.value = const GlassFrame();
    await tester.pump();
    expect(
      tester.layers.whereType<OpacityLayer>().map((layer) => layer.alpha),
      isNot(contains(64)),
    );
  });

  testWidgets('an outline body is its path on the flat renderer and its '
      "field in a layer of its own on the liquid one", (tester) async {
    final edge = Path();
    edge.moveTo(0, 0);
    edge.lineTo(100, 0);
    edge.lineTo(100, 44);
    edge.lineTo(50, 60);
    edge.lineTo(0, 44);
    edge.close();
    final field = LiquidGlassField(
      samples: Float32List(2 * 2 * 4),
      cols: 2,
      rows: 2,
      origin: Offset.zero,
      step: 60,
    );
    final frames = _Frames(
      GlassFrame(outline: GlassOutline(edge, field: () => field)),
    );
    Widget surface(GlassRenderer renderer, {bool grouped = false}) {
      final body = GlassSurface.live(
        frame: frames.selection,
        child: const RepaintBoundary(child: SizedBox(width: 100, height: 60)),
      );
      return _app(
        renderer,
        grouped ? GlassGroup(child: body) : body,
      );
    }

    await tester.pumpWidget(surface(const GlassRenderer.flat()));
    final at = tester.getTopLeft(find.byType(GlassSurface));
    final clip = tester.layers.whereType<ClipPathLayer>().single.clipPath!;
    expect(clip.getBounds(), edge.getBounds().shift(at));
    expect(clip.contains(at + const Offset(50, 58)), isTrue);
    expect(clip.contains(at + const Offset(4, 58)), isFalse);
    await tester.pumpWidget(surface(const GlassRenderer.liquid()));
    LiquidGlassLayerFrame layer() => tester
        .widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .live!
        .value;
    expect(layer().field, field);
    expect(
      tester.widget<LiquidGlass>(find.byType(LiquidGlass)).frame!.value.rect,
      const Rect.fromLTWH(0, 0, 100, 60),
    );
    frames.value = const GlassFrame();
    await tester.pump();
    expect(layer().field, isNull);

    frames.value = GlassFrame(outline: GlassOutline(edge));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(surface(const GlassRenderer.liquid()));
    expect(
      find.byType(LiquidGlass),
      findsNothing,
      reason: 'an outline without a field draws flat',
    );
    frames.value = GlassFrame(outline: GlassOutline(edge, field: () => field));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      surface(const GlassRenderer.liquid(), grouped: true),
    );
    expect(
      find.byType(LiquidGlass),
      findsNothing,
      reason: 'a shared layer has no field for one member',
    );
  });

  testWidgets('flat content reports where it is drawn', (tester) async {
    final frames = _Frames(const GlassFrame());
    const key = Key('content');
    await tester.pumpWidget(
      _app(
        const GlassRenderer.flat(),
        GlassSurface.live(
          frame: frames.selection,
          child: const SizedBox(key: key, width: 100, height: 44),
        ),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    final rest = box.localToGlobal(Offset.zero);
    frames.value = const GlassFrame(rect: Rect.fromLTWH(10, 0, 100, 44));
    await tester.pump();
    expect(box.localToGlobal(Offset.zero), rest + const Offset(10, 0));
  });

  group('theme', () {
    testWidgets('a renderer switch rebuilds surfaces and keeps their '
        "content's state", (tester) async {
      final builds = <int>[];
      final frames = _Frames(const GlassFrame());
      Widget surface(GlassRenderer renderer) => _app(
        renderer,
        GlassSurface.live(frame: frames.selection, child: _Counted(builds)),
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

    testWidgets('adaptive draws what GlassRenderer.precache found from its '
        'first frame', (tester) async {
      AdaptiveGlassRenderer.debugReset();
      addTearDown(AdaptiveGlassRenderer.debugReset);
      await tester.runAsync(GlassRenderer.precache);
      final support = (await tester.runAsync(LiquidGlass.precache))!;
      await tester.pumpWidget(
        _app(
          const GlassRenderer.adaptive(
            capable: GlassRenderer.liquid(),
            fallback: GlassRenderer.flat(),
          ),
          const GlassSurface(child: SizedBox(width: 100, height: 44)),
        ),
      );
      expect(
        find.byType(LiquidGlass),
        support.deviceClass == LiquidGlassDeviceClass.capable
            ? findsOneWidget
            : findsNothing,
      );
    });
  });

  testWidgets('a clip follows the frames of its glass without a rebuild', (
    tester,
  ) async {
    final frames = _Frames(
      const GlassFrame(rect: Rect.fromLTWH(10, 0, 40, 20)),
    );
    final builds = <int>[];
    await tester.pumpWidget(
      _app(
        const GlassRenderer.flat(),
        GlassClip.live(frame: frames.selection, child: _Counted(builds)),
      ),
    );
    final box = tester.renderObject<RenderClipPath>(find.byType(ClipPath));
    Rect clip() => box.clipper!.getClip(box.size).getBounds();
    expect(clip(), const Rect.fromLTWH(10, 0, 40, 20));
    frames.value = const GlassFrame(
      rect: Rect.fromLTWH(10, 0, 40, 20),
      scaleX: 2,
    );
    await tester.pump();
    expect(clip(), const Rect.fromLTWH(-10, 0, 80, 20));
    expect(builds, [0]);
  });

  test('a clip of a shape is the shape the glass draws', () {
    const shapes = [
      GlassShape.superellipse(12),
      GlassShape.roundedRect(12),
      GlassShape.oval(),
    ];
    final clips = [
      for (final shape in shapes)
        GlassClip(shape: shape).build(_NoContext()).runtimeType,
    ];
    expect(clips, [ClipRSuperellipse, ClipRRect, ClipOval]);
  });
}

final class _NoContext extends Fake implements BuildContext {}

/// Frames a test writes; the surface follows them as a selection.
final class _Frames {
  _Frames(this._frame);

  GlassFrame _frame;
  final _version = MotionValue<double>(0);

  late final MotionSelection<GlassFrame> selection = MotionSelection(() {
    _version.value;
    return _frame;
  });

  GlassFrame get value => _frame;

  set value(GlassFrame frame) {
    _frame = frame;
    _version.snap(MotionClock.instance.now, _version.value + 1);
  }
}
