import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';

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
/// (a press, a tap), the accessibility tap and the `ActivateIntent` and
/// `ButtonActivateIntent` of the app's shortcuts activate it: Space and
/// Enter under a `WidgetsApp`, as for Flutter's own buttons. An app remaps
/// the keys with `Shortcuts` and replaces what activation does with an
/// `Actions` above the region, since the region's actions are
/// `Action.overridable`. When an interaction [Interaction.adjusts] (a
/// slider, a stepper), the region binds the keys of
/// [AdjustValueIntent.defaultShortcuts] around its focus and gives
/// accessibility increase and decrease; both arrive as [AdjustInput]s.
///
/// Presses of the secondary button reach the interactions that accept them
/// (`SecondaryClickInteraction`); the scroll wheel reaches them as
/// [PointerScrollInput]s when one [Interaction.takesWheel], and the region
/// then keeps it from the scroll views around it.
///
/// With a [port] it also hears the touches another region hands on to it
/// (`InputPort.forward`), mapped into its own coordinates. It writes
/// pressed, hovered, focused, dragged and disabled into [statesController]
/// (focused only while the focus should show: when the keyboard was used
/// last, as `InkWell` does, so a tap that focuses lights no ring), and
/// plays the haptic [feedback] picks for each event as it happens;
/// keyboard and accessibility activations play none.
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
    this.minimumHitSize,
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
  ///
  /// This is the one way a control plays a haptic: the region plays it as
  /// the event happens, never for a keyboard or accessibility activation,
  /// and plays none under a [MotionHapticScope] that turns haptics off.
  final MotionHaptic? Function(InteractionEvent event)? feedback;

  /// Whether the region takes input; disabling it ends a touch.
  final bool enabled;

  /// The cursor over the region, or null for the default.
  ///
  /// A `WidgetStateMouseCursor` is resolved against the region's states:
  /// [statesController]'s value when there is one, else the states the
  /// region writes (pressed, hovered, focused, dragged, disabled). The
  /// default is `WidgetStateMouseCursor.adaptiveClickable` when an
  /// interaction [Interaction.activates] (a click cursor on the web, the
  /// basic one elsewhere and while disabled), `MouseCursor.defer`
  /// otherwise, which leaves the cursor to what lies under the region.
  final MouseCursor? mouseCursor;

  /// The region's focus node, or null for its own.
  ///
  /// The region's own node is skipped in focus traversal when no
  /// interaction activates or adjusts, since such a region takes no key:
  /// Tab never stops on it. A given node keeps its own
  /// `FocusNode.skipTraversal`.
  final FocusNode? focusNode;

  /// Whether the region takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the region.
  final String? semanticLabel;

  /// Where touches handed on from another region arrive, or null.
  final InputPort? port;

  /// The smallest area the region takes pointers in, or null for its box.
  ///
  /// A region smaller than this takes pointers in a rectangle of this size
  /// centred on its box, without changing its layout or its paint: a 28
  /// point switch with a 44 by 44 minimum is pressed by a finger up to 8
  /// points above or below it, as UIKit's is. A pointer in the extension
  /// reaches the region's interactions at its real position, with
  /// [PointerDownInput.hitArea] covering the extension, so a press there
  /// counts as inside; the child is hit at the nearest point of the box.
  /// The accessibility rectangle grows the same way when the region owns
  /// its semantics node: a control that adds its own `Semantics` puts it
  /// below the region, so its flags join the region's node.
  ///
  /// Flutter delivers a pointer only through ancestors whose own hit test
  /// contains it: where a parent clips or stops at its box, as a `Row`
  /// sized to the region does, the extension beyond the parent takes
  /// nothing. Give such a parent room, as Material's buttons do with their
  /// tap target padding.
  final Size? minimumHitSize;

  @override
  State<InputRegion> createState() => _InputRegionState();
}

class _InputRegionState extends State<InputRegion> {
  late InteractionSession _session = InteractionSession(widget.interactions);
  FocusNode? _ownFocus;
  WidgetStatesController? _ownStates;
  MouseCursor? _builtCursor;
  Map<Type, Action<Intent>>? _actions;
  double? _scheduled;
  VoidCallback? _cancelDue;
  final Map<int, VelocityTracker> _trackers = {};
  final Map<int, _ArenaMember> _members = {};

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  MotionClock get _clock => MotionClock.instance;

