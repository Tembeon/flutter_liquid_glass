import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/raw/still.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/widgets.dart';

/// A half of a stepper.
enum GlassStepperHalf {
  /// The minus half: on the left, on the right in a right-to-left context.
  decrement,

  /// The plus half: on the right, on the left in a right-to-left context.
  increment;

  /// Where this half lies in a stepper's [box] laid out in [direction].
  Rect rectIn(Rect box, TextDirection direction) {
    final width = box.width / 2;
    final leading =
        (this == GlassStepperHalf.decrement) ==
        (direction == TextDirection.ltr);
    return Rect.fromLTWH(
      leading ? box.left : box.left + width,
      box.top,
      width,
      box.height,
    );
  }
}

/// Builds a glass stepper from [details]; it runs again when the held half
/// or the states change.
typedef GlassStepperBuilder = Widget Function(
  BuildContext context,
  GlassStepperDetails details,
);

/// What a [GlassStepperBuilder] builds a stepper from.
@immutable
final class GlassStepperDetails {
  /// Describes a stepper.
  const GlassStepperDetails({
    required this.pressed,
    required this.canDecrement,
    required this.canIncrement,
    required this.states,
    this.statesListenable,
  });

  /// The half a finger holds, or null.
  final GlassStepperHalf? pressed;

  /// Whether a step down stays at or above the minimum.
  final bool canDecrement;

  /// Whether a step up stays at or below the maximum.
  final bool canIncrement;

  /// The states the stepper is in.
  final Set<WidgetState> states;

  /// The stepper's states as they change, or null for a look that shows
  /// neither focus nor hover: a builder hands it to the `GlassSurface` of
  /// the halves, whose renderer then draws the focus ring and the hover
  /// response.
  final ValueListenable<Set<WidgetState>>? statesListenable;
}

