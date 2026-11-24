import 'package:kinesis/motion.dart';

/// How a split view moves. The split view passport captures it at rest
/// only: the sidebar's showing and hiding and a drag between the columns
/// are not measured, so these springs are this package's own.
abstract final class SplitViewMotion {
  /// The spring the primary column slides in and out on, from the sidebar
  /// button or from code.
  static const Spring toggle = Spring.smooth;

  /// The spring the primary column takes a width given from code on, such
  /// as a return to its preferred width or a step of the keyboard.
  static const Spring resize = Spring.smooth;
}