  _RenderRegion? _box;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownStates ??= WidgetStatesController());

  @override
  void initState() {
    super.initState();
    _states.update(WidgetState.disabled, !widget.enabled);
    _states.addListener(_statesChanged);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    _bindRegions();
    _attachPort(widget.port);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = MediaQuery.maybeNavigationModeOf(context);
    if (navigation == _navigation) return;
    _navigation = navigation;
    _showFocus();
  }

  @override
  void didUpdateWidget(InputRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.interactions, widget.interactions)) {
      _cancelAll(PointerCancelReason.platform);
      _session = InteractionSession(widget.interactions);
      _bindRegions();
    }
    if (oldWidget.enabled && !widget.enabled) {
      _cancelAll(PointerCancelReason.disabled);
    }
    if (oldWidget.port != widget.port) {
      oldWidget.port?.detach(_receive);
      _attachPort(widget.port);
    }
    if (oldWidget.statesController != widget.statesController) {
      (oldWidget.statesController ?? _ownStates)?.removeListener(
        _statesChanged,
      );
      if (widget.statesController != null) {
        _ownStates?.dispose();
        _ownStates = null;
      }
      _states.addListener(_statesChanged);
    }
    _states.update(WidgetState.disabled, !widget.enabled);
    if (oldWidget.enabled != widget.enabled) _showFocus();
  }

  @override
  void dispose() {
    widget.port?.detach(_receive);
    _cancelAll(PointerCancelReason.platform);
    _cancelDue?.call();
    _states.removeListener(_statesChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _ownStates?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  bool _hasFocus = false;

  void _focusChanged(bool focused) {
    _hasFocus = focused;
    _showFocus();
  }

  void _highlightModeChanged(FocusHighlightMode mode) => _showFocus();

  // As InkWell does: focus shows only in keyboard mode, so a tap that
  // focuses lights no ring, and under directional navigation (a TV remote)
  // a disabled region that holds focus shows it too.
  void _showFocus() {
    final shown =
        _hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional &&
        (widget.enabled || _navigation == NavigationMode.directional);
    _states.update(WidgetState.focused, shown);
  }

  MouseCursor get _cursor => WidgetStateProperty.resolveAs<MouseCursor>(
    widget.mouseCursor ??
        (_activates
            ? WidgetStateMouseCursor.adaptiveClickable
            : MouseCursor.defer),
    _states.value,
  );

  // Only a cursor that changes with the states rebuilds the region.
  void _statesChanged() {
    if (mounted && _builtCursor != null && _cursor != _builtCursor) {
      setState(() {});
    }
  }

  void _bindRegions() {
    for (final interaction in widget.interactions) {
      interaction.bindRegion(_toGlobal);
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
      hitArea: box.hitArea,
      scrollAxes: event.handOff ? _scrollAxes() : const {},
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
    if (event is PointerScrollEvent) {
      if (widget.interactions.any((i) => i.takesWheel)) {
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          _scrolled,
        );
      }
      return;
    }
    if (event is! PointerDownEvent && !_members.containsKey(event.pointer)) {
      return;
    }
    final time = _clock.stamp(event.timeStamp);
    _clock.input(time, () => _dispatch(event, size, time));
  }

  void _scrolled(PointerSignalEvent event) {
    if (!mounted || !widget.enabled || event is! PointerScrollEvent) return;
    final time = _clock.stamp(event.timeStamp);
    _clock.input(
      time,
      () => _answer(
        _session.handle(
          PointerScrollInput(
            time: time,
            position: event.localPosition,
            scrollDelta: event.scrollDelta,
            kind: event.kind,
          ),
        ),
      ),
    );
  }

  Duration? _movedAt;

  void _reportSpeed(PointerMoveEvent event) {
    final last = _movedAt;
    _movedAt = event.timeStamp;
    if (last == null || !mounted) return;
    final seconds = (event.timeStamp - last).inMicroseconds / 1e6;
    if (seconds <= 0) return;
    FrameCadence.instance.input(
      pixelsPerSecond:
          event.delta.distance * View.of(context).devicePixelRatio / seconds,
    );
  }

  void _dispatch(PointerEvent event, Size size, double time) {
    switch (event) {
      case PointerDownEvent():
        _movedAt = event.timeStamp;
        FrameCadence.instance.input(changed: true);
        final tracker = VelocityTracker.withKind(event.kind);
        tracker.addPosition(event.timeStamp, event.localPosition);
        final output = _session.handle(
          PointerDownInput(
            time: time,
            pointer: event.pointer,
            position: event.localPosition,
            regionSize: size,
            hitArea: _box?.hitArea,
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
        _reportSpeed(event);
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
        FrameCadence.instance.input(changed: true);
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
    if (!MotionHapticScope._enabledHere(context)) return;
    widget.feedback?.call(event)?.play();
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
    final states = _states;
    var pressed = false;
    var dragged = false;
    for (final interaction in widget.interactions) {
      pressed = pressed || interaction.pressed;
      dragged = dragged || interaction.dragged;
    }
    states.update(WidgetState.pressed, pressed);
    states.update(WidgetState.dragged, dragged);
  }

  bool get _activates => widget.interactions.any((i) => i.activates);

  bool get _adjusts => widget.interactions.any((i) => i.adjusts);

  NavigationMode? _navigation;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    _actions ??= {
      ActivateIntent: Action<ActivateIntent>.overridable(
        defaultAction: _Activate<ActivateIntent>(this),
        context: context,
      ),
      ButtonActivateIntent: Action<ButtonActivateIntent>.overridable(
        defaultAction: _Activate<ButtonActivateIntent>(this),
        context: context,
      ),
      AdjustValueIntent: Action<AdjustValueIntent>.overridable(
        defaultAction: _Adjust(this),
        context: context,
      ),
    };
    return _Region(
      state: this,
      described: (
        minimumHitSize: widget.minimumHitSize,
        label: widget.semanticLabel,
        textDirection: Directionality.maybeOf(context),
        enabled: enabled,
        tappable: enabled && _activates,
        adjustable: enabled && _adjusts,
      ),
      child: Actions(
        actions: _actions!,
        child: Shortcuts(
          shortcuts: _adjusts
              ? AdjustValueIntent.defaultShortcuts(
                  Directionality.maybeOf(context) ?? TextDirection.ltr,
                  _navigation ?? NavigationMode.traditional,
                )
              : const {},
          child: Focus(
            focusNode: _focus,
            autofocus: widget.autofocus,
            canRequestFocus: enabled,
            skipTraversal: widget.focusNode == null
                ? !_activates && !_adjusts
                : null,
            onFocusChange: _focusChanged,
            child: MouseRegion(
              cursor: _builtCursor = _cursor,
              onEnter: (event) => _hover(event, inside: true),
              onHover: (event) => _hover(event, inside: true),
              onExit: (event) => _hover(event, inside: false),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  void _semanticTap() => _input(
    ActivateInput(time: _clock.now, source: ActivationSource.accessibility),
  );

  void _adjust(ValueCommand command, ActivationSource source) => _input(
    AdjustInput(time: _clock.now, command: command, source: source),
  );

  void _hover(PointerEvent event, {required bool inside}) {
    _states.update(WidgetState.hovered, inside);
    _input(
      PointerHoverInput(
        time: _clock.now,
        position: event.localPosition,
        inside: inside,
      ),
    );
  }
}

/// Activates the region for an intent the app's shortcuts send, as long as
/// the region is enabled and an interaction activates.
class _Activate<T extends Intent> extends Action<T> {
  _Activate(this.state);

  final _InputRegionState state;

  @override
  bool isEnabled(T intent) => state.widget.enabled && state._activates;

  @override
  Object? invoke(T intent) {
    state._input(ActivateInput(time: state._clock.now));
    return null;
  }
}

/// Steps the region's value for an [AdjustValueIntent], as long as the
/// region is enabled and an interaction adjusts.
class _Adjust extends Action<AdjustValueIntent> {
  _Adjust(this.state);

  final _InputRegionState state;

  @override
  bool isEnabled(AdjustValueIntent intent) =>
      state.widget.enabled && state._adjusts;

  @override
  Object? invoke(AdjustValueIntent intent) {
    state._adjust(intent.command, ActivationSource.keyboard);
    return null;
  }
}

/// Asks the focused region to step its value: the intent of the arrows,
/// Home and End, Page Up and Page Down on a slider, a stepper or a page
/// control.
///
/// Flutter: the private adjustment intent of `Slider`.
///
/// An [InputRegion] whose interaction [Interaction.adjusts] binds
/// [defaultShortcuts] around its focus, as `Slider` does inside its own
/// widget, and turns the intent into an [AdjustInput]. An app replaces
/// what a command does with an `Actions` above the region (the region's
/// action is `Action.overridable`), and binds more keys to the intent with
/// a `Shortcuts` above the region; the keys the region binds itself come
/// first, as `Slider`'s do.
class AdjustValueIntent extends Intent {
  /// Asks for [command].
  const AdjustValueIntent(this.command);

  /// The step asked for.
  final ValueCommand command;

  static const Map<ShortcutActivator, Intent> _vertical = {
    SingleActivator(LogicalKeyboardKey.arrowUp): AdjustValueIntent(
      ValueCommand.increase,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): AdjustValueIntent(
      ValueCommand.decrease,
    ),
    SingleActivator(LogicalKeyboardKey.home): AdjustValueIntent(
      ValueCommand.toMinimum,
    ),
    SingleActivator(LogicalKeyboardKey.end): AdjustValueIntent(
      ValueCommand.toMaximum,
    ),
    SingleActivator(LogicalKeyboardKey.pageUp): AdjustValueIntent(
      ValueCommand.increaseLarge,
    ),
    SingleActivator(LogicalKeyboardKey.pageDown): AdjustValueIntent(
      ValueCommand.decreaseLarge,
    ),
  };

  static const Map<ShortcutActivator, Intent> _leftToRight = {
    SingleActivator(LogicalKeyboardKey.arrowRight): AdjustValueIntent(
      ValueCommand.increase,
    ),
    SingleActivator(LogicalKeyboardKey.arrowLeft): AdjustValueIntent(
      ValueCommand.decrease,
    ),
  };

  static const Map<ShortcutActivator, Intent> _rightToLeft = {
    SingleActivator(LogicalKeyboardKey.arrowLeft): AdjustValueIntent(
      ValueCommand.increase,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): AdjustValueIntent(
      ValueCommand.decrease,
    ),
  };

  static final Map<ShortcutActivator, Intent> _traditionalLeftToRight = {
    ..._leftToRight,
    ..._vertical,
  };

  static final Map<ShortcutActivator, Intent> _traditionalRightToLeft = {
    ..._rightToLeft,
    ..._vertical,
  };

  /// The keys a value region binds in [direction] under [navigation]: the
  /// arrow toward the end of the line increases (right in left-to-right,
  /// left in right-to-left), the other decreases, and in traditional
  /// navigation up increases, down decreases, Home and End go to the
  /// minimum and maximum, Page Up and Page Down take a larger step. In
  /// directional navigation (a TV remote) only the horizontal arrows are
  /// bound, so up and down still move focus.
  static Map<ShortcutActivator, Intent> defaultShortcuts(
    TextDirection direction,
    NavigationMode navigation,
  ) => switch ((navigation, direction)) {
    (NavigationMode.directional, TextDirection.ltr) => _leftToRight,
    (NavigationMode.directional, TextDirection.rtl) => _rightToLeft,
    (NavigationMode.traditional, TextDirection.ltr) => _traditionalLeftToRight,
    (NavigationMode.traditional, TextDirection.rtl) => _traditionalRightToLeft,
  };
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

/// What the region's box needs besides its state: its hit size and what
/// it tells accessibility.
typedef _Described = ({
  Size? minimumHitSize,
  String? label,
  TextDirection? textDirection,
  bool enabled,
  bool tappable,
  bool adjustable,
});

class _Region extends SingleChildRenderObjectWidget {
  const _Region({
    required this.state,
    required this.described,
    required super.child,
  });

  final _InputRegionState state;
  final _Described described;

  @override
  _RenderRegion createRenderObject(BuildContext context) {
    final box = _RenderRegion(state, described);
    state._box = box;
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderRegion renderObject) {
    renderObject.state = state;
    renderObject.described = described;
    state._box = renderObject;
  }
}

/// The region's box: it takes pointers in its hit area and describes the
/// region to accessibility over that area.
class _RenderRegion extends RenderProxyBox {
  _RenderRegion(this.state, this._described);

  _InputRegionState state;

  _Described _described;
  _Described get described => _described;
  set described(_Described value) {
    if (value == _described) return;
    // The accessibility rectangle is laid out with the box.
    if (value.minimumHitSize != _described.minimumHitSize) markNeedsLayout();
    _described = value;
    markNeedsSemanticsUpdate();
  }

  /// Where the region takes pointers, in its coordinates.
  Rect get hitArea {
    final box = Offset.zero & size;
    final minimum = _described.minimumHitSize;
    if (minimum == null) return box;
    return Rect.fromCenter(
      center: box.center,
      width: math.max(size.width, minimum.width),
      height: math.max(size.height, minimum.height),
    );
  }

  @override
  Rect get semanticBounds => hitArea;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    if (_described.minimumHitSize == null || !hitArea.contains(position)) {
      return false;
    }
    // The child is hit where the box is nearest; the events keep their real
    // position, since the transform to this box is unchanged.
    hitTestChildren(
      result,
      position: Offset(
        position.dx.clamp(0, _inside(size.width)),
        position.dy.clamp(0, _inside(size.height)),
      ),
    );
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  static double _inside(double extent) =>
      math.max(0, extent - precisionErrorTolerance);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    state._pointer(event, size);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final described = _described;
    final label = described.label;
    if (label != null) {
      config.label = label;
      config.textDirection = described.textDirection;
    }
    config.isEnabled = described.enabled;
    if (described.tappable) config.onTap = state._semanticTap;
    if (described.adjustable) {
      config.onIncrease = () =>
          state._adjust(ValueCommand.increase, ActivationSource.accessibility);
      config.onDecrease = () =>
          state._adjust(ValueCommand.decrease, ActivationSource.accessibility);
    }
  }
}

/// Turns the haptics of the input regions below it on or off: an app's
/// setting for haptics, or a part of a screen that stays quiet.
///
/// UIKit: the System Haptics setting. Flutter: none; `TickerMode` is the
/// same shape for tickers.
///
/// An [InputRegion] below a scope with [enabled] false plays no
/// [InputRegion.feedback]. A scope cannot turn haptics back on below one
/// that turned them off. Code that calls [MotionHapticPlay.play] itself is
/// not silenced.
class MotionHapticScope extends StatelessWidget {
  /// Turns the haptics of [child] on or off.
  const MotionHapticScope({
    required this.enabled,
    required this.child,
    super.key,
  });

  /// Whether the regions below play their haptics.
  final bool enabled;

  /// The subtree the scope governs.
  final Widget child;

  /// Whether haptics are on at [context]: false below any scope that turns
  /// them off, true otherwise. Rebuilds [context] when that changes.
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HapticScope>()?.enabled ??
      true;

  static bool _enabledHere(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_HapticScope>()?.enabled ?? true;

  @override
  Widget build(BuildContext context) => _HapticScope(
    enabled: enabled && enabledOf(context),
    child: child,
  );
}

class _HapticScope extends InheritedWidget {
  const _HapticScope({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_HapticScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Plays a [MotionHaptic] on the platform at once.
///
/// It plays even below a [MotionHapticScope] that turns haptics off: a
/// control plays its haptics through [InputRegion.feedback], which the
/// scope silences, and calls this only where no region event fits.
extension MotionHapticPlay on MotionHaptic {
  /// Plays the haptic, whatever any scope says.
  void play() => switch (this) {
    .selection => HapticFeedback.selectionClick(),
    .lightImpact => HapticFeedback.lightImpact(),
    .mediumImpact => HapticFeedback.mediumImpact(),
    .heavyImpact => HapticFeedback.heavyImpact(),
  }.ignore();
}
