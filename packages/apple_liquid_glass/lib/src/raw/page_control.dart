import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// When a page control shows the platter behind its dots.
///
/// UIKit: `UIPageControl.BackgroundStyle`.
enum GlassPageControlBackground {
  /// Only while the user interacts with the control.
  automatic,

  /// Always.
  prominent,

  /// Never; the control drops the platter's padding and height, so one
  /// page is a 9.67 point square.
  minimal,
}

/// Builds a page control from [details]; it runs again when the control's
/// states or progress change, never while it moves.
typedef GlassPageControlBuilder = Widget Function(
  BuildContext context,
  GlassPageControlDetails details,
);

/// What a [GlassPageControlBuilder] builds a page control from.
@immutable
final class GlassPageControlDetails {
  /// Describes a page control.
  const GlassPageControlDetails({
    required this.pose,
    required this.progress,
    required this.states,
    this.statesListenable,
  });

  /// Where the indicators sit and how they show, as the control moves.
  final MotionSelection<GlassPageControlPose> pose;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots. Under a [GlassPageControlTimer] it is where the timer stood when
  /// the look was built; the pose's [GlassPageControlPose.progress] moves
  /// with the timer.
  final double? progress;

  /// The states the control is in: [WidgetState.disabled] while it ignores
  /// input, and what its input region writes (pressed, hovered, focused).
  final Set<WidgetState> states;

  /// The control's states as they change, or null for a look that shows
  /// neither focus nor hover: a builder hands it to the `GlassSurface` of
  /// the platter, whose renderer then draws the focus ring and the hover
  /// response.
  final ValueListenable<Set<WidgetState>>? statesListenable;
}

/// A page control's indicators at one moment, in the control's box.
@immutable
final class GlassPageControlPose {
  /// Describes the indicators.
  const GlassPageControlPose({
    required this.indicators,
    required this.fills,
    required this.platter,
    required this.page,
    this.direction = AxisDirection.right,
    this.progress,
  });

  factory GlassPageControlPose._of(
    PageControlMotion motion, {
    required GlassPageControlBackground background,
    required AxisDirection direction,
    required double? progress,
  }) {
    final rects = motion.indicatorRects(
      rtl: axisDirectionIsReversed(direction),
    );
    final vertical = axisDirectionToAxis(direction) == Axis.vertical;
    return GlassPageControlPose(
      direction: direction,
      progress: progress,
      indicators: vertical
          ? [
              for (final r in rects)
                Rect.fromLTWH(r.top, r.left, r.height, r.width),
            ]
          : rects,
      fills: [for (var i = 0; i < motion.count; i++) motion.fillOpacity(i)],
      platter: switch (background) {
        GlassPageControlBackground.prominent => 1,
        GlassPageControlBackground.minimal => 0,
        GlassPageControlBackground.automatic => motion.platter,
      },
      page: motion.page,
    );
  }

  /// Each page's indicator box, a dot across and as long as the indicator
  /// along [direction], in which a look draws a capsule.
  final List<Rect> indicators;

  /// How far each indicator's fill shows, 0 to 1: 1 on the current page,
  /// fading on the page just left, 0 elsewhere. A look draws the fill only
  /// while the control shows a progress.
  final List<double> fills;

  /// How far the platter behind the indicators shows, 0 to 1.
  final double platter;

  /// The page the indicators show as current.
  final int page;

  /// The way the pages run from the first: [AxisDirection.right] across
  /// the control, [AxisDirection.left] in right-to-left, and
  /// [AxisDirection.down] or [AxisDirection.up] on a vertical control. A
  /// progress fills an indicator this way.
  final AxisDirection direction;

  /// How far a [GlassPageControlTimer] has run through the current page,
  /// 0 to 1, as it moves every frame; null without a timer, where the
  /// look's progress is [GlassPageControlDetails.progress].
  final double? progress;

  @override
  bool operator ==(Object other) =>
      other is GlassPageControlPose &&
      other.platter == platter &&
      other.page == page &&
      other.direction == direction &&
      other.progress == progress &&
      listEquals(other.indicators, indicators) &&
      listEquals(other.fills, fills);

  @override
  int get hashCode => Object.hash(
    platter,
    page,
    direction,
    progress,
    Object.hashAll(indicators),
    Object.hashAll(fills),
  );
}

