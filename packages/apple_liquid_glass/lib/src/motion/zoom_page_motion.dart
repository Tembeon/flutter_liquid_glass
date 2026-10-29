import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// The measured motion of UIKit's zoom transition into a pushed page
/// (`preferredTransition = .zoom` on a view controller pushed onto a
/// navigation controller).
///
/// Read from screen recordings of an iPhone 16 Pro on iOS 27.0.1 (four
/// pushes from a 160 x 100 card, a pop by the back button, drags down,
/// sideways and from the edge). The zooming container's center and width
/// ride one spring and its height another on the way in; on the way out
/// all of them ride UIKit's `zoomOut` spring. The page's content is drawn
/// at its own size scaled by the container's width, from the container's
/// top; the source's look crossfades into it; the page underneath dims
/// and the container casts a shadow on it.
@internal
@immutable
class ZoomPageTuning {
  /// Creates a tuning from explicit values.
  const ZoomPageTuning({
    this.openSpring = const Spring.response(0.317),
    this.openHeightSpring = const Spring.response(0.406, dampingRatio: 0.925),
    this.closeSpring = _zoomOutSpring,
    this.dismissSpring = const Spring.response(0.45, dampingRatio: 0.81),
    this.dismissHeightSpring = const Spring.response(0.33, dampingRatio: 0.98),
    this.returnSpring = const Spring.response(0.278, dampingRatio: 0.927),
    this.openFadeSpring = const Spring.response(0.156),
    this.openFadeDelay = 0.01,
    this.closeFadeSpring = const Spring.response(0.191),
    this.openDimmingSpring = _zoomInSpring,
    this.closeDimmingSpring = _zoomOutSpring,
    this.dimmingOpacity = 0.15,
    this.shadowOpacity = 0.36,
    this.shadowSigma = 30,
    this.shadowOffset = 4,
    this.dragSlop = 13.5,
    this.dragAngle = math.pi / 6,
    this.downWidthRate = 0.00078,
    this.downHeightRate = 0.00154,
    this.downGain = 0.61,
    this.sidewaysWidthRate = 0.00156,
    this.sidewaysHeightRate = 0.00168,
    this.sidewaysGain = 0.95,
    this.dismissDistance = 132.5,
    this.dismissVelocity = _dismissVelocity,
  });

  /// The spring the container's center and width travel on toward the
  /// page (fitted to four device pushes with [openHeightSpring]: 0.98
  /// points rms over the container's edges).
  final Spring openSpring;

  /// The spring the container's height grows on toward the page.
  final Spring openHeightSpring;

  /// The spring the whole container travels on back into the source when
  /// the page is popped without a finger: UIKit's
  /// `_UIZoomTransitionSpec.zoomOut` (a pop by the back button fits it to
  /// 0.54 points rms).
  final Spring closeSpring;

  /// The spring the container's center and width travel on back into the
  /// source after a drag dismissed the page (two device drags: center
  /// 0.47 / 0.82, width 0.43 / 0.80).
  final Spring dismissSpring;

  /// The spring the container's height shrinks on after a drag dismissed
  /// the page (two device drags: 0.33 / 0.98).
  final Spring dismissHeightSpring;

  /// The spring a page released short of a dismissal returns to full
  /// screen on (device fit 0.40 points rms).
  final Spring returnSpring;

  /// The spring the source's look crossfades into the page's content on
  /// (device fit 0.156 s, critically damped, after [openFadeDelay]).
  final Spring openFadeSpring;

  /// Seconds the crossfade waits after the container starts to grow.
  final double openFadeDelay;

  /// The spring the page's content crossfades back into the source's look
  /// on (device fit 0.191 s, critically damped).
  final Spring closeFadeSpring;

  /// The spring the dimming rises on: UIKit's `zoomIn` spring.
  final Spring openDimmingSpring;

  /// The spring the dimming falls on: UIKit's `zoomOut` spring.
  final Spring closeDimmingSpring;

  /// The opacity of the black dimming over the page underneath (a 50
  /// percent grey reads 128 -> 109 on the device, whatever the drag).
  final double dimmingOpacity;

  /// The opacity of the container's black shadow (the grey page darkens
  /// from 109 to 89 at the container's edge).
  final double shadowOpacity;

  /// The Gaussian sigma of the container's shadow in points (the
  /// darkening falls to a third 20 points out and to nothing by 60).
  final double shadowSigma;

  /// How far below the container its shadow sits, in points.
  final double shadowOffset;

  /// The finger travel, in points, the page ignores before it follows
  /// (fitted 12.5 sideways, 14.4 down).
  final double dragSlop;

