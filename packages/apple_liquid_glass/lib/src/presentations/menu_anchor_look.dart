part of 'menu_anchor.dart';

/// Paints the highlight of one card where the layer says it is now.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.layer,
    required this.card,
    required this.layout,
    required this.color,
  }) : super(repaint: Listenable.merge([layer._frames, layer._zones]));

  final _MenuLayerState layer;
  final int card;
  final MenuLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!layer.mounted) return;
    final rrect = layer._highlightOf(card, layout);
    if (rrect == null) return;
    final paint = Paint();
    paint.color = color;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.card != card ||
      oldDelegate.color != color;
}

// The menu's glass in [motion]'s frame. A tinted source's color stays on
// the glass, fused body included, until its look has faded.
GlassFrame _menuFrame(
  MenuMotion motion, {
  Color? sourceTint,
  double opacity = 1,
}) {
  final glow = motion.rootGlow;
  final tint = motion.drawsSource ? sourceTint : null;
  final tintAmount = tint == null ? 1.0 : motion.buttonLookOpacity;
  final (:shape, :outline) = motion.rootBody;
  if (outline != null) {
    return GlassFrame(
      outline: outline,
      tint: tint,
      tintAmount: tintAmount,
      glow: glow,
      opacity: opacity,
    );
  }
  return GlassFrame(
    shape: GlassShape.roundedRect(shape.tlRadiusX),
    rect: shape.outerRect,
    tint: tint,
    tintAmount: tintAmount,
    glow: glow,
    opacity: opacity,
  );
}

// A menu's GlassSurface.live over its whole box, whose frame is frameOf,
// read again on every step live publishes and on every rebuild.
class _LiveGlassSurface extends StatelessWidget {
  const _LiveGlassSurface({required this.live, required this.frameOf});

  final MotionSelection<Object?> live;

  final GlassFrame Function() frameOf;

  @override
  Widget build(BuildContext context) => GlassSurface.live(
    role: GlassRole.panel,
    frame: MotionSelection(() {
      live.value;
      return frameOf();
    }),
    child: const SizedBox.expand(),
  );
}
