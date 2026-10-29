import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/scroll_edge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassTheme(
      data: const GlassThemeData(renderer: GlassRenderer.flat()),
      child: child,
    ),
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

class _Shell extends StatefulWidget {
  const _Shell({required this.built});

  final List<int> built;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabBar: GlassTabBar(
      destinations: const [
        GlassTabDestination(
          icon: SizedBox.square(dimension: 24),
          label: Text('One'),
        ),
        GlassTabDestination(
          icon: SizedBox.square(dimension: 24),
          label: Text('Two'),
        ),
      ],
      selectedIndex: index,
      onDestinationSelected: (next) => setState(() => index = next),
    ),
    tabBuilder: (context, i) {
      widget.built.add(i);
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
  );
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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
        .widgetList<ScrollEdge>(find.byType(ScrollEdge))
        .map((edge) => edge.details.edge);
    expect(edges, isNot(contains(AxisDirection.down)));
  });
}
