import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(Widget child, {GlassThemeData theme = const GlassThemeData()}) =>
    MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassTheme(
          data: theme.merge(
            const GlassThemeData(renderer: GlassRenderer.flat()),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 402, child: child),
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

// The light highlight, systemGray4.
const _highlight = Color(0xFFD1D1D6);

void main() {
  setUp(MotionClock.debugReset);

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
    expect(one.left - section.left, 20);
    expect(one.width, 362);
    expect(one.height, 53);
    expect(tester.getTopLeft(find.text('One')).dx - one.left, 16);
    final separator = GlassListSection.separator.color;
    expect(find.byType(GlassListRow).first, paints..rect(color: separator));
    expect(
      find.byType(GlassListRow).last,
      isNot(paints..rect(color: separator)),
    );
  });

  testWidgets('a symbol puts the text at 56 points; a wider image keeps its '
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
    expect(tester.getTopLeft(find.text('One')).dx - one.left, 56);
    expect(tester.getSize(find.byKey(image)), const Size.square(30));
    expect(tester.getTopLeft(find.byKey(image)).dx - one.left, 16);
    expect(tester.getTopLeft(find.text('Two')).dx - one.left, 62);
    expect(
      find.byType(GlassListRow).at(1),
      paints..something((method, arguments) {
        if (method != #drawRect) return false;
        final rect = arguments[0] as Rect;
        return rect.height == 1 && rect.left == 62;
      }),
    );
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
    expect(row, paints..rect(color: _highlight));
    await gesture.up();
    expect(pressed, 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(row, isNot(paints..rect(color: _highlight)));
    await _settle(tester);
    expect(row, isNot(paints..rect(color: const Color(0x01D1D1D6))));
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
    expect(row, isNot(paints..rect(color: _highlight)));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(_frame);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 200));
    expect(row, isNot(paints..rect(color: _highlight)));
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
          listStyle: GlassListStyle(
            secondaryColor: WidgetStatePropertyAll(Color(0xFF123456)),
          ),
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
