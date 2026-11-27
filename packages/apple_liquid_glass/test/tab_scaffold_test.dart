import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(renderer: const FlatGlassRenderer(), child: child),
  ),
);

class _Counter extends StatefulWidget {
  const _Counter(this.name);

  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => taps++),
    child: Text('${widget.name} $taps'),
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.built});

  final List<int> built;

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabs: [
      for (final (i, name) in [(0, 'One'), (1, 'Two')])
        GlassTab(
          icon: const SizedBox.square(dimension: 24),
          label: Text(name),
          builder: (context) {
            built.add(i);
            return GlassPageScaffold(
              navigationBar: GlassNavigationBar(title: Text('Page $i')),
              child: GlassContentScroll(
                child: ListView(
                  children: [
                    _Counter('Tab $i'),
                    for (var r = 0; r < 40; r++)
                      SizedBox(key: ValueKey('$i.$r'), height: 50),
                  ],
                ),
              ),
            );
          },
        ),
    ],
  );
}

// One tab without bars, one with a navigation bar and a toolbar.
class _Bare extends StatefulWidget {
  const _Bare();

  @override
  State<_Bare> createState() => _BareState();
}

class _BareState extends State<_Bare> {
  final controller = GlassTabController(initialIndex: 1);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    controller: controller,
    tabs: [
      GlassTab(
        icon: const SizedBox.square(dimension: 24),
        label: const Text('Bare'),
        builder: (context) => const SizedBox.expand(),
      ),
      GlassTab(
        icon: const SizedBox.square(dimension: 24),
        label: const Text('Barred'),
        builder: (context) => GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: const Text('Barred'),
            trailing: [
              GlassBarItem(label: const Text('Edit'), onPressed: () {}),
            ],
          ),
          toolbar: GlassToolbar(
            items: [
              GlassBarItem(label: const Text('Share'), onPressed: () {}),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ],
  );
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the bar stands 21 points from the bottom and a tab is built '
      'when first selected', (tester) async {
    await _phone(tester);
    final built = <int>[];
    await tester.pumpWidget(_app(_Shell(built: built)));
    expect(built, [0]);
    final bar = tester.getRect(find.byType(RawGlassSelector));
    expect(bar.bottom, 874 - 21);
    expect(bar.center.dx, 201);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(built.toSet(), {0, 1});
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 0'), findsNothing);
  });

