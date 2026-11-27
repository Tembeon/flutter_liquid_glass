import 'package:kinesis/motion.dart';

/// UIKit's activity indicator turning (activity indicator passport, iOS
/// 27, device confirmed): [images] images a [turn] of 0.8 s, each a step
/// of half a spoke for the brightest one, so it stands on a spoke and
/// between two in turn. A restart turns on from the image a stop left, as
/// UIKit hands its layer the images from the one it shows; a stopped
/// indicator keeps its image.
final class ActivityMotion extends Motion {
  /// Creates the motion, stepped by [clock] or the ambient one.
  ActivityMotion({super.clock});

  /// The number of spokes the indicator draws.
  static const spokes = 8;

  /// The images of one turn.
  static const images = 16;

  /// The seconds of one turn (`fullLoopDuration`).
  static const double turn = 0.8;

  /// How bright the brightest spoke draws, of the indicator's color: the
  /// spoke image's head alpha.
  static const double head = 0.84;

  /// How bright the spokes past the four-spoke tail draw, of the head's
  /// brightness (99 against 32 levels from the page, light and dark).
  static const double tail = 0.32;

  late final _loop = own(_ActivityLoop());

  /// The image shown now, from 0: where the brightest spoke stands, in
  /// half spokes.
  int get image => _loop.image;

  /// Whether the indicator turns.
  bool get isTurning => _loop.turning;

  /// Turns on from the image shown, from [t].
  void start(double t) {
    _loop
      ..from = _loop.image
      ..start = t
      ..turning = true
      ..wake(t);
  }

  /// Stops on the image shown.
  void stop() => _loop.turning = false;

  /// How bright [spoke] draws at [image], of the indicator's color: [head]
  /// for the brightest, falling evenly over the four spokes behind it to
  /// [tail] of that, and [tail] of it past them. Between two spokes the
  /// image lights each by how far behind the head it stands (this
  /// package's reading of UIKit's images, which it does not hold).
  static double brightness(int spoke, int image) {
    final behind = (image / 2 - spoke) % spokes;
    final fall = behind >= 4 ? 1.0 : behind / 4;
    return head * (1 - (1 - tail) * fall);
  }
}

final class _ActivityLoop extends MotionLoop {
  _ActivityLoop() : super(rate: ActivityMotion.images / ActivityMotion.turn);

  double start = 0;
  int from = 0;
  int image = 0;
  bool turning = false;

  @override
  bool step(double t) {
    if (!turning) return false;
    // A frame's time lands on a whole image within rounding.
    final steps = ((t - start) * rate + 1e-6).floor();
    image = (from + steps) % ActivityMotion.images;
    return true;
  }
}
