import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

Widget _page(String name) => GlassPageScaffold(
  navigationBar: GlassNavigationBar(title: Text('$name bar')),
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Counter(name),
        Builder(
          builder: (context) => GestureDetector(
            onTap: () => Navigator.of(context).push(
              GlassPageRoute<void>(
                builder: (context) => _page('$name.routed'),
              ),
            ),
            child: Text('route $name'),
          ),
        ),
      ],
    ),
  ),
);

class _List extends StatelessWidget {
  const _List();

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: const GlassNavigationBar(title: Text('List bar')),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Counter('List'),
        for (final name in ['A', 'B'])
          GestureDetector(
            onTap: () => GlassTabStack.of(context).push(_Opener(name)),
            child: Text('open $name'),
          ),
      ],
    ),
  );
}

class _Opener extends StatelessWidget {
  const _Opener(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(title: Text('$name bar')),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Counter(name),
        GestureDetector(
          onTap: () => GlassTabStack.of(context).push(_page('$name.next')),
          child: Text('deeper $name'),
        ),
      ],
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  GlassTabController controller,
  Size size,
) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: GlassTabScaffold(
          controller: controller,
          tabs: [
            GlassTab(
              icon: const SizedBox.square(dimension: 24),
              label: const Text('Mail'),
              builder: (context) => const _List(),
              detailPlaceholder: (context) => const Text('Nothing open'),
            ),
            GlassTab(
              icon: const SizedBox.square(dimension: 24),
              label: const Text('Plain'),
              builder: (context) => _page('Plain'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

int _taps(WidgetTester tester, String name) => tester
    .state<_CounterState>(
      find.ancestor(
        of: find.textContaining(RegExp('^$name [0-9]+\$')),
        matching: find.byType(_Counter),
      ),
    )
    .taps;

// The back buttons on screen, named as the bar names them: after the page
// below.
Iterable<String> _backs(WidgetTester tester) => find.semantics
    .byPredicate(
      (node) =>
          node.flagsCollection.isButton &&
          node.label.endsWith(' bar') &&
          !node.label.startsWith('open'),
    )
    .evaluate()
    .map((node) => node.label);

const _phone = Size(402, 874);
const _pad = Size(834, 1210);

void main() {
  setUp(MotionClock.debugReset);

  group('GlassTabController', () {
    test('pushes, pops and sets the pages of each tab apart', () {
      final controller = GlassTabController();
      addTearDown(controller.dispose);
      var heard = 0;
      controller.addListener(() => heard++);
      final a = GlassTabPage(child: const SizedBox());
      final b = GlassTabPage(child: const SizedBox());
      controller
        ..push(0, a)
        ..push(0, b)
        ..push(1, GlassTabPage(child: const SizedBox()));
      expect(controller.pagesOf(0), [a, b]);
      expect(controller.pagesOf(1), hasLength(1));
      controller.pop(0);
      expect(controller.pagesOf(0), [a]);
      controller.popToRoot(1);
      expect(controller.pagesOf(1), isEmpty);
      controller
        ..setPages(0, [b])
        ..index = 1;
      expect(controller.pagesOf(0), [b]);
      expect(controller.index, 1);
      expect(heard, 7);
      controller
        ..pop(1)
        ..index = 1
        ..setPages(0, [b]);
      expect(heard, 7, reason: 'nothing changed');
    });
  });

  testWidgets('on a phone a push covers the list and a back pops it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    expect(find.text('List bar'), findsOneWidget);
    await tester.tap(find.text('open A'));
    await _settle(tester);
    expect(controller.pagesOf(0), hasLength(1));
    expect(find.text('A 0'), findsOneWidget);
    expect(find.text('List 0'), findsNothing);
    expect(_backs(tester), ['List bar']);
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await _settle(tester);
    expect(controller.pagesOf(0), isEmpty);
    expect(find.text('List 0'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('on an iPad a list tab shows its root beside the placeholder, '
      'a push from the list replaces the detail and a push from the detail '
      'goes on top', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _pad);
    expect(find.text('List bar'), findsOneWidget);
    expect(find.text('Nothing open'), findsOneWidget);
    await tester.tap(find.text('open A'));
    await _settle(tester);
    expect(find.text('Nothing open'), findsNothing);
    expect(find.text('A 0'), findsOneWidget);
    expect(find.text('List 0'), findsOneWidget);
    expect(
      _backs(tester),
      isEmpty,
      reason: 'the first page of the detail column has no back button',
    );
    await tester.tap(find.text('open B'));
    await _settle(tester);
    expect(controller.pagesOf(0), hasLength(1));
    expect(find.text('B 0'), findsOneWidget);
    expect(find.text('A 0'), findsNothing);
    await tester.tap(find.text('deeper B'));
    await _settle(tester);
    expect(controller.pagesOf(0), hasLength(2));
    expect(find.text('B.next 0'), findsOneWidget);
    expect(find.text('List 0'), findsOneWidget);
    expect(_backs(tester), ['B bar']);
    semantics.dispose();
  });

  testWidgets('a page keeps its state when the width flips under it', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    await tester.tap(find.text('List 0'));
    await tester.pump();
    await tester.tap(find.text('open A'));
    await _settle(tester);
    await tester.tap(find.text('A 0'));
    await tester.pump();
    await tester.tap(find.text('A 1'));
    await tester.pump();
    final page = tester.state<_CounterState>(
      find.ancestor(of: find.text('A 2'), matching: find.byType(_Counter)),
    );

    await _pump(tester, controller, _pad);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('A 2'), findsOneWidget);
    expect(find.text('List 1'), findsOneWidget);
    expect(
      tester.state<_CounterState>(
        find.ancestor(of: find.text('A 2'), matching: find.byType(_Counter)),
      ),
      same(page),
    );

    await _pump(tester, controller, _phone);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('A 2'), findsOneWidget);
    expect(_taps(tester, 'A'), 2);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(controller.pagesOf(0), isEmpty);
    expect(find.text('List 1'), findsOneWidget);
  });

  testWidgets('a flip in the middle of a push lands the page at rest', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    await tester.tap(find.text('open A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await _pump(tester, controller, _pad);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('A 0'), findsOneWidget);
    await _pump(tester, controller, _phone);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('A bar')).dx,
      lessThan(_phone.width / 2),
      reason: 'the page stands at rest over the list',
    );
  });

  testWidgets('the system back pops the shown tab alone', (tester) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    await tester.tap(find.text('open A'));
    await _settle(tester);
    await tester.tap(find.text('Plain'));
    await _settle(tester);
    expect(find.text('Plain 0'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(
      controller.pagesOf(0),
      hasLength(1),
      reason: 'the tab left keeps its page',
    );
  });

  testWidgets('a route a page pushes on its tab goes back with the system '
      'back, under the tab bar', (tester) async {
    final controller = GlassTabController(initialIndex: 1);
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    await tester.tap(find.text('route Plain'));
    await _settle(tester);
    expect(find.text('Plain.routed 0'), findsOneWidget);
    expect(find.text('Mail'), findsWidgets, reason: 'the tab bar stays');
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await _settle(tester);
    expect(find.text('Plain.routed 0'), findsNothing);
    expect(find.text('Plain 0'), findsOneWidget);
  });

  testWidgets('selecting the selected tab again pops it to its root', (
    tester,
  ) async {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, _phone);
    await tester.tap(find.text('open A'));
    await _settle(tester);
    await tester.tap(find.text('deeper A'));
    await _settle(tester);
    expect(controller.pagesOf(0), hasLength(2));
    await tester.tap(find.text('Mail').last);
    await _settle(tester);
    expect(controller.pagesOf(0), isEmpty);
    expect(find.text('List 0'), findsOneWidget);
  });
}
