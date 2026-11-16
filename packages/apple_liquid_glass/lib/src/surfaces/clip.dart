import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// Clips its child to a glass body, so content laid over the glass ends
/// where the renderer draws the glass's edge.
class GlassClip extends StatelessWidget {
  /// Clips [child] to a body of [shape] that fills the child's box.
  const GlassClip({required GlassShape this.shape, super.key, this.child})
    : frame = null;

  /// Clips [child] to the body each of [frame]'s frames draws in the
  /// child's box: its outline, or its shape where it is drawn. The clip
  /// follows the frames without a rebuild.
  const GlassClip.live({
    required MotionSelection<GlassFrame> this.frame,
    super.key,
    this.child,
  }) : shape = null;

  /// The body of a clip that fills the box, or null for [frame]'s.
  final GlassShape? shape;

  /// The frames whose bodies clip, or null for [shape]'s.
  final MotionSelection<GlassFrame>? frame;

  /// The clipped widget.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return switch (shape) {
      GlassSuperellipse(:final radius) => ClipRSuperellipse(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        child: child,
      ),
      GlassRoundedRect(:final radius) => ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        child: child,
      ),
      GlassOval() => ClipOval(child: child),
      null => ClipPath(clipper: _FrameClip(frame!), child: child),
    };
  }
}

class _FrameClip extends CustomClipper<Path> {
  _FrameClip(this.frame) : super(reclip: frame);

  final ValueListenable<GlassFrame> frame;

  @override
  Path getClip(Size size) {
    final value = frame.value;
    if (value.outline case final outline?) return outline.path;
    return value.shape.pathIn(value.drawnIn(size));
  }

  @override
  bool shouldReclip(_FrameClip oldClipper) => oldClipper.frame != frame;
}
