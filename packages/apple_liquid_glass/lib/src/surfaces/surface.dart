import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:apple_liquid_glass/src/surfaces/glass.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:apple_liquid_glass/src/surfaces/shape.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// A glass body behind [child], drawn by the ambient `GlassRenderer`.
///
/// UIKit: `UIVisualEffectView` with a `UIGlassEffect`. SwiftUI:
/// `.glassEffect(_:in:)`.
///
/// The child is drawn over the body and clipped to it. The same surface is
/// real glass, fake glass or flat depending on the renderer in
/// `GlassTheme`, so an app's own panels follow its user's choice too; the
/// child keeps its state when the renderer changes.
class GlassSurface extends StatefulWidget {
  /// Creates a still body whose outline is `shape`, a capsule by default.
  const GlassSurface({
    required this.child,
    GlassShape this._shape = GlassShape.capsule,
    this.role = GlassRole.control,
    this.glass = const Glass.regular(),
    @internal this.part,
    super.key,
  }) : frame = null;

  /// Creates a body that follows [frame]: moved, scaled, lifted, tinted and
  /// lit frame by frame without a rebuild. Pass a selection of the motion
  /// that moves the body (`Motion.select`): the renderer hears it in the
  /// frame's publish phase, before build, or in its resolve phase after a
  /// layout commanded the motion, so the glass shows each step in the frame
  /// the motion takes it.
  const GlassSurface.live({
    required MotionSelection<GlassFrame> this.frame,
    required this.child,
    this.role = GlassRole.control,
    this.glass = const Glass.regular(),
    @internal this.part,
    super.key,
  }) : _shape = null;

  // A bar writes its capsules' frames in the frame's resolve phase, after
  // its items are laid out, from what no selection can read.
  /// Creates a body that follows frames its owner writes in the frame's
  /// resolve phase.
  @internal
  const GlassSurface.written({
    required ValueListenable<GlassFrame> this.frame,
    required this.child,
    super.key,
  }) : _shape = null,
       role = GlassRole.control,
       glass = const Glass.regular(),
       part = null;

  final GlassShape? _shape;

  /// The frames of a live surface, or null for a still one.
  final ValueListenable<GlassFrame>? frame;

  /// The glass family of the surface.
  final GlassRole role;

  /// The package's own surface of [role] this is, for its renderers.
  @internal
  final GlassPart? part;

  /// The glass it is made of.
  final Glass glass;

  /// The content drawn over the body.
  final Widget child;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  final _child = GlobalKey(debugLabel: 'GlassSurface.child');

  Glass _resolved(BuildContext context) {
    final glass = widget.glass;
    final tint = glass.tint;
    if (tint is! GlassDynamicColor) return glass;
    final resolved = tint.resolveFrom(context);
    return glass.isClear
        ? Glass.clear(tint: resolved)
        : Glass.regular(tint: resolved);
  }

  @override
  Widget build(BuildContext context) {
    final frame =
        widget.frame ?? StillGlassFrame(GlassFrame(shape: widget._shape!));
    final body = GlassTheme.rendererOf(context).buildSurface(
      context,
      GlassSurfaceDetails(
        role: widget.role,
        part: widget.part,
        glass: _resolved(context),
        frame: frame,
        child: KeyedSubtree(key: _child, child: widget.child),
      ),
    );
    if (!GlassTraits.of(context).showBorders) return body;
    final label = GlassDynamicColor.resolve(
      GlassTheme.of(context).labelColor,
      context,
    );
    return CustomPaint(
      foregroundPainter: _Border(
        frame: frame,
        color: label.withValues(alpha: label.a * 0.35),
      ),
      child: body,
    );
  }
}

@immutable
/// A frame that never changes.
@internal
final class StillGlassFrame implements ValueListenable<GlassFrame> {
  /// Holds [value].
  const StillGlassFrame(this.value);

  @override
  final GlassFrame value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  bool operator ==(Object other) =>
      other is StillGlassFrame && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The hairline Show Borders draws around a glass body, where the frame
/// draws it, faded with it.
class _Border extends CustomPainter {
  _Border({required this.frame, required this.color}) : super(repaint: frame);

  final ValueListenable<GlassFrame> frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final now = frame.value;
    if (now.opacity <= 0) return;
    final paint = Paint();
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    paint.color = color.withValues(
      alpha: color.a * now.opacity.clamp(0.0, 1.0),
    );
    final outline = now.outline;
    if (outline != null) {
      canvas.drawPath(outline.path, paint);
      return;
    }
    canvas.drawPath(now.shape.pathIn(now.drawnIn(size).deflate(0.5)), paint);
  }

  @override
  bool shouldRepaint(_Border oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.color != color;
}

/// A menu's [GlassSurface.live] over its whole box, whose frame is
/// [frameOf], read again on every step [live] publishes and on every
/// rebuild.
@internal
class LiveGlassSurface extends StatelessWidget {
  /// Creates the surface.
  const LiveGlassSurface({
    required this.live,
    required this.frameOf,
    super.key,
  });

  /// Publishes when [frameOf] has a new frame.
  final MotionSelection<Object?> live;

  /// The surface's frame now.
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
