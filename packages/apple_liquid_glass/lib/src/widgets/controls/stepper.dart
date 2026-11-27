import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';

/// The look of a [GlassStepper], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the stepper's states. A
/// stepper looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state. [merge] combines two styles the same way.
@immutable
class GlassStepperStyle extends GlassStyle<GlassStepperStyle> {
  /// Creates a style.
  const GlassStepperStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.dividerColor,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassStepperStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassStepperStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassStepperStyle>(context);

  /// The fill of each half; by default UIStepper's, measured on the device
  /// (stepper passport).
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The minus and plus glyphs; label by default. A half that cannot step
  /// further draws its glyph in tertiaryLabel.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The line between the halves; tertiaryLabel by default (stepper
  /// passport).
  final Color? dividerColor;

  /// The ring around a stepper focused from the keyboard; null derives it
  /// from systemBlue as Flutter's Cupertino controls do, and a transparent
  /// color draws none.
  final Color? focusColor;

  /// What a mouse over the stepper fills under its halves; null for half
  /// the darkening of a held half, and a transparent color shows none.
  final Color? hoverColor;

  /// Builds the stepper's look in place of the default one; the stepper
  /// then ignores the other fields. Null leaves it to the theme's builder,
  /// then the default look.
  final GlassStepperBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassStepperStyle merge(GlassStepperStyle? other) {
    if (other == null) return this;
    return GlassStepperStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      dividerColor: dividerColor ?? other.dividerColor,
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassStepperStyle lerp(GlassStepperStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassStepperStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      dividerColor: GlassDynamicColor.lerp(dividerColor, other.dividerColor, t),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassStepperStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.dividerColor == dividerColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    dividerColor,
    focusColor,
    hoverColor,
    builder,
  );
}

/// An iOS 27 stepper: a capsule of minus and plus halves that step a value
/// between [min] and [max].
///
/// UIKit: `UIStepper`. SwiftUI: `Stepper`. Flutter: none.
///
/// The app holds the value: pass it as [value] and set it again in
/// [onChanged], called with the value one [step] away; a null
/// [onChanged] disables the stepper. A held half repeats. The stepper
/// shows no number, so the app shows [value] beside it;
/// [semanticFormatterCallback] formats the value screen readers announce.
///
/// ```dart
/// GlassStepper(
///   value: copies,
///   min: 1,
///   max: 10,
///   onChanged: (value) => setState(() => copies = value),
/// )
/// ```
///
/// It draws no glass on any renderer, as iOS draws none: a plain capsule
/// that looks the same under the liquid, fake and flat renderers and with
/// no `GlassScope` above.
///
/// Its touch, repeat, keys and semantics are [RawGlassStepper]'s. A
/// disabled stepper looks like an enabled one. Focused from the keyboard
/// it draws Flutter's Cupertino focus ring around its capsule, and a mouse
/// over it darkens the capsule by half the overlay of a held half.
///
/// Fidelity. The disabled look matches UIKit's. The focus ring and the
/// hover response are approximations of the platform, not measured.
class GlassStepper extends StatelessWidget {
  /// Creates a stepper showing [value] between [min] and [max].
  const GlassStepper({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.wraps = false,
    this.autorepeat = true,
    this.style,
    this.decrementIcon,
    this.incrementIcon,
    this.decrementLabel,
    this.incrementLabel,
    this.semanticFormatterCallback,
    this.semanticLabel,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// See [RawGlassStepper.value].
  final double value;

  /// See [RawGlassStepper.onChanged].
  final ValueChanged<double>? onChanged;

  /// See [RawGlassStepper.onChangeStart].
  final ValueChanged<double>? onChangeStart;

  /// See [RawGlassStepper.onChangeEnd].
  final ValueChanged<double>? onChangeEnd;

  /// See [RawGlassStepper.wraps].
  final bool wraps;

  /// See [RawGlassStepper.autorepeat].
  final bool autorepeat;

  /// See [RawGlassStepper.min].
  final double min;

  /// See [RawGlassStepper.max].
  final double max;

  /// See [RawGlassStepper.step].
  final double step;

  /// The look, over the theme's and the stepper's defaults.
  final GlassStepperStyle? style;

  /// What the decrement half shows in place of its minus, usually an
  /// [Icon], as UIKit's `setDecrementImage` sets it; it takes the glyph's
  /// color, tertiaryLabel at the limit, and 17 point icons.
  ///
  /// Fidelity. The icon size is not measured.
  final Widget? decrementIcon;

  /// What the increment half shows in place of its plus; see
  /// [decrementIcon].
  final Widget? incrementIcon;

  /// See [RawGlassStepper.decrementLabel].
  final String? decrementLabel;

  /// See [RawGlassStepper.incrementLabel].
  final String? incrementLabel;

  /// See [RawGlassStepper.semanticFormatterCallback].
  final String Function(double value)? semanticFormatterCallback;

  /// See [RawGlassStepper.semanticLabel].
  final String? semanticLabel;

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
    Color? dividerColor,
  }) => GlassStepperStyle(
    backgroundColor: GlassStyle.allOrNull(backgroundColor),
    foregroundColor: GlassStyle.allOrNull(foregroundColor),
    dividerColor: dividerColor,
  );

