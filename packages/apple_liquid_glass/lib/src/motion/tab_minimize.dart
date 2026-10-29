import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// When a tab bar minimizes to its selected tab while the content under it
/// scrolls.
///
/// UIKit: `UITabBarController.MinimizeBehavior`. SwiftUI:
/// `TabBarMinimizeBehavior`.
enum GlassTabBarMinimizeBehavior {
  /// The platform's default for the context. On an iPhone tab bar that
  /// does not opt in, UIKit's default does not minimize, so this resolves
  /// to [never] (an approximation: the resolution is not read from UIKit).
  automatic,

  /// The bar never minimizes.
  never,

  /// The bar minimizes when the content scrolls down. It expands at the
  /// content's top end, on a tap and when the content is pushed past its
  /// far end; a scroll back up in the middle of the content leaves it
  /// minimized, as iOS 27 does.
  onScrollDown,

  /// The bar minimizes when the content scrolls up, mirroring
  /// [onScrollDown]; for content aligned to the bottom (a chat).
  onScrollUp;

  /// Whether a bar with this behavior minimizes at all.
  bool get minimizes => this == onScrollDown || this == onScrollUp;
}

/// The measured tuning of a minimizing tab bar and its bottom accessory.
///
/// The thresholds, springs and the hint scale are read from UIKit on iOS
/// 27 (the scroll-away interaction of the floating tab bar, its animation
/// settings and its phone layout record; notes private), the circle
/// matched to the measured search tab circle (48 pt, 28 from the side and
/// the bottom). The bar turns into the circle in one liquid morph of its
/// shape and content ([morphSpring]); the four collapse and expand springs
/// move only the bottom accessory, one axis after the other. A film of the
/// morph, the accessory's path and the hold expansion is still due.
@internal
abstract final class TabBarMinimizeTuning {
  /// The scroll in the minimizing direction, in points, before the bar
  /// starts to respond: UIKit's activation threshold, 0.
  static const double activationDistance = 0;

  /// The scroll, in points, past [activationDistance] that takes the bar
  /// from expanded to minimized: UIKit's active distance, 64.
  static const double activeDistance = 64;

  /// The scrollable range a content needs, as a multiple of
  /// [activationDistance] + [activeDistance], before the bar minimizes
  /// over it: 1.5 (96 pt), read from UIKit.
  static const double minimumRangeFactor = 1.5;

  /// The least progress of a scroll that has started to minimize the
  /// bar, so a scroll that turns back mid-way does not read as one that
  /// expanded it: UIKit clamps between 0.01 and 1.
  static const double minimumProgress = 0.01;

  /// How much smaller the bar draws at the end of a scroll's progress,
  /// before it minimizes: the bar's glass group scales by 1 - 0.05 x
  /// progress about its center, read from UIKit.
  static const double hintScale = 0.05;

  /// The spring of the hint while a finger drags the content (UIKit
  /// `scrollAwayTrackingProgressSpring`: damping 0.8, response 0.1).
  static const hintTrackingSpring = Spring.response(0.1, dampingRatio: 0.8);

  /// The spring of the hint while the content decelerates on its own
  /// (UIKit `scrollAwayProgressSpring`: damping 0.8, response 0.5).
  static const hintSpring = Spring.response(0.5, dampingRatio: 0.8);

  /// The spring the hint returns to full size on when the bar minimizes,
  /// expands or the scroll ends short of it (UIKit
  /// `scrollAwayHintResetSpring`: damping 0.8, response 0.3).
  static const hintResetSpring = Spring.response(0.3, dampingRatio: 0.8);

  /// The spring of the liquid morph between the bar and the circle: every
  /// channel of the shapes (size, position, transform) and the morph of
  /// their content, both ways, without a delay (damping 0.8, response 0.3;
  /// read from UIKit).
  static const morphSpring = Spring.response(0.3, dampingRatio: 0.8);

