import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _held = Key('held');
const _page = Key('page');

Widget _app({required ValueChanged<MotionSource> onPreviewPressed}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) =>
          GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      home: ColoredBox(
        color: const Color(0xFFF2F2F7),
        child: Align(
          alignment: const Alignment(0, -0.5),
          child: GlassContextMenu(
            onPreviewPressed: onPreviewPressed,
            menuChildren: [
              GlassMenuItem(title: 'Copy', onPressed: () {}),
              GlassMenuItem(title: 'Share', onPressed: () {}),
            ],
            child: const SizedBox(
              key: _held,
              width: 120,
              height: 80,
              child: ColoredBox(color: Color(0xFF3478F6)),
            ),
          ),
        ),
      ),
    );

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

Future<Rect> _open(WidgetTester tester) async {
  final rest = tester.getRect(find.byKey(_held));
  final hold = await tester.startGesture(rest.center);
  await _frames(tester, 60);
  await hold.up();
  await _frames(tester, 60);
  expect(find.text('Copy').hitTestable(), findsOneWidget);
  return tester.getRect(find.byKey(_held).last);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap on the preview of a menu whose app pushes a page with '
      'it commits: the menu goes at once and the page grows out of the '
      'preview to the screen, and popped it zooms back into the held view', (
    tester,
  ) async {
    _phone(tester);
    late NavigatorState navigator;
    var presses = 0;
    await tester.pumpWidget(
      _app(
        onPreviewPressed: (preview) {
          presses++;
          navigator.push(
            GlassPageRoute<void>(
              source: preview,
              builder: (_) => const ColoredBox(
                key: _page,
                color: Color(0xFFFFFFFF),
                child: SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
    navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final rest = tester.getRect(find.byKey(_held));
    final preview = await _open(tester);

    await tester.tapAt(preview.center);
    await tester.pump();
    expect(presses, 1);
    expect(find.text('Copy').hitTestable(), findsNothing);
    await tester.pump();
    final first = tester.getRect(find.byKey(_page));
    expect(first.center.dx, closeTo(preview.center.dx, 6));
    expect(first.center.dy, closeTo(preview.center.dy, 6));
    await _frames(tester, 90);
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );

    navigator.pop();
    await tester.pump();
    await _frames(tester, 12);
    final leaving = tester.getRect(find.byKey(_page)).center;
    expect(
      (leaving - rest.center).distance,
      lessThan((const Offset(201, 437) - rest.center).distance),
      reason: 'it heads back into the held view',
    );
    await _frames(tester, 90);
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('a tap on the preview of a menu whose app pushes nothing '
      'closes the menu', (tester) async {
    _phone(tester);
    var presses = 0;
    await tester.pumpWidget(_app(onPreviewPressed: (_) => presses++));
    final preview = await _open(tester);
    await tester.tapAt(preview.center);
    await _frames(tester, 60);
    expect(presses, 1);
    expect(find.text('Copy'), findsNothing);
  });
}
