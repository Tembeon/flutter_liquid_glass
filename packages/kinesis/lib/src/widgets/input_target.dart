import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/haptics.dart';
import 'package:kinesis/src/widgets/input_intents.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/keyboard_use.dart';
import 'package:kinesis/src/widgets/pointer_line.dart';

/// One thing a person acts on, as an input host keeps it: a session of
/// interactions with its keys, its states, its haptics and its timed
/// reactions.
///
/// `InputRegion` hosts one; each zone of an `InputZones` is one, and so is
/// the box of the zones itself. A host says where its target is and, at
/// each build, what it may do now ([update]); what a target does with an
/// input is the same in every host. Its pointers reach it through its
/// [line].
@internal
abstract class InputTarget {
  /// Creates a target over [interactions], as [update] describes.
  InputTarget(
    List<Interaction> interactions, {
    this._enabled = true,
    this._adjustRange,
  }) : _interactions = interactions,
       _takes = _takesOf(interactions),
       session = InteractionSession(interactions) {
    _adjustRange?.addListener(rangeChanged);
  }

  static Set<InputKind> _takesOf(List<Interaction> interactions) =>
      Set.unmodifiable({
        for (final interaction in interactions) ...interaction.takes,
      });

  /// The element the target belongs to: where its haptics find their scope
  /// and its actions their overrides.
  BuildContext get context;

  /// Whether [context] is still in the tree.
  bool get mounted;

  /// The clock that stamps the target's inputs.
  MotionClock get clock;

  /// The line that brings the target its pointers.
  PointerLine<InputTarget> get line;

  bool _enabled;

  /// Whether the target takes input now.
  bool get enabled => _enabled;

  ValueListenable<AdjustRange>? _adjustRange;

  /// Takes what the host says at a build, in this order: other
  /// [interactions] end the touches the target follows
  /// ([PointerCancelReason.platform]) and start a new [session]; then a
  /// change of [enabled] ends them ([PointerCancelReason.disabled]), or
  /// hovers a mouse resting over the target; then another [adjustRange] is
  /// heard instead of the last.
  void update({
    required List<Interaction> interactions,
    bool enabled = true,
    ValueListenable<AdjustRange>? adjustRange,
  }) {
    if (!listEquals(interactions, _interactions)) {
      line.drop(this, PointerCancelReason.platform);
      _interactions = interactions;
      final takes = _takesOf(interactions);
      if (!setEquals(takes, _takes)) _takes = takes;
      session = InteractionSession(interactions);
      _scheduleDue();
    }
    if (enabled != _enabled) {
      _enabled = enabled;
      enabled ? _enable() : _disable();
    }
    if (adjustRange != _adjustRange) {
      _adjustRange?.removeListener(rangeChanged);
      _adjustRange = adjustRange;
      adjustRange?.addListener(rangeChanged);
      rangeChanged();
    }
  }

  /// [input], given in the coordinates of the [line]'s box, in the
  /// target's own.
  InteractionInput local(InteractionInput input) => input;

  /// Writes the target's states where its host keeps them: what the host
  /// says of it with its [inputStates].
  void publish();

  /// The haptic for [event], or null.
  MotionHaptic? feedback(InteractionEvent event);

  /// Which ways a value the target adjusts can move now.
  AdjustRange get range => _adjustRange?.value ?? AdjustRange.open;

  /// Called when [range] may have changed: the host describes the target's
  /// semantics again.
  @protected
  void rangeChanged() {}

  /// The target's centre in the coordinates of the [line]'s box: where a
  /// context menu asked for by a key opens; by default the box's centre.
  Offset get centre => switch (line.box) {
    final box? when box.hasSize => box.size.center(Offset.zero),
    _ => Offset.zero,
  };

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

  Set<InputKind> _takes;

  /// What the interactions take together ([Interaction.takes]): the same
  /// set until that changes.
  Set<InputKind> get takes => _takes;

  /// Whether the target takes a key: [InputKind.activation] or
  /// [InputKind.adjustment].
  bool get acts =>
      _takes.contains(InputKind.activation) ||
      _takes.contains(InputKind.adjustment);

