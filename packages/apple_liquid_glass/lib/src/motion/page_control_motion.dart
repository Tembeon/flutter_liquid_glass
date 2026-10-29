import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// The measured geometry and motion of iOS 27's UIPageControl.
@internal
abstract final class PageControlTuning {
  /// The box of one page's indicator.
  static const double indicatorSize = 9.67;

  /// The diameter of a drawn dot.
  static const double dotSize = 7.67;

  /// The gap between two indicators.
  static const double spacing = 8;

  /// The width of the current indicator while it shows a progress.
  static const double progressIndicatorWidth = 27.33;

  /// The padding between the dots and the platter's ends.
  static const double padding = 14;

  /// The height of the control and its platter.
  static const double height = 25.67;

  /// The spring an indicator's width changes on when the current page of
  /// a control showing progress changes (fitted to the simulator's
  /// frames, 0.08 point rms).
  static const widthSpring = Spring.response(0.398, dampingRatio: 0.927);

  /// The spring the finished progress fades out on (0.002 rms).
  static const fadeSpring = Spring.response(0.381, dampingRatio: 0.963);

  /// Seconds a touch rests on the control before its platter shows (and
  /// the dots take the platter's colors) under
  /// `GlassPageControlBackground.automatic`: 0.19 - 0.2 s on an iPhone 16
  /// Pro at 120 Hz (the 60 Hz simulator read 0.2).
  static const double platterDelay = 0.193;

  /// The spring the platter fades in on (critically damped 0.100 s on the
  /// device, 0.001 rms; 0.106 / 0.973 on the simulator's coarser frames).
  static const platterInSpring = Spring.response(0.100);

  /// The spring the platter fades out on (0.001 rms).
  static const platterOutSpring = Spring.response(0.100);

  /// Seconds between the lift of the touch and the platter's fade out
  /// (0.03 - 0.035 s on the device; 0.02 on the simulator).
  static const double platterOutDelay = 0.032;

  /// How far a touch travels before it scrubs instead of tapping.
  static const double scrubSlop = 10;

  /// How far past the midpoint between two dots a scrubbing finger goes
  /// before the page changes, either way (1 - 2 points measured, a frame
  /// of latency included).
  static const double scrubHysteresis = 1.5;

  /// The distance between two dot centers.
  static const double pitch = indicatorSize + spacing;
}

/// The motion of an iOS 27 page control's indicators.
///
/// Without a progress every dot is [PageControlTuning.indicatorSize]
/// wide and a page change is instant, as UIKit's is. With a progress the
/// current indicator is a capsule
/// [PageControlTuning.progressIndicatorWidth] wide whose fill shows
/// the progress; when the
/// page changes, the old capsule shrinks to a dot and the new one grows on
/// [PageControlTuning.widthSpring] while the old fill fades out on
/// [PageControlTuning.fadeSpring]. Times are seconds.
@internal
class PageControlMotion {
  /// Creates a motion of [count] pages showing [page].
  PageControlMotion({
    required int count,
    required int page,
    this.showsProgress = false,
  }) : _page = count > 0 ? page.clamp(0, count - 1) : 0,
       _widths = [
         for (var i = 0; i < count; i++)
           MotionValue<double>(
             _restWidth(i == page.clamp(0, count - 1), showsProgress),
             spring: PageControlTuning.widthSpring,
           ),
       ];

  static double _restWidth(bool current, bool progress) => current && progress
      ? PageControlTuning.progressIndicatorWidth
      : PageControlTuning.indicatorSize;

  /// Whether the current indicator shows a progress.
  bool showsProgress;

  int _page;
  final List<MotionValue<double>> _widths;
  final _platter = MotionValue<double>(
    0,
    spring: PageControlTuning.platterInSpring,
  );
  final MotionTimeline _timeline = MotionTimeline(now: 0);
  double? _downX;
  bool _scrubbing = false;
  bool _stepped = false;

  /// The opacity of the platter under a touch, 0 to 1.
  double get platter => _platter.valueAt(_now).clamp(0.0, 1.0);

  /// Whether a touch is scrubbing through the pages.
  bool get isScrubbing => _scrubbing;

  MotionValue<double>? _fade;
  int _fading = -1;
  double _now = 0;
  final List<PageControlEvent> _events = [];

