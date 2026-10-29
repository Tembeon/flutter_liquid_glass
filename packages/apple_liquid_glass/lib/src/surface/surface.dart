import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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
    LiquidShape this._shape = GlassFrame.capsule,
    this.role = GlassRole.control,
    this.glass = const Glass.regular(),
    super.key,
  }) : frame = null;

  /// Creates a body that follows [frame]: moved, scaled, lifted, tinted and
  /// lit frame by frame without a rebuild.
  const GlassSurface.live({
    required ValueListenable<GlassFrame> this.frame,
    required this.child,
    this.role = GlassRole.control,
    this.glass = const Glass.regular(),
    super.key,
  }) : _shape = null;

  final LiquidShape? _shape;

  /// The frames of a live surface, or null for a still one.
  final ValueListenable<GlassFrame>? frame;

  /// The glass family of the surface.
  final GlassRole role;

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
        widget.frame ?? _StillFrame(GlassFrame(shape: widget._shape!));
    final body = GlassTheme.rendererOf(context).buildSurface(
      context,
      GlassSurfaceDetails(
        role: widget.role,
        glass: _resolved(context),
        frame: frame,
        child: KeyedSubtree(key: _child, child: widget.child),
      ),
    );
    if (!GlassTraits.of(context).showBorders) return body;
    final label = GlassDynamicColor.resolve(
      GlassTheme.of(context).colorScheme?.label ?? GlassColors.label,
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
final class _StillFrame implements ValueListenable<GlassFrame> {
  const _StillFrame(this.value);

  @override
  final GlassFrame value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  bool operator ==(Object other) =>
      other is _StillFrame && other.value == value;

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
    canvas.drawPath(
      now.shape.getOuterPath(now.drawnIn(size).deflate(0.5)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Border oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.color != color;
}
