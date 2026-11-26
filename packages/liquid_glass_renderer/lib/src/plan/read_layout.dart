import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/rects.dart';
import 'package:meta/meta.dart';

// The largest sigma, in the copy's own pixels, the shader frosts by. Its taps
// lie about a sigma apart, so a wider frost shows hard edges as faint copies:
// they show at 5 copy pixels in the host test and not at 3.4.
const double _shaderFrostTexels = 3.5;

// A copy blurred by at least this many of its own pixels is drawn as the blur
// leaves it at a fraction of the screen's pixels: sampled back up, it adds a
// tent of its pixel's width to a blur many times wider.
const double _blurredCopySigma = 2.5;

// The share a copy of glass with a fitted blur takes at least, on a screen
// of at least this many device pixels per point ([CopyNeed.levelled]).
const int _coarseCopyShare = 2;
const double _coarseCopyMinRatio = 2.5;

// How many device pixels along each side one pixel of a copy holds that the
// shader frosts for Impeller's blur by [sigma] device pixels, or null when
// the frost is too wide for it: the largest up to [maxShare] whose pixels the
// frost spans by at most 3.5, then halved while the frost still spans
// [minTexels] of its pixels.
int? _shaderFrostShare(
  double sigma, {
  required double minTexels,
  required int maxShare,
}) {
  final delivered = sigma * ImpellerBlur.deliveredFraction;
  var share = 1;
  while (share < maxShare && delivered / share > _shaderFrostTexels) {
    share *= 2;
  }
  if (delivered <= 0 || delivered / share > _shaderFrostTexels) return null;
  while (share < maxShare && delivered / (share * 2) >= minTexels) {
    share *= 2;
  }
  return share;
}

// The sigma, in device pixels, the shaders' taps frost a copy by for
// Impeller's blur by [sigma] device pixels, where each pixel of the copy
// holds [share] device pixels along each side.
//
// The taps frost by what the copy leaves: a pixel of a smaller copy averages
// k x k device px (a box), every bilinear tap adds a tent of a copy pixel,
// and Gaussians add in variance.
double _frostResidual(double sigma, {required int share}) {
  final delivered = sigma * ImpellerBlur.deliveredFraction;
  final carried = share * share * (bilinearTapVariance + copyPixelBox(share));
  return sqrt(max(delivered * delivered - carried, 0));
}

/// What glass blurs the copy it reads by, in logical pixels: the least and
/// the most sigma of its blur inside the glass, and the sigma of the wide
/// blur it mixes in, its fill (0 for none). The read lays out the levels
/// they take beside its copy ([LevelStrip]).
@immutable
final class CopyLevels {
  /// Levels for a blur from [least] to [most] and a fill of [fill].
  const CopyLevels({this.least = 0, this.most = 0, this.fill = 0});

  /// The least sigma the glass blurs by inside, past its edge's fringe.
  final double least;

  /// The most sigma the glass blurs by.
  final double most;

  /// The sigma of the fill, 0 for none.
  final double fill;

  /// Whether the glass blurs what it shows.
  bool get blurs => most > 0;

  /// Whether the glass mixes a fill in.
  bool get fills => fill > 0;

  /// These levels for glass that adds [frost] to its blur ([blurAdding]);
  /// its fill stays.
  CopyLevels adding(double frost) => frost <= 0
      ? this
      : CopyLevels(
          least: blurAdding(least, frost),
          most: blurAdding(most, frost),
          fill: fill,
        );

  @override
  bool operator ==(Object other) =>
      other is CopyLevels &&
      other.least == least &&
      other.most == most &&
      other.fill == fill;

  @override
  int get hashCode => Object.hash(least, most, fill);
}

/// [sigma] with [frost] added, as Gaussians add: what glass blurring by
/// [sigma] blurs by where its copy leaves [frost] to it.
double blurAdding(double sigma, double frost) =>
    sqrt(sigma * sigma + frost * frost);

/// What a site needs of a copy of its backdrop: how many device pixels along
/// each side one pixel of the copy may stand for, and whether a scroll edge's
/// shader frosts it ([FrostNeed]), glass blurs it from levels it carries
/// ([LevelNeed]), or it is read as it is ([PlainNeed]).
///
/// A site states the most a copy may be reduced for it; the read joining
/// sites takes the least of their shares, and its [ReadLayout] decides the
/// copy's grid.
@immutable
sealed class CopyNeed {
  const CopyNeed({required this.share});