  /// How far, in radians, a drag may lean off straight down or straight
  /// toward the trailing edge and still move the page: a drag 31 degrees
  /// off down does not, and neither do drags up or toward the leading
  /// edge.
  final double dragAngle;

  /// The share of its width the page loses per point of downward travel
  /// past the slop (four device drags, 2.4 points rms together with the
  /// other `down` values).
  final double downWidthRate;

  /// The share of its height the page loses per point of downward travel
  /// past the slop.
  final double downHeightRate;

  /// The share of downward finger travel the page's center follows (the
  /// page also shrinks about the point under the finger).
  final double downGain;

  /// The share of its width the page loses per point of sideways travel
  /// past the slop (the content shrinks like the height: a label read off
  /// a held drag scales 0.56 at 285 points).
  final double sidewaysWidthRate;

  /// The share of its height the page loses per point of sideways travel
  /// past the slop (4.5 points rms over a drag out and back).
  final double sidewaysHeightRate;

  /// The share of sideways finger travel the page's center follows.
  final double sidewaysGain;

  /// The finger travel past which a released page zooms back into its
  /// source: device drags held still at 70, 110 and 125 points return, at
  /// 140, 150 and 300 they dismiss.
  final double dismissDistance;

  /// The release speed along the drag, in points per second, past which
  /// a page zooms back into its source whatever its travel: a 70 point
  /// flick leaving at about 900 points per second returned, a 100 point
  /// one at about 1200 dismissed.
  final double dismissVelocity;

  /// The measured tuning.
  static const standard = ZoomPageTuning();
}

/// The zoom of a pushed page out of its source and back, as a pure
/// function of time and of the touches it is fed.
///
/// The container is four quantities in points - its center, width and
/// height - each a spring of its own. [open] sends them from the source
/// to the page, [close] back into the source, carrying each one's
/// velocity, so a reversal is continuous. While a finger drags the page
/// ([dragStart], [dragUpdate]) the container is a pure function of the
/// finger's travel ([dragFrame]); [dragEnd] either returns the page or
/// reports a dismissal, after which the owner pops the page and calls
/// [close], which starts from where the finger left the page with the
/// finger's speed.
@internal
class ZoomPageMotion {
  /// Creates a motion resting at the page.
  ZoomPageMotion({this.tuning = ZoomPageTuning.standard})
    : _cx = MotionValue<double>(0, spring: tuning.openSpring),
      _cy = MotionValue<double>(0, spring: tuning.openSpring),
      _w = MotionValue<double>(0, spring: tuning.openSpring),
      _h = MotionValue<double>(0, spring: tuning.openHeightSpring),
      _fade = MotionValue<double>(1, spring: tuning.openFadeSpring),
      _dim = MotionValue<double>(1, spring: tuning.openDimmingSpring);

  /// The measured behavior this motion reproduces.
  final ZoomPageTuning tuning;

  final MotionValue<double> _cx;
  final MotionValue<double> _cy;
  final MotionValue<double> _w;
  final MotionValue<double> _h;
  final MotionValue<double> _fade;
  final MotionValue<double> _dim;
  double _now = 0;
  bool _opening = true;
  Rect _source = Rect.zero;
  Rect _page = Rect.zero;
  Offset? _dragFrom;
  Offset _dragDelta = Offset.zero;
  bool _dragMoved = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the motion heads to the page.
  bool get isOpening => _opening;

  /// Whether a finger drags the page.
  bool get isDragging => _dragFrom != null;

  /// Whether the dragging finger has moved the page.
  bool get isScrubbing => _dragFrom != null && _dragMoved;

  /// The source frame the motion zooms out of and back into.
  Rect get source => _source;

  /// The page frame the motion zooms into.
  Rect get page => _page;

  /// Zooms out of [source] into [page] from time [t].
  void open(double t, Rect source, Rect page) {
    advance(t);
    _source = source;
    _page = page;
    _opening = true;
    _set(t, source);
    _fade.snap(t, 0);
    _dim.snap(t, 0);
    _cx.retarget(t, page.center.dx, spring: tuning.openSpring);
    _cy.retarget(t, page.center.dy, spring: tuning.openSpring);
    _w.retarget(t, page.width, spring: tuning.openSpring);
    _h.retarget(t, page.height, spring: tuning.openHeightSpring);
    _dim.retarget(t, 1, spring: tuning.openDimmingSpring);
    _fade.retarget(
      t,
      1,
      spring: tuning.openFadeSpring,
      delay: tuning.openFadeDelay,
    );
  }