/// Turns a page control's pages on a timer, a stories-style progress.
///
/// UIKit: `UIPageControlTimerProgress`. SwiftUI: none. Flutter: none.
///
/// Pass it to a [RawGlassPageControl], or a `GlassPageControl`, as `timer`.
/// While [isRunning] the current indicator fills over [duration], and at
/// its end the control calls `onChanged` with the next page, whose
/// indicator starts empty. A page set otherwise, by the app or a tap,
/// starts empty too. Past the last page the timer goes on from the first
/// with [resetsToInitialPageAfterEnd], and otherwise stops there, full.
/// [shouldAdvanceToPage] may refuse a page: the timer then stops where it
/// is, and [resume] asks again.
///
/// A timer starts paused, as UIKit's does: [resume] runs it. It tells its
/// listeners when it starts or stops running, not as it fills; [progress]
/// reads how far it is. A timer serves one control at a time.
///
/// Fidelity. Timing, pausing, the refusal, the loop and a [duration]
/// changed while it runs follow UIKit 27.2 (page control API passport):
/// the running page keeps the duration it started with. UIKit's per-page
/// `setDuration(_:forPage:)` had no effect in 27.2 and is left out.
class GlassPageControlTimer extends ChangeNotifier {
  /// Creates a paused timer that gives each page [duration].
  GlassPageControlTimer({
    required this.duration,
    this.resetsToInitialPageAfterEnd = false,
    this.shouldAdvanceToPage,
  });

  /// How long a page lasts; a page that starts takes it, the one running
  /// keeps its own.
  Duration duration;

  /// Whether the timer goes on from the first page after the last.
  bool resetsToInitialPageAfterEnd;

  /// Asked with the next page as the current one ends; false stops the
  /// timer on the current page, full.
  bool Function(int page)? shouldAdvanceToPage;

  _RawGlassPageControlState? _control;
  bool _running = false;

  /// Whether the timer runs.
  bool get isRunning => _running;

  /// How far the current page has run, 0 to 1; 0 with no control.
  double get progress => _control?._motion.timerProgress ?? 0;

  double get _seconds =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;

  /// Runs the timer on from where it stands.
  void resume() {
    if (_running) return;
    _running = true;
    _control?._resumeTimer();
    notifyListeners();
  }

  /// Stops the timer, keeping its progress.
  void pause() {
    if (!_running) return;
    _running = false;
    _control?._pauseTimer();
    notifyListeners();
  }

  void _stopped() => notifyListeners();

  void _attach(_RawGlassPageControlState control) {
    assert(
      _control == null || identical(_control, control),
      'a GlassPageControlTimer serves one page control at a time',
    );
    _control = control;
  }

  void _detach(_RawGlassPageControlState control) {
    if (identical(_control, control)) _control = null;
  }
}

