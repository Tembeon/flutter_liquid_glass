part of 'liquid.dart';

/// A surface's wish to write its glow in the frame's resolve phase.
final class _GlowRequest {
  _RenderGlowResolve? _host;
  bool pending = false;

  void ask() {
    pending = true;
    _host?.scheduleResolve();
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// Writes its surface's glow from its own laid out box in the frame's
/// resolve phase.
class _GlowResolve extends SingleChildRenderObjectWidget {
  const _GlowResolve({
    required this.request,
    required this.onResolve,
    required super.child,
  });

  final _GlowRequest request;
  final ValueSetter<RenderBox> onResolve;

  @override
  _RenderGlowResolve createRenderObject(BuildContext context) =>
      _RenderGlowResolve(request, onResolve);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlowResolve renderObject,
  ) {
    renderObject.onResolve = onResolve;
  }
}

class _RenderGlowResolve extends RenderProxyBox with MotionResolveHost {
  _RenderGlowResolve(this.request, this.onResolve);

  final _GlowRequest request;
  ValueSetter<RenderBox> onResolve;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    request._host = this;
  }

  @override
  void detach() {
    if (identical(request._host, this)) request._host = null;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (request.pending) scheduleResolve();
  }

  @override
  void resolve() {
    if (!request.pending || !hasSize) return;
    request.pending = false;
    onResolve(this);
  }
}

/// Casts [shadows] by the outline of [frame]'s body, outside the body only
/// so none shows through the glass, faded with the body.
class _OutlineShadow extends SingleChildRenderObjectWidget {
  const _OutlineShadow({
    required this.frame,
    required this.shadows,
    required super.child,
  });

  final ValueListenable<GlassFrame> frame;
  final List<BoxShadow> shadows;

  @override
  _RenderOutlineShadow createRenderObject(BuildContext context) =>
      _RenderOutlineShadow(frame, shadows);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOutlineShadow renderObject,
  ) {
    renderObject.frame = frame;
    renderObject.shadows = shadows;
  }
}

class _RenderOutlineShadow extends RenderProxyBox with ListenableFollower {
  _RenderOutlineShadow(this._frame, this._shadows);

  ValueListenable<GlassFrame> _frame;
  ValueListenable<GlassFrame> get frame => _frame;
  set frame(ValueListenable<GlassFrame> value) {
    if (value == _frame) return;
    refollow(() => _frame = value);
    markNeedsPaint();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [(_frame, _changed)];

  List<BoxShadow> _shadows;
  List<BoxShadow> get shadows => _shadows;
  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) return;
    _shadows = value;
    markNeedsPaint();
  }

  GlassOutline? _outline;
  double _opacity = 1;
  Path? _outside;

  void _changed() {
    final frame = _frame.value;
    if (frame.outline == _outline && frame.opacity == _opacity) return;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _frame.value;
    final outline = frame.outline;
    _opacity = frame.opacity;
    if (outline != _outline) {
      _outline = outline;
      _outside = null;
    }
    if (outline != null && _shadows.isNotEmpty && _opacity > 0) {
      final shadows = LiquidGlassShadow.resolve(_shadows, outline.bounds.size);
      final reach = shadows.fold<double>(
        0,
        (r, s) => math.max(
          r,
          s.offset.distance + s.spreadRadius + 3 * s.blurSigma,
        ),
      );
      final outside = _outside ??= pathOutside(
        outline.path,
        outline.bounds.inflate(reach),
      );
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.clipPath(outside);
      for (final shadow in shadows) {
        final paint = Paint();
        paint.color = shadow.color.withValues(
          alpha: shadow.color.a * _opacity.clamp(0.0, 1.0),
        );
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.blurSigma);
        canvas.drawPath(outline.path.shift(shadow.offset), paint);
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }
}
