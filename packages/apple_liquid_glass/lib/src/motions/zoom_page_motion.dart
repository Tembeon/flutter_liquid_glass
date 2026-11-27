import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/navigation_motion.dart';
import 'package:apple_liquid_glass/src/motions/sheet_tuning.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured motion of UIKit's zoom transition into a pushed page
/// (`preferredTransition = .zoom` on a view controller pushed onto a
/// navigation controller).
///
/// Read from screen recordings of an iPhone 16 Pro on iOS 27.0.1 (four
/// pushes from a 160 x 100 card, a pop by the back button, drags down,
/// sideways and from the edge). The zooming container's center and width
/// ride one spring and its height another on the way in; a back-button pop
/// returns all of them on UIKit's `zoomOut` spring, a drag's dismissal on
/// [ZoomPageTuning.dismissSpring] and [ZoomPageTuning.dismissHeightSpring].
/// The page's content is drawn
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
    this.dragAngle = math.pi / 8,
    this.dragAnglePadding = 15,
    this.downWidthRate = 0.00078,
    this.downHeightRate = 0.00154,
    this.downGain = 0.61,
    this.sidewaysWidthRate = 0.00156,
    this.sidewaysHeightRate = 0.00168,
    this.sidewaysGain = 0.95,
    this.panSlop = 10,
    this.dismissThreshold = 150,
    this.dismissProjection = 0.099,
    this.edgeDismissThreshold = 200,
    this.pinchDismissScale = 0.5,
    this.pinchDismissDrop = 200,
    this.pinchMinimumScale = 0.25,
    this.pinchStretchBelow = 0.1,
    this.pinchStretchAbove = 0.75,
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
  /// (fitted 12.5 sideways, 14.4 down; drags from the edge included).
  final double dragSlop;

  /// How far, in radians, a drag may lean off straight down or straight
  /// toward the trailing edge and still move the page: 22.5 degrees each
  /// side, UIKit's cones (read from UIKit's code; a device drag 31 degrees
  /// off down did not move the page). Drags up or toward the leading edge
  /// never do.
  final double dragAngle;

  /// How much farther than [dragSlop], in points, a drag outside the
  /// [dragAngle] cones may still turn into them before it gives up: UIKit's
  /// hysteresis padding, 15 (read from UIKit's code).
  final double dragAnglePadding;

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

  /// The travel UIKit's pan takes out of the drag's translation once it
  /// begins, in points (its 10 point slop, read from its code).
  final double panSlop;

  /// The projected translation past which a released page zooms back into
  /// its source: the translation along the drag's axis less [panSlop],
  /// plus [dismissProjection] times the release speed along it, over 150
  /// points (read from UIKit's code; eight injected drags on the iOS 27.2
  /// simulator ended as it says, and the device drags do when their holds
  /// kept the drag's speed, as synthesized holds do).
  final double dismissThreshold;

  /// The seconds of release speed added to the translation: a 0.99
  /// deceleration's projection, 0.99 / (1 - 0.99) / 1000.
  final double dismissProjection;

  /// The projected translation past which a pan from the leading edge
  /// dismisses the page: 200 points, measured from where the pan began
  /// (read from UIKit's code).
  final double edgeDismissThreshold;

  /// The pinch scale under which a released pinch dismisses the page
  /// (read from UIKit's code).
  final double pinchDismissScale;

  /// How far down, in points, the point between the pinching fingers may
  /// move before a released pinch dismisses the page whatever its scale
  /// (read from UIKit's code: a pinch's threshold, at no speed).
  final double pinchDismissDrop;

  /// The scale a pinch shows at least before it resists: UIKit's minimum
  /// pinch scale (read from its code).
  final double pinchMinimumScale;

  /// How far below [pinchMinimumScale] a pinch can ever show the page.
  final double pinchStretchBelow;

  /// How far above full size a pinch can ever show the page.
  final double pinchStretchAbove;

  /// The measured tuning.
  static const standard = ZoomPageTuning();
}

