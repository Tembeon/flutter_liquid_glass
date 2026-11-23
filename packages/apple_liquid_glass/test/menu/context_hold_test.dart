import 'package:apple_liquid_glass/src/motions/menu_context_hold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a resting finger grows the view by the law until the hold ends, '
      'which answers the growth and drops the view back at once', () {
    final hold = ContextHold();
    hold.down(1);
    hold.advance(1.3);
    expect(hold.growth, closeTo(32 * (0.3 - 0.184), 1e-9));
    expect(hold.release(1.78), closeTo(8 + 20 * (0.78 - 0.434), 1e-9));
    expect(hold.isHeld, isFalse);
    expect(hold.growth, 0);
    expect(hold.isSettled, isTrue);
  });

  test('the growth law matches the measured knee and cap', () {
    expect(ContextHold.growthAfter(0.184), 0);
    expect(ContextHold.growthAfter(0.434), closeTo(8, 1e-9));
    expect(ContextHold.growthAfter(5), 15);
  });
}