/// A stepper with the behavior of iOS 27's `UIStepper` and no look of its own:
/// [builder] decides how it looks.
///
/// UIKit: `UIStepper`. SwiftUI: `Stepper`. Flutter: none.
///
/// There is no motion: a held half highlights at once and clears on release. A
/// tap commits on release. A held half repeats on a clock that starts with the
/// touch: every half second for the first six steps, every tenth of a second
/// up to the twentieth, then every twentieth (stepper passport: 0.520, 1.021,
/// 1.522 s after the touch on the device, the faster steps on the
/// simulator). A repeat steps only while the finger is on a half's own box
/// and the step is allowed; one that finds it elsewhere steps nothing and
/// slows the clock back to half a second, without restarting it. Sliding to
/// the other half moves the highlight and the repeat with it without a step.
/// Leaving the control's 44 point tall target, which reaches above and below
/// its 32 point box where its parent leaves that room, drops the highlight but
/// keeps the touch: coming back takes it up again, and a release outside
/// changes nothing. A release after a repeat adds no step.
///
/// A step that would cross [min] or [max] is refused, not clamped, so with a
/// fractional [step] a half disables before the value reaches its limit. The
/// halves swap in a right-to-left context, minus on the right (stepper
/// passport, trait and real locale), and the arrow keys follow them: the arrow
/// toward plus increments, as up does. Home and End take the value to [min]
/// and [max]; the stepper has no larger step, so Page Up and Page Down do
/// nothing, and neither do Space and Enter, as on Flutter's `Slider`. The
/// stepper is one Tab stop; its halves are zones that are not focus targets.
/// Screen readers see two buttons with 44 point targets that announce the value
/// and run the same commands as the keys, inside one adjustable node with the
/// value and the accessibility increase and decrease. A disabled stepper
/// ignores input; [builder] sees [WidgetState.disabled].
class RawGlassStepper extends StatefulWidget {
  /// Creates a stepper showing [value] between [min] and [max].
  const RawGlassStepper({
    required this.value,
    required this.onChanged,
    required this.builder,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.decrementLabel,
    this.incrementLabel,
    this.semanticFormatterCallback,
    this.semanticLabel,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The value.
  final double value;

  /// Called with the new value when the user steps; null disables the
  /// stepper.
  final ValueChanged<double>? onChanged;

  /// Builds the stepper's look.
  final GlassStepperBuilder builder;

  /// The lowest value.
  final double min;

  /// The highest value.
  final double max;

  /// How much one step changes the value; greater than zero.
  final double step;

  /// What screen readers announce for the minus half; null reads
  /// [GlassLocalizations.decrementLabel].
  final String? decrementLabel;

  /// What screen readers announce for the plus half; null reads
  /// [GlassLocalizations.incrementLabel].
  final String? incrementLabel;

  /// Formats the value each half announces; null uses up to twelve
  /// significant digits without binary floating-point tails.
  final String Function(double value)? semanticFormatterCallback;

  /// What accessibility reads for the stepper.
  final String? semanticLabel;

  /// Where the stepper publishes its states, or null for its own. The
  /// stepper is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The stepper's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the stepper takes focus when it first appears.
  final bool autofocus;

  /// The size of the stepper (stepper passport, device).
  static const Size size = Size(94, 32);

  @override
  State<RawGlassStepper> createState() => _RawGlassStepperState();
}

class _RawGlassStepperState extends State<RawGlassStepper>
    with ControlStates<RawGlassStepper> {
  late final _StepperInput _input = _StepperInput(
    onPressed: (half) => setState(() => _pressed = half),
    canStep: _canStep,
    onStep: _stepBy,
    onCommand: _command,
  );
  late final List<Interaction> _interactions = [_input];
  late final Map<GlassStepperHalf, Interaction> _halfInputs = {
    for (final half in GlassStepperHalf.values)
      half: CommandInteraction(
        role: InteractionRole.control,
        onActivate: (_) => _halfActivated(half),
      ),
  };
  final GlobalKey _halves = GlobalKey();
  GlassStepperHalf? _pressed;

  @override
  WidgetStatesController? get statesController => widget.statesController;

  bool get enabled => widget.onChanged != null;

  double get _minimum => widget.min.isFinite ? widget.min : 0;

  double get _maximum =>
      widget.max.isFinite && widget.max >= _minimum ? widget.max : _minimum;

  double get _value =>
      widget.value.isFinite ? widget.value.clamp(_minimum, _maximum) : _minimum;

  double get _step => widget.step.isFinite && widget.step > 0 ? widget.step : 0;

  // A step lands within the range up to rounding: 0.9 + 0.1 reaches a
  // maximum of 1.
  bool _canStep(GlassStepperHalf half) {
    final step = _step;
    if (step == 0) return false;
    final slack = step * 1e-9;
    return switch (half) {
      GlassStepperHalf.decrement => _value - step >= _minimum - slack,
      GlassStepperHalf.increment => _value + step <= _maximum + slack,
    };
  }

  double _after(GlassStepperHalf half) {
    if (!_canStep(half)) return _value;
    final delta = half == GlassStepperHalf.increment ? _step : -_step;
    return (_value + delta).clamp(_minimum, _maximum);
  }

  void _stepBy(GlassStepperHalf half) {
    final next = _after(half);
    if (next != _value) widget.onChanged?.call(next);
  }

  void _command(ValueCommand command) {
    switch (command) {
      case ValueCommand.increase:
        _stepBy(GlassStepperHalf.increment);
      case ValueCommand.decrease:
        _stepBy(GlassStepperHalf.decrement);
      case ValueCommand.toMinimum:
        if (_value > _minimum) widget.onChanged?.call(_minimum);
      case ValueCommand.toMaximum:
        if (_value < _maximum) widget.onChanged?.call(_maximum);
      case ValueCommand.increaseLarge || ValueCommand.decreaseLarge:
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = GlassLocalizations.of(context);
    String format(double value) =>
        widget.semanticFormatterCallback?.call(value) ?? _format(value);
    final value = format(_value);
    InputZone<GlassStepperHalf> half(GlassStepperHalf half, String label) =>
        InputZone(
          id: half,
          interactions: [_halfInputs[half]!],
          enabled: enabled && _canStep(half),
          focusable: false,
          reach: glassTargetReach,
          semantics: SemanticsProperties(
            label: label,
            value: value,
            button: true,
          ),
        );
    final direction = Directionality.of(context);
    return InputRegion(
      interactions: _interactions,
      enabled: enabled,
      statesController: widgetStates,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      semantics: SemanticsProperties(
        label: widget.semanticLabel,
        value: value,
        increasedValue: format(_after(GlassStepperHalf.increment)),
        decreasedValue: format(_after(GlassStepperHalf.decrement)),
      ),
      reach: glassTargetReach,
      child: SizedBox.fromSize(
        size: RawGlassStepper.size,
        child: InputZones<GlassStepperHalf>(
          key: _halves,
          zones: [
            half(
              GlassStepperHalf.decrement,
              widget.decrementLabel ?? strings.decrementLabel,
            ),
            half(
              GlassStepperHalf.increment,
              widget.incrementLabel ?? strings.incrementLabel,
            ),
          ],
          frameOf: (half) => InputZoneFrame(
            half.rectIn(Offset.zero & RawGlassStepper.size, direction),
          ),
          frames: still,
          child: withStates(
            (context, states) => widget.builder(
              context,
              GlassStepperDetails(
                pressed: _pressed,
                canDecrement: _canStep(GlassStepperHalf.decrement),
                canIncrement: _canStep(GlassStepperHalf.increment),
                states: states,
                statesListenable: widgetStates,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A half's button runs the stepper's own command through the actions
  // above the halves, so an app that overrides AdjustValueIntent hears it.
  void _halfActivated(GlassStepperHalf half) {
    final context = _halves.currentContext;
    if (context == null) return;
    Actions.maybeInvoke(
      context,
      AdjustValueIntent(switch (half) {
        GlassStepperHalf.decrement => ValueCommand.decrease,
        GlassStepperHalf.increment => ValueCommand.increase,
      }),
    );
  }

  static String _format(double value) {
    final digits = value.toStringAsPrecision(12);
    final number = double.parse(digits);
    return number == number.truncateToDouble()
        ? number.toInt().toString()
        : number.toString();
  }
}

/// A stepper's touch, its repeat and its value commands.
final class _StepperInput extends Interaction {
  _StepperInput({
    required this.onPressed,
    required this.canStep,
    required this.onStep,
    required this.onCommand,
  }) : super(role: InteractionRole.control);

  final ValueChanged<GlassStepperHalf?> onPressed;
  final bool Function(GlassStepperHalf half) canStep;
  final ValueChanged<GlassStepperHalf> onStep;
  final ValueChanged<ValueCommand> onCommand;

  // Stepper passport, "The repeat clock": the wait before the next repeat
  // after [count] repeats in a row.
  static double _interval(int count) => count <= 5
      ? 0.5
      : count < 20
      ? 0.1
      : 0.05;

  int? _pointer;
  TextDirection _direction = TextDirection.ltr;
  PressReach _reach = PressReach.box;
  GlassStepperHalf? _half;
  Offset _position = Offset.zero;
  Rect _box = Rect.zero;
  double? _due;
  int _count = 0;
  bool _repeated = false;

  @override
  bool get pressed => _half != null;

  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.adjustment};

  @override
  double? get nextDue => _due;

  GlassStepperHalf? _halfIn(Rect box) {
    for (final half in GlassStepperHalf.values) {
      final rect = half.rectIn(box, _direction);
      if (_position.dx >= rect.left && _position.dx < rect.right) return half;
    }
    return null;
  }

  GlassStepperHalf? _held() =>
      _reach.contains(_box, _position) ? _halfIn(_box) : null;

  void _track(Offset position, Rect box) {
    _position = position;
    _box = box;
    final half = _held();
    if (half == _half) return;
    _half = half;
    onPressed(half);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case AdjustInput(:final command):
        onCommand(command);
      case PointerDownInput() when _pointer == null && accepts(input):
        _direction = input.textDirection;
        _reach = input.reach;
        _position = input.position;
        _box = Offset.zero & input.regionSize;
        if (_held() == null) return const InteractionUpdate(fails: true);
        _pointer = input.pointer;
        _count = 0;
        _repeated = false;
        _due = input.time + _interval(0);
        _track(input.position, _box);
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        _track(input.position, input.regionBox);
      case PointerUpInput() when input.pointer == _pointer:
        _track(input.position, input.regionBox);
        final half = _half;
        final repeated = _repeated;
        _end();
        if (half != null && !repeated) onStep(half);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _end();
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }

  void _end() {
    _pointer = null;
    _due = null;
    if (_half == null) return;
    _half = null;
    onPressed(null);
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (due == null || time < due) return InteractionUpdate.none;
    final half = _box.contains(_position) ? _halfIn(_box) : null;
    if (half != null && canStep(half)) {
      _repeated = true;
      _count++;
      onStep(half);
    } else if (_count > 0) {
      _count = 1;
    }
    _due = due + _interval(_count);
    return InteractionUpdate.none;
  }
}
