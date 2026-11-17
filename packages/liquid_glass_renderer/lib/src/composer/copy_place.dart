import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/composer/impeller.dart';
import 'package:liquid_glass_renderer/src/composer/read_geometry.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// How `backdrop_frost.frag` reads a copy, in the texture's pixels.
@internal
@immutable
final class FrostSampling {
  /// Creates the sampling.
  const FrostSampling({
    required this.size,
    required this.bounds,
    required this.frost,
    required this.scale,
    required this.shown,
    this.dissolve = FrostDissolve.none,
  });

  /// uSize: the size of the texture the shader reads, in its pixels.
  final Size size;

  /// uBounds: the copy in the texture, in the copy's pixels, half a pixel
  /// in from its edge.
  final Rect bounds;

  /// uFrost: the sigma, in the copy's pixels, the taps frost it by.
  final double frost;

  /// uScale: the copy's pixels per fragment.
  final double scale;

  /// uShown: the fragments the frost covers.
  final Rect shown;

  /// uDissolve: the fragment rows between which the frost dissolves.
  final FrostDissolve dissolve;
}

/// The rows between which a frost dissolves into what lies under it: whole
/// at [whole], gone at [gone], smoothly between them.
@internal
@immutable
final class FrostDissolve {
  /// Creates the rows.
  const FrostDissolve(this.whole, this.gone);

  /// The rows of a frost that is whole everywhere.
  static const none = FrostDissolve(-99999, -100000);

  /// The row where the frost is whole.
  final double whole;

  /// The row where the frost is gone.
  final double gone;

  /// Whether the frost is whole everywhere.
  bool get isNone => whole == none.whole && gone == none.gone;

  /// The rows moved by [offset] and then scaled by [scale].
  FrostDissolve mapped(double offset, double scale) => isNone
      ? this
      : FrostDissolve((whole + offset) * scale, (gone + offset) * scale);

  /// How much of the frost shows at [row].
  double at(double row) {
    final t = ((row - gone) / (whole - gone)).clamp(0.0, 1.0);
    return t * t * t * (t * (t * 6 - 15) + 10);
  }

  @override
  bool operator ==(Object other) =>
      other is FrostDissolve && other.whole == whole && other.gone == gone;

  @override
  int get hashCode => Object.hash(whole, gone);
}

/// Where a copy's haze mixes into it: the part of its texture the copy
/// fills (`copy`, from the top left), where the copy lies in it (`rect`),
/// the texture's pixels per logical pixel (`pixels`), and the size of the
/// layers that mix it (`size`: the copy and its strip below it).
typedef HazeLayout = ({Size copy, Rect rect, double pixels, Size size});

/// The haze layout of a copy that fills [copy] of its texture, lying at
/// [rect] of it, [pixels] to a logical pixel.
@internal
HazeLayout hazeLayoutOf(
  LiquidGlassHaze haze, {
  required Size copy,
  required Rect rect,
  required double pixels,
}) {
  final strip = HazeStrip(haze.sigma * pixels, copy);
  return (
    copy: copy,
    rect: rect,
    pixels: pixels,
    size: Size(
      max(copy.width, strip.across.toDouble()),
      copy.height + strip.rows,
    ),
  );
}

/// One read's copy laid out in one texture: where the copy lies in it, which
/// fragments of a draw over it read which of its pixels, and what frost the
/// reads still add.
///
/// A fragment of glass over the copy stands for a device pixel of the screen
/// counted from [zero], or for a pixel of a coarser target ([CornerPlace]),
/// and reads the texture's pixel `fragment / share`, the copy's own pixels
/// starting at [at]. So `zero + at * share` is where the copy's top left lies
/// on the screen, in device pixels, in both layouts.
@internal
@immutable
sealed class CopyPlace {
  const CopyPlace._(this.geometry);

  /// Where the read's pixels lie.
  final ReadGeometry geometry;

  /// How many device pixels along each side one of the copy's pixels holds
  /// in this texture.
  int get gridStep;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio => geometry.devicePixelRatio;

  /// Where fragment zero of a draw over the texture lies on the screen, in
  /// device pixels.
  Offset get zero;

