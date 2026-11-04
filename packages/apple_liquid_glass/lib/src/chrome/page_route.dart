import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:apple_liquid_glass/src/motion/navigation_motion.dart';
import 'package:apple_liquid_glass/src/motion/zoom_page_motion.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

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
/// last speeds, on a spring of response 0.3 and damping 0.85. With Prefer
/// Cross-Fade Transitions, which iOS turns on with Reduce Motion, a push or
/// pop without a finger cross-fades over 0.5 s instead.
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
/// With a [source], the page zooms out of it instead, as a UIKit page with
/// `preferredTransition = .zoom` does: it grows from the source's frame to the
/// screen, center and width on a critically damped spring of response 0.317 and
/// height on one of response 0.406, damping 0.925, while the source's look
/// crossfades into it and the page underneath dims 15 percent under the growing
/// card's shadow; popped, it shrinks back into the source on UIKit's zoom-out
/// spring (iPhone 16 Pro recordings, replayed). A drag down or toward the
/// trailing side shrinks the page under the finger after 13.5 points, and a
/// release past 132.5 points or at 1050 points a second pops it into the
/// source; short of that it returns. The source hides while the page shows.
/// Without an attached source the page slides.
class GlassPageRoute<T> extends PresentationPageRoute<T> {
  /// Creates a page [builder] builds, zooming out of [source] when given.
  GlassPageRoute({required this.builder, this.source, super.settings});

  /// Builds the page.
  final WidgetBuilder builder;

  /// The source the page zooms out of and back into, shown by a
  /// [GlassZoomSource], or null for a page that slides in.
  final MotionSource? source;

  // Fixed when the page is installed, so the page and the route agree on
  // its transition for its whole life.
  late final bool _zooms = source?.geometry != null;

  late final PageMotion _motion = _zooms
      ? ZoomPageMotion(page: _navigatorRect())
      : PageSlideMotion();
  late final MotionSelection<double> _progress = _motion.select(
    (m) => m.progress,
  );
  late final MotionSelection<bool> _fades = _motion.select((m) => m.fades);

  @override
  Presentation<T, Presented> get presentation => _presentation;

  late final Presentation<T, Presented> _presentation =
      Presentation<T, PageMotion>(
        motion: (_) => _motion,
        builder: (context, motion) => motion is ZoomPageMotion
            ? _Zoom(
                route: this,
                motion: motion,
                child: Builder(builder: builder),
              )
            : _Slide(
                route: this,
                motion: motion as PageSlideMotion,
                child: Builder(builder: builder),
              ),
        source: _zooms ? source : null,
        dismiss: DismissPolicy.modal,
      );

  // The motion time of the call that presented the page.
  double _presented = 0;

  // The page above this one, whose progress moves and dims this one.
  final _cover = ValueNotifier<GlassPageRoute<Object?>?>(null);
  GlassPageRoute<Object?>? _below;

  // The page's end of its navigator's shared bar.
  late final GlassPageBarLink _bar;
  bool _presenting = false;

  // The time of the finger's lift that committed a swipe's pop.
  double? _lifted;

  Rect _navigatorRect() {
    final box = navigator?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void install() {
    _bar = GlassBarHost.of(navigator!).attach(this, presence: _progress);
    super.install();
  }

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
            : _Card(
                presence: _progress,
                fades: _fades,
                top: false,
                child: child,
              );

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
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) =>
      GlassBarSlot(link: _bar, child: super.buildContent(context));

  @override
  bool leave(DismissTrigger trigger) {
    final lifted = trigger == DismissTrigger.interaction ? _lifted : null;
    _lifted = null;
    _bar.host.leaving(_bar, time: lifted ?? MotionClock.instance.now);
    return super.leave(trigger);
  }

  // The time a push's transition counts from, read in the first frame
  // after it.
  double _origin() {
    final clock = MotionClock.instance;
    return transitionOrigin(
      call: _presented,
      firstFrame: clock.now,
      framePeriod: clock.framePeriod,
    );
  }
}

class _Slide extends StatefulWidget {
  const _Slide({
    required this.route,
    required this.motion,
    required this.child,
  });

  final GlassPageRoute<Object?> route;
  final PageSlideMotion motion;
  final Widget child;

  @override
  State<_Slide> createState() => _SlideState();
}

/// The page's slide, its cross-fade for Prefer Cross-Fade Transitions and its
/// interactive pop.
class _SlideState extends State<_Slide> {
  // The page moves under the card of a page pushed above it and back; the
  // key carries its state along.
  final _page = GlobalKey(debugLabel: 'GlassPageRoute.page');
  late final _input = _SwipePop(this);
  late final List<Interaction> _interactions = [_input];

  GlassPageRoute<Object?> get route => widget.route;
  PageSlideMotion get motion => widget.motion;

