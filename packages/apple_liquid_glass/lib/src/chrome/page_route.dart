import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:apple_liquid_glass/src/chrome/zoom_source.dart';
import 'package:apple_liquid_glass/src/motion/live.dart';
import 'package:apple_liquid_glass/src/motion/navigation_motion.dart';
import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:apple_liquid_glass/src/motion/zoom_page_motion.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// An iOS 27 page pushed onto a navigator: it slides in over the page
/// below, which moves aside and dims under it.
///
/// UIKit: `UINavigationController.pushViewController(_:animated:)`.
/// SwiftUI: `NavigationLink`. Flutter: `CupertinoPageRoute`.
///
/// Without a finger the page slides on a critically damped spring of
/// response 0.3, leaving its start at 8.77 widths a second; the page below
/// moves aside by the width less 0.7 of it and dims under black at 10
/// percent, both with the page's progress; while they move, both pages are
/// cards with the display's corners and the top one casts UIKit's light
/// shadow (read from UIKit, notes private; device recordings). A finger
/// that drags the page toward the trailing side pops it as UIKit's
/// interactive pop does, from the leading edge (9 percent of the width)
/// after 15 points, or from anywhere else after 30 points within UIKit's
/// funnel, so drags and scrolls of the page's own that claim the touch
/// first keep it: the page follows the finger, rubber bands past either
/// end, and on release pops or returns as UIKit predicts from the finger's
/// last speeds, on a spring of response 0.3 and damping 0.85. Under Reduce
/// Motion a push or pop without a finger cross-fades over 0.5 s instead.
/// Back, Escape and a screen reader's dismiss pop it through the page's
/// `PopScope`s; a pop asked for while a finger holds the page waits for
/// the release, which then takes the page out.
///
/// The pages of a navigator share one `GlassNavigationBar`, drawn right
/// above the topmost glass page and under every route pushed after it, so
/// alerts, sheets and menus cover it; its capsules stay while the pages
/// move and change into the next page's as UIKit's do. The page follows
/// the finger one to one; UIKit's settings carry a
/// tracking spring whose use is not confirmed on the device. A finger does
/// not catch a page that is already leaving, as UIKit's does: the
/// navigator has popped it by then.
///
/// With a [source], the page zooms out of it instead, as a UIKit page
/// with `preferredTransition = .zoom` does: it grows from the source's
/// frame to the screen, center and width on a critically damped spring of
/// response 0.317 and height on one of 0.406, while the source's look
/// crossfades into it and the page underneath dims 15 percent under the
/// growing card's shadow; popped, it shrinks back into the source on
/// UIKit's zoom-out spring (iPhone 16 Pro recordings, replayed). A drag
/// down or toward the trailing side shrinks the page under the finger
/// after 13.5 points, and a release past 132.5 points or at 1050 points a
/// second pops it into the source; short of that it returns. The source
/// hides while the page shows. Without an attached source the page
/// slides.
class GlassPageRoute<T> extends PresentationPageRoute<T> {
  /// Creates a page [builder] builds, zooming out of [source] when given.
  GlassPageRoute({required this.builder, this.source, super.settings});

  /// Builds the page.
  final WidgetBuilder builder;

  /// The source the page zooms out of and back into, or null for a page
  /// that slides in.
  final GlassZoomLink? source;

  // Fixed when the page is installed, so the page and the route agree on
  // its transition for its whole life.
  late final bool _zooms = source?.isAttached ?? false;
  _ZoomState? _zoom;

  final _presence = MotionValue<double>(
    0,
    spring: NavigationTuning.pushSpring,
    restDistance: GlassRest.opacity / 10,
  );
  final _fades = ValueNotifier<bool>(false);
  _SlideState? _slide;

  // The motion time of the push or pop call that presented the page.
  double _presented = 0;

  // The page above this one, whose progress moves and dims this one.
  final _cover = ValueNotifier<GlassPageRoute<Object?>?>(null);
  GlassPageRoute<Object?>? _below;

  // The page's end of its navigator's shared bar.
  late final GlassPageBarLink _bar;
  bool _presenting = false;

  // The time of the finger's lift that committed a swipe's pop.
  double? _lifted;

  @override
  void install() {
    _bar = GlassBarHost.of(navigator!).attach(this, presence: _presence);
    super.install();
  }

