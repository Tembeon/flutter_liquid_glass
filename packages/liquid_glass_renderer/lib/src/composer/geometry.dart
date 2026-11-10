import 'dart:math';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

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

// How many device pixels along each side one pixel holds where Impeller's
// blur by [sigma] device pixels downsamples (GaussianBlurFilterContents::
// CalculateScale: none up to 4, else 2^round(log2(sigma / 4))).
int _blurShare(double sigma) =>
    sigma <= 4 ? 1 : 1 << max(0, (log(sigma / 4) / ln2).round());

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
  final floor = nearBlurScale ? 2 * _blurShare(sigma) : _shaderFrostMaxShare;
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

/// The whole pixels below [pixels].
///
/// A rect snapped once and scaled back lands a hair off its pixels (837 /
/// 2.625 * 2.625 is 836.999...); it stays on them, or a second snap grows
/// its layer by a pixel.
double _floorPixels(double pixels) => (pixels + 1e-6).floorToDouble();

/// The whole pixels above [pixels], as [_floorPixels] rounds.
@internal
double ceilPixels(double pixels) => (pixels - 1e-6).ceilToDouble();

/// Whether [outer] holds all of [inner].
@internal
bool encloses(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

/// What a site needs of a copy of its backdrop: how many device pixels along
/// each side one pixel of the copy may stand for, and the frost a shader
/// draws over it.
///
/// The one place a copy's share is chosen: a site states its need, and
/// everything that sizes, joins or reaches by the copy reads it from here.
@internal
@immutable
final class CopyNeed {
  /// A need of [share] device pixels a copy pixel, frosted by [frost]; by
  /// default a copy at the screen's pixels with nothing frosted over it.
  const CopyNeed(this.devicePixelRatio, {this.share = 1, this.frost = 0});

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
    return CopyNeed(devicePixelRatio, share: share);
  }

  /// The need of glass whose final shader frosts an unblurred copy by
  /// [sigma] logical pixels, or null where the frost is too wide for its
  /// taps.
  ///
  /// NEAR: the copy is one step coarser than Impeller's own blur would
  /// take, so a weak frost spans 1 to 2 of its pixels and is drawn into it
  /// in one pass of nine reads a pixel (frostLattice in frost.glsl), a
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
  static CopyNeed? glassFrost(
    double sigma, {
    required double devicePixelRatio,
  }) => switch (_shaderFrostShare(
    sigma * devicePixelRatio,
    minTexels: 1,
    nearBlurScale: true,
  )) {
    final share? => CopyNeed(devicePixelRatio, share: share, frost: sigma),
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
    final share? => CopyNeed(devicePixelRatio, share: share, frost: sigma),
    null => null,
  };

  /// The screen's device pixels per logical pixel.
  final double devicePixelRatio;

  /// Device pixels along each side one pixel of the copy may stand for.
  final int share;

  /// The frost a shader draws over the copy, in logical pixels: 0 where the
  /// copy is blurred instead or nothing frosts it.
  final double frost;

  /// The logical pixels a shader frosting the copy reads around a region:
  /// its taps reach 2.8 frosts, one copy pixel more sampled bilinearly.
  ///
  /// A copy drawn at the screen's pixels in place of the ones asked reaches
  /// less: its taps lie at most a sigma wider and its pixel is smaller.
  double get reach => frost > 0
      ? (2.8 * _frostResidual(frost * devicePixelRatio, share: share) + share) /
            devicePixelRatio
      : 0;

  /// Whether a shader's written-out taps stay smooth drawing a band with this
  /// need for glass with [glass]'s over one copy: past 2.8 of the copy's
  /// pixels they speckle, by the Mali model, which counts them in parallel
  /// unlike a loop of twelve.
  bool bandFits(CopyNeed glass) {
    final share = min(this.share, glass.share);
    final residual = _frostResidual(frost * devicePixelRatio, share: share);
    return residual / share <= 2.8;
  }

  @override
  bool operator ==(Object other) =>
      other is CopyNeed &&
      other.devicePixelRatio == devicePixelRatio &&
      other.share == share &&
      other.frost == frost;

  @override
  int get hashCode => Object.hash(devicePixelRatio, share, frost);
}

/// The pixel grid a copy is drawn on: [share] device pixels of the screen
/// along each side of each of its pixels, on a grid anchored at the screen's
/// origin.
///
/// Equal lattices draw the same pixels for the same content, which is what
/// an image, a held layer or a filter keyed by one needs to stay valid.
@internal
@immutable
final class Lattice {
  /// The grid of [share] device pixels a pixel at [devicePixelRatio].
  const Lattice(this.devicePixelRatio, this.share)
    : assert(
        share == 1 || share == 2 || share == 4 || share == 8,
        'A copy holds one, two, four or eight device pixels along each side.',
      );

