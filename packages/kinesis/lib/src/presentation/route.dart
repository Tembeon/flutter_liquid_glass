import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// What asked a presentation to go.
enum DismissTrigger {
  /// A tap outside the content, on the barrier or on what the presentation
  /// counts as outside.
  outsideTap,

  /// The Escape key ([DismissIntent]).
  escape,

  /// The back button, Android back or `Navigator.maybePop`.
  back,

  /// A screen reader's dismiss action.
  accessibility,

  /// A gesture of the presentation's own, such as a drag down.
  interaction,

  /// Code: `Navigator.pop` or [PresentationRoute.dismiss] with no checks.
  programmatic,
}

// A mixin, not a base class: the two shells must be a PopupRoute and a
// PageRoute, which the navigator, HeroController and RouteObserver check.
mixin _PresentationEngine<T> on ModalRoute<T> {
  /// The name screen readers announce for the presented content.
  String? get semanticsLabel;

  late final _StatusProjection _projection = _StatusProjection();
  Ticker? _settle;
  DismissTrigger _trigger = DismissTrigger.programmatic;
  bool _finished = false;
  bool _removeAtEnd = false;
  bool _popped = false;
  ValueNotifier<bool>? _barrierModal;
  T? _result;
  CapturedThemes? _themes;

  /// Builds the content, which runs the motion and reports [didOpen] and
  /// [didLeave].
  @protected
  Widget buildContent(BuildContext context);

  /// Starts the content's close after a dismissal by [trigger]; false when
  /// there is nothing to close, which ends the route at once.
  @protected
  bool leave(DismissTrigger trigger);

  /// Whether [trigger] may dismiss the presentation, before its
  /// `PopScope`s are asked; a programmatic dismissal does not ask.
  @protected
  bool allows(DismissTrigger trigger) => true;

  /// The result a pop with [result] completes with.
  @protected
  T? resultFor(T? result) => result;

  /// Called when a `PopScope` of the content vetoed a dismissal by
  /// [trigger].
  @protected
  void didVetoDismiss(DismissTrigger trigger) {}

  /// Called when the route is presented, by a push or without one, before
  /// its content builds.
  @protected
  void didPresent() {}

  /// Whether the route is modal now: its barrier absorbs taps and hides
  /// the routes below from screen readers. A sheet resting at a detent that
  /// does not dim is not; call [modalityChanged] when the answer changes.
  @protected
  bool get modal => true;

  /// Applies a change of [modal] to the barrier; one reported while the
  /// frame builds applies in the next frame.
  void modalityChanged() {
    final barrier = _barrierModal;
    if (barrier == null || modal == barrier.value) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (isActive) modalityChanged();
      });
      scheduler.ensureVisualUpdate();
      return;
    }
    barrier.value = modal;
  }

  /// Called once, when the route's close has finished or the route was
  /// disposed before that, with the result the route completed with.
  @protected
  void didFinish(T? result) {}

  /// Whether the route was popped and its content closes.
  bool get isLeaving => _projection.status == AnimationStatus.reverse;

  bool _interacting = false;

  /// Shows the routes below while a gesture of the content moves it toward
  /// its dismissal, as an interactive pop does: they stay built and painted
  /// until [endInteraction], and the navigator knows a user gesture runs.
  void beginInteraction() {
    if (!isActive || isLeaving || _interacting) return;
    _interacting = true;
    navigator?.didStartUserGesture();
    _projection.update(AnimationStatus.forward);
  }

  /// Ends what [beginInteraction] began; a route the gesture did not
  /// dismiss rests again. Call it once the content has come back, or after
  /// the dismissal the gesture made.
  void endInteraction() {
    if (!_interacting) return;
    _interacting = false;
    navigator?.didStopUserGesture();
    if (!isLeaving) _projection.update(AnimationStatus.completed);
  }

  /// Reports that the content's open came to rest: the push completes.
  void didOpen() {
    if (!isActive || isLeaving) return;
    _projection.update(AnimationStatus.completed);
    _completeSettle();
  }

  /// Reports that the content's close reached its end: the route goes.
  /// Later reports change nothing.
  void didLeave() {
    if (_finished) return;
    _completeSettle();
    if (_removeAtEnd) {
      // removeRoute disposes the route itself; a dismissed status would ask
      // the navigator to finalize a route it no longer has.
      _removeAtEnd = false;
      if (isActive) _remove();
    } else if (_popped) {
      _projection.update(AnimationStatus.dismissed);
    }
    _finish();
  }

  /// Whether a dismissal by [trigger] would close the presentation now:
  /// [allows] lets it, no `PopScope` of the content vetoes it and no local
  /// history entry takes it first. A programmatic one always goes while
  /// the route is presented.
  bool canDismiss(DismissTrigger trigger) =>
      isActive &&
      !isLeaving &&
      (trigger == DismissTrigger.programmatic ||
          (allows(trigger) &&
              !willHandlePopInternally &&
              super.popDisposition == RoutePopDisposition.pop));

  /// Dismisses the presentation for [trigger] with [result].
  ///
  /// A [DismissTrigger.programmatic] dismissal pops at once; any other
  /// goes through [allows] and the content's `PopScope`s first.
  void dismiss(DismissTrigger trigger, [T? result]) {
    final nav = navigator;
    if (nav == null || !isActive || isLeaving) return;
    if (trigger != DismissTrigger.programmatic) {
      if (!allows(trigger)) {
        didVetoDismiss(trigger);
        return;
      }
      if (super.popDisposition != RoutePopDisposition.pop) {
        super.onPopInvokedWithResult(false, result);
        didVetoDismiss(trigger);
        return;
      }
    }
    _trigger = trigger;
    if (isCurrent) {
      nav.pop<T>(result);
      return;
    }
    _result = resultFor(result);
    _completeSettle();
    _projection.update(AnimationStatus.reverse);
    if (leave(trigger)) {
      _removeAtEnd = true;
    } else {
      _remove();
      _finish();
    }
  }

  /// Captures the themes around [from] for the content, as a presentation
  /// shown from a source carries the source's look.
  @internal
  void captureThemes(BuildContext from, NavigatorState to) =>
      _themes = InheritedTheme.capture(from: from, to: to.context);

  @override
  @nonVirtual
  Color? get barrierColor => null;

  @override
  @nonVirtual
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  @nonVirtual
  Duration get transitionDuration => Duration.zero;

  @override
  @nonVirtual
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  @nonVirtual
  Animation<double> createAnimation() => _projection;

  @override
  @nonVirtual
  bool get finishedWhenPopped => false;

  // While presented, Back reaches the gate through onPopInvokedWithResult
  // instead of popping the route under the Navigator's own check.
  @override
  @nonVirtual
  RoutePopDisposition get popDisposition {
    final base = super.popDisposition;
    return isActive && !isLeaving && base != RoutePopDisposition.bubble
        ? RoutePopDisposition.doNotPop
        : base;
  }

  @override
  @nonVirtual
  void onPopInvokedWithResult(bool didPop, T? result) {
    if (didPop) {
      super.onPopInvokedWithResult(didPop, result);
    } else {
      dismiss(DismissTrigger.back, result);
    }
  }

  @override
  @nonVirtual
  TickerFuture didPush() {
    didPresent();
    _projection.update(AnimationStatus.forward);
    final settle = _settle = Ticker((_) {});
    settle.muted = true;
    final opened = settle.start();
    super.didPush();
    return opened;
  }

  @override
  @nonVirtual
  void didAdd() {
    didPresent();
    super.didAdd();
    _projection.update(AnimationStatus.completed);
  }

  @override
  @nonVirtual
  void didReplace(Route<Object?>? oldRoute) {
    didPresent();
    super.didReplace(oldRoute);
    _projection.update(AnimationStatus.completed);
  }

  @override
  @nonVirtual
  bool didPop(T? result) {
    final trigger = _trigger;
    _trigger = DismissTrigger.programmatic;
    // A route already closing under its cover keeps its result and its
    // close; the pop only makes it leave as a popped route.
    final closing = _removeAtEnd;
    final resolved = closing ? _result : resultFor(result);
    if (!super.didPop(resolved)) return false;
    _popped = true;
    _removeAtEnd = false;
    _result = resolved;
    _completeSettle();
    _projection.update(AnimationStatus.reverse);
    if (!closing && !leave(trigger)) didLeave();
    return true;
  }

  @override
  @nonVirtual
  Widget buildModalBarrier() => ValueListenableBuilder<bool>(
    valueListenable: _barrierModal ??= ValueNotifier<bool>(modal),
    builder: (context, modal, _) => modal
        ? ModalBarrier(
            dismissible: allows(DismissTrigger.outsideTap),
            semanticsLabel: barrierLabel,
            onDismiss: () => dismiss(DismissTrigger.outsideTap),
          )
        : const SizedBox.shrink(),
  );

  // The content root sits outside the page's repaint boundary, so the
  // content repainting every frame of its motion does not repaint it.
  @override
  @nonVirtual
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _ContentRoot(route: this, child: child);

  @override
  @nonVirtual
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final content = Builder(builder: buildContent);
    return _themes?.wrap(content) ?? content;
  }

  // A route removed from under others still tells its PopScopes it went.
  void _remove() {
    super.onPopInvokedWithResult(true, _result);
    navigator?.removeRoute(this, _result);
  }

  void _completeSettle() {
    final settle = _settle;
    if (settle != null && settle.isActive) settle.stop();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    didFinish(_result);
  }

  @override
  void dispose() {
    _settle?.dispose();
    _finish();
    super.dispose();
    _projection.dispose();
    _barrierModal?.dispose();
  }
}

