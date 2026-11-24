import 'dart:async';
import 'dart:ui';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// A view 840 points wide that a hinge 20 points wide splits down its
// middle: a left part 0 - 410 and a right part 430 - 840.
const _hinge = DisplayFeature(
  bounds: Rect.fromLTWH(410, 0, 20, 600),
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.postureFlat,
);

void _unfolded(WidgetTester tester, {bool hinge = true}) {
  tester.view.physicalSize = const Size(840, 600) * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.displayFeatures = [if (hinge) _hinge];
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) =>
      GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  home: ColoredBox(color: const Color(0xFFF2F2F7), child: home),
);

List<GlassMenuEntry> get _rows => [
  for (final title in ['Copy', 'Share', 'Delete'])
    GlassMenuItem(title: title, onPressed: () {}),
];

Future<void> _frames(WidgetTester tester, [int count = 90]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// The open menu's glass.
Rect _menu(WidgetTester tester) => tester
    .widgetList<GlassSurface>(
      find.byWidgetPredicate(
        (widget) =>
            widget is GlassSurface &&
            widget.role == GlassRole.panel &&
            widget.frame != null,
      ),
    )
    .first
    .frame!
    .value
    .rect!;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the overlay padding keeps a layer on the part of a split view '
      'closest to its anchor, or the one at the start of the reading '
      'direction', (tester) async {
    const media = MediaQueryData(
      size: Size(840, 600),
      padding: EdgeInsets.only(top: 24),
      displayFeatures: [_hinge],
    );
    final seen = <EdgeInsets>[];
    for (final (direction, anchor) in [
      (TextDirection.ltr, const Offset(600, 300)),
      (TextDirection.ltr, const Offset(100, 300)),
      (TextDirection.ltr, null),
      (TextDirection.rtl, null),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: media,
            child: Builder(
              builder: (context) {
                seen.add(
                  GlassMediaQueryData.overlayPaddingOf(
                    context,
                    anchorPoint: anchor,
                  ),
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }
    expect(seen, const [
      EdgeInsets.fromLTRB(430, 24, 0, 0),
      EdgeInsets.fromLTRB(0, 24, 430, 0),
      EdgeInsets.fromLTRB(0, 24, 430, 0),
      EdgeInsets.fromLTRB(430, 24, 0, 0),
    ]);
  });

  testWidgets("a menu stays on its button's side of the hinge", (
    tester,
  ) async {
    for (final hinge in [false, true]) {
      _unfolded(tester, hinge: hinge);
      final controller = GlassMenuController();
      await tester.pumpWidget(
        _app(
          Stack(
            children: [
              Positioned(
                left: 436,
                top: 100,
                child: GlassMenuAnchor(
                  controller: controller,
                  menuChildren: _rows,
                  builder: (context, controller, child) =>
                      const SizedBox(width: 40, height: 40),
                ),
              ),
            ],
          ),
        ),
      );
      controller.open();
      await _frames(tester);
      final menu = _menu(tester);
      if (hinge) {
        expect(menu.left, greaterThanOrEqualTo(430));
      } else {
        expect(menu.left, lessThan(410));
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a context menu lifts its preview and stands its menu on the '
      "held view's side of the hinge", (tester) async {
    _unfolded(tester);
    await tester.pumpWidget(
      _app(
        Stack(
          children: [
            Positioned(
              left: 300,
              top: 100,
              child: GlassContextMenu(
                menuChildren: _rows,
                child: const SizedBox(
                  key: Key('held'),
                  width: 100,
                  height: 60,
                  child: ColoredBox(color: Color(0xFF3478F6)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(350, 130));
    await _frames(tester, 60);
    await gesture.up();
    await _frames(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('held')).last).right,
      lessThanOrEqualTo(410),
    );
    expect(_menu(tester).right, lessThanOrEqualTo(410));
  });

  testWidgets("a popover stays on its source's side of the hinge", (
    tester,
  ) async {
    _unfolded(tester);
    await tester.pumpWidget(
      _app(
        Stack(
          children: [
            Positioned(
              left: 436,
              top: 100,
              child: Builder(
                builder: (context) => GlassButton(
                  onPressed: () => showGlassPopover<void>(
                    context,
                    anchor: context,
                    builder: (context) => const SizedBox(
                      key: Key('content'),
                      width: 300,
                      height: 120,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _frames(tester);
    expect(
      tester.getRect(find.byKey(const Key('content'))).left,
      greaterThanOrEqualTo(430),
    );
  });

  testWidgets("a date picker's calendar stays on its label's side of the "
      'hinge', (tester) async {
    _unfolded(tester);
    await tester.pumpWidget(
      _app(
        Stack(
          children: [
            Positioned(
              left: 440,
              top: 100,
              child: GlassCompactDatePicker(
                value: DateTime(2026, 10, 3),
                today: DateTime(2026, 10, 3),
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(GlassCompactDatePicker));
    await _frames(tester);
    // The first column holds the 4th or the 5th, by the first weekday.
    for (final day in ['4', '5']) {
      expect(tester.getRect(find.text(day)).left, greaterThanOrEqualTo(430));
    }
  });

  testWidgets('an alert stands on the part of its anchor point, or the one '
      'at the start of the reading direction', (tester) async {
    _unfolded(tester);
    late BuildContext page;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            page = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    for (final (anchor, part) in [
      (const Offset(700, 300), (430.0, 840.0)),
      (null, (0.0, 410.0)),
    ]) {
      unawaited(
        showGlassAlert(
          page,
          title: const Text('Title'),
          actions: [
            GlassAlertAction(child: const Text('OK'), onPressed: () {}),
          ],
          anchorPoint: anchor,
        ),
      );
      await _frames(tester);
      // The button spans the card, its label centered in it.
      final button = tester.getRect(find.text('OK'));
      expect(button.center.dx, closeTo((part.$1 + part.$2) / 2, 1));
      await tester.tap(find.text('OK'));
      await _frames(tester);
    }
  });
}
