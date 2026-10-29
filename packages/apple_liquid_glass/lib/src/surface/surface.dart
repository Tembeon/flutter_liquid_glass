import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
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

  /// Creates a body that follows [frame]: moved, scaled and lit frame by
  /// frame without a rebuild.
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

  @override
  Widget build(BuildContext context) =>
      GlassTheme.rendererOf(context).buildSurface(
        context,
        GlassSurfaceDetails(
          role: widget.role,
          glass: widget.glass,
          frame: widget.frame ?? _StillFrame(GlassFrame(shape: widget._shape!)),
          child: KeyedSubtree(key: _child, child: widget.child),
        ),
      );
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
