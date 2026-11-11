import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/presentation/presentation.dart';
import 'package:kinesis/src/presentation/presented.dart';
import 'package:kinesis/src/presentation/route.dart';
import 'package:kinesis/src/presentation/source.dart';

/// Presents and dismisses the presentation of a [PresentationPortal].
final class PresentationPortalController {
  /// Creates a controller for one portal.
  PresentationPortalController();

  _PresentationPortalState? _portal;

  /// Whether the presentation shows, leaving included.
  bool get isPresented => _portal?._motion != null;

  /// Presents at the clock's time: inside an input, the input's stamp. A
  /// presentation on its way out comes back: its motion opens again from
  /// where it is.
  void present() => _portal?._present();

  /// Dismisses for [trigger], through the policy unless it is
  /// programmatic.
  void dismiss(DismissTrigger trigger) => _portal?.dismiss(trigger);
}

/// The overlay shell: the [presentation] shows on the root overlay over
/// [child], with the dismissal policy, dim, barrier, focus, Escape, Back and
/// the screen reader's dismiss of a route, but nothing is pushed, so the
/// touch that presented it is never cancelled: a hold that opens a context
/// menu keeps its finger on the rows. The content's `PopScope`s are not
/// asked. As on a route, new touches reach what is below as soon as the
/// presentation leaves, while its close plays on.
class PresentationPortal extends StatefulWidget {
  /// Shows [presentation] over [child] when [controller] presents it.
  const PresentationPortal({
    required this.controller,
    required this.presentation,
    required this.child,
    super.key,
  });

  /// Presents and dismisses.
  final PresentationPortalController controller;

  /// What is presented.
  final Presentation<Object?, Presented> presentation;

  /// What the portal sits on: the source of the presentation.
  final Widget child;

  @override
  State<PresentationPortal> createState() => _PresentationPortalState();
}

class _PresentationPortalState extends State<PresentationPortal>
    implements PresentationShell, PopEntry<Object?> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final ValueNotifier<bool> _canPop = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _modal = ValueNotifier<bool>(true);
  final FocusScopeNode _scope = FocusScopeNode(
    debugLabel: 'PresentationPortal',
  );
  Presented? _motion;
  SourceLease? _lease;
  ModalRoute<Object?>? _route;
  FocusNode? _restore;
  Object? _result;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.controller._portal = this;
  }

  @override
  void didUpdateWidget(PresentationPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._portal = null;
      widget.controller._portal = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route?.unregisterPopEntry(this);
    _route = route;
    route?.registerPopEntry(this);
  }

  @override
  void dispose() {
    if (identical(widget.controller._portal, this)) {
      widget.controller._portal = null;
    }
    _route?.unregisterPopEntry(this);
    _end();
    _canPop.dispose();
    _modal.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _present() {
    final t = MotionClock.instance.now;
    final shown = _motion;
    if (shown != null) {
      if (!_leaving) return;
      _leaving = false;
      _result = null;
      _canPop.value = false;
      shown.open(t);
      return;
    }
    final presentation = widget.presentation;
    final motion = _motion = presentation.create(
      PresentationEnvironment.of(context, t),
    );
    final source = presentation.source;
    if (source != null) {
      _lease = source.lease();
      if (motion is Sourced) {
        (motion as Sourced).sourceMoved(t, source.geometry);
      }
    }
    motion.open(t);
    _leaving = false;
    _restore = FocusManager.instance.primaryFocus;
    _canPop.value = false;
    _modal.value = presentation.modalOf(motion);
    _overlay.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_motion, motion) && !_leaving) _scope.requestFocus();
    });
  }

  void _end() {
    if (_motion == null) return;
    _lease?.release();
    _lease = null;
    _motion = null;
    _leaving = false;
    _canPop.value = true;
    final result = _result;
    _result = null;
    widget.presentation.dismissed(result);
  }

  @override
  void dismiss(DismissTrigger trigger, [Object? result]) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    final presentation = widget.presentation;
    if (!presentation.dismiss.allows(trigger)) {
      presentation.onVeto?.call(trigger);
      return;
    }
    _leaving = true;
    _result = presentation.resultOf(result);
    if (!motion.leave(MotionClock.instance.now, trigger)) didLeave();
  }

  @override
  bool canDismiss(DismissTrigger trigger) =>
      _motion != null &&
      !_leaving &&
      widget.presentation.dismiss.allows(trigger);

  @override
  void didOpen() {}

  @override
  void didLeave() {
    if (_motion == null) return;
    _end();
    final restore = _restore;
    _restore = null;
    if (_scope.hasFocus && restore != null && restore.canRequestFocus) {
      restore.requestFocus();
    }
    if (mounted) _overlay.hide();
  }

  @override
  void modalityChanged() {
    final motion = _motion;
    if (motion != null) _modal.value = widget.presentation.modalOf(motion);
  }

  @override
  bool get isLeaving => _leaving;

  @override
  void beginInteraction() {}

  @override
  void endInteraction() {}

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) dismiss(DismissTrigger.back, result);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _overlay,
    overlayLocation: OverlayChildLocation.rootOverlay,
    overlayChildBuilder: _content,
    child: widget.child,
  );

  Widget _content(BuildContext context) {
    final motion = _motion;
    if (motion == null) return const SizedBox.shrink();
    final presentation = widget.presentation;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _modal,
          builder: (context, modal, _) => modal
              ? ModalBarrier(
                  barrierSemanticsDismissible: presentation.dismiss.allows(
                    DismissTrigger.outsideTap,
                  ),
                  onDismiss: () => dismiss(DismissTrigger.outsideTap),
                )
              : const SizedBox.shrink(),
        ),
        Semantics(
          scopesRoute: true,
          namesRoute: presentation.semanticsLabel != null,
          explicitChildNodes: true,
          label: presentation.semanticsLabel,
          onDismiss: presentation.dismiss.allows(DismissTrigger.accessibility)
              ? () => dismiss(DismissTrigger.accessibility)
              : null,
          child: Actions(
            actions: <Type, Action<Intent>>{
              if (presentation.dismiss.allows(DismissTrigger.escape))
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    dismiss(DismissTrigger.escape);
                    return null;
                  },
                ),
            },
            child: FocusScope(
              node: _scope,
              child: PresentedContent(
                presentation: presentation,
                motion: motion,
                shell: this,
              ),
            ),
          ),
        ),
      ],
    );
    return _LeavingGate(isLeaving: () => _leaving, child: content);
  }
}

/// Takes no new touches while [isLeaving], asked at each touch: a close can
/// start in any phase of a frame, and a finger already down stays with what
/// it touched.
class _LeavingGate extends SingleChildRenderObjectWidget {
  const _LeavingGate({required this.isLeaving, required super.child});

  final bool Function() isLeaving;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLeavingGate(isLeaving);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLeavingGate renderObject,
  ) {
    renderObject.isLeaving = isLeaving;
  }
}

class _RenderLeavingGate extends RenderProxyBox {
  _RenderLeavingGate(this.isLeaving);

  bool Function() isLeaving;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !isLeaving() && super.hitTest(result, position: position);
}