  /// Whether focus traversal passes the target by: it takes no key.
  bool get skipsTraversal => !acts;

  /// The cursor [given] resolves to in [states]; by default the adaptive
  /// click cursor when the target [acts], the cursor of what lies below
  /// otherwise.
  MouseCursor cursor(MouseCursor? given, Set<WidgetState> states) =>
      WidgetStateProperty.resolveAs<MouseCursor>(
        given ??
            (acts
                ? WidgetStateMouseCursor.adaptiveClickable
                : MouseCursor.defer),
        states,
      );

  /// Whether the touches of the controls inside the target start contested
  /// ([PointerDownInput.contested]): a host around contends with them, or an
  /// interaction of the target does. Read in a build, it makes [context]
  /// depend on the host around.
  bool get contestsBelow =>
      ContestScope.of(context) ||
      _interactions.any((i) => i.contendsWithControls);

  /// Carries out what the session made of an input: plays the events'
  /// haptics, publishes pressed and dragged, and waits for the next timed
  /// reaction.
  void answer(SessionOutput output) {
    for (final event in output.events) {
      play(event);
    }
    if (mounted) {
      _pressed = _interactions.any((i) => i.pressed);
      _dragged = _interactions.any((i) => i.dragged);
      publish();
    }
    _scheduleDue();
  }

  bool _pressed = false;
  bool _dragged = false;

  /// The states input keeps of the target.
  Set<WidgetState> get inputStates => {
    if (_pressed) WidgetState.pressed,
    if (_dragged) WidgetState.dragged,
    if (_hovering) WidgetState.hovered,
    if (_hasFocus && KeyboardUse.inUse) WidgetState.focused,
  };

  /// Plays the haptic the host picks for [event]; none while a key or
  /// accessibility input is dispatched (`gestureInput`).
  void play(InteractionEvent event) {
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

  Offset? _mouseAt;

  /// Whether the mouse is over the target, taking input or not.
  bool get mouseOver => _mouseAt != null;

  /// The mouse is over the target at [position], or left it, as an event
  /// stamped [timeStamp] says; a hover the target makes itself has none
  /// and comes at the clock's time.
  void hover(Offset position, {required bool inside, Duration? timeStamp}) {
    _mouseAt = inside ? position : null;
    if (!enabled) return;
    _hovering = inside;
    if (!mounted) return;
    publish();
    final time = timeStamp == null ? clock.now : clock.stamp(timeStamp);
    input(PointerHoverInput(time: time, position: position, inside: inside));
  }

  void _enable() {
    if (_mouseAt == null) return;
    // After the frame: hover publishes states this frame's builds read, and
    // Flutter's mouse tracker enters a region a frame adds then too.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_mouseAt case final position? when !_hovering && enabled) {
        hover(position, inside: true);
      }
    });
  }

  // A disabled target hears no more hover: what waited on the mouse resting
  // over it (a dwell) hears the mouse leave now.
  void _disable() {
    line.drop(this, PointerCancelReason.disabled);
    if (!_hovering) return;
    _hovering = false;
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
    publish();
  }

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

  Set<InputKind>? _actionsFor;
  late Map<Type, Action<Intent>> _actions;

  /// The actions around the target's focus, the same map until what the
  /// interactions take changes.
  ///
  /// There is an action only for what an interaction takes. A registered
  /// action, even a disabled one, answers its intent for the focus below
  /// and overrides the overridable actions there: a target that takes no
  /// key, around a row of focusable parts, would take theirs.
  Map<Type, Action<Intent>> get actions {
    if (identical(_takes, _actionsFor)) return _actions;
    _actionsFor = _takes;
    return _actions = {
      if (_takes.contains(InputKind.activation)) ...{
        ActivateIntent: _activateAction,
        ButtonActivateIntent: _buttonAction,
      },
      if (_takes.contains(InputKind.adjustment))
        AdjustValueIntent: _adjustAction,
      if (_takes.contains(InputKind.contextMenu))
        ContextMenuIntent: _menuAction,
      ...moreActions,
    };
  }

  /// The keys the target binds around its focus: the value keys when it
  /// takes [InputKind.adjustment], the context menu keys when it takes
  /// [InputKind.contextMenu].
  Map<ShortcutActivator, Intent> shortcuts(TextDirection direction) {
    final adjust = _takes.contains(InputKind.adjustment)
        ? AdjustValueIntent.defaultShortcuts(
            direction,
            navigation ?? NavigationMode.traditional,
          )
        : const <ShortcutActivator, Intent>{};
    if (!_takes.contains(InputKind.contextMenu)) return adjust;
    return {...ContextMenuIntent.defaultShortcuts, ...adjust};
  }

  /// Writes what the target can do into its semantics node: enabled,
  /// focus, the tap of one that takes [InputKind.activation], increase and
  /// decrease of one that takes [InputKind.adjustment], as far as its
  /// [range] allows.
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
    if (_takes.contains(InputKind.activation)) {
      config.onTap = () => activate(ActivationSource.accessibility);
    }
    if (_takes.contains(InputKind.adjustment)) {
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

  /// Ends the target's touches and its timed reactions, and stops hearing
  /// its range.
  void dispose() {
    _adjustRange?.removeListener(rangeChanged);
    line.drop(this, PointerCancelReason.platform);
    _cancelDue?.call();
    _cancelDue = null;
  }
}

