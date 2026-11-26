import 'dart:ui';

import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';

/// Where a read's backdrop comes from.
sealed class ReadSource {
  const ReadSource();
}

/// The copy's layers added again inside the read's filter: one target.
final class SceneRead extends ReadSource {
  /// Creates the source.
  const SceneRead();
}

/// An image: none in the frame's scene. A new one costs its own submit.
final class ImageRead extends ReadSource {
  /// Creates the source.
  const ImageRead({required this.held});

  /// Whether the image of an earlier frame still holds.
  final bool held;
}

/// A backdrop filter: the frame goes offscreen, and splits once per read.
final class BackdropRead extends ReadSource {
  /// Creates the source.
  const BackdropRead();
}

/// One backdrop and all the glass drawn from it.
final class GlassRead {
  /// Opens a read at [lead].
  GlassRead(this.lead)
    : footprint = lead.ask.reads,
      quad = lead.ask.drawn,
      share = lead.ask.look.need.share,
      shapes = lead.isBand ? 0 : lead.ask.look.shapes {
    members.add(lead);
  }

  /// The shapes in its members' shared atlas.
  int shapes;

  /// The first member in paint order; the filter draws at its place.
  final SiteFacts lead;

  /// Everything drawn from this read, in paint order.
  final List<SiteFacts> members = [];

  /// The sites drawn from this read, its band left out, in paint order.
  Iterable<SiteFacts> get glassMembers =>
      lead.isBand ? members.skip(1) : members;

  /// The glass that draws the band leading this read, in the band's place.
  SiteFacts? get bandPainter =>
      lead.isBand && members.length > 1 ? members[1] : null;

  /// What this read holds of what lies under it.
  Rect footprint;

  /// What its filter draws over.
  Rect quad;

  /// The most device pixels along each side one pixel of its copy can stand
  /// for, for every member.
  int share;

  /// Where the backdrop comes from.
  ReadSource source = const SceneRead();

  /// What the layers under its lead leave it.
  ReadLimit limit = ReadLimit.none;

  /// Earlier reads whose glass lies in [footprint]: each is drawn again inside
  /// this read, so nesting doubles a read's targets.
  final List<GlassRead> holds = [];

  /// Zero over pictures alone, else one more than the highest read it holds.
  int level = 0;

  /// Where its copy's pixels lie, for a read that takes a copy (not a
  /// [BackdropRead]).
  late ReadLayout layout;

  /// Where its filter takes the geometry of the glass it draws from.
  GeometryKind geometryKind = const OwnAtlas();

  /// What the glass of [glassMembers] is, in paint order.
  List<ShapeCensus> get glass => [
    for (final member in glassMembers)
      if (member.ask.role is GlassSiteRole) member.ask.look.census,
  ];

  /// The least blur the shader of the glass it leads draws over all of the
  /// copy it shows, in logical pixels: 0 under a band.
  double get leadShaderBlur => lead.isBand ? 0 : lead.ask.look.need.leastBlur;

  /// Whether what it holds differs from the last frame.
  bool changed = false;

  /// The frames it holds still before it buys its image, where it reads the
  /// scene and may buy one.
  int? wait;

  /// Whether every glass drawn from it blurs what it shows by [flatBlur]
  /// or more, so its copy leaves out what that blur hides: a blur of what
  /// lies under it.
  bool get flat => members.every((site) => site.ask.look.blurSigma >= flatBlur);

  /// The least blur, a sigma in logical pixels, that hides what a flat copy
  /// leaves out: a little under the 2.2 of a bar of regular glass. Glass
  /// turned toward clear shows what lies under it, and reads it whole.
  static const double flatBlur = 2;

  /// The passes its copy takes for what it draws of the screen (see
  /// `PlanScenery.savedUnder`).
  int inside = 0;

  /// The group of backdrop reads that share one copy of the backdrop, taken at
  /// the first of them, or null for a read on its own.
  int? backdropGroup;

  /// The targets this read issues, each a pass of the frame: none for an
  /// image, else [sceneTargets].
  int get targets => source is ImageRead ? 0 : sceneTargets;

  /// The targets it issues drawn in the scene: its filter's layer, the layers
  /// its copy passes through where it lies ([CornerPlace.passes]), what its
  /// copy draws apart of the screen, and all of that again for each read it
  /// holds that is no image, where its copy holds some of it.
  int get sceneTargets =>
      source is BackdropRead ? 1 : _drawnIn(CornerPlace.inFrame(layout));

  int _drawnIn(CornerPlace place) {
    var total = 1 + inside + place.passes;
    for (final held in holds) {
      if (held.source is ImageRead) continue;
      if (CornerPlace.heldIn(held.layout, layout) case final inner?) {
        total += held._drawnIn(inner);
      }
    }
    return total;
  }
}

/// What a site does this frame.
sealed class SiteFate {
  const SiteFate();
}

/// Idle, off screen or outside its clips.
final class HiddenFate extends SiteFate {
  /// Creates the fate.
  const HiddenFate();
}

/// Draws [read]'s filter at its own place.
final class LeadFate extends SiteFate {
  /// Creates the fate.
  const LeadFate(this.read);

  /// The read it leads.
  final GlassRead read;
}

/// Another site's filter draws this glass.
final class FollowFate extends SiteFate {
  /// Creates the fate.
  const FollowFate(this.read);

  /// The read it follows.
  final GlassRead read;
}

/// One frame's plan. Every route the frame takes is a value in here.
final class GlassPlan {
  /// Creates a plan.
  GlassPlan(
    this.reads,
    this.fates, {
    required this.issuedTargets,
    required this.dueAt,
    required this.notes,
    required this.limits,
  });

  /// The frame's reads in paint order.
  final List<GlassRead> reads;

  /// Parallel to the sites of the frame the plan was compiled for.
  final List<SiteFate> fates;

  /// Targets the frame issues, nested replays counted.
  final int issuedTargets;

  /// The first frame a read that holds still can buy its image, if none
  /// changes before it.
  final int dueAt;

  /// Why the frame is what it is; empty unless asked for.
  final List<String> notes;

  /// What the layers under each site left its read, parallel to [fates]:
  /// null for a hidden site.
  final List<ReadLimit?> limits;
}
