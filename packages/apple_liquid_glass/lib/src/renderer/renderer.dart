import 'package:apple_liquid_glass/src/renderer/adaptive.dart';
import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:apple_liquid_glass/src/renderer/liquid.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/group.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How every glass surface is drawn: real glass, fake glass, one flat look
/// or an app's own, chosen by the app or its user in `GlassTheme` and
/// switchable at any time.
///
/// A renderer builds a surface when the surface's widget rebuilds, never per
/// frame: frames reach what it built only through
/// [GlassSurfaceDetails.frame], followed below build, so nothing rebuilds
/// while a control moves. Controls above the surfaces keep their state
/// across a switch, even mid-press.
@immutable
abstract class GlassRenderer {
  /// Creates a renderer.
  const GlassRenderer();

  /// Draws every surface as liquid glass on `LiquidGlassLayer`s; on a device
  /// without full glass the layers draw fake glass instead.
  const factory GlassRenderer.liquid() = LiquidGlassRenderer;

  /// Draws every surface as fake glass: blurred and lit, without
  /// refraction.
  const factory GlassRenderer.fake() = LiquidGlassRenderer.fake;

  /// Draws every surface flat: a fill per role, a soft shadow under
  /// floating ones, no backdrop reads.
  const factory GlassRenderer.flat() = FlatGlassRenderer;

  /// Draws with [capable] on a device whose GPU draws full glass well, and
  /// with [fallback] on any other, as `LiquidGlass.precache` finds it once
  /// per run; [capable] draws until it has.
  const factory GlassRenderer.adaptive({
    required GlassRenderer capable,
    required GlassRenderer fallback,
  }) = AdaptiveGlassRenderer;

  /// Builds the surface [details] describes.
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details);

  /// Builds a group of surfaces that belong together; by default the
  /// surfaces are drawn on their own.
  Widget buildGroup(BuildContext context, GlassGroupDetails details) =>
      details.child;
}

/// What a renderer needs to build one surface.
@immutable
final class GlassSurfaceDetails {
  /// Describes a surface.
  const GlassSurfaceDetails({
    required this.role,
    required this.glass,
    required this.frame,
    required this.child,
  });

  /// The glass family of the surface.
  final GlassRole role;

  /// The glass it is made of.
  final Glass glass;

  /// Its frames; a renderer follows them below build and never rebuilds for
  /// a new one.
  final ValueListenable<GlassFrame> frame;

  /// The content drawn over the body, clipped to it.
  final Widget child;
}

/// What a renderer needs to build a group of surfaces.
@immutable
final class GlassGroupDetails {
  /// Describes a group.
  const GlassGroupDetails({required this.merge, required this.child});

  /// How the members fuse.
  final GlassMerge merge;

  /// The subtree holding the members.
  final Widget child;
}
