// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass is
// drawn as on a device, and fake glass otherwise.
@Tags(['composer'])
library;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_test/liquid_glass_test.dart';

import '../shared.dart';

const _settings = LiquidGlassSettings.ios27Regular();

const _background = Color(0xFF204060);

Widget _glass() => const LiquidGlassLayer(
  settings: _settings,
  child: LiquidGlass(
    shape: LiquidRoundedSuperellipse(radius: 22),
    child: SizedBox(width: 44, height: 44),
  ),
);

// A box in a boundary of its own: what a layer holds reaches as far as the
// canvas of the boundary its pictures were drawn in.
Widget _box() => const RepaintBoundary(
  child: SizedBox(
    width: 60,
    height: 40,
    child: ColoredBox(color: Color(0xFFF0A030)),
  ),
);

// A page of stripes with [foreign] at [at] in a layer of [type], and glass
// at the bottom.
Widget _page({
  required Widget foreign,
  Offset at = const Offset(40, 40),
  _Type type = _Type.atPaint,
}) => RepaintBoundary(
  key: const Key('page'),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: ColoredBox(
        color: _background,
        child: Stack(
          children: [
            for (var i = 0; i < 12; i++)
              Positioned(
                left: 20,
                top: 20.0 + i * 60,
                width: 300,
                height: 30,
                child: ColoredBox(color: Color(0xFF000000 | (i * 0x151515))),
              ),
            Positioned(
              left: at.dx,
              top: at.dy,
              child: _Foreign(type: type, child: foreign),
            ),
            Positioned(left: 20, top: 700, child: _glass()),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _screen(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(page);
  await tester.pump();
}

Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('page')),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final data = (await tester.runAsync(image.toByteData))!;
  final i = (at.dy.round() * image.width + at.dx.round()) * 4;
  return Color.fromARGB(
    255,
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  setUp(() => glassReadsCopies = true);
  tearDown(() => glassReadsCopies = false);

  group('a container of a type nobody registered', () {
    testWidgets('keeps glass away from what it holds on its copy', (
      tester,
    ) async {
      await _screen(tester, _page(foreign: _box()));
      final report = await expectGlassBudget(tester, backdropReads: 0);
      expect(report.reads, isNotEmpty);
    }, skip: skipProperGlassTests);

    testWidgets('makes glass over what it holds read the backdrop, from the '
        'frame it moves under the glass', (tester) async {
      await _screen(tester, _page(foreign: _box()));
      await expectGlassBudget(tester, backdropReads: 0);
      await tester.pumpWidget(
        _page(foreign: _box(), at: const Offset(30, 690)),
      );
      await expectGlassBudget(tester, backdropReads: 1);
    }, skip: skipProperGlassTests);

    testWidgets('draws the glass inside it, over the backdrop', (tester) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      await tester.runAsync(precacheLiquidGlass);
      await _screen(tester, _page(foreign: _glass()));
      final report = await expectGlassBudget(tester, backdropReads: 1);
      expect(report.reads, hasLength(2));
      expect(await _pixel(tester, const Offset(62, 62)), isNot(_background));
    }, skip: skipProperGlassTests);

    testWidgets('makes glass over the glass inside it read the backdrop', (
      tester,
    ) async {
      await _screen(
        tester,
        _page(foreign: _glass(), at: const Offset(30, 690)),
      );
      await expectGlassBudget(tester, reads: 2, backdropReads: 2);
    }, skip: skipProperGlassTests);

    testWidgets('reads the backdrop under all glass on the first frame of its '
        'type', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      GlassFrameReport? first;
      void note(GlassFrameReport report) => first ??= report;
      GlassFrameReports.addListener(note);
      addTearDown(() => GlassFrameReports.removeListener(note));
      await tester.pumpWidget(_page(foreign: _box(), type: _Type.firstSeen));
      expect(first!.backdropReads, 1);
    }, skip: skipProperGlassTests);

    testWidgets('that places what it holds while the scene is built keeps '
        'all glass on the backdrop', (tester) async {
      await _screen(tester, _page(foreign: _box(), type: _Type.atScene));
      for (var i = 0; i < 3; i++) {
        await expectGlassBudget(tester, backdropReads: 1);
      }
    }, skip: skipProperGlassTests);
  });
}

enum _Type { atPaint, firstSeen, atScene }

// Places its children by an offset it holds, as a package's leader does.
class _AtPaintLayer extends ContainerLayer {
  Offset offset = Offset.zero;

  @override
  void applyTransform(Layer? child, Matrix4 transform) {
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    builder.pushOffset(offset.dx, offset.dy);
    addChildrenToScene(builder);
    builder.pop();
  }
}

// A type no other test paints.
class _FirstSeenLayer extends _AtPaintLayer {}

// Places its children while the scene is built, as a package's follower
// does: what it tells of its place before then is the last scene's.
class _AtSceneLayer extends _AtPaintLayer {
  Offset _placed = const Offset(-1000, -1000);

  @override
  void applyTransform(Layer? child, Matrix4 transform) {
    transform.translateByDouble(_placed.dx, _placed.dy, 0, 1);
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    _placed = offset;
    super.addToScene(builder);
  }
}

class _Foreign extends SingleChildRenderObjectWidget {
  const _Foreign({required this.type, super.child});

  final _Type type;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderForeign(type);
}

class _RenderForeign extends RenderProxyBox {
  _RenderForeign(this.type);

  final _Type type;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer =
        ((this.layer as _AtPaintLayer?) ??
              switch (type) {
                _Type.atPaint => _AtPaintLayer(),
                _Type.firstSeen => _FirstSeenLayer(),
                _Type.atScene => _AtSceneLayer(),
              })
          ..offset = offset
          ..removeAllChildren();
    this.layer = layer;
    context.pushLayer(
      layer,
      (context, _) => super.paint(context, Offset.zero),
      Offset.zero,
    );
  }
}
