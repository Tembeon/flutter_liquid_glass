import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/haptics.dart';
import 'package:kinesis/src/widgets/input_intents.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/input_target.dart';
import 'package:kinesis/src/widgets/source.dart';

/// Where an [InputZone] lies in one frame, as its control reads it from the
/// motion it paints with.
///
/// [InputZones.frameOf] answers one per zone whenever input or
/// accessibility asks: at hit testing, at every pointer event of a touch,
/// for the focus rectangle and the semantics rectangle. Nothing is cached,
/// so a zone is hit where it is painted in the frame the finger lands in.
@immutable
final class InputZoneFrame {
  /// Places a zone at [rect] with [radius] corners, painted at [opacity],
  /// taking input while [takesInput] holds.
  const InputZoneFrame(
    this.rect, {
    this.opacity = 1,
    this.takesInput = true,
    this.radius = BorderRadius.zero,
  });

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

  /// The corners of the zone as painted: the shape a presentation that
  /// grows out of the zone starts from.
  final BorderRadius radius;

  /// Whether the zone is there for input and accessibility in this frame:
  /// it [takesInput], is painted at [minimumOpacity] or more, and has an
  /// area.
  bool get live => takesInput && opacity >= minimumOpacity && !rect.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is InputZoneFrame &&
      other.rect == rect &&
      other.opacity == opacity &&
      other.takesInput == takesInput &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(rect, opacity, takesInput, radius);
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
    this.focusable = true,
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

  /// Whether the zone is a focus target of its own.
  ///
  /// A zone that is not takes touch, mouse and accessibility as any other
  /// (its semantics node, its tap, its hit area) but no focus and no key:
  /// the halves of a stepper, whose control is one value control with one
  /// stop and its value commands, and whose halves are just targets with a
  /// 44 point area and a semantic button each. The focus and the keys then
  /// belong to a region around the host.
  final bool focusable;

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
  final Map<T, MotionSource> _sources = {};
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

  /// The zone that takes input under [position], in the host's
  /// coordinates, as a touch landing there finds it (its rect, else its
  /// hit extension); null between and beyond the zones, on a disabled
  /// zone, and while no host holds the controller.
  ///
  /// What a host interaction (`InputZones.interactions`) asks as the
  /// finger moves: a menu's finger over its rows.
  T? zoneAt(Offset position) {
    final zone = _host?._zoneAt(position);
    return zone != null && zone.takesInput ? zone.id : null;
  }

  /// Moves focus to [zone]; false when the host holds no such zone or it
  /// cannot take focus now.
  bool requestFocus(T zone) {
    final state = _host?._zones[zone];
    if (state == null || !state.node.canRequestFocus) return false;
    state.node.requestFocus();
    return true;
  }

  /// What a presentation grows out of when it grows out of [zone]: a menu
  /// from a bar item, a popover from a segment. Pass it as the
  /// presentation's `source`.
  ///
  /// The same source is answered for a zone every time. Its geometry is
  /// the zone's frame where the host paints it now, in global coordinates
  /// (`InputZones.frameOf`, read again in every frame the presentation
  /// shows), and null while no host holds the controller or the zone is
  /// not painted. While a presentation holds it, [MotionSource.isHidden]
  /// is true and the controller notifies, so the control paints the zone
  /// hidden, as a `MotionSourceBox` does.
  MotionSource sourceOf(T zone) => _sources.putIfAbsent(zone, () {
    final source = MotionSource(debugLabel: 'zone $zone');
    source.showIn(_ZoneSource<T>(this, zone));
    return source;
  });

  // A presentation may let go of a zone's source after the control that
  // painted the zone disposed of its controller.
  bool _disposed = false;

  void _sourceHiddenChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sources.clear();
    super.dispose();
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

/// Shows a zone's [MotionSource]: the zone's frame where its host paints
/// it now.
final class _ZoneSource<T extends Object> implements SourceView {
  _ZoneSource(this.controller, this.zone);

  final InputZonesController<T> controller;
  final T zone;

