import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/composer/impeller.dart';
import 'package:liquid_glass_renderer/src/composer/rects.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:meta/meta.dart';

// The share of the sigma asked that Impeller's blur delivers, which the
// shader's frost matches so a copy and the live filter blur alike: the best
// of 0.70 to 1.0 against ImageFilter.blur at 3, 5 and 8 device px, where
// Impeller's blur passes deliver 0.84 to 0.87 of the sigma.
const double _deliveredFrost = 0.84;

// The largest sigma, in the copy's own pixels, the shader frosts by. Its taps
// lie about a sigma apart, so a wider frost shows hard edges as faint copies:
// they show at 5 copy pixels in the host test and not at 3.4.
const double _shaderFrostTexels = 3.5;

// How many device pixels along each side one pixel of a copy the shader
// frosts stands for at most. 8 gave no clear GPU gain on the Pixel 6a.
const int _shaderFrostMaxShare = 4;

// A copy blurred by at least this many of its own pixels is drawn as the blur
// leaves it at a fraction of the screen's pixels: sampled back up, it adds a
// tent of its pixel's width to a blur many times wider.
const double _blurredCopySigma = 2.5;

// How many device pixels along each side one pixel of a copy holds that the
// shader frosts for Impeller's blur by [sigma] device pixels, or null when
// the frost is too wide for it: the largest whose pixels the frost spans by at
// most 3.5, then halved while the frost still spans [minTexels] of its pixels
// and, with [nearBlurScale], to one step past where Impeller's own blur
// would downsample.
int? _shaderFrostShare(
  double sigma, {
  required double minTexels,
  bool nearBlurScale = false,
}) {
  final delivered = sigma * _deliveredFrost;
  var share = 1;
  while (share < _shaderFrostMaxShare &&
      delivered / share > _shaderFrostTexels) {
    share *= 2;
  }
  if (delivered <= 0 || delivered / share > _shaderFrostTexels) return null;
  final floor = nearBlurScale
      ? 2 * ImpellerBlur.share(sigma)
      : _shaderFrostMaxShare;
  while (share < _shaderFrostMaxShare &&
      share * 2 <= floor &&
      delivered / (share * 2) >= minTexels) {
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
  final delivered = sigma * _deliveredFrost;
  final carried = share * share * (share > 1 ? 1 / 4 : 1 / 6);
  return sqrt(max(delivered * delivered - carried, 0));
}

/// What a site needs of a copy of its backdrop: how many device pixels along
/// each side one pixel of the copy may stand for, and the frost a shader
/// draws over it.
///
/// A site states the most a copy may be reduced for it; the read joining
/// sites takes the least of their shares, and its [ReadGeometry] decides the
/// copy's grid.
@immutable
final class CopyNeed {
  /// A need of [share] device pixels a copy pixel, frosted by [shaderFrost]; by
  /// default a copy at the screen's pixels with nothing frosted over it.
  const CopyNeed({this.share = 1, this.shaderFrost = 0, this.haze});

  /// The need of a copy Impeller blurs by at least [sigma] logical pixels
  /// along each axis: halved while the blur spans 2.5 of its pixels, to at
  /// most [maxShare].
  factory CopyNeed.blurred(
    double sigma, {
    required double devicePixelRatio,
    required int maxShare,
  }) {
    var share = 1;
    while (share * 2 <= maxShare &&
        sigma * devicePixelRatio / (share * 2) >= _blurredCopySigma) {
      share *= 2;
    }
    return CopyNeed(share: share);
  }

  /// The need of glass whose final shader frosts an unblurred copy by
  /// [sigma] logical pixels, or null where the frost is too wide for its
  /// taps.
  ///
  /// NEAR: the copy is one step coarser than Impeller's own blur would
  /// take, so a weak frost spans 1 to 2 of its pixels and is drawn into it
  /// in one pass of nine reads a pixel (latticeTaps in copy_frost.dart), a
  /// bar's 2.2 logical pixels over a sixteenth of the screen's pixels where
  /// the finer copy took two passes over a quarter. Text and thin lines are
  /// drawn into the copy at its scale and land up to half of its pixel from
  /// where the page has them. Against what reading the backdrop draws, on
  /// the test font's blocks (host, dpr 1): 18 levels at a frost of 3, where
  /// the glass's own taps over a copy at the screen's pixels lay 22, and 21
  /// at a frost of 8, where the finer copy lay 11. On a Pixel 6a a bar over
  /// a list at rest differs by at most 10 levels in a few hundred pixels,
  /// and a slow scroll under it flickers no more (a screen recording's
  /// frames against their neighbours, 2.85 against 2.86 levels).
  ///
  /// A copy with a [haze] has it mixed in after its frost, where the frost
  /// is drawn into the copy.
  static CopyNeed? glassFrost(
    double sigma, {
    required double devicePixelRatio,
    LiquidGlassHaze? haze,
  }) => switch (_shaderFrostShare(
    sigma * devicePixelRatio,
    minTexels: 1,
    nearBlurScale: true,
  )) {
    final share? => CopyNeed(share: share, shaderFrost: sigma, haze: haze),
    null => null,
  };

  /// The need of a scroll edge or fake glass whose frost shader frosts an
  /// unblurred copy by [sigma] logical pixels, or null where the frost is too
  /// wide for it. A copy whose pixels the frost spans by less than 1.5 is not
  /// halved again: drawn smaller, its edges show through the frost.
  static CopyNeed? edgeFrost(
    double sigma, {
    required double devicePixelRatio,
  }) => switch (_shaderFrostShare(sigma * devicePixelRatio, minTexels: 1.5)) {
    final share? => CopyNeed(share: share, shaderFrost: sigma),
    null => null,
  };

  /// Device pixels along each side one pixel of the copy may stand for.
  final int share;

  /// The frost a shader draws over the copy, in logical pixels: 0 where the
  /// copy is blurred instead or nothing frosts it.
  final double shaderFrost;

  /// The wide blur of the copy mixed into it, or null for none.
  final LiquidGlassHaze? haze;

  /// The logical pixels a shader frosting the copy reads around a region on
  /// a screen of [devicePixelRatio].
  ///
  /// A copy drawn at the screen's pixels in place of the ones asked reaches
  /// less: its taps lie at most a sigma wider and its pixel is smaller.
  double reachAt(double devicePixelRatio) => shaderFrost > 0
      ? (_tapReach *
                    _frostResidual(
                      shaderFrost * devicePixelRatio,
                      share: share,
                    ) +
                share) /
            devicePixelRatio
      : 0;

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

  static const double _tapReach = 2.8;

  @override
  bool operator ==(Object other) =>
      other is CopyNeed &&
      other.share == share &&
      other.shaderFrost == shaderFrost &&
      other.haze == haze;

  @override
  int get hashCode => Object.hash(share, shaderFrost, haze);
}

/// The frost, in logical pixels, a read's copy holds, frosted once at its own
/// pixels so the glass over it takes one read per fragment in place of its
/// taps, or 0 where the glass frosts it.
///
/// A copy at the screen's pixels holds none, nor does one holding glass,
/// which lies at the screen's pixels: there the frost costs more than the
/// taps it saves. Nor does a copy whose glass a band leads with less frost
/// ([bandFrost]): the band adds to the frost what it still lacks, so the copy
/// can't hold more. [glassFrost] is that of the glass reading the copy, 0
/// where a band reads it alone: the copy then holds the band's frost, and
/// the band, drawn at the screen's pixels, takes one read of it per
/// fragment where frosting it there took a frost's reads for each.
///
/// Where the frost's program is not loaded yet the copy is drawn unfrosted
/// and the glass frosts it.
///
/// NEAR: the glass takes one read for its 12 taps per fragment, over a copy
/// of a quarter of the screen's pixels along each side where the frost spans
/// at least one of them. The frost drawn into the copy weighs every pixel of
/// the copy it reaches (latticeTaps in copy_frost.dart), where the glass's
/// own taps are sparse: a point under the glass stays one point
/// (frost_point_test), and white bars lie 13 to 21 levels from what reading
/// the backdrop draws at a frost of 3 to 12 (backdrop_underlay_frost_test,
/// host, dpr 1). On a Pixel 6a it costs what the sparse taps it replaced
/// did: 107 against 106 ms of GPU a second over flat under a tab bar, 52
/// against 58 over a page of photos (in-launch pairs).
double _bakedFrost({
  required int share,
  required bool holdsGlass,
  required double glassFrost,
  required double? bandFrost,
}) {
  if (share < 2 || holdsGlass) return 0;
  if (bandFrost != null && bandFrost < glassFrost) return 0;
  return glassFrost > 0 ? glassFrost : bandFrost ?? 0;
}

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

/// Where a haze keeps the wide blur of a copy: a strip of pixels under the
/// copy, each the average of a square cell of it.
@immutable
final class HazeStrip {
  /// The strip of a copy of [copy] pixels for a wide blur by [sigma] of
  /// them.
  ///
  /// A cell is 0.87 to 1 sigma wide, an even number of pixels: two of the
  /// copy's pixels share one read of a cell, and the bell
  /// backdrop_haze_mix.frag draws over six cells makes up the rest of the
  /// width. Wider cells would be fewer, and would turn a page striped finer
  /// than two of them into slow bands.
  factory HazeStrip(double sigma, Size copy) {
    final cell = (2 * (sigma / 2.3).ceil()).clamp(2, 2 * hazeMostReads);
    // What an average over a cell blurs by is a twelfth of its side squared.
    final left = sigma * sigma / (cell * cell) - 1 / 12;
    return HazeStrip._(
      cell: cell,
      across: (copy.width / cell).ceil(),
      down: (copy.height / cell).ceil(),
      reach: _reachOf(left),
    );
  }

  const HazeStrip._({
    required this.cell,
    required this.across,
    required this.down,
    required this.reach,
  });

  // How many strip pixels the bell reaches whose weights over six of them,
  // `(1 - (d / reach)^2)^2` a distance `d` away, are [wide] pixels squared
  // wide: three at most, the six pixels a fragment reads, where a width
  // past what they hold gets what they hold.
  static double _reachOf(double wide) {
    if (_reaches[wide] case final held?) return held;
    if (_reaches.length >= 32) _reaches.clear();
    // The width over the places a fragment takes between two pixels.
    double widthOf(double reach) {
      var width = 0.0;
      for (var place = 0; place < 4; place++) {
        var total = 0.0;
        var spread = 0.0;
        for (var pixel = -2; pixel <= 3; pixel++) {
          final distance = pixel - place / 4;
          final inside = max(1 - distance * distance / (reach * reach), 0);
          final weight = inside * inside;
          total += weight;
          spread += weight * distance * distance;
        }
        width += spread / total / 4;
      }
      return width;
    }

    var narrow = 1.0;
    var far = 3.0;
    if (widthOf(far) > wide) {
      for (var i = 0; i < 40; i++) {
        final middle = (narrow + far) / 2;
        if (widthOf(middle) < wide) {
          narrow = middle;
        } else {
          far = middle;
        }
      }
    }
    return _reaches[wide] = far;
  }

  static final _reaches = <double, double>{};

  /// The side of a cell, in the copy's pixels.
  final int cell;

  /// How many cells the copy is wide, which is the strip's width in pixels.
  final int across;

  /// How many cells the copy is high, which is the strip's height in pixels.
  final int down;

  /// The rows a layer keeps under the copy for the strip.
  int get rows => down + ImpellerLayers.spareRows;

  /// How many of the strip's pixels the bell read over it reaches.
  final double reach;
}

/// Where one read's backdrop pixels lie: on which grid, at which boxes and
/// with which frost, in the frame and inside the copies that hold it.
/// Compile resolves it, the ledger compares it, emit lays it out and sites
/// read it; nothing decides any of it again.
@immutable
final class ReadGeometry {
  const ReadGeometry._({
    required this.view,
    required this.step,
    required this.reads,
    required this.band,
    required this.layer,
    required this.clip,
    required this.bakedFrost,
    required this.frostLeftOut,
    required this.filter,
    required this.haze,
    this.room,
    this.imageBox,
  });

  /// The geometry of a read asking [reads] of a copy of [share] device pixels
  /// a pixel at [devicePixelRatio], led under [clip], on [screen] (logical
  /// pixels).
  ///
  /// A copy that holds glass drawn at the screen's pixels lands on the
  /// screen's own pixels ([atScreen]).
  factory ReadGeometry.resolve({
    required double devicePixelRatio,
    required int share,
    required bool atScreen,
    required Rect reads,
    required Rect screen,
    required Rect? clip,
    required bool holdsGlass,
    required double glassFrost,
    required double? bandFrost,
    required double frostLeftOut,
    required Object? filter,
    LiquidGlassHaze? haze,
  }) {
    assert(
      share == 1 || share == 2 || share == 4 || share == 8,
      'A copy holds one, two, four or eight device pixels along each side.',
    );
    final view = ViewPixels(devicePixelRatio);
    final step = atScreen ? 1 : share;
    final band = view.cover(reads, step: step).intersect(view.cover(screen));
    final cut = clip?.intersect(screen);
    final layer = switch (cut) {
      null => band.outTo(step),
      // A smaller copy lies in its layer's corner, which a layer grown past
      // the clip leaves outside it, and Impeller draws none of the copy there
      // (host test): the layer starts inside the clip. NEAR: glass reads what
      // lies past the clip mirrored at it, as where a clip leaves no room to
      // grow.
      _ when step > 1 => view.cover(
        view.logical(band).intersect(cut),
        step: step,
      ),
      _ => ImpellerLayers.layerIn(band, cut, view),
    };
    return ReadGeometry._(
      view: view,
      step: step,
      reads: reads.intersect(screen),
      band: band,
      layer: haze == null || step > 1
          ? layer
          : _withHazeRows(layer, band, cut, haze, view),
      clip: cut,
      bakedFrost: _bakedFrost(
        share: step,
        holdsGlass: holdsGlass,
        glassFrost: glassFrost,
        bandFrost: bandFrost,
      ),
      frostLeftOut: frostLeftOut,
      filter: filter,
      haze: haze,
    );
  }

  // A copy at the screen's pixels fills its layer, which grows down by the
  // rows its haze keeps its strip in ([HazeStrip]), past the screen or the
  // clip where it must: they are a small part of the layer. Where the layer
  // with them would not keep its corner ([ImpellerLayers.keepsCorner]), it
  // is cut to the clip first. NEAR: as where a clip leaves no room to grow,
  // its glass reads the copy mirrored at the clip.
  static DeviceBox _withHazeRows(
    DeviceBox layer,
    DeviceBox band,
    Rect? cut,
    LiquidGlassHaze haze,
    ViewPixels view,
  ) {
    DeviceBox grown(DeviceBox from) {
      final copy = Size(band.right - from.left, band.bottom - from.top);
      final rows = HazeStrip(haze.sigma * view.devicePixelRatio, copy).rows;
      return from.downTo(band.bottom + rows);
    }

    final whole = grown(layer);
    if (cut == null ||
        ImpellerLayers.keepsCorner(
          whole.rect,
          cut.scaled(view.devicePixelRatio),
        )) {
      return whole;
    }
    return grown(view.cover(view.logical(band).intersect(cut)));
  }

  /// The screen's pixels the copy is laid out on.
  final ViewPixels view;

  /// How many device pixels along each side one pixel of the copy holds, on
  /// a grid anchored at the screen's origin.
  ///
  /// Equal steps draw the same pixels for the same content, which is what an
  /// image, a held layer or a filter keyed by one needs to stay valid.
  final int step;

  /// What the read asks of the copy, on the screen, in logical pixels.
  final Rect reads;

  /// What the copy holds: [reads] grown to whole pixels of the copy, and cut
  /// at the screen's edge, which need not lie on them.
  final DeviceBox band;

  /// The layer the copy is drawn in: [band] grown to whole pixels of the
  /// copy, grown where a clip would cut the layer, or the part of it inside a
  /// clip that leaves no room to grow or that cuts a copy smaller than the
  /// screen; and under a copy at the screen's pixels the rows its [haze]
  /// keeps its strip in.
  final DeviceBox layer;

  /// The clip around the read's lead, on the screen, in logical pixels.
  final Rect? clip;

  /// The frost the copy holds drawn in the frame, in logical pixels (see
  /// [_bakedFrost]).
  final double bakedFrost;

  /// The widest frost of a band left out of the copy under glass that
  /// frosts as wide, which the glass adds to its own, in logical pixels.
  final double frostLeftOut;

  /// Equal while the page filter the copy is drawn through draws alike, null
  /// for none.
  final Object? filter;

  /// The wide blur of the copy mixed into it over its frost, or null for
  /// none.
  final LiquidGlassHaze? haze;

  /// The room an image of the read takes, as the plan chose it, in logical
  /// pixels, or null for a copy drawn in the frame.
  final Rect? room;

  /// What an image of the read holds: [room] grown to whole pixels of the
  /// copy and cut at the screen's edge.
  final DeviceBox? imageBox;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio => view.devicePixelRatio;

  /// The copy's pixels per logical pixel.
  double get pixels => view.devicePixelRatio / step;

  /// [band] in logical pixels.
  Rect get bandRect => view.logical(band);

  /// [layer] in logical pixels.
  Rect get layerRect => view.logical(layer);

  /// [imageBox] in logical pixels.
  Rect? get imageRect => switch (imageBox) {
    final box? => view.logical(box),
    null => null,
  };

  /// This geometry for an image of [room], on [screen].
  ReadGeometry withRoom(Rect room, Rect screen) => ReadGeometry._(
    view: view,
    step: step,
    reads: reads,
    band: band,
    layer: layer,
    clip: clip,
    bakedFrost: bakedFrost,
    frostLeftOut: frostLeftOut,
    filter: filter,
    haze: haze,
    room: room,
    imageBox: view.cover(room, step: step).intersect(view.cover(screen)),
  );

  /// The sigma, in device pixels, the shaders' taps frost a copy whose
  /// pixels hold [step] device pixels by for Impeller's blur by [sigma]
  /// screen logical pixels. The copy's own pixels already blur by what they
  /// hold, which a band holding glass that a filter draws, at the screen's
  /// pixels whatever was asked, holds less of. NEAR there: the taps lie up to
  /// 14 of its pixels apart, past the 3.5 a shader-frosted copy keeps to;
  /// under the scroll edge over glass the frost is 0.55 levels off the live
  /// read on average at 2.625 dpr and 0.41 at 3 (host test).
  double residualAt(int step, double sigma) => sigma > 0
      ? _frostResidual(sigma * view.devicePixelRatio, share: step)
      : 0;

  /// The frost, in logical pixels, drawn into the copy at its own pixels in
  /// a target whose pixels hold [scale] device pixels each: [bakedFrost] in
  /// the frame, none inside a coarser copy, which would draw the frost's
  /// filter at its own pixels and the frost's taps take them for device
  /// pixels.
  double bakedIn(int scale) => scale > 1 ? 0 : bakedFrost;

  /// The filtered layers that frost the copy in place in a target whose
  /// pixels hold [scale] device pixels each, each a pass of the frame: none
  /// for no frost, two for a frost drawn an axis at a time, else one.
  int frostLayersIn(int scale) {
    final baked = bakedIn(scale);
    if (baked <= 0) return 0;
    final inCopyPixels = residualAt(step, frostFor(baked)) / step;
    if (inCopyPixels <= 0) return 0;
    return frostLatticeOf(inCopyPixels) == FrostLattice.axes ? 2 : 1;
  }

  /// The layers that mix the copy's [haze] into it, each a pass of the
  /// frame: one averages the copy into a strip, one reads its wide blur out
  /// of the strip.
  int get hazeLayers => haze == null ? 0 : 2;

  /// The frost, in logical pixels, that stands for [sigma] over what the
  /// copy left out.
  double frostFor(double sigma) => sigma > 0 && frostLeftOut > 0
      ? sqrt(sigma * sigma + frostLeftOut * frostLeftOut)
      : sigma;

  /// The part of [layer] to draw inside the copy of [outer], which holds
  /// this read's glass, in logical pixels.
  ///
  /// A smaller copy starts inside the band of the read holding it, cut by
  /// [clip], as [layer] does inside a clip: it lies in its layer's corner,
  /// which the cut would leave outside, and on Metal the glass over it then
  /// reads black (iPhone 16 Pro, a sheet moving over glass; Vulkan does not
  /// show it). NEAR: glass reads what lies past the cut mirrored at it, under
  /// the frost of the read holding it.
  Rect heldIn(ReadGeometry outer) {
    final clip = this.clip;
    final band = outer.bandRect;
    final held = clip == null ? band : band.intersect(clip);
    return step == 1 && ImpellerLayers.keepsWholeOn(layer, held, view)
        ? layerRect
        : held;
  }

  /// Whether a copy at this geometry draws what one at [other] draws over
  /// the same backdrop: the same frost held and left out, through the same
  /// page filter, under the same haze.
  bool drawsLike(ReadGeometry other) =>
      bakedFrost == other.bakedFrost &&
      frostLeftOut == other.frostLeftOut &&
      filter == other.filter &&
      haze == other.haze;

  /// Whether an image drawn at this geometry serves a read at [next]: it
  /// draws alike on the same pixels, and its room holds all [next] reads.
  bool servesAsImage(ReadGeometry next) {
    final room = this.room;
    return room != null &&
        step == next.step &&
        view == next.view &&
        drawsLike(next) &&
        encloses(room, next.reads);
  }
}