  /// [morphSpring] under Reduce Motion: critically damped, response 0.15
  /// (read from UIKit).
  static const reducedMotionMorphSpring = Spring.response(0.15);

  /// The spring the bottom accessory's horizontal position and width move
  /// on as the bar minimizes (UIKit `collapseIntermediateSpring`: damping
  /// 0.72, response 0.36).
  static const accessoryCollapseSpring = Spring.response(
    0.36,
    dampingRatio: 0.72,
  );

  /// The spring its vertical position and height follow on,
  /// [accessoryFollowDelay] later (`collapseFinalSpring`: damping 0.76,
  /// response 0.42).
  static const accessoryCollapseFollowSpring = Spring.response(
    0.42,
    dampingRatio: 0.76,
  );

  /// The spring the bottom accessory's vertical position and height move
  /// on as the bar expands (`expandIntermediateSpring`: damping 0.72,
  /// response 0.3).
  static const accessoryExpandSpring = Spring.response(0.3, dampingRatio: 0.72);

  /// The spring its horizontal position and width follow on,
  /// [accessoryFollowDelay] later (`expandFinalSpring`: damping 0.72,
  /// response 0.36).
  static const accessoryExpandFollowSpring = Spring.response(
    0.36,
    dampingRatio: 0.72,
  );

  /// The delay of the accessory's second axis, both ways (0.05 s).
  static const double accessoryFollowDelay = 0.05;

  /// The diameter of the minimized bar: UIKit's collapsed platter, 48,
  /// the size of the search tab's circle while searching.
  static const double collapsedSize = 48;

  /// The space between the minimized bar and the expanded bar's edges:
  /// (62 - 48) / 2 = 7, read from UIKit's layout record; with the bar 21
  /// from the screen's side and bottom, the circle sits 28 from both, as
  /// the measured search tab circle does.
  static const double collapsedInset = 7;

  /// The space between the expanded bar and the accessory above it: the
  /// accessory's bottom stands 8 above the bar's top (read from UIKit).
  static const double accessoryGap = 8;

  /// The space between the minimized circle and the inline accessory, and
  /// between the accessory and a minimized search circle (read from
  /// UIKit).
  static const double inlineGap = 14;

  /// The height of the bottom accessory, expanded and inline (read from
  /// UIKit; content may opt into 48 - 64 there, which the port does not
  /// offer).
  static const double accessoryHeight = 48;

  /// The space between the screen's sides and the bar group: 21 (the
  /// measured tab bar inset).
  static const double sideInset = 21;

  /// How long a finger rests on the minimized bar before the bar expands
  /// under it: UIKit's `minimumPressDuration` of the tab bar's interactive
  /// expansion, 0.22 s, read from UIKit.
  static const double holdDuration = 0.22;

  /// How far a finger on the minimized bar moves along the bar, in points,
  /// before the bar expands at once and the touch becomes the bar's
  /// selection drag: UIKit's `expansionHysteresis`, 4, read from UIKit
  /// (the selection gesture of the floating tab bar applies the same 4
  /// points).
  static const double holdHysteresis = 4;

  /// The spring of UIKit's interactive expansion under a held finger
  /// (`expansionSpring`: damping 0.5, response 0.4), read from UIKit. UIKit
  /// grows a container of the bar from the circle's size on it, which the
  /// port does not yet: it expands a held bar on [morphSpring].
  static const expansionSpring = Spring.response(0.4, dampingRatio: 0.5);

  /// The spring UIKit's interactive expansion returns on when the finger
  /// lifts without moving (`collapsedSpring`: damping 0.75, response 0.4),
  /// read from UIKit; the port collapses on [morphSpring], as
  /// [expansionSpring].
  static const collapsedSpring = Spring.response(0.4, dampingRatio: 0.75);
}