  @override
  SourceGeometry? get sourceGeometry {
    final host = controller._host;
    final box = host?._box;
    if (host == null || box == null || !box.attached || !box.hasSize) {
      return null;
    }
    final frame = host.widget.frameOf(zone);
    if (frame == null ||
        frame.opacity < InputZoneFrame.minimumOpacity ||
        frame.rect.isEmpty) {
      return null;
    }
    return SourceGeometry(
      rect: MatrixUtils.transformRect(box.getTransformTo(null), frame.rect),
      radius: frame.radius,
    );
  }

  @override
  void sourceHiddenChanged() => controller._sourceHiddenChanged();
}

/// Where Tab stops among the zones of an [InputZones] host.
///
/// WAI-ARIA: the tab sequence of a composite widget, every item or one
/// roving stop. Flutter: a `FocusTraversalGroup` whose items are all in
/// traversal, or a `RadioGroup`, whose radios Tab treats as one.
enum InputZoneStops {
  /// Every zone that takes a key is a stop of its own: the buttons of a
  /// dialog, the items of a toolbar.
  each,

  /// The host is one stop: Tab enters at [InputZones.current] (the
  /// selected item), else at the zone focused last, else at the first, and
  /// the next Tab leaves the group; the arrows, Home and End move among
  /// the zones. A segmented control, a tab bar, a radio-like group.
  one,
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
/// region arrive the same way, also onto no zone at first. The host's own
/// [interactions] hear each touch on the host whole, from down to up,
/// wherever the finger goes, and ask [InputZonesController.zoneAt] what
/// lies under it.
///
/// Mouse: each zone has its own cursor and hovered state, and hears hover
/// as `PointerHoverInput`s; a zone that moves under a resting mouse is
/// entered and left with the next frame. The secondary button and the
/// scroll wheel reach a zone's interactions that take them.
///
/// Focus: each zone has a focus node, made and disposed with the zone. A zone
/// can take focus while it is [InputZone.focusable] and takes input now, and is
/// a focus target for the keys while an interaction also activates or adjusts.
/// With [stops] at [InputZoneStops.each], Tab visits the targets in the order
/// of [zones] (other focusable widgets inside [child] come after them); at
/// [InputZoneStops.one] the host is a single stop that Tab enters at [current]
/// or at the zone focused last. Assistive technology reaches every zone that
/// can take focus either way. The arrows move between targets: along [axis] in
/// the order of [zones], mirrored in right-to-left for a horizontal axis, or to
/// the nearest zone on screen when [axis] is null; Home and End reach the first
/// and the last target. With [activatesOnMove], the zone an arrow, Home or End
/// moves to is also activated, as a keyboard activation: a selection that
/// follows focus. An arrow with no zone in its direction (past the last one, or
/// across [axis]) asks [onEdge], then moves focus as Flutter's directional
/// focus does, which may leave the host. A zone whose interaction adjusts keeps
/// the arrows, Home and End for its value
/// (`AdjustValueIntent.defaultShortcuts`). Space and Enter activate the focused
/// zone through `ActivateIntent`, and the context menu key and Shift+F10
/// open the context menu of a focused zone that has a secondary click
/// (`ContextMenuIntent`, at the zone's centre), which an app overrides with
/// `Actions` above
/// the host, as for `InputRegion`; a region around the host does not take
/// them from a focused zone.
///
/// Semantics: each zone that is [InputZoneFrame.live] is one semantics
/// node over its hit rectangle, which follows [frameOf], with its label,
/// value, flags, enabled state, tap, increase and decrease, and focus. The
/// semantics of [child] are dropped unless [excludeChildSemantics] is
/// false, since the zones describe what the child paints.
///
/// Each zone is a render box of its hit rectangle's size, placed on the
/// zone by the host's paint transform: tests and tools find a zone where it
/// is painted (`tester.tap(find.bySemanticsLabel('Edit'))` taps it), and
/// its focus node reports its rectangle. A frame in which the zones only
/// move rebuilds and lays out nothing: the host refreshes the zones'
/// semantics and focus state, and the transform is read when a hit test,
/// the semantics or the focus ask. A zone that appears or changes size
/// lays out its own box alone (each is its own relayout boundary) at the
/// start of the next frame; until then the transform scales the box to the
/// zone, and a box still empty reports the zone's bounds to semantics and
/// focus.
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
    this.stops = InputZoneStops.each,
    this.current,
    this.activatesOnMove = false,
    this.slides = false,
    this.feedback,
    this.onEdge,
    this.port,
    this.excludeChildSemantics = true,
    this.interactions = const [],
    this.hostFeedback,
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