  /// The screen's device pixels per logical pixel.
  final double devicePixelRatio;

  /// How many device pixels along each side one pixel of the copy holds.
  final int share;

  /// The copy's pixels per logical pixel.
  double get pixels => devicePixelRatio / share;

  /// The same grid at the screen's pixels.
  Lattice get atScreen => share == 1 ? this : Lattice(devicePixelRatio, 1);

  /// The grid a copy on this one is drawn at in a target whose pixels hold
  /// [target] device pixels each: the coarser of the two. Drawn finer, its
  /// pixels would hold the product of both shares, more than either asked:
  /// glass frosting itself by 6 logical pixels, held at share 4 under a frost
  /// of 20, lies 16 levels off the scene copied at the screen's pixels drawn
  /// that way, and 8 at most drawn this way (host test, dpr 2).
  Lattice inside(int target) =>
      target <= share ? this : Lattice(devicePixelRatio, target);

  /// [rect] (logical pixels) grown to whole pixels of the copy.
  Rect snapOut(Rect rect) {
    final pixels = this.pixels;
    return Rect.fromLTRB(
      _floorPixels(rect.left * pixels) / pixels,
      _floorPixels(rect.top * pixels) / pixels,
      ceilPixels(rect.right * pixels) / pixels,
      ceilPixels(rect.bottom * pixels) / pixels,
    );
  }

  /// [rect] (logical pixels) in the screen's device pixels, grown to whole
  /// pixels of the copy: the layer a copy of it is drawn in.
  Rect toDevice(Rect rect) {
    final pixels = this.pixels;
    return Rect.fromLTRB(
      _floorPixels(rect.left * pixels) * share,
      _floorPixels(rect.top * pixels) * share,
      ceilPixels(rect.right * pixels) * share,
      ceilPixels(rect.bottom * pixels) * share,
    );
  }

  /// The copy's pixels across [rect], a rect [snapOut] returned.
  (int, int) pixelsOf(Rect rect) =>
      ((rect.width * pixels).round(), (rect.height * pixels).round());

  /// From the coordinates of a form's root, the screen's device pixels, to
  /// a copy of [rect], its top left at [origin]: one scale, and the layers'
  /// own transforms after it.
  ///
  /// Impeller sets text drawn at a translation and a scale alone on whole
  /// pixels of its target (impeller/entity/contents/text_contents.cc): text
  /// moving under glass would step a pixel of the copy, up to four of the
  /// screen's, at a time. Under a skew too small to see it lies where it is
  /// drawn, read from its atlas bilinearly.
  ///
  /// NEAR: under such a transform Impeller draws a glyph at its place from
  /// the atlas entry of its quarter of a pixel, which holds the glyph that
  /// quarter along already. Text in a copy lies right of where the page has
  /// it by the quarter of the copy's pixel it falls on, three quarters at
  /// most: 0, 1, 2 and 3 device pixels in a copy of four a side (host, dpr
  /// 3). Shapes and images lie within 0.2 device pixels. Text scrolled up or
  /// down keeps its quarter and moves evenly; text carried sideways under
  /// frosted glass steps back three quarters of a copy's pixel each pixel of
  /// the copy it travels.
  Matrix4 deviceToCopy(Rect rect, Offset origin) {
    final scale = 1 / share;
    final skew = share > 1 ? 1e-6 : 0.0;
    final left = rect.left * devicePixelRatio;
    final top = rect.top * devicePixelRatio;
    final matrix = Matrix4.zero();
    final storage = matrix.storage;
    storage[0] = scale;
    storage[1] = scale * skew;
    storage[5] = scale;
    storage[10] = 1;
    storage[12] = origin.dx - scale * left;
    storage[13] = origin.dy - scale * top - scale * skew * left;
    storage[15] = 1;
    return matrix;
  }

  /// The sigma, in device pixels, the shaders' taps frost a copy on this
  /// grid by for Impeller's blur by [sigma] screen logical pixels. The copy's
  /// own pixels already blur by what they hold, which a band holding glass
  /// that a filter draws, at the screen's pixels whatever was asked, holds
  /// less of. NEAR there: the taps lie up to 14 of its pixels apart, past the
  /// 3.5 a shader-frosted copy keeps to; under the scroll edge over glass the
  /// frost is 0.55 levels off the live read on average at 2.625 dpr and 0.41
  /// at 3 (host test).
  double residual(double sigma) =>
      sigma > 0 ? _frostResidual(sigma * devicePixelRatio, share: share) : 0;

  @override
  bool operator ==(Object other) =>
      other is Lattice &&
      other.devicePixelRatio == devicePixelRatio &&
      other.share == share;

  @override
  int get hashCode => Object.hash(devicePixelRatio, share);
}