  /// The need of a copy Impeller blurs by at least [sigma] logical pixels
  /// along each axis: halved while the blur spans 2.5 of its pixels, to at
  /// most [maxShare] and 2.
  ///
  /// NEAR: a copy drawn at half size differs from the full one by at most 10
  /// channel levels on the Pixel 6a (5 in the scroll scene, 10 under the
  /// crowd of buttons), and by 4 in the host test of white text under 8 px
  /// of frost at dpr 1. In return the Pixel's rails spend 7 % less on a dot
  /// or the Liquid tab and 32 % less under the crowd. A quarter size differs
  /// by 15 on the Liquid tab and saves no more.
  factory CopyNeed.blurred(
    double sigma, {
    required double devicePixelRatio,
    required int maxShare,
  }) {
    var share = 1;
    while (share * 2 <= min(maxShare, 2) &&
        sigma * devicePixelRatio / (share * 2) >= _blurredCopySigma) {
      share *= 2;
    }
    return PlainNeed(share: share);
  }

  /// The need of glass that blurs an unblurred copy from [levels]: halved
  /// while its least blur spans two pixels of the copy, to at most
  /// [maxShare]. Glass whose blur follows iOS 27's [fittedBlur] reads at
  /// least half the screen's pixels on a screen of 2.5 or more.
  ///
  /// A blur narrower than two of the copy's pixels mixes the copy itself
  /// in, whose pixels show as the page moves under the glass: against a
  /// Gaussian under sub-pixel shifts, 29 to 73 levels off below it and 2 to
  /// 10 above, glass of 64 to 90 points on a replica of the levels.
  ///
  /// iOS captures what lies under glass at half the screen's pixels, which a
  /// screen of 2.5 device pixels per point or more shows that soft. Against
  /// native glass 63 points high over hard cells, glass with a fitted blur
  /// lies 2.0 levels off so and 3.4 at the screen's pixels (dark glass 1.1
  /// and 4.0).
  factory CopyNeed.levelled(
    CopyLevels levels, {
    required double devicePixelRatio,
    required int maxShare,
    bool fittedBlur = false,
  }) {
    final atLeast = fittedBlur && devicePixelRatio >= _coarseCopyMinRatio
        ? _coarseCopyShare
        : 1;
    var share = min(atLeast, maxShare);
    while (share * 2 <= maxShare &&
        levels.least * devicePixelRatio / (share * 2) >= 2) {
      share *= 2;
    }
    return LevelNeed(levels, share: share);
  }

  /// The need of a scroll edge or fake glass whose frost shader frosts an
  /// unblurred copy by [sigma] logical pixels, to at most [maxShare], or null
  /// where the frost is too wide for it. A copy whose pixels the frost spans
  /// by less than 1.5 is not halved again: drawn smaller, its edges show
  /// through the frost.
  static FrostNeed? edgeFrost(
    double sigma, {
    required double devicePixelRatio,
    required int maxShare,
  }) => switch (_shaderFrostShare(
    sigma * devicePixelRatio,
    minTexels: 1.5,
    maxShare: maxShare,
  )) {
    final share? => FrostNeed(sigma, share: share),
    null => null,
  };

  /// Device pixels along each side one pixel of the copy may stand for.
  final int share;

  /// The frost a scroll edge's shader draws over the copy, in logical
  /// pixels; none but for a [FrostNeed].
  double get shaderFrost => 0;

  /// Whether a frost shader draws over the copy ([shaderFrost]), where
  /// otherwise the copy holds the filtered backdrop.
  bool get frostedByShader => false;

  /// What glass blurs the copy by; none but for a [LevelNeed].
  CopyLevels? get levels => null;

  /// The least blur, in logical pixels, a shader draws over all of the
  /// copy it shows: a scroll edge's frost, or the least blur of glass.
  double get leastBlur;

  /// The logical pixels a shader frosting or blurring the copy reads around a
  /// region on a screen of [devicePixelRatio]. A blur reads three sigmas
  /// out; the fill reads the copy's edge for what lies past it.
  ///
  /// A copy drawn at the screen's pixels in place of the ones asked reaches
  /// less: its taps lie at most a sigma wider and its pixel is smaller.
  double reachAt(double devicePixelRatio);
}

