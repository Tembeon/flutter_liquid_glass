import 'package:apple_liquid_glass/src/motion/slider_motion.dart';
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
  });

  /// The frames of the track in the slider's box: it stretches toward a
  /// finger dragged past an end and thins.
  final ValueListenable<GlassFrame> track;

  /// The frames of the fill from the track's start to the value.
  final ValueListenable<GlassFrame> fill;

  /// The frames of the thumb: where it sits, how it stretches, and how far
  /// a finger has lifted it into glass.
  final ValueListenable<GlassFrame> thumb;

  /// The centers of the tick marks in the slider's box, empty for a
  /// continuous slider.
  final List<Offset> ticks;

  /// The states the slider is in.
  final Set<WidgetState> states;
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
/// spaced stops through UIKit's detent curve. The arrow keys and the
/// accessibility increase and decrease step it. Under Reduce Motion the
/// thumb never lifts, as UIKit's does (read from UIKit, notes private), and
/// never stretches (an approximation, not measured); the track still
/// stretches past an end. In a right-to-left context the value grows to the
/// left. Without a bounded width the slider is 200 wide (not measured). A
/// dragging finger reaching an end or a stop plays UIKit's end or detent
/// haptic, approximated by a light impact and a selection click.
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
    this.animated = false,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  }) : assert(min < max, 'min must be less than max');

  /// The value shown. A new value that arrives during a drag or its glide
  /// waits until it ends.
  final double value;

  /// Called with each new value as the user drags, as the released thumb
  /// glides on, and on each arrow-key or accessibility step; null disables
  /// the slider. A slider whose [value] does not follow returns to it.
  final ValueChanged<double>? onChanged;

  /// Builds the slider's look.
  final GlassSliderBuilder builder;

  /// Called with the value when a finger touches the thumb, and before each
  /// arrow-key or accessibility step; [onChangeEnd] follows unless the
  /// slider is removed first.
  final ValueChanged<double>? onChangeStart;

  /// Called with the final value when the touch, its drag and its glide
  /// end, and after each arrow-key or accessibility step.
  final ValueChanged<double>? onChangeEnd;

  /// The value at the track's start.
  final double min;

  /// The value at the track's end.
  final double max;

  /// The number of stops the value snaps to; below two it is continuous. A
  /// value set between stops shows there until a drag or a key step moves
  /// it onto a stop.
  final int ticks;

  /// Whether a new [value] from outside moves the thumb on UIKit's
  /// programmatic spring instead of jumping; a stepped slider always jumps.
  final bool animated;

  /// Where the slider writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The slider's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the slider takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the slider.
  final String? semanticLabel;

  /// The height of the slider, not measured.
  static const double height = 34;

  /// The diameter of a tick mark (slider passport).
  static const double tickSize = SliderMotion.tickSize;

  /// The share of the range an arrow key or an accessibility step moves a
  /// continuous slider by, not measured; a stepped slider moves to the next
  /// stop on that side instead.
  static const double keyboardStep = 0.1;

  @override
  State<RawGlassSlider> createState() => _RawGlassSliderState();
}

class _RawGlassSliderState extends State<RawGlassSlider> {
  late final _SliderBody _body = _SliderBody(
    _deliver,
    value: _unit(widget.value),
    ticks: widget.ticks,
  );
  late final _SliderInput _input = _SliderInput(
    body: _body,
    start: _start,
    end: _endUnlessGliding,
  );
  late final List<Interaction> _interactions = [_input];
  WidgetStatesController? _ownStates;
  Widget? _visual;
  Object? _visualKey;
  Set<WidgetState>? _visualStates;
  bool _reconcilePending = false;
  double? _reported;
  bool _changing = false;

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
  void didUpdateWidget(RawGlassSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = oldWidget.statesController ?? _ownStates;
    if (!identical(states, _states)) {
      states?.removeListener(_statesChanged);
      _states.addListener(_statesChanged);
    }
    _writeStates();
    _body.ticks = widget.ticks;
    if (oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _reported = null;
    }
    if (!_inSync && !_body.leading) {
      _body.setValue(_unit(widget.value), animated: widget.animated);
      _reported = widget.value;
    }
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownStates?.dispose();
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    super.dispose();
  }

