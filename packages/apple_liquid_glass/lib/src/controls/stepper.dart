import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
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
/// increment. A disabled stepper looks like an enabled one and ignores
/// input, as UIKit's does.
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

class _RawGlassStepperState extends State<RawGlassStepper> {
  late final _StepperInput _input = _StepperInput(
    onPressed: (half) => setState(() => _pressed = half),
    onStep: _stepBy,
  );
  late final List<Interaction> _interactions = [_input];
  WidgetStatesController? _ownStates;
  GlassStepperHalf? _pressed;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownStates ??= WidgetStatesController());

  @override
  void initState() {
    super.initState();
    _writeStates();
    _states.addListener(_statesChanged);
  }

  @override
  void didUpdateWidget(RawGlassStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = oldWidget.statesController ?? _ownStates;
    if (!identical(states, _states)) {
      states?.removeListener(_statesChanged);
      _states.addListener(_statesChanged);
    }
    _writeStates();
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownStates?.dispose();
    super.dispose();
  }

  // The region writes disabled too, and ends a press when disabled;
  // writing both first makes its writes no-ops, so it never asks this
  // ancestor to rebuild while it builds.
  void _writeStates() {
    final disabled = widget.onChanged == null;
    _states.update(WidgetState.disabled, disabled);
    if (disabled) _states.update(WidgetState.pressed, false);
  }

  void _statesChanged() => setState(() {});

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
        statesController: _states,
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
                      states: {..._states.value},
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

/// A stepper's touch: it holds the half under the finger, repeats while it
/// is held, follows the finger to the other half and ends when the finger
/// leaves the control.
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

/// The look of a [GlassStepper], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the stepper's states. A
/// stepper looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state. [merge] combines two styles the same way.
@immutable
class GlassStepperStyle {
  /// Creates a style.
  const GlassStepperStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.builder,
  });

  /// The fill of each half; the device's measured fill by default
  /// ([GlassStepper.background]).
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The minus and plus glyphs; label by default. A half that cannot step
  /// further draws its glyph in tertiaryLabel.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// Builds the stepper's look in place of the default one; the stepper
  /// then ignores the other fields. Null leaves it to the theme's builder,
  /// then the default look.
  final GlassStepperBuilder? builder;

  /// This style over [other], state by state.
  GlassStepperStyle merge(GlassStepperStyle? other) {
    if (other == null) return this;
    return GlassStepperStyle(
      backgroundColor: fallThrough(backgroundColor, other.backgroundColor),
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassStepperStyle? lerp(
    GlassStepperStyle? a,
    GlassStepperStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassStepperStyle(
      backgroundColor: color(a.backgroundColor, b.backgroundColor),
      foregroundColor: color(a.foregroundColor, b.foregroundColor),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassStepperStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(backgroundColor, foregroundColor, builder);
}

/// An iOS 27 stepper.
///
/// UIKit: `UIStepper`. SwiftUI: `Stepper`. Flutter: none.
///
/// A plain capsule, not glass, on every renderer, as iOS draws it; its
/// behavior is [RawGlassStepper]'s.
class GlassStepper extends StatelessWidget {
  /// Creates a stepper showing [value] between [min] and [max].
  const GlassStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.style,
    this.decrementLabel = 'Decrement',
    this.incrementLabel = 'Increment',
    this.semanticFormatterCallback,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// See [RawGlassStepper.value].
  final double value;

  /// See [RawGlassStepper.onChanged].
  final ValueChanged<double>? onChanged;

  /// See [RawGlassStepper.min].
  final double min;

  /// See [RawGlassStepper.max].
  final double max;

  /// See [RawGlassStepper.step].
  final double step;

  /// The look, over the theme's and the stepper's defaults.
  final GlassStepperStyle? style;

  /// See [RawGlassStepper.decrementLabel].
  final String decrementLabel;

  /// See [RawGlassStepper.incrementLabel].
  final String incrementLabel;

  /// See [RawGlassStepper.semanticFormatterCallback].
  final String Function(double value)? semanticFormatterCallback;

  /// See [RawGlassStepper.statesController].
  final WidgetStatesController? statesController;

  /// See [RawGlassStepper.focusNode].
  final FocusNode? focusNode;

  /// See [RawGlassStepper.autofocus].
  final bool autofocus;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassStepperStyle styleFrom({
    Color? backgroundColor,
    Color? foregroundColor,
  }) => GlassStepperStyle(
    backgroundColor: allStates(backgroundColor),
    foregroundColor: allStates(foregroundColor),
  );

  /// UIStepper's fill of each half (stepper passport, device).
  static const background = GlassDynamicColor.withBrightness(
    color: Color(0x163C3C43),
    darkColor: Color(0x14EBEBF5),
  );

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassStepperStyle()).merge(
      GlassTheme.of(context).stepperStyle,
    );
    return RawGlassStepper(
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      step: step,
      decrementLabel: decrementLabel,
      incrementLabel: incrementLabel,
      semanticFormatterCallback: semanticFormatterCallback,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      builder:
          look.builder ??
          (context, details) => _StepperLook(details: details, look: look),
    );
  }
}

class _StepperLook extends StatelessWidget {
  const _StepperLook({required this.details, required this.look});

  final GlassStepperDetails details;
  final GlassStepperStyle look;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    final scheme = GlassTheme.colorSchemeOf(context);
    final dark = GlassTraits.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _StepperPainter(
        pressed: details.pressed,
        background: resolve(look.backgroundColor, GlassStepper.background),
        foreground: resolve(
          look.foregroundColor,
          scheme?.label ?? GlassColors.label,
        ),
        limit: GlassDynamicColor.resolve(
          scheme?.tertiaryLabel ?? GlassColors.tertiaryLabel,
          context,
        ),
        divider: GlassDynamicColor.resolve(GlassColors.tertiaryLabel, context),
        replacesFill: dark,
        canDecrement: details.canDecrement,
        canIncrement: details.canIncrement,
      ),
    );
  }
}