/// A copy read as it is, or blurred by Impeller.
final class PlainNeed extends CopyNeed {
  /// A copy of [share] device pixels a pixel.
  const PlainNeed({super.share = 1});

  @override
  double get leastBlur => 0;

  @override
  double reachAt(double devicePixelRatio) => 0;

  @override
  bool operator ==(Object other) => other is PlainNeed && other.share == share;

  @override
  int get hashCode => Object.hash(PlainNeed, share);
}

/// A copy glass blurs from [levels] it carries beside it.
final class LevelNeed extends CopyNeed {
  /// A copy blurred from [levels], of [share] device pixels a pixel.
  const LevelNeed(this.levels, {super.share = 1});

  @override
  final CopyLevels levels;

  @override
  double get leastBlur => levels.least;

  @override
  double reachAt(double devicePixelRatio) {
    final most = levels.most;
    return most > 0 ? 3 * most + share / devicePixelRatio : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is LevelNeed && other.share == share && other.levels == levels;

  @override
  int get hashCode => Object.hash(LevelNeed, share, levels);
}

/// A copy a scroll edge's or fake glass's shader frosts by [shaderFrost].
final class FrostNeed extends CopyNeed {
  /// A copy frosted by [shaderFrost] logical pixels, of [share] device
  /// pixels a pixel.
  const FrostNeed(this.shaderFrost, {super.share = 1})
    : assert(shaderFrost > 0, 'A frost need frosts.');

  @override
  final double shaderFrost;

  @override
  bool get frostedByShader => true;

  @override
  double get leastBlur => shaderFrost;

  @override
  double reachAt(double devicePixelRatio) =>
      (frostTapReach *
              _frostResidual(shaderFrost * devicePixelRatio, share: share) +
          share) /
      devicePixelRatio;

  /// Whether a shader's written-out taps stay smooth drawing a band with this
  /// need for glass with [glass]'s over one copy, on a screen of
  /// [devicePixelRatio].
  bool bandFits(CopyNeed glass, {required double devicePixelRatio}) {
    final share = min(this.share, glass.share);
    final residual = _frostResidual(
      shaderFrost * devicePixelRatio,
      share: share,
    );
    return residual / share <= frostEightMost;
  }

  @override
  bool operator ==(Object other) =>
      other is FrostNeed &&
      other.share == share &&
      other.shaderFrost == shaderFrost;

  @override
  int get hashCode => Object.hash(FrostNeed, share, shaderFrost);
}

/// The frost, in logical pixels, a read's copy holds, frosted once at its own
/// pixels so the scroll edge or fake glass over it takes one read per
/// fragment in place of its taps, or 0 where the shader frosts it.
///
/// Only a copy that every reader frosts by at least [shaderFrost] holds it, at
/// fewer pixels than the screen's: at the screen's pixels, or holding glass,
/// which lies at them, the frost costs more than the taps it saves. Glass
/// blurs from the levels beside its copy, which stays unfrosted, as does the
/// copy of a band that glass draws.
///
/// Where the frost's program is not loaded yet the copy is drawn unfrosted
/// and the shader frosts it.
///
/// NEAR: the frost drawn into the copy weighs every pixel of the copy it
/// reaches (_latticeTaps in copy_frost.dart), where the shader's own taps
/// are sparse.
double _bakedFrost({
  required int share,
  required bool nestsGlass,
  required double shaderFrost,
}) => share < 2 || nestsGlass ? 0 : shaderFrost;

// The pairs along an axis a frost over every pixel of a copy reads, fewest
// first.
const _latticePairs = [3, 4, 6, 8];

// n pairs of a copy's pixels hold a Gaussian up to this many times n wide.
const double _sigmaPerPair = 1.3 / 3;

/// How many pairs of a copy's pixels along each axis a frost by a sigma of
/// [inCopyPixels] of them reads where it weighs every pixel it reaches: 3, 4,
/// 6 or 8, or null for one wider than eight pairs hold.
///
/// A bilinear read of the copy adds [bilinearTapVariance] to the frost.
int? latticePairsOf(double inCopyPixels) {
  final sigma = sqrt(inCopyPixels * inCopyPixels + bilinearTapVariance);
  for (final pairs in _latticePairs) {
    if (sigma <= pairs * _sigmaPerPair) return pairs;
  }
  return null;
}

/// How a frost is drawn over every pixel of a copy it reaches, at the copy's
/// own pixels (see [frostLatticeOf]).
enum FrostLattice {
  /// One pass of nine reads: three pairs of pixels along each axis.
  square(passes: 1),