/// The scroll-away interaction of a minimizing tab bar: how far a user's
/// scroll has carried the bar toward minimizing, ported from UIKit's
/// floating tab bar (iOS 27.0.1; equations read from UIKit, notes
/// private).
///
/// Offsets are along the content's scroll axis, growing as the content
/// moves toward its end (Flutter's `pixels` on a downward list, UIKit's
/// `contentOffset.y`); `min` and `max` are the offsets of the content's
/// two ends. Only a user's scroll counts: a drag, and the deceleration
/// after it. A programmatic scroll is only recorded ([last]).
///
/// - A drag starts a fresh accumulation ([beginDrag]).
/// - Past an end, only motion further past it counts (a rubber band's
///   return does not).
/// - Motion in the minimizing direction starts the interaction once it
///   passes [TabBarMinimizeTuning.activationDistance], if the
///   content's range is at least
///   [TabBarMinimizeTuning.minimumRangeFactor] x (activation + active
///   distance); from then on
///   [progress] grows by the scroll over
///   [TabBarMinimizeTuning.activeDistance], clamped to 0.01 - 1; at 1
///   the bar minimizes and the interaction rests until the next drag.
/// - The end of a drag that does not decelerate, and the end of a
///   deceleration, floor [progress]: a scroll that stopped short returns
///   to 0.
/// - Pushing further past the far end while the bar is minimized expands
///   it, as does reaching the near end while the interaction runs.
/// - A scroll to the top ([scrollToTop]) expands it.
/// - A drag in the expanding direction in the middle of the content does
///   not expand a minimized bar: UIKit's code has no such path, and on the
///   iOS 27 simulator a 150 point drag back left the bar minimized,
///   although the SDK header says the bar expands when the content
///   scrolls back.
@internal
class ScrollAway {
  /// Creates the interaction; [minimizesOnScrollUp] reverses the
  /// minimizing direction (UIKit `onScrollUp`).
  ScrollAway({this.minimizesOnScrollUp = false});

  /// Whether scrolling toward the content's start minimizes the bar.
  bool minimizesOnScrollUp;

  /// How far the bar has gone toward minimizing: 0 expanded, 1 minimized.
  double get progress => _progress;
  double _progress = 0;

  /// Called with the new [progress] and whether a finger drags the
  /// content, whenever [progress] changes.
  void Function(double progress, {required bool tracking})? onProgress;

  _State _state = _State.idle;
  double _accumulated = 0;
  double _startProgress = 0;

  /// The content's offset when it last moved; set it to record a scroll the
  /// user did not drive, without reacting to it.
  double? last;
  bool _tracking = false;

  /// Starts a fresh accumulation: a finger began to drag the content.
  void beginDrag() {
    _state = _State.accumulating;
    _accumulated = 0;
    _tracking = true;
  }

  /// Puts [progress] at [value] without reporting it: the bar was
  /// minimized or expanded by other means (a tap, the app).
  void reset(double value) {
    _state = _State.idle;
    _progress = value;
  }

  /// Reacts to the content scrolled to [offset] by a user (dragging when
  /// [tracking], else decelerating), its ends at [min] and [max].
  void scroll(
    double offset, {
    required double min,
    required double max,
    required bool tracking,
  }) {
    _tracking = tracking;
    final previous = last;
    last = offset;
    if (previous == null || _state == _State.idle) return;
    var delta = offset - previous;
    if (offset > max && delta < 0) delta = 0;
    if (offset < min && delta > 0) delta = 0;
    final signed = minimizesOnScrollUp ? -delta : delta;
    var excess = 0.0;
    if (_state == _State.accumulating) {
      final same = (signed < 0) == (_accumulated < 0);
      final acc = same ? _accumulated + signed : signed;
      _accumulated = acc;
      const threshold = TabBarMinimizeTuning.activationDistance;
      if (acc.abs() < threshold) return;
      final atFarEdge = minimizesOnScrollUp ? offset <= min : offset >= max;
      if (atFarEdge && signed > 0 && _progress != 0) {
        _state = _State.idle;
        _set(0);
        return;
      }
      const range =
          TabBarMinimizeTuning.minimumRangeFactor *
          (threshold + TabBarMinimizeTuning.activeDistance);
      if (acc < threshold || max - min < range) return;
      _state = _State.active;
      _startProgress = _progress;
      excess = acc - threshold > 0 ? acc - threshold : 0;
    } else {
      excess = signed;
    }
    final atNearEdge = minimizesOnScrollUp ? offset >= max : offset <= min;
    if (atNearEdge && excess < 0 && _startProgress != 0) {
      _state = _State.idle;
      _set(0);
      return;
    }
    if (_progress == 1) return;
    final next = (_progress + excess / TabBarMinimizeTuning.activeDistance)
        .clamp(TabBarMinimizeTuning.minimumProgress, 1.0);
    if (next == _progress) return;
    if (next == 1) _state = _State.idle;
    _set(next);
  }

