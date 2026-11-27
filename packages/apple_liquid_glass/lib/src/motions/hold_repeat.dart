/// UIKit's autorepeat of a control held down: the first repeat 0.5 s after
/// the touch, then every 0.5 s for five repeats, every 0.1 s up to the
/// twentieth and every 0.05 s after (stepper passport, "The repeat clock";
/// a 2.5 s hold on the device steps at 0.520, 1.021, 1.522 and 2.023 s).
abstract final class HoldRepeat {
  /// The wait before the next repeat after [count] repeats in a row.
  static double interval(int count) => count <= 5
      ? 0.5
      : count < 20
      ? 0.1
      : 0.05;
}
