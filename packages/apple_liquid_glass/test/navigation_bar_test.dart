import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/scroll_edge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MediaQuery(
      data: const MediaQueryData(
        size: Size(402, 874),
        devicePixelRatio: 3,
        padding: EdgeInsets.only(top: 62, bottom: 34),
      ),
      child: Directionality(
        textDirection: direction,
        child: GlassTheme(
          data: const GlassThemeData(renderer: GlassRenderer.flat()),
          child: child,
        ),
      ),
    );

Widget _page({
  Widget? title,
  Widget? largeTitle,
  Widget? leading,
  Widget? trailing,
  ScrollController? controller,
}) => GlassPageScaffold(
  navigationBar: GlassNavigationBar(
    title: title,
    largeTitle: largeTitle,
    leading: [if (leading != null) GlassBarItem.custom(child: leading)],
    trailing: [if (trailing != null) GlassBarItem.custom(child: trailing)],
  ),
  child: GlassContentScroll(
    child: ListView(
      controller: controller,
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 50, child: Text('Row $i')),
      ],
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

double _titleOpacity(WidgetTester tester) => tester
    .widgetList<MotionTransition>(find.byType(MotionTransition))
    .firstWhere((transition) => transition.opacity != null)
    .opacity!
    .value;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the inline title sits on the center when it fits, else from '
      'the leading side, level with the capsules', (tester) async {
    await _phone(tester);
    const side = SizedBox(width: 36, height: 36);
    await tester.pumpWidget(
      _app(_page(title: const Text('Title'), leading: side, trailing: side)),
    );
    await tester.pump();
    expect(tester.getCenter(find.text('Title')).dx, 201);
    expect(tester.getCenter(find.text('Title')).dy, 62 + 22);
    await tester.pumpWidget(
      _app(
        _page(
          title: const Text('A title much too long to stand centered'),
          leading: const SizedBox(width: 120, height: 36),
          trailing: side,
        ),
      ),
    );
    await tester.pump();
    final title = tester.getRect(
      find.text('A title much too long to stand centered'),
    );
    expect(title.left, 16 + 128 + 12);
    expect(title.right, lessThanOrEqualTo(402 - 16 - 44 - 12));
  });

  testWidgets('right to left, the leading capsule stands at the right', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        _page(
          title: const Text('Title'),
          leading: const SizedBox(key: Key('leading'), width: 36, height: 36),
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump();
    expect(
      tester.getTopRight(find.byKey(const Key('leading'))).dx,
      402 - 16 - 4,
    );
  });

  testWidgets('a large title scrolls away with the content, then the '
      'inline title rises in', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_page(largeTitle: const Text('Notes'), controller: controller)),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.text('Row 0')).dy, 62 + 54 + 52);
    final large = find.text('Notes').last;
    final rest = tester.getTopLeft(large).dy;
    expect(_titleOpacity(tester), 0);
    controller.jumpTo(20);
    await tester.pump();
    expect(tester.getTopLeft(large).dy, rest - 20);
    await _settle(tester);
    expect(controller.offset, 20);
    expect(_titleOpacity(tester), 0);
    controller.jumpTo(60);
    await tester.pump(_frame);
    expect(_titleOpacity(tester), 1);
    controller.jumpTo(0);
    await tester.pump(_frame);
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -120),
      const Duration(milliseconds: 600),
    );
    await tester.pump(_frame);
    expect(_titleOpacity(tester), inExclusiveRange(0, 1));
    await _settle(tester);
    expect(_titleOpacity(tester), 1);
  });

  testWidgets('a scroll left with the large title partly away springs to '
      'the nearer end', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_page(largeTitle: const Text('Notes'), controller: controller)),
    );
    await tester.pump();
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -20),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -36),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(52, 0.5));
  });

  testWidgets('the edge under a large title bar is hard and covers only the '
      'row, once the title has gone', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_page(largeTitle: const Text('Notes'), controller: controller)),
    );
    await tester.pump();
    final top = tester
        .widgetList<ScrollEdge>(find.byType(ScrollEdge))
        .map((edge) => edge.details)
        .firstWhere((details) => details.edge == AxisDirection.up);
    expect(top.hard, isTrue);
    expect(top.extent, 62 + 54);
    controller.jumpTo(40);
    await _settle(tester);
    expect(top.presence.value, 0);
    controller.jumpTo(100);
    await _settle(tester);
    expect(top.presence.value, 1);
  });

  testWidgets('the theme colors the titles', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        GlassTheme(
          data: const GlassThemeData(
            navigationBarStyle: GlassNavigationBarStyle(
              foregroundColor: Color(0xFF123456),
            ),
          ),
          child: _page(title: const Text('Title')),
        ),
      ),
    );
    final style = DefaultTextStyle.of(tester.element(find.text('Title'))).style;
    expect(style.color, isSameColorAs(const Color(0xFF123456)));
    expect(style.fontSize, 17);
  });
}
