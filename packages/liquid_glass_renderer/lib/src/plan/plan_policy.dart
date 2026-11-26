import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';

/// Decisions a person made once, from the measured trades of how copies are
/// drawn to the bounds of a frame's plan. Only tests replace them, through
/// `debugGlassPolicy`.
final class PlanPolicy {
  /// Creates a policy.
  const PlanPolicy({
    this.maxTargets = 24,
    this.maxShapes = geometryMaxShapesPerDraw,
    this.shaderFrost = true,
    this.maxCopyShare = 4,
    this.passPixels = 345714,
    this.deadWeight = 3 / 7,
    this.imagePasses = 7.438,
  });

  /// Shapes one shared atlas can hold.
  final int maxShapes;

  /// Targets a frame may issue before reads move to images. Counted as
  /// `GlassRead.targets` counts them: a frosted read is two or three.
  final int maxTargets;

  /// Whether glass blurs a copy it reads and mixes in its fill from the
  /// copy's levels, and fake glass and scroll edge bands frost their copies
  /// through a shader; without, a copy is blurred or filtered as the
  /// backdrop is and glass draws no fill. Glass picks its final shader by it.
  ///
  /// NEAR, for glass: one bilinear read of a level (`CopyLevelPasses`) is
  /// not Impeller's blur, and its peak sits up to half a cell of the level
  /// off, by where the screen's grid falls. Over the white bars of the host
  /// test at a device pixel ratio of 1, glass blurred all over by the sigma
  /// Impeller's blur delivers, with no fill (`debugGlassFill`), by 3 to 20
  /// px over copies of 1 to 4 device px a pixel, differs from the backdrop
  /// filter by 0.3 to 0.9 channel levels on average, 8 to 12 at the 99th
  /// percentile and at most 20 to 31. The backdrop draws no fill and one
  /// sigma for the whole face, so the paths differ by the recipe's ramp and
  /// fill besides. In return the copy takes at most two passes for its
  /// levels, whatever the blur and the fill.
  ///
  /// NEAR, for a frost of a copy: the shader weighs every pixel of the copy
  /// the frost reaches (latticeTaps in copy_frost.dart), so a point under
  /// the frost stays one point. Over the colored rows and white lines of
  /// apple_liquid_glass's scroll edge frost host test, the bands differ from
  /// the copy filtered as the backdrop by at most 11 channel levels at a
  /// device pixel ratio of 2.625 and 6 at 3. Fake glass with 6 px of frost
  /// over the test font's white blocks, the hardest edges a frost meets,
  /// differs by at most 20 at 2.625 (13 for the filtered copy); at 3 the
  /// frost is too wide for the shader and the copy stays filtered. In return
  /// the copy takes no blur passes and, once the frost spans 3.6 device px,
  /// holds a quarter of the pixels or fewer; a change of the color matrix
  /// alone, as a band or a glass fades in, keeps it.
  final bool shaderFrost;

  /// How many device pixels along each side one pixel of a copy stands for
  /// at most. A copy Impeller blurs takes at most 2 of them
  /// ([CopyNeed.blurred]); one glass blurs from its levels takes them from
  /// its least blur ([CopyNeed.levelled]), and one a frost shader frosts
  /// from the frost ([CopyNeed.edgeFrost]). 8 gave no clear GPU gain on the
  /// Pixel 6a.
  final int maxCopyShare;

  /// How many device pixels of copy one read is worth: glass beside a read
  /// joins it while the pixels the shared copy grows by, at its size, and
  /// [deadWeight] of the pixels of the shared quad nothing draws in stay
  /// below it.
  ///
  /// One read is a pass on the GPU and a filter on the raster thread. The
  /// number signs the in-launch pairs of 2026-11-05 on the Pixel 6a: 12
  /// buttons scattered over a page share a read, a group over the whole
  /// screen does not, a band under glass joins it and dead area in a menu
  /// at full resolution keeps it apart. It is a read's 0.121 GPU ms over
  /// the 0.35 a million copied pixels took there; the pairs disagree with
  /// any one price of a pixel, so this is a join rule, not a prediction.
  final double passPixels;

  /// How much a pixel of a shared quad that nothing draws in weighs against
  /// a copied one ([passPixels]): 0.15 GPU ms a million against 0.35 on the
  /// Pixel 6a.
  final double deadWeight;

  /// How many reads one image is worth: a read of [passPixels] or fewer
  /// holds still that many frames before it moves to an image, a larger one
  /// fewer ([imageRent]). An image took 0.9 GPU ms on the Pixel 6a, its
  /// target and its submit, a read 0.121.
  final double imagePasses;

  /// This policy with the given decisions replaced.
  PlanPolicy copyWith({
    int? maxTargets,
    int? maxShapes,
    bool? shaderFrost,
    int? maxCopyShare,
    double? passPixels,
    double? deadWeight,
    double? imagePasses,
  }) => PlanPolicy(
    maxTargets: maxTargets ?? this.maxTargets,
    maxShapes: maxShapes ?? this.maxShapes,
    shaderFrost: shaderFrost ?? this.shaderFrost,
    maxCopyShare: maxCopyShare ?? this.maxCopyShare,
    passPixels: passPixels ?? this.passPixels,
    deadWeight: deadWeight ?? this.deadWeight,
    imagePasses: imagePasses ?? this.imagePasses,
  );

  /// The device pixels a copy of [footprint] at [share] takes on a screen
  /// of [devicePixelRatio].
  static double copyPixels(
    Rect footprint,
    int share,
    double devicePixelRatio,
  ) =>
      footprint.width *
      footprint.height *
      devicePixelRatio *
      devicePixelRatio /
      (share * share);

  /// How many frames a read over [footprint] at [share] must hold still to
  /// pay for its image, which spares the frame its [targets]: [imagePasses]
  /// over the reads the frame spares, each of its copy's pixels counted as
  /// [passPixels] count them.
  int imageRent(
    Rect footprint,
    int share, {
    required double devicePixelRatio,
    int targets = 1,
  }) => math.max(
    1,
    (imagePasses /
            (targets +
                copyPixels(footprint, share, devicePixelRatio) / passPixels))
        .ceil(),
  );
}

/// The decisions glass keeps to outside release builds ([glassPolicy]), so a
/// test can draw the other side of a trade or reach a path an app reaches
/// only in a crowd, such as reads moved to images. A test sets it and puts
/// it back.
@visibleForTesting
PlanPolicy debugGlassPolicy = const PlanPolicy();

/// The decisions glass keeps to: the shipped policy in release builds,
/// [debugGlassPolicy] in others.
@internal
PlanPolicy get glassPolicy =>
    kReleaseMode ? const PlanPolicy() : debugGlassPolicy;