/// What Impeller does to a layer a clip cuts, and the only code that knows:
/// it cuts the layer to the clip, and starts fragment coordinates at the cut,
/// only once the part it cuts off either axis is 30 % or more of what is left
/// (ComputeSaveLayerCoverage, impeller/entity/save_layer_utils.cc).
@internal
abstract final class ImpellerLayers {
  /// Whether Impeller draws a layer of [layer] whole inside a clip of
  /// [clip], both in the same space.
  static bool keepsWhole(Rect layer, Rect clip) {
    final cut = layer.intersect(clip);
    if (cut.isEmpty) return false;
    return (layer.width - cut.width) / cut.width < 0.3 &&
        (layer.height - cut.height) / cut.height < 0.3;
  }

  // Whether Impeller draws a copy of [layer] on [lattice] whole inside [clip]
  // (both logical pixels). It measures the layer as drawn: the whole pixels
  // it grows to can tip a layer just under the bound over it.
  static bool _keepsWholeOn(Lattice lattice, Rect layer, Rect clip) {
    final dpr = lattice.devicePixelRatio;
    return keepsWhole(
      lattice.toDevice(layer),
      Rect.fromLTRB(
        clip.left * dpr,
        clip.top * dpr,
        clip.right * dpr,
        clip.bottom * dpr,
      ),
    );
  }

  /// The layer that holds [band] inside [clip] (both logical pixels) on
  /// [lattice].
  ///
  /// The glass reads what lies past the clip, so the layer grows into the
  /// clip, empty, until the part cut off is less than Impeller's bound;
  /// where the clip leaves no room, it is cut to the clip. NEAR: there,
  /// glass reads the copy mirrored at the clip, up to 163 levels off over
  /// the 30 px of glass the host test leaves above such a clip.
  static Rect _layerIn(Rect band, Rect clip, Lattice lattice) {
    if (_keepsWholeOn(lattice, band, clip)) return band;
    // Along one axis: the span from [lo] to [hi] grown inside [from, to].
    (double, double)? grow(double lo, double hi, double from, double to) {
      final cut = max(from - lo, 0) + max(hi - to, 0);
      final inside = min(hi, to) - max(lo, from);
      if (inside <= 0) return null;
      // A margin below 30 % keeps rounding off the threshold.
      final wanted = cut / 0.28;
      if (inside >= wanted) return (lo, hi);
      if (lo < from && hi > to) return null;
      if (lo < from) {
        final end = max(lo, from) + wanted;
        return end <= to ? (lo, end) : null;
      }
      final start = min(hi, to) - wanted;
      return start >= from ? (start, hi) : null;
    }

    final x = grow(band.left, band.right, clip.left, clip.right);
    final y = grow(band.top, band.bottom, clip.top, clip.bottom);
    if (x == null || y == null) {
      return lattice.snapOut(band.intersect(clip));
    }
    final grown = lattice.snapOut(Rect.fromLTRB(x.$1, y.$1, x.$2, y.$2));
    return _keepsWholeOn(lattice, grown, clip)
        ? grown
        : lattice.snapOut(band.intersect(clip));
  }

  /// A device pixel at the top left and one at the bottom right of [layer]
  /// (logical pixels): a clip path that covers them too keeps its bounds at
  /// the layer's, so Impeller does not cut the layer.
  static (Rect, Rect) pinsOf(Rect layer, double devicePixelRatio) {
    final pixel = 1 / devicePixelRatio;
    return (
      layer.topLeft & Size.square(pixel),
      Rect.fromPoints(
        layer.bottomRight - Offset(pixel, pixel),
        layer.bottomRight,
      ),
    );
  }
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
/// the copy it reaches (frostLattice in frost.glsl), where the glass's own
/// taps are sparse: a point under the glass stays one point, and white bars
/// lie 8 to 13 levels from what reading the backdrop draws at a frost of 5
/// to 12, against 17 to 27 through the taps (host test, dpr 1). On a Pixel
/// 6a, in-launch pairs: main pass -0.50 ms a frame over photos, for one more
/// pass and +0.4 ms on the raster thread.
@internal
double bakedFrost({
  required int share,
  required bool holdsGlass,
  required double glassFrost,
  required double? bandFrost,
}) {
  if (share < 2 || holdsGlass) return 0;
  if (bandFrost != null && bandFrost < glassFrost) return 0;
  return glassFrost > 0 ? glassFrost : bandFrost ?? 0;
}

/// Where one read's backdrop pixels lie: on which lattice, at which rects
/// and with which frost. Compile resolves it, the ledger compares it, emit
/// lays it out and sites read it; nothing decides any of it again.
@internal
@immutable
final class ReadGeometry {
  const ReadGeometry._({
    required this.lattice,
    required this.reads,
    required this.band,
    required this.layer,
    required this.clip,
    required this.bakedFrost,
    required this.frostLeftOut,
    required this.filter,
    this.room,
    this.imageRect,
  });

