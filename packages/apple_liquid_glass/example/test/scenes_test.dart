import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/pages/present_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/control_center_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/lens_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/lock_screen_page.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

// Opens the scene [row] names from the Present page.
Future<void> _open(
  WidgetTester tester,
  String row, {
  GalleryRenderer renderer = GalleryRenderer.flat,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    GalleryApp(settings: GallerySettings(renderer: renderer)),
  );
  await _frames(tester);
  await tester.tap(find.text('Present'));
  await _frames(tester);
  final scroll = find
      .descendant(
        of: find.byType(PresentPage),
        matching: find.byType(Scrollable),
      )
      .first;
  // Until the row stands clear of the bars.
  for (var i = 0; i < 40; i++) {
    final found = find.text(row).evaluate().isNotEmpty;
    final y = found ? tester.getCenter(find.text(row)).dy : null;
    if (y != null && y > 250 && y < 600) break;
    await tester.drag(scroll, Offset(0, y != null && y <= 250 ? 150 : -150));
    await _frames(tester, 20);
  }
  await _frames(tester, 30);
  await tester.tap(find.text(row));
  await _frames(tester, 90);
}

void main() {
  // Real glass with `--enable-impeller --enable-flutter-gpu`, fake without.
  for (final (row, page) in const [
    ('Control Center', ControlCenterPage),
    ('Lock Screen', LockScreenPage),
    ('Lens', LensPage),
  ]) {
    testWidgets('$row draws with liquid glass', (tester) async {
      await _open(tester, row, renderer: GalleryRenderer.liquid);
      expect(find.byType(page), findsOneWidget);
      expect(find.byType(GlassSurface), findsWidgets);
      await _frames(tester, 30);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Control Center: a module fills with its state and a tall '
      'slider follows the finger', (tester) async {
    await _open(tester, 'Control Center');
    expect(find.byType(ControlCenterPage), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Focus'));
    await _frames(tester);
    expect(find.text('Do Not Disturb'), findsOneWidget);

    final brightness = find.bySemanticsLabel('Brightness');
    String value() => tester.getSemantics(brightness).value;
    expect(value(), '62%');
    // Down by a quarter of the slider, then far past its lower end.
    final height = tester.getSize(brightness).height;
    final gesture = await tester.startGesture(tester.getCenter(brightness));
    // The first move is the recognizer's slop.
    await gesture.moveBy(const Offset(0, 30));
    final from = value();
    await gesture.moveBy(Offset(0, height / 4));
    await _frames(tester, 2);
    expect(
      int.parse(value().replaceAll('%', '')),
      int.parse(from.replaceAll('%', '')) - 25,
    );
    await gesture.moveBy(Offset(0, height * 2));
    await _frames(tester, 2);
    expect(value(), '0%');
    await gesture.up();
    await _frames(tester);
    expect(value(), '0%');
  });

  testWidgets('Lock Screen: the notifications fan out, and a swipe up '
      'unlocks', (tester) async {
    await _open(tester, 'Lock Screen');
    expect(find.byType(LockScreenPage), findsOneWidget);
    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    // Stacked, the cards lie ten points apart; open, a card apart.
    expect(top('Weather') - top('Tim'), closeTo(20, 1));
    await tester.tap(find.text('Tim'));
    await _frames(tester);
    expect(top('Weather') - top('Tim'), closeTo(164, 1));

    await tester.fling(
      find.text('Swipe up to open'),
      const Offset(0, -300),
      1500,
    );
    await _frames(tester, 90);
    expect(find.byType(LockScreenPage), findsNothing);
    expect(find.byType(PresentPage), findsOneWidget);
  });

  testWidgets('Lens: the lens follows the finger, and a second one joins '
      'it', (tester) async {
    await _open(tester, 'Lens');
    final page = find.byType(LensPage);
    Finder lenses() => find.descendant(
      of: find.descendant(of: page, matching: find.byType(GlassGroup)),
      matching: find.byType(GlassSurface),
    );
    expect(lenses(), findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(lenses()));
    // The first move is the recognizer's slop.
    await gesture.moveBy(const Offset(30, 30));
    await _frames(tester, 2);
    final before = tester.getCenter(lenses());
    await gesture.moveBy(const Offset(40, 60));
    await _frames(tester, 2);
    final moved = tester.getCenter(lenses()) - before;
    expect(moved.dx, closeTo(40, 0.01));
    expect(moved.dy, closeTo(60, 0.01));
    await gesture.up();

    final size = tester.getSize(lenses());
    await tester.tap(find.text('Capsule'));
    await _frames(tester);
    expect(tester.getSize(lenses()).width, greaterThan(size.width));

    await tester.tap(find.bySemanticsLabel('Add a lens'));
    await _frames(tester);
    expect(lenses(), findsNWidgets(2));
  });
}
