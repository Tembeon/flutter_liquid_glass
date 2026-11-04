import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/port.dart';

/// Turns pointer, keyboard, hover and accessibility input into the input
/// of its [interactions].
///
/// UIKit: a control's touch tracking with its gesture recognizers. SwiftUI:
/// a view's gestures. Flutter: `RawGestureDetector` with `Focus`,
/// `MouseRegion` and `Semantics`.
///
/// Every event of a touch the region follows is stamped on the motion clock
/// at its own time stamp, the release included, and the release carries
/// the velocity of the base `VelocityTracker` estimated with the release's
/// own sample, so a live drag ends as its replay does. The region joins the
/// gesture arena only for touches an interaction accepts, so one that
/// takes nothing never blocks a scroll, and it holds or gives up a touch as
/// its [InteractionSession] decides, including the scroll delay of a
/// control inside a scroll view. When an interaction [Interaction.activates]
/// (a press, a tap), Space, Enter and the accessibility tap activate it.
/// With a [port] it also hears the touches another region hands on to it
/// (`InputPort.forward`), mapped into its own coordinates. It
/// writes pressed, hovered, focused, dragged and disabled into
/// [statesController], and plays the haptic [feedback] picks for each
/// event as it happens; keyboard and accessibility activations play none.
class InputRegion extends StatefulWidget {
  /// Creates a region whose [interactions] answer input on [child].
  const InputRegion({
    required this.interactions,
    required this.child,
    this.statesController,
    this.feedback,
    this.enabled = true,
    this.mouseCursor,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.port,
    super.key,
  });

  /// The interactions; when two recognize on one input, the first wins.
  /// Their owner makes them once.
  final List<Interaction> interactions;

  /// The widget the region covers.
  final Widget child;

  /// Where the region writes its states, or null.
  final WidgetStatesController? statesController;

  /// The haptic for an event, or null for none.
  final MotionHaptic? Function(InteractionEvent event)? feedback;

  /// Whether the region takes input; disabling it ends a touch.
  final bool enabled;

  /// The cursor over the region.
  final MouseCursor? mouseCursor;

  /// The region's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the region takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the region.
  final String? semanticLabel;

  /// Where touches handed on from another region arrive, or null.
  final InputPort? port;

  @override
  State<InputRegion> createState() => _InputRegionState();
}

class _InputRegionState extends State<InputRegion> {
  late InteractionSession _session = InteractionSession(widget.interactions);
  FocusNode? _ownFocus;
  double? _scheduled;
  VoidCallback? _cancelDue;
  final Map<int, VelocityTracker> _trackers = {};
  final Map<int, _ArenaMember> _members = {};

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  MotionClock get _clock => MotionClock.instance;

  Iterable<Interaction> get _all =>
      widget.interactions.expand(flattenInteraction);

  _RenderListener? _box;

  @override
  void initState() {
    super.initState();
    widget.statesController?.update(WidgetState.disabled, !widget.enabled);
    _bindForwards();
    _attachPort(widget.port);
  }

