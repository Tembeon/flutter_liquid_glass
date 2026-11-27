import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(devicePixelRatio: 3),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 402, child: child),
      ),
    ),
  ),
);

class _Outline extends StatefulWidget {
  const _Outline();

  @override
  State<_Outline> createState() => _OutlineState();
}

class _OutlineState extends State<_Outline> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => GlassListSection(
    children: [
      GlassListRow(
        title: const Text('Plants'),
        accessory: GlassListAccessory.outlineDisclosure,
        expanded: expanded,
        onAccessoryPressed: () => setState(() => expanded = !expanded),
      ),
      if (expanded) ...[
        const GlassListRow(title: Text('Fern'), indentationLevel: 1),
        const GlassListRow(title: Text('Moss'), indentationLevel: 2),
      ],
    ],
  );
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('each outline level moves the text 10 points in from an '
      'indented inset of 16: 36, 42 and 52 on a card at 16 (iOS 27.2 '
      'simulator)', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassListSection(
          children: [
            GlassListRow(title: Text('Zero')),
            GlassListRow(title: Text('One'), indentationLevel: 1),
            GlassListRow(title: Text('Two'), indentationLevel: 2),
          ],
        ),
      ),
    );
    final left = tester.getTopLeft(find.byType(GlassListSection)).dx;
    double at(String text) => tester.getTopLeft(find.text(text)).dx - left;
    expect(at('Zero'), moreOrLessEquals(36));
    expect(at('One'), moreOrLessEquals(42));
    expect(at('Two'), moreOrLessEquals(52));
  });

  testWidgets('an outline row shows its disclosure button 5 points from the '
      'card end, turns its chevron down on the 0.25 s list spring and reads '
      'as expand and collapse', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Outline()));
    final card = tester.getRect(find.byType(GlassListRow).first);
    final button = find.bySemanticsLabel('Expand');
    expect(button, findsOneWidget);
    final box = tester.getRect(button);
    expect(box.width, moreOrLessEquals(44));
    expect(box.right, moreOrLessEquals(card.right - 5));
    expect(find.text('Fern'), findsNothing);

    await tester.tap(button);
    await tester.pump();
    expect(find.text('Fern'), findsOneWidget);
    expect(find.bySemanticsLabel('Collapse'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'a header row is 40.33 tall with its title 17 point semibold '
    'in the secondary color, 10 from its top and bottom (iOS 27.2 simulator)',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GlassListSection(
            children: [
              GlassListRow(title: Text('Plants'), header: true),
              GlassListRow(title: Text('Fern')),
            ],
          ),
        ),
      );
      final row = tester.getRect(find.byType(GlassListRow).first);
      expect(row.height, moreOrLessEquals(40.33, epsilon: 0.01));
      final title = tester.widget<RichText>(
        find.descendant(
          of: find.text('Plants'),
          matching: find.byType(RichText),
        ),
      );
      final style = title.text.style!;
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontSize, 17);
      // UIKit's 20.33 point label 10 from the top: its middle 20.17 down.
      expect(
        tester.getCenter(find.text('Plants')).dy - row.top,
        moreOrLessEquals(10 + 20.33 / 2, epsilon: 0.5),
      );
      expect(tester.getRect(find.byType(GlassListRow).last).height, 53);
    },
  );

  test('the chevron turns a quarter on the critically damped 0.25 s list '
      'spring, and back', () {
    final motion = OutlineDisclosureMotion(expanded: false);
    motion.expand(0, expanded: true);
    motion.advance(0.1);
    expect(motion.turn.valueAt(0.1), inExclusiveRange(0.3, 0.9));
    motion.advance(1);
    expect(motion.turn.valueAt(1), moreOrLessEquals(1, epsilon: 0.001));
    motion.expand(1, expanded: false);
    motion.advance(2);
    expect(motion.turn.valueAt(2), moreOrLessEquals(0, epsilon: 0.001));
  });
}
