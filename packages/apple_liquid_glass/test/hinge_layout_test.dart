import 'dart:async';
import 'dart:ui';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

// The iPhone Duo's inner display half open as a book: a band 40 wide
// centered on the crease at 475.5 (glass-lab spec/fold.md).
const _crease = DisplayFeature(
  bounds: Rect.fromLTWH(455.5, 0, 40, 669),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

// The same display flat: the fold is a line that separates nothing.
const _flat = DisplayFeature(
  bounds: Rect.fromLTWH(475.5, 0, 0, 669),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

void _window(
  WidgetTester tester,
  Size size, {
  List<DisplayFeature> features = const [_crease],
  FakeViewPadding padding = FakeViewPadding.zero,
}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1
    ..padding = padding
    ..displayFeatures = features;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) => Directionality(
        textDirection: direction,
        child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      ),
      home: home,
    );

Widget _page(String title) => GlassPageScaffold(
  navigationBar: GlassNavigationBar(title: Text(title)),
  child: SizedBox.expand(key: Key(title)),
);

Widget _split({
  double leadingInset = 0,
  bool resizable = true,
  bool pages = true,
  GlassSplitViewController? controller,
}) => GlassSplitView(
  controller: controller,
  leadingInset: leadingInset,
  resizable: resizable,
  primary: pages
      ? _page('Primary')
      : const SizedBox.expand(key: Key('Primary')),
  secondary: pages
      ? _page('Secondary')
      : const SizedBox.expand(key: Key('Secondary')),
);

Rect _column(WidgetTester tester, String title) =>
    tester.getRect(find.byKey(Key(title)));

MediaQueryData _media(WidgetTester tester, String title) =>
    MediaQuery.of(tester.element(find.byKey(Key(title))));

final _sidebarIcon = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == 'GlassSidebarGlyph',
);

