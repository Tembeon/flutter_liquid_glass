import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The look of a [GlassButton], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the button's states. A
/// button looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one, and `WidgetStatePropertyAll(null)`
/// hands every state on. [merge] combines two styles the same way.
@immutable
class GlassButtonStyle extends GlassStyle<GlassButtonStyle> {
  /// Creates a style.
  const GlassButtonStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.iconColor,
    this.textStyle,
    this.padding,
    this.minimumSize,
    this.iconSize,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassButtonStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassButtonStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassButtonStyle>(context);

  /// The tint of the glass; an untinted button's resolves to null.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The color of the label's text, and of its icons without [iconColor].
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The color of the label's icons.
  final WidgetStateProperty<Color?>? iconColor;

  /// The style of the label's text; its color comes from [foregroundColor].
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The space around the label.
  final WidgetStateProperty<EdgeInsetsGeometry?>? padding;

  /// The smallest size of the button.
  final WidgetStateProperty<Size?>? minimumSize;

  /// The size of the label's icons.
  final WidgetStateProperty<double?>? iconSize;

  /// The ring around a button focused from the keyboard; null derives it
  /// from the glass's tint as Flutter's Cupertino button does, and a
  /// transparent color draws none.
  final Color? focusColor;

  /// What a mouse over the button adds to its glass; null for a pressed
  /// glass's wash at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// Builds the button's look in place of the default one; the button then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassButtonBuilder? builder;

  // Builds a style of this one's class, so a merge, copy or lerp of a
  // GlassProminentButtonStyle stays one and keeps its key in the theme.
  GlassButtonStyle _with({
    required WidgetStateProperty<Color?>? backgroundColor,
    required WidgetStateProperty<Color?>? foregroundColor,
    required WidgetStateProperty<Color?>? iconColor,
    required WidgetStateProperty<TextStyle?>? textStyle,
    required WidgetStateProperty<EdgeInsetsGeometry?>? padding,
    required WidgetStateProperty<Size?>? minimumSize,
    required WidgetStateProperty<double?>? iconSize,
    required Color? focusColor,
    required Color? hoverColor,
    required GlassButtonBuilder? builder,
  }) => GlassButtonStyle(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    iconColor: iconColor,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    iconSize: iconSize,
    focusColor: focusColor,
    hoverColor: hoverColor,
    builder: builder,
  );