  /// Whether every zone that takes a key is a Tab stop, or the host is one.
  final InputZoneStops stops;

  /// The zone Tab enters a host of [InputZoneStops.one] at, such as the
  /// selected item; null, or a zone that cannot take focus now, enters at
  /// the zone focused last, else at the first.
  final T? current;

  /// Whether the zone an arrow, Home or End moves focus to is activated
  /// too, as a keyboard activation: a selection that follows focus, as in
  /// a radio group or a segmented control.
  final bool activatesOnMove;

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

  /// What hears the touches on the host as a whole, in the host's
  /// coordinates; when two recognize on one input, the first wins.
  ///
  /// They hear a touch that lands anywhere on the host, on a zone or
  /// between the zones, or arrives through [port], from its down to its
  /// release wherever the finger goes, beyond the host too, beside the
  /// zone the touch lands on. They hold or give up the touch in the gesture
  /// arena as an `InputRegion`'s interactions do, and hear the arena give
  /// it to the host ([PointerAcceptedInput]); an observer
  /// ([InteractionRole.observer]) stays out of it. A host interaction asks
  /// [InputZonesController.zoneAt] which zone lies under the finger: a
  /// finger that opened a menu slides over its rows and beyond its edge,
  /// and the menu follows it. They also hear the mouse moving over the
  /// host, as `PointerHoverInput`s with `inside` true. When one
  /// [Interaction.contendsWithControls], the controls inside [child] start
  /// their touches contested, as below an `InputRegion`. Keys and
  /// accessibility stay the zones'; the haptics of the host's interactions
  /// are [hostFeedback]'s.
  final List<Interaction> interactions;

  /// The haptic for an event of [interactions], or null for none.
  ///
  /// As [feedback]: played as the event happens, never for a keyboard or
  /// accessibility input, and not below a `MotionHapticScope` that turns
  /// haptics off. A menu plays its selection haptic for the row a sliding
  /// finger reaches this way.
  final MotionHaptic? Function(InteractionEvent event)? hostFeedback;

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
  late InteractionSession _hostSession = InteractionSession(
    widget.interactions,
  );
  late final FocusTraversalPolicy _policy = _ZonesTraversal<T>(this);
  double? _scheduled;
  VoidCallback? _cancelDue;
  NavigationMode? _navigation;
  T? _lastFocused;

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
    _scheduleResize();
    _bindHost();
  }

  void _bindHost() {
    for (final interaction in widget.interactions) {
      interaction.bindRegion((local) => _box?.localToGlobal(local) ?? local);
    }
  }

  /// Ends the touches the host's interactions follow, for [reason].
  void _cancelHost(PointerCancelReason reason) {
    for (final pointer in _downs.keys.toList()) {
      _answerHost(
        _hostSession.handle(
          PointerCancelInput(
            time: _clock.now,
            pointer: pointer,
            reason: reason,
          ),
        ),
      );
    }
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
    _scheduleResize();
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
    if (!listEquals(oldWidget.interactions, widget.interactions)) {
      _cancelHost(PointerCancelReason.platform);
      _hostSession = InteractionSession(widget.interactions);
      _bindHost();
    }
    assert(
      widget.zones.map((zone) => zone.id).toSet().length == widget.zones.length,
      'Every zone of an InputZones has its own id.',
    );
  }

