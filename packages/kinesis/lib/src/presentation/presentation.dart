import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/presence.dart';
import 'package:kinesis/src/motion/presented.dart';
import 'package:kinesis/src/motion/selection.dart';
import 'package:kinesis/src/motion/source_geometry.dart';
import 'package:kinesis/src/motion/transaction.dart';
import 'package:kinesis/src/presentation/route.dart';
import 'package:kinesis/src/presentation/source.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';
import 'package:meta/meta.dart';

/// Where and how big a presentation may be, read from the place it shows
/// in when it commits.
@immutable
final class PresentationEnvironment {
  /// Describes the place a presentation commits into.
  const PresentationEnvironment({
    required this.time,
    required this.bounds,
    required this.padding,
    required this.traits,
  });

  /// The environment of [context] at [time].
  factory PresentationEnvironment.of(BuildContext context, double time) {
    final media = MediaQuery.maybeOf(context);
    return PresentationEnvironment(
      time: time,
      bounds: media?.size ?? Size.zero,
      padding:
          (media?.viewPadding ?? EdgeInsets.zero) +
          (media?.viewInsets ?? EdgeInsets.zero),
      traits: MotionTraitsOverride.of(context),
    );
  }

  /// The commit's time: the stamp of the input that presented it.
  final double time;

  /// The size of the place the presentation shows in.
  final Size bounds;

  /// What covers its edges: the safe area and the keyboard.
  final EdgeInsets padding;

  /// The motion preferences there.
  final MotionTraits traits;
}

/// A presentation: the motion it plays and the content over it. One
/// description runs in a route ([PresentationRoute], [PresentationPageRoute])
/// or a portal (`PresentationPortal`, for a touch that must not be
/// cancelled).
///
/// The shell commands the motion at stamped times: it opens it at the
/// commit and starts its leave at the dismissal's stamp. It completes the
/// push once the motion's presence is shown and ends once it is hidden
/// after a leave. A motion that starts leaving on its own dismisses the
/// presentation programmatically; its [Presented.leave] then answers true
/// for the leave already under way. The shell draws the [dim], owns the
/// barrier, Back, Escape, focus and the screen reader's dismiss, and holds
/// the [source] while it shows; a [Sourced] motion hears where the source
/// is in every frame.
///
/// ```dart
/// final alert = Presentation<bool, AlertMotion>(
///   motion: (environment) => AlertMotion(),
///   builder: (context, motion) => AlertCard(motion: motion),
///   dismiss: DismissPolicy.modal,
///   dim: (motion) => 0.2 * motion.dimming,
/// );
/// showPresentation(context, PresentationRoute(presentation: alert));
/// ```
@immutable
final class Presentation<T, M extends Presented> {
  /// Describes a presentation.
  const Presentation({
    required this.motion,
    required this.builder,
    this.source,
    this.dismiss = const DismissPolicy(),
    this.dim,
    this.dimColor = const Color(0xFF000000),
    this.modal,
    this.result,
    this.onVeto,
    this.onDismissed,
    this.semanticsLabel,
  });

  /// Makes the motion at the commit, or hands over one the caller keeps
  /// for longer (a menu's lives with its anchor).
  final M Function(PresentationEnvironment environment) motion;

  /// Builds the content over [motion].
  final Widget Function(BuildContext context, M motion) builder;

  /// What the presentation grows out of, hidden while it shows.
  final MotionSource? source;

  /// Which user dismissals go through.
  final DismissPolicy dismiss;

  /// The opacity of the dim behind the content, 0 to 1; none when null.
  final double Function(M motion)? dim;

  /// The color of the dim at opacity 1, black by default.
  final Color dimColor;

  /// Whether the presentation is modal now (its barrier absorbs taps and
  /// hides what is below from screen readers); always when null.
  final bool Function(M motion)? modal;

  /// The result a dismissal with [result] completes with: an alert's
  /// cancel action for a dismissal without one.
  final T? Function(T? result)? result;

  /// Called when [dismiss] or a `PopScope` refused a dismissal.
  final void Function(DismissTrigger trigger)? onVeto;

  /// Called once the presentation has gone, with what it completed with, as
  /// UIKit calls a dismissal's completion: an alert runs the chosen
  /// action's handler here.
  final void Function(T? result)? onDismissed;

  /// The name screen readers announce for the content.
  final String? semanticsLabel;

  // The calls below take the motion as a Presented and the result as an
  // Object?, so a shell holding a Presentation<Object?, Presented> calls
  // the functions of a Presentation<T, M> without a covariance error.

  /// Makes the motion for [environment].
  @internal
  Presented create(PresentationEnvironment environment) => motion(environment);

  /// Builds the content over [motion].
  @internal
  Widget build(BuildContext context, Presented motion) =>
      builder(context, motion as M);