  /// How many fragments of a draw over the texture along each side one of
  /// its pixels holds.
  int get share;

  /// Where the copy's top left lies in the texture, in its pixels.
  Offset get at;

  /// The texture's pixels per logical pixel.
  double get pixels => devicePixelRatio / share;

  /// The part of the screen the copy's content is replayed from.
  DeviceBox get replayed;

  /// The sigma, in device pixels, the shaders' taps frost the copy by for
  /// Impeller's blur by [frost] logical pixels of glass.
  double residual(double frost) =>
      geometry.residualAt(gridStep, geometry.frostFor(frost));

  /// The sigma, in device pixels, taps still frost the copy that holds
  /// [held] by for Impeller's blur by [frost] (both logical pixels): none
  /// where the copy holds that frost.
  double tapFrost(double frost, {required double held}) {
    assert(
      held == 0 || frost == held,
      'A copy that holds a frost is read for that frost.',
    );
    return frost == held ? 0 : residual(frost);
  }

  /// The fragments of a draw over the texture that [shown] (screen logical
  /// pixels) covers, or null where none of it lies in the texture.
  Rect? fragmentsOf(Rect shown);

  /// From the coordinates of a form's root, the screen's device pixels, to
  /// the copy drawn with its top left at [origin] of the texture: one scale,
  /// and the layers' own transforms after it. Under a coarser copy the scale
  /// carries [ImpellerLayers.glyphSkew].
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
  Matrix4 deviceToCopy(Offset origin) {
    final scale = 1 / share;
    final skew = share > 1 ? ImpellerLayers.glyphSkew : 0.0;
    final left = replayed.left;
    final top = replayed.top;
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
}

/// A copy in the top-left share of a layer of a target's pixels: the frame
/// itself, or a coarser copy that holds the read's glass. A filter on the
/// layer sees fragments of the target's pixels from the layer's corner.
///
/// NEAR: past the copy the layer is empty, and reads mirror at the copy's
/// edge.
@internal
final class CornerPlace extends CopyPlace {
  CornerPlace._(
    super.geometry,
    this.cut,
    this.scale,
    this.under,
    this.device,
  ) : super._();

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerPlace.inFrame(ReadGeometry geometry) {
    assert(
      !geometry.layer.isEmpty,
      'A read that draws holds some of the screen.',
    );
    return CornerPlace._(
      geometry,
      geometry.layerRect,
      1,
      geometry.clip,
      geometry.layer,
    );
  }

  /// The copy of [geometry] where it lies inside the copy of [outer], which
  /// holds its glass, or null where none of it does.
  ///
  /// It is drawn at the coarser of the two copies' pixels. Drawn finer, its
  /// pixels would hold the product of both shares, more than either asked:
  /// glass frosting itself by 6 logical pixels, held at share 4 under a frost
  /// of 20, lies 16 levels off the scene copied at the screen's pixels drawn
  /// that way, and 8 at most drawn this way (host test, dpr 2).
  static CornerPlace? heldIn(ReadGeometry geometry, ReadGeometry outer) {
    final cut = geometry.heldIn(outer).intersect(geometry.layerRect);
    if (cut.isEmpty) return null;
    final footprint = outer.footprintRect;
    final scale = outer.step;
    return CornerPlace._(
      geometry,
      cut,
      scale,
      geometry.clip?.intersect(footprint) ?? footprint,
      geometry.view.cover(cut, step: max(geometry.step, scale)),
    );
  }

  /// The part of the copy's layer read, in the screen's logical pixels.
  final Rect cut;

  /// How many device pixels one pixel of the target the layer is drawn into
  /// stands for.
  final int scale;

  /// The clip the layer is drawn under, in the screen's logical pixels, or
  /// null for none.
  final Rect? under;

  /// The layer, in the screen's device pixels, on the copy's pixels in the
  /// target: a layer off the target's pixels starts its fragments at the
  /// pixel it is rounded out to.
  final DeviceBox device;

  @override
  int get gridStep => max(geometry.step, scale);

  @override
  Offset get zero => device.topLeft;

  @override
  int get share => gridStep ~/ scale;

  @override
  DeviceBox get replayed => geometry.footprint;

