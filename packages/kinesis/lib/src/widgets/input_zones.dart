import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/input_region.dart';
import 'package:kinesis/src/widgets/input_shared.dart';

/// Where an [InputZone] lies in one frame, as its control reads it from the
/// motion it paints with.
///
/// [InputZones.frameOf] answers one per zone whenever input or
/// accessibility asks: at hit testing, at every pointer event of a touch,
/// for the focus rectangle and the semantics rectangle. Nothing is cached,
/// so a zone is hit where it is painted in the frame the finger lands in.
@immutable
final class InputZoneFrame {
  /// Places a zone at [rect], painted at [opacity], taking input while
  /// [takesInput] holds.
  const InputZoneFrame(this.rect, {this.opacity = 1, this.takesInput = true});

  /// UIKit's hit-testing rule: a view painted with an alpha below 0.01
  /// takes no touch (`UIView.hitTest(_:with:)`).
  ///
  /// It is the one opacity threshold of input: a zone fading in starts to
  /// take input at this opacity, a zone fading out stops. A control that
  /// wants a zone to stop earlier, such as an item that is leaving while
  /// its replacement fades in over it, says so with [takesInput].
  static const double minimumOpacity = 0.01;

  /// The zone's box as painted, in the coordinates of the [InputZones]
  /// host, which are those of its child.
  final Rect rect;

  /// How opaque the zone is painted, from 0 to 1.
  final double opacity;

  /// Whether the control lets the zone take input in this frame: false
  /// for a zone that is leaving, covered or not yet shown.
  final bool takesInput;

  /// Whether the zone is there for input and accessibility in this frame:
  /// it [takesInput], is painted at [minimumOpacity] or more, and has an
  /// area.
  bool get live => takesInput && opacity >= minimumOpacity && !rect.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is InputZoneFrame &&
      other.rect == rect &&
      other.opacity == opacity &&
      other.takesInput == takesInput;

  @override
  int get hashCode => Object.hash(rect, opacity, takesInput);
}

/// One interactive part of a control that paints many parts in one render
/// object: a bar item, an alert action, a segment, a menu row, a day.
///
/// A zone is what a lone `InputRegion` is, without a widget of its own: its
/// [interactions] hear the touches that land on it, in its own
/// coordinates (its rect's top left is the origin), and the keyboard and
/// accessibility commands sent to it; it has a focus node, a mouse cursor,
/// hover, a state set and a semantics node. Its geometry comes from
/// [InputZones.frameOf].
@immutable
class InputZone<T extends Object> {
  /// Describes the zone [id].
  const InputZone({
    required this.id,
    this.interactions = const [],
    this.enabled = true,
    this.mouseCursor,
    this.minimumHitSize,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticValue,
    this.button = false,
    this.selected,
    this.checked,
    this.toggled,
    this.semanticsRole,
    this.describeSemantics,
    this.adjustRange,
  });

  /// What the zone stands for; unique among the host's zones. The host
  /// keeps the zone's focus node, session and states across rebuilds by
  /// this id.
  final T id;

  /// The zone's interactions; when two recognize on one input, the first
  /// wins. Their owner makes them once, one set per zone.
  ///
  /// A press with [InteractionRole.content] lets a gesture around the host
  /// (a row that slides, a selector's drag) take the touch once it moves.
  final List<Interaction> interactions;

  /// Whether the zone takes input. A disabled zone is still hit, so it
  /// keeps a touch from what lies below it, shows its cursor and is read
  /// by accessibility as disabled; disabling it ends its touch.
  final bool enabled;

  /// The cursor over the zone, or null for the default.
  ///
  /// A `WidgetStateMouseCursor` resolves against the zone's states. The
  /// default is `WidgetStateMouseCursor.adaptiveClickable` when an
  /// interaction [Interaction.activates] or [Interaction.adjusts],
  /// `MouseCursor.defer` otherwise, as for `InputRegion.mouseCursor`.
  final MouseCursor? mouseCursor;

  /// The smallest area the zone takes pointers in, centred on its rect, or
  /// null for its rect: a 28 point segment with a 44 by 44 minimum is hit
  /// 8 points above and below it. A zone whose own rect holds the pointer
  /// wins over one whose extension does. The semantics rectangle grows the
  /// same way.
  final Size? minimumHitSize;

  /// Whether the zone takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the zone.
  final String? semanticLabel;

  /// The zone's value for accessibility, such as a day's date. A zone
  /// that adjusts and has a value also says its increased and decreased
  /// values, with [describeSemantics], as Flutter requires.
  final String? semanticValue;

  /// Whether accessibility announces the zone as a button.
  final bool button;

  /// Whether the zone is selected, or null when it has no selected state.
  final bool? selected;

  /// Whether the zone is checked, or null when it has no checked state.
  final bool? checked;

  /// Whether the zone is toggled on, or null when it has no toggled state.
  final bool? toggled;

  /// The zone's role for accessibility, such as `SemanticsRole.tab`, or
  /// null for none.
  final SemanticsRole? semanticsRole;

  /// Adds what the fields above do not say to the zone's semantics, after
  /// the host wrote them; null for nothing.
  final void Function(SemanticsConfiguration config)? describeSemantics;

  /// Which ways the value of a zone that adjusts can move now, or null when
  /// it always can; as `InputRegion.adjustRange`, followed without a
  /// rebuild.
  final ValueListenable<AdjustRange>? adjustRange;
}