class _StepperPainter extends CustomPainter {
  _StepperPainter({
    required this.pressed,
    required this.background,
    required this.foreground,
    required this.limit,
    required this.divider,
    required this.replacesFill,
    required this.canDecrement,
    required this.canIncrement,
  });

  final GlassStepperHalf? pressed;
  final Color background;
  final Color foreground;
  final Color limit;
  final Color divider;
  final bool replacesFill;
  final bool canDecrement;
  final bool canIncrement;

  // Stepper passport, device: the held half turns black at 8 percent,
  // replacing the fill in dark and over it in light; a 1 x 24 divider; 14
  // point glyphs 2 wide.
  static const _overlay = Color(0x14000000);
  static const double _dividerHeight = 24;
  static const double _arm = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2;
    final halves = {
      GlassStepperHalf.decrement: Rect.fromLTWH(0, 0, half, size.height),
      GlassStepperHalf.increment: Rect.fromLTWH(half, 0, half, size.height),
    };
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
    );
    final fill = Paint();
    fill.color = background;
    for (final MapEntry(key: side, value: rect) in halves.entries) {
      if (!(replacesFill && pressed == side)) canvas.drawRect(rect, fill);
    }
    if (pressed case final side?) {
      final overlay = Paint();
      overlay.color = _overlay;
      canvas.drawRect(halves[side]!, overlay);
    }
    canvas.restore();
    final line = Paint();
    line.color = divider;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(half, size.height / 2),
        width: 1,
        height: _dividerHeight,
      ),
      line,
    );
    final glyph = Paint();
    glyph.strokeWidth = 2;
    glyph.strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final minusX = half / 2;
    final plusX = half + half / 2;
    glyph.color = canDecrement ? foreground : limit;
    canvas.drawLine(Offset(minusX - _arm, y), Offset(minusX + _arm, y), glyph);
    glyph.color = canIncrement ? foreground : limit;
    canvas.drawLine(Offset(plusX - _arm, y), Offset(plusX + _arm, y), glyph);
    canvas.drawLine(Offset(plusX, y - _arm), Offset(plusX, y + _arm), glyph);
  }

  @override
  bool shouldRepaint(_StepperPainter oldDelegate) =>
      oldDelegate.pressed != pressed ||
      oldDelegate.background != background ||
      oldDelegate.foreground != foreground ||
      oldDelegate.limit != limit ||
      oldDelegate.divider != divider ||
      oldDelegate.replacesFill != replacesFill ||
      oldDelegate.canDecrement != canDecrement ||
      oldDelegate.canIncrement != canIncrement;
}