  /// The geometry of a read asking [reads] of a copy on [asked], led under
  /// [clip], on [screen] (logical pixels).
  ///
  /// A copy that holds glass drawn at the screen's pixels lands on the
  /// screen's lattice ([atScreen]).
  factory ReadGeometry.resolve({
    required Lattice asked,
    required bool atScreen,
    required Rect reads,
    required Rect screen,
    required Rect? clip,
    required double bakedFrost,
    required double frostLeftOut,
    required Object? filter,
  }) {
    final lattice = atScreen ? asked.atScreen : asked;
    final band = lattice.snapOut(reads).intersect(screen);
    final cut = clip?.intersect(screen);
    final layer = switch (cut) {
      null => band,
      // A smaller copy lies in its layer's corner, which a layer grown past
      // the clip leaves outside it, and Impeller draws none of the copy there
      // (host test): the layer starts inside the clip. NEAR: glass reads what
      // lies past the clip mirrored at it, as where a clip leaves no room to
      // grow.
      _ when lattice.share > 1 => lattice.snapOut(band.intersect(cut)),
      _ => ImpellerLayers._layerIn(band, cut, lattice),
    };
    return ReadGeometry._(
      lattice: lattice,
      reads: reads.intersect(screen),
      band: band,
      layer: layer,
      clip: cut,
      bakedFrost: bakedFrost,
      frostLeftOut: frostLeftOut,
      filter: filter,
    );
  }

  /// The lattice the copy is drawn on.
  final Lattice lattice;

  /// What the read asks of the copy, on the screen.
  final Rect reads;

  /// What the copy holds: [reads] grown to whole copy pixels, on the screen.
  final Rect band;

  /// The rect of the layer the copy is drawn in: [band], grown where a clip
  /// would cut the layer, or the part of it inside a clip that leaves no
  /// room to grow or that cuts a copy smaller than the screen.
  final Rect layer;

  /// The clip around the read's lead, on the screen.
  final Rect? clip;

  /// The frost the copy holds, in logical pixels (see [bakedFrost]).
  final double bakedFrost;

  /// The widest frost of a band left out of the copy under glass that
  /// frosts as wide, which the glass adds to its own, in logical pixels.
  final double frostLeftOut;

  /// Equal while the page filter the copy is drawn through draws alike, null
  /// for none.
  final Object? filter;

  /// The room an image of the read takes, as the plan chose it, or null for a
  /// copy drawn in the frame.
  final Rect? room;

  /// What an image of the read holds: [room] grown to whole copy pixels, on
  /// the screen.
  final Rect? imageRect;

  /// This geometry for an image of [room], on [screen].
  ReadGeometry withRoom(Rect room, Rect screen) => ReadGeometry._(
    lattice: lattice,
    reads: reads,
    band: band,
    layer: layer,
    clip: clip,
    bakedFrost: bakedFrost,
    frostLeftOut: frostLeftOut,
    filter: filter,
    room: room,
    imageRect: lattice.snapOut(room).intersect(screen),
  );

  /// The frost, in logical pixels, that stands for [sigma] over what the
  /// copy left out.
  double frostFor(double sigma) => sigma > 0 && frostLeftOut > 0
      ? sqrt(sigma * sigma + frostLeftOut * frostLeftOut)
      : sigma;

  /// The part of [layer] to draw inside the copy of [outer], which holds
  /// this read's glass.
  ///
  /// A smaller copy starts inside the band of the read holding it, cut by
  /// [clip], as [layer] does inside a clip: it lies in its layer's corner,
  /// which the cut would leave outside, and on Metal the glass over it then
  /// reads black (iPhone 16 Pro, a sheet moving over glass; Vulkan does not
  /// show it). NEAR: glass reads what lies past the cut mirrored at it, under
  /// the frost of the read holding it.
  Rect heldIn(ReadGeometry outer) {
    final clip = this.clip;
    final held = clip == null ? outer.band : outer.band.intersect(clip);
    return lattice.share == 1 &&
            ImpellerLayers._keepsWholeOn(lattice, layer, held)
        ? layer
        : held;
  }

  /// Whether a copy at this geometry draws what one at [other] draws over
  /// the same backdrop: the same frost held and left out, through the same
  /// page filter.
  bool drawsLike(ReadGeometry other) =>
      bakedFrost == other.bakedFrost &&
      frostLeftOut == other.frostLeftOut &&
      filter == other.filter;

  /// Whether an image drawn at this geometry serves a read at [next]: it
  /// draws alike on the same lattice, and its room holds all [next] reads.
  bool servesAsImage(ReadGeometry next) {
    final room = this.room;
    return room != null &&
        lattice == next.lattice &&
        drawsLike(next) &&
        encloses(room, next.reads);
  }
}