/// The states of an [InputZones] host's zones, and its focus.
///
/// UIKit: each control's `state`. Flutter: one `WidgetStatesController`
/// per zone.
///
/// The host writes pressed, dragged, hovered, focused (only while focus
/// should show, as `InputRegion` does) and disabled; the control writes the
/// rest, such as selected, with [update]. It notifies on every change, so a
/// control that paints its zones listens to it and repaints. The host
/// writes disabled without notifying while it builds: the control that
/// gave the zone its `enabled` already knows it.
class InputZonesController<T extends Object> extends ChangeNotifier {
  /// Creates a controller with no states.
  InputZonesController();

  final Map<T, Set<WidgetState>> _states = {};
  _InputZonesState<T>? _host;
  T? _focused;

  /// The states of [zone]; empty for a zone the host does not hold.
  Set<WidgetState> statesOf(T zone) {
    final states = _states[zone];
    return states == null ? const {} : UnmodifiableSetView(states);
  }

  /// Adds [state] to [zone]'s states when [add] is true, removes it
  /// otherwise; notifies when that changes them.
  void update(T zone, WidgetState state, {required bool add}) =>
      _set(zone, state, add: add);

  /// The zone that has the primary focus, or null.
  T? get focusedZone => _focused;

  /// Moves focus to [zone]; false when the host holds no such zone or it
  /// cannot take focus now.
  bool requestFocus(T zone) {
    final state = _host?._zones[zone];
    if (state == null || !state.node.canRequestFocus) return false;
    state.node.requestFocus();
    return true;
  }

  bool _set(
    T zone,
    WidgetState state, {
    required bool add,
    bool notify = true,
  }) {
    final states = _states.putIfAbsent(zone, () => {});
    final changed = add ? states.add(state) : states.remove(state);
    if (changed && notify) notifyListeners();
    return changed;
  }

  void _forget(T zone) => _states.remove(zone);

  void _focus(T zone, {required bool focused}) {
    final now = focused ? zone : (_focused == zone ? null : _focused);
    if (now == _focused) return;
    _focused = now;
    notifyListeners();
  }
}

/// Gives each of the interactive [zones] a control paints inside [child]
/// what an `InputRegion` gives a box: touch, mouse, focus, keys,
/// semantics, states and haptics, while the zones move every frame.
///
/// UIKit: the controls and gesture recognizers of a view's subviews, hit
/// tested where their layers are. Flutter: no equivalent; a widget per
/// part with its own `InputRegion` comes closest, but its box only moves
/// with a relayout.
///
/// For the author of a control whose parts live in one render object that
/// moves them without rebuilding (a bar's items, an alert's actions, a
/// selector's segments, a menu's rows, a calendar's days, a row's swipe
/// buttons). The control names its parts once as [zones] and answers
/// [frameOf] from the same motion it paints with; [frames] notifies when
/// that motion moves, and the host then only refreshes the semantics and
/// focus rectangles: a frame of motion rebuilds no widget and lays out
/// nothing.
///
/// ```dart
/// InputZones<int>(
///   zones: [
///     for (final (i, item) in items.indexed)
///       InputZone(
///         id: i,
///         interactions: presses[i],
///         semanticLabel: item.label,
///         button: true,
///         minimumHitSize: const Size.square(44),
///       ),
///   ],
///   frameOf: (i) => InputZoneFrame(
///     motion.rectOf(i),
///     opacity: motion.alphaOf(i),
///   ),
///   frames: motion,
///   controller: zones,
///   child: CustomPaint(painter: ItemsPainter(motion, zones)),
/// )
/// ```
///
/// Touch: a pointer that lands on a zone (its rect, or its extension to
/// [InputZone.minimumHitSize]) goes to that zone's interactions, mapped
/// into the zone's coordinates with the zone's rect at each event, so a
/// finger that rests on a moving zone stays inside it. Touches join the
/// gesture arena as an `InputRegion`'s do. With [slides], a finger that
/// moves onto another zone moves the touch there: the zone it leaves gets
/// a cancel, the zone it enters a down at the finger, and [feedback] hears
/// a `ScrubChangeEvent` with the new zone; the touch then ends where the
/// finger lifts. This is how an alert's actions, a menu's rows and a tab
/// bar's items are scrubbed. With a [port], touches handed on from another
/// region arrive the same way, also onto no zone at first.
///
/// Mouse: each zone has its own cursor and hovered state, and hears hover
/// as `PointerHoverInput`s; a zone that moves under a resting mouse is
/// entered and left with the next frame. The secondary button and the
/// scroll wheel reach a zone's interactions that take them.
///
/// Focus: each zone has a focus node, made and disposed with the zone. Tab
/// visits the zones in the order of [zones] (other focusable widgets
/// inside [child] come after them), skipping zones that take no key (no
/// interaction activates or adjusts) or no input now. The arrows move
/// between zones: along [axis] in the order of [zones], mirrored in
/// right-to-left for a horizontal axis, or to the nearest zone on screen
/// when [axis] is null; Home and End reach the first and the last zone.
/// An arrow with no zone in its direction (past the last one, or across
/// [axis]) asks [onEdge], then moves focus as Flutter's directional focus
/// does, which may leave the host. A zone whose interaction
/// adjusts keeps the arrows, Home and End for its value
/// (`AdjustValueIntent.defaultShortcuts`). Space and Enter activate the
/// focused zone through `ActivateIntent`, which an app overrides with
/// `Actions` above the host, as for `InputRegion`.
///
/// Semantics: each zone that is [InputZoneFrame.live] is one semantics
/// node over its hit rectangle, which follows [frameOf], with its label,
/// value, flags, enabled state, tap, increase and decrease, and focus. The
/// semantics of [child] are dropped unless [excludeChildSemantics] is
/// false, since the zones describe what the child paints.
///
/// A zone that is disabled takes nothing; a zone whose frame is null or
/// not [InputZoneFrame.live] is not hit, not focusable and not in the
/// semantics tree.
class InputZones<T extends Object> extends StatefulWidget {
  /// Hosts [zones] over [child].
  const InputZones({
    required this.zones,
    required this.frameOf,
    required this.frames,
    required this.child,
    this.controller,
    this.axis = Axis.horizontal,
    this.slides = false,
    this.feedback,
    this.onEdge,
    this.port,
    this.excludeChildSemantics = true,
    super.key,
  });

