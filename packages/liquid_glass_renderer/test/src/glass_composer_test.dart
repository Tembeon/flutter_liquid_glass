import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';

Widget _glass() => LiquidGlassLayer(
  settings: LiquidGlassSettings.ios27RegularLight(),
  child: const SizedBox(
    width: 120,
    height: 60,
    child: LiquidGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

List<GlassComposer> _composers() =>
    GlassComposer.debugAllUnder(RendererBinding.instance.rootPipelineOwner);

void main() {
  testWidgets('glass of one view shares one composer, dropped with the last', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [_glass(), _glass()]),
      ),
    );
    expect(_composers(), hasLength(1));
    final census = _composers().single.census;
    final frames = census.frames;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(census.frames, frames + 1);
    expect(census.sites, census.frames * 2);

    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
  });

  testWidgets('glass built lazily during layout adopts and drops a composer', (
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
    expect(_composers(), hasLength(1));
    controller.jumpTo(5000);
    await tester.pump();
    expect(_composers(), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
  });

  testWidgets('a composer lives with semantics on', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: _glass()),
    );
    expect(_composers(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(_composers(), isEmpty);
    semantics.dispose();
  });

  test('each owner gets its own composer and can be disposed after', () {
    final a = PipelineOwner();
    final b = PipelineOwner();
    final siteA = Object();
    final siteB = Object();
    GlassComposer.track(a, siteA);
    GlassComposer.track(b, siteB);
    final composers = [
      ...GlassComposer.debugAllUnder(a),
      ...GlassComposer.debugAllUnder(b),
    ];
    expect(composers, hasLength(2));
    expect(identical(composers.first, composers.last), isFalse);

    GlassComposer.untrack(a, siteA);
    GlassComposer.untrack(b, siteB);
    expect(GlassComposer.debugAllUnder(a), isEmpty);
    a.dispose();
    b.dispose();
  });
}
