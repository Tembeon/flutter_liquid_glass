import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/src/menu/anchor.dart';
import 'package:apple_liquid_glass/src/menu/entries.dart';
import 'package:apple_liquid_glass/src/motion/glass_button_motion.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Builds a glass button from [details]; it runs again when the button's
/// states change, never while the button moves.
typedef GlassButtonBuilder = Widget Function(
  BuildContext context,
  GlassButtonDetails details,
);

/// What a [GlassButtonBuilder] builds a button from.
@immutable
final class GlassButtonDetails {
  /// Describes a button.
  const GlassButtonDetails({
    required this.body,
    required this.states,
    required this.label,
  });

  /// The frames of the button's body: the measured lift, lean and touch
  /// glow, in the button's own box. The button keeps this listenable for
  /// its whole life; a builder hands it to a [GlassSurface.live] that fills
  /// the button.
  final ValueListenable<GlassFrame> body;

  /// The states the button is in.
  final Set<WidgetState> states;

  /// The button's label.
  final Widget label;
}

/// A button with the measured press of an iOS 27 glass button and no look
/// of its own: [builder] decides how it looks.
///
/// UIKit: `UIButton` with a glass configuration. SwiftUI: `Button` with
/// `.buttonStyle(.glass)`. Flutter: `RawMaterialButton`.
///
/// A touch lifts the body, a finger that drags leans and stretches it
/// toward itself, and a glow follows the finger; a release within 70
/// points of the button presses it. All of that reaches the look through
/// [GlassButtonDetails.body], so the builder never runs while the button
/// moves. Space, Enter and the accessibility tap press it too. Reduce
/// Motion keeps the glow and drops the lift and the lean.
class RawGlassButton extends StatefulWidget {
  /// Creates a button labeled [child] whose look [builder] builds.
  const RawGlassButton({
    required this.onPressed,
    required this.builder,
    required this.child,
    this.shape = GlassFrame.capsule,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Called when the button is pressed; null disables it.
  final VoidCallback? onPressed;

  /// Builds the button's look.
  final GlassButtonBuilder builder;

  /// The button's label.
  final Widget child;

  /// The outline of the button's body.
  final LiquidShape shape;

  /// Where the button writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The button's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the button takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the button; null lets its label speak.
  final String? semanticLabel;

  @override
  State<RawGlassButton> createState() => _RawGlassButtonState();
}

class _RawGlassButtonState extends State<RawGlassButton> {
  late final _ButtonBody _body = _ButtonBody(widget.shape);
  late final List<Interaction> _interactions = [
    PressInteraction(
      releaseSlop: const EdgeInsets.all(GlassButtonMotion.highlightSlop),
      onTap: () => widget.onPressed?.call(),
    ).simultaneously(_FlexInput(_body)),
  ];
  WidgetStatesController? _ownStates;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownStates ??= WidgetStatesController());

  @override
  void initState() {
    super.initState();
    _writeStates();
    _states.addListener(_statesChanged);
    MotionClock.instance.addDriver(_body);
  }

  @override
  void didUpdateWidget(RawGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = oldWidget.statesController ?? _ownStates;
    if (!identical(states, _states)) {
      states?.removeListener(_statesChanged);
      _states.addListener(_statesChanged);
    }
    _writeStates();
    _body.shape = widget.shape;
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownStates?.dispose();
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    super.dispose();
  }

  // The region writes disabled too, and ends a press when disabled;
  // writing both first makes its writes no-ops, so it never asks this
  // ancestor to rebuild while it builds.
  void _writeStates() {
    final disabled = widget.onPressed == null;
    _states.update(WidgetState.disabled, disabled);
    if (disabled) _states.update(WidgetState.pressed, false);
  }

  void _statesChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    _body.reducedMotion = GlassTraits.of(context).reduceMotion;
    return Semantics(
      button: true,
      child: InputRegion(
        interactions: _interactions,
        enabled: widget.onPressed != null,
        statesController: _states,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semanticLabel: widget.semanticLabel,
        child: widget.builder(
          context,
          GlassButtonDetails(
            body: _body,
            states: {..._states.value},
            label: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The body of a glass button: its measured motion stepped on the motion
/// clock, published as a [GlassFrame] when it changes.
final class _ButtonBody extends ChangeNotifier
    implements ValueListenable<GlassFrame>, MotionDriver {
  _ButtonBody(this._shape) : _value = GlassFrame(shape: _shape);

  LiquidShape _shape;
  GlassFrame _value;
  GlassButtonMotion? _motion;
  bool _shapeChanged = false;

  bool reducedMotion = false;

  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (value == _shape) return;
    _shape = value;
    _shapeChanged = true;
    MotionClock.instance.wake(this);
  }

  @override
  GlassFrame get value => _value;

  @override
  bool get isActive => _shapeChanged || !(_motion?.isSettled ?? true);

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _shapeChanged = false;
    final motion = _motion;
    if (motion != null) {
      motion.advance(time);
      if (motion.isSettled) motion.settle();
    }
    final next = motion == null || motion.isAtRest
        ? GlassFrame(shape: _shape)
        : GlassFrame(
            shape: _shape,
            rect: (Offset.zero & motion.size).shift(motion.lean),
            scaleX: motion.scaleX,
            scaleY: motion.scaleY,
            glow: motion.touchGlow,
          );
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  void down(double time, Offset position, Size size) {
    final motion = _motion ??= GlassButtonMotion(size: size);
    motion.size = size;
    motion.reducedMotion = reducedMotion;
    motion.pointerDown(time, position);
    MotionClock.instance.wake(this);
  }

  void move(double time, Offset position) {
    _motion?.pointerMove(time, position);
    MotionClock.instance.wake(this);
  }

  void up(double time, Offset position) {
    _motion?.pointerUp(time, position);
    MotionClock.instance.wake(this);
  }

  void cancel(double time) {
    _motion?.pointerCancel(time);
    MotionClock.instance.wake(this);
  }
}

/// Feeds one touch of the button to its body; the press decides what the
/// touch does, this only follows it.
final class _FlexInput extends Interaction {
  _FlexInput(this._body) : super(role: InteractionRole.control);

  final _ButtonBody _body;
  int? _pointer;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null:
        _pointer = input.pointer;
        _body.down(input.time, input.position, input.regionSize);
      case PointerMoveInput() when input.pointer == _pointer:
        _body.move(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _body.up(input.time, input.position);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _body.cancel(input.time);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The look of a [GlassButton], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the button's states. A
/// button looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one, and `WidgetStatePropertyAll(null)`
/// hands every state on. [merge] combines two styles the same way.
@immutable
class GlassButtonStyle {
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
  /// ignores the other fields. Null keeps the default.
  final GlassButtonBuilder? builder;

  /// This style over [other], state by state.
  GlassButtonStyle merge(GlassButtonStyle? other) {
    if (other == null) return this;
    return GlassButtonStyle(
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
  }) => GlassButtonStyle(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    iconColor: iconColor ?? this.iconColor,
    textStyle: textStyle ?? this.textStyle,
    padding: padding ?? this.padding,
    minimumSize: minimumSize ?? this.minimumSize,
    iconSize: iconSize ?? this.iconSize,
    builder: builder ?? this.builder,
  );

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassButtonStyle? lerp(
    GlassButtonStyle? a,
    GlassButtonStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return GlassButtonStyle(
      backgroundColor: WidgetStateProperty.lerp<Color?>(
        a.backgroundColor,
        b.backgroundColor,
        t,
        snapNull(GlassDynamicColor.lerp),
      ),
      foregroundColor: WidgetStateProperty.lerp<Color?>(
        a.foregroundColor,
        b.foregroundColor,
        t,
        snapNull(GlassDynamicColor.lerp),
      ),
      iconColor: WidgetStateProperty.lerp<Color?>(
        a.iconColor,
        b.iconColor,
        t,
        snapNull(GlassDynamicColor.lerp),
      ),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        a.textStyle,
        b.textStyle,
        t,
        snapNull(TextStyle.lerp),
      ),
      padding: WidgetStateProperty.lerp<EdgeInsetsGeometry?>(
        a.padding,
        b.padding,
        t,
        snapNull(EdgeInsetsGeometry.lerp),
      ),
      minimumSize: WidgetStateProperty.lerp<Size?>(
        a.minimumSize,
        b.minimumSize,
        t,
        snapNull(Size.lerp),
      ),
      iconSize: WidgetStateProperty.lerp<double?>(
        a.iconSize,
        b.iconSize,
        t,
        snapNull(lerpDouble),
      ),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassButtonStyle &&
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

enum _Variant { regular, prominent, clear, prominentClear }

/// An iOS 27 glass button.
///
/// UIKit: `UIButton.Configuration.glass()`. SwiftUI:
/// `.buttonStyle(.glass)`. Flutter: `FilledButton`.
///
/// Its body is a [GlassSurface] of the ambient renderer, its press the
/// measured one of [RawGlassButton]. A disabled regular button keeps its
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
  /// UIKit: `UIButton.menu`. SwiftUI: `Menu`. Flutter: `MenuAnchor`.
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
    final theme = GlassTheme.of(context);
    final scheme = theme.colorScheme;
    final disabledLabel = scheme?.tertiaryLabel ?? GlassColors.tertiaryLabel;
    final label = _prominent ? _white : scheme?.label ?? GlassColors.label;
    return GlassButtonStyle(
      backgroundColor: _prominent
          ? ByState<Color>(
              theme.primaryColor ?? GlassColors.systemBlue,
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

  GlassButtonStyle? _themeStyleOf(BuildContext context) {
    final theme = GlassTheme.of(context);
    return _prominent ? theme.prominentButtonStyle : theme.buttonStyle;
  }

  @override
  Widget build(BuildContext context) {
    final menu = menuChildren;
    if (menu != null) return _menuButton(context, menu);
    return _button(context);
  }

  Widget _menuButton(BuildContext context, List<GlassMenuEntry> menu) {
    const states = <WidgetState>{};
    return MenuAnchor(
      entries: menu,
      trigger: onPressed == null ? MenuTrigger.tap : MenuTrigger.hold,
      onTap: onPressed,
      controller: menuController,
      semanticLabel: semanticLabel,
      look: _label(context, states, child),
      face: _defaultBody(
        context,
        GlassButtonDetails(
          body: const _Resting(),
          states: states,
          label: child,
        ),
      ),
    );
  }

  Widget _button(BuildContext context) => RawGlassButton(
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
final class _Resting implements ValueListenable<GlassFrame> {
  const _Resting();

  @override
  GlassFrame get value => const GlassFrame();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