  /// The zones, in their reading order.
  final List<InputZone<T>> zones;

  /// Where a zone lies now, in the host's coordinates, or null when it is
  /// not shown. Read at hit testing, for every pointer event, and for the
  /// focus and semantics rectangles.
  final InputZoneFrame? Function(T zone) frameOf;

  /// Notifies when what [frameOf] answers changes: the motion the control
  /// paints with.
  final Listenable frames;

  /// What paints the zones.
  final Widget child;

  /// Where the host writes the zones' states and keeps their focus, or
  /// null for one of its own.
  final InputZonesController<T>? controller;

  /// The axis the arrows move along in the order of [zones], or null to
  /// move to the nearest zone on screen in the arrow's direction (a grid).
  final Axis? axis;

  /// Whether a finger moves its touch onto the zone it slides onto.
  final bool slides;

  /// The haptic for an event of a zone, or null for none.
  ///
  /// As `InputRegion.feedback`: played as the event happens, never for a
  /// keyboard or accessibility activation, and not below a
  /// `MotionHapticScope` that turns haptics off.
  final MotionHaptic? Function(T zone, InteractionEvent event)? feedback;

  /// Called when an arrow finds no zone in its direction, with the focused
  /// zone; true when the control handled it (a calendar turning its
  /// month), false to let Flutter's directional focus move on.
  final bool Function(T zone, TraversalDirection direction)? onEdge;

  /// Where touches handed on from another region arrive, or null.
  final InputPort? port;

  /// Whether the semantics of [child] are dropped, leaving the zones'.
  final bool excludeChildSemantics;

  @override
  State<InputZones<T>> createState() => _InputZonesState<T>();
}

class _InputZonesState<T extends Object> extends State<InputZones<T>> {
  InputZonesController<T>? _ownController;
  final Map<T, _ZoneState<T>> _zones = {};
  _RenderZones<T>? _box;
  final Map<int, PointerDownInput> _downs = {};
  final Map<int, T> _owners = {};
  final Map<int, VelocityTracker> _trackers = {};
  final Map<int, InputArenaMember> _members = {};
  final PointerSpeed _speed = PointerSpeed();
  late final FocusTraversalPolicy _policy = OrderedTraversalPolicy();
  double? _scheduled;
  VoidCallback? _cancelDue;
  NavigationMode? _navigation;

  InputZonesController<T> get controller =>
      widget.controller ?? (_ownController ??= InputZonesController<T>());

  MotionClock get _clock => MotionClock.instance;

  @override
  void initState() {
    super.initState();
    controller._host = this;
    widget.frames.addListener(_framesChanged);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    _attachPort(widget.port);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = MediaQuery.maybeNavigationModeOf(context);
    if (navigation == _navigation) return;
    _navigation = navigation;
    for (final zone in _zones.values) {
      zone._showFocus(notify: false);
    }
  }

