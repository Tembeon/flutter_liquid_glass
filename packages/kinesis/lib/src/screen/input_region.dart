import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/input/interaction.dart';

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
/// control inside a scroll view. When a press or a tap is among the
/// interactions, Space, Enter and the accessibility tap activate it. It
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

  @override
  void initState() {
    super.initState();
    widget.statesController?.update(WidgetState.disabled, !widget.enabled);
  }

  @override
  void didUpdateWidget(InputRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.interactions, widget.interactions)) {
      _cancelAll(PointerCancelReason.platform);
      _session = InteractionSession(widget.interactions);
    }
    if (oldWidget.enabled && !widget.enabled) {
      _cancelAll(PointerCancelReason.disabled);
    }
    widget.statesController?.update(WidgetState.disabled, !widget.enabled);
  }

  @override
  void dispose() {
    _cancelAll(PointerCancelReason.platform);
    _cancelDue?.call();
    _ownFocus?.dispose();
    super.dispose();
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
        final member = _ArenaMember(this, event.pointer);
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
    _answer(_session.handle(input));
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
      _answer(_session.advance(time), pointer: _members.keys.firstOrNull);
    });
  }

  void _writeStates() {
    final states = widget.statesController;
    if (states == null) return;
    var pressed = false;
    var dragged = false;
    for (final interaction in _all) {
      if (interaction is PressInteraction && interaction.highlighted) {
        pressed = true;
      }
      if (interaction is DragInteraction && interaction.started) {
        dragged = true;
      }
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

  bool get _activates =>
      _all.any((i) => i is PressInteraction || i is TapInteraction);

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
  _ArenaMember(this.state, this.pointer);

  final _InputRegionState state;
  final int pointer;
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
  _RenderListener createRenderObject(BuildContext context) =>
      _RenderListener(state);

  @override
  void updateRenderObject(BuildContext context, _RenderListener renderObject) {
    renderObject.state = state;
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

/// A widget that activates when pressed, with the states of a UIKit
/// control and no look of its own.
///
/// UIKit: a `UIControl` with a primary action. SwiftUI: `Button` with a
/// plain style. Flutter: `InkWell` without the ink.
class MotionPressable extends StatefulWidget {
  /// Creates a pressable around [child].
  const MotionPressable({
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.haptic,
    this.statesController,
    this.releaseSlop = EdgeInsets.zero,
    super.key,
  });

  /// Called when pressed; null disables it.
  final VoidCallback? onPressed;

  /// Called when held, or null.
  final VoidCallback? onLongPress;

  /// The haptic of a press, or null for none, as a plain `UIButton` plays.
  final MotionHaptic? haptic;

  /// Where the pressable writes its states, or null.
  final WidgetStatesController? statesController;

  /// How far outside the widget a finger still counts as inside.
  final EdgeInsets releaseSlop;

  /// The widget pressed.
  final Widget child;

  @override
  State<MotionPressable> createState() => _MotionPressableState();
}

class _MotionPressableState extends State<MotionPressable> {
  late final PressInteraction _press = PressInteraction(
    onTap: () => widget.onPressed?.call(),
  );
  late final LongPressInteraction _long = LongPressInteraction(
    onStart: () => widget.onLongPress?.call(),
  );

  @override
  Widget build(BuildContext context) {
    _press.releaseSlop = widget.releaseSlop;
    final interactions = widget.onLongPress == null
        ? <Interaction>[_press]
        : <Interaction>[_long, _press];
    return InputRegion(
      interactions: interactions,
      enabled: widget.onPressed != null,
      statesController: widget.statesController,
      feedback: (event) => event is ActivationEvent ? widget.haptic : null,
      child: widget.child,
    );
  }
}

/// Follows a finger dragging over its child, with the release velocity of
/// the lift's own sample and the stamped time of every update.
///
/// UIKit: `UIPanGestureRecognizer`. SwiftUI: `DragGesture`. Flutter:
/// `GestureDetector`'s pan callbacks.
///
/// Updates carry their input's motion time: drive values with
/// `DragInteraction.track` and `DragInteraction.settle`, whose targets
/// apply at that time.
class MotionDragDetector extends StatefulWidget {
  /// Creates a drag detector along [axis], or free when [axis] is null.
  const MotionDragDetector({
    required this.child,
    this.axis,
    this.slop = 10,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
    super.key,
  });

  /// The axis followed, or null for any direction.
  final Axis? axis;

  /// How far the finger travels before the drag starts.
  final double slop;

  /// Called when the drag starts.
  final ValueChanged<DragInteractionDetails>? onStart;

  /// Called on every move of a started drag.
  final ValueChanged<DragInteractionDetails>? onUpdate;

  /// Called on the release of a started drag.
  final ValueChanged<DragInteractionDetails>? onEnd;

  /// Called when a started drag ends without a release.
  final VoidCallback? onCancel;

  /// The widget dragged over.
  final Widget child;

  @override
  State<MotionDragDetector> createState() => _MotionDragDetectorState();
}

class _MotionDragDetectorState extends State<MotionDragDetector> {
  late final DragInteraction _drag = DragInteraction(
    onStart: (details) => widget.onStart?.call(details),
    onUpdate: (details) => widget.onUpdate?.call(details),
    onEnd: (details) => widget.onEnd?.call(details),
    onCancel: () => widget.onCancel?.call(),
  );
  late final List<Interaction> _interactions = [_drag];

  @override
  Widget build(BuildContext context) {
    _drag.axis = widget.axis;
    _drag.slop = widget.slop;
    return InputRegion(interactions: _interactions, child: widget.child);
  }
}