  /// The finger lifted; [decelerates] when the content goes on moving.
  void endDrag({required bool decelerates}) {
    _tracking = false;
    if (decelerates) return;
    _end();
  }

  /// The content stopped after a deceleration.
  void endDeceleration() => _end();

  /// The content is scrolled to its top: the bar expands.
  void scrollToTop() {
    _state = _State.idle;
    _set(0);
  }

  void _end() {
    _state = _State.idle;
    _tracking = false;
    _set(_progress.floorToDouble());
  }

  void _set(double value) {
    if (value == _progress) return;
    _progress = value;
    onProgress?.call(value, tracking: _tracking);
  }
}

enum _State { accumulating, active, idle }

/// The motion of a minimizing tab bar: the scroll-away interaction
/// ([ScrollAway]), the hint scale it drives and the morph between the
/// expanded bar and its minimized circle.
///
/// While a scroll carries the bar toward minimizing, the whole bar group
/// draws smaller by [TabBarMinimizeTuning.hintScale] x progress on
/// the tracking spring (a finger down) or the progress spring
/// (decelerating), and returns to full size on the reset spring when it
/// minimizes, expands or the scroll stops short. Minimizing or expanding
/// runs the liquid morph of the bar ([morph]) on one spring, and moves the
/// bottom accessory along the bar ([accessoryX]) and up it ([accessoryY])
/// one after the other. A change in the middle of another turns it around
/// with its velocity.
///
/// Times are seconds on the caller's clock.
@internal
class TabBarMinimizeMotion {
  /// Creates the motion of a bar that minimizes as [behavior] says.
  TabBarMinimizeMotion({
    GlassTabBarMinimizeBehavior behavior =
        GlassTabBarMinimizeBehavior.onScrollDown,
  }) : _behavior = behavior {
    scrollAway.minimizesOnScrollUp =
        behavior == GlassTabBarMinimizeBehavior.onScrollUp;
    scrollAway.onProgress = _progressChanged;
  }

  /// The scroll-away interaction; feed it the content's scrolls.
  final ScrollAway scrollAway = ScrollAway();

  final _hint = MotionValue<double>(
    1,
    spring: TabBarMinimizeTuning.hintResetSpring,
  );
  final _morph = MotionValue<double>(
    0,
    spring: TabBarMinimizeTuning.morphSpring,
  );
  final _accessoryX = MotionValue<double>(
    0,
    spring: TabBarMinimizeTuning.accessoryCollapseSpring,
  );
  final _accessoryY = MotionValue<double>(
    0,
    spring: TabBarMinimizeTuning.accessoryExpandSpring,
  );
  final MotionTimeline _timeline = MotionTimeline(now: 0);
  double _now = 0;
  int _generation = 0;

  /// The behavior; a bar that no longer minimizes expands.
  GlassTabBarMinimizeBehavior get behavior => _behavior;
  GlassTabBarMinimizeBehavior _behavior;

