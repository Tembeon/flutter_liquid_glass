import 'package:flutter/physics.dart';
import 'package:kinesis/motion.dart';

/// The snap of a released scroll between a collapsed and an expanded large
/// title.
abstract final class LargeTitleSnap {
  static const _spring = Spring.response(0.33);

  /// The spring the snap runs on, for Flutter's scroll simulation.
  static SpringDescription get spring => _spring.description;
}
