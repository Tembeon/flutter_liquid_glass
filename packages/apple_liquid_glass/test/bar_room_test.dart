import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_room.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/poses.dart';

const _frame = Duration(milliseconds: 16);

// The Duo's status cluster as UIKit reports it: in its column, and in the
// top row without the column (duo report, glass-lab spec/fold.md).
const _coverColumnCluster = Rect.fromLTWH(382, 0, 84, 174);
const _innerColumnCluster = Rect.fromLTWH(867, 0, 84, 124);
const _coverClassicCluster = Rect.fromLTWH(266, 0, 200, 82);
const _innerClassicCluster = Rect.fromLTWH(807, 0, 144, 82);
const _rightColumn = GlassBarColumn(
  side: GlassBarColumnSide.right,
  reservedWidth: 84,
);

// An iPad window's buttons: 41 x 22 at x 21, on the first row's line.
GlassWindowControls _iPadButtons(Pose pose) => GlassWindowControls(
  left: 62,
  lineCenter: pose.padding.top + GlassWindowControls.rowCenter,
);

typedef _Room = ({double top, BarSides row, BarSides toolbar});

Future<_Room> _roomOf(
  WidgetTester tester,
  Pose pose, {
  GlassBarColumn? column,
  List<Rect>? occlusions,
  GlassWindowControls? controls,
  double covered = 0,
  TextDirection direction = TextDirection.ltr,
}) async {
  pose.apply(tester);
  late _Room room;
  await tester.pumpWidget(
    MediaQuery.fromView(
      view: tester.view,
      child: Directionality(
        textDirection: direction,
        child: GlassEnvironmentOverride(
          barColumn: column,
          occlusions: occlusions,
          windowControls: controls,
          child: GlassBarInset(
            leading: covered,
            child: Builder(
              builder: (context) {
                final top = BarRoom.rowTopOf(context);
                room = (
                  top: top,
                  row: BarRoom.sidesOf(
                    context,
                    inset: navigationSideInset,
                    top: top,
                    height: GlassNavigationBar.height,
                  ),
                  toolbar: BarRoom.sidesOf(
                    context,
                    inset: GlassToolbar.sideInset,
                  ),
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    ),
  );
  return room;
}

Widget _app(
  Widget home, {
  bool glassRoutes = false,
  GlassBarColumn? column,
  List<Rect>? occlusions,
  GlassWindowControls? controls,
}) => WidgetsApp(
  color: const Color(0xFFFFFFFF),
  pageRouteBuilder: <T>(settings, builder) => glassRoutes
      ? GlassPageRoute<T>(builder: builder, settings: settings)
      : PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
  builder: (context, child) => GlassScope(
    renderer: const FlatGlassRenderer(),
    child: GlassEnvironmentOverride(
      barColumn: column,
      occlusions: occlusions,
      windowControls: controls,
      child: child!,
    ),
  ),
  home: home,
);

final _presses = <String>[];

GlassBarItem _icon(String name) => GlassBarItem(
  icon: SizedBox.square(key: Key(name), dimension: 22),
  semanticLabel: name,
  onPressed: () => _presses.add(name),
);

Widget _page({String? title = 'Page', Widget? body, String name = ''}) =>
    GlassPageScaffold(
      navigationBar: GlassNavigationBar(
        title: title == null ? null : Text(title),
        leading: [_icon('${name}lead')],
        trailing: [_icon('${name}trail')],
      ),
      child: body ?? const SizedBox.expand(),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

// How far an icon's center stands from its capsule's outer edge: the
// capsule of one icon item, measured where the row starts at the side
// inset.
Future<double> _iconOffset(WidgetTester tester) async {
  Poses.iPhone.apply(tester);
  await tester.pumpWidget(_app(_page()));
  await _settle(tester);
  return tester.getCenter(find.byKey(const Key('lead'))).dx -
      navigationSideInset;
}

void main() {
  setUp(() {
    MotionClock.debugReset();
    _presses.clear();
  });

  group('the room of a row of bars', () {
    testWidgets('a phone in portrait and the bare test window: the row under '
        'the top padding, the side insets', (tester) async {
      final portrait = await _roomOf(tester, Poses.iPhone);
      expect(portrait.top, 62);
      expect(portrait.row, (left: 16.0, right: 16.0));
      expect(portrait.toolbar, (left: 28.0, right: 28.0));
      final bare = await _roomOf(
        tester,
        const Pose('test window', Size(800, 600), EdgeInsets.zero),
      );
      expect(bare.top, 0);
      expect(bare.row, (left: 16.0, right: 16.0));
    });

    testWidgets('an iPhone in landscape: the row at 24 and the items 38 in, '
        '24 into the 62 point safe area, toolbar too', (tester) async {
      final room = await _roomOf(tester, Poses.iPhoneLandscape);
      expect(room.top, 24);
      expect(room.row, (left: 38.0, right: 38.0));
      expect(room.toolbar, (left: 38.0, right: 38.0));
    });

    testWidgets("the Duo's column: the row at 24, ending 4 before the column, "
        'on either display', (tester) async {
      final cover = await _roomOf(
        tester,
        Poses.duoCover,
        column: _rightColumn,
        occlusions: const [_coverColumnCluster],
      );
      expect(cover.top, 24);
      expect(466 - cover.row.right, 378);
      expect(cover.row.left, 16);
      expect(466 - cover.toolbar.right, 378);
      final inner = await _roomOf(
        tester,
        Poses.duoInner,
        column: _rightColumn,
        occlusions: const [_innerColumnCluster],
      );
      expect(951 - inner.row.right, 863);
      final unreported = await _roomOf(
        tester,
        Poses.duoCover,
        column: _rightColumn,
      );
      expect(unreported.top, 24);
      expect(466 - unreported.row.right, 378);
    });

    testWidgets("the Duo without its column: the row shares the status row "
        'and ends 4 before the status cluster; the toolbar does not meet '
        'it', (tester) async {
      final cover = await _roomOf(
        tester,
        Poses.duoCoverClassic,
        occlusions: const [_coverClassicCluster],
      );
      expect(cover.top, 24);
      expect(466 - cover.row.right, 262);
      expect(cover.toolbar, (left: 28.0, right: 28.0));
      final inner = await _roomOf(
        tester,
        Poses.duoInnerClassic,
        occlusions: const [_innerClassicCluster],
      );
      expect(inner.top, 24);
      expect(951 - inner.row.right, 803);
      final unreported = await _roomOf(tester, Poses.duoCoverClassic);
      expect(unreported.top, 82);
    });

    testWidgets("an iPad window's buttons push the first row's leading items "
        "16 past them, and no row below their line", (tester) async {
      const pose = Poses.iPadWindowCompactWidest;
      final room = await _roomOf(tester, pose, controls: _iPadButtons(pose));
      expect(room.top, 24);
      expect(room.row, (left: 78.0, right: 16.0));
      expect(room.toolbar, (left: 28.0, right: 28.0));
      final below = await _roomOf(
        tester,
        pose,
        controls: GlassWindowControls(
          left: 62,
          lineCenter: pose.padding.top - 30,
        ),
      );
      expect(below.row, (left: 16.0, right: 16.0));
      final trailing = await _roomOf(
        tester,
        pose,
        controls: const GlassWindowControls(right: 138),
      );
      expect(trailing.row, (left: 16.0, right: 154.0));
    });

    testWidgets('a sidebar over the box moves the leading side, whichever '
        'it is', (tester) async {
      final ltr = await _roomOf(tester, Poses.iPadFull, covered: 280);
      expect(ltr.row, (left: 296.0, right: 16.0));
      final rtl = await _roomOf(
        tester,
        Poses.iPadFull,
        covered: 280,
        direction: TextDirection.rtl,
      );
      expect(rtl.row, (left: 16.0, right: 296.0));
    });
  });

  group('bars in the room', () {
    for (final glassRoutes in [false, true]) {
      final routes = glassRoutes ? 'shared bars' : 'bars of their own';
      testWidgets('$routes: an iPhone in landscape puts the row at 24 and '
          'its items 38 in, the title on the center', (tester) async {
        final offset = await _iconOffset(tester);
        Poses.iPhoneLandscape.apply(tester);
        await tester.pumpWidget(_app(_page(), glassRoutes: glassRoutes));
        await _settle(tester);
        final lead = tester.getCenter(find.byKey(const Key('lead')));
        final trail = tester.getCenter(find.byKey(const Key('trail')));
        expect(lead.dx, moreOrLessEquals(38 + offset));
        expect(trail.dx, moreOrLessEquals(874 - 38 - offset));
        expect(lead.dy, moreOrLessEquals(24 + 22));
        expect(tester.getCenter(find.text('Page')).dx, moreOrLessEquals(437));
      });

      testWidgets("$routes: on the Duo without its column the row shares the "
          'status row, ends before the cluster, and takes its taps', (
        tester,
      ) async {
        final offset = await _iconOffset(tester);
        Poses.duoCoverClassic.apply(tester);
        double? contentTop;
        await tester.pumpWidget(
          _app(
            _page(
              body: Builder(
                builder: (context) {
                  contentTop = MediaQuery.paddingOf(context).top;
                  return const SizedBox.expand();
                },
              ),
            ),
            glassRoutes: glassRoutes,
            occlusions: const [_coverClassicCluster],
          ),
        );
        await _settle(tester);
        final trail = tester.getCenter(find.byKey(const Key('trail')));
        expect(trail.dx, moreOrLessEquals(262 - offset));
        expect(trail.dy, moreOrLessEquals(24 + 22));
        expect(contentTop, 82);
        await tester.tap(find.byKey(const Key('trail')));
        await tester.tap(find.byKey(const Key('lead')));
        await _settle(tester);
        expect(_presses, ['trail', 'lead']);
      });
    }

    testWidgets("an iPad window's buttons move the compact window's first "
        'item past them, the title staying on the window center', (
      tester,
    ) async {
      final offset = await _iconOffset(tester);
      const pose = Poses.iPadWindowCompactWidest;
      pose.apply(tester);
      await tester.pumpWidget(
        _app(_page(), glassRoutes: true, controls: _iPadButtons(pose)),
      );
      await _settle(tester);
      expect(
        tester.getCenter(find.byKey(const Key('lead'))).dx,
        moreOrLessEquals(62 + 16 + offset),
      );
      expect(
        tester.getCenter(find.text('Page')).dx,
        moreOrLessEquals(667 / 2),
      );
    });

    testWidgets("a sheet's bars stand clear of the window buttons and the "
        "Duo's status cluster", (tester) async {
      final offset = await _iconOffset(tester);
      Poses.duoCoverClassic.apply(tester);
      late BuildContext context;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
          occlusions: const [_coverClassicCluster],
          controls: const GlassWindowControls(left: 62),
        ),
      );
      showGlassSheet<void>(context, builder: (_) => _page()).ignore();
      await _settle(tester);
      final lead = tester.getCenter(find.byKey(const Key('lead')));
      final trail = tester.getCenter(find.byKey(const Key('trail')));
      expect(lead.dx, moreOrLessEquals(16 + offset));
      expect(trail.dx, moreOrLessEquals(466 - 16 - offset));
    });

    testWidgets("the first row's empty parts let a touch through to what "
        'lies under them, as a window drag region', (tester) async {
      const pose = Poses.iPadWindowCompactWidest;
      pose.apply(tester);
      var under = 0;
      await tester.pumpWidget(
        _app(
          _page(
            title: null,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => under++,
              child: const SizedBox.expand(),
            ),
          ),
          glassRoutes: true,
          controls: _iPadButtons(pose),
        ),
      );
      await _settle(tester);
      await tester.tapAt(Offset(300, pose.padding.top + 22));
      await _settle(tester);
      expect(under, 1);
      expect(_presses, isEmpty);
    });

    testWidgets("each column of a split view meets the window's buttons and "
        'the status cluster at its own edges, in its own coordinates', (
      tester,
    ) async {
      final offset = await _iconOffset(tester);
      const pose = Poses.duoInnerClassic;
      pose.apply(tester);
      await tester.pumpWidget(
        _app(
          GlassSplitView(
            showsSidebarButton: false,
            primary: _page(name: 'p-'),
            secondary: _page(name: 's-'),
          ),
          glassRoutes: true,
          occlusions: const [_innerClassicCluster],
          controls: const GlassWindowControls(
            left: 62,
            lineCenter: BarRoom.statusRowTop + GlassWindowControls.rowCenter,
          ),
        ),
      );
      await _settle(tester);
      final columns = [
        for (final element in find.byType(GlassPageScaffold).evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ]..sort((a, b) => a.left.compareTo(b.left));
      final primary = columns.first;
      final secondaryLeft = columns.last.left;
      expect(
        tester.getCenter(find.byKey(const Key('p-lead'))).dx,
        moreOrLessEquals(62 + 16 + offset),
      );
      expect(
        tester.getCenter(find.byKey(const Key('p-trail'))).dx,
        moreOrLessEquals(primary.right - 16 - offset),
      );
      expect(
        tester.getCenter(find.byKey(const Key('s-lead'))).dx,
        moreOrLessEquals(secondaryLeft + 16 + offset),
      );
      expect(
        tester.getCenter(find.byKey(const Key('s-trail'))).dx,
        moreOrLessEquals(807 - BarRoom.coverGap - offset),
      );
    });
  });

  group('a tab scaffold', () {
    Future<void> pump(
      WidgetTester tester,
      Pose pose, {
      GlassTabLayoutPolicy layout = const GlassTabLayoutPolicy.automatic(),
      GlassTabController? controller,
    }) async {
      pose.apply(tester);
      await tester.pumpWidget(
        _app(
          GlassTabScaffold(
            layout: layout,
            controller: controller,
            tabs: [
              for (final name in ['One', 'Two'])
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: Text(name),
                  builder: (context) => _page(name: '$name-'),
                ),
            ],
          ),
          controls: _iPadButtons(pose),
        ),
      );
      await _settle(tester);
    }

    testWidgets("gives the window's buttons to the top bar's row, not to "
        'the pages under it', (tester) async {
      final offset = await _iconOffset(tester);
      await pump(tester, Poses.iPadWindowShortRegular);
      expect(
        tester.getCenter(find.byKey(const Key('One-lead'))).dx,
        moreOrLessEquals(16 + offset),
      );
    });

    testWidgets('drops the rail below the window buttons, and the pages '
        'beside it start past both', (tester) async {
      final offset = await _iconOffset(tester);
      final controller = GlassTabController()..sidebarRail = true;
      addTearDown(controller.dispose);
      const pose = Poses.iPadWindowShortRegular;
      await pump(
        tester,
        pose,
        layout: const GlassTabLayoutPolicy.desktop(),
        controller: controller,
      );
      final glyph = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'GlassSidebarGlyph',
      );
      expect(
        tester.getRect(glyph.first).top,
        greaterThan(pose.padding.top + 2 * GlassWindowControls.rowCenter),
      );
      expect(
        tester.getCenter(find.byKey(const Key('One-lead'))).dx,
        moreOrLessEquals(72 + 16 + offset),
      );
    });
  });
}
