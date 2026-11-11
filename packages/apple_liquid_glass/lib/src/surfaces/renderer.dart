import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/group.dart';
import 'package:apple_liquid_glass/src/surfaces/scroll_edge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How every glass surface is drawn: real glass, fake glass, one flat look
/// or an app's own, chosen by the app or its user in a `GlassRendererScope`
/// and switchable at any time.
///
/// The package draws with `FlatGlassRenderer` (this library) and with
/// `LiquidGlassRenderer`, `FakeGlassRenderer` and `AdaptiveGlassRenderer`
/// (the `liquid` library). An app's own renderer extends this class with
/// public API only: [GlassSurfaceDetails] says what to draw; a frame's
/// [GlassShape.pathIn], or the shape's kinds ([GlassSuperellipse],
/// [GlassRoundedRect], [GlassOval]), and [GlassOutline.path] give the
/// body; [GlassFrame.drawnIn] and [GlassFrame.contentTransformIn] say
/// where it and its content go; [GlassFrame.glassnessAt] says how far a
/// lens has turned into glass.
///
/// A renderer builds a surface when the surface's widget rebuilds; frames
/// reach what it built through [GlassSurfaceDetails.frame], followed below
/// build, so a moving control rebuilds nothing per frame. Controls above
/// the surfaces keep their state across a switch, even mid-press.
@immutable
abstract class GlassRenderer {
  /// Creates a renderer.
  const GlassRenderer();

  /// Builds the surface [details] describes.
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details);

  /// Builds a group of surfaces that belong together; by default the
  /// surfaces are drawn on their own.
  Widget buildGroup(BuildContext context, GlassGroupDetails details) =>
      details.child;

  /// Builds the scroll edge effect [details] describes, laid out over the
  /// whole scroll view; by default the flat renderer's, where the content
  /// under it dissolves toward the background without a blur.
  Widget buildScrollEdge(
    BuildContext context,
    GlassScrollEdgeDetails details,
  ) => FlatScrollEdge(details: details);
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
    this.lens = const GlassLens(),
  });

  /// The glass family of the surface.
  final GlassRole role;

  /// What a [GlassRole.lens] body asks of its glass; other roles ignore
  /// it.
  final GlassLens lens;

  /// The glass it is made of.
  final Glass glass;

  /// Its frames; a renderer follows them below build rather than rebuilding
  /// per frame.
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

/// What a renderer needs to draw one scroll edge effect: the band where a
/// scroll view's content passes under a bar.
///
/// UIKit: `UIScrollEdgeEffect`. SwiftUI: `scrollEdgeEffectStyle`.
@immutable
final class GlassScrollEdgeDetails {
  /// Describes an edge effect.
  const GlassScrollEdgeDetails({
    required this.edge,
    required this.hard,
    required this.extent,
    required this.presence,
    required this.background,
  }) : assert(
         edge == AxisDirection.up || edge == AxisDirection.down,
         'Only the top and bottom edges have an effect.',
       );

  /// The edge: [AxisDirection.up] under a navigation bar,
  /// [AxisDirection.down] over a toolbar.
  final AxisDirection edge;

  /// Whether the effect is UIKit's hard one, the thin film of a navigation
  /// bar: a blur with raised saturation and brightness over the bar's own
  /// band, a uniform fade toward [background] and a hairline at the bar's
  /// edge. Otherwise it is the soft one: a light blur over a band that
  /// reaches 40 points past the bar, with a fade that dissolves along it.
  final bool hard;

  /// The distance from the scroll view's edge to the bar's far edge.
  final double extent;

  /// How present the effect is, 0 to 1; a renderer follows it below build.
  final ValueListenable<double> presence;

  /// What lies behind the content, resolved: the color the content fades
  /// toward under the bar.
  final Color background;

  @override
  bool operator ==(Object other) =>
      other is GlassScrollEdgeDetails &&
      other.edge == edge &&
      other.hard == hard &&
      other.extent == extent &&
      other.presence == presence &&
      other.background == background;

  @override
  int get hashCode => Object.hash(edge, hard, extent, presence, background);
}