  // The region writes disabled too; writing it first makes its write a
  // no-op, so it never asks this ancestor to rebuild while it builds.
  void _writeStates() =>
      _states.update(WidgetState.disabled, widget.onChanged == null);

  void _statesChanged() => setState(() {});

  double _unit(double value) =>
      ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  double _out(double unit) => widget.min + unit * (widget.max - widget.min);

  bool get _inSync =>
      widget.value == _reported || _unit(widget.value) == _body.reportedValue;

  // Callbacks may rebuild ancestors: a cancel from the region's own update
  // or dispose arrives while the framework builds or finalizes the tree,
  // so they wait for the end of the frame there.
  void _deliver(SliderEvent event) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deliverNow(event);
      });
      return;
    }
    _deliverNow(event);
  }

  void _deliverNow(SliderEvent event) {
    switch (event) {
      case SliderChanged(:final value):
        final out = _reported = _out(value);
        widget.onChanged?.call(out);
        _reconcileLater();
      case SliderChangeEnded(:final value):
        _end(_out(value));
        _reconcileLater();
      case SliderFelt(:final detent):
        (detent
                ? HapticFeedback.selectionClick()
                : HapticFeedback.lightImpact())
            .ignore();
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
    if (_body.leading) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _end(widget.value);
      });
    } else {
      _end(widget.value);
    }
    _reconcileLater();
  }

  // One pending check, re-armed while a drag or glide leads the value.
  void _reconcileLater() {
    if (_reconcilePending) return;
    _reconcilePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _reconcilePending = false;
      if (!mounted || _inSync) return;
      if (_body.leading) {
        _reconcileLater();
        return;
      }
      _body.setValue(_unit(widget.value));
      _reported = widget.value;
    });
  }

  double _stepFrom(double from, int delta) {
    final ticks = widget.ticks;
    if (ticks < 2) {
      return (from + delta * RawGlassSlider.keyboardStep).clamp(0.0, 1.0);
    }
    final steps = ticks - 1;
    final at = from * steps;
    // A stop the parent rounded sits a hair off it and still counts as it.
    final base = delta > 0 ? (at + 1e-6).floor() : (at - 1e-6).ceil();
    return (base + delta).clamp(0, steps) / steps;
  }

  void _nudge(int delta) {
    if (widget.onChanged == null) return;
    final from = _unit(widget.value);
    final unit = _stepFrom(from, delta);
    if (unit == from) return;
    final value = _out(unit);
    _start();
    widget.onChanged?.call(value);
    _end(value);
  }

  Widget _visualFor(BuildContext context, double width) {
    final key = (widget.builder, width, widget.ticks, _body.mirrored);
    final visual = _visual;
    if (visual != null &&
        key == _visualKey &&
        setEquals(_visualStates, _states.value)) {
      return visual;
    }
    _visualKey = key;
    final states = _visualStates = {..._states.value};
    return _visual = widget.builder(
      context,
      GlassSliderDetails(
        track: _body.track,
        fill: _body.fill,
        thumb: _body.thumb,
        ticks: _body.tickCenters,
        states: states,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _body.reducedMotion = GlassTraits.of(context).reduceMotion;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _body.mirrored = rtl;
    _input.mirrored = rtl;
    final enabled = widget.onChanged != null;
    final value = _unit(widget.value);
    String percent(double v) => '${(v * 100).round()}%';
    final back = rtl ? 1 : -1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(back),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _nudge(-back),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(1),
      },
      child: Semantics(
        slider: true,
        value: percent(value),
        increasedValue: percent(_stepFrom(value, 1)),
        decreasedValue: percent(_stepFrom(value, -1)),
        onIncrease: enabled && value < 1 ? () => _nudge(1) : null,
        onDecrease: enabled && value > 0 ? () => _nudge(-1) : null,
        child: InputRegion(
          interactions: _interactions,
          enabled: enabled,
          statesController: _states,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          semanticLabel: widget.semanticLabel,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : 200.0;
              _body.width = width;
              return SizedBox(
                width: width,
                height: RawGlassSlider.height,
                child: _visualFor(context, width),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The motion of a slider, stepped on the motion clock and published as
/// the frames of its track, fill and thumb.
final class _SliderBody implements MotionDriver {
  _SliderBody(this._deliver, {required double value, required int ticks})
    : _motion = SliderMotion(
        width: 0,
        value: value,
        ticks: ticks,
        frameRate: MotionClock.instance.frameRate,
      ) {
    _publish();
  }

  final SliderMotion _motion;
  final void Function(SliderEvent event) _deliver;
  final track = ValueNotifier(const GlassFrame());
  final fill = ValueNotifier(const GlassFrame());
  final thumb = ValueNotifier(const GlassFrame());

  bool get leading => _motion.isDragging || _motion.isGliding;

  double get reportedValue => _motion.reportedValue;

  List<Offset> get tickCenters => [
    for (final x in _motion.tickCenters)
      Offset(
        _mirrored ? _motion.width - x : x,
        RawGlassSlider.height / 2 + SliderMotion.tickOffset,
      ),
  ];

  bool get reducedMotion => _motion.lens.reducedMotion;
  set reducedMotion(bool value) => _motion.lens.reducedMotion = value;

  bool _mirrored = false;
  bool get mirrored => _mirrored;
  set mirrored(bool value) {
    if (value == _mirrored) return;
    _mirrored = value;
    _publish();
  }

  double get width => _motion.width;
  set width(double value) {
    if (value == _motion.width) return;
    _motion.width = value;
    _publish();
  }

  int get ticks => _motion.ticks;
  set ticks(int value) {
    if (value == _motion.ticks) return;
    _motion.ticks = value;
    _publish();
    _wake();
  }

  bool hitsThumb(double x) => _motion.hitsThumb(x);

  bool get isDragging => _motion.isDragging;

  @override
  bool get isActive => !_motion.isSettled;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _motion.advance(time);
    if (_motion.isSettled) _motion.settle();
    _publish();
    _drain();
  }

  Rect _shown(Rect rect) => _mirrored
      ? Rect.fromLTRB(
          _motion.width - rect.right,
          rect.top,
          _motion.width - rect.left,
          rect.bottom,
        )
      : rect;

  void _publish() {
    final motion = _motion;
    final t = motion.time;
    const y = RawGlassSlider.height / 2;
    final ends = motion.trackEnds;
    final height = motion.currentTrackHeight.clamp(0.0, double.infinity);
    final fillEnd = motion.fillEnd.clamp(ends.left, double.infinity);
    track.value = GlassFrame(
      rect: _shown(
        Rect.fromLTRB(ends.left, y - height / 2, ends.right, y + height / 2),
      ),
    );
    fill.value = GlassFrame(
      rect: _shown(
        Rect.fromLTRB(ends.left, y - height / 2, fillEnd, y + height / 2),
      ),
    );
    final lens = motion.lens;
    final size = lens.size(t);
    thumb.value = GlassFrame(
      rect: _shown(
        Rect.fromCenter(
          center: Offset(motion.thumbCenter + lens.shift(t), y),
          width: size.width * lens.scaleX(t),
          height: size.height * lens.scaleY(t),
        ),
      ),
      lift: lens.progress(t).clamp(0.0, 1.0),
    );
  }

  void _drain() {
    for (final event in _motion.drainEvents()) {
      _deliver(event);
    }
  }

  void _wake() => MotionClock.instance.wake(this);

  // A jump settles the motion at once, and the clock steps only active
  // drivers, so it publishes here.
  void setValue(double value, {bool animated = false}) {
    _motion.setValue(MotionClock.instance.now, value, animated: animated);
    _publish();
    _drain();
    _wake();
  }

  void down(double t, double x) {
    _motion.pointerDown(t, x);
    _drain();
    _wake();
  }

  void move(double t, double x) {
    _motion.pointerMove(t, x);
    _drain();
    _wake();
  }

  void up(double t, double x, double velocity) {
    _motion.pointerUp(t, x, velocity: velocity);
    _drain();
    _wake();
  }

  void cancel(double t, {required bool revert}) {
    _motion.pointerCancel(t, revert: revert);
    _drain();
    _wake();
  }

  void dispose() {
    track.dispose();
    fill.dispose();
    thumb.dispose();
  }
}

/// A slider's touch: it takes a touch only on the thumb and holds it
/// against a scroll.
final class _SliderInput extends Interaction {
  _SliderInput({required this.body, required this.start, required this.end})
    : super(role: InteractionRole.control);

  final _SliderBody body;
  final VoidCallback start;
  final VoidCallback end;
  bool mirrored = false;
  int? _pointer;

  @override
  bool get pressed => _pointer != null;

  @override
  bool get dragged => _pointer != null && body.isDragging;

  double _x(Offset position) =>
      mirrored ? body.width - position.dx : position.dx;

  @override
  bool accepts(PointerDownInput down) =>
      _pointer == null &&
      super.accepts(down) &&
      body.hitsThumb(_x(down.position));

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && !accepts(input):
        // A delivery held for a scroll may come after the thumb moved away.
        return const InteractionUpdate(fails: true);
      case PointerDownInput() when accepts(input):
        _pointer = input.pointer;
        start();
        body.down(input.time, _x(input.position));
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        body.move(input.time, _x(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        final velocity = input.velocity.dx;
        body.up(
          input.time,
          _x(input.position),
          mirrored ? -velocity : velocity,
        );
        end();
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        body.cancel(
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

/// The look of a [GlassSlider], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the slider's states. A
/// slider looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSliderStyle {
  /// Creates a style.
  const GlassSliderStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.tickColor,
    this.builder,
  });

  /// The fill of the resting thumb (UIKit `thumbTintColor`); white in both
  /// appearances by default (slider passport).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track below the value (UIKit `minimumTrackTintColor`); the theme's
  /// primary color by default, else [GlassColors.systemBlue].
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track above the value (UIKit `maximumTrackTintColor`);
  /// [GlassSlider.inactiveTrack] by default.
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// The tick marks of a stepped slider; [GlassColors.opaqueSeparator] by
  /// default, the dot color the slider passport measured.
  final WidgetStateProperty<Color?>? tickColor;

  /// Builds the slider's look in place of the default one; the slider then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSliderBuilder? builder;

  /// This style over [other], state by state.
  GlassSliderStyle merge(GlassSliderStyle? other) {
    if (other == null) return this;
    return GlassSliderStyle(
      thumbColor: fallThrough(thumbColor, other.thumbColor),
      activeTrackColor: fallThrough(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: fallThrough(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      tickColor: fallThrough(tickColor, other.tickColor),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassSliderStyle? lerp(
    GlassSliderStyle? a,
    GlassSliderStyle? b,
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
    return GlassSliderStyle(
      thumbColor: color(a.thumbColor, b.thumbColor),
      activeTrackColor: color(a.activeTrackColor, b.activeTrackColor),
      inactiveTrackColor: color(a.inactiveTrackColor, b.inactiveTrackColor),
      tickColor: color(a.tickColor, b.tickColor),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSliderStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.tickColor == tickColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    thumbColor,
    activeTrackColor,
    inactiveTrackColor,
    tickColor,
    builder,
  );
}

/// An iOS 27 slider.
///
/// UIKit: `UISlider`. SwiftUI: `Slider`. Flutter: `CupertinoSlider`.
///
/// Its track and fill are plain fills and its thumb a platter that turns
/// into glass under the finger, drawn by the ambient renderer; its motion
/// is [RawGlassSlider]'s. A disabled slider draws at half opacity, as
/// UIKit does (iPhone 16 Pro, light and dark).
class GlassSlider extends StatefulWidget {
  /// Creates a slider showing [value] between [min] and [max].
  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.ticks = 0,
    this.animated = false,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// See [RawGlassSlider.value].
  final double value;

  /// See [RawGlassSlider.onChanged].
  final ValueChanged<double>? onChanged;

  /// See [RawGlassSlider.onChangeStart].
  final ValueChanged<double>? onChangeStart;

  /// See [RawGlassSlider.onChangeEnd].
  final ValueChanged<double>? onChangeEnd;

  /// See [RawGlassSlider.min].
  final double min;

  /// See [RawGlassSlider.max].
  final double max;

  /// See [RawGlassSlider.ticks].
  final int ticks;

  /// See [RawGlassSlider.animated].
  final bool animated;

  /// The look, over the theme's and the slider's defaults.
  final GlassSliderStyle? style;

  /// Where the slider writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The slider's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the slider takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the slider.
  final String? semanticLabel;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassSliderStyle styleFrom({
    Color? thumbColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? tickColor,
  }) => GlassSliderStyle(
    thumbColor: allStates(thumbColor),
    activeTrackColor: allStates(activeTrackColor),
    inactiveTrackColor: allStates(inactiveTrackColor),
    tickColor: allStates(tickColor),
  );

  /// UISlider's track above the value: black or white at 10 percent (slider
  /// passport).
  static const inactiveTrack = GlassDynamicColor.withBrightness(
    color: Color(0x1A000000),
    darkColor: Color(0x1AFFFFFF),
  );

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  GlassSliderStyle? _look;
  late GlassSliderBuilder _builder;

  // One builder per look: the core keeps the look it built until the
  // builder changes, so a style or theme change reaches it through a new
  // builder; brightness and contrast reach it through [_SliderLook].
  GlassSliderBuilder _builderFor(GlassSliderStyle look) {
    if (look == _look) return _builder;
    _look = look;
    return _builder =
        look.builder ??
        (context, details) => _SliderLook(details: details, look: look);
  }

  @override
  Widget build(BuildContext context) {
    final look = (widget.style ?? const GlassSliderStyle()).merge(
      GlassTheme.of(context).sliderStyle,
    );
    return RawGlassSlider(
      value: widget.value,
      onChanged: widget.onChanged,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
      min: widget.min,
      max: widget.max,
      ticks: widget.ticks,
      animated: widget.animated,
      statesController: widget.statesController,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      semanticLabel: widget.semanticLabel,
      builder: _builderFor(look),
    );
  }
}

class _SliderLook extends StatelessWidget {
  const _SliderLook({required this.details, required this.look});

  final GlassSliderDetails details;
  final GlassSliderStyle look;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    final active = resolve(
      look.activeTrackColor,
      GlassTheme.of(context).primaryColor ?? GlassColors.systemBlue,
    );
    Widget surface(
      GlassRole role,
      ValueListenable<GlassFrame> frame,
      Color tint,
    ) => Positioned.fill(
      child: GlassSurface.live(
        role: role,
        glass: Glass.regular(tint: tint),
        frame: frame,
        child: const SizedBox.expand(),
      ),
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? 0.5 : 1,
      child: Stack(
        children: [
          surface(
            GlassRole.track,
            details.track,
            resolve(look.inactiveTrackColor, GlassSlider.inactiveTrack),
          ),
          surface(GlassRole.track, details.fill, active),
          if (details.ticks.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _TickPainter(
                  details.ticks,
                  resolve(look.tickColor, GlassColors.opaqueSeparator),
                ),
              ),
            ),
          surface(
            GlassRole.thumb,
            details.thumb,
            resolve(look.thumbColor, const Color(0xFFFFFFFF)),
          ),
        ],
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.ticks, this.color);

  final List<Offset> ticks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    for (final center in ticks) {
      canvas.drawCircle(center, RawGlassSlider.tickSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      !listEquals(oldDelegate.ticks, ticks) || oldDelegate.color != color;
}
