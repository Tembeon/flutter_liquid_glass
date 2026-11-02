import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('screen');

Widget _scene({double shift = 0}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF1E3A8A),
                  Color(0xFFF59E0B),
                  Color(0xFF10B981),
                ],
                begin: Alignment(-1 + shift, -1),
                end: Alignment.bottomRight,
                tileMode: TileMode.mirror,
              ),
            ),
            child: const Center(
              child: Text(
                'Page under the glass',
                style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: const Rect.fromLTWH(40, 70, 180, 60),
          child: LiquidGlassLayer(
            fake: true,
            settings: LiquidGlassSettings.ios27RegularLight().copyWith(
              frost: 6,
            ),
            child: const LiquidGlass(
              shape: LiquidRoundedSuperellipse(borderRadius: 30),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ],
    ),
  ),
);

RenderConsolidatedFakeGlassLayer _glass(WidgetTester tester) =>
    tester.renderObject<RenderConsolidatedFakeGlassLayer>(
      find.byType(ConsolidatedFakeGlassLayer),
    );

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  tearDown(() {
    BackdropUnderlay.debugEnabledOverride = null;
  });

  testWidgets('grouped fake glass over a copy draws what reading the '
      'backdrop draws', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(LiquidGlass.precache);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    BackdropUnderlay.debugEnabledOverride = false;
    await tester.pumpWidget(_scene());
    await tester.pump();
    final reading = await _pixels(tester);
    expect(_glass(tester).debugDrewOverCopy, isFalse);

    BackdropUnderlay.debugEnabledOverride = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(shift: 0.3));
    await tester.pumpWidget(_scene());
    expect(_glass(tester).debugDrewOverCopy, isTrue);
    expect(
      tester.layers.whereType<BackdropFilterLayer>().where(
        (layer) => layer is! OpacitySeedLayer,
      ),
      isEmpty,
    );
    final copied = await _pixels(tester);
    // NEAR: a blur Impeller downsamples takes other taps over a copy than
    // over the whole backdrop; at 2 px of frost the two do not differ.
    expect(_difference(reading, copied), lessThanOrEqualTo(20));
  }, skip: skipProperGlassTests);
}