/// The zoom of a pushed page out of its source and back, in the page's
/// coordinates.
///
/// The container is four quantities in points - its center, width and
/// height - each a spring of its own. [open] puts it on the source and
/// [start] sends it to the page; [leave] sends it back into the source,
/// carrying each one's velocity, so a reversal is continuous. While a
/// finger drags the page ([dragStart] or [edgePanStart], [dragUpdate]) the
/// container is a pure function of the finger's travel ([dragFrame]), and
/// while two fingers pinch it ([pinchStart], [pinchUpdate]) of their
/// scale ([pinchFrame]); [dragEnd] either returns the page or reports a
/// dismissal, after which the shell pops the page and [leave] starts from
/// where the fingers left the page, at rest.
///
/// It rests within [MotionRest.length] for the frame and
/// [MotionRest.opacity] for the crossfade and the dimming (NEAR).
final class ZoomPageMotion extends PageMotion with Sourced {
  /// Creates a motion for a page filling [page], in global coordinates.
  ZoomPageMotion({
    @internal this.tuning = ZoomPageTuning.standard,
    Rect page = Rect.zero,
    this.commits = false,
    super.clock,
  }) : _origin = page.topLeft,
       _size = page.size;

  /// Whether the page grows out of a context menu's preview, as UIKit
  /// commits a tapped preview into the page it opens (read from UIKit's
  /// code, iOS 27.2 simulator): the container's size and corners move on a
  /// spring of 0.5 s and damping 0.7 that starts at 15 times its distance a
  /// second, its center and the page's fade on a critically damped 0.35 s
  /// spring; the preview fades out over the first 0.14 s, and the screen
  /// behind gives way to the page's background from 0.105 s to 0.245 s.
  /// Both the preview and the page fill the container, centered. Once the
  /// page is in, it leaves as a zooming page does.
  final bool commits;

  static final _commitSize = Spring.settling(duration: 0.5, dampingRatio: 0.7);
  static final _commitMove = Spring.settling(duration: 0.35, dampingRatio: 1);
  static const double _commitKick = 15;
  static const _commitLook = TimingCurve(0.14, curve: Curves.linear);
  static const _commitBackdrop = TimingCurve(0.14, curve: Curves.linear);
  static const double _commitBackdropDelay = 0.105;

  // Whether the page is in its commit: from the start until it leaves.
  bool get _committing => commits && !_left;
  bool _left = false;

  /// The measured behavior this motion reproduces.
  @internal
  final ZoomPageTuning tuning;

  /// The radius of the display's corners, which the container's corners
  /// turn into.
  double displayRadius = SheetTuning.fallbackDisplayRadius;

  late final _cx = own(
    MotionValue<double>(0, spring: tuning.openSpring, restDistance: _length),
  );
  late final _cy = own(
    MotionValue<double>(0, spring: tuning.openSpring, restDistance: _length),
  );
  late final _w = own(
    MotionValue<double>(0, spring: tuning.openSpring, restDistance: _length),
  );
  late final _h = own(
    MotionValue<double>(
      0,
      spring: tuning.openHeightSpring,
      restDistance: _length,
    ),
  );
  late final _fade = own(
    MotionValue<double>(
      1,
      spring: tuning.openFadeSpring,
      restDistance: _opacity,
    ),
  );
  late final _dim = own(
    MotionValue<double>(
      1,
      spring: tuning.openDimmingSpring,
      restDistance: _opacity,
    ),
  );
  late final _look = own(MotionValue<double>(1, restDistance: _opacity));
  final Offset _origin;
  Size _size;
  bool _shown = false;
  bool _started = false;
  Rect _source = Rect.zero;
  double _sourceRadius = 0;
  Offset? _dragFrom;
  Offset _dragDelta = Offset.zero;
  bool _dragMoved = false;
  // The drag's axis toward the dismissal, set as it passes the slop.
  Offset _axis = Offset.zero;
  // Where a pan from the leading edge measures its translation from.
  Offset? _edgeFrom;
  // The scale of a pinch, null while a finger drags.
  double? _pinch;
  // UIKit's pan velocity: one sample per move, its displacement over the
  // time since the move before, the last two weighed 0.2 and 0.8.
  double _lastMove = 0;
  Offset _lastAt = Offset.zero;
  Offset? _sample;
  Offset? _earlierSample;

  static double _length() => MotionRest.length;
  static double _opacity() => MotionRest.opacity;

  Rect get _page => Offset.zero & _size;

  /// Whether a finger drags the page.
  bool get isDragging => _dragFrom != null;

  /// The source frame the motion zooms out of and back into.
  Rect get source => _source;

  @override
  bool get isShown => _shown;

  /// Whether a finger may take the page now.
  bool get takesDrag => _shown && presence == PresenceStatus.shown;

  @override
  bool get holds => _dragFrom != null || (_shown && !_started);

  @override
  PresenceStatus get presence =>
      PresenceStatus.of(shown: _shown, settled: isSettled);

