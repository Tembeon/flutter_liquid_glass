import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/haptics.dart';
import 'package:kinesis/src/widgets/input_intents.dart';
import 'package:kinesis/src/widgets/input_shared.dart';

/// One thing a person acts on, as an input host keeps it: a session of
/// interactions with its keys, its states, its haptics and its timed
/// reactions.
///
/// `InputRegion` hosts one; each zone of an `InputZones` is one, and so is
/// the box of the zones itself. A host says where its target is and what it
/// may do now; what a target does with an input is the same in every host.
/// Its pointers reach it through its [line].
@internal
abstract class InputTarget {
  /// Creates a target over [interactions].
  InputTarget(List<Interaction> interactions)
    : _interactions = interactions,
      session = InteractionSession(interactions) {
    _bind();
  }

  /// The element the target belongs to: where its haptics find their scope
  /// and its actions their overrides.
  BuildContext get context;

  /// Whether [context] is still in the tree.
  bool get mounted;

  /// The clock that stamps the target's inputs.
  MotionClock get clock;

  /// The line that brings the target its pointers.
  PointerLine get line;

  /// Whether the target takes input now.
  bool get enabled;

  /// A position of the target's own coordinates in global ones.
  Offset toGlobal(Offset local);

  /// [input], given in the coordinates of the [line]'s box, in the
  /// target's own.
  InteractionInput local(InteractionInput input) => input;

  /// Sets or clears [state] where the target's states are kept.
  void write(WidgetState state, {required bool on});

  /// The haptic for [event], or null.
  MotionHaptic? feedback(InteractionEvent event);

  /// Which ways a value the target adjusts can move now.
  AdjustRange get range => AdjustRange.open;

  /// The target's centre in the coordinates of the [line]'s box: where a
  /// context menu asked for by a key opens.
  Offset get centre;

  /// The target's focus node, or null when it takes no focus.
  FocusNode? get focusNode => null;

  /// Whether [focusNode] may take focus now, the nodes around it aside.
  bool get focusable => false;

  /// How the device moves focus, when known.
  NavigationMode? get navigation => null;

  /// The actions the host adds to the target's own.
  Map<Type, Action<Intent>> get moreActions => const {};

  /// The interactions' session.
  InteractionSession session;

  List<Interaction> _interactions;

  /// The interactions. Other ones end the touches the target follows and
  /// start a new [session].
  List<Interaction> get interactions => _interactions;
  set interactions(List<Interaction> value) {
    if (listEquals(value, _interactions)) return;
    line.drop(this, PointerCancelReason.platform);
    _interactions = value;
    session = InteractionSession(value);
    _bind();
    _scheduleDue();
  }

  void _bind() {
    for (final interaction in _interactions) {
      interaction.bindRegion(toGlobal);
    }
  }

  /// Whether an interaction activates: Space, Enter and the accessibility
  /// tap reach the target.
  bool get activates => _interactions.any((i) => i.activates);

  /// Whether an interaction adjusts a value: the value keys and the
  /// accessibility increase and decrease reach the target.
  bool get adjusts => _interactions.any((i) => i.adjusts);

  /// Whether an interaction opens a context menu.
  bool get opensMenu => _interactions.any((i) => i.opensContextMenu);

  /// Whether an interaction takes the scroll wheel.
  bool get takesWheel => _interactions.any((i) => i.takesWheel);

  /// Whether an interaction takes pointers.
  bool get takesPointers => _interactions.any((i) => i.takesPointers);

  /// Whether an interaction contends with the controls inside the target.
  bool get contendsWithControls =>
      _interactions.any((i) => i.contendsWithControls);

  /// Whether the target takes a key: it [activates] or [adjusts].
  bool get acts => activates || adjusts;

  /// Carries out what the session made of an input: plays the events'
  /// haptics, writes pressed and dragged, and waits for the next timed
  /// reaction.
  void answer(SessionOutput output) {
    for (final event in output.events) {
      play(event);
    }
    if (mounted) {
      var pressed = false;
      var dragged = false;
      for (final interaction in _interactions) {
        pressed = pressed || interaction.pressed;
        dragged = dragged || interaction.dragged;
      }
      write(WidgetState.pressed, on: pressed);
      write(WidgetState.dragged, on: dragged);
    }
    _scheduleDue();
  }