  /// The dim's opacity for [motion], or null for none.
  @internal
  MotionSelection<double>? dimOf(Presented motion) {
    final dim = this.dim;
    if (dim == null) return null;
    return motion.select((m) => dim(m as M).clamp(0.0, 1.0));
  }

  /// Whether [modal] can change while the presentation shows.
  @internal
  bool get changesModality => modal != null;

  /// Whether the presentation is modal for [motion] now.
  @internal
  bool modalOf(Presented motion) => modal?.call(motion as M) ?? true;

  /// Tells [onDismissed] the presentation has gone with [result].
  @internal
  void dismissed(Object? result) => onDismissed?.call(result as T?);

  /// The result a dismissal with [popped] completes with.
  @internal
  Object? resultOf(Object? popped) {
    final result = this.result;
    return result == null ? popped : result(popped as T?);
  }
}

/// The content's hold on its shell.
abstract interface class PresentationHandle {
  /// The handle of the presentation around [context].
  static PresentationHandle of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HandleScope>();
    assert(scope != null, 'No presentation around $context.');
    return scope!.handle;
  }

  /// Dismisses the presentation for [trigger] with [result]. Unless
  /// [trigger] is programmatic it goes through the policy and, in a route,
  /// the content's `PopScope`s.
  void dismiss(DismissTrigger trigger, [Object? result]);

  /// Whether a dismissal by [trigger] would go through now: a sheet asks
  /// before a drag whether the drag may take it away.
  bool canDismiss(DismissTrigger trigger);

  /// Shows what is below while a gesture of the content moves it toward
  /// its dismissal; [endInteraction] ends it.
  void beginInteraction();

  /// Ends what [beginInteraction] began.
  void endInteraction();
}

/// What a shell does for the content it presents.
@internal
abstract interface class PresentationShell implements PresentationHandle {
  /// The motion's open came to rest.
  void didOpen();

  /// The motion's leave reached its end.
  void didLeave();

  /// The answer of [Presentation.modal] may have changed.
  void modalityChanged();

  /// Whether the presentation was dismissed and its motion leaves.
  bool get isLeaving;
}

class _HandleScope extends InheritedWidget {
  const _HandleScope({required this.handle, required super.child});

  final PresentationHandle handle;

  @override
  bool updateShouldNotify(_HandleScope oldWidget) =>
      !identical(handle, oldWidget.handle);
}

/// Runs a described presentation's motion inside a shell: holds it on the
/// clock, tells the shell when it opened and left, draws the dim and
/// follows the source.
@internal
class PresentedContent extends StatefulWidget {
  /// Shows [motion] of [presentation] in [shell].
  const PresentedContent({
    required this.presentation,
    required this.motion,
    required this.shell,
    super.key,
  });

  /// The description.
  final Presentation<Object?, Presented> presentation;

  /// The motion the shell committed.
  final Presented motion;

  /// The shell.
  final PresentationShell shell;

  @override
  State<PresentedContent> createState() => _PresentedContentState();
}

class _PresentedContentState extends State<PresentedContent> {
  late MotionSelection<PresenceStatus> _presence;
  late MotionSelection<bool>? _modal;
  late MotionSelection<double>? _dim;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(PresentedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.motion, widget.motion)) return;
    _unbind();
    _bind();
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _bind() {
    final motion = widget.motion;
    _presence = motion.select((m) => m.presence);
    _presence.addListener(_heard);
    final presentation = widget.presentation;
    _modal = !presentation.changesModality
        ? null
        : motion.select(presentation.modalOf);
    _modal?.addListener(widget.shell.modalityChanged);
    _dim = presentation.dimOf(motion);
    _heard();
  }

  void _unbind() {
    _presence.removeListener(_heard);
    _modal?.removeListener(widget.shell.modalityChanged);
  }

  void _heard() {
    final shell = widget.shell;
    switch (_presence.value) {
      case PresenceStatus.shown when !shell.isLeaving:
        shell.didOpen();
      case PresenceStatus.hidden when shell.isLeaving:
        shell.didLeave();
      // A motion that leaves on its own, as a menu does once a row is
      // chosen, takes the shell with it.
      case PresenceStatus.leaving when !shell.isLeaving:
        shell.dismiss(DismissTrigger.programmatic);
      case PresenceStatus.shown ||
          PresenceStatus.hidden ||
          PresenceStatus.opening ||
          PresenceStatus.leaving:
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final motion = widget.motion;
    Widget content = Builder(
      builder: (context) => presentation.build(context, motion),
    );
    final source = presentation.source;
    if (source != null && motion is Sourced) {
      content = SourceFollower(
        source: source,
        motion: motion as Sourced,
        child: content,
      );
    }
    final dim = _dim;
    if (dim != null) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: MotionTransition(
              opacity: dim,
              child: ColoredBox(color: presentation.dimColor),
            ),
          ),
          content,
        ],
      );
    }
    return _HandleScope(
      handle: widget.shell,
      child: MotionScope(motion: motion, child: content),
    );
  }
}
