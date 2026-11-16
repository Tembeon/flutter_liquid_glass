import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/composer/impeller.dart';
import 'package:liquid_glass_renderer/src/composer/read_geometry.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
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

  /// uFrost: the sigma, in the copy's pixels, the taps frost it by, as
  /// [CopyPlace.tapFrost] says.
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

/// One read's copy laid out in one texture: the only code that says where
/// the copy lies in it, which fragments of a draw over it read which of its
/// pixels, how large the texture is, and what frost the reads still add.
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

  /// The grid the copy's pixels are on in this texture.
  Lattice get grid;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio => grid.devicePixelRatio;

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

  /// The sigma, in device pixels, the shaders' taps frost the copy by for
  /// Impeller's blur by [frost] logical pixels of glass.
  double residual(double frost) => grid.residual(geometry.frostFor(frost));

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
}

/// A copy in the top-left share of a layer of a target's pixels: the frame
/// itself, or a coarser copy that holds the read's glass. A filter on the
/// layer sees fragments of the target's pixels from the layer's corner.
///
/// NEAR: past the copy the layer is empty, and reads mirror at the copy's
/// edge.
@internal
final class CornerPlace extends CopyPlace {
  /// The part [cut] of [geometry]'s layer (screen logical pixels), drawn
  /// into a target whose pixels each stand for [scale] device pixels, under
  /// [under] (screen logical pixels), or under no clip.
  CornerPlace(super.geometry, this.cut, this.scale, this.under)
    : grid = geometry.gridIn(scale),
      super._();

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerPlace.inFrame(ReadGeometry geometry) {
    assert(
      !geometry.layer.isEmpty,
      'A read that draws holds some of the screen.',
    );
    return CornerPlace(geometry, geometry.layer, 1, geometry.clip);
  }

  /// The part of the copy's layer read, in the screen's logical pixels.
  final Rect cut;

  /// How many device pixels one pixel of the target the layer is drawn into
  /// stands for.
  final int scale;

  /// The clip the layer is drawn under, in the screen's logical pixels, or
  /// null for none.
  final Rect? under;

  /// The grid the copy is drawn at: its own, or the target's where that is
  /// coarser.
  @override
  final Lattice grid;

  /// The layer, in the screen's device pixels, on [grid]: a layer off the
  /// target's pixels starts its fragments at the pixel it is rounded out to.
  late final Rect device = grid.toDevice(cut);

  @override
  Offset get zero => device.topLeft;

  /// The device pixels along each side one pixel of the layer holds of the
  /// copy, past the target's own.
  @override
  int get share => grid.share ~/ scale;

  @override
  Offset get at => Offset(
    (geometry.band.left * devicePixelRatio - device.left) / share,
    (geometry.band.top * devicePixelRatio - device.top) / share,
  );