  /// Changes the behavior at time [t].
  void setBehavior(double t, GlassTabBarMinimizeBehavior value) {
    if (value == _behavior) return;
    _behavior = value;
    scrollAway.minimizesOnScrollUp =
        value == GlassTabBarMinimizeBehavior.onScrollUp;
    scrollAway.reset(0);
    _hint.retarget(t, 1, spring: TabBarMinimizeTuning.hintResetSpring);
    if (!value.minimizes) setMinimized(t, minimized: false);
  }

  /// Whether the morph runs on its Reduce Motion spring.
  bool reducedMotion = false;

  /// Whether the bar is minimized or heading there.
  bool get minimized => _minimized;
  bool _minimized = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Minimizes or expands the bar at time [t].
  void setMinimized(double t, {required bool minimized}) {
    scrollAway.reset(minimized ? 1 : 0);
    if (_hint.target != 1) {
      _hint.retarget(t, 1, spring: TabBarMinimizeTuning.hintResetSpring);
    }
    _transition(t, minimized: minimized);
  }

  void _progressChanged(double progress, {required bool tracking}) {
    final t = _now;
    if (progress > 0 && progress < 1) {
      _hint.retarget(
        t,
        1 - progress * TabBarMinimizeTuning.hintScale,
        spring: tracking
            ? TabBarMinimizeTuning.hintTrackingSpring
            : TabBarMinimizeTuning.hintSpring,
      );
    } else {
      _hint.retarget(t, 1, spring: TabBarMinimizeTuning.hintResetSpring);
    }
    if (progress == 0 && _minimized) _transition(t, minimized: false);
    if (progress == 1 && !_minimized && _behavior.minimizes) {
      _transition(t, minimized: true);
    }
  }

  void _transition(double t, {required bool minimized}) {
    if (minimized == _minimized) return;
    _minimized = minimized;
    final generation = ++_generation;
    final target = minimized ? 1.0 : 0.0;
    _morph.retarget(
      t,
      target,
      spring: reducedMotion
          ? TabBarMinimizeTuning.reducedMotionMorphSpring
          : TabBarMinimizeTuning.morphSpring,
    );
    // Collapsing, the accessory moves along first and up after; expanding,
    // up first and along after: an L, not a straight path.
    final first = minimized ? _accessoryX : _accessoryY;
    final second = minimized ? _accessoryY : _accessoryX;
    first.retarget(
      t,
      target,
      spring: minimized
          ? TabBarMinimizeTuning.accessoryCollapseSpring
          : TabBarMinimizeTuning.accessoryExpandSpring,
    );
    _timeline.at(t + TabBarMinimizeTuning.accessoryFollowDelay, (double at) {
      if (generation != _generation) return;
      second.retarget(
        at,
        target,
        spring: minimized
            ? TabBarMinimizeTuning.accessoryCollapseFollowSpring
            : TabBarMinimizeTuning.accessoryExpandFollowSpring,
      );
    });
  }

  double? _pressX;
  bool _held = false;
  bool _scrubs = false;
  int _press = 0;

  /// Whether a finger that went down on the minimized bar is still on it.
  bool get pressed => _pressX != null;

  /// Whether the finger on the bar has rested long enough to expand it
  /// under itself ([TabBarMinimizeTuning.holdDuration]).
  bool get held => _held;

  /// Whether the finger on the bar has become the bar's selection drag
  /// ([pressMove] returned true): it scrubs the tabs and its release
  /// selects, as the expanded bar's own drag does.
  bool get scrubs => _scrubs;

  /// A finger went down at [x] along the minimized bar at time [t].
  ///
  /// Held for [TabBarMinimizeTuning.holdDuration] without moving,
  /// the bar expands under it (UIKit's interactive expansion of the
  /// minimized tab bar). Nothing happens on a bar that is not minimized.
  void pressDown(double t, double x) {
    if (!_minimized) return;
    _pressX = x;
    _held = false;
    _scrubs = false;
    final press = ++_press;
    _timeline.at(t + TabBarMinimizeTuning.holdDuration, (double at) {
      if (press != _press || _pressX == null || _scrubs) return;
      _held = true;
      setMinimized(at, minimized: false);
    });
  }