  /// Shows the page in place at time [t], without a zoom.
  void showInPlace(double t, Rect source, Rect page) {
    advance(t);
    _source = source;
    _page = page;
    _opening = true;
    _set(t, page);
    _fade.snap(t, 1);
    _dim.snap(t, 1);
  }

  /// Zooms back into [source] from time [t]. After a drag the container
  /// starts from where the finger left the page, at rest (a 100 point
  /// flick on the device leaves without carrying the finger's speed), and
  /// rides [ZoomPageTuning.dismissSpring] and
  /// [ZoomPageTuning.dismissHeightSpring]; otherwise
  /// [ZoomPageTuning.closeSpring].
  void close(double t, Rect source) {
    advance(t);
    final from = _dragFrom;
    if (from != null) {
      _set(t, dragFrame(_page, from, _dragDelta));
      _dragFrom = null;
    }
    _source = source;
    _opening = false;
    final spring = from == null ? tuning.closeSpring : tuning.dismissSpring;
    final height = from == null
        ? tuning.closeSpring
        : tuning.dismissHeightSpring;
    _cx.retarget(t, source.center.dx, spring: spring);
    _cy.retarget(t, source.center.dy, spring: spring);
    _w.retarget(t, source.width, spring: spring);
    _h.retarget(t, source.height, spring: height);
    _fade.retarget(t, 0, spring: tuning.closeFadeSpring);
    _dim.retarget(t, 0, spring: tuning.closeDimmingSpring);
  }

  /// Moves the end the motion heads to when the source or the page
  /// changes frame at time [t]; the springs carry on from where they are.
  void retargetEnds(double t, {Rect? source, Rect? page}) {
    advance(t);
    if (source != null) _source = source;
    if (page != null) _page = page;
    if (_dragFrom != null) return;
    final to = _opening ? _page : _source;
    if (_cx.target != to.center.dx) _cx.retarget(t, to.center.dx);
    if (_cy.target != to.center.dy) _cy.retarget(t, to.center.dy);
    if (_w.target != to.width) _w.retarget(t, to.width);
    if (_h.target != to.height) _h.retarget(t, to.height);
  }

  /// A finger touched the page at [position] at time [t].
  void dragStart(double t, Offset position) {
    advance(t);
    _dragFrom = position;
    _dragDelta = Offset.zero;
    _dragMoved = false;
  }

  /// The dragging finger is at [position] at time [t].
  void dragUpdate(double t, Offset position) {
    advance(t);
    final from = _dragFrom;
    if (from == null) return;
    _dragDelta = position - from;
    if (_dragDelta.distance > tuning.dragSlop) _dragMoved = true;
    final frame = dragFrame(_page, from, _dragDelta);
    _set(t, frame);
  }

  /// The finger left the page at time [t] moving at [velocity] points per
  /// second; returns whether the page zooms back into its source (the
  /// owner then pops the page and calls [close]) or returns to full
  /// screen.
  bool dragEnd(double t, Offset velocity) {
    advance(t);
    if (_dragFrom == null) return false;
    final d = _dragDelta.distance;
    final along = d == 0
        ? 0.0
        : (velocity.dx * _dragDelta.dx + velocity.dy * _dragDelta.dy) / d;
    if (_dragMoved &&
        (d > tuning.dismissDistance || along > tuning.dismissVelocity)) {
      return true;
    }
    _dragFrom = null;
    final spring = tuning.returnSpring;
    _cx.retarget(t, _page.center.dx, spring: spring);
    _cy.retarget(t, _page.center.dy, spring: spring);
    _w.retarget(t, _page.width, spring: spring);
    _h.retarget(t, _page.height, spring: spring);
    return false;
  }

  /// Whether a drag that has travelled [delta] heads where the page
  /// follows: down, or toward the trailing edge ([rtl] mirrors it),
  /// within [ZoomPageTuning.dragAngle].
  bool allowsDrag(Offset delta, {bool rtl = false}) {
    if (delta.distance == 0) return false;
    final along = rtl ? -delta.dx : delta.dx;
    final limit = math.cos(tuning.dragAngle) * delta.distance;
    return delta.dy >= limit || along >= limit;
  }

