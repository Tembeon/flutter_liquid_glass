import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Results extends StatelessWidget {
  const _Results();

  @override
  Widget build(BuildContext context) {
    final search = GlassSearchController.of(context);
    return Center(
      child: Text('${search.isOpen ? 'searching' : 'idle'} ${search.text}'),
    );
  }
}

Widget _app(GlassSearchController search) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: GlassTabScaffold(
        searchController: search,
        tabs: [
          GlassTab(
            icon: const SizedBox.square(dimension: 24),
            label: const Text('Home'),
            builder: (context) => Center(
              child: Text(
                GlassSearchController.maybeOf(context) == null
                    ? 'no search'
                    : 'has search',
              ),
            ),
          ),
          GlassTab(
            icon: const SizedBox.square(dimension: 24),
            label: const Text('Library'),
            builder: (context) => const SizedBox(),
          ),
        ],
        searchBuilder: (context) => const _Results(),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets("a tab scaffold's pages read its search, which rebuilds them "
      'as it opens and its query changes, and close it', (tester) async {
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(_app(search));
    expect(find.text('has search'), findsOneWidget);
    search.openView();
    await _settle(tester);
    expect(find.text('searching '), findsOneWidget);
    search.text = 'fern';
    await tester.pump();
    expect(find.text('searching fern'), findsOneWidget);
    GlassSearchController.of(tester.element(find.byType(_Results))).closeView();
    await _settle(tester);
    expect(search.isOpen, isFalse);
    expect(find.text('has search'), findsOneWidget);
  });

  testWidgets('outside a scope there is no search', (tester) async {
    late BuildContext seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = context;
          return const SizedBox();
        },
      ),
    );
    expect(GlassSearchController.maybeOf(seen), isNull);
    expect(() => GlassSearchController.of(seen), throwsFlutterError);
  });

  testWidgets('a search given to a scaffold later keeps the state of its '
      'pages', (tester) async {
    final search = GlassSearchController();
    addTearDown(search.dispose);
    Widget app(GlassSearchController? controller) => MediaQuery(
      data: const MediaQueryData(size: Size(402, 874)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          child: GlassTabScaffold(
            searchController: controller,
            tabs: [
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: const Text('Home'),
                builder: (context) => const _Counter(),
              ),
              GlassTab(
                icon: const SizedBox.square(dimension: 24),
                label: const Text('Library'),
                builder: (context) => const SizedBox(),
              ),
            ],
            searchBuilder: (context) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(null));
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;
    await tester.pumpWidget(app(search));
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