  @override
  void dispose() {
    widget.port?.detach(_receive);
    _cancelHost(PointerCancelReason.platform);
    widget.frames.removeListener(_framesChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _cancelDue?.call();
    if (_resize case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    if (controller._host == this) controller._host = null;
    _ownController?.dispose();
    super.dispose();
  }

  void _framesChanged() {
    // The frames may change inside a layout (a bar measures its items in
    // its own), where a control's frames cannot be read: they are compared
    // at the start of the next frame instead.
    final laying =
        SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    var resized = laying;
    for (final zone in _zones.values) {
      zone._syncNode();
      final anchor = zone._anchor;
      if (anchor == null || !anchor.attached) continue;
      resized = resized || anchor.wanted != zone.bounds.size;
      // An absent zone is out of the semantics tree; the host's update
      // drops a zone that leaves, and one that appears is described anew.
      final present = zone.present;
      if (present || zone._described) anchor.markNeedsSemanticsUpdate();
      zone._described = present;
    }
    _box?.markNeedsSemanticsUpdate();
    if (resized) _scheduleResize();
  }

  int? _resize;

  // An anchor is laid out to the size its zone had when the frame began: a
  // control reads its frames from its own boxes, which nothing may read
  // while the frame lays out. The host's transform scales an anchor to its
  // zone until then.
  void _scheduleResize() {
    _resize ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _resize = null;
      if (!mounted) return;
      for (final zone in _zones.values) {
        final anchor = zone._anchor;
        if (anchor == null || !anchor.attached) continue;
        final wanted = zone.bounds.size;
        if (anchor.wanted == wanted) continue;
        anchor.wanted = wanted;
        anchor.markNeedsLayout();
      }
    });
  }