  /// One pass along x and one along y over what it left.
  axes(passes: 2);

  const FrostLattice({required this.passes});

  /// The filtered layers that draw it, each a pass of the frame.
  final int passes;
}

/// How a frost by a sigma of [inCopyPixels] of a copy's pixels is drawn over
/// every pixel of the copy it reaches, or null where it is not: no frost, or
/// one too wide for eight pairs of the copy's pixels ([latticePairsOf]), which
/// sparse taps draw.
///
/// The one rule both the plan, which counts the passes a copy's frost
/// takes, and the filters that draw it follow.
FrostLattice? frostLatticeOf(double inCopyPixels) {
  if (inCopyPixels <= 0) return null;
  return switch (latticePairsOf(inCopyPixels)) {
    null => null,
    3 => FrostLattice.square,
    _ => FrostLattice.axes,
  };
}

/// The variance, in a copy's pixels squared, of the box a pixel of a copy
/// averages where it holds [share] device pixels along each side: none for
/// one.
double copyPixelBox(int share) => share > 1 ? copyPixelBoxVariance : 0;

/// The variance, in a copy's pixels squared, a bilinear read of blur level
/// [k] of a copy at [share] holds: the box a copy pixel averages
/// ([copyPixelBox]), the tent the level averages its cells by and the tent
/// of the read, each as wide as two of its cells, 4^k / 3 together; level 0
/// is the copy itself. A level past [coarseSourceLevel] averages that level,
/// so it carries [levelSourceTent] too.
double levelVariance(int k, {required int share}) {
  final box = copyPixelBox(share);
  if (k == 0) return box + bilinearTapVariance;
  final source = k > coarseSourceLevel ? levelSourceTent : 0.0;
  return box + source + (1 << 2 * k) / levelSpanScale;
}

/// The deepest blur level whose read blurs by at most [variance], in a
/// copy's pixels squared: the inverse of [levelVariance], 0 below level 1,
/// as copy_levels.glsl takes it for every fragment.
int levelBelow(double variance, {required int share}) {
  final span = levelSpanScale * (variance - copyPixelBox(share));
  final level = span >= levelSpanKnee
      ? span - levelSourceSpan
      : min<double>(span, levelSpanKnee - levelSourceSpan - 1);
  return level < 4 ? 0 : (log(level) / ln2 / 2).floor();
}

const int _sourceCell = 1 << coarseSourceLevel;

/// Where the levels of a copy lie: one row of cells under the copy in its
/// texture, which copy_levels.frag writes and the final shader reads
/// (copy_levels.glsl).
///
/// Blur level k averages 2^k x 2^k of the copy's pixels by a tent twice that
/// wide, and the fill level a cell of its own stride the same way, each on a
/// grid anchored at the screen: a copy that moves with its glass averages
/// the same pixels into a cell, and its blur stays put. Cells counted from
/// the copy's corner part the page another way at each step of the copy,
/// and the glass flickers in patches as it moves. The levels up to
/// [coarseSourceLevel] average the copy, the coarser ones and the fill level
/// average that one, so the levels take two passes at most. A level's cells
/// over the copy number one more along each side than the copy spans, as
/// the screen's grid falls anywhere.
///
/// The row holds the fill level first, then the blur levels from the finest
/// ([first]) to the coarsest ([last]), each inside a ring of [levelRing]
/// texels that repeats its edge.
@immutable
final class LevelStrip {
  /// The strip of a copy of [copy] pixels, its top left at [grid] on the
  /// screen's grid of its pixels, each pixel [share] device pixels along each
  /// side on a screen of [devicePixelRatio], for glass blurring it from
  /// [levels].
  factory LevelStrip(
    CopyLevels levels, {
    required double devicePixelRatio,
    required int share,
    required Size copy,
    required Offset grid,
  }) {
    final (:first, :last, :blurs, :fillStride) = _choose(
      levels,
      pixels: devicePixelRatio / share,
      share: share,
    );
    final cell = 1 << last;
    final width = (copy.width / cell).ceil() * cell;
    return LevelStrip._(
      first: first,
      last: last,
      blurs: blurs,
      fillStride: fillStride,
      width: width,
      height: (copy.height / cell).ceil() * cell,
      fillCells: fillStride > 0 ? (width / fillStride).ceil() + 1 : 0,
      copy: copy,
      grid: grid,
    );
  }