  /// Plays the haptic the host picks for [event]; an activation by a key
  /// or by accessibility plays none.
  void play(InteractionEvent event) {
    if (event is ActivationEvent && event.source != ActivationSource.pointer) {
      return;
    }
    if (!mounted) return;
    final haptic = feedback(event);
    if (haptic != null) playHaptic(context, haptic);
  }

  /// Hands the session an input that is no touch (a key, an accessibility
  /// action, hover, the wheel), given in the coordinates of the [line]'s
  /// box, and answers it.
  void input(InteractionInput input) {
    if (!enabled) return;
    dispatchInput(
      input,
      () => clock.input(
        input.time,
        () => answer(session.handle(local(input))),
      ),
    );
  }

  /// Activates the target for a key or an accessibility tap.
  void activate(ActivationSource source) =>
      input(ActivateInput(time: clock.now, source: source));

  /// Steps the target's value for a key or an accessibility action.
  void adjust(ValueCommand command, ActivationSource source) => input(
    AdjustInput(time: clock.now, command: command, source: source),
  );

  /// Asks for the target's context menu at its [centre].
  void openMenu() => input(ContextMenuInput(time: clock.now, position: centre));

  bool _hovering = false;

  /// The mouse is over the target at [position], or left it.
  void hover(Offset position, {required bool inside}) {
    _hovering = inside;
    if (!mounted) return;
    write(WidgetState.hovered, on: inside);
    input(
      PointerHoverInput(time: clock.now, position: position, inside: inside),
    );
  }

  /// The target stopped taking input: its touches end, and what waited on
  /// the mouse resting over it (a dwell) hears the mouse leave, since a
  /// disabled target hears no more hover.
  void disable() {
    line.drop(this, PointerCancelReason.disabled);
    if (!_hovering) return;
    final time = clock.now;
    clock.input(
      time,
      () => answer(
        session.handle(
          PointerHoverInput(time: time, position: Offset.zero, inside: false),
        ),
      ),
    );
  }

  bool _hasFocus = false;

  /// Whether [focusNode] has the focus.
  bool get hasFocus => _hasFocus;
  set hasFocus(bool value) {
    _hasFocus = value;
    showFocus();
  }

  /// Writes the focused state: set while the focus should show.
  void showFocus() => write(
    WidgetState.focused,
    on: focusShows(
      hasFocus: _hasFocus,
      enabled: enabled,
      navigation: navigation,
    ),
  );

  late final Action<ActivateIntent> _activateAction =
      Action<ActivateIntent>.overridable(
        defaultAction: _Activate<ActivateIntent>(this),
        context: context,
      );

  late final Action<ButtonActivateIntent> _buttonAction =
      Action<ButtonActivateIntent>.overridable(
        defaultAction: _Activate<ButtonActivateIntent>(this),
        context: context,
      );

  late final Action<AdjustValueIntent> _adjustAction =
      Action<AdjustValueIntent>.overridable(
        defaultAction: _Adjust(this),
        context: context,
      );

  late final Action<ContextMenuIntent> _menuAction =
      Action<ContextMenuIntent>.overridable(
        defaultAction: _ContextMenu(this),
        context: context,
      );

  ({bool activates, bool adjusts, bool opensMenu})? _actionsFor;
  late Map<Type, Action<Intent>> _actions;

  /// The actions around the target's focus, the same map until what the
  /// interactions take changes.
  ///
  /// There is an action only for what an interaction takes. A registered
  /// action, even a disabled one, answers its intent for the focus below
  /// and overrides the overridable actions there: a target that takes no
  /// key, around a row of focusable parts, would take theirs.
  Map<Type, Action<Intent>> get actions {
    final takes = (
      activates: activates,
      adjusts: adjusts,
      opensMenu: opensMenu,
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
      ...moreActions,
    };
  }

  /// The keys the target binds around its focus: the value keys when it
  /// [adjusts], the context menu keys when it [opensMenu].
  Map<ShortcutActivator, Intent> shortcuts(TextDirection direction) {
    final adjust = adjusts
        ? AdjustValueIntent.defaultShortcuts(
            direction,
            navigation ?? NavigationMode.traditional,
          )
        : const <ShortcutActivator, Intent>{};
    if (!opensMenu) return adjust;
    return {...ContextMenuIntent.defaultShortcuts, ...adjust};
  }