  /// The page dragged by a finger that touched it at [from] and has
  /// travelled [delta]: past [ZoomPageTuning.dragSlop] it shrinks
  /// about the point under the finger - its height faster than its width
  /// on a drag down, both alike on a drag sideways - and its center
  /// follows the finger by the gains; between the two directions the
  /// rates blend by the square of the direction's components.
  Rect dragFrame(Rect page, Offset from, Offset delta) {
    final d = delta.distance;
    final e = math.max<double>(0, d - tuning.dragSlop);
    if (e == 0) return page;
    final down = delta.dy * delta.dy / (d * d);
    final side = 1 - down;
    final sw = math.max<double>(
      0,
      1 - (tuning.downWidthRate * down + tuning.sidewaysWidthRate * side) * e,
    );
    final sh = math.max<double>(
      0,
      1 - (tuning.downHeightRate * down + tuning.sidewaysHeightRate * side) * e,
    );
    final cx =
        from.dx +
        tuning.sidewaysGain * delta.dx +
        (page.center.dx - from.dx) * sw;
    final cy =
        from.dy + tuning.downGain * delta.dy + (page.center.dy - from.dy) * sh;
    return Rect.fromCenter(
      center: Offset(cx, cy),
      width: page.width * sw,
      height: page.height * sh,
    );
  }

  void _set(double t, Rect r) {
    _cx.snap(t, r.center.dx);
    _cy.snap(t, r.center.dy);
    _w.snap(t, r.width);
    _h.snap(t, r.height);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// Lands a settled motion exactly on its targets, so a page at rest
  /// fills the screen to the pixel.
  void settle() {
    for (final value in [_cx, _cy, _w, _h, _fade, _dim]) {
      value.snap(_now, value.target);
    }
  }

  /// The container's frame.
  Rect get rect => _rectAt(_now);

  Rect _rectAt(double t) => Rect.fromCenter(
    center: Offset(_cx.valueAt(t), _cy.valueAt(t)),
    width: math.max(0, _w.valueAt(t)),
    height: math.max(0, _h.valueAt(t)),
  );

  /// How far the container's frame has come from the source toward the
  /// page: the mean of its width's and its height's share, 0
  /// at the source and 1 at the page.
  double get reach => _reachAt(_now);

  double _reachAt(double t) {
    final r = _rectAt(t);
    double share(double v, double a, double b) =>
        (b - a).abs() < 1e-6 ? 1 : ((v - a) / (b - a)).clamp(0.0, 1.0);
    return (share(r.width, _source.width, _page.width) +
            share(r.height, _source.height, _page.height)) /
        2;
  }

  /// The container's corner radius, from the source's
  /// [sourceRadius] to the display's [pageRadius] by [reach] (device: 0.6
  /// points off along four pushes).
  double radius(double sourceRadius, double pageRadius) =>
      _radiusAt(_now, sourceRadius, pageRadius);

  double _radiusAt(double t, double sourceRadius, double pageRadius) =>
      lerpDouble(sourceRadius, pageRadius, _reachAt(t))!;

  /// The uniform scale the page's content is drawn at in the container:
  /// the container's width over the page's.
  double get contentScale => _contentScaleAt(_now);

  double _contentScaleAt(double t) =>
      _page.width <= 0 ? 1 : _rectAt(t).width / _page.width;

  /// The opacity of the page's content; the source's look
  /// shows at one minus it.
  double get fade => _fade.valueAt(_now).clamp(0.0, 1.0);

  /// The fraction of the dimming and of the shadow.
  double get dimming => _dimmingAt(_now);

  double _dimmingAt(double t) => _dim.valueAt(t).clamp(0.0, 1.0);

  /// Whether what remains of the motion is invisible ([GlassRest], NEAR):
  /// the frame's center and size swing less than [GlassRest.length], the
  /// crossfade and the dimming less than [GlassRest.opacity].
  bool get _rests =>
      _cx.isWithin(_now, GlassRest.length) &&
      _cy.isWithin(_now, GlassRest.length) &&
      _w.isWithin(_now, GlassRest.length) &&
      _h.isWithin(_now, GlassRest.length) &&
      _fade.isWithin(_now, GlassRest.opacity) &&
      _dim.isWithin(_now, GlassRest.opacity);

  /// Whether the motion has come back to the source and rests there.
  bool get isClosed => !_opening && _dragFrom == null && _rests;

  /// Whether the page shows at full screen and nothing moves.
  bool get isOpen => _opening && _dragFrom == null && _rests;

  /// Whether nothing moves and nothing is pending.
  bool get isSettled => _dragFrom == null && _rests;
}

/// UIKit's zoom-in spring (`_UIZoomTransitionSpec`): the dimming rises on
/// it.
const _zoomInSpring = Spring.response(0.34);

/// UIKit's zoom-out spring (`_UIZoomTransitionSpec`).
const _zoomOutSpring = Spring.response(0.34, dampingRatio: 0.92);

/// The speed along a drag, in points per second, past which a release
/// dismisses the page whatever the distance.
const double _dismissVelocity = 1050;