/// A presented route whose motion lives in its content: a sheet, an alert,
/// a popover, a menu.
///
/// UIKit: a presented `UIViewController` with a custom transition.
/// SwiftUI: `.sheet`, `.alert`, `.popover`. Flutter: a [PopupRoute].
///
/// The route owns the lifecycle and the content owns the motion. The
/// content reports [didOpen] when the open comes to rest and [didLeave]
/// when the close first reaches its end; the route starts the close
/// through [leave] once it is popped. Only the status of [animation]
/// follows the motion, its value stays 1, so nothing the route builds
/// rebuilds as the motion runs. The push's transition completes at the
/// open's rest, so a `pushReplacement` keeps the replaced route until the
/// new one is in place. The future of `Navigator.push` completes at the
/// pop, as the close starts; for a route dismissed under another, when it
/// leaves the navigator.
///
/// Every user dismissal (an outside tap, Escape, Back, a screen reader's
/// dismiss, a gesture of the content) goes through one gate: [allows] for
/// the trigger, then the content's `PopScope`s. A `PopScope` veto tells the
/// `PopScope`s with `didPop` false, as a blocked Back does, and calls
/// [didVetoDismiss], as a trigger [allows] refuses does. On the first route
/// of its navigator Back goes on to whatever is outside the navigator. A
/// dismissal always pops this route, never whatever
/// is on top: one under another route closes under it and leaves the
/// navigator when its close ends. `Navigator.pop` is programmatic and
/// consults nothing.
///
/// While [modal], the barrier absorbs taps and hides the routes below from
/// screen readers; with a [barrierLabel] and an [allows] outside tap it is
/// a labelled dismiss target.
abstract class PresentationRoute<T> extends PopupRoute<T>
    with _PresentationEngine<T> {
  /// Creates a presentation route.
  PresentationRoute({
    super.settings,
    super.requestFocus,
    super.traversalEdgeBehavior,
    this.semanticsLabel,
  });

  @override
  final String? semanticsLabel;
}

