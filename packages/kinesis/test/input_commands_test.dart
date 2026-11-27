import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

class _Toggle extends Intent {
  const _Toggle();
}

const _keys = {SingleActivator(LogicalKeyboardKey.keyS, meta: true): _Toggle()};

Future<bool> _press(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  return handled;
}

void main() {
  testWidgets('a key reaches the innermost part that answers its intent, and '
      'goes on to the part above where the inner one has no action', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final heard = <String>[];
    Action<Intent> action(String name) => CallbackAction<_Toggle>(
      onInvoke: (_) {
        heard.add(name);
        return null;
      },
    );
    Future<void> pump({required bool innerAnswers}) => tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => InputCommands(
          shortcuts: _keys,
          actions: {_Toggle: action('outer')},
          child: InputCommands(
            actions: {if (innerAnswers) _Toggle: action('inner')},
            child: Focus(focusNode: focus, child: const SizedBox()),
          ),
        ),
      ),
    );

    await pump(innerAnswers: true);
    focus.requestFocus();
    await tester.pump();
    expect(await _press(tester), isTrue);
    expect(heard, ['inner']);

    await pump(innerAnswers: false);
    expect(await _press(tester), isTrue);
    expect(heard, ['inner', 'outer']);
  });

  testWidgets('without the focus inside, the keys do nothing', (tester) async {
    var heard = 0;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => InputCommands(
          shortcuts: _keys,
          actions: {
            _Toggle: CallbackAction<_Toggle>(onInvoke: (_) => heard++),
          },
          child: const SizedBox(),
        ),
      ),
    );
    expect(await _press(tester), isFalse);
    expect(heard, 0);
  });
}