  /// The events raised since the last call, oldest first.
  List<PageControlEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final drained = List<PageControlEvent>.of(_events);
    _events.clear();
    return drained;
  }

  /// The number of pages.
  int get count => _widths.length;

  /// The current page.
  int get page => _page;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether nothing moves. A resting finger does not count: the
  /// control's moves and lift arrive as stamped pointer events, which wake
  /// the clock.
  bool get isSettled => _timeline.isEmpty && _still;

  /// Puts what is still moving onto its targets.
  void settle() {
    _platter.settle(_now);
    for (final w in _widths) {
      w.settle(_now);
    }
    _fade?.settle(_now);
  }

  /// Whether what remains is invisible ([GlassRest], NEAR): the platter
  /// and the old fill fade by less than [GlassRest.opacity], the widths
  /// swing less than [GlassRest.length].
  bool get _still =>
      _platter.isWithin(_now, GlassRest.opacity) &&
      _widths.every(
        (MotionValue<double> w) => w.isWithin(_now, GlassRest.length),
      ) &&
      (_fade?.isWithin(_now, GlassRest.opacity) ?? true);

  /// The time before which nothing moves, or null while something does:
  /// a touch waiting out the platter's delay draws nothing new.
  double? get wakeTime => _still ? _timeline.nextDue : null;

  /// Advances the motion to [t]; an earlier [t] changes nothing.
  void advance(double t) {
    if (t < _now) return;
    _timeline.runDue(t);
    _now = t;
  }

  /// A finger touched the control at [x], measured from the start of the
  /// dots.
  void pointerDown(double t, double x) {
    advance(t);
    if (count == 0) return;
    _downX = x;
    _scrubbing = false;
    _stepped = false;
    _timeline.clear();
    _timeline.at(
      t + PageControlTuning.platterDelay,
      (double s) => _platter.retarget(
        s,
        1,
        spring: PageControlTuning.platterInSpring,
      ),
    );
  }

  /// The finger moved to [x].
  void pointerMove(double t, double x) {
    advance(t);
    final from = _downX;
    if (from == null || count == 0) return;
    if (!_scrubbing && (x - from).abs() <= PageControlTuning.scrubSlop) {
      return;
    }
    _scrubbing = true;
    const pitch = PageControlTuning.pitch;
    const h = PageControlTuning.scrubHysteresis;
    final ahead = x - center(_page);
    var next = _page;
    if (ahead > pitch / 2 + h) {
      next = _page + ((ahead - pitch / 2 - h) / pitch).floor() + 1;
    } else if (ahead < -pitch / 2 - h) {
      next = _page - ((-ahead - pitch / 2 - h) / pitch).floor() - 1;
    }
    next = next.clamp(0, count - 1);
    if (next != _page) {
      _stepped = true;
      setPage(t, next);
      _events.add(PageControlPicked(next, scrubbed: true));
    }
  }

  /// The finger lifted at [x]; a tap on the trailing half of a control
  /// [width] wide (dots and padding) steps forward, on the leading half
  /// back, unless the touch scrubbed.
  void pointerUp(double t, double x, {required double width}) {
    advance(t);
    final from = _downX;
    _downX = null;
    _hidePlatter(t);
    if (count == 0 || from == null || _scrubbing || _stepped) {
      _scrubbing = false;
      return;
    }
    final mid = width / 2 - PageControlTuning.padding;
    final next = (_page + (x > mid ? 1 : -1)).clamp(0, count - 1);
    if (next != _page) {
      setPage(t, next);
      _events.add(PageControlPicked(next, scrubbed: false));
    }
  }

  /// The touch was cancelled.
  void pointerCancel(double t) {
    advance(t);
    _downX = null;
    _scrubbing = false;
    _hidePlatter(t);
  }

  void _hidePlatter(double t) {
    _timeline.clear();
    _timeline.at(
      t + PageControlTuning.platterOutDelay,
      (double s) => _platter.retarget(
        s,
        0,
        spring: PageControlTuning.platterOutSpring,
      ),
    );
  }

  /// Shows [page] from time [t]; animated only while showing progress.
  void setPage(double t, int page) {
    advance(t);
    if (count == 0) return;
    final next = page.clamp(0, count - 1);
    if (next == _page) return;
    final previous = _page;
    _page = next;
    if (!showsProgress) {
      for (var i = 0; i < count; i++) {
        _widths[i].snap(t, PageControlTuning.indicatorSize);
      }
      return;
    }
    _widths[previous].retarget(t, PageControlTuning.indicatorSize);
    _widths[next].retarget(t, PageControlTuning.progressIndicatorWidth);
    final fade = MotionValue<double>(
      1,
      spring: PageControlTuning.fadeSpring,
    );
    fade.retarget(t, 0);
    _fade = fade;
    _fading = previous;
  }

  /// The width of indicator [index].
  double width(int index) =>
      index >= 0 && index < count ? _widths[index].valueAt(_now) : 0;

  /// The opacity of the fill of indicator [index]: 1 on the current page,
  /// fading on the page just left, 0 elsewhere.
  double fillOpacity(int index) {
    if (index == _page) return 1;
    if (index == _fading) return (_fade?.valueAt(_now) ?? 0).clamp(0.0, 1.0);
    return 0;
  }

  /// The width of all indicators and the gaps between them.
  double get contentWidth {
    if (count == 0) return 0;
    var w = PageControlTuning.spacing * (count - 1);
    for (var i = 0; i < count; i++) {
      w += width(i);
    }
    return w;
  }

  /// The center of indicator [index] from the start of the dots.
  double center(int index) {
    if (index < 0 || index >= count) return 0;
    var x = 0.0;
    for (var i = 0; i < index; i++) {
      x += width(i) + PageControlTuning.spacing;
    }
    return x + width(index) / 2;
  }
}

/// What a [PageControlMotion] tells its host.
@internal
sealed class PageControlEvent {
  const PageControlEvent();
}

/// A touch picked [page]: a tap on either half, or a scrubbing finger
/// ([scrubbed]) that moved the control to another page.
@internal
final class PageControlPicked extends PageControlEvent {
  /// Creates the event.
  const PageControlPicked(this.page, {required this.scrubbed});

  /// The page picked.
  final int page;

  /// Whether a scrubbing finger picked it.
  final bool scrubbed;
}
