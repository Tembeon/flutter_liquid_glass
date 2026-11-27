import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/raw/mirror.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// Builds a glass slider from [details]; it runs again when the slider's
/// states, width, stops or direction change, or when a different builder
/// is passed, never while it moves. A builder that is a new closure on
/// every build of the slider's parent rebuilds the look on each of them.
typedef GlassSliderBuilder = Widget Function(
  BuildContext context,
  GlassSliderDetails details,
);

/// What a [GlassSliderBuilder] builds a slider from.
@immutable
final class GlassSliderDetails {
  /// Describes a slider.
  const GlassSliderDetails({
    required this.track,
    required this.fill,
    required this.thumb,
    required this.ticks,
    required this.states,
    this.statesListenable,
  });

  /// The frames of the track in the slider's box: it stretches toward a
  /// finger dragged past an end and thins.
  final MotionSelection<GlassFrame> track;

  /// The frames of the fill from the track's start to the value.
  final MotionSelection<GlassFrame> fill;

  /// The frames of the thumb: where it sits, how it stretches, and how far
  /// a finger has lifted it into glass.
  final MotionSelection<GlassFrame> thumb;

  /// The centers of the tick marks in the slider's box, empty for a
  /// continuous slider.
  final List<Offset> ticks;

  /// The states the slider is in.
  final Set<WidgetState> states;

  /// The slider's states as they change, or null for a look that shows
  /// neither focus nor hover: a builder hands it to the `GlassSurface` of
  /// the thumb, whose renderer then draws the focus ring and the hover
  /// response.
  final ValueListenable<Set<WidgetState>>? statesListenable;
}

/// A slider with the measured motion of iOS 27's `UISlider` and no look of
/// its own: [builder] decides how it looks.
///
/// UIKit: `UISlider`. SwiftUI: `Slider`. Flutter: `CupertinoSlider`.
///
/// Only the thumb is a handle: a touch on it lifts it into a lens, a drag
/// maps the finger's travel onto the value by the full track width, a
/// release glides on, and a drag past an end stretches the whole track. A
/// tap on the track does nothing. With [ticks] the value snaps to evenly
/// spaced stops through UIKit's detent curve. A finger takes the thumb
/// within a 44 point tall area around the 34 point slider, where the
/// slider's parent leaves that room. The value commands of the arrow keys
/// (mirrored in right-to-left), Home and End, and the accessibility
/// increase and decrease step it, a continuous slider by a tenth of the
/// range (not measured) and a stepped one to the next stop on that side,
/// or take it to [min] and [max]; it has no
/// larger step, so Page Up and Page Down do nothing, and neither do Space
/// and Enter, as on Flutter's `Slider`. Under Reduce Motion the
/// thumb never lifts, as UIKit's does (read from UIKit, notes private), and
/// never stretches (an approximation, not measured); the track still
/// stretches past an end. In a right-to-left context the value grows to the
/// left. Without a bounded width the slider is 200 wide (not measured). A
/// dragging finger reaching an end or a stop plays UIKit's end or detent
/// haptic, approximated by a light impact and a selection click; a key or
/// an accessibility step plays none, and a `MotionHapticScope` turns them
/// off.
class RawGlassSlider extends StatefulWidget {
  /// Creates a slider showing [value] between [min] and [max].
  const RawGlassSlider({
    required this.value,
    required this.onChanged,
    required this.builder,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.ticks = 0,
    this.neutralValue,
    this.adjustmentStep,
    this.snapsToTicks = true,
    this.enabledBounds,
    this.animated = false,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticFormatterCallback,
    super.key,
  }) : assert(min < max, 'min must be less than max');

  /// The value shown. A new value that arrives during a drag or its glide
  /// waits until it ends.
  final double value;

  /// Called with each new value as the user drags, as the released thumb
  /// glides on, and on each key or accessibility step; null disables
  /// the slider. A slider whose [value] does not follow returns to it.
  final ValueChanged<double>? onChanged;

  /// Builds the slider's look.
  final GlassSliderBuilder builder;

  /// Called with the value when a finger touches the thumb, and before each
  /// key or accessibility step; [onChangeEnd] follows unless the
  /// slider is removed first.
  final ValueChanged<double>? onChangeStart;

  /// Called with the final value when the touch, its drag and its glide
  /// end, and after each key or accessibility step.
  final ValueChanged<double>? onChangeEnd;

  /// The value at the track's start.
  final double min;

  /// The value at the track's end.
  final double max;

  /// The number of stops the value snaps to; below two it is continuous. A
  /// value set between stops shows at the nearest stop, a tie at the lower
  /// one, without calling [onChanged], as UIKit snaps at rest.
  final int ticks;