  const LevelStrip._({
    required this.first,
    required this.last,
    required this.blurs,
    required this.fillStride,
    required this.width,
    required this.height,
    required this.fillCells,
    required this.copy,
    required this.grid,
  });

  // The levels a copy at [share] carries for glass blurring it from
  // [levels] at [pixels] copy pixels a logical pixel: the blur levels from
  // first to last, which take in the level the others average, whether the
  // glass reads them, and the fill level's stride, 0 for none.
  //
  // The glass reads the two levels whose blur brackets its own, so the least
  // blur picks the finest and the most the coarsest; level 0 is the copy
  // itself.
  static ({int first, int last, bool blurs, int fillStride}) _choose(
    CopyLevels levels, {
    required double pixels,
    required int share,
  }) {
    final box = copyPixelBox(share);
    final least = levels.least * pixels;
    final most = levels.most * pixels;
    final fill = levels.fill * pixels;
    final blurs = most > 0;
    final finest = blurs
        ? min(max(1, levelBelow(least * least, share: share)), levelMostDeep)
        : coarseSourceLevel;
    final coarsest = blurs
        ? min(
            max(finest, levelBelow(most * most, share: share) + 1),
            levelMostDeep,
          )
        : coarseSourceLevel;
    final across = sqrt(
      max(levelSpanScale * (fill * fill - box - levelSourceTent), 0),
    );
    return (
      first: min(finest, coarseSourceLevel),
      last: max(coarsest, coarseSourceLevel),
      blurs: blurs,
      fillStride: fill > 0
          ? _sourceCell *
                (across / _sourceCell).round().clamp(
                  1,
                  levelMostPairs - 1,
                )
          : 0,
    );
  }

  /// The finest blur level the strip holds.
  final int first;

  /// The coarsest blur level the strip holds.
  final int last;

  /// Whether the glass reads the blur levels, where level 2 may lie in the
  /// strip only for the fill level to average.
  final bool blurs;

  /// The fill level's stride in copy pixels, 0 for none: whole cells of
  /// [coarseSourceLevel], which it averages.
  final int fillStride;

  /// The copy's width rounded up to whole cells of [last].
  final int width;

  /// The copy's height rounded up to whole cells of [last].
  final int height;

  /// The fill level's cells across, its ring aside.
  final int fillCells;

  /// The copy's size in its pixels.
  final Size copy;

  /// Where the copy's top left lies on the screen's grid of its pixels.
  final Offset grid;

  /// This strip of a copy whose top left lies at [grid] on the screen's grid.
  LevelStrip withGrid(Offset grid) => grid == this.grid
      ? this
      : LevelStrip._(
          first: first,
          last: last,
          blurs: blurs,
          fillStride: fillStride,
          width: width,
          height: height,
          fillCells: fillCells,
          copy: copy,
          grid: grid,
        );

  /// The columns the fill level takes, its ring included.
  int get fillColumns => fillStride > 0 ? fillCells + 2 * levelRing : 0;

  /// The column, from the strip's left, the cells of blur level [k] start
  /// at, past its ring: the fill level's columns, then each finer level's
  /// cells inside their ring.
  int columnOf(int k) =>
      fillColumns +
      (width >> (first - 1)) -
      (width >> (k - 1)) +
      (1 + 2 * levelRing) * (k - first) +
      levelRing;

  /// The row, from the copy's top, the strip starts at: right under the
  /// copy.
  double get top => copy.height;

  /// The row, from the copy's top, every level's cells start at, past their
  /// ring.
  double get cellsTop => top + levelRing;

  /// Where the fill level's cells start, from the copy's top left, past
  /// their ring: the fill level comes first in the row.
  Offset get fillCellsAt => Offset(levelRing.toDouble(), cellsTop);

  /// The cells of blur level [k] along each side, their ring aside.
  Size cellsOf(int k) =>
      Size(((width >> k) + 1).toDouble(), ((height >> k) + 1).toDouble());

  /// The strip's width in pixels.
  int get across => columnOf(last + 1) - levelRing;

  /// The strip's height in pixels: the finest level's cells and its ring.
  int get down => (height >> first) + 1 + 2 * levelRing;