  @override
  void initState() {
    super.initState();
    motion.onReturned = route.endInteraction;
    // A page added without a push, as a navigator's first, stands in place.
    if (route.animation?.status == AnimationStatus.completed) {
      motion.showInPlace(MotionClock.instance.now);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && motion.isShown) motion.start(route._origin());
    });
  }

  @override
  void dispose() {
    motion.onReturned = null;
    super.dispose();
  }

  bool get _canPop =>
      motion.takesSwipe &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted(double t) {
    motion.hold(t);
    route.beginInteraction();
  }

  void _released(double t, {required bool pops, required double velocity}) {
    motion.release(t, pops: pops, velocity: velocity);
    if (!pops && motion.isShown) return;
    if (motion.isShown) {
      route._lifted = t;
      route.dismiss(DismissTrigger.interaction);
    }
    route.endInteraction();
    if (motion.isShown) {
      // A PopScope vetoed the pop: the page returns.
      motion.stay(t);
      route.beginInteraction();
    }
  }

  // The page builds in the build phase, never under a LayoutBuilder: what
  // it declares to the shared bar is in place before any layout.
  @override
  Widget build(BuildContext context) {
    motion.width = MediaQuery.sizeOf(context).width;
    motion.crossFades = GlassTraits.of(context).prefersCrossFade;
    _input.rtl = Directionality.of(context) == TextDirection.rtl;
    return InputRegion(
      interactions: _interactions,
      child: _Card(
        presence: route._progress,
        fades: route._fades,
        top: true,
        child: ValueListenableBuilder(
          valueListenable: route._cover,
          builder: (context, cover, child) => cover == null
              ? child!
              : _Card(
                  presence: cover._progress,
                  fades: cover._fades,
                  top: false,
                  child: child,
                ),
          child: RepaintBoundary(key: _page, child: widget.child),
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
          _slide._dragStarted(input.time);
          predictor.begin(input.time);
          return const InteractionUpdate(recognizes: true);
        }
        final progress = travel / _width;
        _slide.motion.drag(input.time, progress);
        predictor.update(input.time, progress);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        final predictor = _predictor;
        final progress = (_along(input.position) - _along(_start)) / _width;
        predictor.update(input.time, progress, ending: true);
        _slide._released(
          input.time,
          pops: predictor.shouldPop(progress),
          velocity: predictor.settleVelocity,
        );
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        if (_dragging) {
          _dragging = false;
          _slide._released(input.time, pops: false, velocity: 0);
        }
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// A page in a slide, as a card with the display's corners: the page on
/// top when [top], moved by its progress, with a light shadow while it
/// moves; otherwise the page below, moved aside and dimmed with the page
/// above's progress. Under a cross-fade either fades instead.
class _Card extends SingleChildRenderObjectWidget {
  const _Card({
    required this.presence,
    required this.fades,
    required this.top,
    super.child,
  });

  final ValueListenable<double> presence;
  final ValueListenable<bool> fades;
  final bool top;

  @override
  _RenderCard createRenderObject(BuildContext context) => _RenderCard(
    presence: presence,
    fades: fades,
    radius: _cardRadius(context),
    rtl: Directionality.of(context) == TextDirection.rtl,
    top: top,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderCard renderObject) {
    renderObject.presence = presence;
    renderObject.fades = fades;
    renderObject.radius = _cardRadius(context);
    renderObject.rtl = Directionality.of(context) == TextDirection.rtl;
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
  const _Zoom({required this.route, required this.motion, required this.child});

  final GlassPageRoute<Object?> route;
  final ZoomPageMotion motion;
  final Widget child;

  @override
  State<_Zoom> createState() => _ZoomState();
}

/// The page's zoom out of its source and back, and its drag to dismiss.
class _ZoomState extends State<_Zoom> {
  late final _input = _ZoomDrag(this);
  late final List<Interaction> _interactions = [_input];
  late final _dim = motion.select((m) => m.tuning.dimmingOpacity * m.dimming);
  late final _shadow = motion.select((m) => (m.rect, m.radius, m.dimming));
  late final _frame = motion.select((m) => (m.rect, m.radius));
  late final _fade = motion.select((m) => m.fade);
  late final _lookFade = motion.select((m) => 1 - m.fade);
  late final _scale = motion.select((m) => m.contentScale);
  late final _lookScale = motion.select((m) => m.lookScale);
  bool _begun = false;

  GlassPageRoute<Object?> get route => widget.route;
  ZoomPageMotion get motion => widget.motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resize();
    if (_begun) return;
    _begun = true;
    // A page added without a push, as a navigator's first, stands in place.
    if (route.animation?.status == AnimationStatus.completed) {
      motion.showInPlace(MotionClock.instance.now);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && motion.isShown) motion.start(route._origin());
    });
  }

  void _resize() {
    motion.displayRadius = _cardRadius(context).topLeft.x;
    motion.resize(MotionClock.instance.now, MediaQuery.sizeOf(context));
  }

  bool get _canPop =>
      motion.takesDrag &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted(double t, Offset from) {
    route.beginInteraction();
    motion.dragStart(t, from);
  }

  void _released(double t, Offset velocity) {
    final dismisses = motion.dragEnd(t, velocity);
    route.endInteraction();
    if (!dismisses) return;
    route._lifted = t;
    route.dismiss(DismissTrigger.interaction);
    // A PopScope vetoed the pop: the page returns.
    if (motion.isDragging) motion.stay(t);
  }

  @override
  Widget build(BuildContext context) {
    _input.rtl = Directionality.of(context) == TextDirection.rtl;
    final size = MediaQuery.sizeOf(context);
    final tuning = motion.tuning;
    final source = route.source;
    final look = source == null ? null : _looks[source];
    final sourceSize = motion.source.size;
    return InputRegion(
      interactions: _interactions,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: MotionTransition(
              opacity: _dim,
              child: const ColoredBox(color: Color(0xFF000000)),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ZoomShadow(
                _shadow,
                color: Color.fromRGBO(0, 0, 0, tuning.shadowOpacity),
                sigma: tuning.shadowSigma,
                offset: tuning.shadowOffset,
              ),
            ),
          ),
          MotionDriven(
            template: () {
              final (rect, radius) = _frame.value;
              return CustomSingleChildLayout(
                delegate: _Place(rect),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(radius)),
                ),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MotionTransition(
                  opacity: _fade,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: size.width,
                    maxWidth: size.width,
                    minHeight: size.height,
                    maxHeight: size.height,
                    child: MotionDriven(
                      template: () => Transform.scale(
                        alignment: Alignment.topLeft,
                        scale: _scale.value,
                      ),
                      child: RepaintBoundary(child: widget.child),
                    ),
                  ),
                ),
                if (look != null)
                  IgnorePointer(
                    child: MotionTransition(
                      opacity: _lookFade,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: sourceSize.width,
                        maxWidth: sourceSize.width,
                        minHeight: sourceSize.height,
                        maxHeight: sourceSize.height,
                        child: MotionDriven(
                          template: () => Transform.scale(
                            alignment: Alignment.topLeft,
                            scale: _lookScale.value,
                          ),
                          child: look,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays its child out at [rect].
class _Place extends SingleChildLayoutDelegate {
  _Place(this.rect);

  final Rect rect;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(rect.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => rect.topLeft;

  @override
  bool shouldRelayout(_Place oldDelegate) => oldDelegate.rect != rect;
}

/// The shadow the zooming card casts on the page underneath, faded with
/// the dimming.
class _ZoomShadow extends CustomPainter {
  _ZoomShadow(
    this.shadow, {
    required this.color,
    required this.sigma,
    required this.offset,
  }) : super(repaint: shadow);

  final ValueListenable<(Rect, double, double)> shadow;
  final Color color;
  final double sigma;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final (rect, radius, shown) = shadow.value;
    if (shown <= 0) return;
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * shown);
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(0, offset)),
        Radius.circular(radius),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ZoomShadow oldDelegate) =>
      !identical(oldDelegate.shadow, shadow) ||
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
  late VelocityTracker _tracker;

  @override
  bool get dragged => _dragging;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && _pointer == null && _zoom._canPop;

  @override
  InteractionUpdate handle(InteractionInput input) {
    final motion = _zoom.motion;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _start = input.position;
        _dragging = false;
        _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
        _tracker.addPosition(_duration(input.time), input.position);
      case PointerMoveInput() when input.pointer == _pointer:
        _tracker.addPosition(_duration(input.time), input.position);
        final delta = input.position - _start;
        if (!_dragging) {
          if (delta.distance < motion.tuning.dragSlop) break;
          if (!motion.allowsDrag(delta, rtl: rtl)) {
            _pointer = null;
            return const InteractionUpdate(fails: true);
          }
          _dragging = true;
          _zoom._dragStarted(input.time, _start);
          motion.dragUpdate(input.time, input.position);
          return const InteractionUpdate(recognizes: true);
        }
        motion.dragUpdate(input.time, input.position);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        _tracker.addPosition(_duration(input.time), input.position);
        final velocity = _tracker.getVelocity().pixelsPerSecond;
        motion.dragUpdate(input.time, input.position);
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

// What each zoom source shows, which its page draws while the source's look
// crossfades into the page.
final _looks = Expando<Widget>('GlassZoomSource.look');

/// The widget a [GlassPageRoute] with a [source] grows out of when it is
/// pushed and lands in when it is popped.
///
/// UIKit: the `sourceViewProvider` of `.zoom`. SwiftUI:
/// `matchedTransitionSource(id:in:)`.
///
/// The source hides from the frame its page is pushed in until the page
/// has gone, as UIKit hides a zoom transition's source view, and stays
/// tappable meanwhile; the zoom draws [child] while it crossfades into the
/// page.
class GlassZoomSource extends StatelessWidget {
  /// Marks [child] as the [source] of a page.
  const GlassZoomSource({
    required this.source,
    required this.child,
    this.borderRadius = 0,
    super.key,
  });

  /// The source the page is pushed with.
  final MotionSource source;

  /// The radius of the source's corners, which the zoom's corners turn
  /// from into the display's.
  final double borderRadius;

  /// The source.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    _looks[source] = child;
    return MotionSourceBox(
      source: source,
      radius: BorderRadius.all(Radius.circular(borderRadius)),
      child: child,
    );
  }
}