  /// The node Tab enters a host of one stop at: the current zone's, else
  /// the one focused last, else the first target's.
  FocusNode? _entry() {
    _ZoneState<T>? first;
    _ZoneState<T>? last;
    for (final zone in widget.zones) {
      final state = _zones[zone.id];
      if (state == null || !_traversable(state)) continue;
      if (zone.id == widget.current) return state.node;
      first ??= state;
      if (zone.id == _lastFocused) last = state;
    }
    return (last ?? first)?.node;
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
      contested: ContestScope.of(context, listen: false),
    );
    _clock.input(input.time, () => _route(input, arena: false));
  }

  void _pointer(PointerEvent event) {
    switch (event) {
      case PointerScrollEvent():
        _wheel(event);
      case PointerHoverEvent():
        _hoverHost(event);
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

  void _hoverHost(PointerHoverEvent event) {
    if (widget.interactions.isEmpty) return;
    final time = _clock.now;
    _clock.input(
      time,
      () => _answerHost(
        _hostSession.handle(
          PointerHoverInput(
            time: time,
            position: event.localPosition,
            inside: true,
          ),
        ),
      ),
    );
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
            globalPosition: event.position,
            kind: event.kind,
            buttons: event.buttons,
            scrollAxes: scrollAxesAround(context),
            contested: ContestScope.of(context, listen: false),
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
            globalPosition: event.position,
          ),
          arena: true,
        );
      case PointerUpEvent():
        _speed.lifted();
        final tracker = _trackers.remove(event.pointer);
        tracker?.addPosition(event.timeStamp, event.localPosition);
        final velocity = tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
        _route(
          PointerUpInput(
            time: time,
            pointer: event.pointer,
            position: event.localPosition,
            velocity: velocity,
            globalPosition: event.position,
            globalVelocity: globalVector(
              event.transform,
              velocity,
              event.localPosition,
            ),
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
        _answerHost(_hostSession.handle(input), pointer: pointer);
        final zone = _zones[_owners.remove(pointer)];
        if (zone == null) return;
        _answer(
          zone,
          zone.session.handle(zone._local(input)),
          pointer: pointer,
        );
      case PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        break;
    }
  }

  void _down(PointerDownInput down, {required bool arena}) {
    final pointer = down.pointer;
    if (_downs.containsKey(pointer)) return;
    final host = _hostSession.handle(down);
    final hostTakes = _hostSession.follows(pointer);
    final zone = _zoneAt(down.position);
    final output = zone != null && zone.takesInput
        ? zone.session.handle(zone._local(down))
        : null;
    final accepted = output != null && !output.reject;
    if (!accepted &&
        !widget.slides &&
        !hostTakes &&
        !_hostSession.observes(pointer)) {
      if (zone != null && output != null) _answer(zone, output);
      _answerHost(host);
      return;
    }
    _downs[pointer] = down;
    if (arena && (accepted || widget.slides || hostTakes)) {
      final member = InputArenaMember(_lost, onAccepted: _accepted);
      _members[pointer] = member;
      member.entry = GestureBinding.instance.gestureArena.add(pointer, member);
    }
    if (zone != null && output != null) {
      if (accepted) {
        _owners[pointer] = zone.id;
        _answer(
          zone,
          output,
          pointer: pointer,
          extra: [
            if (widget.slides)
              ScrubChangeEvent(
                time: down.time,
                selected: zone.id,
                atDown: true,
              ),
          ],
        );
      } else {
        _answer(zone, output);
      }
    }
    // After the zone took its part, so a host that takes nothing leaves
    // the touch to the zone.
    _answerHost(host, pointer: pointer);
  }

  void _move(PointerMoveInput move) {
    final down = _downs[move.pointer];
    if (down == null) return;
    _answerHost(_hostSession.handle(move), pointer: move.pointer);
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
          globalPosition: move.globalPosition,
          kind: down.kind,
          buttons: down.buttons,
          scrollAxes: down.scrollAxes,
          contested: down.contested,
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

  void _accepted(int pointer) {
    if (!_members.containsKey(pointer)) return;
    final time = _clock.now;
    _clock.input(time, () {
      final input = PointerAcceptedInput(time: time, pointer: pointer);
      _answerHost(_hostSession.handle(input), pointer: pointer);
      final zone = _zones[_owners[pointer]];
      if (zone == null) return;
      _answer(zone, zone.session.handle(input), pointer: pointer);
    });
  }

  void _lost(int pointer) {
    if (_members.remove(pointer) == null) return;
    if (!_hostSession.observes(pointer)) {
      _trackers.remove(pointer);
      _downs.remove(pointer);
    }
    _answerHost(_hostSession.lost(pointer, _clock.now));
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
      if (output.reject && !widget.slides && !_hostSession.follows(pointer)) {
        entry?.resolve(GestureDisposition.rejected);
      }
    }
    for (final event in [...extra, ...output.events]) {
      _play(zone.id, event);
    }
    if (zone.mounted) zone._writeStates();
    _scheduleDue();
  }

  /// Resolves the arena for what the host's interactions made of a touch,
  /// and plays their haptics.
  void _answerHost(SessionOutput output, {int? pointer}) {
    if (pointer != null) {
      final entry = _members[pointer]?.entry;
      if (output.claim) entry?.resolve(GestureDisposition.accepted);
      if (output.reject && !widget.slides && !_owners.containsKey(pointer)) {
        entry?.resolve(GestureDisposition.rejected);
      }
    }
    for (final event in output.events) {
      _playHost(event);
    }
    _scheduleDue();
  }

  void _playHost(InteractionEvent event) {
    if (event is ActivationEvent && event.source != ActivationSource.pointer) {
      return;
    }
    if (!mounted) return;
    final haptic = widget.hostFeedback?.call(event);
    if (haptic != null) playHaptic(context, haptic);
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
    var due = _hostSession.nextDue;
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
        final hostDue = _hostSession.nextDue;
        if (hostDue != null && hostDue <= time) {
          _answerHost(
            _hostSession.advance(time),
            pointer: _downs.keys.where(_hostSession.follows).firstOrNull,
          );
        }
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

  // What can take focus for the keys, whether or not Tab visits it.
  bool _traversable(_ZoneState<T> zone) =>
      zone.node.canRequestFocus && zone._takesKeys;

  void _moveTo(_ZoneState<T> zone) {
    zone.node.requestFocus();
    if (widget.activatesOnMove && zone._activates) {
      zone._activate(ActivationSource.keyboard);
    }
  }

  void _moveFocus(_ZoneState<T> from, TraversalDirection direction) {
    final next = widget.axis == null
        ? _nearest(from, direction)
        : _along(from, direction, widget.axis!);
    if (next != null) {
      _moveTo(next);
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
    if (target != null && !identical(target, from)) _moveTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final contends = widget.interactions.any((i) => i.contendsWithControls);
    return FocusTraversalGroup(
      policy: _policy,
      child: _ZonesHost<T>(
        state: this,
        excludeChildSemantics: widget.excludeChildSemantics,
        children: [
          ContestScope(
            contested: ContestScope.of(context) || contends,
            child: widget.child,
          ),
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
}

/// Tab order of the zones: every target in the order of the zones, or,
/// for a host of one stop, the entry alone besides the focused node.
class _ZonesTraversal<T extends Object> extends OrderedTraversalPolicy {
  _ZonesTraversal(this.host);

  final _InputZonesState<T> host;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final sorted = super.sortDescendants(descendants, currentNode);
    if (host.widget.stops == InputZoneStops.each) return sorted;
    final zones = {for (final zone in host._zones.values) zone.node};
    final entry = host._entry();
    return [
      for (final node in sorted)
        if (!zones.contains(node) || node == entry || node == currentNode) node,
    ];
  }
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
  _RenderZoneAnchor<T>? _anchor;
  late Map<Type, Action<Intent>> _actions;
  Offset _origin = Offset.zero;
  Size _size = Size.zero;
  bool _hasFocus = false;
  bool _hovering = false;

  // Whether the zone was present when the frames last changed.
  bool _described = false;

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

  bool get _opensMenu => zone.interactions.any((i) => i.opensContextMenu);

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
      if (_hovering) {
        final now = host._clock.now;
        host._clock.input(
          now,
          () => host._answer(
            this,
            session.handle(
              PointerHoverInput(
                time: now,
                position: Offset.zero,
                inside: false,
              ),
            ),
          ),
        );
      }
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

  /// Whether the zone takes a key: an interaction activates or adjusts.
  bool get _takesKeys => _activates || _adjusts;

  void _syncNode() {
    node.canRequestFocus = zone.focusable && takesInput;
    node.skipTraversal = !_takesKeys;
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
    if (focused) host._lastFocused = id;
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
        globalPosition: input.globalPosition,
        kind: input.kind,
        buttons: input.buttons,
        scrollAxes: input.scrollAxes,
        contested: input.contested,
      ),
      PointerMoveInput() => PointerMoveInput(
        time: input.time,
        pointer: input.pointer,
        position: input.position - origin,
        globalPosition: input.globalPosition,
      ),
      PointerUpInput() => PointerUpInput(
        time: input.time,
        pointer: input.pointer,
        position: input.position - origin,
        velocity: input.velocity,
        globalPosition: input.globalPosition,
        globalVelocity: input.globalVelocity,
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
      ContextMenuInput() => ContextMenuInput(
        time: input.time,
        position: input.position - origin,
        source: input.source,
      ),
      PointerCancelInput() ||
      PointerAcceptedInput() ||
      ActivateInput() ||
      AdjustInput() => input,
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

  void _openMenu() => _input(
    ContextMenuInput(time: host._clock.now, position: bounds.center),
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

  late final Action<ActivateIntent> _activateAction =
      Action<ActivateIntent>.overridable(
        defaultAction: _ZoneActivate<ActivateIntent, T>(this),
        context: context,
      );

  late final Action<ButtonActivateIntent> _buttonAction =
      Action<ButtonActivateIntent>.overridable(
        defaultAction: _ZoneActivate<ButtonActivateIntent, T>(this),
        context: context,
      );

  late final Action<AdjustValueIntent> _adjustAction =
      Action<AdjustValueIntent>.overridable(
        defaultAction: _ZoneAdjust<T>(this),
        context: context,
      );

  late final Action<ContextMenuIntent> _menuAction =
      Action<ContextMenuIntent>.overridable(
        defaultAction: _ZoneMenu<T>(this),
        context: context,
      );

  ({bool activates, bool adjusts, bool opensMenu})? _actionsFor;

  // As an InputRegion: an action only for what the zone takes, so a key it
  // does not take reaches the actions around the host.
  Map<Type, Action<Intent>> _actionsNow() {
    final takes = (
      activates: _activates,
      adjusts: _adjusts,
      opensMenu: _opensMenu,
    );
    if (takes == _actionsFor) return _actions;
    _actionsFor = takes;
    return _actions = {
      if (takes.activates) ...{
        ActivateIntent: _activateAction,
        ButtonActivateIntent: _buttonAction,
      },
      if (takes.adjusts) AdjustValueIntent: _adjustAction,
      if (takes.opensMenu) ContextMenuIntent: _menuAction,
      DirectionalFocusIntent: _ZoneMove<T>(this),
      _ZoneEndIntent: _ZoneEnd<T>(this),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!zone.focusable) return _ZoneAnchor<T>(state: this);
    return Actions(
      actions: _actionsNow(),
      child: Shortcuts(
        includeSemantics: false,
        shortcuts: _adjusts || _opensMenu
            ? {
                ..._moves,
                if (_opensMenu) ...ContextMenuIntent.defaultShortcuts,
                if (_adjusts)
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

class _ZoneActivate<I extends Intent, T extends Object> extends HostAction<I> {
  _ZoneActivate(this.zone);

  final _ZoneState<T> zone;

  @override
  bool takes(I intent) => zone.zone.enabled && zone._activates;

  @override
  bool get focused => zone.node.hasPrimaryFocus;

  @override
  void run(I intent) => zone._activate(ActivationSource.keyboard);
}

class _ZoneAdjust<T extends Object> extends HostAction<AdjustValueIntent> {
  _ZoneAdjust(this.zone);

  final _ZoneState<T> zone;

  @override
  bool takes(AdjustValueIntent intent) =>
      zone.zone.enabled && zone._adjusts && zone._range.allows(intent.command);

  @override
  bool get focused => true;

  @override
  void run(AdjustValueIntent intent) =>
      zone._adjust(intent.command, ActivationSource.keyboard);
}

class _ZoneMenu<T extends Object> extends HostAction<ContextMenuIntent> {
  _ZoneMenu(this.zone);

  final _ZoneState<T> zone;

  @override
  bool takes(ContextMenuIntent intent) => zone.zone.enabled && zone._opensMenu;

  @override
  bool get focused => zone.node.hasPrimaryFocus;

  @override
  void run(ContextMenuIntent intent) => zone._openMenu();
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
/// zones' anchors after it paint nothing and lie where their zones are,
/// placed by paint transform.
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
    // Each anchor sizes itself and is its own relayout boundary.
    var anchor = childAfter(content);
    while (anchor != null) {
      anchor.layout(const BoxConstraints());
      anchor = childAfter(anchor);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (child is! _RenderZoneAnchor<T>) {
      return super.applyPaintTransform(child, transform);
    }
    final bounds = child.zone.bounds;
    transform.translateByDouble(bounds.left, bounds.top, 0, 1);
    final laid = child.size;
    // Until it is laid out to a new size, the anchor is scaled to it.
    if (laid != bounds.size && !laid.isEmpty) {
      transform.scaleByDouble(
        bounds.width / laid.width,
        bounds.height / laid.height,
        1,
        1,
      );
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
      final hit = content.hitTest(result, position: position);
      if (state.widget.interactions.isEmpty) return hit;
      // The host's own interactions hear a touch between the zones.
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    content?.hitTest(result, position: position);
    // In the host's coordinates: the zone's events are read in them.
    if (zone._anchor case final anchor? when anchor.attached) {
      result.add(BoxHitTestEntry(anchor, position));
    }
    return true;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (state.mounted) state._pointer(event);
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
    renderObject.markNeedsLayout();
    renderObject.markNeedsSemanticsUpdate();
  }
}

/// A zone's place in the render tree: a box of the zone's hit size,
/// which the host places on the zone by paint transform, so a frame where
/// the zone only moves lays nothing out. It is what a pointer on the zone
/// hits (its cursor and hover for the mouse tracker), the box its focus
/// node reports, and it describes the zone to accessibility.
class _RenderZoneAnchor<T extends Object> extends RenderBox
    implements MouseTrackerAnnotation {
  _RenderZoneAnchor(this.zone);

  _ZoneState<T> zone;

  /// The size to lay out to: its zone's when the frame began.
  Size wanted = Size.zero;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(wanted);

  @override
  void performLayout() => size = constraints.constrain(wanted);

  // A zone that appears after its anchor was laid out empty (its first
  // frame comes after the layout that places it) has no size to scale: its
  // bounds stand for it until it is laid out.
  Rect get _local => Offset.zero & (size.isEmpty ? zone.bounds.size : size);

  @override
  Rect get paintBounds => _local;

  @override
  Rect get semanticBounds => _local;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  // The host adds the anchor to a hit at the host's coordinates.
  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (zone.mounted) zone.host._pointer(event);
  }

  @override
  MouseCursor get cursor => zone.mounted ? zone.cursor : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => zone._entered;

  @override
  PointerExitEventListener? get onExit => zone._exited;

  @override
  bool get validForMouseTracker => attached && zone.mounted;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    zone.describe(config);
  }
}