  @override
  Offset get at => Offset(
    (geometry.footprint.left - device.left) / share,
    (geometry.footprint.top - device.top) / share,
  );

  Size get _footprintPixels => geometry.footprint.size / share.toDouble();

  /// The screen rect (logical pixels) past which the read holds nothing.
  Rect get holds =>
      geometry.view.logical(device).intersect(geometry.footprintRect);

  @override
  Rect? fragmentsOf(Rect shown) {
    final drawn = shown.intersect(cut);
    if (drawn.isEmpty) return null;
    return drawn.scaled(devicePixelRatio).shift(-device.topLeft);
  }

  /// The part of the layer the copy's own pixels fill, in the layer's own
  /// pixels.
  Size get copySize {
    final at = this.at;
    final footprint = _footprintPixels;
    return Size(
      min((max(at.dx, 0) + footprint.width).ceilToDouble(), device.width),
      min((max(at.dy, 0) + footprint.height).ceilToDouble(), device.height),
    );
  }

  /// The rect the copy fills in the layer, in the layer's own pixels.
  Rect get copyRect {
    final at = this.at;
    final size = copySize;
    final footprint = _footprintPixels;
    return Rect.fromLTRB(
      max(at.dx, 0),
      max(at.dy, 0),
      min(at.dx + footprint.width, size.width),
      min(at.dy + footprint.height, size.height),
    );
  }

  /// The frost, in logical pixels, drawn into the copy where it lies in
  /// the layer ([ReadGeometry.bakedIn]).
  double get baked => geometry.bakedIn(scale);

  /// How `backdrop_frost.frag` frosts the copy in place by [baked], at its
  /// own pixels.
  FrostSampling get inPlace {
    final size = copySize;
    return FrostSampling(
      size: size,
      bounds: copyRect.deflate(0.5),
      frost: residual(baked) / share,
      scale: 1,
      shown: Offset.zero & size,
    );
  }

  /// How `backdrop_frost.frag` reads the layer, [size] of it, to cover
  /// [shown] (screen logical pixels) pixel by pixel, frosted by [tap]
  /// device pixels, or null where none of [shown] lies in it.
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling? frostSampling(
    Rect shown,
    double tap, {
    required Size size,
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final fragments = fragmentsOf(shown);
    if (fragments == null) return null;
    final at = this.at;
    final footprint = _footprintPixels;
    return FrostSampling(
      size: size,
      bounds: Rect.fromLTRB(
        max(at.dx, 0) + 0.5,
        max(at.dy, 0) + 0.5,
        min(at.dx + footprint.width, device.width / share) - 0.5,
        min(at.dy + footprint.height, device.height / share) - 0.5,
      ),
      frost: tap / share,
      scale: 1 / share,
      shown: fragments,
      dissolve: dissolve.mapped(0, devicePixelRatio).mapped(-device.top, 1),
    );
  }

  /// Where the copy's haze mixes into it, counted in the target's pixels,
  /// or null where it has none.
  ///
  /// The geometry leaves the haze of a copy at the screen's pixels its rows
  /// in the layer. A coarser copy, or one drawn inside another copy, grows
  /// its layer down by them here, past the clip it is drawn under where it
  /// must. Where the layer with them would not keep its corner
  /// ([ImpellerLayers.keepsCorner]), the copy is drawn with no haze. Cut at
  /// its bottom or right alone a layer only loses the strip, which the mix
  /// sees.
  late final HazeLayout? haze = () {
    final haze = geometry.haze;
    if (haze == null) return null;
    final copySize = this.copySize;
    final layout = hazeLayoutOf(
      haze,
      copy: Size(
        (copySize.width / scale).ceilToDouble(),
        (copySize.height / scale).ceilToDouble(),
      ),
      rect: copyRect.scaled(1 / scale),
      pixels: pixels / scale,
    );
    return _keepsCorner(layout.size * scale.toDouble()) ? layout : null;
  }();

  bool _keepsCorner(Size size) => switch (under) {
    final under? => ImpellerLayers.keepsCorner(
      device.topLeft & sizeWith(size),
      under.scaled(devicePixelRatio),
    ),
    null => true,
  };

  /// The layer's size in device pixels where layers of [size] lie in it
  /// from its corner: the part of the screen it covers, and under it the
  /// rows of a haze's strip where the layer has none for them.
  Size sizeWith(Size size) => Size(
    max(device.width, size.width),
    max(device.height, size.height),
  );

  /// Where the copy's top left lies in the layer's coordinates.
  Offset get copyOrigin => device.topLeft + at;

  /// The rect the copy fills at [copyOrigin], inside [within].
  Rect copyIn(Rect within) => (copyOrigin & _footprintPixels).intersect(within);
}

/// A copy at an offset in an image of the copy's own pixels, which glass
/// stretches over the screen's.
@internal
final class PagePlace extends CopyPlace {
  /// The page of [geometry] at [at] in an image.
  const PagePlace(super.geometry, this.at) : super._();