  /// The screen rect (logical pixels) past which the read holds nothing.
  Rect get holds => Rect.fromLTRB(
    device.left / devicePixelRatio,
    device.top / devicePixelRatio,
    device.right / devicePixelRatio,
    device.bottom / devicePixelRatio,
  ).intersect(geometry.band);

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
    final band = geometry.band;
    final pixels = this.pixels;
    return Size(
      min(ceilPixels(max(at.dx, 0) + band.width * pixels), device.width),
      min(ceilPixels(max(at.dy, 0) + band.height * pixels), device.height),
    );
  }

  /// The rect the copy fills in the layer, in the layer's own pixels.
  Rect get copyRect {
    final at = this.at;
    final size = copySize;
    final band = geometry.band;
    final pixels = this.pixels;
    return Rect.fromLTRB(
      max(at.dx, 0),
      max(at.dy, 0),
      min(at.dx + band.width * pixels, size.width),
      min(at.dy + band.height * pixels, size.height),
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
    final band = geometry.band;
    final pixels = this.pixels;
    return FrostSampling(
      size: size,
      bounds: Rect.fromLTRB(
        max(at.dx, 0) + 0.5,
        max(at.dy, 0) + 0.5,
        min(at.dx + band.width * pixels, device.width / share) - 0.5,
        min(at.dy + band.height * pixels, device.height / share) - 0.5,
      ),
      frost: tap / share,
      scale: 1 / share,
      shown: fragments,
      dissolve: dissolve.mapped(0, devicePixelRatio).mapped(-device.top, 1),
    );
  }

  /// Where the copy's haze mixes into it, counted in the target's pixels,
  /// or null where it has none or its layers would cut the layer from its
  /// corner.
  ///
  /// A read's geometry leaves a haze its rows in the layer; a layer drawn
  /// inside another copy, or one of a few pixels, has none, and grows down by
  /// them, past the clip it is drawn under where it must: they are a small
  /// part of the layer, which Impeller then still draws whole
  /// ([ImpellerLayers.keepsWhole]). A layer that already lies past the clip
  /// at its top or left as far as Impeller lets it would be cut to the clip
  /// with them, and start at another pixel than the glass reads it from: it
  /// is drawn with no haze. Cut at its bottom or right alone a layer only
  /// loses the strip, which the mix sees.
  late final HazeLayout? haze = () {
    final haze = geometry.haze;
    if (haze == null) return null;
    final copySize = this.copySize;
    final layout = hazeLayoutOf(
      haze,
      copy: Size(
        ceilPixels(copySize.width / scale),
        ceilPixels(copySize.height / scale),
      ),
      rect: copyRect.scaled(1 / scale),
      pixels: pixels / scale,
    );
    return _keepsCorner(layout.size * scale.toDouble()) ? layout : null;
  }();

  bool _keepsCorner(Size size) {
    final under = this.under;
    if (under == null) return true;
    final bounds = under.scaled(devicePixelRatio);
    if (device.left >= bounds.left && device.top >= bounds.top) return true;
    return ImpellerLayers.keepsWhole(device.topLeft & sizeWith(size), bounds);
  }

  /// The layer's size in device pixels where layers of [size] lie in it
  /// from its corner: the part of the screen it covers, and under it the
  /// rows of a haze's strip where the layer has none for them.
  Size sizeWith(Size size) => Size(
    max(device.width, size.width),
    max(device.height, size.height),
  );

  /// Where the copy's top left lies in the layer's coordinates.
  Offset get copyOrigin => device.topLeft + at;

  /// The grid the copy's content is replayed at in the layer.
  Lattice get replayGrid => geometry.copyIn(scale);
}

/// A copy at an offset in an image of the copy's own pixels, which glass
/// stretches over the screen's.
@internal
final class PagePlace extends CopyPlace {
  /// The page of [geometry] at [at] in an image.
  const PagePlace(super.geometry, this.at) : super._();

  /// The size of a page of [geometry], in the image's pixels.
  static (int, int) sizeOf(ReadGeometry geometry) =>
      geometry.lattice.pixelsOf(geometry.imageRect!);

  @override
  final Offset at;

  @override
  Lattice get grid => geometry.lattice;

  @override
  int get share => grid.share;

  /// The screen rect the page holds, in logical pixels.
  Rect get rect => geometry.imageRect!;

  @override
  Offset get zero => rect.topLeft * devicePixelRatio - at * share.toDouble();

  @override
  Rect fragmentsOf(Rect shown) =>
      shown.intersect(rect).scaled(devicePixelRatio).shift(-zero);

  /// [shown] (screen logical pixels) in the image's pixels.
  Rect texelsOf(Rect shown) {
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
    final pixels = this.pixels;
    return FrostSampling(
      size: image,
      bounds: Rect.fromLTRB(
        at.dx + 0.5,
        at.dy + 0.5,
        at.dx + rect.width * pixels - 0.5,
        at.dy + rect.height * pixels - 0.5,
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
    final pixels = this.pixels;
    return Matrix4.translationValues(
      at.dx - rect.left * pixels,
      at.dy - rect.top * pixels,
      0,
    )..scaleByDouble(pixels, pixels, 1, 1);
  }
}