  /// The rows a layer keeps under the copy for the strip.
  int get rows => down + ImpellerLayers.spareRows;

  /// The size of what the copy and its strip take from the copy's top left.
  Size get size => Size(
    max(copy.width, across.toDouble()),
    copy.height + rows,
  );

  /// The passes that draw the levels: one for the levels up to
  /// [coarseSourceLevel], and one for the coarser ones and the fill level.
  int get passes => last > coarseSourceLevel || fillStride > 0 ? 2 : 1;

  @override
  bool operator ==(Object other) =>
      other is LevelStrip &&
      other.first == first &&
      other.last == last &&
      other.blurs == blurs &&
      other.fillStride == fillStride &&
      other.width == width &&
      other.height == height &&
      other.copy == copy &&
      other.grid == grid;

  @override
  int get hashCode =>
      Object.hash(first, last, blurs, fillStride, width, height, copy, grid);
}

/// Where the pixels of one read's copy lie: on which grid, at which boxes and
/// with which frost, in the frame and inside the copies that hold it.
@immutable
final class ReadLayout {
  const ReadLayout._({
    required this.view,
    required this.share,
    required this.reads,
    required this.copyBox,
    required this.layer,
    required this.clip,
    required this.bakedFrost,
    required this.frostLeftOut,
    required this.filter,
    required this.levels,
    required this.imageGrid,
    required this.imageFilterBlurs,
    this.room,
    this.imageBox,
  });

  /// The layout of a read asking [reads] of a copy of [askedShare] device
  /// pixels a pixel at [devicePixelRatio], led under [clip], on [screen]
  /// (logical pixels).
  ///
  /// A copy that holds glass drawn at the screen's pixels lands on the
  /// screen's own pixels ([atScreen]). [shaderFrost] is the frost, in logical
  /// pixels, of the scroll edge or fake glass that leads the read, where no
  /// glass reads its copy. An image of a copy that Impeller blurs
  /// by [imageBlur] logical pixels, null for none, lies on the grid its blur
  /// samples ([imageGrid]).
  factory ReadLayout.resolve({
    required double devicePixelRatio,
    required int askedShare,
    required bool atScreen,
    required Rect reads,
    required Rect screen,
    required Rect? clip,
    required bool nestsGlass,
    required double shaderFrost,
    required double frostLeftOut,
    required ImageReadLook? filter,
    required double? imageBlur,
    CopyLevels? levels,
  }) {
    assert(
      askedShare == 1 || askedShare == 2 || askedShare == 4 || askedShare == 8,
      'A copy holds one, two, four or eight device pixels along each side.',
    );
    assert(
      frostLeftOut <= 0 || (levels?.blurs ?? true),
      'Glass is left a frost only where it blurs as wide.',
    );
    final drawn = levels?.adding(frostLeftOut);
    final view = ViewPixels(devicePixelRatio);
    final share = atScreen ? 1 : askedShare;
    final imageSigma = (imageBlur ?? 0) * devicePixelRatio / share;
    final copyBox = view
        .cover(reads, share: share)
        .intersect(view.cover(screen));
    final cut = clip?.intersect(screen);
    final layer = switch (cut) {
      null => copyBox.outTo(share),
      // A smaller copy lies in its layer's corner, which a layer grown past
      // the clip leaves outside it, and Impeller draws none of the copy there
      // (host test): the layer starts inside the clip. NEAR: glass reads what
      // lies past the clip mirrored at it, as where a clip leaves no room to
      // grow.
      _ when share > 1 => view.cover(
        view.logical(copyBox).intersect(cut),
        share: share,
      ),
      _ => ImpellerLayers.layerIn(copyBox, cut, view),
    };
    return ReadLayout._(
      view: view,
      share: share,
      reads: reads.intersect(screen),
      copyBox: copyBox,
      layer: drawn == null || share > 1
          ? layer
          : _withLevelRows(layer, copyBox, cut, drawn, view),
      clip: cut,
      bakedFrost: _bakedFrost(
        share: share,
        nestsGlass: nestsGlass,
        shaderFrost: shaderFrost,
      ),
      frostLeftOut: frostLeftOut,
      filter: filter,
      levels: drawn,
      imageGrid: share * ImpellerBlur.share(imageSigma),
      imageFilterBlurs:
          imageBlur != null && ImpellerBlur.imageFilterMatches(imageSigma),
    );
  }

