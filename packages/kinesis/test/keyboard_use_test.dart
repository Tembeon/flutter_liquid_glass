import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/src/widgets/keyboard_use.dart';

void main() {
  testWidgets('changes tells of a key, a pointer and a highlight mode that '
      'changes whether the keyboard is in use', (tester) async {
    final heard = <bool>[];
    void listener() => heard.add(KeyboardUse.inUse);
    KeyboardUse.changes.addListener(listener);
    addTearDown(() {
      KeyboardUse.changes.removeListener(listener);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });
    await tester.pumpWidget(const SizedBox.shrink());

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    expect(heard, [true]);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    expect(heard, [true, false]);

    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    heard.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(heard.last, isTrue);
    await tester.tapAt(Offset.zero);
    expect(heard.last, isFalse);
  });
}
