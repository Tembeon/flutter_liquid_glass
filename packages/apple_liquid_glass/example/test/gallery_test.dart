import 'dart:ui' show FrameTiming;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/components/components_page.dart';
import 'package:apple_liquid_glass_example/glass/glass_page.dart';
import 'package:apple_liquid_glass_example/motion/motion_page.dart';
import 'package:apple_liquid_glass_example/scenes/lava_page.dart';
import 'package:apple_liquid_glass_example/scenes/scene.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/showcase/cover.dart';
import 'package:apple_liquid_glass_example/showcase/showcase_page.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

Future<ValueNotifier<GallerySettings>> _launch(
  WidgetTester tester, {
  GalleryRenderer renderer = GalleryRenderer.flat,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final settings = ValueNotifier(GallerySettings(renderer: renderer));
  addTearDown(settings.dispose);
  await tester.pumpWidget(GalleryApp(notifier: settings));
  await _frames(tester, 30);
  return settings;
}

// Scrolls [scroll] until [target] stands clear of the bars.
Future<void> _bring(WidgetTester tester, Finder target, Finder scroll) async {
  for (var i = 0; i < 40; i++) {
    final y = target.evaluate().isEmpty ? null : tester.getCenter(target).dy;
    if (y != null && y > 220 && y < 640) break;
    await tester.drag(scroll, Offset(0, y != null && y <= 220 ? 140 : -140));
    await _frames(tester, 20);
  }
  await _frames(tester, 30);
}

// Leaves the catalog page on top.
Future<void> _back(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(ComponentPage))).pop();
  await _frames(tester, 90);
}

