import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/pages/present_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/control_center_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/island_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/lava_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/lens_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/lock_screen_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/pads_page.dart';
import 'package:apple_liquid_glass_example/pages/scenes/weather_page.dart';
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
    ('Island', IslandPage),
    ('Lava', LavaPage),
    ('Weather', WeatherPage),
    ('Pads', PadsPage),
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

  testWidgets('Island: an activity stretches it, a second splits a bubble '
      'off, and a tap opens it', (tester) async {
    await _open(tester, 'Island');
    final timer = find.textContaining(RegExp(r'^[45]:\d\d$'));
    expect(timer, findsNothing);
    await tester.tap(find.bySemanticsLabel('Timer'));
    await _frames(tester);
    expect(timer, findsOneWidget);
    final compact = tester.getSize(timer);

    // The timer moves into the bubble, which shows its icon alone.
    await tester.tap(find.bySemanticsLabel('Music'));
    await _frames(tester);
    expect(timer, findsNothing);

    await tester.tapAt(
      Offset(201, tester.view.padding.top / tester.view.devicePixelRatio + 28),
    );
    await _frames(tester);
    expect(find.text('Liquid Dreams'), findsOneWidget);
    await tester.tapAt(const Offset(201, 500));
    await _frames(tester);
    expect(find.text('Liquid Dreams'), findsNothing);

    // Ending the music hands the island back to the timer.
    await tester.tap(find.bySemanticsLabel('Music'));
    await _frames(tester);
    expect(timer, findsOneWidget);
    expect(tester.getSize(timer), compact);
  });

  testWidgets('Lava: the drops move by themselves, and the buttons add and '
      'take them', (tester) async {
    await _open(tester, 'Lava');
    Iterable<GlassSurface> drops() => tester
        .widgetList<GlassSurface>(
          find.descendant(
            of: find.descendant(
              of: find.byType(LavaPage),
              matching: find.byType(GlassGroup),
            ),
            matching: find.byType(GlassSurface),
          ),
        )
        .where((surface) => surface.frame != null);
    expect(drops(), hasLength(9));
    final before = [for (final drop in drops()) drop.frame!.value.rect];
    await _frames(tester);
    final after = [for (final drop in drops()) drop.frame!.value.rect];
    expect(after, isNot(before));

    await tester.tap(find.bySemanticsLabel('Add a drop'));
    await _frames(tester, 10);
    expect(drops(), hasLength(10));
    await tester.tap(find.bySemanticsLabel('Take a drop'));
    await tester.tap(find.bySemanticsLabel('Take a drop'));
    await _frames(tester, 10);
    expect(drops(), hasLength(8));
  });

  testWidgets('Weather: the slider turns the day and the bar item makes '
      'it rain', (tester) async {
    await _open(tester, 'Weather');
    expect(find.text('Sunny'), findsOneWidget);
    // From the knob, at half past four, into the night.
    final track = tester.getRect(find.byType(GlassSlider));
    final gesture = await tester.startGesture(
      Offset(track.left + track.width * 16.5 / 24, track.center.dy),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(Offset(track.width * 0.2, 0));
    await _frames(tester, 10);
    await gesture.up();
    await _frames(tester, 20);
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Let it rain'));
    await _frames(tester, 20);
    expect(find.text('Rain'), findsOneWidget);
  });

  testWidgets('Pads: a pressed pad fills with its color, and two fingers '
      'play two pads', (tester) async {
    await _open(tester, 'Pads');
    List<GlassSurface> pads() => [
      ...tester
          .widgetList<GlassSurface>(
            find.descendant(
              of: find.byType(PadsPage),
              matching: find.byType(GlassSurface),
            ),
          )
          .where((surface) => surface.frame?.value.tint != null),
    ];
    expect(pads(), hasLength(16));
    double filled(int pad) => pads()[pad].frame!.value.tintAmount;
    expect(filled(0), 0);

    final notes = find.descendant(
      of: find.byType(PadsPage),
      matching: find.text('C'),
    );
    final first = await tester.startGesture(tester.getCenter(notes.at(0)));
    final second = await tester.startGesture(
      tester.getCenter(notes.at(1)),
      pointer: 9,
    );
    await _frames(tester, 30);
    expect(filled(0), greaterThan(0.8));
    expect(filled(5), greaterThan(0.8));
    expect(filled(1), 0);

    await first.up();
    await second.up();
    await _frames(tester, 90);
    expect(filled(0), closeTo(0, 0.01));

    // The pattern plays without a finger.
    await tester.tap(find.bySemanticsLabel('Play'));
    await _frames(tester, 30);
    expect(
      [for (var i = 0; i < 16; i++) filled(i)].any((f) => f > 0.1),
      isTrue,
    );
    await tester.tap(find.bySemanticsLabel('Stop'));
    await _frames(tester, 90);
  });

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
    // Stacked, only the first card is a notification; open, they stand a
    // card apart; closed again, the others are edges under the first.
    expect(find.text('Weather'), findsNothing);
    await tester.tap(find.text('Tim'));
    await _frames(tester);
    expect(top('Weather') - top('Tim'), closeTo(164, 1));
    await tester.tap(find.text('Tim'));
    await _frames(tester);
    expect(find.text('Weather'), findsNothing);

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