  @override
  void didUpdateWidget(InputZones<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames) {
      oldWidget.frames.removeListener(_framesChanged);
      widget.frames.addListener(_framesChanged);
    }
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller ?? _ownController;
      if (old?._host == this) old?._host = null;
      if (widget.controller != null) {
        _ownController?.dispose();
        _ownController = null;
      }
      controller._host = this;
      for (final zone in _zones.values) {
        zone._writeAll();
      }
    }
    if (oldWidget.port != widget.port) {
      oldWidget.port?.detach(_receive);
      _attachPort(widget.port);
    }
    assert(
      widget.zones.map((zone) => zone.id).toSet().length == widget.zones.length,
      'Every zone of an InputZones has its own id.',
    );
  }

  @override
  void dispose() {
    widget.port?.detach(_receive);
    widget.frames.removeListener(_framesChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _cancelDue?.call();
    if (controller._host == this) controller._host = null;
    _ownController?.dispose();
    super.dispose();
  }

  void _framesChanged() {
    for (final zone in _zones.values) {
      zone._syncNode();
      zone._anchor?.markNeedsSemanticsUpdate();
    }
    _box?.markNeedsSemanticsUpdate();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    for (final zone in _zones.values) {
      zone._showFocus();
    }
  }

  /// The zone at [position]: the last zone in [InputZones.zones] whose
  /// rect holds it, else the last whose hit extension does. Disabled zones
  /// count, so they keep a touch from what lies below.
  _ZoneState<T>? _zoneAt(Offset position) {
    _ZoneState<T>? extended;
    for (final zone in widget.zones.reversed) {
      final state = _zones[zone.id];
      final frame = widget.frameOf(zone.id);
      if (state == null || frame == null || !frame.live) continue;
      if (frame.rect.contains(position)) return state;
      if (extended == null &&
          _hitRect(frame.rect, zone.minimumHitSize).contains(position)) {
        extended = state;
      }
    }
    return extended;
  }

  static Rect _hitRect(Rect rect, Size? minimum) => minimum == null
      ? rect
      : Rect.fromCenter(
          center: rect.center,
          width: math.max(rect.width, minimum.width),
          height: math.max(rect.height, minimum.height),
        );

  void _attachPort(InputPort? port) => attachPortAfterFrame(
    port,
    _receive,
    () => mounted && widget.port == port,
  );

  void _receive(PortEvent event) {
    final box = _box;
    if (box == null || !box.hasSize) return;
    final input = event.input(
      box.globalToLocal,
      size: box.size,
      scrollAxes: event.handOff ? scrollAxesAround(context) : const {},
    );
    _clock.input(input.time, () => _route(input, arena: false));
  }

  void _pointer(PointerEvent event) {
    switch (event) {
      case PointerScrollEvent():
        _wheel(event);
      case PointerHoverEvent():
        final zone = _zoneAt(event.localPosition);
        if (zone != null && zone.takesInput) {
          zone._input(
            PointerHoverInput(
              time: _clock.now,
              position: event.localPosition,
              inside: true,
            ),
          );
        }
      case PointerDownEvent():
      case _ when _downs.containsKey(event.pointer):
        final time = _clock.stamp(event.timeStamp);
        _clock.input(time, () => _dispatch(event, time));
      default:
        break;
    }
  }

  void _wheel(PointerScrollEvent event) {
    final zone = _zoneAt(event.localPosition);
    if (zone == null ||
        !zone.takesInput ||
        !zone.zone.interactions.any((i) => i.takesWheel)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!mounted || !zone.mounted || event is! PointerScrollEvent) return;
      final time = _clock.stamp(event.timeStamp);
      zone._input(
        PointerScrollInput(
          time: time,
          position: event.localPosition,
          scrollDelta: event.scrollDelta,
          kind: event.kind,
        ),
      );
    });
  }

  void _dispatch(PointerEvent event, double time) {
    final box = _box;
    if (box == null || !box.hasSize) return;
    switch (event) {
      case PointerDownEvent():
        _speed.touched(event.timeStamp);
        _route(
          PointerDownInput(
            time: time,
            pointer: event.pointer,
            position: event.localPosition,
            regionSize: box.size,
            kind: event.kind,
            buttons: event.buttons,
            scrollAxes: scrollAxesAround(context),
          ),
          arena: true,
        );
        if (_downs.containsKey(event.pointer)) {
          final tracker = VelocityTracker.withKind(event.kind);
          tracker.addPosition(event.timeStamp, event.localPosition);
          _trackers[event.pointer] = tracker;
        }
      case PointerMoveEvent():
        _trackers[event.pointer]?.addPosition(
          event.timeStamp,
          event.localPosition,
        );
        _speed.moved(event, View.of(context).devicePixelRatio);
        _route(
          PointerMoveInput(
            time: time,
            pointer: event.pointer,
            position: event.localPosition,
          ),
          arena: true,
        );
      case PointerUpEvent():
        _speed.lifted();
        final tracker = _trackers.remove(event.pointer);
        tracker?.addPosition(event.timeStamp, event.localPosition);
        _route(
          PointerUpInput(
            time: time,
            pointer: event.pointer,
            position: event.localPosition,
            velocity: tracker?.getVelocity().pixelsPerSecond ?? Offset.zero,
          ),
          arena: true,
        );
        _members.remove(event.pointer);
      case PointerCancelEvent():
        _trackers.remove(event.pointer);
        _route(
          PointerCancelInput(
            time: time,
            pointer: event.pointer,
            reason: PointerCancelReason.platform,
          ),
          arena: true,
        );
        _members.remove(event.pointer);
      default:
        break;
    }
  }

  /// Routes a pointer input in the host's coordinates to the zone that
  /// owns its touch.
  void _route(InteractionInput input, {required bool arena}) {
    switch (input) {
      case PointerDownInput():
        _down(input, arena: arena);
      case PointerMoveInput():
        _move(input);
      case PointerUpInput(:final pointer) || PointerCancelInput(:final pointer):
        if (_downs.remove(pointer) == null) return;
        final zone = _zones[_owners.remove(pointer)];
        if (zone == null) return;
        _answer(
          zone,
          zone.session.handle(zone._local(input)),
          pointer: pointer,
        );
      case PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput():
        break;
    }
  }

  void _down(PointerDownInput down, {required bool arena}) {
    if (_downs.containsKey(down.pointer)) return;
    final zone = _zoneAt(down.position);
    final output = zone != null && zone.takesInput
        ? zone.session.handle(zone._local(down))
        : null;
    final accepted = output != null && !output.reject;
    if (!accepted && !widget.slides) {
      if (zone != null && output != null) _answer(zone, output);
      return;
    }
    _downs[down.pointer] = down;
    if (arena) {
      final member = InputArenaMember(_lost);
      _members[down.pointer] = member;
      member.entry = GestureBinding.instance.gestureArena.add(
        down.pointer,
        member,
      );
    }
    if (zone == null || output == null) return;
    if (!accepted) {
      _answer(zone, output);
      return;
    }
    _owners[down.pointer] = zone.id;
    _answer(
      zone,
      output,
      pointer: down.pointer,
      extra: [
        if (widget.slides)
          ScrubChangeEvent(time: down.time, selected: zone.id, atDown: true),
      ],
    );
  }

  void _move(PointerMoveInput move) {
    final down = _downs[move.pointer];
    if (down == null) return;
    final zone = _zones[_owners[move.pointer]];
    if (widget.slides) {
      final under = _zoneAt(move.position);
      if (under != null && under != zone && under.takesInput) {
        _handOver(move, down, from: zone, to: under);
        return;
      }
    }
    if (zone == null) return;
    _answer(
      zone,
      zone.session.handle(zone._local(move)),
      pointer: move.pointer,
    );
  }

  void _handOver(
    PointerMoveInput move,
    PointerDownInput down, {
    required _ZoneState<T>? from,
    required _ZoneState<T> to,
  }) {
    final pointer = move.pointer;
    _owners.remove(pointer);
    if (from != null) {
      _answer(
        from,
        from.session.handle(
          PointerCancelInput(
            time: move.time,
            pointer: pointer,
            reason: PointerCancelReason.taken,
          ),
        ),
      );
    }
    final output = to.session.handle(
      to._local(
        PointerDownInput(
          time: move.time,
          pointer: pointer,
          position: move.position,
          regionSize: down.regionSize,
          contactTime: down.contactTime,
          kind: down.kind,
          buttons: down.buttons,
          scrollAxes: down.scrollAxes,
        ),
      ),
    );
    if (output.reject) {
      _answer(to, output);
      return;
    }
    _owners[pointer] = to.id;
    _answer(
      to,
      output,
      pointer: pointer,
      extra: [ScrubChangeEvent(time: move.time, selected: to.id)],
    );
  }

  void _lost(int pointer) {
    if (_members.remove(pointer) == null) return;
    _trackers.remove(pointer);
    _downs.remove(pointer);
    final zone = _zones[_owners.remove(pointer)];
    if (zone == null) return;
    _answer(zone, zone.session.lost(pointer, _clock.now));
  }

  /// Ends the touches [zone] owns, for [reason].
  void _cancelTouches(_ZoneState<T> zone, PointerCancelReason reason) {
    for (final MapEntry(key: pointer, value: id) in _owners.entries.toList()) {
      if (id != zone.id) continue;
      _owners.remove(pointer);
      _answer(
        zone,
        zone.session.handle(
          PointerCancelInput(
            time: _clock.now,
            pointer: pointer,
            reason: reason,
          ),
        ),
      );
      if (!widget.slides) {
        _downs.remove(pointer);
        _trackers.remove(pointer);
        _members.remove(pointer)?.entry?.resolve(GestureDisposition.rejected);
      }
    }
  }

  void _answer(
    _ZoneState<T> zone,
    SessionOutput output, {
    int? pointer,
    List<InteractionEvent> extra = const [],
  }) {
    if (pointer != null) {
      final entry = _members[pointer]?.entry;
      if (output.claim) entry?.resolve(GestureDisposition.accepted);
      if (output.reject && !widget.slides) {
        entry?.resolve(GestureDisposition.rejected);
      }
    }
    for (final event in [...extra, ...output.events]) {
      _play(zone.id, event);
    }
    if (zone.mounted) zone._writeStates();
    _scheduleDue();
  }

  void _play(T zone, InteractionEvent event) {
    if (event is ActivationEvent && event.source != ActivationSource.pointer) {
      return;
    }
    if (!mounted) return;
    final haptic = widget.feedback?.call(zone, event);
    if (haptic != null) playHaptic(context, haptic);
  }

  void _scheduleDue() {
    double? due;
    for (final zone in _zones.values) {
      final at = zone.session.nextDue;
      if (at != null && (due == null || at < due)) due = at;
    }
    if (due == _scheduled) return;
    _cancelDue?.call();
    _cancelDue = null;
    _scheduled = due;
    if (due == null) return;
    _cancelDue = _clock.schedule(due, (time) {
      _scheduled = null;
      _cancelDue = null;
      if (!mounted) return;
      _clock.input(time, () {
        for (final zone in _zones.values.toList()) {
          final at = zone.session.nextDue;
          if (at == null || at > time) continue;
          final owned = _owners.entries
              .where((entry) => entry.value == zone.id)
              .firstOrNull;
          _answer(zone, zone.session.advance(time), pointer: owned?.key);
        }
      });
    });
  }

  bool _traversable(_ZoneState<T> zone) =>
      zone.node.canRequestFocus && !zone.node.skipTraversal;

  void _moveFocus(_ZoneState<T> from, TraversalDirection direction) {
    final next = widget.axis == null
        ? _nearest(from, direction)
        : _along(from, direction, widget.axis!);
    if (next != null) {
      next.node.requestFocus();
      return;
    }
    if (widget.onEdge?.call(from.id, direction) ?? false) return;
    from.node.focusInDirection(direction);
  }

  _ZoneState<T>? _along(
    _ZoneState<T> from,
    TraversalDirection direction,
    Axis axis,
  ) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final step = switch ((axis, direction)) {
      (Axis.horizontal, TraversalDirection.right) => rtl ? -1 : 1,
      (Axis.horizontal, TraversalDirection.left) => rtl ? 1 : -1,
      (Axis.vertical, TraversalDirection.down) => 1,
      (Axis.vertical, TraversalDirection.up) => -1,
      _ => 0,
    };
    if (step == 0) return null;
    final zones = widget.zones;
    final start = zones.indexWhere((zone) => zone.id == from.id);
    if (start < 0) return null;
    for (var i = start + step; i >= 0 && i < zones.length; i += step) {
      final zone = _zones[zones[i].id];
      if (zone != null && _traversable(zone)) return zone;
    }
    return null;
  }

  _ZoneState<T>? _nearest(_ZoneState<T> from, TraversalDirection direction) {
    final origin = from.frame?.rect.center;
    if (origin == null) return null;
    _ZoneState<T>? best;
    var bestScore = double.infinity;
    for (final zone in _zones.values) {
      if (identical(zone, from) || !_traversable(zone)) continue;
      final rect = zone.frame?.rect;
      if (rect == null) continue;
      final d = rect.center - origin;
      final (along, across) = switch (direction) {
        TraversalDirection.up => (-d.dy, d.dx.abs()),
        TraversalDirection.down => (d.dy, d.dx.abs()),
        TraversalDirection.left => (-d.dx, d.dy.abs()),
        TraversalDirection.right => (d.dx, d.dy.abs()),
      };
      if (along <= precisionErrorTolerance) continue;
      final score = along + 2 * across;
      if (score < bestScore) {
        best = zone;
        bestScore = score;
      }
    }
    return best;
  }

  void _toEnd(_ZoneState<T> from, {required bool last}) {
    final order = [
      for (final zone in widget.zones)
        if (_zones[zone.id] case final state? when _traversable(state)) state,
    ];
    final target = last ? order.lastOrNull : order.firstOrNull;
    if (target != null && !identical(target, from)) target.node.requestFocus();
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: _policy,
    child: _ZonesHost<T>(
      state: this,
      excludeChildSemantics: widget.excludeChildSemantics,
      children: [
        widget.child,
        for (final (order, zone) in widget.zones.indexed)
          _Zone<T>(
            key: _ZoneKey<T>(zone.id),
            host: this,
            zone: zone,
            order: order,
          ),
      ],
    ),
  );
}