  // A copy at the screen's pixels fills its layer, which grows down by the
  // rows its levels lie in ([LevelStrip]), past the screen or the clip where
  // it must: they are a small part of the layer. Where the layer with them
  // would not keep its corner ([ImpellerLayers.keepsCorner]), it is cut to
  // the clip first. NEAR: as where a clip leaves no room to grow, its glass
  // reads the copy mirrored at the clip.
  static DeviceBox _withLevelRows(
    DeviceBox layer,
    DeviceBox copyBox,
    Rect? cut,
    CopyLevels levels,
    ViewPixels view,
  ) {
    DeviceBox grown(DeviceBox from) {
      final copy = Size(
        copyBox.right - from.left,
        copyBox.bottom - from.top,
      );
      final rows = LevelStrip(
        levels,
        devicePixelRatio: view.devicePixelRatio,
        share: 1,
        copy: copy,
        grid: from.topLeft,
      ).rows;
      return from.downTo(copyBox.bottom + rows);
    }

    final whole = grown(layer);
    if (cut == null ||
        ImpellerLayers.keepsCorner(
          whole.rect,
          cut.scaled(view.devicePixelRatio),
        )) {
      return whole;
    }
    return grown(view.cover(view.logical(copyBox).intersect(cut)));
  }

  /// The screen's pixels the copy is laid out on.
  final ViewPixels view;

  /// How many device pixels along each side one pixel of the copy holds, on
  /// a grid anchored at the screen's origin.
  ///
  /// Equal shares draw the same pixels for the same content, which is what an
  /// image, a held layer or a filter keyed by one needs to stay valid.
  final int share;

  /// What the read asks of the copy, on the screen, in logical pixels.
  final Rect reads;

  /// What the copy holds: [reads] grown to whole pixels of the copy, and cut
  /// at the screen's edge, which need not lie on them.
  final DeviceBox copyBox;

  /// The layer the copy is drawn in: [copyBox] grown to whole pixels of the
  /// copy, grown where a clip would cut the layer, or the part of it inside a
  /// clip that leaves no room to grow or that cuts a copy smaller than the
  /// screen; and under a copy at the screen's pixels the rows its [levels]
  /// lie in.
  final DeviceBox layer;

  /// The clip around the read's lead, on the screen, in logical pixels.
  final Rect? clip;

  /// The frost the copy holds drawn in the frame, in logical pixels (see
  /// [_bakedFrost]).
  final double bakedFrost;

  /// The widest frost of a band left out of the copy under glass that
  /// frosts as wide, which the glass adds to its own, in logical pixels.
  final double frostLeftOut;

  /// Equal while the image read filter the copy is drawn through draws alike,
  /// null for none.
  final ImageReadLook? filter;

  /// What the glass reading the copy blurs it by, the frost [frostLeftOut]
  /// added, or null where it reads it as it is: the blur the levels it
  /// carries beside it are laid out for.
  final CopyLevels? levels;

  /// How many device pixels along each side a cell of the grid holds that an
  /// image of the read starts on and spans whole cells of: the copy's pixels,
  /// or for an image Impeller blurs, the cells its blur averages the image
  /// into first.
  ///
  /// Impeller averages an image it blurs into cells from the image's corner
  /// and pads an image of a part of a cell symmetrically, so the cells move
  /// with the image's corner and with its size. An image that grows by a
  /// pixel of the copy as its glass moves then blurs the same page another
  /// way each frame: the glass blinks a level all over (a lens carried over
  /// text at 2.625 dpr, host). On the grid, the cells lie on the screen. An
  /// image cut by the screen's edge keeps that edge, and its cells their
  /// place.
  final int imageGrid;

  /// Whether an image of the read is blurred by an image filter over a
  /// layer it shares with the images blurred alike, where that draws as a
  /// backdrop filter of its own does ([ImpellerBlur.imageFilterMatches]);
  /// false for an image not blurred.
  final bool imageFilterBlurs;

  /// The room an image of the read takes, as the plan chose it, in logical
  /// pixels, or null for a copy drawn in the frame.
  final Rect? room;

  /// What an image of the read holds: [room] grown to whole pixels of the
  /// copy and cut at the screen's edge.
  final DeviceBox? imageBox;

  /// The copy's pixels per logical pixel.
  double get pixels => view.devicePixelRatio / share;

