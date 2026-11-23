import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/presentation/presentation.dart';
import 'package:kinesis/src/widgets/source.dart';

/// The part of a presentation's life that does not depend on where it
/// shows, shared by the route and the portal: the committed motion and the
/// source's lease, whether it leaves, whether it is modal, the result it
/// completes with, the dismissal policy, the scrollable it leaves with and
/// its single end.
@internal
final class PresentationSession {
  /// A session for the shell's `presentation`, read at each use, since a
  /// portal's can change while it shows; the motion runs on `scopeClock`
  /// until the commit makes one.
  PresentationSession({
    required this._presentation,
    required MotionClock Function() scopeClock,
  }) : _scopeClockOf = scopeClock;

  final Presentation<Object?, Presented> Function() _presentation;
  final MotionClock Function() _scopeClockOf;

  Presented? _motion;
  VoidCallback? _lease;
  MotionClock? _scopeClock;
  bool _leaving = false;
  bool _ended = false;
  bool _disposed = false;
  Object? _result;
  ScrollPosition? _scroll;
  VoidCallback? _onScroll;
  final ValueNotifier<bool> _inert = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _modal = ValueNotifier<bool>(true);

  /// The presentation the shell shows now.
  Presentation<Object?, Presented> get presentation => _presentation();

  /// The committed motion; null before the commit and after the end.
  Presented? get motion => _motion;

  /// The motion's clock, or before there is one the clock of the place the
  /// presentation shows in.
  MotionClock get clock => _motion?.clock ?? (_scopeClock ??= _scopeClockOf());

  /// Whether the presentation was dismissed and its motion leaves; read at
  /// each touch, as a leave can start in any phase of a frame.
  bool get isLeaving => _leaving;

  /// [isLeaving] for what only a rebuild changes.
  ValueListenable<bool> get inert => _inert;

  /// Whether the presentation is modal now; true before the commit.
  ValueListenable<bool> get modal => _modal;

  /// The result the presentation completes with.
  Object? get result => _result;

  /// Commits the presentation for [environment]: makes its motion, leases
  /// its source and tells a [Sourced] motion where the source is, opens the
  /// motion at the environment's time and reads whether it is modal.
  void commit(PresentationEnvironment environment) {
    final presentation = _presentation();
    final motion = presentation.create(environment);
    final source = presentation.source;
    final lease = source?.lease();
    if (source != null && motion is Sourced) {
      (motion as Sourced).sourceMoved(environment.time, source.geometry);
    }
    motion.open(environment.time);
    _motion = motion;
    _lease = lease;
    _ended = false;
    _result = null;
    _setLeaving(false);
    _modal.value = _modalNow();
  }

  /// Whether the policy lets [trigger] through; a refusal calls the
  /// presentation's `onVeto`.
  bool admits(DismissTrigger trigger) {
    final presentation = _presentation();
    if (presentation.dismiss.allows(trigger)) return true;
    presentation.onVeto?.call(trigger);
    return false;
  }

  /// The result a dismissal with [popped] completes with: the
  /// presentation's mapping of it.
  Object? resultOf(Object? popped) => _presentation().resultOf(popped);

  /// Marks the presentation leaving and keeps [result], mapped by
  /// [resultOf] already, as what it completes with.
  ///
  /// The mapping stays with the caller because a route hands the mapped
  /// result to the navigator before its leave may start.
  void markLeaving(Object? result) {
    _setLeaving(true);
    _result = result;
  }

  /// Starts the motion's leave for [trigger] at the clock's time; false
  /// when there is nothing to close, which ends the presentation at once.
  bool startLeave(DismissTrigger trigger) =>
      _motion?.leave(clock.now, trigger) ?? false;

  /// [markLeaving] with [result], then [startLeave] for [trigger].
  bool leave(DismissTrigger trigger, Object? result) {
    markLeaving(result);
    return startLeave(trigger);
  }

  /// Brings a leaving presentation back: its motion opens again from where
  /// it is, at the clock's time.
  void reopen() {
    final motion = _motion;
    if (motion == null) return;
    _setLeaving(false);
    _result = null;
    motion.open(clock.now);
  }

  /// Applies a change of whether the presentation is modal; one reported
  /// while the frame builds, lays out or paints applies in the clock's
  /// coming publish phase, before the next frame builds.
  void modalityChanged() {
    if (_motion == null) return;
    final modal = _modalNow();
    if (modal == _modal.value) return;
    clock.runOutsideBuild(() {
      if (!_disposed && _motion != null) _modal.value = _modalNow();
    });
  }

  /// Calls [onScroll] when [position] starts to scroll; a null [position]
  /// stops following.
  void followScroll(ScrollPosition? position, VoidCallback onScroll) {
    _onScroll = onScroll;
    if (identical(position, _scroll)) return;
    _scroll?.isScrollingNotifier.removeListener(_scrolled);
    _scroll = position;
    position?.isScrollingNotifier.addListener(_scrolled);
  }

  /// Ends the presentation once per commit, and once before the first: the
  /// source is released. True on the call that ended it, after which the
  /// shell tells the presentation [result]; a later call does nothing.
  bool end() {
    if (_ended) return false;
    _ended = true;
    _lease?.call();
    _lease = null;
    _motion = null;
    return true;
  }

  /// Stops following the scrollable and releases the notifiers; the shell
  /// calls [end] first.
  void dispose() {
    _scroll?.isScrollingNotifier.removeListener(_scrolled);
    _scroll = null;
    _inert.dispose();
    _modal.dispose();
    _disposed = true;
  }

  void _scrolled() {
    if (_scroll?.isScrollingNotifier.value ?? false) _onScroll?.call();
  }

  bool _modalNow() {
    final motion = _motion;
    return motion == null || _presentation().modalOf(motion);
  }

  // A leave the content reports while it builds applies before the next
  // build: the touch gate already holds.
  void _setLeaving(bool leaving) {
    _leaving = leaving;
    if (_inert.value == leaving) return;
    clock.runOutsideBuild(() {
      if (!_disposed) _inert.value = _leaving;
    });
  }
}
