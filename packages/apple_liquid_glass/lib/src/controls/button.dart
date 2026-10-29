import 'package:apple_liquid_glass/src/motion/glass_button_motion.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
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
    // Written before the region does, so the region's write changes nothing
    // and never asks this ancestor to rebuild while it builds.
    _states.update(WidgetState.disabled, widget.onPressed == null);
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
    _states.update(WidgetState.disabled, widget.onPressed == null);
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

  void _statesChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    _body.reducedMotion =
        MotionAccessibility.reduceMotion ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
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

/// The look of a [GlassButton], like Flutter's `ButtonStyle`: every field
/// but [builder] is resolved against the button's states, and a null field
/// or a null resolved value takes the button's default.
@immutable
class GlassButtonStyle {
  /// Creates a style.
  const GlassButtonStyle({
    this.glass,
    this.foregroundColor,
    this.padding,
    this.minimumSize,
    this.builder,
  });

  /// The glass of the body.
  final WidgetStateProperty<Glass?>? glass;

  /// The color of the label's text and icons.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The space around the label.
  final WidgetStateProperty<EdgeInsetsGeometry?>? padding;

  /// The smallest size of the button.
  final WidgetStateProperty<Size?>? minimumSize;

  /// Builds the button's look in place of the default one, which then
  /// ignores the other fields; null keeps the default.
  final GlassButtonBuilder? builder;
}

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
    super.key,
  }) : _prominent = false;

  /// Creates a prominent glass button, filled with the accent color.
  ///
  /// UIKit: `UIButton.Configuration.prominentGlass()`. SwiftUI:
  /// `.buttonStyle(.glassProminent)`. A disabled one is filled with
  /// systemGray4.
  const GlassButton.prominent({
    required this.onPressed,
    required this.child,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : _prominent = true;

  /// Called when the button is pressed; null disables it.
  final VoidCallback? onPressed;

  /// The label.
  final Widget child;

  /// The look, over the button's defaults.
  final GlassButtonStyle? style;

  /// Where the button writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The button's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the button takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the button; null lets its label speak.
  final String? semanticLabel;

  final bool _prominent;

  // iOS 27's systemBlue as rendered, systemGray4 and tertiaryLabel.
  static const _systemBlue = Color(0xFF0088FF);
  static const _darkSystemBlue = Color(0xFF0091FF);
  static const _systemGray4 = Color(0xFFD1D1D6);
  static const _darkSystemGray4 = Color(0xFF3A3A3C);
  static const _tertiaryLabel = Color(0x4C3C3C43);
  static const _darkTertiaryLabel = Color(0x4CEBEBF5);

  // UIKit's title style, 17 regular (typography passport). The glyph size,
  // insets and minimum size are not measured (glass-button passport).
  static const _labelStyle = TextStyle(fontSize: 17);
  static const _iconSize = 22.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 11);
  static const _minimumSize = Size(44, 44);

  @override
  Widget build(BuildContext context) => RawGlassButton(
    onPressed: onPressed,
    statesController: statesController,
    focusNode: focusNode,
    autofocus: autofocus,
    semanticLabel: semanticLabel,
    builder: style?.builder ?? _body,
    child: child,
  );

  Widget _body(BuildContext context, GlassButtonDetails details) {
    final states = details.states;
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    final disabled = states.contains(WidgetState.disabled);
    final glass =
        style?.glass?.resolve(states) ??
        (_prominent
            ? Glass.regular(
                tint: disabled
                    ? (dark ? _darkSystemGray4 : _systemGray4)
                    : (dark ? _darkSystemBlue : _systemBlue),
              )
            : const Glass.regular());
    final foreground =
        style?.foregroundColor?.resolve(states) ??
        (disabled
            ? (dark ? _darkTertiaryLabel : _tertiaryLabel)
            : _prominent || dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000));
    final padding = style?.padding?.resolve(states) ?? _padding;
    final minimumSize = style?.minimumSize?.resolve(states) ?? _minimumSize;
    return GlassSurface.live(
      frame: details.body,
      glass: glass,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minimumSize.width,
          minHeight: minimumSize.height,
        ),
        child: Padding(
          padding: padding,
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: IconTheme.merge(
              data: IconThemeData(color: foreground, size: _iconSize),
              child: DefaultTextStyle.merge(
                style: _labelStyle.copyWith(color: foreground),
                child: details.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