/// A page control with the measured motion of iOS 27's `UIPageControl` and
/// no look of its own: [builder] decides how it looks.
///
/// UIKit: `UIPageControl`. SwiftUI: the page style of a `TabView`.
/// Flutter: none.
///
/// It has an indicator for each of [count] pages. A tap on the trailing
/// half moves to the next page and one on the leading half to the
/// previous page, on the lift, as UIKit's does; a finger that moves more
/// than 10 points scrubs to the nearest indicator and plays a selection
/// haptic each time it changes the page (read from UIKit, notes private);
/// a `MotionHapticScope` turns that off. A finger takes it within a 44 point
/// tall area around its box, 25.67 points tall with the platter's padding
/// around the dots and 9.67 under [GlassPageControlBackground.minimal],
/// where its parent leaves that room.
/// With [progress] the current indicator widens into a capsule
/// (`UIPageControlProgress`), and a page change grows and shrinks the
/// capsules on the measured springs. The platter shows per
/// [backgroundStyle], fading in after a touch rests 0.193 s. The value
/// commands of the arrow keys (mirrored in right-to-left), Home and End,
/// and the accessibility increase and decrease step through the pages or
/// go to the first and last; it has no larger step, so Page Up and Page
/// Down do nothing, and neither do Space and Enter, as on Flutter's
/// `Slider`. In a right-to-left context the pages run from the right;
/// [direction] runs them another way, down or up a vertical control as
/// UIKit's `direction` does, where the arrow keys still step as on a
/// horizontal control (up, and right or left with the reading direction,
/// for the next page).
class RawGlassPageControl extends StatefulWidget {
  /// Creates a page control of [count] pages showing [page].
  const RawGlassPageControl({
    required this.count,
    required this.page,
    required this.onChanged,
    required this.builder,
    this.progress,
    this.timer,
    this.backgroundStyle = GlassPageControlBackground.automatic,
    this.direction,
    this.allowsContinuousInteraction = true,
    this.semanticLabel,
    this.semanticValueFormatter,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control. A
  /// control whose [page] does not follow returns to it.
  final ValueChanged<int>? onChanged;

  /// Builds the control's look.
  final GlassPageControlBuilder builder;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// indicators.
  final double? progress;

  /// Turns the pages on a timer and shows its progress, where [progress]
  /// is null.
  final GlassPageControlTimer? timer;

  /// When the platter shows.
  final GlassPageControlBackground backgroundStyle;

  /// The way the pages run from the first, or null for the reading
  /// direction: [AxisDirection.down] and [AxisDirection.up] stand the
  /// control on end, 25.67 points wide (page control passport), and
  /// [AxisDirection.right] and [AxisDirection.left] run it across whatever
  /// the reading direction.
  final AxisDirection? direction;

  /// Whether a finger that moves scrubs through the pages; without, a
  /// touch only taps, a page back or forward at its release.
  final bool allowsContinuousInteraction;

  /// What accessibility reads for the control.
  final String? semanticLabel;

  /// Formats the adjustable value from a one-based page and the page count;
  /// null reads [GlassLocalizations.pageValue]. An empty control has no
  /// value.
  final String Function(int page, int count)? semanticValueFormatter;

  /// Where the control publishes its states, or null for its own. The
  /// control is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  @override
  State<RawGlassPageControl> createState() => _RawGlassPageControlState();
}

class _RawGlassPageControlState extends State<RawGlassPageControl>
    with
        ControlStates<RawGlassPageControl>,
        ControlledValue<RawGlassPageControl> {
  late PageControlMotion _motion = _create();
  GlassPageControlTimer? _timer;
  AxisDirection _direction = AxisDirection.right;
  late MotionSelection<GlassPageControlPose> _pose = _poseOf();
  late MotionSelection<bool> _touched = _touchedOf();
  late final _PageControlInput _input = _PageControlInput(this);
  late final List<Interaction> _interactions = [_input];

  int get _count => math.max(0, widget.count);

  int get _page => _count == 0 ? 0 : widget.page.clamp(0, _count - 1);

  PageControlMotion _create() => PageControlMotion(
    count: _count,
    page: _page,
    showsProgress: _showsProgress(widget),
    platterless: _platterless,
    onEvent: _deliver,
    clock: MotionClockScope.of(context),
  )..onTimerEnd = _timerEnded;

  static bool _showsProgress(RawGlassPageControl widget) =>
      widget.progress != null || widget.timer != null;

  @override
  void dispose() {
    _timer?._detach(this);
    _motion.pauseTimer(_motion.clock.now);
    super.dispose();
  }

  // Takes the widget's timer, starting the current page for it.
  void _takeTimer() {
    final timer = widget.timer;
    final now = _motion.clock.now;
    if (!identical(timer, _timer)) {
      _timer?._detach(this);
      _timer = timer?.._attach(this);
    }
    _motion.pauseTimer(now);
    if (timer == null) return;
    _motion.startTimerPage(now, timer._seconds);
    if (timer.isRunning) _motion.resumeTimer(now);
  }

  void _resumeTimer() => _motion.resumeTimer(_motion.clock.now);

  void _pauseTimer() => _motion.pauseTimer(_motion.clock.now);

  void _timerEnded(double t) {
    final timer = _timer;
    if (timer == null) return;
    var next = _page + 1;
    if (next >= _count) {
      if (!timer.resetsToInitialPageAfterEnd) return _stopTimer(timer, t);
      next = 0;
    }
    if (timer.shouldAdvanceToPage?.call(next) == false) {
      return _stopTimer(timer, t);
    }
    _motion.startTimerPage(t, timer._seconds);
    notifyChanged(() {
      if (next != _page) widget.onChanged?.call(next);
    });
  }

  void _stopTimer(GlassPageControlTimer timer, double t) {
    _motion.pauseTimer(t);
    timer._running = false;
    runOutsideBuild(timer._stopped);
  }

  MotionSelection<bool> _touchedOf() =>
      _motion.select((motion) => motion.isTouched);

  bool get _platterless =>
      widget.backgroundStyle == GlassPageControlBackground.minimal;

  MotionSelection<GlassPageControlPose> _poseOf() {
    final background = widget.backgroundStyle;
    final direction = _direction;
    final timed = widget.timer != null;
    return _motion.select(
      (m) => GlassPageControlPose._of(
        m,
        background: background,
        direction: direction,
        progress: timed ? m.timerProgress : null,
      ),
    );
  }

  bool get _vertical => axisDirectionToAxis(_direction) == Axis.vertical;

  // The direction the pages run in this context.
  AxisDirection _directionIn(BuildContext context) =>
      widget.direction ??
      (Directionality.maybeOf(context) == TextDirection.rtl
          ? AxisDirection.left
          : AxisDirection.right);

  @override
  WidgetStatesController? get statesController => widget.statesController;

  @override
  MotionClock get valueClock => _motion.clock;

  @override
  ValueListenable<bool> get userDriving => _touched;

  @override
  void syncFromWidget() {
    final page = _page;
    if (page == _motion.page) return;
    _motion.setPage(_motion.clock.now, page);
    if (_timer case final timer?) {
      _motion.startTimerPage(_motion.clock.now, timer._seconds);
    }
  }

  bool get enabled => widget.onChanged != null && _count > 0;

  @override
  void didUpdateWidget(RawGlassPageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count ||
        _showsProgress(widget) != _showsProgress(oldWidget)) {
      _motion.pauseTimer(_motion.clock.now);
      _motion = _create();
      _pose = _poseOf();
      _touched = _touchedOf();
      _takeTimer();
      _follow(_directionIn(context));
      return;
    }
    if (!identical(widget.timer, oldWidget.timer)) _takeTimer();
    if ((widget.timer == null) != (oldWidget.timer == null)) {
      _pose = _poseOf();
    }
    if (widget.backgroundStyle != oldWidget.backgroundStyle) {
      _motion.platterless = _platterless;
      _pose = _poseOf();
    }
    _follow(_directionIn(context));
  }

  void _follow(AxisDirection direction) {
    if (direction == _direction) return;
    _direction = direction;
    _pose = _poseOf();
  }

  void _deliver(PageControlEvent event) {
    switch (event) {
      case PageControlPicked(:final page, :final scrubbed):
        if (scrubbed) _input.feel(page);
        notifyChanged(() {
          if (page != _page) widget.onChanged?.call(page);
        });
    }
  }

  static MotionHaptic? _feedback(InteractionEvent event) =>
      event is ScrubChangeEvent ? MotionHaptic.selection : null;

  void _command(ValueCommand command) {
    if (!enabled) return;
    final next = switch (command) {
      ValueCommand.increase => _page + 1,
      ValueCommand.decrease => _page - 1,
      ValueCommand.toMinimum => 0,
      ValueCommand.toMaximum => _count - 1,
      ValueCommand.increaseLarge || ValueCommand.decreaseLarge => _page,
    }.clamp(0, _count - 1);
    if (next != _page) widget.onChanged?.call(next);
  }

  Size get _size => _vertical ? _motion.size.flipped : _motion.size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow(_directionIn(context));
    if (!_tookTimer) {
      _tookTimer = true;
      _takeTimer();
    }
  }

