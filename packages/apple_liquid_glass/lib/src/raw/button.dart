import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/shape.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Builds a glass button from [details]; it runs when the button builds,
/// such as when its states change, never on a frame of its motion.
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
  /// glow, in the button's own box. A builder hands it to a
  /// [GlassSurface.live] that fills the button.
  final MotionSelection<GlassFrame> body;

  /// The states the button is in.
  final Set<WidgetState> states;

  /// The button's label.
  final Widget label;
}

/// Anything pressable with the measured press of an iOS 27 glass button and
/// no look of its own: [builder] decides how it looks.
///
/// UIKit: `UIButton` with a glass configuration. SwiftUI: `Button` with
/// `.buttonStyle(.glass)`. Flutter: `RawMaterialButton`.
///
/// A touch lifts the body, a finger that drags leans and stretches it
/// toward itself, and a glow follows the finger; a release within 70
/// points of the button presses it. All of that reaches the look through
/// [GlassButtonDetails.body], so the builder never runs while the button
/// moves. Space, Enter and the accessibility tap press it too. Under
/// Reduce Motion the body glows but never lifts or leans (an
/// approximation, not measured).
class GlassPressable extends StatefulWidget {
  /// Creates a button labeled [child] whose look [builder] builds.
  const GlassPressable({
    required this.onPressed,
    required this.builder,
    required this.child,
    this.shape = GlassShape.capsule,
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
  final GlassShape shape;

  /// Where the button writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The button's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the button takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the button; null lets its label speak.
  final String? semanticLabel;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable>
    with ControlStates<GlassPressable> {
  final GlassPress _press = GlassPress();
  late final List<Interaction> _interactions = [
    PressInteraction(
      releaseSlop: const EdgeInsets.all(GlassPress.highlightSlop),
      onTap: (t) => widget.onPressed?.call(),
    ).simultaneously(FollowInteraction(_press)),
  ];
  late MotionSelection<GlassFrame> _body = _bodyOf(widget.shape);

  MotionSelection<GlassFrame> _bodyOf(GlassShape shape) => _press.select(
    (press) => press.isAtRest
        ? GlassFrame(shape: shape)
        : GlassFrame(
            shape: shape,
            rect: (Offset.zero & press.size).shift(press.lean),
            scaleX: press.scaleX,
            scaleY: press.scaleY,
            glow: press.touchGlow,
          ),
  );

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  void didUpdateWidget(GlassPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shape != oldWidget.shape) _body = _bodyOf(widget.shape);
  }

  @override
  void writeStates() {
    final disabled = widget.onPressed == null;
    widgetStates.update(WidgetState.disabled, disabled);
    if (disabled) widgetStates.update(WidgetState.pressed, false);
  }

  @override
  Widget build(BuildContext context) {
    _press.reducedMotion = GlassTraits.of(context).reduceMotion;
    return Semantics(
      button: true,
      child: InputRegion(
        interactions: _interactions,
        enabled: widget.onPressed != null,
        statesController: widgetStates,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semanticLabel: widget.semanticLabel,
        child: widget.builder(
          context,
          GlassButtonDetails(
            body: _body,
            states: {...widgetStates.value},
            label: widget.child,
          ),
        ),
      ),
    );
  }
}
