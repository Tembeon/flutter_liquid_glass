import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:apple_liquid_glass/src/motions/switch_motion.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Builds a glass switch from [details]; it runs when the switch builds,
/// such as when its states change, never on a frame of its motion.
typedef GlassSwitchBuilder = Widget Function(
  BuildContext context,
  GlassSwitchDetails details,
);

/// What a [GlassSwitchBuilder] builds a switch from.
@immutable
final class GlassSwitchDetails {
  /// Describes a switch.
  const GlassSwitchDetails({
    required this.thumb,
    required this.progress,
    required this.states,
  });

  /// The frames of the knob in the switch's 63 x 28 box: where it sits,
  /// how it stretches, and how far a finger has lifted it into glass.
  final MotionSelection<GlassFrame> thumb;

  /// How far the track has turned on, 0 off and 1 on.
  final MotionSelection<double> progress;

  /// The states the switch is in; [WidgetState.selected] when it is on.
  final Set<WidgetState> states;
}

/// A switch with the measured motion of iOS 27's `UISwitch` and no look of
/// its own: [builder] decides how it looks.
///
/// UIKit: `UISwitch`. SwiftUI: `Toggle`. Flutter: `CupertinoSwitch`.
///
/// The knob lifts into a clear lens under the finger, a tap toggles on
/// release, and a drag carries the knob with a rubber band past the ends
/// and flips the shown state every 25 points toward the other one. In a
/// right-to-left context on is to the left. Space, Enter and the
/// accessibility tap toggle it. Under Reduce Motion the knob travels
/// without lifting, growing or rubber-banding, as UIKit's does, and without
/// stretching, an approximation. A touch that changes the shown state plays
/// a light impact, as UIKit does (read from UIKit, notes private).
class RawGlassSwitch extends StatefulWidget {
  /// Creates a switch showing [value].
  const RawGlassSwitch({
    required this.value,
    required this.onChanged,
    required this.builder,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when the user toggles the switch; null
  /// disables it. A switch whose [value] does not follow returns to it.
  final ValueChanged<bool>? onChanged;

  /// Builds the switch's look.
  final GlassSwitchBuilder builder;

  /// Where the switch writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The switch's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the switch takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the switch.
  final String? semanticLabel;

  /// The size of the switch: UISwitch's 63 x 28 track.
  static const Size size = SwitchMotion.trackSize;

  @override
  State<RawGlassSwitch> createState() => _RawGlassSwitchState();
}

class _RawGlassSwitchState extends State<RawGlassSwitch>
    with ControlStates<RawGlassSwitch> {
  late final SwitchMotion _motion = SwitchMotion(
    value: widget.value,
    frameRate: MotionClock.instance.frameRate,
    onEvent: _deliver,
  );
  late final _SwitchInput _input = _SwitchInput(
    motion: _motion,
    toggle: () => widget.onChanged?.call(!widget.value),
  );
  late final List<Interaction> _interactions = [_input];
  late MotionSelection<GlassFrame> _thumb = _thumbOf(mirrored: false);
  late final MotionSelection<double> _progress = _motion.select(
    (motion) => motion.color,
  );

  MotionSelection<GlassFrame> _thumbOf({required bool mirrored}) =>
      _motion.select((motion) {
        final t = motion.now;
        final lens = motion.lens;
        final size = lens.size(t);
        var x =
            SwitchMotion.inset +
            SwitchMotion.knobSize.width / 2 +
            motion.knob +
            lens.shift(t);
        if (mirrored) x = SwitchMotion.trackSize.width - x;
        return GlassFrame(
          rect: Rect.fromCenter(
            center: Offset(x, SwitchMotion.trackSize.height / 2),
            width: size.width * lens.scaleX(t),
            height: size.height * lens.scaleY(t),
          ),
          lift: lens.progress(t).clamp(0.0, 1.0),
        );
      });

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  void didUpdateWidget(RawGlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _setValue(widget.value);
  }

  @override
  void writeStates() {
    final disabled = widget.onChanged == null;
    widgetStates.update(WidgetState.disabled, disabled);
    if (disabled) widgetStates.update(WidgetState.pressed, false);
    widgetStates.update(WidgetState.selected, widget.value);
  }

  void _setValue(bool value) {
    if (value == _motion.value) return;
    _motion.setValue(MotionClock.instance.now, value: value);
  }

  void _deliver(SwitchEvent event) {
    switch (event) {
      case SwitchChanged(:final on):
        if (on != widget.value) widget.onChanged?.call(on);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setValue(widget.value);
        });
      case SwitchShown():
        MotionHaptic.lightImpact.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    _motion.reducedMotion = GlassTraits.of(context).reduceMotion;
    final mirrored = Directionality.maybeOf(context) == TextDirection.rtl;
    if (mirrored != _input.mirrored) {
      _input.mirrored = mirrored;
      _thumb = _thumbOf(mirrored: mirrored);
    }
    return MotionScope(
      motion: _motion,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Semantics(
          toggled: widget.value,
          child: InputRegion(
            interactions: _interactions,
            enabled: widget.onChanged != null,
            statesController: widgetStates,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            semanticLabel: widget.semanticLabel,
            child: SizedBox.fromSize(
              size: RawGlassSwitch.size,
              child: widget.builder(
                context,
                GlassSwitchDetails(
                  thumb: _thumb,
                  progress: _progress,
                  states: {...widgetStates.value},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch's touch: the press tracks the highlight and holds the touch
/// against a scroll, the motion follows the finger, and an activation
/// toggles.
final class _SwitchInput extends PressInteraction {
  _SwitchInput({required this.motion, required this.toggle});

  final SwitchMotion motion;
  final VoidCallback toggle;
  bool mirrored = false;
  int? _pointer;

  double _x(Offset position) =>
      mirrored ? RawGlassSwitch.size.width - position.dx : position.dx;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case ActivateInput():
        toggle();
        return InteractionUpdate(
          events: [ActivationEvent(time: input.time, source: input.source)],
        );
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        motion.pointerDown(input.time, _x(input.position));
      case PointerMoveInput() when input.pointer == _pointer:
        motion.pointerMove(input.time, _x(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        motion.pointerUp(input.time, _x(input.position));
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        motion.pointerCancel(input.time);
      default:
    }
    return super.handle(input);
  }
}