class _ZoneKey<T extends Object> extends ValueKey<T> {
  const _ZoneKey(super.value);
}

class _Zone<T extends Object> extends StatefulWidget {
  const _Zone({
    required this.host,
    required this.zone,
    required this.order,
    super.key,
  });

  final _InputZonesState<T> host;
  final InputZone<T> zone;
  final int order;

  @override
  State<_Zone<T>> createState() => _ZoneState<T>();
}

/// One zone's session, focus node, hit target and semantics anchor.
class _ZoneState<T extends Object> extends State<_Zone<T>> {
  late InteractionSession session = InteractionSession(zone.interactions);
  final FocusNode node = FocusNode();
  late final _ZoneTarget<T> target = _ZoneTarget<T>(this);
  _RenderZoneAnchor<T>? _anchor;
  Map<Type, Action<Intent>>? _actions;
  Offset _origin = Offset.zero;
  Size _size = Size.zero;
  bool _hasFocus = false;
  bool _hovering = false;

  InputZone<T> get zone => widget.zone;

  T get id => zone.id;

  _InputZonesState<T> get host => widget.host;

  InputZonesController<T> get _controller => host.controller;

  InputZoneFrame? get frame => host.widget.frameOf(id);

  /// Whether the zone is there for input and accessibility now.
  bool get present => frame?.live ?? false;