  @override
  double get progress => reach;

  @override
  void sourceMoved(double t, SourceGeometry? geometry) {
    if (geometry == null) return;
    advance(t);
    _source = geometry.rect.shift(-_origin);
    final radius = geometry.borderRadius.topLeft.x;
    if (radius != _sourceRadius) {
      _sourceRadius = radius;
      changed();
    }
    if (_dragFrom != null) return;
    if (!_started) {
      _set(t, _source);
    } else if (!_shown) {
      _retarget(t, _source);
    }
  }

  /// The page takes [size] from time [t]: a page shown heads to it.
  void resize(double t, Size size) {
    if (size == _size) return;
    advance(t);
    _size = size;
    if (_dragFrom == null && _shown && _started) _retarget(t, _page);
  }

  /// Puts the container on the source at time [t], to zoom out of it once
  /// [start] runs.
  @override
  void open(double t) {
    advance(t);
    _shown = true;
    _started = false;
    changed();
    _set(t, _source);
    _fade.snap(t, 0);
    _dim.snap(t, 0);
    _look.snap(t, 1);
  }

  /// Zooms out of the source into the page from time [t].
  @override
  void start(double t) {
    advance(t);
    _started = true;
    if (commits) return _commit(t);
    _zoomTo(t, _page, tuning.openSpring, height: tuning.openHeightSpring);
    _dim.retarget(t, 1, spring: tuning.openDimmingSpring);
    _fade.retarget(
      t,
      1,
      spring: tuning.openFadeSpring,
      delay: tuning.openFadeDelay,
    );
  }

  void _commit(double t) {
    final page = _page;
    _cx.retarget(t, page.center.dx, spring: _commitMove);
    _cy.retarget(t, page.center.dy, spring: _commitMove);
    for (final (value, to) in [(_w, page.width), (_h, page.height)]) {
      value.setVelocity(t, _commitKick * (to - value.valueAt(t)));
      value.retarget(t, to, spring: _commitSize);
    }
    _fade.retarget(t, 1, spring: _commitMove);
    _look.animate(t, 0, animation: _commitLook);
    _dim.animate(
      t,
      1,
      animation: _commitBackdrop,
      delay: _commitBackdropDelay,
    );
  }

  @override
  void showInPlace(double t) {
    advance(t);
    _started = true;
    _set(t, _page);
    _fade.snap(t, 1);
    _dim.snap(t, 1);
  }

  /// Zooms back into the source from time [t]. After a drag the container
  /// starts from where the finger left the page, at rest (a 100 point
  /// flick on the device leaves without carrying the finger's speed), and
  /// rides [ZoomPageTuning.dismissSpring] and
  /// [ZoomPageTuning.dismissHeightSpring]; otherwise
  /// [ZoomPageTuning.closeSpring].
  @override
  bool leave(double t) {
    advance(t);
    final from = _dragFrom;
    if (from != null) {
      _set(t, _heldFrame(from));
      _dragFrom = null;
    }
    _shown = false;
    _started = true;
    _left = true;
    if (from == null) {
      _zoomTo(t, _source, tuning.closeSpring);
    } else {
      _zoomTo(
        t,
        _source,
        tuning.dismissSpring,
        height: tuning.dismissHeightSpring,
      );
    }
    _fade.retarget(t, 0, spring: tuning.closeFadeSpring);
    _dim.retarget(t, 0, spring: tuning.closeDimmingSpring);
    return true;
  }

  void _retarget(double t, Rect to) {
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
    _axis = Offset.zero;
    _lastMove = t;
    _lastAt = position;
    _sample = null;
    _earlierSample = null;
    _edgeFrom = null;
    _pinch = null;
    changed();
  }

  /// A finger that touched the page's leading edge at [position] took it
  /// at time [t], having moved inward to [from], the touch before the one
  /// that began the pan, where UIKit's edge pan measures its translation
  /// from; it drags the page toward the trailing side ([rtl] mirrors it),
  /// as [dragUpdate] says, and [dragEnd] weighs it against
  /// [ZoomPageTuning.edgeDismissThreshold].
  void edgePanStart(
    double t,
    Offset position, {
    required Offset from,
    required bool rtl,
  }) {
    dragStart(t, position);
    _edgeFrom = from;
    _dragMoved = true;
    _axis = Offset(rtl ? -1 : 1, 0);
  }

  /// Two fingers began to pinch the page in about [focal], the point
  /// between them, at time [t].
  void pinchStart(double t, Offset focal) {
    dragStart(t, focal);
    _pinch = 1;
    _dragMoved = true;
    _axis = const Offset(0, 1);
  }