  /// The value the fill starts from, toward the thumb on either side, or
  /// null for [min]: a balance or a pitch reads from its middle
  /// (`neutralValue`; slider passport, recheck 27.2).
  final double? neutralValue;

  /// How much a key or a screen reader's increase or decrease changes the
  /// value of a slider without [ticks], as SwiftUI's `Slider(step:)` and
  /// UIKit's `accessibilityIncrement` set it; null for a tenth of the
  /// range. A finger still moves it freely.
  final double? adjustmentStep;

  /// Whether the value snaps to [ticks]; false, UIKit's
  /// `allowsTickValuesOnly = false`, lets it track the finger freely and
  /// takes a tick only within 0.05 of the track from it.
  final bool snapsToTicks;

  /// The least and the most, between [min] and [max], a drag can take the
  /// value to, as UIKit's `enabledRange` and SwiftUI's `enabledBounds`;
  /// nothing is drawn for it.
  final (double, double)? enabledBounds;

  /// Whether a new [value] from outside moves the thumb on UIKit's
  /// programmatic spring instead of jumping; a stepped slider always jumps.
  final bool animated;

  /// Where the slider publishes its states, or null for its own. The slider is
  /// its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The slider's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the slider takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the slider.
  final String? semanticLabel;

  /// Formats the value screen readers read, and the values one step up and
  /// down; null reads it as a percentage of the range.
  final String Function(double value)? semanticFormatterCallback;

  /// The height of the slider, not measured.
  static const double height = 34;

  /// The diameter of a tick mark (slider passport).
  static const double tickSize = SliderMotion.tickSize;

  static const double _keyboardStep = 0.1;

  @override
  State<RawGlassSlider> createState() => _RawGlassSliderState();
}