class _Activate<I extends Intent> extends _HostAction<I> {
  _Activate(super.target);

  @override
  bool takes(I intent) =>
      target.enabled && target.takes.contains(InputKind.activation);

  @override
  void run(I intent) => target.activate(ActivationSource.keyboard);
}

class _Adjust extends _HostAction<AdjustValueIntent> {
  _Adjust(super.target);

  @override
  bool takes(AdjustValueIntent intent) =>
      target.enabled &&
      target.takes.contains(InputKind.adjustment) &&
      target.range.allows(intent.command);

  @override
  void run(AdjustValueIntent intent) =>
      target.adjust(intent.command, ActivationSource.keyboard);
}

class _ContextMenu extends _HostAction<ContextMenuIntent> {
  _ContextMenu(super.target);

  @override
  bool takes(ContextMenuIntent intent) =>
      target.enabled && target.takes.contains(InputKind.contextMenu);

  @override
  void run(ContextMenuIntent intent) => target.openMenu();

  // The menu of a host is for all it holds: from a focused part inside it
  // that has no menu of its own, the key opens the host's.
  @override
  bool get answersWithin => true;
}

/// An input host's own action for an intent of the focused host: a
/// region's or a zone's activation.
///
/// Hosts register their actions as `Action.overridable`, so the lookup of
/// an inner host's override finds the action of the host around it. Such an
/// action, reached as the override of another host's, hands the intent
/// back to that host; reached first, it answers only while its own focus
/// node has the primary focus, or, when it [answersWithin], while the focus
/// is anywhere inside it. The focused, innermost host that takes the intent
/// handles it, and a host around it handles it only when it is focused
/// itself, or holds the focus and [answersWithin].
abstract class _HostAction<I extends Intent> extends Action<I> {
  _HostAction(this.target);

  final InputTarget target;

  /// Whether the host takes the intent now: it is enabled and one of its
  /// interactions takes it.
  bool takes(I intent);

  /// Runs the intent on the host.
  void run(I intent);

  /// Whether the host answers for the focus anywhere inside it, not only
  /// for its own.
  bool get answersWithin => false;

  _HostAction<I>? get _inner => switch (callingAction) {
    final _HostAction<I> inner => inner,
    _ => null,
  };

  @override
  bool isEnabled(I intent) {
    if (_inner case final inner?) return inner.isEnabled(intent);
    final node = target.focusNode;
    final focused = answersWithin ? node?.hasFocus : node?.hasPrimaryFocus;
    return (focused ?? false) && takes(intent);
  }

  @override
  Object? invoke(I intent) {
    if (_inner case final inner?) return inner.invoke(intent);
    run(intent);
    return null;
  }
}