  /// The pinching fingers stand [scale] times as far apart as when they
  /// began, about [focal], at time [t].
  void pinchUpdate(double t, double scale, Offset focal) {
    advance(t);
    final from = _dragFrom;
    if (from == null || _pinch == null) return;
    _pinch = scale;
    _dragDelta = focal - from;
    _set(t, _heldFrame(from));
  }

  Rect _heldFrame(Offset from) => switch (_pinch) {
    final scale? => pinchFrame(_page, from, scale, _dragDelta),
    null => dragFrame(_page, from, _dragDelta),
  };

  /// The release velocity UIKit's pan reports: the last move's speed at
  /// 0.2 and the one before at 0.8; a lift adds no sample, so a finger
  /// that rested without moving keeps the speed it had (read from UIKit's
  /// code).
  Offset get _panVelocity {
    final last = _sample;
    if (last == null) return Offset.zero;
    final earlier = _earlierSample;
    return earlier == null ? last : last * 0.2 + earlier * 0.8;
  }

  /// The dragging finger is at [position] at time [t].
  void dragUpdate(double t, Offset position) {
    advance(t);
    final from = _dragFrom;
    if (from == null) return;
    _dragDelta = position - from;
    if (position != _lastAt) {
      final dt = t - _lastMove;
      _earlierSample = _sample;
      _sample = dt < 0.001 ? Offset.zero : (position - _lastAt) / dt;
      _lastMove = t;
      _lastAt = position;
    }
    if (!_dragMoved && _pastSlop(_dragDelta)) {
      _dragMoved = true;
      _axis = _dragDelta.dy.abs() >= _dragDelta.dx.abs()
          ? const Offset(0, 1)
          : Offset(_dragDelta.dx.sign, 0);
    }
    _set(t, dragFrame(_page, from, _dragDelta));
  }

  /// The fingers left the page at time [t]; returns whether the page
  /// zooms back into its source (the shell then pops the page and [leave]
  /// runs) or returns to full screen. A drag dismisses as
  /// [ZoomPageTuning.dismissThreshold] says, a pan from the edge as
  /// [ZoomPageTuning.edgeDismissThreshold], and a pinch as
  /// [ZoomPageTuning.pinchDismissScale] and
  /// [ZoomPageTuning.pinchDismissDrop] say.
  bool dragEnd(double t) {
    advance(t);
    final from = _dragFrom;
    if (from == null) return false;
    double along(Offset v) => v.dx * _axis.dx + v.dy * _axis.dy;
    final pinch = _pinch;
    final edge = _edgeFrom;
    final dismisses = switch ((pinch, edge)) {
      (final scale?, _) =>
        scale < tuning.pinchDismissScale ||
            _dragDelta.dy > tuning.pinchDismissDrop,
      (null, final edge?) =>
        along(from + _dragDelta - edge) +
                tuning.dismissProjection * along(_panVelocity) >
            tuning.edgeDismissThreshold,
      (null, null) =>
        _dragMoved &&
            math.max(0, along(_dragDelta) - tuning.panSlop) +
                    tuning.dismissProjection * along(_panVelocity) >
                tuning.dismissThreshold,
    };
    if (dismisses) return true;
    stay(t);
    return false;
  }

  /// Returns the page to full screen from time [t]: the finger let go
  /// short of a dismissal, or the dismissal it asked for was refused.
  void stay(double t) {
    advance(t);
    _dragFrom = null;
    _pinch = null;
    _edgeFrom = null;
    _zoomTo(t, _page, tuning.returnSpring);
  }

  void _zoomTo(double t, Rect to, Spring spring, {Spring? height}) {
    _cx.retarget(t, to.center.dx, spring: spring);
    _cy.retarget(t, to.center.dy, spring: spring);
    _w.retarget(t, to.width, spring: spring);
    _h.retarget(t, to.height, spring: height ?? spring);
  }

  bool _pastSlop(Offset delta) => delta.distance > tuning.dragSlop;