  /// Whether the zone takes input now.
  bool get takesInput => zone.enabled && present;

  bool get _activates => zone.interactions.any((i) => i.activates);

  bool get _adjusts => zone.interactions.any((i) => i.adjusts);

  AdjustRange get _range => zone.adjustRange?.value ?? AdjustRange.open;

  void _rangeChanged() => _anchor?.markNeedsSemanticsUpdate();

  MouseCursor get cursor => resolveCursor(
    zone.mouseCursor,
    clickable: _activates || _adjusts,
    states: _controller.statesOf(id),
  );

  @override
  void initState() {
    super.initState();
    node.debugLabel = 'InputZone $id';
    host._zones[id] = this;
    _bind();
    _writeAll();
    _syncNode();
    zone.adjustRange?.addListener(_rangeChanged);
  }

  @override
  void didUpdateWidget(_Zone<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.zone;
    if (!listEquals(old.interactions, zone.interactions)) {
      host._cancelTouches(this, PointerCancelReason.platform);
      session = InteractionSession(zone.interactions);
      _bind();
    }
    if (old.enabled && !zone.enabled) {
      host._cancelTouches(this, PointerCancelReason.disabled);
    }
    if (old.adjustRange != zone.adjustRange) {
      old.adjustRange?.removeListener(_rangeChanged);
      zone.adjustRange?.addListener(_rangeChanged);
    }
    _writeAll();
    _syncNode();
    _anchor?.markNeedsSemanticsUpdate();
  }

  @override
  void dispose() {
    zone.adjustRange?.removeListener(_rangeChanged);
    host._cancelTouches(this, PointerCancelReason.platform);
    if (identical(host._zones[id], this)) host._zones.remove(id);
    _controller._forget(id);
    if (_hasFocus) _controller._focus(id, focused: false);
    node.dispose();
    super.dispose();
  }

  void _bind() {
    for (final interaction in zone.interactions) {
      interaction.bindRegion(
        (local) => host._box?.localToGlobal(local + _origin) ?? local,
      );
    }
  }

  /// Writes what the zone's widget says: disabled, without notifying.
  void _writeAll() {
    _controller._set(
      id,
      WidgetState.disabled,
      add: !zone.enabled,
      notify: false,
    );
    _showFocus(notify: false);
  }

  void _syncNode() {
    node.canRequestFocus = takesInput;
    node.skipTraversal = !_activates && !_adjusts;
  }

