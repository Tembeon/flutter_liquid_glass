import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Plants extends StatefulWidget {
  const _Plants({this.editing = false, this.empty = false});

  final bool editing;
  final bool empty;

  @override
  State<_Plants> createState() => _PlantsState();
}

class _PlantsState extends State<_Plants> {
  Set<Object> selection = {'Fern', 'Fig'};
  final List<Set<Object>> built = [];
  final List<String> log = [];

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF000000),
    pageRouteBuilder: <T>(settings, builder) =>
        GlassPageRoute<T>(builder: builder, settings: settings),
    builder: (context, child) =>
        GlassScope(renderer: const FlatGlassRenderer(), child: child!),
    home: GlassListContextMenu(
      menuBuilder: (context, values) {
        built.add(values);
        if (widget.empty) return const [];
        return [
          GlassMenuItem(
            title: 'Water ${values.length}',
            onPressed: () => log.add('water ${values.join(',')}'),
          ),
        ];
      },
      onPrimaryAction: (values) => log.add('open ${values.join(',')}'),
      child: GlassListEditing(
        editing: widget.editing,
        selection: selection,
        onSelectionChanged: (next) => setState(() => selection = next),
        child: Align(
          alignment: Alignment.topCenter,
          child: GlassListSection(
            children: [
              for (final name in ['Fern', 'Fig', 'Jade'])
                GlassListRow(title: Text(name), value: name),
              GlassListRow(
                title: const Text('Lily'),
                value: 'Lily',
                onPressed: () => log.add('pressed Lily'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _hold(WidgetTester tester, String name) async {
  final finger = await tester.startGesture(tester.getCenter(find.text(name)));
  await _frames(tester, 60);
  await finger.up();
  await _frames(tester, 60);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a held row out of editing opens a menu over its own value', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(const _Plants());
    await _hold(tester, 'Fig');
    expect(find.text('Water 1'), findsOneWidget);
    await tester.tap(find.text('Water 1'));
    await _frames(tester, 60);
    expect(tester.state<_PlantsState>(find.byType(_Plants)).log, [
      'water Fig',
    ]);
  });

  testWidgets('in editing a held row of the selection acts on all of it, '
      'one outside it on itself', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const _Plants(editing: true));
    await _hold(tester, 'Fern');
    expect(find.text('Water 2'), findsOneWidget);
    await tester.tap(find.text('Water 2'));
    await _frames(tester, 60);
    final state = tester.state<_PlantsState>(find.byType(_Plants));
    expect(state.log, ['water Fern,Fig']);
    await _hold(tester, 'Jade');
    expect(find.text('Water 1'), findsOneWidget);
    await tester.tap(find.text('Water 1'));
    await _frames(tester, 60);
    expect(state.log, ['water Fern,Fig', 'water Jade']);
  });

  testWidgets('a tap runs the primary action on a row without its own '
      'press, out of editing; in editing it selects', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const _Plants());
    final state = tester.state<_PlantsState>(find.byType(_Plants));
    await tester.tap(find.text('Jade'));
    await _frames(tester, 30);
    await tester.tap(find.text('Lily'));
    await _frames(tester, 30);
    expect(state.log, ['open Jade', 'pressed Lily']);
    await tester.pumpWidget(const _Plants(editing: true));
    await tester.tap(find.text('Jade'));
    await _frames(tester, 30);
    expect(state.log, ['open Jade', 'pressed Lily']);
    expect(state.selection, {'Fern', 'Fig', 'Jade'});
  });

  testWidgets('no entries, no menu', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const _Plants(empty: true));
    await _hold(tester, 'Fig');
    expect(find.textContaining('Water'), findsNothing);
    expect(
      tester.state<_PlantsState>(find.byType(_Plants)).built,
      anyElement(equals({'Fig'})),
    );
  });
}