// Real glass with `--enable-impeller --enable-flutter-gpu`, fake without.
void main() {
  testWidgets('the gallery opens on the showcase and has a tab for each '
      'question', (tester) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    expect(find.byType(ShowcasePage), findsOneWidget);
    expect(find.byType(Cover), findsOneWidget);
    for (final (tab, page) in const [
      ('Glass', GlassPage),
      ('Components', ComponentsPage),
      ('Motion', MotionPage),
    ]) {
      await tester.tap(find.text(tab).last);
      await _frames(tester);
      expect(find.byType(page), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Showcase').last);
    await _frames(tester);
    expect(find.byType(Cover), findsOneWidget);
  });

  testWidgets('the showcase turns through every scene, each under its name, '
      'and opens the one shown', (tester) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    for (final scene in GalleryScene.all) {
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await _frames(tester);
      expect(find.text(scene.title), findsOneWidget);
      expect(find.text(scene.shows), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Back to Lava, the second scene, by its dot.
    for (var i = 0; i < GalleryScene.all.length - 2; i++) {
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await _frames(tester, 40);
    }
    expect(find.text('Lava'), findsOneWidget);
    // The preview has no bar; the scene opened to play with has one.
    expect(find.byType(GlassNavigationBar), findsNothing);
    await tester.tap(find.text('Open'));
    await _frames(tester, 90);
    expect(
      tester.widgetList<LavaPage>(find.byType(LavaPage)).any((p) => !p.preview),
      isTrue,
    );
    expect(find.bySemanticsLabel('Add a drop'), findsOneWidget);
  });

  testWidgets('the switch on the showcase draws the app flat or in glass', (
    tester,
  ) async {
    final settings = await _launch(tester, renderer: GalleryRenderer.liquid);
    await tester.tap(find.text('Flat'));
    await _frames(tester);
    expect(settings.value.renderer, GalleryRenderer.flat);
    await tester.tap(find.text('Glass').first);
    await _frames(tester);
    expect(settings.value.renderer, GalleryRenderer.liquid);
  });

  testWidgets('the Glass tab shows every property down to the last stage', (
    tester,
  ) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    await tester.tap(find.text('Glass').last);
    await _frames(tester);
    final scroll = find
        .descendant(
          of: find.byType(GlassPage),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final title in const [
      'It bends light',
      'Clear, regular, tinted',
      'Any outline',
      'It fuses',
      'Glass on glass',
      'Glass, or flat',
      'Light and dark',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: scroll,
      );
      await _frames(tester, 20);
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every family of the catalog opens a page of its widgets', (
    tester,
  ) async {
    await _launch(tester, renderer: GalleryRenderer.liquid);
    await tester.tap(find.text('Components').last);
    await _frames(tester);
    final catalog = find
        .descendant(
          of: find.byType(ComponentsPage),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final (_, _, title, _, _) in ComponentsPage.families) {
      await _bring(tester, find.text(title), catalog);
      await tester.tap(find.text(title));
      await _frames(tester, 90);
      final page = find.byType(ComponentPage);
      expect(page, findsOneWidget, reason: title);
      // To the end of the page and back out.
      final scroll = find
          .descendant(of: page, matching: find.byType(Scrollable))
          .first;
      await tester.drag(scroll, const Offset(0, -600));
      await _frames(tester, 40);
      expect(tester.takeException(), isNull, reason: title);
      await _back(tester);
      expect(find.byType(ComponentPage), findsNothing, reason: title);
    }
  });

  testWidgets("the catalog's widgets work: a switch, a menu, an alert and "
      'a sheet', (tester) async {
    await _launch(tester);
    await tester.tap(find.text('Components').last);
    await _frames(tester);

    final catalog = find
        .descendant(
          of: find.byType(ComponentsPage),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> open(String family) async {
      await _bring(tester, find.text(family), catalog);
      await tester.tap(find.text(family));
      await _frames(tester, 90);
    }

    await open('Switches, sliders, steppers');
    final airplane = find.byType(GlassSwitch).first;
    expect(tester.widget<GlassSwitch>(airplane).value, isFalse);
    await tester.tap(airplane);
    await _frames(tester);
    expect(tester.widget<GlassSwitch>(airplane).value, isTrue);
    await _back(tester);

    await open('Menus');
    await tester.tap(find.text('Options'));
    await _frames(tester, 90);
    expect(find.text('New Folder'), findsOneWidget);
    await tester.tap(find.text('New Folder'));
    await _frames(tester, 90);
    expect(find.text('New Folder'), findsNothing);
    await _back(tester);

    await open('Alerts and action sheets');
    await tester.tap(find.text('Destructive'));
    await _frames(tester, 90);
    expect(find.text('Delete 24 photos?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _frames(tester, 90);
    expect(find.text('Delete 24 photos?'), findsNothing);
    await _back(tester);

    await open('Sheets and popovers');
    await tester.tap(find.text('Sheet with detents'));
    await _frames(tester, 90);
    expect(find.text('Places'), findsOneWidget);
  });

  testWidgets('the frame meter reads frames a second and the time of a '
      'frame from the engine', (tester) async {
    final settings = await _launch(tester);
    expect(find.textContaining('fps'), findsNothing);
    settings.value = settings.value.copyWith(frameMeter: true);
    await _frames(tester, 5);
    FrameTiming frame(int at) => FrameTiming(
      vsyncStart: at,
      buildStart: at,
      buildFinish: at + 3000,
      rasterStart: at + 3000,
      rasterFinish: at + 8000,
      rasterFinishWallTime: at + 8000,
    );
    // Thirty frames, one every sixtieth of a second.
    tester.binding.platformDispatcher.onReportTimings!([
      for (var i = 0; i < 30; i++) frame(i * 16667),
    ]);
    await _frames(tester, 5);
    expect(find.text('60 fps   UI 3.0   raster 5.0 ms'), findsOneWidget);
    settings.value = settings.value.copyWith(frameMeter: false);
    await _frames(tester, 5);
    expect(find.textContaining('fps'), findsNothing);
  });

  testWidgets('search finds a scene by what it shows and opens it', (
    tester,
  ) async {
    await _launch(tester);
    await tester.tap(find.bySemanticsLabel('Search'));
    await _frames(tester, 90);
    await tester.enterText(find.byType(EditableText), 'fuses');
    await _frames(tester, 30);
    expect(find.text('Lava'), findsOneWidget);
    expect(find.text('Island'), findsNothing);
    await tester.tap(find.text('Lava'));
    await _frames(tester, 90);
    expect(find.byType(LavaPage), findsOneWidget);
  });
}
