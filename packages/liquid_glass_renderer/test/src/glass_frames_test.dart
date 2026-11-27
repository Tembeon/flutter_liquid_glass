import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_frames.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';
import 'package:material_ui/material_ui.dart';

Widget _glass() => const LiquidGlassLayer(
  settings: LiquidGlassSettings.ios27Regular(),
  child: SizedBox(
    width: 120,
    height: 60,
    child: LiquidGlass(
      shape: LiquidRoundedSuperellipse(radius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

List<GlassFrames> _frames() =>
    GlassFrames.debugAllUnder(RendererBinding.instance.rootPipelineOwner);

void main() {
  testWidgets(
    'glass of one view shares one GlassFrames, dropped with the last',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [_glass(), _glass()]),
        ),
      );
      expect(_frames(), hasLength(1));
      final census = _frames().single.census;
      final frames = census.frames;
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(census.frames, frames + 1);
      expect(census.sites, census.frames * 2);

      await tester.pumpWidget(const SizedBox());
      expect(_frames(), isEmpty);
    },
  );

  testWidgets(
    'glass built lazily during layout adopts and drops a GlassFrames',
    (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView.builder(
            controller: controller,
            itemExtent: 100,
            itemCount: 100,
            itemBuilder: (context, index) =>
                index.isEven ? _glass() : const SizedBox.shrink(),
          ),
        ),
      );
      expect(_frames(), hasLength(1));
      controller.jumpTo(5000);
      await tester.pump();
      expect(_frames(), hasLength(1));

      await tester.pumpWidget(const SizedBox());
      expect(_frames(), isEmpty);
    },
  );

  testWidgets('a GlassFrames lives with semantics on', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: _glass()),
    );
    expect(_frames(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(_frames(), isEmpty);
    semantics.dispose();
  });

  testWidgets(
    "the view's glass plans a frame ahead of the scene, and a scene it "
    'did not plan plans its own',
    (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              _glass(),
              RepaintBoundary(
                child: _Recorder(
                  log: log,
                  name: 'outer',
                  child: _Recorder(
                    log: log,
                    name: 'inner',
                    child: const SizedBox.square(dimension: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      log.clear();
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(log, ['outer planned', 'inner planned']);

      log.clear();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byType(_Recorder).first,
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      (await tester.runAsync(boundary.toImage))!.dispose();
      expect(log, ['outer unplanned', 'inner unplanned']);
    },
  );

  testWidgets('a view whose only glass layer a host holds has one GlassFrames '
      'while the host is attached, planned ahead, and none once it detaches', (
    tester,
  ) async {
    final log = <String>[];
    GlassFrames.debugPlannedAlone = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: _Recorder(
            log: log,
            name: 'host',
            hosts: true,
            child: const SizedBox.square(dimension: 20),
          ),
        ),
      ),
    );
    expect(_frames(), hasLength(1));
    final frames = _frames().single;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(_frames().single, same(frames));
    expect(log, isNotEmpty);
    expect(log, everyElement('host planned'));
    expect(GlassFrames.debugPlannedAlone, 0);

    await tester.pumpWidget(const SizedBox());
    expect(_frames(), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('fake glass alone in a view holds a GlassFrames while attached', (
    tester,
  ) async {
    GlassFrames.debugPlannedAlone = 0;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            height: 60,
            child: FakeGlass(
              appearance: LiquidGlassAppearance(
                colorModel: LiquidGlassColorModel.direct(
                  brightness: Brightness.light,
                ),
              ),
              shape: LiquidRoundedSuperellipse(radius: 20),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    expect(_frames(), hasLength(1));
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(GlassFrames.debugPlannedAlone, 0);

    await tester.pumpWidget(const SizedBox());
    expect(_frames(), isEmpty);
  });

  testWidgets('a composed layer in a frame with no registered holder asserts', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: _Recorder(
            log: log,
            name: 'stray',
            child: const SizedBox.square(dimension: 20),
          ),
        ),
      ),
    );
    final error = tester.takeException();
    expect(error, isA<AssertionError>());
    expect(
      '$error',
      allOf(
        contains('_RecordingLayer'),
        contains('LiquidGlassBackdropFilterHost'),
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('each owner gets its own GlassFrames and can be disposed after', () {
    final a = PipelineOwner();
    final b = PipelineOwner();
    final siteA = _Site();
    final siteB = _Site();
    GlassFrames.track(a, siteA);
    GlassFrames.track(b, siteB);
    final all = [
      ...GlassFrames.debugAllUnder(a),
      ...GlassFrames.debugAllUnder(b),
    ];
    expect(all, hasLength(2));
    expect(identical(all.first, all.last), isFalse);

    GlassFrames.untrack(a, siteA);
    GlassFrames.untrack(b, siteB);
    expect(GlassFrames.debugAllUnder(a), isEmpty);
    a.dispose();
    b.dispose();
  });
}

class _Site extends RenderProxyBox with TransformTrackingRenderObjectMixin {
  @override
  void onTransformChanged() {}
}

class _Recorder extends SingleChildRenderObjectWidget {
  const _Recorder({
    required this.log,
    required this.name,
    this.hosts = false,
    super.child,
  });

  final List<String> log;
  final String name;
  final bool hosts;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      hosts ? _RenderHostRecorder(log, name) : _RenderRecorder(log, name);
}

class _RenderRecorder extends RenderProxyBox {
  _RenderRecorder(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer =
        (this.layer as _RecordingLayer?) ?? _RecordingLayer(log, name);
    this.layer = layer;
    context.pushLayer(layer, super.paint, offset);
  }
}

class _RenderHostRecorder extends _RenderRecorder
    with LiquidGlassBackdropFilterHost {
  _RenderHostRecorder(super.log, super.name);

  @override
  LiquidGlassBackdropFilterLayer? get backdropFilterLayer =>
      layer as _RecordingLayer?;
}

class _RecordingLayer extends LiquidGlassBackdropFilterLayer {
  _RecordingLayer(this.log, this.name)
    : super(
        filter: const LiquidGlassBackdropFilter.image(
          ColorFilter.mode(Color(0x00000000), BlendMode.dst),
        ),
        clip: const Rect.fromLTWH(0, 0, 20, 20),
      );

  final List<String> log;
  final String name;

  @override
  void updateSubtreeNeedsAddToScene() {
    log.add('$name ${debugPlannedAhead(this) ? 'planned' : 'unplanned'}');
    super.updateSubtreeNeedsAddToScene();
  }
}