  /// [copyBox] in logical pixels.
  Rect get copyBounds => view.logical(copyBox);

  /// [layer] in logical pixels.
  Rect get layerRect => view.logical(layer);

  /// [imageBox] in logical pixels.
  Rect? get imageRect => switch (imageBox) {
    final box? => view.logical(box),
    null => null,
  };

  /// This layout for an image of [room], on [screen].
  ReadLayout withRoom(Rect room, Rect screen) => ReadLayout._(
    view: view,
    share: share,
    reads: reads,
    copyBox: copyBox,
    layer: layer,
    clip: clip,
    bakedFrost: bakedFrost,
    frostLeftOut: frostLeftOut,
    filter: filter,
    levels: levels,
    imageGrid: imageGrid,
    imageFilterBlurs: imageFilterBlurs,
    room: room,
    imageBox: view.cover(room, share: imageGrid).intersect(view.cover(screen)),
  );

  /// The sigma, in device pixels, the shaders' taps frost a copy whose
  /// pixels hold [share] device pixels by for Impeller's blur by [sigma]
  /// screen logical pixels. The copy's own pixels already blur by what they
  /// hold, which a band holding glass that a filter draws, at the screen's
  /// pixels whatever was asked, holds less of. NEAR there: the taps lie up to
  /// 14 of its pixels apart, past the 3.5 a shader-frosted copy keeps to;
  /// under the scroll edge over glass the frost is 0.55 levels off the
  /// backdrop read on average at 2.625 dpr and 0.41 at 3 (host test).
  double residualAt(int share, double sigma) => sigma > 0
      ? _frostResidual(sigma * view.devicePixelRatio, share: share)
      : 0;

  /// The frost, in logical pixels, drawn into the copy at its own pixels in a
  /// target whose pixels hold [targetShare] device pixels each: [bakedFrost]
  /// in the frame, whose device pixels the frost's taps are spaced in, none
  /// inside a coarser copy.
  double bakedIn(int targetShare) => targetShare > 1 ? 0 : bakedFrost;

  /// The filtered layers that frost the copy in place in a target whose pixels
  /// hold [targetShare] device pixels each, each a pass of the frame: none for
  /// no frost, the [FrostLattice.passes] of one drawn over every pixel, and
  /// one for sparse taps.
  int frostLayersIn(int targetShare) {
    final baked = bakedIn(targetShare);
    if (baked <= 0) return 0;
    final inCopyPixels = residualAt(share, frostFor(baked)) / share;
    if (inCopyPixels <= 0) return 0;
    return frostLatticeOf(inCopyPixels)?.passes ?? 1;
  }

  /// The frost, in logical pixels, that stands for [sigma] over what the
  /// copy left out.
  double frostFor(double sigma) =>
      sigma > 0 ? blurAdding(sigma, frostLeftOut) : sigma;

  /// The part of [layer] to draw inside the copy of [outer], which holds
  /// this read's glass, in logical pixels.
  ///
  /// A smaller copy starts inside the copy box of the read nesting it, cut by
  /// [clip], as [layer] does inside a clip: it lies in its layer's corner,
  /// which the cut would leave outside, and on Metal the glass over it then
  /// reads black (iPhone 16 Pro, a sheet moving over glass; Vulkan does not
  /// show it). NEAR: glass reads what lies past the cut mirrored at it, under
  /// the frost of the read holding it.
  Rect nestedIn(ReadLayout outer) {
    final clip = this.clip;
    final copyBox = outer.copyBounds;
    final held = clip == null ? copyBox : copyBox.intersect(clip);
    return share == 1 && ImpellerLayers.keepsWholeOn(layer, held, view)
        ? layerRect
        : held;
  }

  /// Whether a copy at this layout draws what one at [other] draws over
  /// the same backdrop: the same frost held and left out, through the same
  /// image read filter, with the same levels beside it.
  bool drawsLike(ReadLayout other) =>
      bakedFrost == other.bakedFrost &&
      frostLeftOut == other.frostLeftOut &&
      filter == other.filter &&
      levels == other.levels;

  /// Whether an image drawn at this layout serves a read at [next]: it
  /// draws alike on the same pixels, and its room holds all [next] reads.
  bool servesAsImage(ReadLayout next) {
    final room = this.room;
    return room != null &&
        share == next.share &&
        view == next.view &&
        drawsLike(next) &&
        encloses(room, next.reads);
  }
}
