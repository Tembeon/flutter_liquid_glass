import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/glass.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/presentations/menu_anchor.dart';
import 'package:apple_liquid_glass/src/presentations/menu_entries.dart';
import 'package:apple_liquid_glass/src/raw/button.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
    required GlassButtonBuilder? builder,
  }) => GlassButtonStyle(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    iconColor: iconColor,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    iconSize: iconSize,
    builder: builder,
  );

  /// This style over [other], state by state.
  @override
  GlassButtonStyle merge(GlassButtonStyle? other) {
    if (other == null) return this;
    return _with(
      backgroundColor: fallThrough(backgroundColor, other.backgroundColor),
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      iconColor: fallThrough(iconColor, other.iconColor),
      textStyle: fallThrough(textStyle, other.textStyle),
      padding: fallThrough(padding, other.padding),
      minimumSize: fallThrough(minimumSize, other.minimumSize),
      iconSize: fallThrough(iconSize, other.iconSize),
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
    GlassButtonBuilder? builder,
  }) => _with(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    iconColor: iconColor ?? this.iconColor,
    textStyle: textStyle ?? this.textStyle,
    padding: padding ?? this.padding,
    minimumSize: minimumSize ?? this.minimumSize,
    iconSize: iconSize ?? this.iconSize,
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
        snapNull(GlassDynamicColor.lerp),
      ),
      foregroundColor: WidgetStateProperty.lerp<Color?>(
        foregroundColor,
        other.foregroundColor,
        t,
        snapNull(GlassDynamicColor.lerp),
      ),
      iconColor: WidgetStateProperty.lerp<Color?>(
        iconColor,
        other.iconColor,
        t,
        snapNull(GlassDynamicColor.lerp),
      ),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        snapNull(TextStyle.lerp),
      ),
      padding: WidgetStateProperty.lerp<EdgeInsetsGeometry?>(
        padding,
        other.padding,
        t,
        snapNull(EdgeInsetsGeometry.lerp),
      ),
      minimumSize: WidgetStateProperty.lerp<Size?>(
        minimumSize,
        other.minimumSize,
        t,
        snapNull(Size.lerp),
      ),
      iconSize: WidgetStateProperty.lerp<double?>(
        iconSize,
        other.iconSize,
        t,
        snapNull(lerpDouble),
      ),
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
    required GlassButtonBuilder? builder,
  }) => GlassProminentButtonStyle(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    iconColor: iconColor,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    iconSize: iconSize,
    builder: builder,
  );
}

enum _Variant { regular, prominent, clear, prominentClear }

