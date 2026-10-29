import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: direction,
        child: Center(child: child),
      ),
    );

class _Pages extends StatefulWidget {
  const _Pages({this.picks, this.accept = true});

  final List<int>? picks;
  final bool accept;

  @override
  State<_Pages> createState() => _PagesState();
}

class _PagesState extends State<_Pages> {
  int page = 2;

  @override
  Widget build(BuildContext context) => GlassPageControl(
    count: 5,
    page: page,
    semanticLabel: 'Pages',
    onChanged: (next) {
      widget.picks?.add(next);
      if (widget.accept) setState(() => page = next);
    },
  );
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap on either half steps toward it on the lift', (
    tester,
  ) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [3, 2, 1]);
  });

  testWidgets('a scrub follows the nearest dot and plays a selection haptic '
      'per page', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks)));
    final box = tester.getRect(find.byType(GlassPageControl));
    final gesture = await tester.startGesture(box.center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(picks, [3, 4]);
    expect(haptics, hasLength(2));
  });

  testWidgets('keys and accessibility step; it reads as an adjustable value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final picks = <int>[];
    await tester.pumpWidget(
      _app(
        GlassPageControl(
          count: 5,
          page: 2,
          onChanged: picks.add,
          focusNode: focus,
          semanticLabel: 'Pages',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pages')),
      matchesSemantics(
        label: 'Pages',
        value: 'page 3 of 5',
        increasedValue: 'page 4 of 5',
        decreasedValue: 'page 2 of 5',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    tester.semantics.increase(find.semantics.byLabel('Pages'));
    expect(picks, [3, 1, 3]);
    semantics.dispose();
  });

  testWidgets('right to left the pages run from the right', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(
      _app(_Pages(picks: picks), direction: TextDirection.rtl),
    );
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerLeft + const Offset(6, 0));
    await tester.pump();
    expect(picks, [3]);
  });

  testWidgets('a control whose page does not follow returns to it; disabled '
      'it ignores taps', (tester) async {
    final picks = <int>[];
    await tester.pumpWidget(_app(_Pages(picks: picks, accept: false)));
    final box = tester.getRect(find.byType(GlassPageControl));
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    await tester.pump();
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    expect(picks, [3, 3]);

    await tester.pumpWidget(
      _app(const GlassPageControl(count: 5, page: 2, onChanged: null)),
    );
    await tester.tapAt(box.centerRight - const Offset(6, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a progress capsule widens the control by its extra width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassPageControl(count: 5, page: 0, onChanged: null)),
    );
    final plain = tester.getSize(find.byType(GlassPageControl)).width;
    await tester.pumpWidget(
      _app(
        const GlassPageControl(
          count: 5,
          page: 0,
          progress: 0.5,
          onChanged: null,
        ),
      ),
    );
    final withProgress = tester.getSize(find.byType(GlassPageControl)).width;
    expect(withProgress - plain, closeTo(27.33 - 9.67, 1e-9));
  });
}
