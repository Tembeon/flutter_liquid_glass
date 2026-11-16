part of 'liquid.dart';

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
