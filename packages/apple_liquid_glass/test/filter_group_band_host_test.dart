@Tags(['macos_pixels'])
library;

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the band and
// the glass over it are drawn by runtime effects, which only Impeller draws.
//
// A scroll edge and the button over it draw in the button's filter as they
// draw in filters of their own.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';

const _viewSize = Size(300, 400);

class _CapturingView extends TestFlutterView {
  _CapturingView(WidgetTester tester)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      ) {
    physicalSize = _viewSize * 2;
    devicePixelRatio = 2;
  }

  ui.Image? last;

  @override
  void render(ui.Scene scene, {Size? size}) {
    last?.dispose();
    last = scene.toImageSync(
      _viewSize.width.toInt() * 2,
      _viewSize.height.toInt() * 2,
    );
  }
}

Widget _page(
  _CapturingView view,
  ScrollController controller, {
  required bool hard,
}) => View(
  view: view,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.liquid()),
      child: Stack(
        children: [
          GlassPageScaffold(
            backgroundColor: const Color(0xFFFFFFFF),
            navigationBar: const PreferredSize(
              preferredSize: Size.fromHeight(60),
              child: SizedBox(height: 60),
            ),
            child: GlassContentScroll(
              edgeEffects: GlassScrollEdgeEffects(
                top: hard
                    ? GlassScrollEdgeEffect.hard
                    : GlassScrollEdgeEffect.soft,
              ),
              child: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 40; i++)
                    Container(
                      height: 30,
                      color: Color(0xFF000000 | (i * 2654435761) & 0xFFFFFF),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 10,
            width: 44,
            height: 44,
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight(),
              child: const LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 22),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<(Uint8List, bool)> _draw(
  WidgetTester tester,
  _CapturingView view, {
  required bool hard,
  required bool groups,
  bool held = false,
}) async {
  GlassComposer.debugPolicy = Policy(bands: groups);
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    View(view: view, child: const SizedBox()),
    wrapWithView: false,
  );
  await tester.pumpWidget(
    _page(view, controller, hard: hard),
    wrapWithView: false,
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
  controller.jumpTo(200);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final band = tester.layers.whereType<LiquidGlassBackdropFilterLayer>().single;
  if (held) {
    // A read that stood still long enough reads an image.
    for (var i = 0; i < 600 && band.debugPage == null; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(band.debugPage, isNotNull);
  }
  final merged = band.drawsGroup;
  final data = (await tester.runAsync(view.last!.toByteData))!;
  return (data.buffer.asUint8List(), merged);
}

void main() {
  setUp(() => GlassCopies.debugEnabledOverride = true);
  tearDown(() {
    GlassCopies.debugEnabledOverride = null;
    GlassComposer.debugPolicy = const Policy();
  });

  for (final hard in [true, false]) {
    testWidgets('a ${hard ? 'hard' : 'soft'} edge joins the glass over it', (
      tester,
    ) async {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      final view = _CapturingView(tester);
      final (alone, mergedAlone) = await _draw(
        tester,
        view,
        hard: hard,
        groups: false,
      );
      final (merged, mergedOn) = await _draw(
        tester,
        view,
        hard: hard,
        groups: true,
      );
      expect(mergedAlone, isFalse);
      expect(mergedOn, isTrue);
      var sum = 0;
      var most = 0;
      for (var i = 0; i < alone.length; i++) {
        if (i % 4 == 3) continue;
        final delta = (alone[i] - merged[i]).abs();
        sum += delta;
        if (delta > most) most = delta;
      }
      final mean = sum / (alone.length * 3 / 4);
      expect(mean, lessThan(0.5), reason: 'mean $mean, most $most');
    });
  }

  // The glass draws the band's frost and fade for all the band covers, not
  // only under the glass.
  testWidgets('an edge and the glass over it cover the band over an image', (
    tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    final view = _CapturingView(tester);
    final (alone, _) = await _draw(tester, view, hard: false, groups: false);
    final (merged, mergedOn) = await _draw(
      tester,
      view,
      hard: false,
      groups: true,
      held: true,
    );
    expect(mergedOn, isTrue);
    var sum = 0;
    for (var i = 0; i < alone.length; i++) {
      if (i % 4 != 3) sum += (alone[i] - merged[i]).abs();
    }
    final mean = sum / (alone.length * 3 / 4);
    expect(mean, lessThan(2));
  });
}
