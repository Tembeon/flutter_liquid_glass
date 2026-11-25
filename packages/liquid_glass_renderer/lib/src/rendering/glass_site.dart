import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:meta/meta.dart';

/// Where a frame's walk of the layers found a site ([PlanSite.walk]): what
/// the site reads of it.
@internal
abstract interface class SiteWalk {
  /// The transform from the coordinates [at] in the site's layer to the
  /// screen's logical pixels, or null where what lies above cannot say it.
  Matrix4? screenTransform(Offset at);

  /// Whether this frame's walk reached the site and found nothing changed
  /// around it.
  bool get rests;
}

/// A copy of what lies under one read of a frame, which the planner that
/// laid it out replays (`GlassPlanner.readsCopies`).
@internal
abstract interface class ReadCopy {
  /// The read this copy is for.
  GlassRead get read;

  /// Where the copy of [held], whose glass this copy holds, lies inside this
  /// one, or null where none of it does.
  CornerRead? cornerOf(GlassRead held);

  /// Adds the copy at [place]'s corner, inside [within]. What holds between
  /// scenes is kept in [held], the layers of the reader [builder]'s part of
  /// the scene belongs to.
  void addTo(
    ui.SceneBuilder builder,
    CornerPlace place,
    Rect within,
    HeldLayers held,
  );
}

/// The layer behind a site ([SiteFacts]), which the frame's plan decides for.
///
/// The view's planner (`GlassPlanner`) asks each site for its facts, decides
/// and tells each its fate, in paint order, before the scene is built.
@internal
abstract interface class PlanSite {
  /// Where this frame's walk of the layers found the site, if the planner
  /// walks them.
  SiteWalk? walk;

  /// What the site asks of this frame: a new value each frame, which the
  /// form keeps only where it differs from the last.
  SiteAsk ask(ViewPixels view);

  /// This frame's [fate], before any read of the frame is drawn. A site that
  /// draws no read of its own takes its place here.
  void beginFate(SiteFate fate);

  /// Draws [read], which this site leads, from [pixels].
  void show(GlassRead read, ReadPixels pixels);

  /// Adds the read this site leads to [out], inside a copy of what lies under
  /// glass over it.
  void addOutput(SceneOut out, ReadCopy outer);

  /// Whether this frame's read draws what the site's layer holds, so a replay
  /// leaves it out.
  bool get drawsOwnChildren;

  /// Whether a replay meets the site's output where it meets the site, rather
  /// than at a [GlassSlotLayer] further on.
  bool get outputsInPlace;

  /// The frame's plan is drawn: what held for the frame lets go.
  void endFrame();
}

/// Where the pixels of a read its lead draws lie this frame: one kind for
/// each [ReadSource] the plan gives a read.
@internal
sealed class ReadPixels {
  const ReadPixels();
}

/// A [SceneRead]: the read's copy, laid out over its layer in the frame's
/// scene, a layer that replays what lies under the lead when the scene is
/// added.
@internal
final class ScenePixels extends ReadPixels {
  /// Creates the pixels.
  const ScenePixels(this.corner);

  /// The copy's layer.
  final CornerRead corner;
}

/// An [ImageRead]: an image of the read's copy.
@internal
final class ImagePixels extends ReadPixels {
  /// Creates the pixels.
  const ImagePixels(this.copy);

  /// Where the read's copy lies in its image.
  final ImageCopy copy;
}

/// A [BackdropRead]: the backdrop itself.
@internal
final class BackdropPixels extends ReadPixels {
  /// Creates the pixels.
  const BackdropPixels(this.group);

  /// The key the read shares one copy of the backdrop under, if it does.
  final BackdropKey? group;
}

/// Glass that draws other sites of its read in its own filter.
@internal
abstract interface class ReadPainter {
  /// The filter that draws [read] over [corner].
  ui.ImageFilter readFilter(GlassRead read, CornerRead corner);

  /// Equal while [recordImage] draws the same for [read] over [copy].
  Object imageKey(GlassRead read, ImageCopy copy);

  /// Records [read] over [copy], in the coordinates [screenToCanvas] takes the
  /// screen's device pixels to.
  ui.Picture recordImage(
    GlassRead read,
    ImageCopy copy,
    Matrix4 screenToCanvas,
  );
}

/// The role of glass whose [painter] draws the read it is the first glass of.
///
/// Equal while the same painter's origin stays in place on the screen, so a
/// resting glass asks the same.
@internal
final class PainterRole extends GlassSiteRole {
  /// Creates the role of [painter] whose transform puts its origin at
  /// [originOnScreen] this frame.
  const PainterRole(this.painter, {required this.originOnScreen});

  /// What draws the read.
  final ReadPainter painter;

  /// Where the glass's transform puts its origin on the screen this frame, in
  /// logical pixels.
  final Offset originOnScreen;

  @override
  bool operator ==(Object other) =>
      other is PainterRole &&
      identical(other.painter, painter) &&
      other.originOnScreen == originOnScreen;

  @override
  int get hashCode => Object.hash(identityHashCode(painter), originOnScreen);
}

/// Where a site's fate shows in the layer tree: the walk does not go in, and
/// what is in here says nothing to the plan.
@internal
class GlassSlotLayer extends ContainerLayer {
  /// The site the slot shows.
  PlanSite? site;
}

/// A read as a layer of the scene.
///
/// While nothing under its footprint and nothing of its filter changed, it
/// stays out of the scene's rebuild: the engine layer it made holds.
@internal
final class ReadLayer extends ContainerLayer {
  ui.TransformEngineLayer? Function(ui.SceneBuilder builder)? _add;

  /// What the read keeps of the frame between the scenes it is added to.
  final held = HeldLayers();

  /// Shows what [add] adds, which returns the engine layer around it. Unless
  /// [changed], the engine layer of the last frame stands for it.
  void show(
    ui.TransformEngineLayer? Function(ui.SceneBuilder builder) add, {
    required bool changed,
  }) {
    _add = add;
    if (changed) markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    engineLayer = _add?.call(builder);
    held.built();
  }

  @override
  void dispose() {
    held.dispose();
    super.dispose();
  }
}

/// Whether glass reads copies of what lies under it in place of its
/// backdrop, in every build, where the frame's composer plans its view's
/// glass: without the composer, glass always reads its backdrop.
///
/// It starts true wherever Impeller renders, and false under `flutter test`,
/// so a test that checks what an app draws turns it on and puts it back.
/// Turning it off makes every glass and every
/// `LiquidGlassBackdropFilterLayer` read its backdrop as a backdrop filter
/// does, which is what a measurement of the copies compares them with; the
/// next frame plans again.
bool glassReadsCopies = FullGlass.shaderFilters && !runningUnderFlutterTest;
