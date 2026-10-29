import 'package:apple_liquid_glass/src/motion/switch_motion.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Builds a glass switch from [details]; it runs again when the switch's
/// states change, never while it moves.
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
  final ValueListenable<GlassFrame> thumb;

  /// How far the track has turned on, 0 off and 1 on.
  final ValueListenable<double> progress;

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

class _RawGlassSwitchState extends State<RawGlassSwitch> {
  late final _SwitchBody _body = _SwitchBody(_deliver, value: widget.value);
  late final _SwitchInput _input = _SwitchInput(
    body: _body,
    toggle: () => widget.onChanged?.call(!widget.value),
  );
  late final List<Interaction> _interactions = [_input];
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
  void didUpdateWidget(RawGlassSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = oldWidget.statesController ?? _ownStates;
    if (!identical(states, _states)) {
      states?.removeListener(_statesChanged);
      _states.addListener(_statesChanged);
    }
    _writeStates();
    _body.setValue(value: widget.value);
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
    final disabled = widget.onChanged == null;
    _states.update(WidgetState.disabled, disabled);
    if (disabled) _states.update(WidgetState.pressed, false);
    _states.update(WidgetState.selected, widget.value);
  }

  void _statesChanged() => setState(() {});

  void _deliver(SwitchEvent event) {
    switch (event) {
      case SwitchChanged(:final on):
        if (on != widget.value) widget.onChanged?.call(on);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _body.setValue(value: widget.value);
        });
      case SwitchShown():
        HapticFeedback.lightImpact().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    _body.reducedMotion = GlassTraits.of(context).reduceMotion;
    _input.mirrored = Directionality.maybeOf(context) == TextDirection.rtl;
    _body.mirrored = _input.mirrored;
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: Semantics(
        toggled: widget.value,
        child: InputRegion(
          interactions: _interactions,
          enabled: widget.onChanged != null,
          statesController: _states,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          semanticLabel: widget.semanticLabel,
          child: SizedBox.fromSize(
            size: RawGlassSwitch.size,
            child: widget.builder(
              context,
              GlassSwitchDetails(
                thumb: _body.thumb,
                progress: _body.progress,
                states: {..._states.value},
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The motion of a switch, stepped on the motion clock and published as
/// the knob's frame and the track's progress.
final class _SwitchBody implements MotionDriver {
  _SwitchBody(this._deliver, {required bool value})
    : _motion = SwitchMotion(
        value: value,
        frameRate: MotionClock.instance.frameRate,
      ) {
    _publish();
  }

  final SwitchMotion _motion;
  final void Function(SwitchEvent event) _deliver;
  final thumb = ValueNotifier(const GlassFrame());
  final progress = ValueNotifier<double>(0);

  bool _mirrored = false;
  bool get mirrored => _mirrored;
  set mirrored(bool value) {
    if (value == _mirrored) return;
    _mirrored = value;
    _publish();
  }

  bool get reducedMotion => _motion.reducedMotion;
  set reducedMotion(bool value) => _motion.reducedMotion = value;

  @override
  bool get isActive => !_motion.isSettled;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _motion.advance(time);
    if (_motion.isSettled) _motion.settle();
    _publish();
  }

  void _publish() {
    final t = _motion.time;
    final lens = _motion.lens;
    final size = lens.size(t);
    final width = size.width * lens.scaleX(t);
    final height = size.height * lens.scaleY(t);
    var x =
        SwitchMotion.inset +
        SwitchMotion.knobSize.width / 2 +
        _motion.knob +
        lens.shift(t);
    if (_mirrored) x = SwitchMotion.trackSize.width - x;
    thumb.value = GlassFrame(
      rect: Rect.fromCenter(
        center: Offset(x, SwitchMotion.trackSize.height / 2),
        width: width,
        height: height,
      ),
      lift: lens.progress(t).clamp(0.0, 1.0),
    );
    progress.value = _motion.color;
  }

  void _drain() {
    for (final event in _motion.drainEvents()) {
      _deliver(event);
    }
  }

  void _wake() => MotionClock.instance.wake(this);

  void setValue({required bool value}) {
    if (value == _motion.value) return;
    _motion.setValue(MotionClock.instance.now, value: value);
    _wake();
  }

  void down(double t, double x) {
    _motion.pointerDown(t, x);
    _wake();
  }

  void move(double t, double x) {
    _motion.pointerMove(t, x);
    _drain();
    _wake();
  }

  void up(double t, double x) {
    _motion.pointerUp(t, x);
    _drain();
    _wake();
  }

  void cancel(double t) {
    _motion.pointerCancel(t);
    _wake();
  }

  void dispose() {
    thumb.dispose();
    progress.dispose();
  }
}

/// A switch's touch: the press tracks the highlight and holds the touch
/// against a scroll, the body follows the finger, and an activation toggles.
final class _SwitchInput extends PressInteraction {
  _SwitchInput({required this.body, required this.toggle});

  final _SwitchBody body;
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
        body.down(input.time, _x(input.position));
      case PointerMoveInput() when input.pointer == _pointer:
        body.move(input.time, _x(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        body.up(input.time, _x(input.position));
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        body.cancel(input.time);
      default:
    }
    return super.handle(input);
  }
}

/// The look of a [GlassSwitch], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the switch's states. A
/// switch looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSwitchStyle {
  /// Creates a style.
  const GlassSwitchStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.builder,
  });

  /// The fill of the resting knob (UIKit `thumbTintColor`).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track when on (UIKit `onTintColor`).
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track when off.
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// Builds the switch's look in place of the default one; the switch then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSwitchBuilder? builder;

  /// This style over [other], state by state.
  GlassSwitchStyle merge(GlassSwitchStyle? other) {
    if (other == null) return this;
    return GlassSwitchStyle(
      thumbColor: fallThrough(thumbColor, other.thumbColor),
      activeTrackColor: fallThrough(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: fallThrough(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassSwitchStyle? lerp(
    GlassSwitchStyle? a,
    GlassSwitchStyle? b,
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
    return GlassSwitchStyle(
      thumbColor: color(a.thumbColor, b.thumbColor),
      activeTrackColor: color(a.activeTrackColor, b.activeTrackColor),
      inactiveTrackColor: color(a.inactiveTrackColor, b.inactiveTrackColor),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSwitchStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.builder == builder;

  @override
  int get hashCode =>
      Object.hash(thumbColor, activeTrackColor, inactiveTrackColor, builder);
}

/// An iOS 27 switch.
///
/// UIKit: `UISwitch`. SwiftUI: `Toggle` with the switch style. Flutter:
/// `CupertinoSwitch`.
///
/// Its track is a plain fill and its knob a platter that turns into glass
/// under the finger, drawn by the ambient renderer; its motion is
/// [RawGlassSwitch]'s. A disabled switch draws at half opacity, as UIKit
/// does (iPhone 16 Pro, light and dark, on and off).
class GlassSwitch extends StatelessWidget {
  /// Creates a switch showing [value].
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when the user toggles the switch; null
  /// disables it.
  final ValueChanged<bool>? onChanged;

  /// The look, over the theme's and the switch's defaults.
  final GlassSwitchStyle? style;

  /// Where the switch writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The switch's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the switch takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the switch.
  final String? semanticLabel;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassSwitchStyle styleFrom({
    Color? thumbColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
  }) => GlassSwitchStyle(
    thumbColor: allStates(thumbColor),
    activeTrackColor: allStates(activeTrackColor),
    inactiveTrackColor: allStates(inactiveTrackColor),
  );

  /// UISwitch's off track: secondarySystemFill, and under Increase Contrast
  /// its own color, 78 percent of 0x787880 in light and 90 in dark (read
  /// from UIKit's color tables, notes private; not rendered on a device).
  static const inactiveTrack = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x29787880),
    darkColor: Color(0x52787880),
    highContrastColor: Color(0xC7787880),
    darkHighContrastColor: Color(0xE5787880),
  );

  static const _disabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassSwitchStyle()).merge(
      GlassTheme.of(context).switchStyle,
    );
    return RawGlassSwitch(
      value: value,
      onChanged: onChanged,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      builder:
          look.builder ??
          (context, details) => _defaultBody(context, details, look),
    );
  }

  Widget _defaultBody(
    BuildContext context,
    GlassSwitchDetails details,
    GlassSwitchStyle look,
  ) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    final off = resolve(look.inactiveTrackColor, inactiveTrack);
    final on = resolve(look.activeTrackColor, GlassColors.systemGreen);
    final body = Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.track,
            frame: _TrackFrames(details.progress, off, on),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.knob,
            glass: Glass.regular(
              tint: resolve(look.thumbColor, const Color(0xFFFFFFFF)),
            ),
            frame: details.thumb,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? _disabledOpacity : 1,
      child: body,
    );
  }
}

/// The track's frames: the off color turning into the on color with the
/// switch's progress.
@immutable
final class _TrackFrames implements ValueListenable<GlassFrame> {
  const _TrackFrames(this.progress, this.off, this.on);

  final ValueListenable<double> progress;
  final Color off;
  final Color on;

  @override
  GlassFrame get value =>
      GlassFrame(tint: Color.lerp(off, on, progress.value.clamp(0.0, 1.0)));

  @override
  void addListener(VoidCallback listener) => progress.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      progress.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is _TrackFrames &&
      other.progress == progress &&
      other.off == off &&
      other.on == on;

  @override
  int get hashCode => Object.hash(progress, off, on);
}
