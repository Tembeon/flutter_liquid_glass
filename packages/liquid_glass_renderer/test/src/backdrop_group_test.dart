import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

void main() {
  group('glass reading its backdrop directly', () {
    setUp(() {
      final readsCopies = glassReadsCopies;
      glassReadsCopies = false;
      addTearDown(() => glassReadsCopies = readsCopies);
    });

    Widget glass() => const LiquidGlassLayer(
      child: LiquidGlass(
        shape: LiquidOval(),
        child: SizedBox.square(dimension: 80),
      ),
    );

    BackdropKey? keyOf(WidgetTester tester) => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .last
        .debugBackdropFilterLayer!
        .backdropKey;

    testWidgets('shares the backdrop of the nearest BackdropGroup', (
      tester,
    ) async {
      final first = BackdropKey();
      await tester.pumpWidget(
        CupertinoApp(
          home: BackdropGroup(backdropKey: first, child: glass()),
        ),
      );
      await tester.pumpAndSettle();
      expect(keyOf(tester), same(first));

      final second = BackdropKey();
      await tester.pumpWidget(
        CupertinoApp(
          home: BackdropGroup(backdropKey: second, child: glass()),
        ),
      );
      await tester.pump();
      expect(keyOf(tester), same(second));
    });

    testWidgets('reads a backdrop of its own outside a BackdropGroup', (
      tester,
    ) async {
      await tester.pumpWidget(CupertinoApp(home: glass()));
      await tester.pumpAndSettle();
      expect(keyOf(tester), isNull);
    });
  });

  test("a planned read keeps the backdrop the plan gave it", () {
    final rig = BackdropRig();
    final filter = ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1);
    final planned = BackdropKey();
    rig
      ..bindFilter(filter)
      ..showBackdrop(planned)
      ..bindFilter(filter);
    expect(rig.filterLayer!.backdropKey, same(planned));

    final group = BackdropKey();
    rig.bindFilter(filter, direct: true, group: group);
    expect(rig.filterLayer!.backdropKey, same(group));
  });
}
