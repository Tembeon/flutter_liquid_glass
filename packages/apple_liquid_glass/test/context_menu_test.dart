import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _held = Key('held');

Widget _app({
  required List<String> log,
  WidgetBuilder? previewBuilder,
  VoidCallback? onTap,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => GlassTheme(
    data: const GlassThemeData(renderer: GlassRenderer.flat()),
    child: child!,
  ),
  home: ColoredBox(
    color: const Color(0xFFF2F2F7),
    child: Align(
      alignment: const Alignment(0, -0.5),
      child: GlassContextMenu(
        previewBuilder: previewBuilder,
        menuChildren: [
          for (final title in ['Copy', 'Share', 'Delete'])
            GlassMenuItem(title: title, onPressed: () => log.add(title)),
        ],
        child: GestureDetector(
          onTap: onTap,
          child: const SizedBox(
            key: _held,
            width: 120,
            height: 80,
            child: ColoredBox(color: Color(0xFF3478F6)),
          ),
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

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a hold grows the view, then opens the menu beside its lifted '
      'preview; let go there, the menu stays open', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log: log));
    final rest = tester.getRect(find.byKey(_held));
    final gesture = await tester.startGesture(rest.center);
    await _frames(tester, 20);
    expect(tester.getRect(find.byKey(_held)).width, greaterThan(rest.width));
    expect(find.text('Copy'), findsNothing);
    await _frames(tester, 40);
    expect(find.text('Copy'), findsOneWidget);
    await gesture.up();
    await _frames(tester, 60);
    expect(find.text('Copy'), findsOneWidget);
    final preview = tester.getRect(find.byKey(_held).last);
    expect(preview.width, closeTo(120 * 1.15, 0.5));
    final copy = tester.getRect(find.text('Copy'));
    expect(copy.top, greaterThan(preview.bottom));
    await tester.tapAt(tester.getCenter(find.text('Share')));
    await _frames(tester, 60);
    expect(log, ['Share']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a held finger slides onto a row and chooses it on release', (
    tester,
  ) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log: log));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_held)),
    );
    await _frames(tester, 60);
    await gesture.moveTo(tester.getCenter(find.text('Delete')));
    await _frames(tester, 2);
    await gesture.up();
    await _frames(tester, 60);
    expect(log, ['Delete']);
  });

  testWidgets('a tap reaches the view; a finger that moves before the commit '
      'drops the hold', (tester) async {
    _phone(tester);
    final log = <String>[];
    var taps = 0;
    await tester.pumpWidget(_app(log: log, onTap: () => taps++));
    await tester.tap(find.byKey(_held));
    await _frames(tester, 60);
    expect(taps, 1);
    expect(find.text('Copy'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_held)),
    );
    await _frames(tester, 10);
    await gesture.moveBy(const Offset(0, 40));
    await _frames(tester, 60);
    expect(find.text('Copy'), findsNothing);
    await gesture.up();
  });

  testWidgets('Escape closes the menu and the preview lands home', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(log: <String>[]));
    final rest = tester.getRect(find.byKey(_held));
    final gesture = await tester.startGesture(rest.center);
    await _frames(tester, 60);
    await gesture.up();
    await _frames(tester, 60);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester, 90);
    expect(find.text('Copy'), findsNothing);
    expect(tester.getRect(find.byKey(_held)), rest);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a preview builder draws the open preview', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        log: <String>[],
        previewBuilder: (context) => const Text('Preview'),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_held)),
    );
    await _frames(tester, 60);
    await gesture.up();
    await _frames(tester, 60);
    expect(find.text('Preview'), findsOneWidget);
  });
}