  /// Writes what the target can do into its semantics node: enabled,
  /// focus, the tap of one that [activates], increase and decrease of one
  /// that [adjusts], as far as its [range] allows.
  void describe(SemanticsConfiguration config) {
    config.isEnabled = enabled;
    final node = focusNode;
    // From the host's word, not the node's: a Focus sets its node only
    // after the box was described for the frame that disables it.
    if (node != null &&
        focusable &&
        node.ancestors.every((ancestor) => ancestor.descendantsAreFocusable)) {
      config.isFocused = node.hasPrimaryFocus;
      // As Focus does: iOS takes no focus action (flutter/flutter#150030).
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        config.onFocus = node.requestFocus;
      }
    }
    if (!enabled) return;
    if (activates) {
      config.onTap = () => activate(ActivationSource.accessibility);
    }
    if (adjusts) {
      final range = this.range;
      if (range.canIncrease) {
        config.onIncrease = () =>
            adjust(ValueCommand.increase, ActivationSource.accessibility);
      }
      if (range.canDecrease) {
        config.onDecrease = () =>
            adjust(ValueCommand.decrease, ActivationSource.accessibility);
      }
    }
  }

  double? _scheduled;
  VoidCallback? _cancelDue;

  void _scheduleDue() {
    final due = session.nextDue;
    if (due == _scheduled) return;
    _cancelDue?.call();
    _cancelDue = null;
    _scheduled = due;
    if (due == null) return;
    _cancelDue = clock.schedule(due, (time) {
      _scheduled = null;
      _cancelDue = null;
      if (!mounted) return;
      clock.input(time, () => line.due(this, session.advance(time)));
    });
  }

  /// Ends the target's touches and its timed reactions.
  void dispose() {
    line.drop(this, PointerCancelReason.platform);
    _cancelDue?.call();
    _cancelDue = null;
  }
}

class _Activate<I extends Intent> extends HostAction<I> {
  _Activate(this.target);

  final InputTarget target;

  @override
  bool takes(I intent) => target.enabled && target.activates;

  @override
  bool get focused => target.focusNode?.hasPrimaryFocus ?? false;

  @override
  void run(I intent) => target.activate(ActivationSource.keyboard);
}

class _Adjust extends HostAction<AdjustValueIntent> {
  _Adjust(this.target);

  final InputTarget target;

  @override
  bool takes(AdjustValueIntent intent) =>
      target.enabled && target.adjusts && target.range.allows(intent.command);

  @override
  bool get focused => true;

  @override
  void run(AdjustValueIntent intent) =>
      target.adjust(intent.command, ActivationSource.keyboard);
}

class _ContextMenu extends HostAction<ContextMenuIntent> {
  _ContextMenu(this.target);

  final InputTarget target;

  @override
  bool takes(ContextMenuIntent intent) => target.enabled && target.opensMenu;

  @override
  bool get focused => target.focusNode?.hasPrimaryFocus ?? false;

  @override
  void run(ContextMenuIntent intent) => target.openMenu();
}

final class _Touch {
  _Touch(this.down, this.tracker);

  // In the coordinates of the line's box.
  final PointerDownInput down;

  // Null for a touch another region handed on: its release brings its own
  // velocity.
  final VelocityTracker? tracker;

  // Null while only observers hear the touch, and for a touch handed on.
  InputArenaMember? member;

  // The input the pointer's route hands the targets for the event being
  // dispatched, made as the event reached the box.
  InteractionInput? routed;

  InputTarget? base;
  InputTarget? part;
  bool baseContends = false;
  bool partContends = false;

  int get pointer => down.pointer;

  bool get contended => baseContends || partContends;

  bool contends(InputTarget target) => identical(target, base)
      ? baseContends
      : identical(target, part) && partContends;

  // Whether target contended until now.
  bool gaveUp(InputTarget target) {
    if (identical(target, base) && baseContends) {
      baseContends = false;
      return true;
    }
    if (identical(target, part) && partContends) {
      partContends = false;
      return true;
    }
    return false;
  }
}

/// The pointers of one render box: turns its pointer events into stamped
/// inputs, keeps the box in the gesture arena, and hands every input to the
/// targets on the touch.
///
/// A touch has up to two targets: the [base], which hears every touch on
/// the box, and the part under the finger ([partAt]). `InputRegion` has
/// only a base; in an `InputZones` the parts are the zones and the base is
/// the host's own interactions.
///
/// An interaction of the observer role hears an event as it reaches the
/// box, as a `Listener` does. The others hear it on the pointer's route,
/// where Flutter's recognizers hear it, after the recognizers inside the
/// box: a scroll view inside that passes its slop on the same event takes
/// the touch first, as it would from a recognizer around it. The box stays
/// in the arena for a pointer while a target contends for it, and takes it
/// when one claims.
@internal
abstract class PointerLine {
  final Map<int, _Touch> _touches = {};
  final PointerSpeed _speed = PointerSpeed();
  InputPort? _port;