  @override
  bool get maintainState => true;

  @override
  void didPresent() {
    super.didPresent();
    _presented = MotionClock.instance.now;
    _presenting = true;
  }

  // A zooming page shows the page underneath around its card.
  @override
  bool get opaque => !_zooms;

  // Another glass page below follows this page's progress itself, from the
  // push on; any other page below gets it from the navigator, which hands
  // it over once this page rests.
  @override
  DelegatedTransitionBuilder? get delegatedTransition => _zooms
      ? null
      : (context, animation, secondaryAnimation, allowSnapshotting, child) =>
            ModalRoute.of(context) is GlassPageRoute
            ? null
            : _Underneath(presence: _presence, fades: _fades, child: child);

  @override
  void didChangePrevious(Route<Object?>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _uncover();
    if (previousRoute is GlassPageRoute) {
      _below = previousRoute;
      // The page under a zoom stays where it is.
      if (!_zooms) previousRoute._cover.value = this;
    }
    final below = previousRoute is GlassPageRoute ? previousRoute._bar : null;
    if (_presenting) {
      _presenting = false;
      _bar.host.presented(
        _bar,
        below: below,
        current: isCurrent,
        animated: animation?.status == AnimationStatus.forward,
        time: _presented,
      );
    } else {
      _bar.host.previousChanged(
        _bar,
        below: below,
        time: MotionClock.instance.now,
      );
    }
  }

  @override
  void didChangeNext(Route<Object?>? nextRoute) {
    super.didChangeNext(nextRoute);
    _bar.host.coveredChanged(
      _bar,
      covered: nextRoute is PageRoute && nextRoute is! GlassPageRoute,
    );
  }

  @override
  void didPopNext(Route<Object?> nextRoute) {
    super.didPopNext(nextRoute);
    if (nextRoute is! GlassPageRoute) _bar.host.revealed(_bar);
  }

  @override
  void beginInteraction() {
    super.beginInteraction();
    _bar.host.swipeStarted(_bar);
  }

  @override
  void endInteraction() {
    super.endInteraction();
    _bar.host.swipeEnded(_bar);
  }

  void _uncover() {
    final below = _below;
    if (below != null && identical(below._cover.value, this)) {
      below._cover.value = null;
    }
    _below = null;
  }

  @override
  void didFinish(T? result) {
    _uncover();
    _bar.host.finished(_bar);
    super.didFinish(result);
  }

  @override
  void dispose() {
    _uncover();
    _bar.host.detach(_bar);
    _cover.dispose();
    _fades.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) => GlassBarSlot(
    link: _bar,
    child: _zooms
        ? _Zoom(
            route: this,
            child: Builder(builder: builder),
          )
        : _Slide(
            route: this,
            child: Builder(builder: builder),
          ),
  );

  @override
  bool leave(DismissTrigger trigger) {
    final lifted = trigger == DismissTrigger.interaction ? _lifted : null;
    _lifted = null;
    _bar.host.leaving(_bar, time: lifted ?? MotionClock.instance.now);
    if (_zooms) {
      final zoom = _zoom;
      if (zoom == null || !zoom.mounted) return false;
      zoom.leave();
      return true;
    }
    final slide = _slide;
    if (slide == null || !slide.mounted) return false;
    slide.leave();
    return true;
  }
}

class _Slide extends StatefulWidget {
  const _Slide({required this.route, required this.child});

  final GlassPageRoute<Object?> route;
  final Widget child;

  @override
  State<_Slide> createState() => _SlideState();
}

/// The page's slide, its cross-fade under Reduce Motion and its
/// interactive pop, reported to the route's lifecycle.
class _SlideState extends State<_Slide> implements MotionDriver {
  late final _input = _SwipePop(this);
  late final List<Interaction> _interactions = [_input];
  bool _opening = true;
  bool _leaving = false;
  bool _interacting = false;
  bool _returning = false;
  double _width = 400;

  // A cross-fade's start and direction, or null while the page slides.
  double? _fadeStart;
  double _fadeTo = 1;

