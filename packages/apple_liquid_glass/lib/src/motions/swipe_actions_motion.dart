import 'package:kinesis/motion.dart';

/// Where a released swiped row goes.
enum SwipeRelease {
  /// It closes.
  closes,

  /// It settles open on its actions.
  opens,

  /// It sweeps off and its first action runs: a full swipe.
  performs,
}

/// How far a swiped row is moved toward its trailing edge (negative), and
/// where it goes when the finger lets go.
///
/// UIKit 27.2's trailing swipe actions, frame by frame on the simulator
/// (swipe actions passport):
/// - The row moves once the finger has gone [slop] points, then 1:1.
/// - With [fullSwipe] it follows the finger past its actions with no
///   resistance, and the swipe commits only where the row has moved
///   [fullSwipeShare] of its width (284.33 of 370), whatever the speed: a
///   200 point flick at 2000 points a second opens the row and performs
///   nothing. At the commit the row moves a further [commitStep] points
///   and keeps that step for the rest of the touch.
/// - A release past the commit performs the first action; a release after
///   the row came back under it closes the row.
/// - Without a commit, the direction of the finger's last movement decides,
///   not the speed or how far the row is open: a row last pulled open
///   opens, even 5 points open, and one last pushed back closes.
/// - The row settles on a critically damped spring of response 0.49
///   (omega 12.75 to 13, damping 1.02), carrying the release's velocity.
///
/// Not measured: the haptic at the commit, and the rubber band of a row
/// without [fullSwipe] past its actions, which follows kinesis's band.
final class SwipeActionsMotion extends Motion {
  /// Creates the motion of a row at rest.
  SwipeActionsMotion({super.clock});

  static const _spring = Spring.response(0.49, dampingRatio: 1.02);

  /// How far the finger goes before the row moves: the content offset is
  /// the travel less 25 points.
  static const double slop = 25;

  /// The share of the row's width the row must move for a full swipe to
  /// commit.
  static const double fullSwipeShare = 284.33 / 370;

  /// How much further the row moves at the commit.
  static const double commitStep = 50.33;

  /// How far the row is moved.
  late final offset = own(MotionValue<double>(0));

  /// The width of the row at the last layout.
  double rowWidth = 0;

  /// The width of the row's actions at the last layout.
  double actionsWidth = 0;

  /// Whether the finger can pull the row across its whole width, so that a
  /// swipe past [fullSwipeShare] of it commits to the first action;
  /// otherwise the row stretches past its actions only on the band.
  bool fullSwipe = true;

  double _grab = 0;
  bool _stepped = false;
  double _direction = 0;

  RubberBand get _band => RubberBand(
    fullSwipe ? -rowWidth : -actionsWidth,
    0,
    dimension: rowWidth,
  );

  double get _commitAt => -fullSwipeShare * rowWidth;

  /// Whether the swipe has committed and the row stands past the commit, so
  /// that a release now performs the first action.
  bool get isCommitted => _stepped && offset.valueAt(now) <= _commitAt;

  /// A finger takes the row where it is shown at time [t].
  void grab(double t) {
    _grab = _band.invert(offset.valueAt(t));
    _stepped = false;
    _direction = 0;
  }

  /// The finger that took the row has moved [translation] along it by time
  /// [t], counted from past [slop].
  void drag(double t, double translation) {
    advance(t);
    final previous = offset.valueAt(t);
    var value = _band.apply(_grab + translation - (_stepped ? commitStep : 0));
    if (fullSwipe && !_stepped && value <= _commitAt) {
      _stepped = true;
      value = _band.apply(_grab + translation - commitStep);
    }
    if (value != previous) _direction = value < previous ? -1 : 1;
    offset.snap(t, value);
  }

  /// The finger lets go at time [t] with [velocity], and the row goes where
  /// the swipe left it: past the commit it performs when [canPerform],
  /// back under the commit it closes, and otherwise it follows the
  /// finger's last movement.
  SwipeRelease release(
    double t,
    double velocity, {
    required bool canPerform,
  }) {
    advance(t);
    final SwipeRelease release;
    if (_stepped) {
      release = isCommitted && canPerform
          ? SwipeRelease.performs
          : SwipeRelease.closes;
    } else {
      release = _direction < 0 ? SwipeRelease.opens : SwipeRelease.closes;
    }
    _stepped = false;
    moveTo(
      t,
      switch (release) {
        SwipeRelease.performs => -rowWidth,
        SwipeRelease.opens => -actionsWidth,
        SwipeRelease.closes => 0,
      },
      velocity: velocity,
    );
    return release;
  }

  /// The row settles at [value] from time [t], carrying [velocity].
  void moveTo(double t, double value, {double velocity = 0}) {
    advance(t);
    if (velocity != 0) offset.setVelocity(t, velocity);
    offset.retarget(t, value, spring: _spring);
  }
}
