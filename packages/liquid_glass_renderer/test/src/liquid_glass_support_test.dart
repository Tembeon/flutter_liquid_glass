import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

Widget _glass() => const Directionality(
  textDirection: TextDirection.ltr,
  child: LiquidGlassLayer(
    child: Center(
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(radius: 20),
        child: SizedBox.square(dimension: 100),
      ),
    ),
  ),
);

bool _drawsReal(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().isNotEmpty;

bool _drawsFake(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderConsolidatedFakeGlassLayer>()
    .isNotEmpty;

void main() {
  tearDown(() => LiquidGlass.debugOverrideSupport(null));

  testWidgets('precache says full glass draws, and on what GPU', (
    tester,
  ) async {
    final support = (await tester.runAsync(LiquidGlass.precache))!;
    expect(support.available, isTrue, reason: '${support.unavailableReason}');
    expect(support.unavailableReason, isNull);
    expect(
      support.deviceClass,
      isNot(
        anyOf(
          LiquidGlassDeviceClass.unknown,
          LiquidGlassDeviceClass.noShaderFilters,
        ),
      ),
    );
    expect(await tester.runAsync(LiquidGlass.precache), support);
    expect(LiquidGlass.support.value, support);
  }, skip: skipProperGlassTests);

  test('pending is not available and equals only itself', () {
    const pending = LiquidGlassSupport.pending;
    expect(pending.isPending, isTrue);
    expect(pending.available, isFalse);
    expect(pending.deviceClass, LiquidGlassDeviceClass.unknown);
    expect(
      pending,
      isNot(
        LiquidGlassSupport(
          deviceClass: pending.deviceClass,
          unavailableReason: pending.unavailableReason,
        ),
      ),
    );
  });

  test('a load under way when the support is overridden leaves the '
      'override, and what it found comes back after it', () async {
    LiquidGlass.debugOverrideSupport(LiquidGlassSupport.pending);
    final loading = LiquidGlass.precache();
    const unavailable = LiquidGlassSupport(
      deviceClass: LiquidGlassDeviceClass.unknown,
      unavailableReason: 'For the test.',
    );
    LiquidGlass.debugOverrideSupport(unavailable);
    final found = await loading;
    expect(found.available, isTrue);
    expect(LiquidGlass.support.value, unavailable);
    LiquidGlass.debugOverrideSupport(null);
    expect(LiquidGlass.support.value, found);
  }, skip: skipProperGlassTests);

  testWidgets('a layer draws fake glass while full glass loads and real '
      'glass once it has, never a frame without glass', (tester) async {
    LiquidGlass.debugOverrideSupport(LiquidGlassSupport.pending);
    final supports = <LiquidGlassSupport>[];
    void listen() => supports.add(LiquidGlass.support.value);
    LiquidGlass.support.addListener(listen);
    addTearDown(() => LiquidGlass.support.removeListener(listen));

    await tester.pumpWidget(_glass());
    expect(_drawsFake(tester), isTrue);
    expect(_drawsReal(tester), isFalse);
    for (var frame = 0; frame < 4 && !_drawsReal(tester); frame++) {
      await tester.pump();
      expect(
        _drawsFake(tester) || _drawsReal(tester),
        isTrue,
        reason: 'frame $frame draws no glass',
      );
    }
    expect(_drawsReal(tester), isTrue);
    expect(_drawsFake(tester), isFalse);
    expect(supports, [
      isA<LiquidGlassSupport>().having((s) => s.available, 'available', isTrue),
    ]);
  }, skip: skipProperGlassTests);

  testWidgets('a layer draws fake glass where full glass is unavailable, '
      'and real glass from the frame it is', (tester) async {
    LiquidGlass.debugOverrideSupport(
      const LiquidGlassSupport(
        deviceClass: LiquidGlassDeviceClass.unknown,
        unavailableReason: 'For the test.',
      ),
    );
    await tester.pumpWidget(_glass());
    await tester.pump();
    expect(_drawsFake(tester), isTrue);
    expect(_drawsReal(tester), isFalse);

    LiquidGlass.debugOverrideSupport(null);
    await tester.pump();
    expect(_drawsReal(tester), isTrue);
    expect(_drawsFake(tester), isFalse);
  }, skip: skipProperGlassTests);
}