  /// The element of the box.
  BuildContext get context;

  /// Whether [context] is still in the tree.
  bool get mounted;

  /// The clock that stamps the events.
  MotionClock get clock;

  /// The box whose events these are.
  RenderBox? get box;

  /// The area the box takes pointers in when it is larger than the box.
  Rect? get hitArea => null;

  /// The target that hears every touch on the box.
  InputTarget get base;

  /// The part that takes input at [position], or null.
  InputTarget? partAt(Offset position) => null;

  /// Whether a finger slides from part to part: the touch stays in the
  /// arena with no part under it, and moves on to the part it comes over.
  bool get slides => false;

  /// A sliding finger came onto [part], at the down or in a move.
  void slidOnto(InputTarget part, double time, {required bool atDown}) {}

  /// Where touches handed on from another region arrive, or null. It
  /// attaches after the current frame ([attachPortAfterFrame]).
  InputPort? get port => _port;
  set port(InputPort? value) {
    if (identical(value, _port)) return;
    _port?.detach(_receive);
    _port = value;
    attachPortAfterFrame(
      value,
      _receive,
      () => mounted && identical(_port, value),
    );
  }

  /// Lets go of the port.
  void dispose() {
    _port?.detach(_receive);
    _port = null;
  }

  void _receive(PortEvent event) {
    final box = this.box;
    if (box == null || !box.hasSize) return;
    final input = event.input(
      box.globalToLocal,
      size: box.size,
      hitArea: hitArea,
      scrollAxes: event.handOff ? scrollAxesAround(context) : const {},
      contested: ContestScope.of(context, listen: false),
    );
    clock.input(input.time, () {
      switch (input) {
        case PointerDownInput():
          _begin(input, arena: false);
        case PointerMoveInput(:final pointer) ||
            PointerUpInput(:final pointer) ||
            PointerCancelInput(:final pointer):
          final touch = _touches[pointer];
          if (touch == null) return;
          _observe(touch, input);
          _track(touch, input);
        case PointerAcceptedInput() ||
            PointerHoverInput() ||
            PointerScrollInput() ||
            ActivateInput() ||
            AdjustInput() ||
            ContextMenuInput():
          break;
      }
    });
  }

  /// Takes a pointer event of the box: a down, an event of a touch the
  /// line follows, or the wheel.
  void pointer(PointerEvent event) {
    switch (event) {
      case PointerScrollEvent():
        _wheel(event);
      case PointerDownEvent():
      case _ when _touches.containsKey(event.pointer):
        final time = clock.stamp(event.timeStamp);
        clock.input(time, () => _heard(event, time));
      default:
        break;
    }
  }