  void _set(WidgetState state, {required bool add, bool notify = true}) {
    final before = _hovering ? cursor : null;
    _controller._set(id, state, add: add, notify: notify);
    if (_hovering && cursor != before) {
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _showFocus({bool notify = true}) => _set(
    WidgetState.focused,
    add: focusShows(
      hasFocus: _hasFocus,
      enabled: zone.enabled,
      navigation: host._navigation,
    ),
    notify: notify,
  );

  void _focusChanged(bool focused) {
    _hasFocus = focused;
    _showFocus();
    _controller._focus(id, focused: focused);
    _anchor?.markNeedsSemanticsUpdate();
  }

  void _writeStates() {
    var pressed = false;
    var dragged = false;
    for (final interaction in zone.interactions) {
      pressed = pressed || interaction.pressed;
      dragged = dragged || interaction.dragged;
    }
    _set(WidgetState.pressed, add: pressed);
    _set(WidgetState.dragged, add: dragged);
  }

  /// [input], given in the host's coordinates, in the zone's: its rect's
  /// top left is the origin, read at this input.
  InteractionInput _local(InteractionInput input) {
    if (frame case final frame?) {
      _origin = frame.rect.topLeft;
      _size = frame.rect.size;
    }
    final origin = _origin;
    return switch (input) {
      PointerDownInput() => PointerDownInput(
        time: input.time,
        pointer: input.pointer,
        position: input.position - origin,
        regionSize: _size,
        contactTime: input.contactTime,
        hitArea: _InputZonesState._hitRect(
          origin & _size,
          zone.minimumHitSize,
        ).shift(-origin),
        kind: input.kind,
        buttons: input.buttons,
        scrollAxes: input.scrollAxes,
      ),
      PointerMoveInput() => PointerMoveInput(
        time: input.time,
        pointer: input.pointer,
        position: input.position - origin,
      ),
      PointerUpInput() => PointerUpInput(
        time: input.time,
        pointer: input.pointer,
        position: input.position - origin,
        velocity: input.velocity,
      ),
      PointerHoverInput() => PointerHoverInput(
        time: input.time,
        position: input.position - origin,
        inside: input.inside,
      ),
      PointerScrollInput() => PointerScrollInput(
        time: input.time,
        position: input.position - origin,
        scrollDelta: input.scrollDelta,
        kind: input.kind,
      ),
      PointerCancelInput() || ActivateInput() || AdjustInput() => input,
    };
  }

  /// Hands [input], in the host's coordinates, to the zone's session.
  void _input(InteractionInput input) {
    if (!zone.enabled) return;
    dispatchInput(
      input,
      () => host._clock.input(
        input.time,
        () => host._answer(this, session.handle(_local(input))),
      ),
    );
  }

  void _entered(PointerEnterEvent event) {
    _hovering = true;
    _set(WidgetState.hovered, add: true);
    _input(
      PointerHoverInput(
        time: host._clock.now,
        position: event.localPosition,
        inside: true,
      ),
    );
  }

  void _exited(PointerExitEvent event) {
    _hovering = false;
    if (!mounted) return;
    _set(WidgetState.hovered, add: false);
    _input(
      PointerHoverInput(
        time: host._clock.now,
        position: event.localPosition,
        inside: false,
      ),
    );
  }

  void _activate(ActivationSource source) =>
      _input(ActivateInput(time: host._clock.now, source: source));

  void _adjust(ValueCommand command, ActivationSource source) => _input(
    AdjustInput(time: host._clock.now, command: command, source: source),
  );

  void describe(SemanticsConfiguration config) {
    config.isSemanticBoundary = true;
    final zone = this.zone;
    final direction = Directionality.maybeOf(context);
    if (zone.semanticLabel case final label?) {
      config.label = label;
      config.textDirection = direction;
    }
    if (zone.semanticValue case final value?) {
      config.value = value;
      config.textDirection = direction;
    }
    config.isEnabled = zone.enabled;
    if (zone.button) config.isButton = true;
    if (zone.selected case final selected?) config.isSelected = selected;
    if (zone.checked case final checked?) config.isChecked = checked;
    if (zone.toggled case final toggled?) config.isToggled = toggled;
    if (zone.semanticsRole case final role?) config.role = role;
    if (node.canRequestFocus) {
      config.isFocused = node.hasPrimaryFocus;
      config.onFocus = node.requestFocus;
    }
    if (zone.enabled && _activates) {
      config.onTap = () => _activate(ActivationSource.accessibility);
    }
    if (zone.enabled && _adjusts) {
      final range = _range;
      if (range.canIncrease) {
        config.onIncrease = () =>
            _adjust(ValueCommand.increase, ActivationSource.accessibility);
      }
      if (range.canDecrease) {
        config.onDecrease = () =>
            _adjust(ValueCommand.decrease, ActivationSource.accessibility);
      }
    }
    zone.describeSemantics?.call(config);
  }

  /// The zone's hit rectangle now, in the host's coordinates.
  Rect get bounds {
    final frame = this.frame;
    if (frame == null) return Rect.zero;
    return _InputZonesState._hitRect(frame.rect, zone.minimumHitSize);
  }

  static const Map<ShortcutActivator, Intent> _moves = {
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
      TraversalDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
      TraversalDirection.right,
    ),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
      TraversalDirection.up,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
      TraversalDirection.down,
    ),
    SingleActivator(LogicalKeyboardKey.home): _ZoneEndIntent(last: false),
    SingleActivator(LogicalKeyboardKey.end): _ZoneEndIntent(last: true),
  };

  @override
  Widget build(BuildContext context) {
    _actions ??= {
      ActivateIntent: Action<ActivateIntent>.overridable(
        defaultAction: _ZoneActivate<ActivateIntent, T>(this),
        context: context,
      ),
      ButtonActivateIntent: Action<ButtonActivateIntent>.overridable(
        defaultAction: _ZoneActivate<ButtonActivateIntent, T>(this),
        context: context,
      ),
      AdjustValueIntent: Action<AdjustValueIntent>.overridable(
        defaultAction: _ZoneAdjust<T>(this),
        context: context,
      ),
      DirectionalFocusIntent: _ZoneMove<T>(this),
      _ZoneEndIntent: _ZoneEnd<T>(this),
    };
    return Actions(
      actions: _actions!,
      child: Shortcuts(
        includeSemantics: false,
        shortcuts: _adjusts
            ? {
                ..._moves,
                ...AdjustValueIntent.defaultShortcuts(
                  Directionality.maybeOf(context) ?? TextDirection.ltr,
                  host._navigation ?? NavigationMode.traditional,
                ),
              }
            : _moves,
        child: FocusTraversalOrder(
          order: NumericFocusOrder(widget.order.toDouble()),
          child: Focus(
            focusNode: node,
            autofocus: zone.autofocus,
            includeSemantics: false,
            onFocusChange: _focusChanged,
            child: _ZoneAnchor<T>(state: this),
          ),
        ),
      ),
    );
  }
}

