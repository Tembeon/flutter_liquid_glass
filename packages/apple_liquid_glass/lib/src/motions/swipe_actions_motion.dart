import 'dart:math' as math;

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

/// How far a swiped row is moved (negative toward its trailing edge, which
/// shows its trailing actions; positive toward its leading edge), where it
/// goes when the finger lets go, and where its action buttons stand.
///
/// UIKit 27.2's swipe actions, frame by frame on the simulator (swipe
/// actions passport):
/// - The row moves once the finger has gone [slop] points, then 1:1.
/// - With a full swipe on a side the row follows the finger past that
///   side's actions with no resistance, and the swipe commits only where
///   the row has moved a share of its width, whatever the speed: 284.33 of
///   370 on the trailing side ([fullSwipeShare]), where the row also moves
///   [commitStep] further and keeps that step for the rest of the touch,
///   and 195.96 of 370 on the leading side ([leadingFullSwipeShare]), past
///   which the row follows the finger at [leadingCommitResistance] of its
///   travel. A 200 point flick at 2000 points a second opens a row.
/// - A release past the commit performs the first action; a release after
///   the row came back under it closes the row.
/// - Without a commit, the direction of the finger's last movement decides,
///   not the speed or how far the row is open: a row last pulled open
///   opens, even 5 points open, and one last pushed back closes.
/// - The row settles on a critically damped spring of response 0.49
///   (omega 12.75 to 13, damping 1.02), carrying the release's velocity.
/// - The buttons ([buttonWidth]): while a finger pulls, a button stays 0
///   wide until the strip has opened 32 points past the buttons before it,
///   then grows to be whole as its slot opens (1.5 times faster than the
///   pull for a 63 point button); after a release they stand whole and
///   scale in from where they were on the row's spring at damping 0.71
///   ([appear]), and scale out on it when the row closes.
///
/// Not measured: the haptic at the commit, and the rubber band of a row
/// without a full swipe past its actions, which follows kinesis's band.
/// NEAR: UIKit's strip trails the row by a few points under the finger and
/// at a commit, and the buttons' fade runs on the critical spring; here
/// the strip is where the row is and the fade follows the scale.
final class SwipeActionsMotion extends Motion {
  /// Creates the motion of a row at rest.
  SwipeActionsMotion({super.clock});

  static const _spring = Spring.response(0.49, dampingRatio: 1.02);
  static const _appearSpring = Spring.response(0.49, dampingRatio: 0.71);

  /// How far the finger goes before the row moves: the content offset is
  /// the travel less 25 points.
  static const double slop = 25;

  /// The share of the row's width the row must move toward its trailing
  /// edge for a full swipe to commit.
  static const double fullSwipeShare = 284.33 / 370;

  /// The share of the row's width the row must move toward its leading
  /// edge for a full swipe of its leading actions to commit.
  static const double leadingFullSwipeShare = 195.96 / 370;

  /// How much further the row moves at a trailing commit.
  static const double commitStep = 50.33;

  /// How much of the finger's travel the row follows past a leading
  /// commit: 0.45 points a frame against the finger's 2.3.
  static const double leadingCommitResistance = 0.45 / 2.3;

  /// The strip's margin at each end and the gap between two buttons.
  static const double gap = 10;

  /// How far past the buttons before it the strip opens before a button
  /// starts to grow.
  static const double _growLead = 32;

  /// How much wider than whole the buttons stretch past their strip
  /// without a full swipe.
  static const double _stretch = 1.1;

  /// How far the row is moved.
  late final offset = own(MotionValue<double>(0));

  /// How whole the buttons stand after a release: 1 whole, 0 gone, past
  /// either on the spring's overshoot.
  late final appear = own(MotionValue<double>(0));

  /// The width of the row at the last layout.
  double rowWidth = 0;

  /// The whole width of one button of each side at the last layout, the
  /// widest content of the side's buttons.
  double trailingButton = 0;

  /// See [trailingButton].
  double leadingButton = 0;

  /// The number of trailing and leading actions.
  int trailingCount = 0;

  /// See [trailingCount].
  int leadingCount = 0;

  /// Whether a full swipe performs the first trailing action.
  bool fullSwipe = true;

  /// Whether a full swipe performs the first leading action.
  bool leadingFullSwipe = true;

  double _grab = 0;
  bool _stepped = false;
  bool _leadingCommitted = false;
  double _direction = 0;
  bool _held = false;

  /// The width a side's strip opens to: its buttons, the gaps between them
  /// and a margin at each end.
  double stripWidth({required bool leading}) {
    final count = leading ? leadingCount : trailingCount;
    if (count == 0) return 0;
    final button = leading ? leadingButton : trailingButton;
    return gap + count * button + (count - 1) * gap + gap;
  }

  /// Whether a finger holds the row.
  bool get held => _held;

  RubberBand get _band => RubberBand(
    trailingCount == 0
        ? 0
        : fullSwipe
        ? -rowWidth
        : -stripWidth(leading: false),
    leadingCount == 0
        ? 0
        : leadingFullSwipe
        ? rowWidth
        : stripWidth(leading: true),
    dimension: rowWidth,
  );

  double get _commitAt => -fullSwipeShare * rowWidth;
  double get _leadingCommitAt => leadingFullSwipeShare * rowWidth;

