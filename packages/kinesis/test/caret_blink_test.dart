import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('replays exact UIKit _uitcvba discrete stepped opacity timeline', () {
    final caret = CaretBlinkMotion(visible: true);
    expect(caret.opacityAt(0), 1);
    expect(caret.opacityAt(0.49), 1);
    expect(caret.opacityAt(0.5), 1);
    expect(caret.opacityAt(0.54), 0.75);
    expect(caret.opacityAt(0.58), 0.5);
    expect(caret.opacityAt(0.62), 0.25);
    expect(caret.opacityAt(0.66), 0);
    expect(caret.opacityAt(0.84), 0);
    expect(caret.opacityAt(0.89), 0.25);
    expect(caret.opacityAt(0.93), 0.5);
    expect(caret.opacityAt(0.97), 0.75);
    expect(caret.opacityAt(1), 1);
    expect(caret.opacityAt(1.54), 0.75);
  });

  test('reset restarts solid hold on keystroke and hide sleeps the clock', () {
    final clock = ManualMotionClock();
    final caret = CaretBlinkMotion(clock: clock);
    expect(caret.isVisible, isFalse);
    expect(caret.opacity, 0);
    expect(caret.isSettled, isTrue);

    caret.show(0);
    expect(caret.isVisible, isTrue);
    expect(caret.isSettled, isFalse);

    // Keystrokes every 0.3 s keep caret solid at 1.
    caret.advance(0.3);
    expect(caret.opacity, 1);
    caret.reset(0.3);
    caret.advance(0.6);
    expect(caret.opacity, 1);
    caret.advance(0.84);
    expect(caret.opacity, 0.75);

    caret.hide(0.9);
    expect(caret.isVisible, isFalse);
    expect(caret.opacity, 0);
    expect(caret.isSettled, isTrue);
  });
}