  void _wheel(PointerScrollEvent event) {
    final base = this.base;
    final target = switch (partAt(event.localPosition)) {
      final part? when part.takesWheel => part,
      _ when base.enabled && base.takesWheel => base,
      _ => null,
    };
    if (target == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!target.mounted || event is! PointerScrollEvent) return;
      target.input(
        PointerScrollInput(
          time: clock.stamp(event.timeStamp),
          position: event.localPosition,
          scrollDelta: event.scrollDelta,
          kind: event.kind,
        ),
      );
    });
  }

  void _heard(PointerEvent event, double time) {
    if (event is PointerDownEvent) {
      final box = this.box;
      if (box == null || !box.hasSize) return;
      _speed.touched(event.timeStamp);
      final tracker = VelocityTracker.withKind(event.kind);
      tracker.addPosition(event.timeStamp, event.localPosition);
      _begin(
        PointerDownInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          regionSize: box.size,
          hitArea: hitArea,
          globalPosition: event.position,
          kind: event.kind,
          buttons: event.buttons,
          scrollAxes: scrollAxesAround(context),
          contested: ContestScope.of(context, listen: false),
        ),
        arena: true,
        tracker: tracker,
      );
      return;
    }
    final touch = _touches[event.pointer];
    if (touch == null) return;
    final InteractionInput input;
    switch (event) {
      case PointerMoveEvent():
        touch.tracker?.addPosition(event.timeStamp, event.localPosition);
        if (mounted) _speed.moved(event, View.of(context).devicePixelRatio);
        input = PointerMoveInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          globalPosition: event.position,
        );
      case PointerUpEvent():
        _speed.lifted();
        touch.tracker?.addPosition(event.timeStamp, event.localPosition);
        final velocity =
            touch.tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
        input = PointerUpInput(
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
        );
      case PointerCancelEvent():
        input = PointerCancelInput(
          time: time,
          pointer: event.pointer,
          reason: PointerCancelReason.platform,
        );
      default:
        return;
    }
    _observe(touch, input);
    if (touch.member != null) {
      touch.routed = input;
    } else if (input is! PointerMoveInput) {
      _touches.remove(touch.pointer);
    }
  }

  void _begin(
    PointerDownInput down, {
    required bool arena,
    VelocityTracker? tracker,
  }) {
    final pointer = down.pointer;
    if (_touches.containsKey(pointer)) return;
    final base = this.base.enabled ? this.base : null;
    final part = partAt(down.position);
    final touch = _Touch(down, tracker);
    // Both hear the down before either is answered: a target that takes
    // nothing must not give up a touch the other takes.
    final baseAsked = base == null ? null : _ask(base, down);
    if (base != null && baseAsked != null) {
      touch.baseContends = !baseAsked.tracked.reject;
      if (touch.baseContends || base.session.observes(pointer)) {
        touch.base = base;
      }
    }
    final partAsked = part == null ? null : _ask(part, down);
    if (part != null && partAsked != null) {
      touch.partContends = !partAsked.tracked.reject;
      if (touch.partContends || part.session.observes(pointer)) {
        touch.part = part;
      }
    }
    if (touch.base != null || touch.part != null || slides) {
      _touches[pointer] = touch;
      if (arena && (touch.contended || slides)) {
        final member = InputArenaMember(_lost, onAccepted: _accepted);
        touch.member = member;
        member.entry = GestureBinding.instance.gestureArena.add(
          pointer,
          member,
        );
        GestureBinding.instance.pointerRouter.addRoute(pointer, _route);
      }
    }
    if (base != null && baseAsked != null) {
      base.answer(baseAsked.observed);
      _settle(touch, base, baseAsked.tracked);
    }
    if (part != null && partAsked != null) {
      part.answer(partAsked.observed);
      if (slides && touch.partContends) {
        slidOnto(part, down.time, atDown: true);
      }
      _settle(touch, part, partAsked.tracked);
    }
  }

  static ({SessionOutput observed, SessionOutput tracked}) _ask(
    InputTarget target,
    PointerDownInput down,
  ) {
    final at = target.local(down);
    return (
      observed: target.session.observe(at),
      tracked: target.session.track(at),
    );
  }

  void _observe(_Touch touch, InteractionInput input) {
    final pointer = touch.pointer;
    if (touch.base case final base? when base.session.observes(pointer)) {
      base.answer(base.session.observe(base.local(input)));
    }
    if (touch.part case final part? when part.session.observes(pointer)) {
      part.answer(part.session.observe(part.local(input)));
    }
  }

  void _route(PointerEvent event) {
    final touch = _touches[event.pointer];
    final input = touch?.routed;
    if (touch == null || input == null) return;
    touch.routed = null;
    clock.input(input.time, () => _track(touch, input));
  }

  void _track(_Touch touch, InteractionInput input) {
    switch (input) {
      case PointerMoveInput():
        if (touch.base case final base?) {
          _settle(touch, base, base.session.track(base.local(input)));
        }
        if (slides) {
          final under = partAt(input.position);
          if (under != null && !identical(under, touch.part)) {
            _handOver(touch, input, under);
            return;
          }
        }
        if (touch.part case final part?) {
          _settle(touch, part, part.session.track(part.local(input)));
        }
      case PointerUpInput() || PointerCancelInput():
        if (touch.base case final base?) {
          _settle(touch, base, base.session.track(base.local(input)));
        }
        if (touch.part case final part?) {
          _settle(touch, part, part.session.track(part.local(input)));
        }
        if (identical(_touches[touch.pointer], touch)) {
          _touches.remove(touch.pointer);
        }
        _leave(touch);
      case PointerDownInput() ||
          PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        break;
    }
  }

  void _handOver(_Touch touch, PointerMoveInput move, InputTarget to) {
    final from = touch.part;
    touch.part = null;
    touch.partContends = false;
    if (from != null) {
      from.answer(
        from.session.handle(
          PointerCancelInput(
            time: move.time,
            pointer: touch.pointer,
            reason: PointerCancelReason.taken,
          ),
        ),
      );
    }
    final down = touch.down;
    final output = to.session.handle(
      to.local(
        PointerDownInput(
          time: move.time,
          pointer: touch.pointer,
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
      to.answer(output);
      return;
    }
    touch.part = to;
    touch.partContends = true;
    slidOnto(to, move.time, atDown: false);
    _settle(touch, to, output);
  }

  // Acts on what a target made of an input of the touch: a claim takes the
  // pointer in the arena, and the box leaves the arena when the last
  // target that contended gives the touch up.
  void _settle(_Touch touch, InputTarget target, SessionOutput output) {
    if (output.claim) {
      touch.member?.entry?.resolve(GestureDisposition.accepted);
    }
    if (output.reject && touch.gaveUp(target) && !touch.contended && !slides) {
      touch.member?.entry?.resolve(GestureDisposition.rejected);
    }
    target.answer(output);
  }

  // The box is out of the gesture arena for the touch.
  void _leave(_Touch touch) {
    if (touch.member == null) return;
    touch.member = null;
    touch.routed = null;
    GestureBinding.instance.pointerRouter.removeRoute(touch.pointer, _route);
  }

  void _accepted(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.member == null) return;
    final time = clock.now;
    final input = PointerAcceptedInput(time: time, pointer: pointer);
    clock.input(time, () {
      if (touch.base case final base?) {
        _settle(touch, base, base.session.handle(input));
      }
      if (touch.part case final part?) {
        _settle(touch, part, part.session.handle(input));
      }
    });
  }

  void _lost(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.member == null) return;
    _leave(touch);
    final base = touch.base;
    final part = touch.part;
    touch.baseContends = false;
    touch.partContends = false;
    // Observers keep hearing a touch another gesture took.
    if (base != null && !base.session.observes(pointer)) touch.base = null;
    if (part != null && !part.session.observes(pointer)) touch.part = null;
    if (touch.base == null && touch.part == null) _touches.remove(pointer);
    final time = clock.now;
    base?.answer(base.session.lost(pointer, time));
    part?.answer(part.session.lost(pointer, time));
  }

  /// Ends every touch [target] is on, for it alone: it hears a cancel for
  /// [reason], and the box leaves the arena for a touch nothing else
  /// contends for.
  void drop(InputTarget target, PointerCancelReason reason) {
    for (final touch in _touches.values.toList()) {
      if (identical(touch.base, target)) {
        touch.base = null;
        touch.baseContends = false;
      } else if (identical(touch.part, target)) {
        touch.part = null;
        touch.partContends = false;
      } else {
        continue;
      }
      if (!touch.contended && !slides) {
        final entry = touch.member?.entry;
        _leave(touch);
        entry?.resolve(GestureDisposition.rejected);
        if (touch.base == null && touch.part == null) {
          _touches.remove(touch.pointer);
        }
      }
      target.answer(
        target.session.handle(
          PointerCancelInput(
            time: clock.now,
            pointer: touch.pointer,
            reason: reason,
          ),
        ),
      );
    }
  }

  /// Acts on what a timed reaction of [target] made, for the touch it
  /// contends for when there is one: a hold that comes due claims the
  /// pointer.
  void due(InputTarget target, SessionOutput output) {
    for (final touch in _touches.values) {
      if (!touch.contends(target)) continue;
      _settle(touch, target, output);
      return;
    }
    target.answer(output);
  }
}

/// Attaches [receiver] to [port] after the current frame, while [stillWanted]
/// holds.
///
/// The receiver maps positions with its render box, laid out in the frame
/// that builds it, and the touches that waited run interactions that may
/// rebuild or lay out, which that frame's layout and resolve phases do not
/// allow. The clock's coming phases can run before that layout when the host
/// is built outside a frame, so the port attaches after the frame.
@internal
void attachPortAfterFrame(
  InputPort? port,
  void Function(PortEvent event) receiver,
  bool Function() stillWanted,
) {
  if (port == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (stillWanted()) port.attach(receiver);
  });
}