  bool _tookTimer = false;

  @override
  Widget buildControl(BuildContext context) {
    final count = _count;
    final page = _page;
    final strings = GlassLocalizations.of(context);
    String value(int page) =>
        widget.semanticValueFormatter?.call(page, count) ??
        strings.pageValue(page, count);
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _interactions,
        enabled: enabled,
        statesController: widgetStates,
        feedback: _feedback,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semantics: SemanticsProperties(
          label: widget.semanticLabel,
          value: count == 0 ? null : value(page + 1),
          increasedValue: count == 0 ? null : value(math.min(page + 2, count)),
          decreasedValue: count == 0 ? null : value(math.max(page, 1)),
        ),
        reach: glassTargetReach,
        child: SizedBox.fromSize(
          size: _size,
          child: withStates(
            (context, states) => widget.builder(
              context,
              GlassPageControlDetails(
                pose: _pose,
                progress:
                    widget.progress ??
                    (_timer == null ? null : _motion.timerProgress),
                states: states,
                statesListenable: widgetStates,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page control's touch: taps and scrubs anywhere on it, held against a
/// scroll. A scrub onto another page reaches the region as a
/// [ScrubChangeEvent], for its haptic.
final class _PageControlInput extends Interaction {
  _PageControlInput(this.state) : super(role: InteractionRole.control);

  final _RawGlassPageControlState state;
  bool _touching = false;
  final List<InteractionEvent> _felt = [];

  @override
  bool get pressed => _touching;

  @override
  Set<InputKind> get takes => const {InputKind.pointer, InputKind.adjustment};

  void feel(int page) => _felt.add(
    ScrubChangeEvent(time: state._motion.now),
  );

  double _x(Offset position) => state._motion.contentX(
    state._vertical ? position.dy : position.dx,
    rtl: axisDirectionIsReversed(state._direction),
  );

  @override
  InteractionUpdate handle(InteractionInput input) {
    final update = _handle(input);
    if (_felt.isEmpty) return update;
    final events = [...update.events, ..._felt];
    _felt.clear();
    return InteractionUpdate(
      verdict: update.verdict,
      fails: update.fails,
      events: events,
    );
  }

  InteractionUpdate _handle(InteractionInput input) {
    final motion = state._motion;
    switch (input) {
      case AdjustInput(:final command):
        state._command(command);
      case PointerDownInput() when accepts(input):
        _touching = true;
        motion.pointerDown(input.time, _x(input.position));
        return const InteractionUpdate(verdict: .claimed);
      case PointerMoveInput() when state.widget.allowsContinuousInteraction:
        motion.pointerMove(input.time, _x(input.position));
      case PointerUpInput():
        _touching = false;
        motion.pointerUp(
          input.time,
          _x(input.position),
          width: state._motion.size.width,
        );
        return const InteractionUpdate(verdict: .recognized);
      case PointerCancelInput():
        _touching = false;
        motion.pointerCancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}