  GlassPageRoute<Object?> get route => widget.route;
  MotionValue<double> get _presence => route._presence;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    route._slide = this;
    MotionClock.instance.addDriver(this);
    // A page added without a push, as a navigator's first, stands in place.
    if (route.animation?.status == AnimationStatus.completed) {
      _opening = false;
      _presence.snap(_now, 1);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_opening) return;
      final clock = MotionClock.instance;
      _move(
        to: 1,
        at: transitionOrigin(
          call: route._presented,
          firstFrame: clock.now,
          framePeriod: clock.framePeriod,
        ),
      );
    });
  }

  @override
  void dispose() {
    if (identical(route._slide, this)) route._slide = null;
    MotionClock.instance.removeDriver(this);
    super.dispose();
  }

  bool get _reduceMotion => GlassTraits.of(context).reduceMotion;

  // A push or pop without a finger: a slide that leaves at full speed, or
  // a cross-fade under Reduce Motion.
  void _move({required double to, double? at}) {
    final t = at ?? _now;
    if (_reduceMotion) {
      route._fades.value = true;
      _fadeStart = t;
      _fadeTo = to;
    } else {
      route._fades.value = false;
      _fadeStart = null;
      _presence.setVelocity(
        t,
        to > _presence.value
            ? NavigationTuning.pushVelocity
            : -NavigationTuning.pushVelocity,
      );
      _presence.retarget(t, to, spring: NavigationTuning.pushSpring);
    }
    MotionClock.instance.wake(this);
  }

  void leave() {
    _leaving = true;
    _opening = false;
    // Under a finger, its release takes the page out.
    if (_interacting && !_returning) return;
    if (_returning) {
      _returning = false;
      _interacting = false;
      route.endInteraction();
    }
    _move(to: 0);
  }

  @override
  bool get isActive =>
      _fadeStart != null ||
      (_opening && _presence.value >= 1) ||
      (_leaving && _presence.value <= 0) ||
      (_returning && _presence.value >= 1) ||
      !_presence.isWithin(_now, GlassRest.length / _width);

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    final start = _fadeStart;
    if (start != null) {
      final p = ((time - start) / NavigationTuning.crossFadeDuration).clamp(
        0.0,
        1.0,
      );
      final eased = NavigationTuning.crossFadeCurve.transform(p);
      _presence.snap(time, _fadeTo == 1 ? eased : 1 - eased);
      if (p >= 1) _fadeStart = null;
    } else if (_presence.isWithin(time, GlassRest.length / _width)) {
      _presence.snap(time, _presence.target);
    }
    final value = _presence.value;
    if (_opening && value >= 1 && _fadeStart == null) {
      _opening = false;
      route.didOpen();
    }
    if (_leaving && value <= 0 && _fadeStart == null) {
      _leaving = false;
      route.didLeave();
    }
    if (_returning && value >= 1) {
      _returning = false;
      _interacting = false;
      route.endInteraction();
    }
  }

  bool get _canPop =>
      !_opening &&
      !_leaving &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted() {
    _interacting = true;
    _returning = false;
    route.beginInteraction();
  }

  void _dragged(double progress) {
    _presence.snap(_now, 1 - NavigationTuning.rubberBand(progress));
  }

  void _released({required bool pops, required double velocity}) {
    final t = _now;
    _presence.setVelocity(t, -velocity);
    if (pops || _leaving) {
      _presence.retarget(t, 0, spring: NavigationTuning.interactiveSpring);
      route.dismiss(DismissTrigger.interaction);
      _interacting = false;
      route.endInteraction();
      if (!_leaving) {
        // A PopScope vetoed the pop: the page returns.
        _presence.retarget(t, 1, spring: NavigationTuning.interactiveSpring);
        _interacting = true;
        _returning = true;
        route.beginInteraction();
      }
    } else {
      _presence.retarget(t, 1, spring: NavigationTuning.interactiveSpring);
      _returning = true;
    }
    MotionClock.instance.wake(this);
  }

  // The page builds in the build phase, never under a LayoutBuilder: what
  // it declares to the shared bar is in place before any layout.
  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _width = MediaQuery.sizeOf(context).width;
    _input.rtl = rtl;
    return InputRegion(
      interactions: _interactions,
      child: _Card(
        presence: _presence,
        fades: route._fades,
        radius: _cardRadius(context),
        rtl: rtl,
        child: ValueListenableBuilder(
          valueListenable: route._cover,
          builder: (context, cover, child) => cover == null
              ? child!
              : _Underneath(
                  presence: cover._presence,
                  fades: cover._fades,
                  child: child,
                ),
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

BorderRadius _cardRadius(BuildContext context) =>
    MediaQuery.maybeDisplayCornerRadiiOf(context) ??
    const BorderRadius.all(
      Radius.circular(NavigationTuning.fallbackCardRadius),
    );

/// The interactive pop: a touch on the page that moves along it toward
/// the trailing side drags the page, and its release pops or returns the
/// page as UIKit predicts. A touch on the leading edge begins after
/// [NavigationTuning.edgeHysteresis]; one elsewhere, UIKit's content
/// swipe, after [NavigationTuning.contentHysteresis] inside its funnel, so
/// the page's own drags and scrolls take the touches they claim first.
final class _SwipePop extends Interaction {
  _SwipePop(this._slide) : super(role: InteractionRole.gesture);

  final _SlideState _slide;
  double _width = 400;
  bool rtl = false;
  int? _pointer;
  Offset _start = Offset.zero;
  bool _fromEdge = false;
  bool _dragging = false;
  late NavigationPopMotion _predictor;

  double _along(Offset position) => rtl ? -position.dx : position.dx;

  @override
  bool get dragged => _dragging;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && _pointer == null && _slide._canPop;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _width = input.regionSize.width;
        _pointer = input.pointer;
        _start = input.position;
        final x = rtl ? _width - input.position.dx : input.position.dx;
        _fromEdge = x <= _width * NavigationTuning.edgeShare;
        _dragging = false;
        _predictor = NavigationPopMotion(_width);
        _predictor.addPosition(input.time, _along(input.position));
      case PointerMoveInput() when input.pointer == _pointer:
        final along = _along(input.position);
        final predictor = _predictor;
        predictor.addPosition(input.time, along);
        final travel = along - _along(_start);
        if (!_dragging) {
          if (_fromEdge) {
            if (travel.abs() < NavigationTuning.edgeHysteresis) break;
          } else {
            final across = (input.position.dy - _start.dy).abs();
            if (across >= NavigationTuning.contentFunnel(travel) ||
                travel <= -NavigationTuning.contentHysteresis) {
              _pointer = null;
              return const InteractionUpdate(fails: true);
            }
            if (travel < NavigationTuning.contentHysteresis) break;
          }
          _dragging = true;
          _start = input.position;
          _slide._dragStarted();
          predictor.begin(input.time);
          return const InteractionUpdate(recognizes: true);
        }
        final progress = travel / _width;
        _slide._dragged(progress);
        predictor.update(input.time, progress);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        final predictor = _predictor;
        final progress = (_along(input.position) - _along(_start)) / _width;
        predictor.update(input.time, progress, ending: true);
        _slide.route._lifted = input.time;
        _slide._released(
          pops: predictor.shouldPop(progress),
          velocity: predictor.settleVelocity,
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        if (_dragging) {
          _dragging = false;
          _slide._released(pops: false, velocity: 0);
        }
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The page on top: moved by its progress, a card with the display's
/// corners and a light shadow while it moves, faded instead under a
/// cross-fade.
class _Card extends SingleChildRenderObjectWidget {
  const _Card({
    required this.presence,
    required this.fades,
    required this.radius,
    required this.rtl,
    required super.child,
  });

  final ValueListenable<double> presence;
  final ValueListenable<bool> fades;
  final BorderRadius radius;
  final bool rtl;

  @override
  _RenderCard createRenderObject(BuildContext context) => _RenderCard(
    presence: presence,
    fades: fades,
    radius: radius,
    rtl: rtl,
    top: true,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderCard renderObject) {
    renderObject.presence = presence;
    renderObject.fades = fades;
    renderObject.radius = radius;
    renderObject.rtl = rtl;
  }
}

/// The page below: moved aside and dimmed with the page above's
/// progress, a card while it moves, faded out under a cross-fade.
class _Underneath extends StatelessWidget {
  const _Underneath({
    required this.presence,
    required this.fades,
    required this.child,
  });

  final ValueListenable<double> presence;
  final ValueListenable<bool> fades;
  final Widget? child;

  @override
  Widget build(BuildContext context) => _UnderneathCard(
    presence: presence,
    fades: fades,
    radius: _cardRadius(context),
    rtl: Directionality.of(context) == TextDirection.rtl,
    child: child,
  );
}

class _UnderneathCard extends SingleChildRenderObjectWidget {
  const _UnderneathCard({
    required this.presence,
    required this.fades,
    required this.radius,
    required this.rtl,
    super.child,
  });

  final ValueListenable<double> presence;
  final ValueListenable<bool> fades;
  final BorderRadius radius;
  final bool rtl;

  @override
  _RenderCard createRenderObject(BuildContext context) => _RenderCard(
    presence: presence,
    fades: fades,
    radius: radius,
    rtl: rtl,
    top: false,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderCard renderObject) {
    renderObject.presence = presence;
    renderObject.fades = fades;
    renderObject.radius = radius;
    renderObject.rtl = rtl;
  }
}

/// A page in a slide, painted from the top page's progress without
/// building or laying out: the top page offset by what is left of its
/// travel, the page below offset by its share and dimmed, both clipped to
/// the display's corners and the top one shadowed while they move; under a
/// cross-fade the top page fades in and the one below fades out.
class _RenderCard extends RenderProxyBox {
  _RenderCard({
    required this._presence,
    required this._fades,
    required this._radius,
    required this._rtl,
    required this.top,
  });

  final bool top;
  final _clip = LayerHandle<ClipRRectLayer>();
  final _offset = LayerHandle<OffsetLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  ValueListenable<double> _presence;
  ValueListenable<double> get presence => _presence;
  set presence(ValueListenable<double> value) {
    if (identical(value, _presence)) return;
    if (attached) _presence.removeListener(markNeedsPaint);
    _presence = value;
    if (attached) _presence.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  ValueListenable<bool> _fades;
  ValueListenable<bool> get fades => _fades;
  set fades(ValueListenable<bool> value) {
    if (identical(value, _fades)) return;
    if (attached) _fades.removeListener(markNeedsPaint);
    _fades = value;
    if (attached) _fades.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  BorderRadius _radius;
  BorderRadius get radius => _radius;
  set radius(BorderRadius value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _presence.addListener(markNeedsPaint);
    _fades.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _presence.removeListener(markNeedsPaint);
    _fades.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _offset.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  double get _shift {
    final p = _presence.value;
    final width = size.width;
    if (top) return (1 - p) * width * (_rtl ? -1 : 1);
    final aside = width - (NavigationTuning.underneathKeeps * width).round();
    return -aside * p.clamp(0.0, 1.0) * (_rtl ? -1 : 1);
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (!_fades.value) transform.translateByDouble(_shift, 0, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _fades.value ? Offset.zero : Offset(_shift, 0),
        position: position,
        hitTest: (result, local) => super.hitTest(result, position: local),
      );

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final p = _presence.value;
    if (_fades.value) {
      _clip.layer = null;
      _offset.layer = null;
      final shown = top ? p : 1 - p;
      _opacity.layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(shown.clamp(0.0, 1.0)),
        super.paint,
        oldLayer: _opacity.layer,
      );
      return;
    }
    _opacity.layer = null;
    final resting = top ? p >= 1 : p <= 0;
    if (resting) {
      _clip.layer = null;
      _offset.layer = null;
      super.paint(context, offset);
      return;
    }
    final box = Offset.zero & size;
    final card = _radius.toRRect(box);
    final at = offset.translate(_shift, 0);
    final layer = _offset.layer ??= OffsetLayer();
    layer.offset = at;
    context.pushLayer(layer, (context, offset) {
      if (top) {
        final shadow = Paint();
        shadow.color = const Color(0xFF000000).withValues(
          alpha: NavigationTuning.cardShadowOpacity,
        );
        shadow.maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          NavigationTuning.cardShadowRadius / 2,
        );
        context.canvas.drawRRect(
          card.shift(
            offset + const Offset(0, NavigationTuning.cardShadowOffset),
          ),
          shadow,
        );
      }
      _clip.layer = context.pushClipRRect(
        needsCompositing,
        offset,
        box,
        card,
        (context, offset) {
          context.paintChild(child, offset);
          if (!top) {
            final dim = Paint();
            dim.color = const Color(0xFF000000).withValues(
              alpha: NavigationTuning.underDimOpacity * p.clamp(0.0, 1.0),
            );
            context.canvas.drawRect(offset & size, dim);
          }
        },
        oldLayer: _clip.layer,
      );
    }, Offset.zero);
  }
}

class _Zoom extends StatefulWidget {
  const _Zoom({required this.route, required this.child});

  final GlassPageRoute<Object?> route;
  final Widget child;

  @override
  State<_Zoom> createState() => _ZoomState();
}

/// The page's zoom out of its source and back, and its drag to dismiss,
/// reported to the route's lifecycle.
class _ZoomState extends State<_Zoom> implements MotionDriver {
  final _motion = ZoomPageMotion();
  final _frames = ValueNotifier<int>(0);
  late final _input = _ZoomDrag(this);
  late final List<Interaction> _interactions = [_input];
  bool _opening = true;
  bool _leaving = false;
  bool _started = false;
  Size _size = Size.zero;
  double _displayRadius = NavigationTuning.fallbackCardRadius;
  Size _sourceSize = Size.zero;

  GlassPageRoute<Object?> get route => widget.route;

  GlassZoomLink get _link => route.source!;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    route._zoom = this;
    MotionClock.instance.addDriver(this);
    SchedulerBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (identical(route._zoom, this)) route._zoom = null;
    MotionClock.instance.removeDriver(this);
    _link.reveal();
    _frames.dispose();
    super.dispose();
  }

  Rect _page() => Offset.zero & _size;

  Rect _source() {
    final box = context.findRenderObject();
    final rect = box is RenderBox ? _link.rectIn(box) : null;
    if (rect != null && !rect.isEmpty) _sourceSize = rect.size;
    return rect ?? _motion.source;
  }

  void _start() {
    if (!mounted || _started) return;
    _started = true;
    final source = _source();
    // A page added without a push, as a navigator's first, stands in place.
    if (route.animation?.status == AnimationStatus.completed) {
      _opening = false;
      _motion.showInPlace(_now, source, _page());
      route._presence.snap(_now, 1);
      _link.hide();
      _frames.value++;
      return;
    }
    final clock = MotionClock.instance;
    final t = transitionOrigin(
      call: route._presented,
      firstFrame: clock.now,
      framePeriod: clock.framePeriod,
    );
    _motion.open(t, source, _page());
    _link.hide();
    MotionClock.instance.wake(this);
  }

  void leave() {
    _leaving = true;
    _opening = false;
    _motion.close(_now, _source());
    MotionClock.instance.wake(this);
  }

  @override
  bool get isActive => _started && !_motion.isSettled;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _motion.advance(time);
    if (!_motion.isDragging) {
      _motion.retargetEnds(
        time,
        source: _leaving ? _source() : null,
        page: _page(),
      );
    }
    if (_motion.isSettled) _motion.settle();
    route._presence.snap(time, _motion.reach);
    _frames.value++;
    if (_opening && _motion.isOpen) {
      _opening = false;
      route.didOpen();
    }
    if (_leaving && _motion.isClosed) {
      _leaving = false;
      _link.reveal();
      route.didLeave();
    }
  }

  bool get _canPop =>
      !_opening &&
      !_leaving &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted(double t, Offset from) {
    route.beginInteraction();
    _motion.dragStart(t, from);
    MotionClock.instance.wake(this);
  }

  void _dragged(double t, Offset position) {
    _motion.dragUpdate(t, position);
    MotionClock.instance.wake(this);
  }

  void _released(double t, Offset velocity) {
    final dismisses = _motion.dragEnd(t, velocity);
    route.endInteraction();
    if (dismisses) {
      route._lifted = t;
      route.dismiss(DismissTrigger.interaction);
      if (!_leaving) {
        // A PopScope vetoed the pop: the page returns.
        _motion.dragEnd(t, Offset.zero);
      }
    }
    MotionClock.instance.wake(this);
  }

  double _radius() => _motion.radius(_link.radius, _displayRadius);

  Matrix4 _pageScale() {
    final s = _motion.contentScale;
    return Matrix4.diagonal3Values(s, s, 1);
  }

  Matrix4 _lookScale() {
    final width = _sourceSize.width;
    final s = width <= 0 ? 1.0 : _motion.rect.width / width;
    return Matrix4.diagonal3Values(s, s, 1);
  }

  @override
  Widget build(BuildContext context) {
    _size = MediaQuery.sizeOf(context);
    _displayRadius =
        MediaQuery.maybeDisplayCornerRadiiOf(context)?.topLeft.x ??
        NavigationTuning.fallbackCardRadius;
    _input.rtl = Directionality.of(context) == TextDirection.rtl;
    final tuning = _motion.tuning;
    final look = _link.look;
    return InputRegion(
      interactions: _interactions,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: LiveFade(
              live: _frames,
              opacityOf: () =>
                  _started ? tuning.dimmingOpacity * _motion.dimming : 0,
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ZoomShadow(
                frames: _frames,
                state: this,
                color: Color.fromRGBO(0, 0, 0, tuning.shadowOpacity),
                sigma: tuning.shadowSigma,
                offset: tuning.shadowOffset,
              ),
            ),
          ),
          LivePlacement(
            live: _frames,
            rectOf: () => _started ? _motion.rect : _page(),
            child: LiveClipRRect(
              live: _frames,
              rrectOf: () => RRect.fromRectAndRadius(
                Offset.zero & (_started ? _motion.rect.size : _size),
                Radius.circular(_started ? _radius() : 0),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  LiveFade(
                    live: _frames,
                    opacityOf: () => _started ? _motion.fade : 0,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: _size.width,
                      maxWidth: _size.width,
                      minHeight: _size.height,
                      maxHeight: _size.height,
                      child: LiveTransform(
                        live: _frames,
                        alignment: Alignment.topLeft,
                        matrixOf: _pageScale,
                        child: RepaintBoundary(child: widget.child),
                      ),
                    ),
                  ),
                  if (look != null)
                    IgnorePointer(
                      child: LiveFade(
                        live: _frames,
                        opacityOf: () => _started ? 1 - _motion.fade : 1,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: _sourceSize.width,
                          maxWidth: _sourceSize.width,
                          minHeight: _sourceSize.height,
                          maxHeight: _sourceSize.height,
                          child: LiveTransform(
                            live: _frames,
                            alignment: Alignment.topLeft,
                            matrixOf: _lookScale,
                            child: look,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shadow the zooming card casts on the page underneath, faded with
/// the dimming.
class _ZoomShadow extends CustomPainter {
  _ZoomShadow({
    required Listenable frames,
    required this.state,
    required this.color,
    required this.sigma,
    required this.offset,
  }) : super(repaint: frames);

  final _ZoomState state;
  final Color color;
  final double sigma;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    if (!state._started) return;
    final motion = state._motion;
    final shown = motion.dimming;
    if (shown <= 0) return;
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * shown);
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        motion.rect.shift(Offset(0, offset)),
        Radius.circular(state._radius()),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ZoomShadow oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.sigma != sigma ||
      oldDelegate.offset != offset;
}

/// The drag that dismisses a zoomed page: a touch that moves down or
/// toward the trailing side past UIKit's slop takes the page, which
/// follows the finger and, on release, pops into its source or returns.
final class _ZoomDrag extends Interaction {
  _ZoomDrag(this._zoom) : super(role: InteractionRole.gesture);

  final _ZoomState _zoom;
  bool rtl = false;
  int? _pointer;
  Offset _start = Offset.zero;
  bool _dragging = false;
  VelocityTracker? _tracker;

  @override
  bool get dragged => _dragging;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && _pointer == null && _zoom._canPop;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _start = input.position;
        _dragging = false;
        _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
        _tracker!.addPosition(_duration(input.time), input.position);
      case PointerMoveInput() when input.pointer == _pointer:
        _tracker?.addPosition(_duration(input.time), input.position);
        final delta = input.position - _start;
        if (!_dragging) {
          if (delta.distance < _zoom._motion.tuning.dragSlop) break;
          if (!_zoom._motion.allowsDrag(delta, rtl: rtl)) {
            _pointer = null;
            return const InteractionUpdate(fails: true);
          }
          _dragging = true;
          _zoom._dragStarted(input.time, _start);
          _zoom._dragged(input.time, input.position);
          return const InteractionUpdate(recognizes: true);
        }
        _zoom._dragged(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        _tracker?.addPosition(_duration(input.time), input.position);
        final velocity = _tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
        _zoom._dragged(input.time, input.position);
        _zoom._released(input.time, velocity);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        if (_dragging) {
          _dragging = false;
          _zoom._released(input.time, Offset.zero);
        }
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }

  static Duration _duration(double seconds) =>
      Duration(microseconds: (seconds * 1e6).round());
}