class _RawGlassSliderState extends State<RawGlassSlider>
    with ControlStates<RawGlassSlider>, ControlledValue<RawGlassSlider> {
  late final SliderMotion _motion = SliderMotion(
    width: 0,
    value: _unit(widget.value),
    ticks: widget.ticks,
    onEvent: _deliver,
    clock: MotionClockScope.of(context),
  );
  late final _SliderInput _input = _SliderInput(
    motion: _motion,
    start: _start,
    end: _endUnlessGliding,
    command: _command,
  );
  late final List<Interaction> _interactions = [_input];
  late final MotionSelection<bool> _driving = _motion.select(_drivenBy);
  late _SliderFrames _frames = _SliderFrames(
    _motion,
    mirrored: false,
    neutral: _neutral,
  );
  Widget? _visual;
  Object? _visualKey;
  Set<WidgetState>? _visualStates;
  double? _reported;
  // Where the widget's value sat, 0 to 1, when the slider last returned
  // to it.
  late double _given = _unit(widget.value);
  bool _changing = false;

  @override
  WidgetStatesController? get statesController => widget.statesController;

  @override
  MotionClock get valueClock => _motion.clock;

  void _bound() {
    final bounds = widget.enabledBounds;
    _motion
      ..snapsToTicks = widget.snapsToTicks
      ..enabledMin = bounds == null ? 0 : _unit(bounds.$1)
      ..enabledMax = bounds == null ? 1 : _unit(bounds.$2);
  }

  static bool _drivenBy(SliderMotion motion) =>
      motion.isDragging || motion.isGliding;

  @override
  ValueListenable<bool> get userDriving => _driving;

  // A value or range new from outside moves as the widget says; a change
  // the parent refused snaps back.
  @override
  void syncFromWidget() {
    final given = _given;
    final unit = _given = _unit(widget.value);
    if (widget.value == _reported || unit == _motion.reportedValue) return;
    _motion.setValue(
      _motion.clock.now,
      unit,
      animated: widget.animated && unit != given,
    );
    _reported = widget.value;
  }

  @override
  void didUpdateWidget(RawGlassSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.ticks = widget.ticks;
    _bound();
    if (oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _reported = null;
    }
    if (_neutral != _frames.neutral) {
      _frames = _SliderFrames(
        _motion,
        mirrored: _frames.mirrored,
        neutral: _neutral,
      );
    }
  }

  double? get _neutral => switch (widget.neutralValue) {
    final value? => _unit(value),
    null => null,
  };

  double _unit(double value) => Ramp.fraction(value, widget.min, widget.max);

  double _out(double unit) => widget.min + unit * (widget.max - widget.min);

  void _deliver(SliderEvent event) {
    switch (event) {
      // A value during a drag or glide arms no return: the change ends
      // with SliderChangeEnded, which does, and the slider does not
      // rebuild on every value an app that does not follow ignores.
      case SliderChanged(:final value):
        runOutsideBuild(() => widget.onChanged?.call(_reported = _out(value)));
      case SliderChangeEnded(:final value):
        notifyChanged(() => _end(_out(value)));
      case SliderFelt(:final detent):
        (detent ? MotionHaptic.selection : MotionHaptic.lightImpact).play(
          context,
        );
    }
  }

  void _start() {
    if (_changing) return;
    _changing = true;
    widget.onChangeStart?.call(widget.value);
  }

  void _end(double value) {
    if (!_changing) return;
    _changing = false;
    widget.onChangeEnd?.call(value);
  }

  // A touch that never dragged, or left nothing to glide, raises no
  // SliderChangeEnded; it still ends the change it started.
  void _endUnlessGliding() {
    if (_drivenBy(_motion)) return;
    notifyChanged(() => _end(widget.value));
  }

  double _stepFrom(double from, int delta) {
    final ticks = widget.ticks;
    if (ticks < 2) {
      final step = switch (widget.adjustmentStep) {
        final step? when step > 0 => step / (widget.max - widget.min),
        _ => RawGlassSlider._keyboardStep,
      };
      return (from + delta * step).clamp(0.0, 1.0);
    }
    final steps = ticks - 1;
    final at = from * steps;
    // A stop the parent rounded sits a hair off it and still counts as it.
    final base = delta > 0 ? (at + 1e-6).floor() : (at - 1e-6).ceil();
    return (base + delta).clamp(0, steps) / steps;
  }

  void _command(ValueCommand command) {
    if (widget.onChanged == null) return;
    final from = _unit(widget.value);
    final unit = switch (command) {
      ValueCommand.increase => _stepFrom(from, 1),
      ValueCommand.decrease => _stepFrom(from, -1),
      ValueCommand.toMinimum => 0.0,
      ValueCommand.toMaximum => 1.0,
      ValueCommand.increaseLarge || ValueCommand.decreaseLarge => from,
    };
    if (unit == from) return;
    final value = _out(unit);
    _start();
    widget.onChanged?.call(value);
    _end(value);
  }

  Widget _visualFor(
    BuildContext context,
    double width,
    Set<WidgetState> states,
  ) {
    final frames = _frames;
    final key = (widget.builder, width, widget.ticks, frames);
    final visual = _visual;
    if (visual != null &&
        key == _visualKey &&
        setEquals(_visualStates, states)) {
      return visual;
    }
    _visualKey = key;
    _visualStates = states;
    return _visual = widget.builder(
      context,
      GlassSliderDetails(
        track: frames.track,
        fill: frames.fill,
        thumb: frames.thumb,
        ticks: frames.tickCenters(width, widget.ticks),
        states: states,
        statesListenable: widgetStates,
      ),
    );
  }

  void _measured(double t, Size size) => _motion.width = size.width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bound();
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl != _frames.mirrored) {
      _frames = _SliderFrames(_motion, mirrored: rtl, neutral: _neutral);
    }
  }

  @override
  Widget buildControl(BuildContext context) {
    final value = _unit(widget.value);
    final formatter = widget.semanticFormatterCallback;
    final percentValue = GlassLocalizations.of(context).percentValue;
    String percent(double unit) =>
        formatter?.call(_out(unit)) ?? percentValue(unit);
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _interactions,
        enabled: widget.onChanged != null,
        statesController: widgetStates,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semantics: SemanticsProperties(
          label: widget.semanticLabel,
          slider: true,
          value: percent(value),
          increasedValue: percent(_stepFrom(value, 1)),
          decreasedValue: percent(_stepFrom(value, -1)),
        ),
        reach: glassTargetReach,
        // The ticks of the first frame need the width at build; the motion
        // hears it from MotionMeasure after layout, where it may change.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 200.0;
            return MotionMeasure(
              onSize: _measured,
              child: SizedBox(
                width: width,
                height: RawGlassSlider.height,
                child: withStates(
                  (context, states) => _visualFor(context, width, states),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What a slider shows of its motion: the frames of its track, fill and
/// thumb, laid out left to right or mirrored.
final class _SliderFrames {
  _SliderFrames(this._motion, {required this.mirrored, this.neutral});

  final SliderMotion _motion;
  final bool mirrored;

  /// Where the fill starts, 0 to 1, or null for the track's start.
  final double? neutral;

  static const double _y = RawGlassSlider.height / 2;

  late final MotionSelection<GlassFrame> track = _motion.select((motion) {
    final ends = motion.trackEnds;
    final height = _trackHeight(motion);
    return GlassFrame(
      rect: _shown(
        Rect.fromLTRB(ends.left, _y - height / 2, ends.right, _y + height / 2),
      ),
    );
  });

  late final MotionSelection<GlassFrame> fill = _motion.select((motion) {
    final ends = motion.trackEnds;
    final height = _trackHeight(motion);
    final neutral = this.neutral;
    if (neutral != null) {
      // From the thumb's center at the neutral value to its center now.
      final width = motion.width;
      double at(double u) => width <= 0
          ? ends.left
          : ends.left +
                (SliderMotion.thumbSize.width / 2 + u * motion.travel) *
                    (ends.right - ends.left) /
                    width;
      final from = at(neutral);
      final to = at(motion.position);
      return GlassFrame(
        rect: _shown(
          Rect.fromLTRB(
            math.min(from, to),
            _y - height / 2,
            math.max(from, to),
            _y + height / 2,
          ),
        ),
      );
    }
    final end = motion.fillEnd.clamp(ends.left, double.infinity);
    return GlassFrame(
      rect: _shown(
        Rect.fromLTRB(ends.left, _y - height / 2, end, _y + height / 2),
      ),
    );
  });

  late final MotionSelection<GlassFrame> thumb = _motion.select((motion) {
    final t = motion.now;
    final lens = motion.lens;
    final size = lens.size(t);
    return GlassFrame(
      rect: _shown(
        Rect.fromCenter(
          center: Offset(motion.thumbCenter + lens.shift(t), _y),
          width: size.width * lens.scaleX(t),
          height: size.height * lens.scaleY(t),
        ),
      ),
      lift: lens.progress(t).clamp(0.0, 1.0),
    );
  });

  /// The tick centers of a slider [width] wide with [ticks] stops, from
  /// the width layout gives before the motion hears it.
  List<Offset> tickCenters(double width, int ticks) => [
    for (final x in SliderMotion.tickCentersFor(width, ticks))
      Offset(mirrored ? width - x : x, _y + SliderMotion.tickOffset),
  ];

  static double _trackHeight(SliderMotion motion) =>
      motion.currentTrackHeight.clamp(0.0, double.infinity);

  Rect _shown(Rect rect) => mirrored ? mirroredIn(rect, _motion.width) : rect;
}

/// A slider's touch: it takes a touch only on the thumb and holds it
/// against a scroll.
final class _SliderInput extends Interaction {
  _SliderInput({
    required this.motion,
    required this.start,
    required this.end,
    required this.command,
  }) : super(role: InteractionRole.control);

  final SliderMotion motion;
  final VoidCallback start;
  final VoidCallback end;
  final ValueChanged<ValueCommand> command;
  bool _touching = false;
  bool _mirrored = false;
  double _width = 0;

  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.adjustment};

  @override
  bool get pressed => _touching;

  @override
  bool get dragged => _touching && motion.isDragging;

  PointerDownInput _local(PointerDownInput down) =>
      down.textDirection == TextDirection.rtl
      ? down.mirrored(down.regionSize.width)
      : down;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && motion.hitsThumb(_local(down).position.dx);

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case AdjustInput(command: final asked):
        command(asked);
      case PointerDownInput() when !accepts(input):
        // A delivery held for a scroll may come after the thumb moved away.
        return const InteractionUpdate(fails: true);
      case PointerDownInput() when accepts(input):
        _touching = true;
        _mirrored = input.textDirection == TextDirection.rtl;
        _width = input.regionSize.width;
        start();
        motion.pointerDown(input.time, _local(input).position.dx);
        return const InteractionUpdate(verdict: .claimed);
      case PointerMoveInput() when _touching:
        final began = motion.isDragging;
        final local = _mirrored ? input.mirrored(_width) : input;
        motion.pointerMove(input.time, local.position.dx);
        // UISlider keeps a pan along its track that starts on the thumb
        // from the views around it (gestureRecognizerShouldBegin:), so a
        // sheet's pan no longer takes the touch once the slider's began.
        if (!began && motion.isDragging) {
          return const InteractionUpdate(verdict: .recognized);
        }
      case PointerUpInput() when _touching:
        _touching = false;
        final local = _mirrored ? input.mirrored(_width) : input;
        motion.pointerUp(
          input.time,
          local.position.dx,
          velocity: local.velocity.dx,
        );
        end();
        return const InteractionUpdate(verdict: .recognized);
      case PointerCancelInput() when _touching:
        _touching = false;
        motion.pointerCancel(
          input.time,
          revert: input.reason == PointerCancelReason.taken,
        );
        end();
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
