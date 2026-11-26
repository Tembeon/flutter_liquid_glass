import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

class _Placement extends StatelessWidget {
  const _Placement();

  @override
  Widget build(BuildContext context) =>
      Text(GlassTabBar.accessoryPlacementOf(context).name);
}

Widget _scrolling({ScrollController? controller, int rows = 60}) =>
    GlassPageScaffold(
      child: GlassContentScroll(
        child: ListView(
          controller: controller,
          children: [
            for (var r = 0; r < rows; r++)
              SizedBox(key: ValueKey(r), height: 50),
          ],
        ),
      ),
    );

Widget _app({
  required GlassTabBarMinimizeBehavior behavior,
  ScrollController? controller,
  int rows = 60,
  Widget? accessory,
  GlassTabController? tabs,
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
  bool landscape = false,
}) => MediaQuery(
  data: landscape
      ? const MediaQueryData(
          size: Size(874, 402),
          devicePixelRatio: 3,
          padding: EdgeInsets.only(left: 62, right: 62, bottom: 20),
        )
      : const MediaQueryData(
          size: Size(402, 874),
          devicePixelRatio: 3,
          padding: EdgeInsets.only(top: 62, bottom: 34),
        ),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: MotionTraitsOverride(
        traits: MotionTraits(reduceMotion: reduceMotion),
        child: GlassTabScaffold(
          controller: tabs,
          minimizeBehavior: behavior,
          bottomAccessory: accessory,
          tabs: [
            for (final (i, name) in ['One', 'Two', 'Three'].indexed)
              GlassTab(
                icon: SizedBox.square(key: Key('glyph $i'), dimension: 24),
                label: Text(name),
                builder: (context) =>
                    _scrolling(controller: controller, rows: rows),
              ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _dragUp(
  WidgetTester tester,
  double distance, {
  Offset from = const Offset(201, 400),
}) async {
  final gesture = await tester.startGesture(from);
  for (var i = 0; i < 20; i++) {
    await gesture.moveBy(Offset(0, -distance / 20));
    await tester.pump(_frame);
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await _settle(tester);
}

// The bar's own glass, in screen coordinates.
Rect _body(WidgetTester tester) {
  final body = find
      .descendant(
        of: find.byType(RawGlassSelector),
        matching: find.byType(GlassSurface),
      )
      .first;
  final rect =
      tester.widget<GlassSurface>(body).frame!.value.rect ??
      Offset.zero & tester.getSize(body);
  return rect.shift(tester.getTopLeft(body));
}

bool _expanded(WidgetTester tester) => _body(tester).width > 100;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a bar that does not opt in never minimizes', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.automatic),
    );
    await tester.pump();
    await _dragUp(tester, 300);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('a user scroll shrinks the bar into a circle 28 points from '
      'the screen corner; a tap on it expands the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
    );
    await tester.pump();
    expect(_expanded(tester), isTrue);
    await _dragUp(tester, 200);
    expect(_expanded(tester), isFalse);
    final circle = _body(tester);
    expect(circle.left, closeTo(28, 0.5));
    expect(circle.bottom, closeTo(874 - 28, 0.5));
    expect(circle.width, closeTo(48, 0.5));
    await tester.tapAt(circle.center);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('a scroll the app drives never minimizes the bar', (
    tester,
  ) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
      ),
    );
    await tester.pump();
    controller.jumpTo(800);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('content with less than 96 points to scroll never minimizes '
      'the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown, rows: 16),
    );
    await tester.pump();
    await _dragUp(tester, 200);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('scrolling back to the top expands the bar', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
      ),
    );
    await tester.pump();
    await _dragUp(tester, 200);
    expect(_expanded(tester), isFalse);
    controller.jumpTo(0);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('an accessory stands above the bar and beside the circle '
      'once the bar has minimized', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
        accessory: const SizedBox.expand(
          key: Key('accessory'),
          child: _Placement(),
        ),
      ),
    );
    await tester.pump();
    final expanded = tester.getRect(find.byKey(const Key('accessory')));
    expect(
      expanded,
      const Rect.fromLTWH(21 + 16, 874 - 21 - 62 - 8 - 48 + 8, 360 - 32, 32),
    );
    expect(find.text('expanded'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
    }
    final bottom = tester.getBottomLeft(find.byKey(const ValueKey(59))).dy;
    expect(bottom, closeTo(874 - 21 - 62 - 8 - 48, 0.5));
    controller.jumpTo(0);
    await tester.pump();
    await _dragUp(tester, 200);
    expect(find.text('inline'), findsOneWidget);
    final inline = tester.getRect(find.byKey(const Key('accessory')));
    expect(inline.left, closeTo(21 + 7 + 48 + 14 + 16, 0.5));
    expect(inline.right, closeTo(402 - 28 - 16, 0.5));
    expect(inline.top, closeTo(874 - 21 - 62 + 7 + 8, 0.5));
  });

  testWidgets('a wide bar with an accessory stands as one group 640 wide at '
      'the middle, and minimizes into a 44 point circle at its leading end '
      'with the accessory 44 tall beside it (iOS 27.2 simulator in '
      'landscape)', (tester) async {
    tester.view.physicalSize = const Size(874 * 3, 402 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        landscape: true,
        accessory: const SizedBox.expand(
          key: Key('accessory'),
          child: _Placement(),
        ),
      ),
    );
    await tester.pump();
    expect(_body(tester), const Rect.fromLTWH(117, 338, 640, 44));
    expect(
      tester.getRect(find.byKey(const Key('accessory'))),
      const Rect.fromLTWH(117 + 16, 282 + 8, 640 - 32, 48 - 16),
    );
    await _dragUp(tester, 200, from: const Offset(437, 200));
    expect(find.text('inline'), findsOneWidget);
    expect(_body(tester), const Rect.fromLTWH(117, 338, 44, 44));
    final inline = tester.getRect(find.byKey(const Key('accessory')));
    expect(inline.left, closeTo(117 + 44 + 14 + 16, 0.5));
    expect(inline.right, closeTo(757 - 16, 0.5));
    expect(inline.top, closeTo(338 + 8, 0.5));
    expect(inline.bottom, closeTo(338 + 44 - 8, 0.5));
  });

  testWidgets('a wide bar that hosts nothing minimizes into a 44 point '
      "circle at its box's leading end, however wide its tabs (not "
      'measured)', (tester) async {
    tester.view.physicalSize = const Size(874 * 3, 402 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        landscape: true,
      ),
    );
    await tester.pump();
    final expanded = _body(tester);
    expect(expanded.height, 44);
    expect(expanded.center.dx, 437);
    await _dragUp(tester, 200, from: const Offset(437, 200));
    expect(_body(tester), const Rect.fromLTWH(38, 338, 44, 44));
  });

  testWidgets('a fling counts where the content will stop: the bar '
      'minimizes a frame into the glide, not where the content passes the '
      '64 points (read from UIKit)', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
        accessory: const _Placement(),
      ),
    );
    await tester.pump();
    await tester.timedDrag(
      find.byKey(const ValueKey(3)),
      const Offset(0, -50),
      const Duration(milliseconds: 200),
    );
    int? minimizedIn;
    for (var i = 0; i < 60 && minimizedIn == null; i++) {
      await tester.pump(_frame);
      if (find.text('inline').evaluate().isNotEmpty) minimizedIn = i;
    }
    final offset = controller.offset;
    await _settle(tester);
    expect(controller.offset, greaterThan(64), reason: 'the glide goes on');
    expect(minimizedIn, lessThanOrEqualTo(1));
    expect(offset, lessThan(60));
  });

  testWidgets('the hint scales the accessory with the bar, as UIKit '
      'scales the whole group', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        accessory: const SizedBox.expand(key: Key('accessory')),
      ),
    );
    await tester.pump();
    final accessory = find.byKey(const Key('accessory'));
    final bar = find.byType(RawGlassSelector);
    final restAccessory = tester.getRect(accessory).width;
    final restBar = tester.getRect(bar).width;
    final gesture = await tester.startGesture(const Offset(201, 400));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump(_frame);
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
    }
    final accessoryScale = tester.getRect(accessory).width / restAccessory;
    final barScale = tester.getRect(bar).width / restBar;
    expect(barScale, lessThan(0.999));
    expect(accessoryScale, closeTo(barScale, 1e-6));
    await gesture.up();
    await _settle(tester);
  });

  group('a finger on the circle', () {
    // The bar minimized over a page pushed on the first tab, so that a
    // selection of the selected tab, which pops it, shows.
    Future<(Rect, GlassTabController)> minimized(
      WidgetTester tester, {
      List<int>? selected,
      bool reduceMotion = false,
    }) async {
      await _phone(tester);
      final tabs = GlassTabController()
        ..setPages(0, [GlassTabPage(child: _scrolling())]);
      addTearDown(tabs.dispose);
      var last = tabs.index;
      tabs.addListener(() {
        if (tabs.index == last) return;
        last = tabs.index;
        selected?.add(last);
      });
      await tester.pumpWidget(
        _app(
          behavior: GlassTabBarMinimizeBehavior.onScrollDown,
          tabs: tabs,
          reduceMotion: reduceMotion,
        ),
      );
      await tester.pump();
      await _dragUp(tester, 200);
      return (_body(tester), tabs);
    }

    testWidgets('lifts it to 64 points, and however long it stays, the lift '
        'expands the bar and selects nothing', (tester) async {
      final selected = <int>[];
      final (circle, tabs) = await minimized(tester, selected: selected);
      final gesture = await tester.startGesture(circle.center);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(_body(tester).width, closeTo(64, 0.5));
      await gesture.up();
      await _settle(tester);
      expect(_expanded(tester), isTrue);
      expect(selected, isEmpty);
      expect(tabs.pagesOf(0), hasLength(1), reason: 'nothing popped');
    });

    testWidgets('under Reduce Motion lifts nothing and still expands the '
        'bar', (tester) async {
      final (circle, _) = await minimized(tester, reduceMotion: true);
      final gesture = await tester.startGesture(circle.center);
      await _settle(tester);
      expect(_body(tester).width, closeTo(circle.width, 0.5));
      await gesture.up();
      await _settle(tester);
      expect(_expanded(tester), isTrue);
    });

    testWidgets('a quick tap expands the bar and selects nothing', (
      tester,
    ) async {
      final selected = <int>[];
      final (circle, tabs) = await minimized(tester, selected: selected);
      await tester.tapAt(circle.center);
      await _settle(tester);
      expect(_expanded(tester), isTrue);
      expect(selected, isEmpty);
      expect(tabs.pagesOf(0), hasLength(1), reason: 'nothing popped');
    });

    testWidgets('moved along the bar, expands it under the finger and selects '
        'the tab it lifts over', (tester) async {
      final selected = <int>[];
      final (circle, _) = await minimized(tester, selected: selected);
      final gesture = await tester.startGesture(circle.center);
      await tester.pump(_frame);
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(_frame);
      await tester.pump(_frame);
      final early = _body(tester).width;
      expect(early, lessThan(200));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(7, 0));
        await tester.pump(_frame);
      }
      await _settle(tester);
      expect(_body(tester).width, closeTo(274, 8));
      expect(selected, isEmpty);
      await gesture.up();
      await _settle(tester);
      expect(selected, [1]);
      expect(_expanded(tester), isTrue);
    });

    testWidgets('in a right-to-left bar stands at the right', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          behavior: GlassTabBarMinimizeBehavior.onScrollDown,
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      await _dragUp(tester, 200);
      final circle = _body(tester);
      expect(circle.right, closeTo(402 - 28, 0.5));
      expect(circle.width, closeTo(48, 0.5));
    });

    testWidgets('leaves what is beside the circle to its owner', (
      tester,
    ) async {
      final (circle, _) = await minimized(tester);
      final beside = circle.center + const Offset(120, 0);
      final at = tester.hitTestOnBinding(beside);
      expect(
        at.path.any(
          (entry) => entry.target.runtimeType.toString().contains('Selector'),
        ),
        isFalse,
      );
    });
  });

  group('the morph', () {
    Future<void> scrolled(WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
      );
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(201, 400));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(_frame);
      }
      await gesture.up();
    }

    testWidgets('keeps the selector and its state from start to end', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
      );
      await tester.pump();
      final before = tester.state(find.byType(RawGlassSelector));
      await _dragUp(tester, 200);
      expect(tester.state(find.byType(RawGlassSelector)), same(before));
      await tester.tapAt(_body(tester).center);
      await _settle(tester);
      expect(tester.state(find.byType(RawGlassSelector)), same(before));
    });

    testWidgets('moves the bar without a jump and centers the glyph in the '
        'circle', (tester) async {
      await scrolled(tester);
      final glyph = find.byKey(const Key('glyph 0'), skipOffstage: false).last;
      var last = tester.getCenter(glyph);
      for (var i = 0; i < 120; i++) {
        await tester.pump(_frame);
        final now = tester.getCenter(glyph);
        expect((now - last).distance, lessThan(30));
        last = now;
      }
      final circle = _body(tester);
      expect((last - circle.center).distance, lessThan(0.5));
    });

    testWidgets('carries the accessory content with its glass, and a touch '
        'beside the circle reaches the accessory', (tester) async {
      var taps = 0;
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          behavior: GlassTabBarMinimizeBehavior.onScrollDown,
          accessory: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(key: Key('accessory')),
          ),
        ),
      );
      await tester.pump();
      final accessory = find.byKey(const Key('accessory'));
      final top = tester.getRect(accessory);
      final gesture = await tester.startGesture(const Offset(201, 400));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(_frame);
      }
      await gesture.up();
      var last = tester.getCenter(accessory);
      for (var i = 0; i < 120; i++) {
        await tester.pump(_frame);
        final now = tester.getCenter(accessory);
        expect((now - last).distance, lessThan(30));
        last = now;
      }
      expect(last.dy, greaterThan(top.center.dy + 40));
      await tester.tapAt(last);
      await _settle(tester);
      expect(taps, 1);
    });

    testWidgets('brings the lens back as the bar rests', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
      );
      await tester.pump();
      GlassFrame lens() => tester
          .widget<GlassSurface>(
            find
                .descendant(
                  of: find.byType(RawGlassSelector),
                  matching: find.byType(GlassSurface),
                )
                .last,
          )
          .frame!
          .value;
      expect(lens().opacity, 1);
      await _dragUp(tester, 200);
      expect(lens().opacity, 0);
      await tester.tapAt(_body(tester).center);
      await _settle(tester);
      expect(lens().opacity, 1);
    });
  });
}