/// A page whose motion lives in its content, such as a page that zooms out
/// of its source.
///
/// UIKit: a pushed `UIViewController` whose transition the content drives
/// (a slide, `.zoom`).
/// Flutter: a [PageRoute].
///
/// It has the lifecycle, the dismissal gate and the barrier of
/// [PresentationRoute], and is a [PageRoute] to `RouteAware` observers and
/// to its neighbours. Its [animation]'s value stays 1: a neighbour's
/// secondary transition jumps to its end (a page below that should stay
/// put returns false from `canTransitionTo` for it), and no `Hero` flies.
abstract class PresentationPageRoute<T> extends PageRoute<T>
    with _PresentationEngine<T> {
  /// Creates a presentation page route.
  PresentationPageRoute({
    super.settings,
    super.requestFocus,
    this.semanticsLabel,
  });

  @override
  final String? semanticsLabel;
}

class _ContentRoot extends StatefulWidget {
  const _ContentRoot({required this.route, required this.child});

  final _PresentationEngine<Object?> route;
  final Widget child;

  @override
  State<_ContentRoot> createState() => _ContentRootState();
}

class _ContentRootState extends State<_ContentRoot> {
  final FocusNode _fallback = FocusNode(
    debugLabel: 'PresentationRoute',
    skipTraversal: true,
  );

  FocusScopeNode? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = Focus.maybeOf(
      context,
      scopeOk: true,
      createDependency: false,
    )?.nearestScope;
    if (identical(scope, _scope)) return;
    _scope?.removeListener(_catchScopeFocus);
    _scope = scope;
    scope?.addListener(_catchScopeFocus);
  }

  // Escape reaches the dismiss action only from focus inside it. When the
  // route's scope keeps focus itself, nothing in the content took it, so
  // the content root takes it; what the content focuses wins.
  void _catchScopeFocus() {
    if (_scope?.hasPrimaryFocus ?? false) _fallback.requestFocus();
  }

  @override
  void dispose() {
    _scope?.removeListener(_catchScopeFocus);
    _fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    return Semantics(
      scopesRoute: true,
      namesRoute: route.semanticsLabel != null,
      explicitChildNodes: true,
      label: route.semanticsLabel,
      onDismiss: route.allows(DismissTrigger.accessibility)
          ? () => route.dismiss(DismissTrigger.accessibility)
          : null,
      child: Actions(
        actions: <Type, Action<Intent>>{DismissIntent: _DismissAction(route)},
        child: Focus(
          focusNode: _fallback,
          includeSemantics: false,
          child: widget.child,
        ),
      ),
    );
  }
}

class _DismissAction extends DismissAction {
  _DismissAction(this.route);

  final _PresentationEngine<Object?> route;

  @override
  bool isEnabled(DismissIntent intent) =>
      route.isActive && !route.isLeaving && route.allows(DismissTrigger.escape);

  @override
  void invoke(DismissIntent intent) => route.dismiss(DismissTrigger.escape);
}

final class _StatusProjection extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  double get value => 1;

  @override
  AnimationStatus get status => _status;

  void update(AnimationStatus status) {
    if (status == _status) return;
    _status = status;
    notifyStatusListeners(status);
  }

  void dispose() {
    clearListeners();
    clearStatusListeners();
  }

  @override
  void didRegisterListener() {}

  @override
  void didUnregisterListener() {}
}
