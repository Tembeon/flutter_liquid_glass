// Run with `flutter test --enable-impeller --enable-flutter-gpu`; glass is fake
// otherwise and the test skips.
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_test/liquid_glass_test.dart';

const _frame = Duration(milliseconds: 16);

class _Page extends StatelessWidget {
  const _Page(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(title: Text(name)),
    child: ListView(
      children: [
        for (var i = 0; i < 40; i++)
          Container(
            height: 60,
            color: Color(0xFF000000 | (i * 0x3B5D97 & 0xFFFFFF)),
          ),
      ],
    ),
  );
}

Future<void> _pumpScaffold(
  WidgetTester tester,
  GlassTabController controller,
  Size size,
) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: 32 * 2, bottom: 20 * 2);
  addTearDown(tester.view.reset);
  glassReadsCopies = true;
  addTearDown(() => glassReadsCopies = false);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: GlassScope(
        renderer: const LiquidGlassRenderer(),
        child: GlassTabScaffold(
          controller: controller,
          action: GlassTabBarAction(
            icon: const SizedBox.square(dimension: 20),
            semanticLabel: 'Add',
            onPressed: () {},
          ),
          tabs: [
            for (final name in const ['One', 'Two', 'Three'])
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: Text(name),
                builder: (context) => _Page(name),
              ),
          ],
        ),
      ),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  // The bar and the sidebar at rest read one copy of the screen, the sidebar
  // a second for its hide button on its glass; while the glass morphs the
  // fading action circle reads a third.
  testWidgets('the bar at the top of an iPad, the sidebar and the glass '
      'morphing between them take what was reviewed', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pumpScaffold(tester, controller, const Size(1032, 1376));
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(1),
      passes: lessThanOrEqualTo(3),
    );

    controller.sidebarShown = true;
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(_frame);
    }
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(3),
      passes: lessThanOrEqualTo(18),
    );

    for (var i = 0; i < 90; i++) {
      await tester.pump(_frame);
    }
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(2),
      passes: lessThanOrEqualTo(13),
    );
    // Test fonts are wider than any real one and overflow a row.
    tester.takeException();
  }, skip: !ui.ImageFilter.isShaderFilterSupported);

  // A hand on the sidebar's edge moves the side alone: the bar at the top
  // does not mount, and the sidebar reads what it reads at rest, its
  // content following. The rail reads as the sidebar does.
  testWidgets('a drag of the edge of the sidebar and the rail take what the '
      'sidebar at rest takes', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pumpScaffold(tester, controller, const Size(1210, 834));
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(2),
      passes: lessThanOrEqualTo(13),
    );

    final hand = await tester.startGesture(const Offset(280, 400));
    await hand.moveBy(const Offset(41, 0));
    await tester.pump(_frame);
    await hand.moveBy(const Offset(20, 0));
    await tester.pump(_frame);
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(2),
      passes: lessThanOrEqualTo(13),
    );

    await hand.moveBy(const Offset(-200, 0));
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(controller.sidebarRail, isTrue);
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(2),
      passes: lessThanOrEqualTo(13),
    );
    await hand.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    await expectGlassBudget(
      tester,
      reads: lessThanOrEqualTo(2),
      passes: lessThanOrEqualTo(13),
    );
    tester.takeException();
  }, skip: !ui.ImageFilter.isShaderFilterSupported);
}
