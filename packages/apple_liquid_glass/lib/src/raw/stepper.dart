import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// A half of a stepper.
enum GlassStepperHalf {
  /// The minus half, on the left in either direction.
  decrement,

  /// The plus half, on the right in either direction.
  increment,
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
  });

  /// The half a finger holds, or null.
  final GlassStepperHalf? pressed;

  /// Whether the value is above the minimum.
  final bool canDecrement;

  /// Whether the value is below the maximum.
  final bool canIncrement;

  /// The states the stepper is in.
  final Set<WidgetState> states;
}

/// A stepper with the behavior of iOS 27's `UIStepper` and no look of its
/// own: [builder] decides how it looks.
///
/// UIKit: `UIStepper`. SwiftUI: `Stepper`. Flutter: none.
///
/// There is no motion: a held half highlights at once and clears on
/// release. A tap commits on release; a held half repeats every
/// [repeatInterval], first after that long, without acceleration. Sliding
/// to the other half moves the highlight and the repeat with it without a
/// step, and leaving the control cancels the touch. Minus stays on the left
/// in a right-to-left context, as UIKit's does (stepper passport, device).
/// Screen readers see two buttons that announce the value; the left and
/// down arrows decrement, the right and up arrows, Space and Enter
/// increment. A disabled stepper ignores input; [builder] sees
/// [WidgetState.disabled].
class RawGlassStepper extends StatefulWidget {
  /// Creates a stepper showing [value] between [min] and [max].
  const RawGlassStepper({
    required this.value,
    required this.onChanged,
    required this.builder,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.decrementLabel = 'Decrement',
    this.incrementLabel = 'Increment',
    this.semanticFormatterCallback,
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

  /// How much one step changes the value.
  final double step;

  /// What screen readers announce for the minus half.
  final String decrementLabel;

  /// What screen readers announce for the plus half.
  final String incrementLabel;

  /// Formats the value each half announces; null uses up to twelve
  /// significant digits without binary floating-point tails.
  final String Function(double value)? semanticFormatterCallback;

  /// Where the stepper writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The stepper's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the stepper takes focus when it first appears.
  final bool autofocus;

  /// The size of the stepper (stepper passport, device).
  static const Size size = Size(94, 32);

  /// The delay before the first repeat and between repeats (stepper
  /// passport, device: 0.520, 1.021, 1.522 s after the touch).
  static const Duration repeatInterval = Duration(milliseconds: 500);

  @override
  State<RawGlassStepper> createState() => _RawGlassStepperState();
}

class _RawGlassStepperState extends State<RawGlassStepper>
    with ControlStates<RawGlassStepper> {
  late final _StepperInput _input = _StepperInput(
    onPressed: (half) => setState(() => _pressed = half),
    onStep: _stepBy,
  );
  late final List<Interaction> _interactions = [_input];
  GlassStepperHalf? _pressed;

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  void writeStates() {
    final disabled = widget.onChanged == null;
    widgetStates.update(WidgetState.disabled, disabled);
    if (disabled) widgetStates.update(WidgetState.pressed, false);
  }

  double get _minimum => widget.min.isFinite ? widget.min : 0;

  double get _maximum =>
      widget.max.isFinite && widget.max >= _minimum ? widget.max : _minimum;

  double get _value =>
      widget.value.isFinite ? widget.value.clamp(_minimum, _maximum) : _minimum;

  bool _canStep(GlassStepperHalf half) => switch (half) {
    GlassStepperHalf.decrement => _value > _minimum,
    GlassStepperHalf.increment => _value < _maximum,
  };

  void _stepBy(GlassStepperHalf half) {
    final step = widget.step;
    if (widget.onChanged == null ||
        !step.isFinite ||
        step <= 0 ||
        !_canStep(half)) {
      return;
    }
    final delta = half == GlassStepperHalf.increment ? step : -step;
    widget.onChanged?.call((_value + delta).clamp(_minimum, _maximum));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final value =
        widget.semanticFormatterCallback?.call(_value) ?? _format(_value);
    Widget half(GlassStepperHalf half, String label) => Expanded(
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled && _canStep(half),
        label: label,
        value: value,
        onTap: enabled ? () => _stepBy(half) : null,
        child: const SizedBox.expand(),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        for (final key in [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowDown,
        ])
          SingleActivator(key): () => _stepBy(GlassStepperHalf.decrement),
        for (final key in [
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.enter,
        ])
          SingleActivator(key): () => _stepBy(GlassStepperHalf.increment),
      },
      child: InputRegion(
        interactions: _interactions,
        enabled: enabled,
        statesController: widgetStates,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        child: SizedBox.fromSize(
          size: RawGlassStepper.size,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: widget.builder(
                    context,
                    GlassStepperDetails(
                      pressed: _pressed,
                      canDecrement: _canStep(GlassStepperHalf.decrement),
                      canIncrement: _canStep(GlassStepperHalf.increment),
                      states: {...widgetStates.value},
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      half(GlassStepperHalf.decrement, widget.decrementLabel),
                      half(GlassStepperHalf.increment, widget.incrementLabel),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

final class _StepperInput extends Interaction {
  _StepperInput({required this.onPressed, required this.onStep})
    : super(role: InteractionRole.control);

  final ValueChanged<GlassStepperHalf?> onPressed;
  final ValueChanged<GlassStepperHalf> onStep;
  static final double _interval =
      RawGlassStepper.repeatInterval.inMicroseconds / 1e6;

  int? _pointer;
  GlassStepperHalf? _half;
  double? _due;
  bool _repeated = false;

  @override
  bool get pressed => _half != null;

  @override
  double? get nextDue => _due;

  static GlassStepperHalf? _halfAt(Offset position) {
    const size = RawGlassStepper.size;
    if (!(Offset.zero & size).contains(position)) return null;
    return position.dx < size.width / 2
        ? GlassStepperHalf.decrement
        : GlassStepperHalf.increment;
  }

  void _hold(GlassStepperHalf? half) {
    if (half == _half) return;
    _half = half;
    onPressed(half);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        final half = _halfAt(input.position);
        if (half == null) return const InteractionUpdate(fails: true);
        _pointer = input.pointer;
        _repeated = false;
        _due = input.time + _interval;
        _hold(half);
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        final half = _halfAt(input.position);
        if (half == null) return _end(fails: true);
        _hold(half);
      case PointerUpInput() when input.pointer == _pointer:
        final half = _half;
        final repeated = _repeated;
        _end(fails: false);
        if (half != null && !repeated) onStep(half);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        return _end(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }

  InteractionUpdate _end({required bool fails}) {
    _pointer = null;
    _due = null;
    _hold(null);
    return InteractionUpdate(fails: fails);
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    final half = _half;
    if (due == null || half == null || time < due) {
      return InteractionUpdate.none;
    }
    _repeated = true;
    _due = due + _interval;
    onStep(half);
    return InteractionUpdate.none;
  }
}