/// Moves focus to the first or the last zone: Home and End.
class _ZoneEndIntent extends Intent {
  const _ZoneEndIntent({required this.last});

  final bool last;
}

class _ZoneActivate<I extends Intent, T extends Object> extends Action<I> {
  _ZoneActivate(this.zone);

  final _ZoneState<T> zone;

  @override
  bool isEnabled(I intent) => zone.zone.enabled && zone._activates;

  @override
  Object? invoke(I intent) {
    zone._activate(ActivationSource.keyboard);
    return null;
  }
}

class _ZoneAdjust<T extends Object> extends Action<AdjustValueIntent> {
  _ZoneAdjust(this.zone);

  final _ZoneState<T> zone;

  @override
  bool isEnabled(AdjustValueIntent intent) =>
      zone.zone.enabled && zone._adjusts && zone._range.allows(intent.command);

  @override
  Object? invoke(AdjustValueIntent intent) {
    zone._adjust(intent.command, ActivationSource.keyboard);
    return null;
  }
}

class _ZoneMove<T extends Object> extends Action<DirectionalFocusIntent> {
  _ZoneMove(this.zone);

  final _ZoneState<T> zone;

  @override
  Object? invoke(DirectionalFocusIntent intent) {
    zone.host._moveFocus(zone, intent.direction);
    return null;
  }
}

class _ZoneEnd<T extends Object> extends Action<_ZoneEndIntent> {
  _ZoneEnd(this.zone);

  final _ZoneState<T> zone;

  @override
  Object? invoke(_ZoneEndIntent intent) {
    zone.host._toEnd(zone, last: intent.last);
    return null;
  }
}

/// What a pointer hits on a zone: it routes the pointer's events to the
/// host and is the zone's cursor and hover for the mouse tracker.
final class _ZoneTarget<T extends Object>
    with Diagnosticable
    implements HitTestTarget, MouseTrackerAnnotation {
  _ZoneTarget(this.zone);

  final _ZoneState<T> zone;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (zone.mounted) zone.host._pointer(event);
  }

  @override
  MouseCursor get cursor => zone.mounted ? zone.cursor : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => zone._entered;

  @override
  PointerExitEventListener? get onExit => zone._exited;

  @override
  bool get validForMouseTracker => zone.mounted;
}

class _ZonesHost<T extends Object> extends MultiChildRenderObjectWidget {
  const _ZonesHost({
    required this.state,
    required this.excludeChildSemantics,
    required super.children,
  });

  final _InputZonesState<T> state;
  final bool excludeChildSemantics;

  @override
  _RenderZones<T> createRenderObject(BuildContext context) {
    final box = _RenderZones<T>(
      state,
      excludeChildSemantics: excludeChildSemantics,
    );
    state._box = box;
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderZones<T> renderObject) {
    renderObject.state = state;
    renderObject.excludeChildSemantics = excludeChildSemantics;
    state._box = renderObject;
    renderObject.markNeedsSemanticsUpdate();
  }
}

/// The host's box: the size of its first child, which it paints; the
/// zones' anchors after it take no room and paint nothing.
class _RenderZones<T extends Object> extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ZoneParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ZoneParentData> {
  _RenderZones(this.state, {required this._excludeChildSemantics});

  _InputZonesState<T> state;

  bool _excludeChildSemantics;
  bool get excludeChildSemantics => _excludeChildSemantics;
  set excludeChildSemantics(bool value) {
    if (value == _excludeChildSemantics) return;
    _excludeChildSemantics = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ZoneParentData) {
      child.parentData = _ZoneParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      firstChild?.getDistanceToActualBaseline(baseline);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      firstChild?.getDryLayout(constraints) ?? constraints.smallest;

  @override
  void performLayout() {
    final content = firstChild;
    if (content == null) {
      size = constraints.smallest;
      return;
    }
    content.layout(constraints, parentUsesSize: true);
    size = content.size;
    var anchor = childAfter(content);
    while (anchor != null) {
      anchor.layout(const BoxConstraints.tightFor(width: 0, height: 0));
      anchor = childAfter(anchor);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild case final content?) context.paintChild(content, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final content = firstChild;
    final zone = state._zoneAt(position);
    if (zone == null) {
      if (content == null || !size.contains(position)) return false;
      return content.hitTest(result, position: position);
    }
    content?.hitTest(result, position: position);
    result.add(HitTestEntry(zone.target));
    return true;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    if (child == null) return;
    if (!_excludeChildSemantics) visitor(child);
    child = childAfter(child);
    while (child != null) {
      if (child is! _RenderZoneAnchor<T> || child.zone.present) visitor(child);
      child = childAfter(child);
    }
  }
}

class _ZoneParentData extends ContainerBoxParentData<RenderBox> {}

class _ZoneAnchor<T extends Object> extends LeafRenderObjectWidget {
  const _ZoneAnchor({required this.state});

  final _ZoneState<T> state;

  @override
  _RenderZoneAnchor<T> createRenderObject(BuildContext context) {
    final anchor = _RenderZoneAnchor<T>(state);
    state._anchor = anchor;
    return anchor;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderZoneAnchor<T> renderObject,
  ) {
    renderObject.zone = state;
    state._anchor = renderObject;
    renderObject.markNeedsSemanticsUpdate();
  }
}

/// A zone's place in the render tree: an empty box at the host's origin
/// whose bounds are the zone's hit rectangle, read when focus or semantics
/// ask, and which describes the zone to accessibility.
class _RenderZoneAnchor<T extends Object> extends RenderBox {
  _RenderZoneAnchor(this.zone);

  _ZoneState<T> zone;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  Rect get paintBounds => zone.bounds;

  @override
  Rect get semanticBounds => zone.bounds;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    zone.describe(config);
  }
}
