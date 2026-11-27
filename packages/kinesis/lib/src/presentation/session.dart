import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/clock.dart' show MotionClockInternal;
import 'package:kinesis/src/presentation/dismiss.dart';
import 'package:kinesis/src/presentation/presentation.dart';
import 'package:kinesis/src/widgets/source.dart';

/// The part of a presentation's life that does not depend on where it
/// shows, shared by the route and the portal: the committed motion and the
/// source's lease, whether it leaves, whether it is modal, the result it
/// completes with, the dismissal policy, the dismissal when its scrollable
/// scrolls and its single end.
@internal
final class PresentationSession {
  /// A session for the shell's `presentation`, read at each use, since a
  /// portal's can change while it shows; the motion runs on `scopeClock`
  /// until the commit makes one. `dismiss` is the shell's gate.
  PresentationSession({
    required this._presentation,
    required MotionClock Function() scopeClock,
    required this._dismiss,
  }) : _scopeClockOf = scopeClock;

  final Presentation<Object?, Presented> Function() _presentation;
  final MotionClock Function() _scopeClockOf;
  final void Function(DismissTrigger trigger) _dismiss;

  Presented? _motion;
  VoidCallback? _lease;
  MotionClock? _scopeClock;
  bool _isDismissing = false;
  bool _disposed = false;
  Object? _result;
  ScrollPosition? _scrollable;
  ScrollPosition? _followed;
  MotionSelection<bool>? _modality;
  final ValueNotifier<bool> _dismissing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _modal = ValueNotifier<bool>(true);

  /// The presentation the shell shows now.
  Presentation<Object?, Presented> get presentation => _presentation();

  /// The committed motion; null before the commit and after the end.
  Presented? get motion => _motion;

  /// The motion's clock, or before there is one the clock of the place the
  /// presentation shows in.
  MotionClock get clock => _motion?.clock ?? (_scopeClock ??= _scopeClockOf());

  /// Whether the presentation was dismissed and its motion leaves; read at
  /// each touch, as a dismissal can start in any phase of a frame.
  bool get isDismissing => _isDismissing;

  /// [isDismissing] for what only a rebuild changes.
  ValueListenable<bool> get dismissing => _dismissing;

  /// Whether the presentation is modal now; true before the commit.
  ValueListenable<bool> get modal => _modal;

  /// The result the presentation completes with.
  Object? get result => _result;

  /// How focus traversal behaves at the content's edges: Tab stays inside
  /// while the presentation is modal, as in a dialog; [otherwise] while it
  /// is not.
  TraversalEdgeBehavior? edgesOr(TraversalEdgeBehavior? otherwise) =>
      _modal.value ? TraversalEdgeBehavior.closedLoop : otherwise;

  /// Commits the presentation for [environment]: makes its motion, gives it
  /// the environment's traits, leases its source and tells a [Sourced]
  /// motion where the source is, opens the motion at the environment's
  /// time, reads whether it is modal and follows the scrollable.
  void commit(PresentationEnvironment environment) {
    final presentation = _presentation();
    final motion = presentation.create(environment);
    assert(
      identical(motion.clock, environment.clock),
      'A presentation opens its motion at the time of the clock of the place '
      'it shows in: make the motion on PresentationEnvironment.clock.',
    );
    motion.traits = environment.traits;
    final source = presentation.source;
    final lease = source?.lease();
    if (source != null && motion is Sourced) {
      (motion as Sourced).sourceMoved(environment.time, source.geometry);
    }
    motion.open(environment.time);
    _motion = motion;
    _lease = lease;
    _result = null;
    _setDismissing(false);
    final modality = _modality = presentation.changesModality
        ? motion.select(presentation.modalOf)
        : null;
    modality?.addListener(_modalityChanged);
    _modal.value = modality?.value ?? presentation.modalOf(motion);
    _follow();
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

  /// Marks the presentation dismissed and keeps [result], mapped by
  /// [resultOf] already, as what it completes with.
  ///
  /// The mapping stays with the caller because a route hands the mapped
  /// result to the navigator before its leave may start.
  void markDismissing(Object? result) {
    _setDismissing(true);
    _result = result;
  }

  /// Starts the motion's leave at the clock's time; false when there is
  /// nothing to close, which ends the presentation at once.
  bool startLeave() => _motion?.leave(clock.now) ?? false;

  /// [markDismissing] with [result], then [startLeave].
  bool leave(Object? result) {
    markDismissing(result);
    return startLeave();
  }

  /// Brings a leaving presentation back: its motion opens again from where
  /// it is, at the clock's time.
  void reopen() {
    final motion = _motion;
    if (motion == null) return;
    _setDismissing(false);
    _result = null;
    motion.open(clock.now);
  }

  /// The scrollable around where the presentation was shown from: while
  /// it is committed and asks to ([Presentation.dismissesOnScroll]), it is
  /// dismissed for [DismissTrigger.scroll] when [position] starts to
  /// scroll.
  void followScrollable(ScrollPosition? position) {
    _scrollable = position;
    _follow();
  }

  /// Ends the committed presentation: the source is released. True on the
  /// call that ended it, after which the shell tells the presentation
  /// [result]; false when nothing is committed.
  bool end() {
    if (_motion == null) return false;
    _lease?.call();
    _lease = null;
    _modality?.removeListener(_modalityChanged);
    _modality = null;
    _motion = null;
    _follow();
    return true;
  }

  /// Releases the notifiers; the shell calls [end] first.
  void dispose() {
    _dismissing.dispose();
    _modal.dispose();
    _disposed = true;
  }

  void _follow() {
    final position = _motion == null ? null : _scrollable;
    if (identical(position, _followed)) return;
    _followed?.isScrollingNotifier.removeListener(_scrolled);
    _followed = position;
    position?.isScrollingNotifier.addListener(_scrolled);
  }

  void _scrolled() {
    if ((_followed?.isScrollingNotifier.value ?? false) &&
        _presentation().dismissesOnScroll) {
      _dismiss(DismissTrigger.scroll);
    }
  }

  // A change reported while the frame builds, lays out or paints applies
  // in the clock's coming publish phase, before the next frame builds.
  void _modalityChanged() {
    final modality = _modality;
    if (modality == null || modality.value == _modal.value) return;
    clock.runOutsideBuild(() {
      if (!_disposed && _modality != null) _modal.value = _modality!.value;
    });
  }

  // A dismissal the content reports while it builds applies before the
  // next build: the touch gate already holds.
  void _setDismissing(bool dismissing) {
    _isDismissing = dismissing;
    if (_dismissing.value == dismissing) return;
    clock.runOutsideBuild(() {
      if (!_disposed) _dismissing.value = _isDismissing;
    });
  }
}
