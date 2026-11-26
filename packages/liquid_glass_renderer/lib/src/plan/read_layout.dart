import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
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
// k x k device px (a box, variance k^2 / 12), every bilinear tap adds a tent
// of a copy pixel (k^2 / 6), and Gaussians add in variance.
double _frostResidual(double sigma, {required int share}) {
  final delivered = sigma * ImpellerBlur.deliveredFraction;
  final carried = share * share * (share > 1 ? 1 / 4 : 1 / 6);
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

  /// These levels for glass that adds [frost] to its blur, as Gaussians
  /// add.
  CopyLevels adding(double frost) => frost <= 0 || !blurs
      ? this
      : CopyLevels(
          least: sqrt(least * least + frost * frost),
          most: sqrt(most * most + frost * frost),
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

/// What a site needs of a copy of its backdrop: how many device pixels along
/// each side one pixel of the copy may stand for, the frost a scroll edge's
/// shader draws over it, and the levels glass blurs it from.
///
/// A site states the most a copy may be reduced for it; the read joining
/// sites takes the least of their shares, and its [ReadLayout] decides the
/// copy's grid.
@immutable
final class CopyNeed {
  /// A need of [share] device pixels a copy pixel, frosted by [shaderFrost]
  /// and blurred from [levels]; by default a copy at the screen's pixels with
  /// nothing over it.
  const CopyNeed({this.share = 1, this.shaderFrost = 0, this.levels});

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
    return CopyNeed(share: share);
  }

  /// The need of glass that blurs an unblurred copy from [levels]: halved
  /// while its least blur spans two pixels of the copy, to at most
  /// [maxShare], and at least [atLeast].
  ///
  /// A blur narrower than two of the copy's pixels mixes the copy itself
  /// in, whose pixels show as the page moves under the glass: against a
  /// Gaussian under sub-pixel shifts, 29 to 73 levels off below it and 2 to
  /// 10 above, glass of 64 to 90 points on a replica of the levels.
  ///
  /// Glass that shows what lies under it sharp inside reads a copy of
  /// [atLeast] pixels; where it blurs everywhere, a coarser copy loses
  /// nothing its blur would show.
  factory CopyNeed.levelled(
    CopyLevels levels, {
    required double devicePixelRatio,
    required int maxShare,
    int atLeast = 1,
  }) {
    var share = min(atLeast, maxShare);
    while (share * 2 <= maxShare &&
        levels.least * devicePixelRatio / (share * 2) >= 2) {
      share *= 2;
    }
    return CopyNeed(share: share, levels: levels);
  }

  /// The need of a scroll edge or fake glass whose frost shader frosts an
  /// unblurred copy by [sigma] logical pixels, to at most [maxShare], or null
  /// where the frost is too wide for it. A copy whose pixels the frost spans
  /// by less than 1.5 is not halved again: drawn smaller, its edges show
  /// through the frost.
  static CopyNeed? edgeFrost(
    double sigma, {
    required double devicePixelRatio,
    required int maxShare,
  }) => switch (_shaderFrostShare(
    sigma * devicePixelRatio,
    minTexels: 1.5,
    maxShare: maxShare,
  )) {
    final share? => CopyNeed(share: share, shaderFrost: sigma),
    null => null,
  };

  /// Device pixels along each side one pixel of the copy may stand for.
  final int share;

  /// The frost a scroll edge's shader draws over the copy, in logical
  /// pixels: 0 for glass, which blurs from [levels].
  final double shaderFrost;

  /// Whether a frost shader draws over the copy ([shaderFrost]), where
  /// otherwise the copy holds the filtered backdrop.
  bool get frostedByShader => shaderFrost > 0;

  /// What glass blurs the copy by, or null where it reads it as it is or
  /// Impeller blurs it.
  final CopyLevels? levels;

  /// The least blur, in logical pixels, a shader draws over all of the
  /// copy it shows: a scroll edge's frost, or the least blur of glass.
  double get leastBlur => shaderFrost > 0 ? shaderFrost : levels?.least ?? 0;

  /// The logical pixels a shader frosting or blurring the copy reads around a
  /// region on a screen of [devicePixelRatio]. A blur reads three sigmas
  /// out; the fill reads the copy's edge for what lies past it.
  ///
  /// A copy drawn at the screen's pixels in place of the ones asked reaches
  /// less: its taps lie at most a sigma wider and its pixel is smaller.
  double reachAt(double devicePixelRatio) {
    if (shaderFrost > 0) {
      return (frostTapReach *
                  _frostResidual(
                    shaderFrost * devicePixelRatio,
                    share: share,
                  ) +
              share) /
          devicePixelRatio;
    }
    final most = levels?.most ?? 0;
    return most > 0 ? 3 * most + share / devicePixelRatio : 0;
  }

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
      other is CopyNeed &&
      other.share == share &&
      other.shaderFrost == shaderFrost &&
      other.levels == levels;

  @override
  int get hashCode => Object.hash(share, shaderFrost, levels);
}

/// The frost, in logical pixels, a read's copy holds, frosted once at its own
/// pixels so the scroll edge or fake glass over it takes one read per
/// fragment in place of its taps, or 0 where the shader frosts it.
///
/// Only a copy that every reader frosts by at least [edgeFrost] holds it, at
/// fewer pixels than the screen's: at the screen's pixels, or holding glass,
/// which lies at them, the frost costs more than the taps it saves. Glass
/// blurs from the levels beside its copy, which stays unfrosted, as does the
/// copy of a band that glass draws.
///
/// Where the frost's program is not loaded yet the copy is drawn unfrosted
/// and the shader frosts it.
///
/// NEAR: the frost drawn into the copy weighs every pixel of the copy it
/// reaches (latticeTaps in copy_frost.dart), where the shader's own taps
/// are sparse.
double _bakedFrost({
  required int share,
  required bool holdsGlass,
  required double edgeFrost,
}) => share < 2 || holdsGlass ? 0 : edgeFrost;

// The widest frost, in a copy's pixels squared, eight pairs of them hold:
// what a copy picked for its frost spans ([CopyNeed]). A copy finer than was
// asked, such as one that holds glass, leaves a wider frost to sparse taps.
const double _frostLatticeWidest = 11.87;

// The widest frost, in a copy's pixels squared, three pairs hold: one pass
// of nine reads draws it. A wider one is a pass an axis.
const double _frostSquareWidest = 1.5235;

/// How a frost is drawn over every pixel of a copy it reaches, at the copy's
/// own pixels (see [frostLatticeOf]).
enum FrostLattice {
  /// One pass of nine reads: three pairs of pixels along each axis.
  square,

  /// One pass along x and one along y over what it left.
  axes,
}

/// How a frost by a sigma of [inCopyPixels] of a copy's pixels is drawn over
/// every pixel of the copy it reaches, or null where it is not: no frost, or
/// one too wide for eight pairs of the copy's pixels, which sparse taps
/// draw.
///
/// The one rule both the plan, which counts the passes a copy's frost
/// takes, and the filters that draw it follow.
FrostLattice? frostLatticeOf(double inCopyPixels) {
  if (inCopyPixels <= 0) return null;
  final wide = inCopyPixels * inCopyPixels;
  if (wide > _frostLatticeWidest) return null;
  return wide <= _frostSquareWidest ? FrostLattice.square : FrostLattice.axes;
}

/// Where the levels of a copy lie: one row of cells under the copy in its
/// texture, which copy_levels.frag writes and the final shader reads
/// (copy_levels.glsl).
///
/// Blur level k averages 2^k x 2^k of the copy's pixels by a tent twice that
/// wide, and the fill level a cell of its own stride the same way, each on a
/// grid anchored at the screen: a copy that moves with its glass averages
/// the same pixels into a cell, and its blur stays put. Cells counted from
/// the copy's corner part the page another way at each step of the copy,
/// and the glass flickers in patches as it moves. Levels 1 and 2 average the
/// copy, the coarser ones and the fill level average level 2, so the levels
/// take two passes at most.
///
/// The row holds the fill level first, then the blur levels from the finest
/// ([first]) to the coarsest ([last]), each inside a ring of one cell that
/// repeats its edge, so a bilinear read anywhere over the copy needs no
/// clamp.
@immutable
final class LevelStrip {
  /// The strip of a copy of [copy] pixels, its top left at [grid] on the
  /// screen's grid of its pixels, for glass blurring it from [levels] at
  /// [pixels] copy pixels a logical pixel; [boxed] where a copy pixel
  /// averages more than one device pixel.
  factory LevelStrip(
    CopyLevels levels, {
    required double pixels,
    required bool boxed,
    required Size copy,
    required Offset grid,
  }) {
    final (:first, :last, :blurs, :fillStride) = choose(
      levels,
      pixels: pixels,
      boxed: boxed,
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

  /// The levels a copy carries for glass blurring it from [levels] at
  /// [pixels] copy pixels a logical pixel: the blur levels from [first] to
  /// [last], which take in level 2 that the others average, whether the
  /// glass reads them, and the fill level's stride, 0 for none.
  ///
  /// The glass reads the two levels whose blur brackets its own, so the
  /// least blur picks the finest and the most the coarsest; level 0 is the
  /// copy itself.
  static ({int first, int last, bool blurs, int fillStride}) choose(
    CopyLevels levels, {
    required double pixels,
    required bool boxed,
  }) {
    final box = boxed ? 1 / 12 : 0.0;
    final least = levels.least * pixels;
    final most = levels.most * pixels;
    final fill = levels.fill * pixels;
    final blurs = most > 0;
    final finest = blurs
        ? min(max(1, _levelBelow(least * least, box)), levelMostDeep)
        : 2;
    final coarsest = blurs
        ? min(max(finest, _levelBelow(most * most, box) + 1), levelMostDeep)
        : 2;
    final across = sqrt(max(3 * (fill * fill - box - 8 / 3), 0));
    return (
      first: min(finest, 2),
      last: max(coarsest, 2),
      blurs: blurs,
      fillStride: fill > 0
          ? 4 * (across / 4).round().clamp(1, levelMostPairs - 1)
          : 0,
    );
  }

  // The deepest level whose read blurs by at most [variance], in copy pixels
  // squared: level k reads as `box + k^4 / 3`, past level 2 with level 2's
  // own tent too (copy_levels.glsl).
  static int _levelBelow(double variance, double box) {
    final span = 3 * (variance - box);
    final level = span >= 72 ? span - 8 : min<double>(span, 63);
    return level < 4 ? 0 : (log(level) / ln2 / 2).floor();
  }

  /// The finest blur level the strip holds.
  final int first;

  /// The coarsest blur level the strip holds.
  final int last;

  /// Whether the glass reads the blur levels, where level 2 may lie in the
  /// strip only for the fill level to average.
  final bool blurs;

  /// The fill level's stride in copy pixels, 0 for none.
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
  int get fillColumns => fillStride > 0 ? fillCells + 2 : 0;

  /// The column, from the strip's left, the cells of blur level [k] start
  /// at, past its ring.
  int columnOf(int k) =>
      fillColumns +
      (width >> (first - 1)) -
      (width >> (k - 1)) +
      3 * (k - first) +
      1;

  /// The strip's width in pixels.
  int get across => columnOf(last + 1) - 1;

  /// The strip's height in pixels: the finest level's cells and its ring.
  int get down => (height >> first) + 3;

  /// The rows a layer keeps under the copy for the strip.
  int get rows => down + ImpellerLayers.spareRows;

  /// The size of what the copy and its strip take from the copy's top left.
  Size get size => Size(
    max(copy.width, across.toDouble()),
    copy.height + rows,
  );

  /// The passes that draw the levels: one for levels 1 and 2, and one for
  /// the coarser ones and the fill level.
  int get passes => passesOf(
    (first: first, last: last, blurs: blurs, fillStride: fillStride),
  );

  /// The passes that draw the levels [chosen] ([choose]).
  static int passesOf(
    ({int first, int last, bool blurs, int fillStride}) chosen,
  ) => chosen.last > 2 || chosen.fillStride > 0 ? 2 : 1;

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
    required this.footprint,
    required this.layer,
    required this.clip,
    required this.bakedFrost,
    required this.frostLeftOut,
    required this.filter,
    required this.levels,
    required this.imageGrid,
    this.room,
    this.imageBox,
  });

  /// The layout of a read asking [reads] of a copy of [askedShare] device
  /// pixels a pixel at [devicePixelRatio], led under [clip], on [screen]
  /// (logical pixels).
  ///
  /// A copy that holds glass drawn at the screen's pixels lands on the
  /// screen's own pixels ([atScreen]). [edgeFrost] is the frost, in logical
  /// pixels, of the scroll edge or fake glass that leads the read, where no
  /// glass reads its copy. An image of a copy that Impeller blurs
  /// by [imageBlur] logical pixels lies on the grid its blur samples
  /// ([imageGrid]).
  factory ReadLayout.resolve({
    required double devicePixelRatio,
    required int askedShare,
    required bool atScreen,
    required Rect reads,
    required Rect screen,
    required Rect? clip,
    required bool holdsGlass,
    required double edgeFrost,
    required double frostLeftOut,
    required Object? filter,
    required double imageBlur,
    CopyLevels? levels,
  }) {
    assert(
      askedShare == 1 || askedShare == 2 || askedShare == 4 || askedShare == 8,
      'A copy holds one, two, four or eight device pixels along each side.',
    );
    final view = ViewPixels(devicePixelRatio);
    final share = atScreen ? 1 : askedShare;
    final footprint = view
        .cover(reads, share: share)
        .intersect(view.cover(screen));
    final cut = clip?.intersect(screen);
    final layer = switch (cut) {
      null => footprint.outTo(share),
      // A smaller copy lies in its layer's corner, which a layer grown past
      // the clip leaves outside it, and Impeller draws none of the copy there
      // (host test): the layer starts inside the clip. NEAR: glass reads what
      // lies past the clip mirrored at it, as where a clip leaves no room to
      // grow.
      _ when share > 1 => view.cover(
        view.logical(footprint).intersect(cut),
        share: share,
      ),
      _ => ImpellerLayers.layerIn(footprint, cut, view),
    };
    return ReadLayout._(
      view: view,
      share: share,
      reads: reads.intersect(screen),
      footprint: footprint,
      layer: levels == null || share > 1
          ? layer
          : _withLevelRows(
              layer,
              footprint,
              cut,
              levels.adding(frostLeftOut),
              view,
            ),
      clip: cut,
      bakedFrost: _bakedFrost(
        share: share,
        holdsGlass: holdsGlass,
        edgeFrost: edgeFrost,
      ),
      frostLeftOut: frostLeftOut,
      filter: filter,
      levels: levels,
      imageGrid:
          share * ImpellerBlur.share(imageBlur * devicePixelRatio / share),
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
    DeviceBox footprint,
    Rect? cut,
    CopyLevels levels,
    ViewPixels view,
  ) {
    DeviceBox grown(DeviceBox from) {
      final copy = Size(
        footprint.right - from.left,
        footprint.bottom - from.top,
      );
      final rows = LevelStrip(
        levels,
        pixels: view.devicePixelRatio,
        boxed: false,
        copy: copy,
        grid: from.topLeft,
      ).rows;
      return from.downTo(footprint.bottom + rows);
    }

    final whole = grown(layer);
    if (cut == null ||
        ImpellerLayers.keepsCorner(
          whole.rect,
          cut.scaled(view.devicePixelRatio),
        )) {
      return whole;
    }
    return grown(view.cover(view.logical(footprint).intersect(cut)));
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
  final DeviceBox footprint;

  /// The layer the copy is drawn in: [footprint] grown to whole pixels of the
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
  final Object? filter;

  /// What the glass reading the copy blurs it by, or null where it reads it
  /// as it is: the levels it carries beside it.
  final CopyLevels? levels;

  /// [levels] with the frost [frostLeftOut] the glass adds: the blur its
  /// levels are laid out for.
  CopyLevels? get drawnLevels => levels?.adding(frostLeftOut);

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

  /// The room an image of the read takes, as the plan chose it, in logical
  /// pixels, or null for a copy drawn in the frame.
  final Rect? room;

  /// What an image of the read holds: [room] grown to whole pixels of the
  /// copy and cut at the screen's edge.
  final DeviceBox? imageBox;

  /// The copy's pixels per logical pixel.
  double get pixels => view.devicePixelRatio / share;

  /// [footprint] in logical pixels.
  Rect get footprintRect => view.logical(footprint);

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
    footprint: footprint,
    layer: layer,
    clip: clip,
    bakedFrost: bakedFrost,
    frostLeftOut: frostLeftOut,
    filter: filter,
    levels: levels,
    imageGrid: imageGrid,
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
  /// no frost, two for a frost drawn an axis at a time, else one.
  int frostLayersIn(int targetShare) {
    final baked = bakedIn(targetShare);
    if (baked <= 0) return 0;
    final inCopyPixels = residualAt(share, frostFor(baked)) / share;
    if (inCopyPixels <= 0) return 0;
    return frostLatticeOf(inCopyPixels) == FrostLattice.axes ? 2 : 1;
  }

  /// The frost, in logical pixels, that stands for [sigma] over what the
  /// copy left out.
  double frostFor(double sigma) => sigma > 0 && frostLeftOut > 0
      ? sqrt(sigma * sigma + frostLeftOut * frostLeftOut)
      : sigma;

  /// The part of [layer] to draw inside the copy of [outer], which holds
  /// this read's glass, in logical pixels.
  ///
  /// A smaller copy starts inside the footprint of the read holding it, cut by
  /// [clip], as [layer] does inside a clip: it lies in its layer's corner,
  /// which the cut would leave outside, and on Metal the glass over it then
  /// reads black (iPhone 16 Pro, a sheet moving over glass; Vulkan does not
  /// show it). NEAR: glass reads what lies past the cut mirrored at it, under
  /// the frost of the read holding it.
  Rect heldIn(ReadLayout outer) {
    final clip = this.clip;
    final footprint = outer.footprintRect;
    final held = clip == null ? footprint : footprint.intersect(clip);
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