final _divider = find.byWidgetPredicate(
  (widget) => '${widget.runtimeType}' == 'GlassColumnDivider',
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  group('a split view', () {
    for (final direction in TextDirection.values) {
      testWidgets('half open, puts its columns side by side on the crease, '
          'each keeping out of its half of the band, and flat, its own '
          'widths again, ${direction.name}', (tester) async {
        _window(tester, const Size(951, 669));
        await tester.pumpWidget(_app(_split(), direction: direction));
        await tester.pump();
        final ltr = direction == TextDirection.ltr;
        expect(
          _column(tester, 'Primary'),
          Rect.fromLTWH(ltr ? 0 : 475.5, 0, 475.5, 669),
        );
        expect(
          _column(tester, 'Secondary'),
          Rect.fromLTWH(ltr ? 475.5 : 0, 0, 475.5, 669),
        );
        final primary = _media(tester, 'Primary').padding;
        final secondary = _media(tester, 'Secondary').padding;
        expect(ltr ? primary.right : primary.left, 20);
        expect(ltr ? primary.left : primary.right, 0);
        expect(ltr ? secondary.left : secondary.right, 20);
        expect(_media(tester, 'Primary').displayFeatures, isEmpty);
        expect(_media(tester, 'Secondary').displayFeatures, isEmpty);
        expect(
          _divider,
          findsNothing,
          reason: 'the crease holds the border, no hand moves it',
        );
        expect(
          ltr
              ? tester.getRect(_sidebarIcon).right
              : tester.getRect(_sidebarIcon).left,
          ltr ? 475.5 - 20 - 16 - 11 : 475.5 + 20 + 16 + 11,
          reason: "the primary's items stand past its half of the band",
        );
        expect(
          tester.getCenter(find.text('Secondary')).dx,
          moreOrLessEquals(ltr ? (495.5 + 951) / 2 : 455.5 / 2, epsilon: 0.5),
          reason: "the secondary's title centers on what the band leaves",
        );

        tester.view.displayFeatures = [_flat];
        await tester.pump();
        expect(
          _column(tester, 'Primary'),
          Rect.fromLTWH(ltr ? 0 : 951 - 320, 0, 320, 669),
        );
        expect(_media(tester, 'Primary').padding.horizontal, 0);
        expect(_divider, findsOneWidget);
      });
    }

    testWidgets('past a sidebar or a rail, puts its border on the crease '
        'all the same', (tester) async {
      const hinge = DisplayFeature(
        bounds: Rect.fromLTWH(690, 0, 20, 834),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      );
      _window(tester, const Size(1210, 834), features: const [hinge]);
      for (final inset in [280.0, 72.0]) {
        await tester.pumpWidget(_app(_split(leadingInset: inset)));
        await tester.pump();
        expect(_column(tester, 'Primary'), const Rect.fromLTWH(0, 0, 700, 834));
        expect(_media(tester, 'Primary').padding.left, inset);
        expect(_media(tester, 'Primary').padding.right, 10);
        expect(_media(tester, 'Secondary').padding.left, 10);
      }
    });

    testWidgets('leaves a band at its edge, where it splits nothing, to the '
        'column it lies in, in its coordinates', (tester) async {
      for (final (bounds, primary, holder, local) in [
        (
          const Rect.fromLTWH(270, 0, 20, 834),
          600.0,
          'Primary',
          const Rect.fromLTWH(270, 0, 20, 834),
        ),
        (
          const Rect.fromLTWH(1200, 0, 10, 834),
          600.0,
          'Secondary',
          const Rect.fromLTWH(600, 0, 10, 834),
        ),
      ]) {
        _window(
          tester,
          const Size(1210, 834),
          features: [
            DisplayFeature(
              bounds: bounds,
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureFlat,
            ),
          ],
        );
        await tester.pumpWidget(_app(_split(leadingInset: 280)));
        await tester.pump();
        expect(_column(tester, 'Primary').width, primary);
        expect(
          _media(tester, holder).displayFeatures.single.bounds,
          local,
        );
        final other = holder == 'Primary' ? 'Secondary' : 'Primary';
        expect(_media(tester, other).displayFeatures, isEmpty);
        expect(_media(tester, 'Primary').padding.right, 0);
        expect(_media(tester, 'Secondary').padding.left, 0);
      }
    });

    testWidgets('ignores a band across it, which its columns keep in their '
        'own coordinates', (tester) async {
      const across = DisplayFeature(
        bounds: Rect.fromLTWH(0, 400, 1210, 40),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      );
      _window(tester, const Size(1210, 834), features: const [across]);
      await tester.pumpWidget(_app(_split()));
      await tester.pump();
      expect(_column(tester, 'Primary').width, 320);
      expect(
        _media(tester, 'Primary').displayFeatures.single.bounds,
        across.bounds,
      );
      expect(
        _media(tester, 'Secondary').displayFeatures.single.bounds,
        across.bounds.shift(const Offset(-320, 0)),
      );
    });

    testWidgets('gives each column the bottom insets, the keyboard '
        'included, half open as flat', (tester) async {
      for (final features in [
        const [_crease],
        const [_flat],
      ]) {
        _window(
          tester,
          const Size(951, 669),
          features: features,
          padding: const FakeViewPadding(bottom: 34),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpWidget(_app(_split(pages: false)));
        await tester.pump();
        for (final column in ['Primary', 'Secondary']) {
          final media = _media(tester, column);
          expect(media.viewInsets.bottom, 300, reason: column);
          expect(media.padding.bottom, 34, reason: column);
        }
      }
    });

    testWidgets('with its primary column hidden, leaves the crease to the '
        'secondary', (tester) async {
      _window(tester, const Size(951, 669));
      final controller = GlassSplitViewController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(_split(controller: controller)));
      controller.hide(GlassSplitViewColumn.primary);
      await _settle(tester);
      expect(
        _column(tester, 'Secondary'),
        const Rect.fromLTWH(0, 0, 951, 669),
      );
      expect(_media(tester, 'Secondary').padding.left, 0);
      expect(
        _media(tester, 'Secondary').displayFeatures.single.bounds,
        _crease.bounds,
      );
    });
  });

  testWidgets("a tab sidebar's width stops at a band beside it", (
    tester,
  ) async {
    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(300, 0, 20, 834),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureFlat,
    );
    tester.view
      ..physicalSize = const Size(1210, 834) * 2
      ..devicePixelRatio = 2
      ..displayFeatures = const [hinge];
    addTearDown(tester.view.reset);
    final controller = GlassTabController()..sidebarWidth = 400;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        GlassTabScaffold(
          controller: controller,
          tabs: [
            for (final name in ['One', 'Two'])
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: Text(name),
                builder: (context) => SizedBox.expand(key: Key(name)),
              ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(_media(tester, 'One').padding.left, 300);

    tester.view.displayFeatures = const [];
    await tester.pump();
    expect(_media(tester, 'One').padding.left, 400);
  });

  group('a sheet', () {
    Future<void> present(
      WidgetTester tester, {
      required List<GlassSheetDetent> detents,
      TextDirection direction = TextDirection.ltr,
    }) async {
      late BuildContext page;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              page = context;
              return const SizedBox.expand();
            },
          ),
          direction: direction,
        ),
      );
      unawaited(
        showGlassSheet<void>(
          page,
          detents: detents,
          builder: (context) => const SizedBox.expand(key: Key('content')),
        ),
      );
      await _settle(tester);
    }

    for (final direction in TextDirection.values) {
      testWidgets('half open, stands in the left part up to the crease, '
          'its content out of the band, ${direction.name}', (tester) async {
        _window(tester, const Size(951, 669));
        await present(
          tester,
          detents: const [GlassSheetDetent.medium],
          direction: direction,
        );
        final floating = _column(tester, 'content');
        expect(floating.left, moreOrLessEquals(8, epsilon: 0.5));
        expect(floating.right, moreOrLessEquals(475.5 - 8, epsilon: 0.5));
        final media = _media(tester, 'content');
        expect(media.size.width, 475.5);
        expect(media.padding.right, 20);
        expect(media.displayFeatures, isEmpty);
      });
    }

    testWidgets('docked half open, fills the left part up to the crease', (
      tester,
    ) async {
      _window(tester, const Size(951, 669));
      await present(tester, detents: const [GlassSheetDetent.large]);
      final docked = _column(tester, 'content');
      expect(docked.left, moreOrLessEquals(0, epsilon: 0.5));
      expect(docked.right, moreOrLessEquals(475.5, epsilon: 0.5));
    });

    testWidgets('flat, or across a band in the laptop posture, spans the '
        'window', (tester) async {
      for (final (size, features) in [
        (const Size(951, 669), const [_flat]),
        (
          const Size(669, 951),
          const [
            DisplayFeature(
              bounds: Rect.fromLTWH(0, 455.5, 669, 40),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
      ]) {
        _window(tester, size, features: features);
        await present(tester, detents: const [GlassSheetDetent.medium]);
        final floating = _column(tester, 'content');
        expect(floating.left, moreOrLessEquals(8, epsilon: 0.5));
        expect(floating.right, moreOrLessEquals(size.width - 8, epsilon: 0.5));
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('from a split column on the crease', () {
    // The primary column with [child] [start] points from the window's
    // leading edge, short of the band.
    Widget column(double start, Widget child) => Builder(
      builder: (context) {
        final ltr = Directionality.of(context) == TextDirection.ltr;
        return Stack(
          children: [
            Positioned(
              left: ltr ? start : null,
              right: ltr ? null : start,
              top: 200,
              child: child,
            ),
          ],
        );
      },
    );

    // Where the band starts on the primary column's side.
    double edge(TextDirection direction) =>
        direction == TextDirection.ltr ? 455.5 : 495.5;

    void apart(Rect layer, TextDirection direction) {
      if (direction == TextDirection.ltr) {
        expect(layer.right, lessThanOrEqualTo(edge(direction) + 0.5));
      } else {
        expect(layer.left, greaterThanOrEqualTo(edge(direction) - 0.5));
      }
    }

    Widget split(Widget primary, TextDirection direction) => _app(
      GlassSplitView(primary: primary, secondary: _page('Secondary')),
      direction: direction,
    );

    for (final direction in TextDirection.values) {
      testWidgets('a menu stays on its column side of the band, '
          '${direction.name}', (tester) async {
        _window(tester, const Size(951, 669));
        final controller = GlassMenuController();
        await tester.pumpWidget(
          split(
            column(
              400,
              GlassMenuAnchor(
                controller: controller,
                menuChildren: [
                  for (final title in ['Copy', 'Share', 'Delete'])
                    GlassMenuItem(title: title, onPressed: () {}),
                ],
                builder: (context, controller, child) =>
                    const SizedBox(width: 40, height: 40),
              ),
            ),
            direction,
          ),
        );
        controller.open();
        await _settle(tester);
        final menu = tester
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
        apart(menu, direction);
      });

      testWidgets('a popover stays on its column side of the band, '
          '${direction.name}', (tester) async {
        _window(tester, const Size(951, 669));
        await tester.pumpWidget(
          split(
            column(
              350,
              Builder(
                builder: (context) => GlassButton(
                  onPressed: () => showGlassPopover<void>(
                    context,
                    anchor: context,
                    adaptsToSheet: false,
                    builder: (context) => const SizedBox(
                      key: Key('popover'),
                      width: 300,
                      height: 120,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            direction,
          ),
        );
        await tester.tap(find.text('Open'));
        await _settle(tester);
        apart(tester.getRect(find.byKey(const Key('popover'))), direction);
      });

      testWidgets('a tooltip stays on its column side of the band, '
          '${direction.name}', (tester) async {
        _window(tester, const Size(951, 669));
        await tester.pumpWidget(
          split(
            column(
              410,
              const GlassTooltip(
                message: 'A hint long enough to cross the band',
                child: SizedBox(key: Key('hinted'), width: 44, height: 44),
              ),
            ),
            direction,
          ),
        );
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byKey(const Key('hinted'))));
        await _settle(tester);
        final tip = find.ancestor(
          of: find.text('A hint long enough to cross the band'),
          matching: find.byType(GlassSurface),
        );
        apart(tester.getRect(tip), direction);
      });
    }
  });
}
