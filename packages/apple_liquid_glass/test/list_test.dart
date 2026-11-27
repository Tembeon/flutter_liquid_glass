import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

const _infoOut = (25.67 - 44) / 2;

Widget _app(Widget child, {GlassThemeData theme = const GlassThemeData()}) =>
    MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          renderer: const FlatGlassRenderer(),
          data: theme.merge(
            const GlassThemeData(),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 402, child: child),
          ),
        ),
      ),
    );

Widget _keyApp(Widget child, {Map<ShortcutActivator, Intent>? shortcuts}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      shortcuts: shortcuts,
      builder: (context, _) => GlassScope(
        renderer: const FlatGlassRenderer(),
        child: FocusScope(
          autofocus: true,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 402, child: child),
          ),
        ),
      ),
    );

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

// The light highlight, systemGray4.
const _highlight = Color(0xFFD1D1D6);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a section can leave its separators out, and a row can say '
      'otherwise for itself; the last row has none', (tester) async {
    final separators = find.byWidgetPredicate(
      (widget) => '${widget.runtimeType}' == '_RowSeparator',
    );
    Widget section({required bool shows, bool? first}) => _app(
      GlassListSection(
        showsSeparators: shows,
        children: [
          GlassListRow(title: const Text('One'), showsSeparator: first),
          const GlassListRow(title: Text('Two')),
          const GlassListRow(title: Text('Three')),
        ],
      ),
    );
    await tester.pumpWidget(section(shows: true));
    expect(separators, findsNWidgets(2));
    await tester.pumpWidget(section(shows: false));
    expect(separators, findsNothing);
    await tester.pumpWidget(section(shows: false, first: true));
    expect(separators, findsOneWidget);
    await tester.pumpWidget(section(shows: true, first: false));
    expect(separators, findsOneWidget);
  });

  testWidgets('a section lays its rows on an inset card with separators '
      'between them', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassListSection(
          header: Text('Header'),
          footer: Text('Footer'),
          children: [
            GlassListRow(title: Text('One')),
            GlassListRow(title: Text('Two')),
          ],
        ),
      ),
    );
    final section = tester.getRect(find.byType(GlassListSection));
    final one = tester.getRect(find.byType(GlassListRow).first);
    expect(one.left - section.left, 16);
    expect(one.width, 370);
    expect(one.height, 53);
    expect(tester.getTopLeft(find.text('One')).dx - section.left, 36);
    expect(one.left - section.left, GlassListSection.margin);
    expect(
      tester.getTopLeft(find.text('One')).dx - one.left,
      GlassListSection.contentInset,
    );
    expect(
      find.byType(GlassListRow).first,
      paints..something((method, arguments) {
        if (method != #drawRect) return false;
        final rect = arguments[0] as Rect;
        return rect.height == 1 && rect.left == 20 && rect.right == 370 - 20;
      }),
    );
    final separator = GlassColors.separator.color;
    expect(find.byType(GlassListRow).first, paints..rect(color: separator));
    expect(
      find.byType(GlassListRow).last,
      isNot(paints..rect(color: separator)),
    );
  });

  testWidgets('a grouped section runs its card across the list with the '
      'text 16 in, separators from 20 and lines across its top and bottom', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            GlassListSection(
              layout: GlassListLayout.grouped,
              header: Text('Controls'),
              children: [
                GlassListRow(title: Text('One')),
                GlassListRow(
                  leading: Icon(IconData(0xe000)),
                  title: Text('Two'),
                ),
                GlassListRow(title: Text('Three')),
              ],
            ),
          ],
        ),
      ),
    );
    final section = tester.getRect(find.byType(GlassListSection));
    final one = tester.getRect(find.byType(GlassListRow).first);
    expect(one.left, section.left);
    expect(one.width, 402);
    final label = tester.getSize(find.text('Controls')).height;
    expect(one.top - section.top, moreOrLessEquals(11.67 + label + 6));
    expect(tester.getTopLeft(find.text('Controls')).dx - section.left, 16);
    expect(tester.getTopLeft(find.text('One')).dx - section.left, 16);
    expect(tester.getTopLeft(find.text('Two')).dx - section.left, 56);
    bool line(Rect rect, double left, double right) =>
        rect.height == 1 && rect.left == left && rect.right == right;
    expect(
      find.byType(GlassListRow).first,
      paints..something(
        (method, arguments) =>
            method == #drawRect && line(arguments[0] as Rect, 20, 386),
      ),
    );
    expect(
      find.byType(GlassListRow).at(1),
      paints..something(
        (method, arguments) =>
            method == #drawRect && line(arguments[0] as Rect, 56, 386),
      ),
    );
    final card = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          '${widget.foregroundPainter.runtimeType}' == '_EdgeLines',
    );
    for (final edge in [
      const Rect.fromLTWH(0, 0, 402, 1),
      const Rect.fromLTWH(0, 53 * 3 - 1, 402, 1),
    ]) {
      expect(
        card,
        paints..something(
          (method, arguments) => method == #drawRect && arguments[0] == edge,
        ),
      );
    }
  });

  testWidgets('a plain section stands on systemBackground, its header 22 '
      'below the rows above and 28 tall, the last row separated but before '
      'a footer', (tester) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            GlassListSection(
              layout: GlassListLayout.plain,
              header: Text('Controls'),
              footer: Text('Footer'),
              children: [
                GlassListRow(title: Text('One')),
                GlassListRow(title: Text('Two')),
              ],
            ),
            GlassListSection(
              layout: GlassListLayout.plain,
              children: [GlassListRow(title: Text('Three'))],
            ),
          ],
        ),
      ),
    );
    final first = tester.getRect(find.byType(GlassListSection).first);
    final one = tester.getRect(find.byType(GlassListRow).first);
    final two = tester.getRect(find.byType(GlassListRow).at(1));
    final three = tester.getRect(find.byType(GlassListRow).last);
    final label = tester.getSize(find.text('Controls')).height;
    expect(
      one.top - first.top,
      moreOrLessEquals(22 + 28 - 20.33 + label, epsilon: 0.01),
    );
    expect(
      tester.getTopLeft(find.text('Controls')).dy - first.top,
      moreOrLessEquals(26, epsilon: 0.01),
    );
    expect(
      first.bottom - two.bottom,
      moreOrLessEquals(
        28 - 15.67 + tester.getSize(find.text('Footer')).height,
        epsilon: 0.01,
      ),
    );
    expect(
      tester.getTopLeft(find.text('Footer')).dy - two.bottom,
      moreOrLessEquals(6, epsilon: 0.01),
    );
    expect(three.top, first.bottom);
    expect(one.width, 402);
    final separator = GlassColors.separator.color;
    expect(
      find.byType(GlassListRow).at(1),
      isNot(paints..rect(color: separator)),
    );
    expect(find.byType(GlassListRow).last, paints..rect(color: separator));
    expect(
      find
          .ancestor(of: find.text('Three'), matching: find.byType(ColoredBox))
          .evaluate()
          .map((e) => (e.widget as ColoredBox).color.toARGB32()),
      contains(0xFFFFFFFF),
    );
  });

  testWidgets('a card stands its margin inside the safe area, as beside a '
      'tab sidebar or on an iPhone in landscape', (tester) async {
    Widget padded(Widget child) => _app(
      MediaQuery(
        data: const MediaQueryData(
          devicePixelRatio: 3,
          padding: EdgeInsets.only(left: 59, right: 47),
        ),
        child: SizedBox(height: 600, child: child),
      ),
    );
    await tester.pumpWidget(
      padded(
        const GlassListSection(children: [GlassListRow(title: Text('One'))]),
      ),
    );
    var list = tester.getRect(find.byType(GlassListSection));
    var row = tester.getRect(find.byType(GlassListRow));
    expect(row.left - list.left, 59 + GlassListSection.margin);
    expect(list.right - row.right, 47 + GlassListSection.margin);

    await tester.pumpWidget(
      padded(
        CustomScrollView(
          slivers: [
            GlassSliverListSection(
              itemCount: 1,
              itemBuilder: (context, index) =>
                  const GlassListRow(title: Text('One')),
            ),
          ],
        ),
      ),
    );
    list = tester.getRect(find.byType(CustomScrollView));
    row = tester.getRect(find.byType(GlassListRow));
    expect(row.left - list.left, 59 + GlassListSection.margin);
    expect(list.right - row.right, 47 + GlassListSection.margin);
  });

  testWidgets('a symbol puts the text at 60 points; a wider image keeps its '
      'size and moves the text and separator along', (tester) async {
    const image = Key('image');
    await tester.pumpWidget(
      _app(
        const GlassListSection(
          children: [
            GlassListRow(leading: Icon(IconData(0x41)), title: Text('One')),
            GlassListRow(
              leading: SizedBox.square(key: image, dimension: 30),
              title: Text('Two'),
            ),
            GlassListRow(title: Text('Three')),
          ],
        ),
      ),
    );
    final one = tester.getRect(find.byType(GlassListRow).first);
    expect(tester.getTopLeft(find.text('One')).dx - one.left, 60);
    expect(tester.getSize(find.byKey(image)), const Size.square(30));
    expect(tester.getTopLeft(find.byKey(image)).dx - one.left, 20);
    expect(tester.getTopLeft(find.text('Two')).dx - one.left, 66);
    expect(
      find.byType(GlassListRow).at(1),
      paints..something((method, arguments) {
        if (method != #drawRect) return false;
        final rect = arguments[0] as Rect;
        return rect.height == 1 && rect.left == 66;
      }),
    );
  });

  testWidgets('each accessory sits in its measured box and end inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const GlassListSection(
          children: [
            GlassListRow(
              title: Text('Check'),
              accessory: GlassListAccessory.checkmark,
            ),
            GlassListRow(
              title: Text('Info'),
              accessory: GlassListAccessory.detailButton,
            ),
            GlassListRow(
              title: Text('More'),
              accessory: GlassListAccessory.disclosureIndicator,
            ),
          ],
        ),
      ),
    );
    final card = tester.getRect(find.byType(GlassListRow).first);
    Rect accessoryOf(int row) => tester.getRect(
      find
          .descendant(
            of: find.byType(GlassListRow).at(row),
            matching: find.byType(CustomPaint),
          )
          .last,
    );

    final check = accessoryOf(0);
    expect(check.size, const Size(19, 17.33));
    expect(card.right - check.right, closeTo(22.5, 1e-9));
    final info = accessoryOf(1);
    expect(info.width, closeTo(25.67, 1e-9));
    expect(info.height, closeTo(25.67, 1e-9));
    expect(card.right - info.right, closeTo(19.17, 1e-9));
    final chevron = accessoryOf(2);
    expect(chevron.width, closeTo(10.33, 1e-9));
    expect(chevron.height, 14);
    expect(card.right - chevron.right, closeTo(20, 1e-9));
  });

  testWidgets('a tap presses the row and its highlight fades after it', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        GlassListSection(
          children: [
            GlassListRow(title: const Text('Row'), onPressed: () => pressed++),
          ],
        ),
      ),
    );
    final row = find.byType(GlassListRow);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(_frame);
    expect(row, paints..path(color: _highlight));
    await gesture.up();
    expect(pressed, 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(row, isNot(paints..path(color: _highlight)));
    await _settle(tester);
    expect(row, isNot(paints..path(color: const Color(0x01D1D1D6))));
  });

  testWidgets('a selected row keeps its fill through taps and fades it out '
      'when another row is selected; a screen reader reads it as selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return GlassListSection(
              children: [
                for (var i = 0; i < 3; i++)
                  GlassListRow(
                    title: Text('Page $i'),
                    selected: selected == i,
                    onPressed: i == 2
                        ? null
                        : () => setState(() => selected = i),
                  ),
              ],
            );
          },
        ),
      ),
    );
    Finder row(int i) => find.widgetWithText(GlassListRow, 'Page $i');
    expect(row(0), paints..path(color: _highlight));
    expect(row(1), isNot(paints..path(color: _highlight)));
    expect(
      tester.getSemantics(find.text('Page 0')),
      matchesSemantics(
        label: 'Page 0',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );

    await tester.tap(row(0));
    await _settle(tester);
    expect(row(0), paints..path(color: _highlight));

    await tester.tap(row(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(row(1), paints..path(color: _highlight));
    expect(row(0), isNot(paints..path(color: _highlight)));
    await _settle(tester);
    expect(row(1), paints..path(color: _highlight));
    expect(row(0), isNot(paints..path(color: const Color(0x01D1D1D6))));

    update(() => selected = 2);
    await tester.pump();
    expect(row(2), paints..path(color: _highlight));
    await _settle(tester);
    expect(row(1), isNot(paints..path(color: const Color(0x01D1D1D6))));
    expect(row(2), paints..path(color: _highlight));
    semantics.dispose();
  });

  testWidgets('a hold of 0.5 s calls onLongPress, takes the fill away and '
      'presses nothing on release; a quicker tap presses; a row that only '
      'holds does not fill and reads its long press', (tester) async {
    final semantics = tester.ensureSemantics();
    var pressed = 0;
    var held = 0;
    await tester.pumpWidget(
      _app(
        GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Both'),
              onPressed: () => pressed++,
              onLongPress: () => held++,
            ),
            GlassListRow(
              title: const Text('Version'),
              onLongPress: () => held++,
            ),
          ],
        ),
      ),
    );
    final both = find.widgetWithText(GlassListRow, 'Both');
    var gesture = await tester.startGesture(tester.getCenter(both));
    await tester.pump(const Duration(milliseconds: 300));
    expect(both, paints..path(color: _highlight));
    expect(held, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(held, 1);
    expect(both, isNot(paints..path(color: _highlight)));
    await gesture.up();
    await _settle(tester);
    expect(pressed, 0);

    await tester.tap(both);
    await _settle(tester);
    expect(pressed, 1);
    expect(held, 1);

    final version = find.widgetWithText(GlassListRow, 'Version');
    gesture = await tester.startGesture(tester.getCenter(version));
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 300));
    expect(version, isNot(paints..path(color: _highlight)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(held, 2);
    await gesture.up();
    await _settle(tester);
    expect(
      tester.getSemantics(find.text('Version')),
      matchesSemantics(
        label: 'Version',
        hasLongPressAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('inside a scroll view a drag scrolls and takes the touch '
      'from the row', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 400,
          child: ListView(
            children: [
              for (var i = 0; i < 20; i++)
                GlassListRow(
                  title: Text('Row $i'),
                  onPressed: () => pressed++,
                ),
            ],
          ),
        ),
      ),
    );
    final row = find.widgetWithText(GlassListRow, 'Row 1');
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 50));
    expect(row, isNot(paints..path(color: _highlight)));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(_frame);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 200));
    expect(row, isNot(paints..path(color: _highlight)));
    await gesture.up();
    await _settle(tester);
    expect(pressed, 0);

    await tester.tap(find.widgetWithText(GlassListRow, 'Row 5'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('the info button calls its own callback; a checkmark reads as '
      'selected', (tester) async {
    final semantics = tester.ensureSemantics();
    var row = 0;
    var info = 0;
    await tester.pumpWidget(
      _app(
        GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Info'),
              accessory: GlassListAccessory.detailDisclosureButton,
              onPressed: () => row++,
              onAccessoryPressed: () => info++,
            ),
            const GlassListRow(
              title: Text('Chosen'),
              accessory: GlassListAccessory.checkmark,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('More info'));
    await _settle(tester);
    expect(info, 1);
    expect(row, 0);
    expect(
      tester.getSemantics(find.text('Chosen')),
      matchesSemantics(
        label: 'Chosen',
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the info button is a Tab stop of its own after the row; the '
      "app's activation keys press the one that has focus", (tester) async {
    var row = 0;
    var info = 0;
    Widget list({Map<ShortcutActivator, Intent>? shortcuts}) => _keyApp(
      GlassListSection(
        children: [
          GlassListRow(
            title: const Text('Wi-Fi'),
            accessory: GlassListAccessory.detailDisclosureButton,
            onPressed: () => row++,
            onAccessoryPressed: () => info++,
          ),
        ],
      ),
      shortcuts: shortcuts,
    );
    await tester.pumpWidget(list());
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect((row, info), (1, 0));
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect((row, info), (1, 1));
    await _settle(tester);

    await tester.pumpWidget(
      list(
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.space):
              const DoNothingAndStopPropagationIntent(),
          const SingleActivator(LogicalKeyboardKey.keyI):
              const ActivateIntent(),
        },
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _tab(tester);
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect((row, info), (1, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect((row, info), (1, 2));
    await _settle(tester);
  });

  testWidgets('the info button reads as a localized button over its 44 '
      'point target; a row that only displays is no button and no stop', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var info = 0;
    await tester.pumpWidget(
      _keyApp(
        GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Network'),
              accessory: GlassListAccessory.detailButton,
              onAccessoryPressed: () => info++,
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('More info')),
      matchesSemantics(
        label: 'More info',
        rect: const Rect.fromLTWH(_infoOut, _infoOut, 44, 44),
        textDirection: TextDirection.ltr,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Network')),
      matchesSemantics(label: 'Network'),
    );
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(info, 1);
    tester.semantics.tap(find.semantics.byLabel('More info'));
    expect(info, 2);
    await _settle(tester);
    semantics.dispose();
  });

  testWidgets("a tap in the info button's 44 point extension presses it; "
      'one beyond does not', (tester) async {
    var info = 0;
    await tester.pumpWidget(
      _app(
        GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Network'),
              accessory: GlassListAccessory.detailButton,
              onAccessoryPressed: () => info++,
            ),
          ],
        ),
      ),
    );
    final glyph = tester.getRect(
      find
          .descendant(
            of: find.byType(InputRegion),
            matching: find.byType(CustomPaint),
          )
          .last,
    );
    expect(glyph.width, closeTo(25.67, 1e-9));
    expect(glyph.height, closeTo(25.67, 1e-9));
    for (final offset in const [
      Offset(21, 0),
      Offset(0, -21),
      Offset(-21, 0),
    ]) {
      await tester.tapAt(glyph.center + offset);
      await _settle(tester);
    }
    expect(info, 3);
    await tester.tapAt(glyph.center + const Offset(0, 23));
    await _settle(tester);
    expect(info, 3);
  });

  testWidgets('a disabled row disables its info button: no Tab stop, '
      'announced as disabled', (tester) async {
    final semantics = tester.ensureSemantics();
    var info = 0;
    await tester.pumpWidget(
      _keyApp(
        GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Network'),
              accessory: GlassListAccessory.detailButton,
              enabled: false,
              onPressed: () {},
              onAccessoryPressed: () => info++,
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('More info')),
      matchesSemantics(
        label: 'More info',
        rect: const Rect.fromLTWH(_infoOut, _infoOut, 44, 44),
        textDirection: TextDirection.ltr,
        isButton: true,
        hasEnabledState: true,
      ),
    );
    await _tab(tester);
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(find.bySemanticsLabel('More info'), warnIfMissed: false);
    await _settle(tester);
    expect(info, 0);
    semantics.dispose();
  });

  testWidgets('a disabled row takes no press', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        GlassListSection(
          children: [
            GlassListRow(
              title: const Text('Off'),
              enabled: false,
              onPressed: () => pressed++,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Off'));
    await _settle(tester);
    expect(pressed, 0);
  });

  testWidgets('a disabled row dims its text and symbol; a row without a '
      'press keeps its colors', (tester) async {
    final symbols = <String, Color?>{};
    Widget row(String title, {bool enabled = true, VoidCallback? onPressed}) =>
        GlassListRow(
          leading: Builder(
            builder: (context) {
              symbols[title] = IconTheme.of(context).color;
              return const SizedBox.square(dimension: 22);
            },
          ),
          title: Text(title),
          subtitle: Text('$title subtitle'),
          detail: Text('$title detail'),
          enabled: enabled,
          onPressed: onPressed,
        );
    await tester.pumpWidget(
      _app(
        GlassListSection(
          children: [
            row('Off', enabled: false, onPressed: () {}),
            row('Inert'),
          ],
        ),
      ),
    );
    Color? colorOf(String text) =>
        tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color;

    expect(colorOf('Off'), isSameColorAs(const Color(0x4C3C3C43)));
    expect(symbols['Off'], isSameColorAs(const Color(0x4C3C3C43)));
    expect(colorOf('Off subtitle'), isSameColorAs(const Color(0x2D3C3C43)));
    expect(colorOf('Off detail'), isSameColorAs(const Color(0x2D3C3C43)));
    expect(colorOf('Inert'), isSameColorAs(const Color(0xFF000000)));
    expect(symbols['Inert'], isSameColorAs(const Color(0xFF0088FF)));
    expect(colorOf('Inert subtitle'), isSameColorAs(const Color(0x993C3C43)));
  });

  testWidgets('a sliver section builds only the rows in view', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 400,
          child: CustomScrollView(
            slivers: [
              GlassSliverListSection(
                header: const Text('Many'),
                itemCount: 500,
                itemBuilder: (context, i) {
                  built.add(i);
                  return GlassListRow(title: Text('Row $i'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(built.length, lessThan(20));
    expect(find.text('Many'), findsOneWidget);
  });

  group('a detail', () {
    Widget section(
      String title,
      String detail, {
      double scale = 1,
      TextDirection direction = TextDirection.ltr,
    }) => _app(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: direction,
            child: GlassListSection(
              children: [
                GlassListRow(title: Text(title), detail: Text(detail)),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('that fits beside the title sits at the trailing edge, up to '
        'the largest standard text size', (tester) async {
      for (final scale in [1.0, 23 / 17]) {
        await tester.pumpWidget(section('Width', '94', scale: scale));
        final card = tester.getRect(find.byType(GlassListRow));
        final title = tester.getRect(find.text('Width'));
        final detail = tester.getRect(find.text('94'));
        expect(title.left, card.left + 20);
        expect(detail.right, card.right - 20);
        expect(detail.center.dy, title.center.dy);
      }
    });

    testWidgets('that does not fit beside the title goes under it, 4 points '
        'down from its start, and leaves the title whole', (tester) async {
      for (final direction in TextDirection.values) {
        await tester.pumpWidget(
          section('Appearance', 'Light, spacious', direction: direction),
        );
        final card = tester.getRect(find.byType(GlassListRow));
        final title = tester.getRect(find.text('Appearance'));
        final detail = tester.getRect(find.text('Light, spacious'));
        expect(title.height, 17, reason: 'one line');
        expect(detail.top, title.bottom + 4);
        if (direction == TextDirection.ltr) {
          expect(detail.left, title.left);
          expect(title.left, card.left + 20);
        } else {
          expect(detail.right, title.right);
          expect(title.right, card.right - 20);
        }
        expect(card.height, 15.5 + title.height + 4 + detail.height + 15.5);
      }
    });

    testWidgets('goes under the title at the accessibility text sizes, where '
        'it would fit beside it', (tester) async {
      await tester.pumpWidget(section('Width', '94', scale: 40 / 17));
      final card = tester.getRect(find.byType(GlassListRow));
      final title = tester.getRect(find.text('Width'));
      final detail = tester.getRect(find.text('94'));
      expect(title.width + 8 + detail.width, lessThan(card.width - 40));
      expect(detail.top, title.bottom + 4);
      expect(detail.left, title.left);
    });
  });

  testWidgets('the theme styles the rows and a header reads as a header', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const GlassListSection(
          header: Text('Section'),
          children: [GlassListRow(title: Text('Row'), detail: Text('Value'))],
        ),
        theme: const GlassThemeData(
          styles: [
            GlassListStyle(
              secondaryColor: WidgetStatePropertyAll(Color(0xFF123456)),
            ),
          ],
        ),
      ),
    );
    final detail = tester.renderObject<RenderParagraph>(find.text('Value'));
    expect(detail.text.style!.color, isSameColorAs(const Color(0xFF123456)));
    expect(
      tester.getSemantics(find.text('Section')),
      matchesSemantics(label: 'Section', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets("the list style's text styles set the rows' and labels' type "
      "over the theme, their colors stay the roles', and a row is as tall as "
      'its text needs but no less than its least height', (tester) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            GlassListSection(
              header: const Text('Header'),
              footer: const Text('Footer'),
              style: const GlassListStyle(
                titleTextStyle: TextStyle(fontSize: 14),
                minRowHeight: 30,
              ),
              children: [
                const GlassListRow(
                  title: Text('Title'),
                  subtitle: Text('Subtitle'),
                  detail: Text('Value'),
                ),
                GlassListRow(
                  title: const Text('Short'),
                  style: const GlassListStyle(subtitleTextStyle: TextStyle()),
                  onPressed: () {},
                ),
              ],
            ),
            const GlassListSection(
              style: GlassListStyle(minRowHeight: 60),
              children: [GlassListRow(title: Text('Tall'))],
            ),
          ],
        ),
        theme: const GlassThemeData(
          fontFamily: 'Mono',
          styles: [
            GlassListStyle(
              titleTextStyle: TextStyle(fontSize: 15, color: Color(0xFFFF0000)),
              subtitleTextStyle: TextStyle(fontSize: 12),
              detailTextStyle: TextStyle(fontSize: 13),
              headerTextStyle: TextStyle(fontSize: 14),
              footerTextStyle: TextStyle(fontSize: 11),
              secondaryColor: WidgetStatePropertyAll(Color(0xFF123456)),
            ),
          ],
        ),
      ),
    );
    TextStyle style(String text) =>
        tester.renderObject<RenderParagraph>(find.text(text)).text.style!;
    expect(style('Title').fontSize, 14);
    expect(style('Title').color, isNot(isSameColorAs(const Color(0xFFFF0000))));
    expect(style('Title').fontFamily, 'Mono');
    expect(style('Subtitle').fontSize, 12);
    expect(style('Subtitle').color, isSameColorAs(const Color(0xFF123456)));
    expect(style('Value').fontSize, 13);
    expect(style('Header').fontSize, 14);
    expect(style('Header').fontWeight, FontWeight.w600);
    expect(style('Header').fontFamily, 'Mono');
    expect(style('Footer').fontSize, 11);
    final short = tester.getSize(find.widgetWithText(GlassListRow, 'Short'));
    final line = tester.getSize(find.text('Short')).height;
    expect(short.height, closeTo(line + 2 * 15.5, 0.34));
    expect(short.height, lessThan(53));
    expect(
      tester.getSize(find.widgetWithText(GlassListRow, 'Tall')).height,
      60,
    );
  });

  testWidgets('a line is as tall as UIKit makes a label', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassListSection(
          children: [
            GlassListRow(title: Text('Title'), subtitle: Text('Subtitle')),
          ],
        ),
      ),
    );
    final row = tester.getSize(find.byType(GlassListRow));
    expect(row.height, greaterThan(53));
    expect((row.height * 3).roundToDouble(), closeTo(row.height * 3, 1e-6));
  });
}