/// An iOS 27 glass button.
///
/// UIKit: `UIButton.Configuration.glass()`. SwiftUI:
/// `.buttonStyle(.glass)`. Flutter: `FilledButton`.
///
/// Its body is a [GlassSurface] of the ambient renderer, its press the
/// measured one of [GlassPressable]. A disabled regular button keeps its
/// glass, and every disabled button draws its label in tertiaryLabel, as
/// UIKit does (iPhone 16 Pro, iOS 27.0.1, light and dark).
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
    this.menuChildren,
    this.menuController,
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
    this.menuChildren,
    this.menuController,
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
    this.menuChildren,
    this.menuController,
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
    this.menuChildren,
    this.menuController,
    super.key,
  }) : _variant = _Variant.prominentClear;

  /// Called when the button is pressed; null disables it, except for a
  /// button with [menuChildren], which a tap then opens.
  final VoidCallback? onPressed;

  /// The entries of the menu the button's glass grows into, or null for a
  /// button without a menu.
  ///
  /// UIKit: `UIButton.menu`. SwiftUI: `Menu`. Flutter: `MenuAnchor`. The
  /// core without the button's look is [RawGlassMenu].
  ///
  /// Without [onPressed] a tap opens the menu on its release and a hold
  /// opens it under the finger (UIKit's `showsMenuAsPrimaryAction`); with
  /// it a tap presses the button and only a hold opens the menu. The menu
  /// grows out of the button on UIKit's liquid morph springs, the button
  /// and the menu one glass body joined by a neck while they part, and a
  /// finger slides over its rows and chooses the one it lifts from (read
  /// from UIKit and replayed against iPhone 16 Pro recordings). Escape,
  /// Back and a tap outside close it. A button with a menu takes its focus
  /// and states from the menu: it ignores [statesController], [focusNode],
  /// [autofocus] and the [style]'s builder.
  final List<GlassMenuEntry>? menuChildren;

  /// Opens and closes the button's menu from code.
  final GlassMenuController? menuController;

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
  }) => GlassButtonStyle(
    backgroundColor: byState(backgroundColor, disabledBackgroundColor),
    foregroundColor: byState(foregroundColor, disabledForegroundColor),
    iconColor: byState(iconColor, disabledIconColor),
    textStyle: allStates(textStyle),
    padding: allStates(padding),
    minimumSize: allStates(minimumSize),
    iconSize: allStates(iconSize),
  );

  // UIKit's title style, 17 regular (typography passport). The glyph size,
  // insets and minimum size are not measured (glass-button passport).
  static const _labelStyle = TextStyle(fontSize: 17);
  static const _iconSize = 22.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 11);
  static const _minimumSize = Size(44, 44);

  static const _white = Color(0xFFFFFFFF);

  /// The button's own look at [context]: every field but
  /// [GlassButtonStyle.iconColor] and [GlassButtonStyle.builder] is set,
  /// and [GlassButtonStyle.backgroundColor] only on a prominent button.
  @internal
  GlassButtonStyle defaultStyleOf(BuildContext context) {
    final disabledLabel = GlassTheme.tertiaryLabelColorOf(context);
    final label = _prominent ? _white : GlassTheme.labelColorOf(context);
    return GlassButtonStyle(
      backgroundColor: _prominent
          ? ByState<Color>(
              GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
              GlassColors.systemGray4,
            )
          : null,
      foregroundColor: ByState<Color>(label, disabledLabel),
      textStyle: const WidgetStatePropertyAll(_labelStyle),
      padding: const WidgetStatePropertyAll(_padding),
      minimumSize: const WidgetStatePropertyAll(_minimumSize),
      iconSize: const WidgetStatePropertyAll(_iconSize),
    );
  }

  GlassButtonStyle? _themeStyleOf(BuildContext context) => _prominent
      ? GlassProminentButtonStyle.maybeOf(context)
      : GlassButtonStyle.maybeOf(context);

  @override
  Widget build(BuildContext context) {
    final menu = menuChildren;
    if (menu != null) return _menuButton(context, menu);
    return _button(context);
  }

  static final _restingBody = MotionSelection(() => const GlassFrame());

  Widget _menuButton(BuildContext context, List<GlassMenuEntry> menu) {
    const states = <WidgetState>{};
    return RawGlassMenu(
      entries: menu,
      onPressed: onPressed,
      controller: menuController,
      semanticLabel: semanticLabel,
      label: _label(context, states, child),
      tint: GlassDynamicColor.maybeResolve(
        _lookOf(context).backgroundColor?.resolve(states),
        context,
      ),
      child: _defaultBody(
        context,
        GlassButtonDetails(
          body: _restingBody,
          states: states,
          label: child,
        ),
      ),
    );
  }

  Widget _button(BuildContext context) => GlassPressable(
    onPressed: onPressed,
    statesController: statesController,
    focusNode: focusNode,
    autofocus: autofocus,
    semanticLabel: semanticLabel,
    builder: style?.builder ?? _themeStyleOf(context)?.builder ?? _defaultBody,
    child: child,
  );

  GlassButtonStyle _lookOf(BuildContext context) =>
      (style ?? const GlassButtonStyle())
          .merge(_themeStyleOf(context))
          .merge(defaultStyleOf(context));

  Widget _defaultBody(BuildContext context, GlassButtonDetails details) {
    final states = details.states;
    final tint = _lookOf(context).backgroundColor?.resolve(states);
    return GlassSurface.live(
      frame: details.body,
      glass: _clear ? Glass.clear(tint: tint) : Glass.regular(tint: tint),
      child: _label(context, states, details.label),
    );
  }

  Widget _label(
    BuildContext context,
    Set<WidgetState> states,
    Widget label,
  ) {
    final look = _lookOf(context);
    T resolve<T>(WidgetStateProperty<T?>? property) =>
        property!.resolve(states) as T;
    final foreground = GlassDynamicColor.resolve(
      resolve<Color>(look.foregroundColor),
      context,
    );
    final icon = GlassDynamicColor.resolve(
      look.iconColor?.resolve(states) ?? foreground,
      context,
    );
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
              style: resolveGlassText(
                resolve<TextStyle>(
                  look.textStyle,
                ).copyWith(color: foreground),
                context,
              ),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame of a glass button at rest: a menu button's glass stands
/// still, the menu's motion lifts it.