  /// The finger moved to [x] along the bar at time [t]; true on the move
  /// that makes it the bar's selection drag.
  ///
  /// A move of [TabBarMinimizeTuning.holdHysteresis] from where the
  /// finger went down, before or after the hold expanded the bar, expands
  /// it for good: from then on the touch is the expanded bar's drag.
  bool pressMove(double t, double x) {
    final from = _pressX;
    if (from == null || _scrubs) return false;
    if ((x - from).abs() < TabBarMinimizeTuning.holdHysteresis) {
      return false;
    }
    _scrubs = true;
    if (_minimized) setMinimized(t, minimized: false);
    return true;
  }

  /// The finger lifted at time [t].
  ///
  /// After a hold that did not move, the bar collapses back, as UIKit's
  /// interactive expansion ends; a drag leaves it expanded. A release
  /// before the hold expands the bar: UIKit's tab bar does not
  /// (`expandsOnTap` is NO), but a tap on the minimized bar has no other
  /// path back to the tabs in the code read; this waits for a recording.
  void pressUp(double t) {
    if (_pressX == null) return;
    final held = _held;
    final scrubs = _scrubs;
    _endPress();
    if (scrubs) return;
    setMinimized(t, minimized: held);
  }

  /// The touch was taken away at time [t]: a held bar collapses back.
  void pressCancel(double t) {
    if (_pressX == null) return;
    final back = _held && !_scrubs;
    _endPress();
    if (back) setMinimized(t, minimized: true);
  }

  void _endPress() {
    _press++;
    _pressX = null;
    _held = false;
    _scrubs = false;
  }

  /// The time the motion next changes on its own (a held finger's
  /// expansion) while every spring rests within [GlassRest] for a bar
  /// group [extent] points wide, or null.
  double? wakeTime({double extent = 400}) {
    final due = _timeline.nextDue;
    if (due == null) return null;
    return _resting(extent) ? due : null;
  }

  /// Advances the motion to time [t]; feed scrolls stamped at [t] after.
  void advance(double t) {
    _timeline.runDue(t);
    if (t > _now) _now = t;
  }

  /// The scale of the bar group: 1, or less while a scroll
  /// hints at minimizing.
  double get hint => _hintAt(_now);

  double _hintAt(double t) => _hint.valueAt(t);

  /// The morph's way from the expanded bar (0) to the minimized circle
  /// (1): of the glass's shape and of the content.
  double get morph => _morph.valueAt(_now);

  /// The bottom accessory's way from above the bar (0) to beside the
  /// circle (1) along the bar: its horizontal position and width.
  double get accessoryX => _accessoryX.valueAt(_now);

  /// The bottom accessory's way from above the bar (0) to beside the
  /// circle (1) up the screen: its vertical position and height.
  double get accessoryY => _accessoryY.valueAt(_now);

  List<MotionValue<double>> get _channels => [_morph, _accessoryX, _accessoryY];

  /// Whether the bar rests expanded: nothing of the morph moves and
  /// nothing is pending.
  bool get restsExpanded =>
      !_minimized &&
      _timeline.isEmpty &&
      _channels.every(
        (value) => value.target == 0 && value.valueAt(_now) == 0,
      );

  bool _resting(double extent) =>
      _hint.isWithin(_now, GlassRest.scale(extent)) &&
      _channels.every(
        (value) => value.isWithin(_now, GlassRest.scale(extent)),
      );

  /// Whether nothing moves: every spring is within its visible rest
  /// ([GlassRest]) for a bar group [extent] points wide, and nothing is
  /// pending.
  bool isSettled({double extent = 400}) =>
      _timeline.isEmpty && _resting(extent);

  /// Puts every spring onto its target at time [t] (NEAR, invisible: the
  /// motion has settled within [GlassRest]).
  void settle(double t) {
    _hint.settle(t);
    for (final value in _channels) {
      value.settle(t);
    }
  }
}
