import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/pages/present_page.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('every tab, menu and presentation opens', (tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const GalleryApp(
        settings: GallerySettings(renderer: GalleryRenderer.flat),
      ),
    );
    await _frames(tester);
    expect(find.text('Liquid Glass'), findsOneWidget);

    await tester.flingFrom(const Offset(130, 330), const Offset(160, 120), 900);
    await _frames(tester);

    await tester.tap(find.text('Controls'));
    await _frames(tester);
    expect(find.text('Airplane Mode'), findsOneWidget);
    await tester.tap(find.byType(GlassSwitch).first);
    await _frames(tester);

    await tester.tap(find.text('Present'));
    await _frames(tester);
    await tester.tap(find.bySemanticsLabel('More'));
    await _frames(tester);
    expect(find.text('New Folder'), findsOneWidget);
    await tester.tap(find.text('New Folder'));
    await _frames(tester);
    expect(find.text('New folder'), findsOneWidget);
    await tester.tap(find.text('Alert'));
    await _frames(tester);
    expect(find.text('Allow notifications?'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await _frames(tester);
    expect(find.text('Notifications allowed'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Sheet with detents'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(PresentPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _frames(tester);
    await tester.tap(find.text('Music app'));
    await _frames(tester, 90);
    expect(find.text('Liquid Dreams'), findsWidgets);
    await tester.drag(find.text('Refraction').first, const Offset(0, -400));
    await _frames(tester);
    await tester.tap(find.bySemanticsLabel('Present').last);
    await _frames(tester, 90);
    expect(find.text('Music app'), findsOneWidget);
    await tester.tap(find.text('Sheet with detents'));
    await _frames(tester);
    expect(find.text('Places'), findsOneWidget);
    await tester.fling(find.text('Places'), const Offset(0, 600), 2000);
    await _frames(tester, 90);
    expect(find.text('Places'), findsNothing);

    await tester.tap(find.text('Photos'));
    await _frames(tester);
    await tester.tap(find.byType(GlassZoomSource).first);
    await _frames(tester, 90);
    expect(find.byType(GlassToolbar), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete'));
    await _frames(tester, 90);
    expect(find.byType(GlassToolbar), findsNothing);

    await tester.tap(find.text('Liquid'));
    await _frames(tester);
    expect(find.text('Select'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Settings').first);
    await _frames(tester);
    expect(find.text('Renderer'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await _frames(tester);
  });
}
