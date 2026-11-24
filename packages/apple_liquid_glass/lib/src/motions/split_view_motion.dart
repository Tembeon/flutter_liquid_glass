import 'package:kinesis/motion.dart';

/// How a split view moves. The split view passport captures it at rest
/// only: the sidebar's showing and hiding and a drag between the columns
/// are not measured, so its springs are this package's own.
abstract final class SplitViewMotion {
  /// Moves [reveal], how far the primary column shows from 0 to 1, to
  /// [shown]: the column slides in or out, from the sidebar button or from
  /// code.
  static void reveal(MotionValue<double> reveal, {required bool shown}) =>
      withSpring(_toggle, () => reveal.target = shown ? 1 : 0);

  /// Starts [share], how far the columns have moved from their last widths
  /// to new ones given from code, from 0 and moves it to 1: a return to the
  /// preferred width or a step of the keyboard.
  static void resize(MotionValue<double> share) {
    withoutAnimation(() => share.target = 0);
    withSpring(_resize, () => share.target = 1);
  }
}

const Spring _toggle = Spring.smooth;
const Spring _resize = Spring.smooth;