  // Stepper passport: the device fills; under Increase Contrast the 27.2
  // recheck read light only, at 0.40.
  static const _background = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x163C3C43),
    darkColor: Color(0x14EBEBF5),
    highContrastColor: Color(0x663C3C43),
    darkHighContrastColor: Color(0x14EBEBF5),
  );

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassStepperStyle()).merge(
      GlassStepperStyle.maybeOf(context),
    );
    return RawGlassStepper(
      value: value,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      step: step,
      wraps: wraps,
      autorepeat: autorepeat,
      decrementLabel: decrementLabel,
      incrementLabel: incrementLabel,
      semanticFormatterCallback: semanticFormatterCallback,
      semanticLabel: semanticLabel,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      builder:
          look.builder ??
          (context, details) => _StepperLook(
            details: details,
            look: look,
            decrementIcon: decrementIcon,
            incrementIcon: incrementIcon,
          ),
    );
  }
}

class _StepperLook extends StatelessWidget {
  const _StepperLook({
    required this.details,
    required this.look,
    required this.decrementIcon,
    required this.incrementIcon,
  });

  final GlassStepperDetails details;
  final GlassStepperStyle look;
  final Widget? decrementIcon;
  final Widget? incrementIcon;

  static const double _iconSize = 17;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    final color = StateColors(context, states);
    final scheme = GlassTheme.colorSchemeOf(context);
    final traits = GlassTraits.of(context);
    final foreground = color(
      look.foregroundColor,
      scheme?.label ?? GlassColors.label,
    );
    final limit = GlassDynamicColor.resolve(
      scheme?.tertiaryLabel ?? GlassColors.tertiaryLabel,
      context,
    );
    Widget half(Widget? icon, {required bool can}) => Expanded(
      child: icon == null
          ? const SizedBox.shrink()
          : Center(
              child: IconTheme.merge(
                data: IconThemeData(
                  color: can ? foreground : limit,
                  size: _iconSize,
                ),
                child: icon,
              ),
            ),
    );
    final painted = CustomPaint(
      painter: _StepperPainter(
        pressed: details.pressed,
        direction: Directionality.of(context),
        bold: traits.boldText,
        background: color(look.backgroundColor, GlassStepper._background),
        foreground: foreground,
        limit: limit,
        drawsMinus: decrementIcon == null,
        drawsPlus: incrementIcon == null,
        divider: GlassDynamicColor.resolve(
          look.dividerColor ?? GlassColors.tertiaryLabel,
          context,
        ),
        replacesFill: traits.brightness == Brightness.dark,
        canDecrement: details.canDecrement,
        canIncrement: details.canIncrement,
      ),
      child: decrementIcon == null && incrementIcon == null
          ? null
          : Row(
              children: [
                half(decrementIcon, can: details.canDecrement),
                half(incrementIcon, can: details.canIncrement),
              ],
            ),
    );
    final listenable = details.statesListenable;
    if (listenable == null) return painted;
    const overlay = _StepperPainter._overlay;
    return GlassHighlightPaint.of(
      context,
      states: listenable,
      focusColor: look.focusColor,
      hoverColor:
          look.hoverColor ??
          overlay.withValues(alpha: overlay.a * GlassHighlights.hoverGain),
      child: painted,
    );
  }
}