  /// The size of a page of [geometry], in the image's pixels.
  static (int, int) sizeOf(ReadGeometry geometry) =>
      geometry.imageBox!.pixelsOn(geometry.step);

  @override
  final Offset at;

  @override
  int get gridStep => geometry.step;

  @override
  int get share => geometry.step;

  @override
  DeviceBox get replayed => geometry.imageBox!;

  /// The screen rect the page holds, in logical pixels.
  Rect get rect => geometry.imageRect!;

  @override
  Offset get zero => replayed.topLeft - at * share.toDouble();

  @override
  Rect fragmentsOf(Rect shown) =>
      shown.intersect(rect).scaled(devicePixelRatio).shift(-zero);

  /// [shown] (screen logical pixels) in the image's pixels.
  Rect texelsOf(Rect shown) {
    final rect = this.rect;
    final pixels = this.pixels;
    return Rect.fromLTRB(
      (shown.left - rect.left) * pixels + at.dx,
      (shown.top - rect.top) * pixels + at.dy,
      (shown.right - rect.left) * pixels + at.dx,
      (shown.bottom - rect.top) * pixels + at.dy,
    );
  }

  /// How `backdrop_frost.frag` reads the image of [image] pixels to frost
  /// the page by [tap] device pixels, drawn under a canvas that takes the
  /// screen to the image.
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling frostSampling(
    Size image,
    double tap, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final rect = this.rect;
    final page = replayed.size / share.toDouble();
    return FrostSampling(
      size: image,
      bounds: Rect.fromLTRB(
        at.dx + 0.5,
        at.dy + 0.5,
        at.dx + page.width - 0.5,
        at.dy + page.height - 0.5,
      ),
      frost: tap / share,
      scale: 1,
      // The rect drawn bounds the frost.
      shown: Rect.largest,
      dissolve: dissolve.mapped(-rect.top, pixels).mapped(at.dy, 1),
    );
  }

  /// The page's size in the image, in its pixels.
  Size get size {
    final (width, height) = sizeOf(geometry);
    return Size(width.toDouble(), height.toDouble());
  }

  /// Where the page lies in the image.
  Rect get bounds => at & size;

  /// How `backdrop_frost.frag` frosts the page in place by
  /// [ReadGeometry.bakedIn], at its own pixels.
  FrostSampling get inPlace {
    final size = this.size;
    return FrostSampling(
      size: size,
      bounds: Rect.fromLTRB(0.5, 0.5, size.width - 0.5, size.height - 0.5),
      frost: residual(geometry.bakedIn(1)) / share,
      scale: 1,
      shown: Offset.zero & size,
    );
  }

  /// Where the page's haze mixes into it, or null where it has none.
  HazeLayout? get haze => switch (geometry.haze) {
    final haze? => hazeLayoutOf(
      haze,
      copy: size,
      rect: Offset.zero & size,
      pixels: pixels,
    ),
    null => null,
  };

  /// From the screen's logical pixels to the page's place in the image.
  Matrix4 get screenToImage {
    final rect = this.rect;
    final pixels = this.pixels;
    return Matrix4.translationValues(
      at.dx - rect.left * pixels,
      at.dy - rect.top * pixels,
      0,
    )..scaleByDouble(pixels, pixels, 1, 1);
  }
}