  testWidgets('a tab without bars shows none of the tab it left, and the '
      'bars come back with their tab', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: const _Bare(),
      ),
    );
    await _frames(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    await tester.tap(find.text('Bare'));
    await _frames(tester);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Share'), findsNothing);
    await tester.tap(find.text('Barred'));
    await _frames(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('a tab left keeps its state', (tester) async {
    await _phone(tester);
    final built = <int>[];
    await tester.pumpWidget(_app(_Shell(built: built)));
    await tester.tap(find.text('Tab 0 0'));
    await tester.pump();
    expect(find.text('Tab 0 1'), findsOneWidget);
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text('Tab 0 1'), findsOneWidget);
  });

  testWidgets('a page in a tab scrolls clear of the bar and draws no edge '
      'effect under it', (tester) async {
    await _phone(tester);
    final built = <int>[];
    await tester.pumpWidget(_app(_Shell(built: built)));
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    for (var i = 0; i < 3; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('0.39'))).dy,
      874 - 21 - 62,
    );
    final edges = tester
        .widgetList<ScrollEdgeBand>(find.byType(ScrollEdgeBand))
        .map((edge) => edge.details.edge);
    expect(edges, isNot(contains(AxisDirection.down)));
  });

  testWidgets('a page that hides the tab bar slides it away while it shows, '
      'so its toolbar takes the taps; a page pushed on it and another tab '
      'bring the bar back', (tester) async {
    await _phone(tester);
    final tabs = GlassTabController();
    addTearDown(tabs.dispose);
    var shared = 0;
    var hides = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return GlassTabScaffold(
              controller: tabs,
              tabs: [
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: const Text('One'),
                  builder: (context) => GlassPageScaffold(
                    hidesTabBar: hides,
                    toolbar: GlassToolbar(
                      items: [
                        GlassBarItem(
                          label: const Text('Share'),
                          onPressed: () => shared++,
                        ),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                GlassTab(
                  icon: const SizedBox.square(dimension: 24),
                  label: const Text('Two'),
                  builder: (context) => const SizedBox.expand(),
                ),
              ],
            );
          },
        ),
      ),
    );
    await _frames(tester);
    final bar = find.text('One');
    expect(bar.hitTestable(), findsNothing, reason: 'the bar slid away');
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(shared, 1);

    tabs.push(0, GlassTabPage(child: const SizedBox.expand()));
    await _frames(tester);
    expect(bar.hitTestable(), findsOneWidget, reason: 'the page above shows');
    tabs.pop(0);
    await _frames(tester);
    expect(bar.hitTestable(), findsNothing);

    tabs.index = 1;
    await _frames(tester);
    expect(bar.hitTestable(), findsOneWidget, reason: 'another tab shows');
    tabs.index = 0;
    await _frames(tester);
    expect(bar.hitTestable(), findsNothing);

    rebuild(() => hides = false);
    await _frames(tester);
    expect(bar.hitTestable(), findsOneWidget);
  });

  for (final pad in [false, true]) {
    testWidgets(
      'a scaffold pushed as a page gives the first page of a tab a '
      'back button to the page under it, '
      '${pad ? 'beside a detail on an iPad' : 'on a phone'}',
      (tester) async {
        if (pad) {
          tester.view.physicalSize = const Size(834 * 2, 1210 * 2);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
        } else {
          await _phone(tester);
        }
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFF000000),
            pageRouteBuilder: <T>(settings, builder) =>
                GlassPageRoute<T>(builder: builder, settings: settings),
            builder: (context, child) =>
                GlassScope(renderer: const FlatGlassRenderer(), child: child!),
            home: Builder(
              builder: (context) => GlassPageScaffold(
                navigationBar: const GlassNavigationBar(title: Text('Outer')),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    GlassPageRoute<void>(
                      builder: (context) => GlassTabScaffold(
                        tabs: [
                          for (final name in ['One', 'Two'])
                            GlassTab(
                              icon: const SizedBox.square(dimension: 24),
                              label: Text(name),
                              builder: (context) => GlassPageScaffold(
                                navigationBar: GlassNavigationBar(
                                  title: Text('Inner $name'),
                                  previousPageTitle: 'Outer',
                                ),
                                child: const SizedBox.expand(),
                              ),
                              detailPlaceholder: name == 'One'
                                  ? (context) => const Text('Nothing open')
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                  child: const Center(child: Text('open')),
                ),
              ),
            ),
          ),
        );
        await _frames(tester);
        final back = find.semantics.byPredicate(
          (node) => node.flagsCollection.isButton && node.label == 'Outer',
        );
        Set<int> backs() => {for (final node in back.evaluate()) node.id};
        expect(backs(), isEmpty);
        await tester.tap(find.text('open'));
        await _frames(tester);
        expect(find.text('Inner One'), findsOneWidget);
        expect(backs(), hasLength(1));
        await tester.tap(find.text('Two'));
        await _frames(tester);
        expect(find.text('Inner Two'), findsOneWidget);
        expect(backs(), hasLength(1));
        tester.semantics.tap(back.first);
        await _frames(tester);
        expect(find.text('Inner Two'), findsNothing);
        expect(find.text('open'), findsOneWidget);
        semantics.dispose();
      },
    );
  }

  group('a floating tab bar', () {
    const icon = Key('action');
    List<GlassTabDestination> tabs(int count) => [
      for (var i = 0; i < count; i++)
        GlassTabDestination(
          icon: const SizedBox.square(dimension: 24),
          label: Text('Tab $i'),
        ),
    ];
    GlassTabBar bar(int count, {GlassTabBarAction? action}) => GlassTabBar(
      destinations: tabs(count),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      action: action,
    );
    Rect circle(WidgetTester tester) => tester.getRect(
      find.ancestor(
        of: find.byKey(icon),
        matching: find.byType(RawGlassButton),
      ),
    );

    testWidgets('gives its content the room under the bar and stands the bar '
        'where the scaffold does', (tester) async {
      await _phone(tester);
      double? bottom;
      await tester.pumpWidget(
        _app(
          GlassFloatingTabBar(
            tabBar: bar(3),
            child: Builder(
              builder: (context) {
                bottom = MediaQuery.paddingOf(context).bottom;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      expect(bottom, 21 + 62);
      final rect = tester.getRect(find.byType(RawGlassSelector));
      expect(rect.bottom, 874 - 21);
      expect(rect.center.dx, 201);
      expect(rect.width, lessThan(402 - 42));
    });

    testWidgets('lays out wide on an iPhone in landscape: 44 tall, 20 above '
        'the bottom, at the middle, the content cleared by 64', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(874 * 3, 402 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      double? bottom;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(874, 402),
            devicePixelRatio: 3,
            padding: EdgeInsets.only(left: 62, right: 62, bottom: 20),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GlassScope(
              renderer: const FlatGlassRenderer(),
              child: GlassFloatingTabBar(
                tabBar: bar(4),
                child: Builder(
                  builder: (context) {
                    bottom = MediaQuery.paddingOf(context).bottom;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(bottom, 20 + 44);
      final rect = tester.getRect(find.byType(RawGlassSelector));
      expect(rect.height, 44);
      expect(rect.bottom, 402 - 20);
      expect(rect.center.dx, 437);
      expect(rect.width, lessThan(874 - 2 * 62 - 2 * 38));
    });

    testWidgets('lays a wide bar and its action circle out as one group 640 '
        'wide at the middle, the circle 44', (tester) async {
      tester.view.physicalSize = const Size(874 * 3, 402 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(874, 402),
            devicePixelRatio: 3,
            padding: EdgeInsets.only(left: 62, right: 62, bottom: 20),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GlassScope(
              renderer: const FlatGlassRenderer(),
              child: GlassFloatingTabBar(
                tabBar: bar(
                  4,
                  action: GlassTabBarAction(
                    icon: const SizedBox.square(key: icon, dimension: 24),
                    semanticLabel: 'New',
                    onPressed: () {},
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      expect(circle(tester), const Rect.fromLTWH(713, 338, 44, 44));
      final tabs = tester.getRect(find.byType(RawGlassSelector));
      expect(tabs.left, 117);
      expect(tabs.right, 713 - 8);
      expect(tabs.height, 44);
    });

    testWidgets('puts an action circle at the trailing end and the bar at the '
        'leading one, on one glass group', (tester) async {
      await _phone(tester);
      var pressed = 0;
      final action = GlassTabBarAction(
        icon: const SizedBox.square(key: icon, dimension: 24),
        semanticLabel: 'New',
        onPressed: () => pressed++,
      );
      for (final (count, direction) in [
        (2, TextDirection.ltr),
        (3, TextDirection.ltr),
        (3, TextDirection.rtl),
      ]) {
        await tester.pumpWidget(
          _app(
            Directionality(
              textDirection: direction,
              child: GlassFloatingTabBar(
                tabBar: bar(count, action: action),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        final round = circle(tester);
        final tabs = tester.getRect(find.byType(RawGlassSelector));
        expect(round.size, const Size.square(62));
        expect(round.bottom, 874 - 21);
        expect(tabs.bottom, 874 - 21);
        if (direction == TextDirection.ltr) {
          expect(round.right, 402 - 21);
          expect(tabs.left, 21);
          if (count == 3) {
            expect(tabs.right, round.left - 8);
          } else {
            expect(tabs.right, lessThan(round.left - 8));
          }
        } else {
          expect(round.left, 21);
          expect(tabs.right, 402 - 21);
          expect(tabs.left, round.right + 8);
        }
        expect(
          find.ancestor(
            of: find.byType(RawGlassSelector),
            matching: find.byType(GlassGroup),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byKey(icon),
            matching: find.byType(GlassGroup),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(icon));
      await tester.pump();
      expect(pressed, 1);
      expect(find.bySemanticsLabel('New'), findsOneWidget);
    });

    testWidgets('spans a phone wider than an iPhone, compact across, as '
        "UIKit's compact bar has no width limit", (tester) async {
      tester.view.physicalSize = const Size(600 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(600, 874)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GlassScope(
              renderer: const FlatGlassRenderer(),
              child: GlassFloatingTabBar(
                tabBar: bar(
                  3,
                  action: GlassTabBarAction(
                    icon: const SizedBox.square(key: icon, dimension: 24),
                    semanticLabel: 'New',
                    onPressed: () {},
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      expect(circle(tester).right, 600 - 21);
      expect(tester.getRect(find.byType(RawGlassSelector)).left, 21);
    });
  });
}