  /// Whether the page follows a finger that has travelled [delta] since
  /// the touch: null while the travel is within [ZoomPageTuning.dragSlop],
  /// then true once it heads down or toward the trailing edge ([rtl]
  /// mirrors it) within [ZoomPageTuning.dragAngle], and false once it has
  /// gone [ZoomPageTuning.dragAnglePadding] farther outside those cones.
  bool? allowsDrag(Offset delta, {bool rtl = false}) {
    if (!_pastSlop(delta)) return null;
    final along = rtl ? -delta.dx : delta.dx;
    final limit = math.cos(tuning.dragAngle) * delta.distance;
    if (delta.dy >= limit || along >= limit) return true;
    final waits = delta.distance <= tuning.dragSlop + tuning.dragAnglePadding;
    return waits ? null : false;
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

  /// The page pinched by fingers that began about [from] and stand [scale]
  /// times as far apart about [from] plus [delta]: it shows the scale held
  /// inside [ZoomPageTuning.pinchMinimumScale] and full size by UIKit's
  /// rubber band, [ZoomPageTuning.pinchStretchBelow] and
  /// [ZoomPageTuning.pinchStretchAbove] past them (read from UIKit's code;
  /// its pinch also turns the page with the fingers, which this does not),
  /// about the point between the fingers, which it follows.
  Rect pinchFrame(Rect page, Offset from, double scale, Offset delta) {
    final low = tuning.pinchMinimumScale;
    final shown = scale < low
        ? RubberBand(
            low,
            double.infinity,
            dimension: tuning.pinchStretchBelow,
          ).apply(scale)
        : RubberBand(
            double.negativeInfinity,
            1,
            dimension: tuning.pinchStretchAbove,
          ).apply(scale);
    return Rect.fromCenter(
      center: from + delta + (page.center - from) * shown,
      width: page.width * shown,
      height: page.height * shown,
    );
  }

  void _set(double t, Rect r) {
    _cx.snap(t, r.center.dx);
    _cy.snap(t, r.center.dy);
    _w.snap(t, r.width);
    _h.snap(t, r.height);
  }

  /// The container's frame.
  Rect get rect => Rect.fromCenter(
    center: Offset(_cx.valueAt(now), _cy.valueAt(now)),
    width: math.max(0, _w.valueAt(now)),
    height: math.max(0, _h.valueAt(now)),
  );

  /// How far the container's frame has come from the source toward the
  /// page: the mean of its width's and its height's share, 0
  /// at the source and 1 at the page.
  double get reach {
    final r = rect;
    final page = _page;
    double share(double v, double a, double b) =>
        (b - a).abs() < 1e-6 ? 1 : ((v - a) / (b - a)).clamp(0.0, 1.0);
    return (share(r.width, _source.width, page.width) +
            share(r.height, _source.height, page.height)) /
        2;
  }

  /// The container's corner radius, from the source's to [displayRadius]
  /// by [reach] (device: 0.6 points off along four pushes).
  double get radius => lerpDouble(_sourceRadius, displayRadius, reach)!;

  /// Where the page's content is drawn in the container, as a uniform
  /// scale and the shift of its top left: the container's width over the
  /// page's, from the container's top; filling the container, centered,
  /// while the page commits.
  (double, Offset) get contentPlacement => _placed(_size);

  /// Where the source's look is drawn in the container, as
  /// [contentPlacement] is.
  (double, Offset) get lookPlacement => _placed(_source.size);

  (double, Offset) _placed(Size size) {
    final r = rect;
    if (size.width <= 0 || size.height <= 0) return (1, Offset.zero);
    if (!_committing) return (r.width / size.width, Offset.zero);
    final scale = math.max(r.width / size.width, r.height / size.height);
    return (
      scale,
      Offset(
        (r.width - size.width * scale) / 2,
        (r.height - size.height * scale) / 2,
      ),
    );
  }

  /// The opacity of the page's content.
  double get fade => _fade.valueAt(now).clamp(0.0, 1.0);

  /// The opacity of the source's look: one minus [fade], and its own fade
  /// while the page commits.
  double get lookOpacity =>
      _committing ? _look.valueAt(now).clamp(0.0, 1.0) : 1 - fade;

  /// Whether what lies under the container is the screen giving way to the
  /// page's background, as while the page commits, rather than a dimming.
  bool get coversBackdrop => _committing;

  /// The fraction of the dimming and of the shadow, or of the backdrop's
  /// cover while the page commits.
  double get dimming => _dim.valueAt(now).clamp(0.0, 1.0);
}

/// UIKit's zoom-in spring (`_UIZoomTransitionSpec`): the dimming rises on
/// it.
const _zoomInSpring = Spring.response(0.34);

/// UIKit's zoom-out spring (`_UIZoomTransitionSpec`).
const _zoomOutSpring = Spring.response(0.34, dampingRatio: 0.92);
