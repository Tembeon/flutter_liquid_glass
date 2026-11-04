import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motion/glass_press.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(120, 44);
const _center = Offset(60, 22);

/// Steps [press] as the clock does, every 1/120 s from its cursor to [t],
/// and returns the time it settled, or null.
double? _run(GlassPress press, double t) {
  double? settled;
  for (var s = press.now; s <= t; s += 1 / 120) {
    press.advance(s);
    if (press.isSettled) {
      press.settle();
      settled ??= s;
    } else {
      settled = null;
    }
  }
  return settled;
}

void main() {
  test('a finger held still settles the press lifted and fully lit', () {
    final press = GlassPress(size: _size);
    press.pointerDown(0, _center);
    expect(press.isSettled, isFalse);
    final settled = _run(press, 2);
    expect(settled, isNotNull);
    expect(press.isPressed, isTrue);
    expect(press.isAtRest, isFalse);
    expect(press.glow, 1);
    expect(press.scale, moreOrLessEquals(press.liftedScale, epsilon: 1e-3));
  });

  test('a released press comes to rest undeformed and dark', () {
    final press = GlassPress(size: _size);
    press.pointerDown(0, _center);
    _run(press, 0.3);
    expect(press.pointerUp(0.3, _center), isTrue);
    expect(press.isAtRest, isFalse);
    _run(press, 3);
    expect(press.isAtRest, isTrue);
    expect(press.values, FlexInteraction.rest);
    expect(press.touchGlow, isNull);
  });

  test('the flex takes up a touch the touch delay after its stamp', () {
    final press = GlassPress(size: _size);
    press.pointerDown(0, _center);
    press.advance(GlassPress.touchDelay - 0.001);
    expect(press.isActive, isFalse);
    press.advance(GlassPress.touchDelay);
    expect(press.isActive, isTrue);
  });

  test('a touch stamped before the cursor runs at its own time', () {
    final stamped = GlassPress(size: _size);
    stamped.advance(1);
    stamped.pointerDown(0.5, _center);
    final timely = GlassPress(size: _size);
    timely.pointerDown(0.5, _center);
    timely.advance(1);
    expect(stamped.scale, timely.scale);
  });

  test('a release before the activation delay never activates', () {
    final press = GlassPress(
      size: _size,
      law: const FlexLaw(stretches: false, activationDelay: 0.05),
    );
    press.pointerDown(0, _center);
    press.pointerUp(0.02, _center);
    _run(press, 0.2);
    expect(press.isActive, isFalse);
    expect(press.isAtRest, isTrue);
  });

  test('a release far outside the slop does not activate', () {
    final press = GlassPress(size: _size);
    press.pointerDown(0, _center);
    final away = Offset(_size.width + GlassPress.highlightSlop + 1, 22);
    expect(press.pointerUp(0.2, away), isFalse);
  });
}
