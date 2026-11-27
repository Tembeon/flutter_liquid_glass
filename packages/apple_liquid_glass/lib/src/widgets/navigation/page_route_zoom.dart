part of 'page_route.dart';

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
  late final _pinch = _ZoomPinch(this);
  late final List<Interaction> _interactions = [_input, _pinch];
  bool _phone = true;
  late final _dim = motion.select((m) => m.coversBackdrop ? 0.0 : m.dimming);
  late final _cover = motion.select(
    (m) => m.coversBackdrop ? m.dimming : 0.0,
  );
  late final _shadow = motion.select(
    (m) => (m.rect, m.radius, m.coversBackdrop ? 0.0 : m.dimming),
  );
  late final _frame = motion.select((m) => (m.rect, m.radius));
  late final _fade = motion.select((m) => m.fade);
  late final _lookFade = motion.select((m) => m.lookOpacity);
  late final _placement = motion.select((m) => m.contentPlacement);
  late final _lookPlacement = motion.select((m) => m.lookPlacement);

  static Matrix4 _placed((double, Offset) placement) {
    final (scale, shift) = placement;
    final transform = Matrix4.translationValues(shift.dx, shift.dy, 0);
    transform.scaleByDouble(scale, scale, 1, 1);
    return transform;
  }

  bool _begun = false;
  VoidCallback? _cancelStart;

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
      motion.showInPlace(motion.clock.now);
      return;
    }
    _cancelStart = route._startAfterFirstFrame();
  }

  @override
  void dispose() {
    _cancelStart?.call();
    super.dispose();
  }

  void _resize() {
    motion.displayRadius = _cardRadius(context).topLeft.x;
    motion.resize(motion.clock.now, MediaQuery.sizeOf(context));
  }

  bool get _canPop =>
      motion.takesDrag &&
      route.isCurrent &&
      route.canDismiss(DismissTrigger.interaction);

  void _dragStarted(double t, Offset from) {
    route.beginInteraction();
    motion.dragStart(t, from);
  }

  void _edgePanStarted(
    double t,
    Offset position, {
    required Offset from,
    required bool rtl,
  }) {
    route.beginInteraction();
    motion.edgePanStart(t, position, from: from, rtl: rtl);
  }

  void _pinchStarted(double t, Offset focal) {
    route.beginInteraction();
    motion.pinchStart(t, focal);
  }

  void _released(double t) {
    final dismisses = motion.dragEnd(t);
    route.endInteraction();
    if (!dismisses) return;
    route._lifted = t;
    route.dismiss(DismissTrigger.interaction);
    // A PopScope vetoed the pop: the page returns.
    if (motion.isDragging) motion.stay(t);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tuning = motion.tuning;
    _phone = GlassEnvironment.of(context).formFactor == GlassFormFactor.phone;
    final source = route.source;
    final look = source == null ? null : _looks[source];
    final sourceSize = motion.source.size;
    return InputRegion(
      interactions: _interactions,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (motion.commits)
            IgnorePointer(
              child: MotionTransition(
                opacity: _cover,
                child: ColoredBox(
                  color: GlassDynamicColor.resolve(
                    GlassColors.systemBackground,
                    context,
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: MotionTransition(
              opacity: _dim,
              child: ColoredBox(
                color:
                    route.zoomDimmingColor ??
                    Color.fromRGBO(0, 0, 0, tuning.dimmingOpacity),
              ),
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
                      template: () =>
                          Transform(transform: _placed(_placement.value)),
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
                          template: () => Transform(
                            transform: _placed(_lookPlacement.value),
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
/// toward the trailing side past UIKit's slop takes the page, and so does
/// one on the leading edge that moves inward as the navigation's edge pan
/// does ([NavigationPopMotion.edgeHysteresis], no cones); the page follows
/// the finger and, on release, pops into its source or returns.
final class _ZoomDrag extends Interaction {
  _ZoomDrag(this._zoom) : super(role: InteractionRole.gesture);

  final _ZoomState _zoom;
  bool _touching = false;
  bool _rtl = false;
  Offset _start = Offset.zero;
  Offset _last = Offset.zero;
  double _downTime = 0;
  bool _fromEdge = false;
  bool _dragging = false;

  @override
  bool get dragged => _dragging;

  @override
  bool accepts(PointerDownInput down) => super.accepts(down) && _zoom._canPop;

  InteractionUpdate _fail() {
    _touching = false;
    return const InteractionUpdate(fails: true);
  }

  /// A pinch took the page: the finger no longer drags it, even once the
  /// pinch ends.
  void yieldToPinch() => _touching = false;

  bool get _mayBegin => _zoom.route.zoomDismissShouldBegin?.call() ?? true;

  @override
  InteractionUpdate handle(InteractionInput input) {
    final motion = _zoom.motion;
    switch (input) {
      case PointerDownInput() when accepts(input):
        final width = input.regionSize.width;
        _touching = true;
        _rtl = input.textDirection == TextDirection.rtl;
        _start = input.position;
        _last = input.position;
        _downTime = input.time;
        final x = (_rtl ? input.mirrored(width) : input).position.dx;
        _fromEdge =
            x <= NavigationPopMotion.edgeWidth(width, phone: _zoom._phone);
        _dragging = false;
      case PointerMoveInput() when _touching:
        final last = _last;
        _last = input.position;
        final delta = input.position - _start;
        if (!_dragging) {
          if (_fromEdge) {
            final travel = _rtl ? -delta.dx : delta.dx;
            if (travel <= NavigationPopMotion.edgeHysteresis) {
              final drift = delta.dy.abs();
              if (drift >
                  NavigationPopMotion.edgeDrift(input.time - _downTime)) {
                return _fail();
              }
              break;
            }
            if (!_mayBegin) return _fail();
            _dragging = true;
            _zoom._edgePanStarted(input.time, _start, from: last, rtl: _rtl);
          } else {
            final allowed = motion.allowsDrag(delta, rtl: _rtl);
            if (allowed == null) break;
            if (!allowed || !_mayBegin) return _fail();
            _dragging = true;
            _zoom._dragStarted(input.time, _start);
          }
          motion.dragUpdate(input.time, input.position);
          return const InteractionUpdate(verdict: .recognized);
        }
        motion.dragUpdate(input.time, input.position);
      case PointerUpInput() when _touching:
        _touching = false;
        if (!_dragging) return const InteractionUpdate(fails: true);
        _dragging = false;
        motion.dragUpdate(input.time, input.position);
        _zoom._released(input.time);
      case PointerCancelInput() when _touching:
        _touching = false;
        if (_dragging) {
          _dragging = false;
          _zoom._released(input.time);
        }
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The pinch that dismisses a zoomed page: two fingers on the page that
/// draw together take it once they stand closer than they began, and the
/// page shrinks with them about the point between them, as UIKit's pinch
/// does; on release it pops into its source or returns. It hears every
/// finger beside the page's other input, which hears only the first.
final class _ZoomPinch extends Interaction {
  _ZoomPinch(this._zoom) : super(role: InteractionRole.observer);

  final _ZoomState _zoom;
  final Map<int, Offset> _fingers = {};
  double _span = 0;
  Offset _focal = Offset.zero;
  bool pinching = false;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && (_fingers.isNotEmpty || _zoom._canPop);

  (double, Offset)? get _pair {
    if (_fingers.length < 2) return null;
    final [a, b, ...] = _fingers.values.toList();
    return ((a - b).distance, (a + b) / 2);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput(:final pointer, :final position):
        if (_fingers.length >= 2) break;
        _fingers[pointer] = position;
        if (_pair case (final span, final focal)) {
          _span = span;
          _focal = focal;
        }
      case PointerMoveInput(:final pointer, :final position)
          when _fingers.containsKey(pointer):
        _fingers[pointer] = position;
        final (span, focal) = _pair ?? (0.0, Offset.zero);
        if (_span <= 0 || span <= 0) break;
        final scale = span / _span;
        if (!pinching) {
          if (scale >= 1 ||
              _zoom._input.dragged ||
              !_zoom._canPop ||
              !(_zoom.route.zoomDismissShouldBegin?.call() ?? true)) {
            break;
          }
          pinching = true;
          _zoom._input.yieldToPinch();
          _zoom._pinchStarted(input.time, _focal);
        }
        _zoom.motion.pinchUpdate(input.time, scale, focal);
      case PointerUpInput(:final pointer) || PointerCancelInput(:final pointer)
          when _fingers.containsKey(pointer):
        _fingers.remove(pointer);
        _span = 0;
        if (pinching) {
          pinching = false;
          _zoom._released(input.time);
        }
      default:
    }
    return InteractionUpdate.none;
  }
}