class _StepperPainter extends CustomPainter {
  _StepperPainter({
    required this.pressed,
    required this.direction,
    required this.bold,
    required this.background,
    required this.foreground,
    required this.limit,
    required this.drawsMinus,
    required this.drawsPlus,
    required this.divider,
    required this.replacesFill,
    required this.canDecrement,
    required this.canIncrement,
  });

  final GlassStepperHalf? pressed;
  final TextDirection direction;
  final bool bold;
  final Color background;
  final Color foreground;
  final Color limit;
  final bool drawsMinus;
  final bool drawsPlus;
  final Color divider;
  final bool replacesFill;
  final bool canDecrement;
  final bool canIncrement;

  // Stepper passport, device: the held half turns black at 8 percent,
  // replacing the fill in dark and over it in light; a 1 x 24 divider.
  // Recheck 27.2: glyphs 13.33 long and 2 thick, 14 long at a limit;
  // under Bold Text 13.67 and 14.33, 2.67 thick.
  static const _overlay = Color(0x14000000);
  static const double _dividerHeight = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2;
    final halves = {
      for (final side in GlassStepperHalf.values)
        side: side.rectIn(Offset.zero & size, direction),
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
    final thickness = bold ? 2.67 : 2.0;
    final glyph = Paint();
    glyph.strokeWidth = thickness;
    glyph.strokeCap = StrokeCap.round;
    double arm(bool atLimit) {
      final length = switch ((bold, atLimit)) {
        (false, false) => 13.33,
        (false, true) => 14.0,
        (true, false) => 13.67,
        (true, true) => 14.33,
      };
      return (length - thickness) / 2;
    }

    final minus = halves[GlassStepperHalf.decrement]!.center;
    final plus = halves[GlassStepperHalf.increment]!.center;
    if (drawsMinus) {
      final minusArm = arm(!canDecrement);
      glyph.color = canDecrement ? foreground : limit;
      canvas.drawLine(
        minus.translate(-minusArm, 0),
        minus.translate(minusArm, 0),
        glyph,
      );
    }
    if (drawsPlus) {
      final plusArm = arm(!canIncrement);
      glyph.color = canIncrement ? foreground : limit;
      canvas.drawLine(
        plus.translate(-plusArm, 0),
        plus.translate(plusArm, 0),
        glyph,
      );
      canvas.drawLine(
        plus.translate(0, -plusArm),
        plus.translate(0, plusArm),
        glyph,
      );
    }
  }

  @override
  bool shouldRepaint(_StepperPainter oldDelegate) =>
      oldDelegate.pressed != pressed ||
      oldDelegate.direction != direction ||
      oldDelegate.bold != bold ||
      oldDelegate.background != background ||
      oldDelegate.foreground != foreground ||
      oldDelegate.limit != limit ||
      oldDelegate.drawsMinus != drawsMinus ||
      oldDelegate.drawsPlus != drawsPlus ||
      oldDelegate.divider != divider ||
      oldDelegate.replacesFill != replacesFill ||
      oldDelegate.canDecrement != canDecrement ||
      oldDelegate.canIncrement != canIncrement;
}