  /// Whether the swipe has committed and the row stands past the commit, so
  /// that a release now performs a first action.
  bool get isCommitted {
    final value = offset.valueAt(now);
    return (_stepped && value <= _commitAt) ||
        (_leadingCommitted && value >= _leadingCommitAt);
  }

  /// Whether the leading side's swipe is committed.
  bool get leadingCommitted => _leadingCommitted;

  /// A finger takes the row where it is shown at time [t].
  void grab(double t) {
    advance(t);
    _grab = _band.invert(offset.valueAt(t));
    _stepped = false;
    _leadingCommitted = false;
    _direction = 0;
    _held = true;
    appear.snap(t, 1);
  }

  /// The finger that took the row has moved [translation] along it by time
  /// [t], counted from past [slop].
  void drag(double t, double translation) {
    advance(t);
    final previous = offset.valueAt(t);
    final raw = _grab + translation;
    var value = _band.apply(raw - (_stepped ? commitStep : 0));
    if (fullSwipe && trailingCount > 0 && !_stepped && value <= _commitAt) {
      _stepped = true;
      value = _band.apply(raw - commitStep);
    }
    if (leadingFullSwipe && leadingCount > 0) {
      final at = _leadingCommitAt;
      _leadingCommitted = value >= at;
      if (_leadingCommitted) {
        value = at + (value - at) * leadingCommitResistance;
      }
    }
    if (value != previous) _direction = value < previous ? -1 : 1;
    offset.snap(t, value);
  }

  /// The finger lets go at time [t] with [velocity], and the row goes where
  /// the swipe left it: past a commit it performs when [canPerform], back
  /// under a commit it closes, and otherwise it follows the finger's last
  /// movement. The answer says which side the row stood on.
  ({SwipeRelease release, bool leading}) release(
    double t,
    double velocity, {
    required bool canPerform,
  }) {
    advance(t);
    _held = false;
    final value = offset.valueAt(t);
    final leading = value > 0;
    final SwipeRelease release;
    if (_stepped || _leadingCommitted) {
      release = isCommitted && canPerform
          ? SwipeRelease.performs
          : SwipeRelease.closes;
    } else if (value == 0) {
      release = SwipeRelease.closes;
    } else {
      final opening = leading ? _direction > 0 : _direction < 0;
      release = opening ? SwipeRelease.opens : SwipeRelease.closes;
    }
    _stepped = false;
    _leadingCommitted = false;
    final strip = stripWidth(leading: leading);
    switch (release) {
      case SwipeRelease.performs:
        if (leading) {
          moveTo(t, 0);
        } else {
          moveTo(t, -rowWidth, velocity: velocity);
        }
      case SwipeRelease.opens:
        _show(t, (value.abs() / math.max(strip, 1)).clamp(0.0, 1.0));
        moveTo(t, leading ? strip : -strip, velocity: velocity);
      case SwipeRelease.closes:
        moveTo(t, 0, velocity: velocity);
    }
    return (release: release, leading: leading);
  }

  /// Opens the row on its trailing actions from time [t], as the edit
  /// control's tap does.
  void open(double t) {
    advance(t);
    _show(t, 0);
    moveTo(t, -stripWidth(leading: false));
  }

  void _show(double t, double from) {
    appear.snap(t, from);
    appear.retarget(t, 1, spring: _appearSpring);
  }

  /// The row settles at [value] from time [t], carrying [velocity]; at 0
  /// the buttons scale out.
  void moveTo(double t, double value, {double velocity = 0}) {
    advance(t);
    if (velocity != 0) offset.setVelocity(t, velocity);
    offset.retarget(t, value, spring: _spring);
    if (value == 0) appear.retarget(t, 0, spring: _appearSpring);
  }

  /// How wide button [index] of a side stands (0 the first, outermost),
  /// before [appear] scales it, with the row moved [pull] points toward the
  /// other side.
  double buttonWidth(int index, {required bool leading, required double pull}) {
    final count = leading ? leadingCount : trailingCount;
    final whole = leading ? leadingButton : trailingButton;
    if (index >= count) return 0;
    final strip = stripWidth(leading: leading);
    final full = leading ? leadingFullSwipe : fullSwipe;
    if (pull > strip) {
      if (full) {
        if (leading && _leadingCommitted) {
          return index == 0 ? math.max(0, pull - 2 * gap) : 0;
        }
        return index == 0 ? pull - (strip - whole) : whole;
      }
      final share = (pull / strip).clamp(1.0, _stretch);
      return whole * share;
    }
    if (!_held) return whole;
    final before = index * (whole + gap);
    final start = before + _growLead;
    final end = before + gap + whole;
    if (end <= start) return pull >= end ? whole : 0;
    return (whole * (pull - start) / (end - start)).clamp(0.0, whole);
  }

  /// Where the gaps stand with the row moved [pull] points: the margin at
  /// each end and between the buttons, wider when the row stretches past
  /// its strip without a full swipe.
  double gapAt({required bool leading, required double pull}) {
    final count = leading ? leadingCount : trailingCount;
    final strip = stripWidth(leading: leading);
    final full = leading ? leadingFullSwipe : fullSwipe;
    if (count == 0 || full || pull <= strip) return gap;
    var buttons = 0.0;
    for (var i = 0; i < count; i++) {
      buttons += buttonWidth(i, leading: leading, pull: pull);
    }
    return (pull - buttons) / (count + 1);
  }
}