  /// This style over [other], state by state.
  @override
  GlassButtonStyle merge(GlassButtonStyle? other) {
    if (other == null) return this;
    return _with(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      iconColor: GlassStyle.mergeStates(iconColor, other.iconColor),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      padding: GlassStyle.mergeStates(padding, other.padding),
      minimumSize: GlassStyle.mergeStates(minimumSize, other.minimumSize),
      iconSize: GlassStyle.mergeStates(iconSize, other.iconSize),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// A copy with the given fields replaced.
  GlassButtonStyle copyWith({
    WidgetStateProperty<Color?>? backgroundColor,
    WidgetStateProperty<Color?>? foregroundColor,
    WidgetStateProperty<Color?>? iconColor,
    WidgetStateProperty<TextStyle?>? textStyle,
    WidgetStateProperty<EdgeInsetsGeometry?>? padding,
    WidgetStateProperty<Size?>? minimumSize,
    WidgetStateProperty<double?>? iconSize,
    Color? focusColor,
    Color? hoverColor,
    GlassButtonBuilder? builder,
  }) => _with(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    iconColor: iconColor ?? this.iconColor,
    textStyle: textStyle ?? this.textStyle,
    padding: padding ?? this.padding,
    minimumSize: minimumSize ?? this.minimumSize,
    iconSize: iconSize ?? this.iconSize,
    focusColor: focusColor ?? this.focusColor,
    hoverColor: hoverColor ?? this.hoverColor,
    builder: builder ?? this.builder,
  );

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassButtonStyle lerp(GlassButtonStyle other, double t) {
    if (identical(this, other)) return this;
    return _with(
      backgroundColor: WidgetStateProperty.lerp<Color?>(
        backgroundColor,
        other.backgroundColor,
        t,
        GlassStyle.lerpNullable(GlassDynamicColor.lerp),
      ),
      foregroundColor: WidgetStateProperty.lerp<Color?>(
        foregroundColor,
        other.foregroundColor,
        t,
        GlassStyle.lerpNullable(GlassDynamicColor.lerp),
      ),
      iconColor: WidgetStateProperty.lerp<Color?>(
        iconColor,
        other.iconColor,
        t,
        GlassStyle.lerpNullable(GlassDynamicColor.lerp),
      ),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        GlassStyle.lerpNullable(TextStyle.lerp),
      ),
      padding: WidgetStateProperty.lerp<EdgeInsetsGeometry?>(
        padding,
        other.padding,
        t,
        GlassStyle.lerpNullable(EdgeInsetsGeometry.lerp),
      ),
      minimumSize: WidgetStateProperty.lerp<Size?>(
        minimumSize,
        other.minimumSize,
        t,
        GlassStyle.lerpNullable(Size.lerp),
      ),
      iconSize: WidgetStateProperty.lerp<double?>(
        iconSize,
        other.iconSize,
        t,
        GlassStyle.lerpNullable(lerpDouble),
      ),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassButtonStyle &&
      other.type == type &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.iconColor == iconColor &&
      other.textStyle == textStyle &&
      other.padding == padding &&
      other.minimumSize == minimumSize &&
      other.iconSize == iconSize &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    iconColor,
    textStyle,
    padding,
    minimumSize,
    iconSize,
    focusColor,
    hoverColor,
    builder,
  );
}

/// The look of prominent glass buttons, as a theme keeps it apart from
/// the regular and clear ones' [GlassButtonStyle].
///
/// A theme holds one style per type: put a [GlassButtonStyle] in
/// `GlassThemeData.styles` for `GlassButton` and `GlassButton.clear`, and
/// this one for `GlassButton.prominent` and `GlassButton.prominentClear`.
/// As a button's own `style` it acts as any [GlassButtonStyle].
class GlassProminentButtonStyle extends GlassButtonStyle {
  /// Creates a style.
  const GlassProminentButtonStyle({
    super.backgroundColor,
    super.foregroundColor,
    super.iconColor,
    super.textStyle,
    super.padding,
    super.minimumSize,
    super.iconSize,
    super.focusColor,
    super.hoverColor,
    super.builder,
  });

  /// A prominent style with the fields of [style], as from
  /// [GlassButton.styleFrom].
  factory GlassProminentButtonStyle.from(GlassButtonStyle style) =>
      GlassProminentButtonStyle(
        backgroundColor: style.backgroundColor,
        foregroundColor: style.foregroundColor,
        iconColor: style.iconColor,
        textStyle: style.textStyle,
        padding: style.padding,
        minimumSize: style.minimumSize,
        iconSize: style.iconSize,
        focusColor: style.focusColor,
        hoverColor: style.hoverColor,
        builder: style.builder,
      );

  /// The theme's [GlassProminentButtonStyle] at [context], or null without
  /// one: the look between a prominent button's own style and its
  /// defaults.
  static GlassButtonStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassButtonStyle>(context, GlassProminentButtonStyle);

  @override
  Object get type => GlassProminentButtonStyle;

  @override
  GlassButtonStyle _with({
    required WidgetStateProperty<Color?>? backgroundColor,
    required WidgetStateProperty<Color?>? foregroundColor,
    required WidgetStateProperty<Color?>? iconColor,
    required WidgetStateProperty<TextStyle?>? textStyle,
    required WidgetStateProperty<EdgeInsetsGeometry?>? padding,
    required WidgetStateProperty<Size?>? minimumSize,
    required WidgetStateProperty<double?>? iconSize,
    required Color? focusColor,
    required Color? hoverColor,
    required GlassButtonBuilder? builder,
  }) => GlassProminentButtonStyle(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    iconColor: iconColor,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    iconSize: iconSize,
    focusColor: focusColor,
    hoverColor: hoverColor,
    builder: builder,
  );
}

/// The look of plain buttons, as a theme keeps it apart from the glass
/// buttons' [GlassButtonStyle].
///
/// A theme holds one style per type: put this one in
/// `GlassThemeData.styles` for `GlassButton.plain`. As a button's own
/// `style` it acts as any [GlassButtonStyle]; a plain button draws no
/// background, so it does not use [backgroundColor].
class GlassPlainButtonStyle extends GlassButtonStyle {
  /// Creates a style.
  const GlassPlainButtonStyle({
    super.backgroundColor,
    super.foregroundColor,
    super.iconColor,
    super.textStyle,
    super.padding,
    super.minimumSize,
    super.iconSize,
    super.focusColor,
    super.hoverColor,
    super.builder,
  });

  /// A plain style with the fields of [style], as from
  /// [GlassButton.styleFrom].
  factory GlassPlainButtonStyle.from(GlassButtonStyle style) =>
      GlassPlainButtonStyle(
        backgroundColor: style.backgroundColor,
        foregroundColor: style.foregroundColor,
        iconColor: style.iconColor,
        textStyle: style.textStyle,
        padding: style.padding,
        minimumSize: style.minimumSize,
        iconSize: style.iconSize,
        focusColor: style.focusColor,
        hoverColor: style.hoverColor,
        builder: style.builder,
      );

  /// The theme's [GlassPlainButtonStyle] at [context], or null without
  /// one: the look between a plain button's own style and its defaults.
  static GlassButtonStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassButtonStyle>(context, GlassPlainButtonStyle);

  @override
  Object get type => GlassPlainButtonStyle;

  @override
  GlassButtonStyle _with({
    required WidgetStateProperty<Color?>? backgroundColor,
    required WidgetStateProperty<Color?>? foregroundColor,
    required WidgetStateProperty<Color?>? iconColor,
    required WidgetStateProperty<TextStyle?>? textStyle,
    required WidgetStateProperty<EdgeInsetsGeometry?>? padding,
    required WidgetStateProperty<Size?>? minimumSize,
    required WidgetStateProperty<double?>? iconSize,
    required Color? focusColor,
    required Color? hoverColor,
    required GlassButtonBuilder? builder,
  }) => GlassPlainButtonStyle(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    iconColor: iconColor,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    iconSize: iconSize,
    focusColor: focusColor,
    hoverColor: hoverColor,
    builder: builder,
  );
}

enum _Variant { regular, prominent, clear, prominentClear, plain }

/// An iOS 27 button: a glass capsule around a text or icon label.
///
/// UIKit: `UIButton.Configuration.glass()`. SwiftUI:
/// `.buttonStyle(.glass)`. Flutter: `FilledButton`.
///
/// Pass the label as [child] and the action as [onPressed]; a null
/// [onPressed] disables the button. [GlassButton.prominent] tints the
/// glass with the theme's primary color; [GlassButton.clear] and
/// [GlassButton.prominentClear] use clear glass, for buttons over photos
/// and video, where the label needs contrast of its own;
/// [GlassButton.plain] draws no glass, only its label in the primary
/// color, for text actions in content. [style], usually
/// built with [styleFrom], changes colors, text, padding and size. The
/// button stands anywhere; a `GlassMenuAnchor` around it gives it a menu.
///
/// ```dart
/// GlassButton.prominent(
///   onPressed: () => debugPrint('saved'),
///   child: const Text('Save'),
/// )
/// ```
///
/// Its body is a [GlassSurface] drawn by the renderer above it. The liquid
/// renderer draws liquid glass that bends and lights what lies behind it
/// and glows under the finger; the fake renderer blurs and lights it, with
/// no bending and no glow; the flat renderer, which also draws when no
/// `GlassScope` is above, draws a translucent fill with a hairline rim and
/// a soft shadow, and reads nothing behind it.
///
/// A touch lifts, leans and lights the body as [RawGlassButton] does. A
/// prominent button draws its label in white, or in black on a tint too
/// light for white, whichever tint its style gives it. A disabled regular
/// button keeps its glass, a disabled prominent one is
/// tinted systemGray4, and every disabled button draws its label in
/// tertiaryLabel. Its menu form, UIKit's `UIButton.menu`, is a
/// `GlassMenuAnchor` around it: the button describes its glass to the
/// anchor ([GlassSource]), and the menu grows out of it and carries its
/// tint and label as it grows.
///
/// Fidelity. The press is measured on iOS 27. The disabled look matches
/// UIKit on an iPhone 16 Pro with iOS 27.0.1, in light and dark. A
/// prominent label's white or black is UIKit 27.2's, read through
/// `UIButton.Configuration` under Mac Catalyst. The label's 17 point text
/// is UIKit's title style; the icon size, the padding and the minimum size
/// are not measured.
class GlassButton extends StatelessWidget {
  /// Creates a regular glass button.
  const GlassButton({
    required this.onPressed,
    required this.child,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : _variant = _Variant.regular;

  /// Creates a prominent glass button, tinted with the theme's primary
  /// color.
  ///
  /// UIKit: `UIButton.Configuration.prominentGlass()`. SwiftUI:
  /// `.buttonStyle(.glassProminent)`. A disabled one is tinted systemGray4.
  const GlassButton.prominent({
    required this.onPressed,
    required this.child,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : _variant = _Variant.prominent;

  /// Creates a clear glass button, for buttons over rich media; its label
  /// needs contrast of its own.
  ///
  /// UIKit: `UIButton.Configuration.clearGlass()`.
  const GlassButton.clear({
    required this.onPressed,
    required this.child,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : _variant = _Variant.clear;

  /// Creates a prominent clear glass button, tinted with the theme's
  /// primary color.
  ///
  /// UIKit: `UIButton.Configuration.prominentClearGlass()`.
  const GlassButton.prominentClear({
    required this.onPressed,
    required this.child,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : _variant = _Variant.prominentClear;

  /// Creates a plain button: its label in the theme's primary color, with
  /// no glass and no background.
  ///
  /// UIKit: `UIButton.Configuration.plain()`. SwiftUI:
  /// `.buttonStyle(.borderless)`. Flutter: `TextButton`.
  ///
  /// It is UIKit's medium plain button: 17 point text 12 points in from
  /// its sides and 7 from its top and bottom, 34.33 points tall for one
  /// line. A press dims the label to 0.75 of its color at once and a lift
  /// brings it back at once, with no lift, lean or glow; a finger takes it
  /// within 44 by 44 points around a smaller button, and a release within
  /// 70 points of it presses it, as UIKit's. A disabled one draws its label
  /// in tertiaryLabel. Focused from the keyboard it draws Flutter's
  /// Cupertino focus ring around its capsule, and a mouse over it dims the
  /// label half as much as a press, or fills its capsule with the style's
  /// [GlassButtonStyle.hoverColor]. Its theme style is a
  /// [GlassPlainButtonStyle].
  ///
  /// Fidelity. The size, insets, text and press are measured on the iOS
  /// 27.2 simulator (button passport). Not measured: the disabled plain
  /// button (borrowed from the other presets), the focus ring and the
  /// hover.
  const GlassButton.plain({
    required this.onPressed,
    required this.child,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : _variant = _Variant.plain;

  /// Called when the button is pressed; null disables it.
  final VoidCallback? onPressed;

  /// The label.
  final Widget child;

  /// The look, over the theme's and the button's defaults.
  final GlassButtonStyle? style;

  /// Where the button writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The button's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the button takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the button; null lets its label speak.
  final String? semanticLabel;

  final _Variant _variant;

  bool get _prominent =>
      _variant == _Variant.prominent || _variant == _Variant.prominentClear;

  bool get _clear =>
      _variant == _Variant.clear || _variant == _Variant.prominentClear;

  bool get _plain => _variant == _Variant.plain;

  /// A style from plain values: each `disabled` value applies to a
  /// disabled button, the other to every other state, and a null value
  /// keeps the default.
  static GlassButtonStyle styleFrom({
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    Color? foregroundColor,
    Color? disabledForegroundColor,
    Color? iconColor,
    Color? disabledIconColor,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    double? iconSize,
    Color? focusColor,
    Color? hoverColor,
  }) => GlassButtonStyle(
    backgroundColor: _enabledOrDisabled(
      backgroundColor,
      disabledBackgroundColor,
    ),
    foregroundColor: _enabledOrDisabled(
      foregroundColor,
      disabledForegroundColor,
    ),
    iconColor: _enabledOrDisabled(iconColor, disabledIconColor),
    textStyle: GlassStyle.allOrNull(textStyle),
    padding: GlassStyle.allOrNull(padding),
    minimumSize: GlassStyle.allOrNull(minimumSize),
    iconSize: GlassStyle.allOrNull(iconSize),
    focusColor: focusColor,
    hoverColor: hoverColor,
  );

  static WidgetStateProperty<Color?>? _enabledOrDisabled(
    Color? enabled,
    Color? disabled,
  ) => enabled == null && disabled == null
      ? null
      : WidgetStateMapper<Color?>({
          WidgetState.disabled: disabled,
          WidgetState.any: enabled,
        });

  // UIKit's title style, 17 regular (typography passport). The glyph size,
  // insets and minimum size are not measured (glass-button passport).
  static const _labelStyle = TextStyle(fontSize: 17);
  static const _iconSize = 22.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 11);

  // UIKit's medium plain button (button passport, iOS 27.2 simulator).
  static const _plainPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 7,
  );

  // A pressed plain button's title alpha (button passport).
  static const double _pressedPlain = 0.75;

  static const _transparent = Color(0x00000000);

  /// The button's own look at [context]: every field but
  /// [GlassButtonStyle.iconColor] and [GlassButtonStyle.builder] is set,
  /// and [GlassButtonStyle.backgroundColor] only on a prominent button.
  @internal
  GlassButtonStyle defaultStyleOf(BuildContext context) {
    final disabledLabel = GlassTheme.tertiaryLabelColorOf(context);
    if (_plain) {
      return GlassButtonStyle(
        foregroundColor: WidgetStateMapper<Color?>({
          WidgetState.disabled: disabledLabel,
          WidgetState.any:
              GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
        }),
        textStyle: const WidgetStatePropertyAll(_labelStyle),
        padding: const WidgetStatePropertyAll(_plainPadding),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        iconSize: const WidgetStatePropertyAll(_iconSize),
      );
    }
    final label = GlassTheme.labelColorOf(context);
    final fill = _prominent
        ? WidgetStateMapper<Color?>({
            WidgetState.disabled: GlassColors.systemGray4,
            WidgetState.any:
                GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
          })
        : null;
    final drawnFill = fill == null
        ? null
        : GlassStyle.mergeStates(_givenOf(context).backgroundColor, fill);
    final traits = GlassTraits.of(context);
    return GlassButtonStyle(
      backgroundColor: fill,
      foregroundColor: WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled)
            ? disabledLabel
            : drawnFill == null
            ? label
            : GlassColors.legibleOn(drawnFill.resolve(states)!, traits),
      ),
      textStyle: const WidgetStatePropertyAll(_labelStyle),
      padding: const WidgetStatePropertyAll(_padding),
      minimumSize: const WidgetStatePropertyAll(glassMinimumTarget),
      iconSize: const WidgetStatePropertyAll(_iconSize),
    );
  }

  GlassButtonStyle? _themeStyleOf(BuildContext context) => switch (_variant) {
    _Variant.prominent ||
    _Variant.prominentClear => GlassProminentButtonStyle.maybeOf(context),
    _Variant.plain => GlassPlainButtonStyle.maybeOf(context),
    _Variant.regular || _Variant.clear => GlassButtonStyle.maybeOf(context),
  };

  @override
  Widget build(BuildContext context) {
    final button = RawGlassButton(
      onPressed: onPressed,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      builder:
          style?.builder ??
          _themeStyleOf(context)?.builder ??
          (_plain ? _plainBody : _defaultBody),
      child: child,
    );
    if (!GlassSource.isSourceAt(context)) return button;
    final states = {if (onPressed == null) WidgetState.disabled};
    return GlassSource(
      description: GlassSourceDescription(
        tint: StateColors(
          context,
          states,
        ).maybe(_lookOf(context).backgroundColor),
        semanticLabel: semanticLabel,
      ),
      child: button,
    );
  }

  GlassButtonStyle _givenOf(BuildContext context) =>
      (style ?? const GlassButtonStyle()).merge(_themeStyleOf(context));

  GlassButtonStyle _lookOf(BuildContext context) =>
      _givenOf(context).merge(defaultStyleOf(context));

  Widget _defaultBody(BuildContext context, GlassButtonDetails details) {
    final states = details.states;
    final look = _lookOf(context);
    final tint = look.backgroundColor?.resolve(states);
    return GlassSurface.live(
      frame: details.body,
      glass: _clear ? Glass.clear(tint: tint) : Glass.regular(tint: tint),
      states: details.statesListenable,
      focusColor: look.focusColor,
      hoverColor: look.hoverColor,
      child: _label(context, look, states, details.label),
    );
  }

  Widget _plainBody(BuildContext context, GlassButtonDetails details) {
    final states = details.states;
    final look = _lookOf(context);
    final hover = look.hoverColor;
    final dim = states.contains(WidgetState.pressed)
        ? _pressedPlain
        : hover == null && states.contains(WidgetState.hovered)
        ? 1 - (1 - _pressedPlain) * GlassHighlights.hoverGain
        : 1.0;
    return GlassHighlightPaint.of(
      context,
      states: details.statesListenable,
      focusColor: look.focusColor,
      hoverColor: hover ?? _transparent,
      base: StateColors(context, states)(look.foregroundColor),
      child: _label(context, look, states, details.label, dim: dim),
    );
  }

  Widget _label(
    BuildContext context,
    GlassButtonStyle look,
    Set<WidgetState> states,
    Widget label, {
    double dim = 1,
  }) {
    T resolve<T>(WidgetStateProperty<T?>? property) =>
        property!.resolve(states) as T;
    Color dimmed(Color color) =>
        dim == 1 ? color : color.withValues(alpha: color.a * dim);
    final color = StateColors(context, states);
    final foreground = dimmed(color(look.foregroundColor));
    final icon = dimmed(color(look.iconColor, color(look.foregroundColor)));
    final minimumSize = resolve<Size>(look.minimumSize);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minimumSize.width,
        minHeight: minimumSize.height,
      ),
      child: Padding(
        padding: resolve<EdgeInsetsGeometry>(look.padding),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: IconTheme.merge(
            data: IconThemeData(
              color: icon,
              size: resolve<double>(look.iconSize),
            ),
            child: DefaultTextStyle.merge(
              style: GlassTextScale.of(context).resolve(
                resolve<TextStyle>(
                  look.textStyle,
                ).copyWith(color: foreground),
              ),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}