  @override
  void didUpdateWidget(InputRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.interactions, widget.interactions)) {
      _cancelAll(PointerCancelReason.platform);
      _session = InteractionSession(widget.interactions);
      _bindForwards();
    }
    if (oldWidget.enabled && !widget.enabled) {
      _cancelAll(PointerCancelReason.disabled);
    }
    if (oldWidget.port != widget.port) {
      oldWidget.port?.detach(_receive);
      _attachPort(widget.port);
    }
    widget.statesController?.update(WidgetState.disabled, !widget.enabled);
  }

  @override
  void dispose() {
    widget.port?.detach(_receive);
    _cancelAll(PointerCancelReason.platform);
    _cancelDue?.call();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _bindForwards() {
    for (final forward in _all.whereType<PortForward>()) {
      forward.toGlobal = _toGlobal;
    }
  }

  Offset _toGlobal(Offset local) => _box?.localToGlobal(local) ?? local;

  // The receiver maps positions with its render box, which is laid out
  // only after the frame that built it.
  void _attachPort(InputPort? port) {
    if (port == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.port == port) port.attach(_receive);
    });
  }

  void _receive(PortEvent event) {
    final box = _box;
    if (!widget.enabled || box == null || !box.hasSize) return;
    final input = event.input(
      box.globalToLocal,
      size: box.size,
      scrollAxes: event.phase == PortPhase.down ? _scrollAxes() : const {},
    );
    _clock.input(input.time, () => _answer(_session.handle(input)));
  }

  Set<Axis> _scrollAxes() {
    final axes = <Axis>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        axes.add((element.state as ScrollableState).position.axis);
      }
      return true;
    });
    return axes;
  }

  void _pointer(PointerEvent event, Size size) {
    if (!widget.enabled) return;
    if (event is! PointerDownEvent && !_members.containsKey(event.pointer)) {
      return;
    }
    final time = _clock.stamp(event.timeStamp);
    _clock.input(time, () => _dispatch(event, size, time));
  }

  void _dispatch(PointerEvent event, Size size, double time) {
    switch (event) {
      case PointerDownEvent():
        final tracker = VelocityTracker.withKind(event.kind);
        tracker.addPosition(event.timeStamp, event.localPosition);
        final output = _session.handle(
          PointerDownInput(
            time: time,
            pointer: event.pointer,
            position: event.localPosition,
            regionSize: size,
            kind: event.kind,
            buttons: event.buttons,
            scrollAxes: _scrollAxes(),
          ),
        );
        if (output.reject) {
          _answer(output);
          return;
        }
        _trackers[event.pointer] = tracker;
        final member = _ArenaMember(this);
        _members[event.pointer] = member;
        member.entry = GestureBinding.instance.gestureArena.add(
          event.pointer,
          member,
        );
        _answer(output, pointer: event.pointer);
      case PointerMoveEvent():
        _trackers[event.pointer]?.addPosition(
          event.timeStamp,
          event.localPosition,
        );
        _answer(
          _session.handle(
            PointerMoveInput(
              time: time,
              pointer: event.pointer,
              position: event.localPosition,
            ),
          ),
          pointer: event.pointer,
        );
      case PointerUpEvent():
        final tracker = _trackers.remove(event.pointer);
        tracker?.addPosition(event.timeStamp, event.localPosition);
        final velocity = tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
        _answer(
          _session.handle(
            PointerUpInput(
              time: time,
              pointer: event.pointer,
              position: event.localPosition,
              velocity: velocity,
            ),
          ),
          pointer: event.pointer,
        );
        _members.remove(event.pointer);
      case PointerCancelEvent():
        _trackers.remove(event.pointer);
        _members.remove(event.pointer);
        _answer(
          _session.handle(
            PointerCancelInput(
              time: time,
              pointer: event.pointer,
              reason: PointerCancelReason.platform,
            ),
          ),
        );
      default:
        break;
    }
  }

  void _lost(int pointer) {
    if (_members.remove(pointer) == null) return;
    _trackers.remove(pointer);
    _answer(_session.lost(pointer, _clock.now));
  }

  void _cancelAll(PointerCancelReason reason) {
    for (final pointer in _members.keys.toList()) {
      _members.remove(pointer)?.entry?.resolve(GestureDisposition.rejected);
      _trackers.remove(pointer);
      _answer(
        _session.handle(
          PointerCancelInput(
            time: _clock.now,
            pointer: pointer,
            reason: reason,
          ),
        ),
      );
    }
  }

  void _input(InteractionInput input) {
    if (!widget.enabled) return;
    _clock.input(input.time, () => _answer(_session.handle(input)));
  }

  void _answer(SessionOutput output, {int? pointer}) {
    if (pointer != null) {
      final entry = _members[pointer]?.entry;
      if (output.claim) entry?.resolve(GestureDisposition.accepted);
      if (output.reject) entry?.resolve(GestureDisposition.rejected);
    }
    for (final event in output.events) {
      _play(event);
    }
    _writeStates();
    _scheduleDue();
  }

  void _play(InteractionEvent event) {
    if (event is ActivationEvent && event.source != ActivationSource.pointer) {
      return;
    }
    final haptic = widget.feedback?.call(event);
    if (haptic != null) _haptic(haptic);
  }

  static void _haptic(MotionHaptic haptic) {
    switch (haptic) {
      case MotionHaptic.selection:
        HapticFeedback.selectionClick();
      case MotionHaptic.lightImpact:
        HapticFeedback.lightImpact();
      case MotionHaptic.mediumImpact:
        HapticFeedback.mediumImpact();
      case MotionHaptic.heavyImpact:
        HapticFeedback.heavyImpact();
    }
  }

  void _scheduleDue() {
    final due = _session.nextDue;
    if (due == _scheduled) return;
    _cancelDue?.call();
    _cancelDue = null;
    _scheduled = due;
    if (due == null) return;
    _cancelDue = _clock.schedule(due, (time) {
      _scheduled = null;
      _cancelDue = null;
      if (!mounted) return;
      _clock.input(
        time,
        () => _answer(
          _session.advance(time),
          pointer: _members.keys.firstOrNull,
        ),
      );
    });
  }

  void _writeStates() {
    final states = widget.statesController;
    if (states == null) return;
    var pressed = false;
    var dragged = false;
    for (final interaction in _all) {
      pressed = pressed || interaction.pressed;
      dragged = dragged || interaction.dragged;
    }
    states.update(WidgetState.pressed, pressed);
    states.update(WidgetState.dragged, dragged);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (!_activates ||
        (key != LogicalKeyboardKey.space && key != LogicalKeyboardKey.enter)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _input(ActivateInput(time: _clock.now));
    return KeyEventResult.handled;
  }

  bool get _activates => widget.interactions.any((i) => i.activates);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Semantics(
      label: widget.semanticLabel,
      enabled: enabled,
      onTap: enabled && _activates
          ? () => _input(
              ActivateInput(
                time: _clock.now,
                source: ActivationSource.accessibility,
              ),
            )
          : null,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        canRequestFocus: enabled,
        onKeyEvent: _key,
        onFocusChange: (focused) =>
            widget.statesController?.update(WidgetState.focused, focused),
        child: MouseRegion(
          cursor: widget.mouseCursor ?? MouseCursor.defer,
          onEnter: (event) => _hover(event, inside: true),
          onHover: (event) => _hover(event, inside: true),
          onExit: (event) => _hover(event, inside: false),
          child: _Listener(state: this, child: widget.child),
        ),
      ),
    );
  }

  void _hover(PointerEvent event, {required bool inside}) {
    widget.statesController?.update(WidgetState.hovered, inside);
    _input(
      PointerHoverInput(
        time: _clock.now,
        position: event.localPosition,
        inside: inside,
      ),
    );
  }
}

class _ArenaMember extends GestureArenaMember {
  _ArenaMember(this.state);

  final _InputRegionState state;
  GestureArenaEntry? entry;

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) => state._lost(pointer);
}

class _Listener extends SingleChildRenderObjectWidget {
  const _Listener({required this.state, required super.child});

  final _InputRegionState state;

  @override
  _RenderListener createRenderObject(BuildContext context) {
    final box = _RenderListener(state);
    state._box = box;
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderListener renderObject) {
    renderObject.state = state;
    state._box = renderObject;
  }
}

class _RenderListener extends RenderProxyBox {
  _RenderListener(this.state);

  _InputRegionState state;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    state._pointer(event, size);
  }
}
