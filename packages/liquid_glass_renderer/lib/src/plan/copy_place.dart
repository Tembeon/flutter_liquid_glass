import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
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
    required this.texelsPerFragment,
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
  final double texelsPerFragment;

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

  /// The rows moved by [offset] and then scaled by [factor].
  FrostDissolve mapped(double offset, double factor) => isNone
      ? this
      : FrostDissolve((whole + offset) * factor, (gone + offset) * factor);

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

/// One read's copy laid out in one texture: where the copy lies in it, which
/// fragments of a draw over it read which of its pixels, and what frost the
/// reads still add.
///
/// A fragment of glass over the copy stands for a device pixel of the screen
/// counted from [zero], or for a pixel of a coarser target ([CornerPlace]), and
/// reads the texture's pixel `fragment / fragmentsPerTexel`, the copy's own
/// pixels starting at [at]. So `zero + at * fragmentsPerTexel` is where the
/// copy's top left lies on the screen, in device pixels, in both layouts.
@internal
@immutable
sealed class CopyPlace {
  const CopyPlace._(this.layout);

  /// Where the read's pixels lie.
  final ReadLayout layout;

  /// How many device pixels along each side one of the copy's pixels holds
  /// in this texture.
  int get share;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio => layout.view.devicePixelRatio;

  /// Where fragment zero of a draw over the texture lies on the screen, in
  /// device pixels.
  Offset get zero;

  /// How many fragments of a draw over the texture along each side one of
  /// its pixels holds.
  int get fragmentsPerTexel;

  /// Where the copy's top left lies in the texture, in its pixels.
  Offset get at;

  /// The copy's pixels per logical pixel.
  double get pixels => devicePixelRatio / share;

  /// [device], a point of the screen in device pixels, counted in the copy's
  /// pixels.
  Offset _onScreen(Offset device) => Offset(
    (device.dx / share).roundToDouble(),
    (device.dy / share).roundToDouble(),
  );

  /// The part of the screen the copy's content is replayed from.
  DeviceBox get replayed;

  /// Where the copy's levels lie beside it, from [levelAt], or null where
  /// it carries none.
  LevelStrip? get levels;

  /// Where the copy's top left lies in the texture its levels lie in, in its
  /// pixels: where its strip of levels starts from.
  Offset get levelAt;

  LevelStrip _stripOf(CopyLevels levels, Size copy) => LevelStrip(
    levels,
    pixels: pixels,
    boxed: share > 1,
    copy: copy,
    grid: _onScreen(zero) + levelAt,
  );

  /// The sigma, in device pixels, the shaders' taps frost the copy by for
  /// Impeller's blur by [frost] logical pixels of glass.
  double residual(double frost) =>
      layout.residualAt(share, layout.frostFor(frost));

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

  /// The frost, in logical pixels, drawn into the copy where it lies
  /// ([ReadLayout.bakedIn]).
  double get baked;

  // What a filter over the copy where it lies reads: the size of its input
  // and the rect of it the copy fills, in the copy's own pixels.
  (Size, Rect) get _inPlaceInput;

  /// How `backdrop_frost.frag` frosts the copy in place by [baked], at its
  /// own pixels.
  FrostSampling get inPlace {
    final (size, rect) = _inPlaceInput;
    return FrostSampling(
      size: size,
      bounds: rect.deflate(0.5),
      frost: residual(baked) / fragmentsPerTexel,
      texelsPerFragment: 1,
      shown: Offset.zero & size,
    );
  }

  /// From the coordinates of a form's root, the screen's device pixels, to
  /// the copy drawn with its top left at [origin] of the texture: one scale,
  /// and the layers' own transforms after it. Under a coarser copy the scale
  /// carries [ImpellerLayers.glyphSkew].
  ///
  /// NEAR: under such a transform Impeller draws a glyph at its place from
  /// the atlas entry of its quarter of a pixel, which holds the glyph that
  /// quarter along already. Text in a copy lies right of where the screen has
  /// it by the quarter of the copy's pixel it falls on, three quarters at
  /// most: 0, 1, 2 and 3 device pixels in a copy of four a side (host, dpr
  /// 3). Shapes and images lie within 0.2 device pixels. Text scrolled up or
  /// down keeps its quarter and moves evenly; text carried sideways under
  /// frosted glass steps back three quarters of a copy's pixel each pixel of
  /// the copy it travels.
  Matrix4 deviceToCopy(Offset origin) {
    final perFragment = 1 / fragmentsPerTexel;
    final skew = fragmentsPerTexel > 1 ? ImpellerLayers.glyphSkew : 0.0;
    final left = replayed.left;
    final top = replayed.top;
    final matrix = Matrix4.zero();
    final storage = matrix.storage;
    storage[0] = perFragment;
    storage[1] = perFragment * skew;
    storage[5] = perFragment;
    storage[10] = 1;
    storage[12] = origin.dx - perFragment * left;
    storage[13] = origin.dy - perFragment * top - perFragment * skew * left;
    storage[15] = 1;
    return matrix;
  }
}

/// A copy in the top-left corner of a layer of a target's pixels: the frame
/// itself, or a coarser copy that holds the read's glass. A filter on the
/// layer sees fragments of the target's pixels from the layer's corner.
///
/// NEAR: past the copy the layer is empty, and reads mirror at the copy's
/// edge.
@internal
final class CornerPlace extends CopyPlace {
  CornerPlace._(
    super.layout,
    this.cut,
    this.targetShare,
    this.under,
    this.device,
  ) : super._();

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerPlace.inFrame(ReadLayout layout) {
    assert(
      !layout.layer.isEmpty,
      'A read that draws holds some of the screen.',
    );
    return CornerPlace._(
      layout,
      layout.layerRect,
      1,
      layout.clip,
      layout.layer,
    );
  }

  /// The copy of [layout] where it lies inside the copy of [outer], which
  /// holds its glass, or null where none of it does.
  ///
  /// It is drawn at the coarser of the two copies' pixels. Drawn finer, its
  /// pixels would hold the product of both shares: glass frosting itself by
  /// 6 logical pixels, held at a share of 4 under a frost of 20, lies 16
  /// levels off the scene copied at the screen's pixels that way, and 8 at
  /// most this way (host test, dpr 2).
  static CornerPlace? heldIn(ReadLayout layout, ReadLayout outer) {
    final cut = layout.heldIn(outer).intersect(layout.layerRect);
    if (cut.isEmpty) return null;
    final footprint = outer.footprintRect;
    final targetShare = outer.share;
    return CornerPlace._(
      layout,
      cut,
      targetShare,
      layout.clip?.intersect(footprint) ?? footprint,
      layout.view.cover(cut, share: max(layout.share, targetShare)),
    );
  }

  /// The part of the copy's layer read, in the screen's logical pixels.
  final Rect cut;

  /// How many device pixels one pixel of the target the layer is drawn into
  /// stands for.
  final int targetShare;

  /// The clip the layer is drawn under, in the screen's logical pixels, or
  /// null for none.
  final Rect? under;

  /// The layer, in the screen's device pixels, on the copy's pixels in the
  /// target: a layer off the target's pixels starts its fragments at the
  /// pixel it is rounded out to.
  final DeviceBox device;

  @override
  int get share => max(layout.share, targetShare);

  @override
  Offset get zero => device.topLeft;

  @override
  int get fragmentsPerTexel => share ~/ targetShare;

  @override
  DeviceBox get replayed => layout.footprint;

  @override
  Offset get at => Offset(
    (layout.footprint.left - device.left) / fragmentsPerTexel,
    (layout.footprint.top - device.top) / fragmentsPerTexel,
  );

  Size get _footprintPixels =>
      layout.footprint.size / fragmentsPerTexel.toDouble();

  /// The screen rect (logical pixels) past which the read holds nothing.
  Rect get holds => layout.view.logical(device).intersect(layout.footprintRect);

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

  @override
  double get baked => layout.bakedIn(targetShare);

  @override
  (Size, Rect) get _inPlaceInput => (copySize, copyRect);

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
        min(at.dx + footprint.width, device.width / fragmentsPerTexel) - 0.5,
        min(at.dy + footprint.height, device.height / fragmentsPerTexel) - 0.5,
      ),
      frost: tap / fragmentsPerTexel,
      texelsPerFragment: 1 / fragmentsPerTexel,
      shown: fragments,
      dissolve: dissolve.mapped(0, devicePixelRatio).mapped(-device.top, 1),
    );
  }

  /// Where the copy's levels lie in the layer, counted in the target's
  /// pixels, or null where it carries none.
  ///
  /// Where the clip the layer is drawn under would cut the levels' rows off
  /// ([ImpellerLayers.keepsWhole]), as a coarser copy's footprint cuts glass
  /// it holds near its bottom, the copy carries none.
  @override
  late final LevelStrip? levels = () {
    final levels = layout.drawnLevels;
    if (levels == null) return null;
    final copy = copyRect.size / targetShare.toDouble();
    final strip = _stripOf(
      levels,
      Size(copy.width.ceilToDouble(), copy.height.ceilToDouble()),
    );
    return _keepsWhole(levelSize(strip)) ? strip : null;
  }();

  @override
  Offset get levelAt => copyRect.topLeft / targetShare.toDouble();

  /// The part of the layer, from its corner, the passes of [strip] draw: the
  /// copy and its levels under it, in the layer's coordinates.
  Size levelSize(LevelStrip strip) {
    final at = levelAt;
    final size = strip.size;
    return Size(at.dx + size.width, at.dy + size.height) *
        targetShare.toDouble();
  }

  bool _keepsWhole(Size size) => switch (under) {
    final under? => ImpellerLayers.keepsWhole(
      device.topLeft & sizeWith(size),
      under.scaled(devicePixelRatio),
    ),
    null => true,
  };

  /// The layer's size in device pixels where layers of [size] lie in it
  /// from its corner: the part of the screen it covers, and under it the
  /// rows of its levels where the layer has none for them.
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
final class ImagePlace extends CopyPlace {
  /// The copy of [layout] at [at] in an image.
  const ImagePlace(super.layout, this.at) : super._();

  /// The size of a copy of [layout], in the image's pixels.
  static (int, int) sizeOf(ReadLayout layout) =>
      layout.imageBox!.pixelsOn(layout.share);

  /// The size a copy of [layout] takes in the image with the levels it
  /// carries under it, in the image's pixels.
  static (int, int) reservedOf(ReadLayout layout) {
    final (width, height) = sizeOf(layout);
    final levels = layout.drawnLevels;
    if (levels == null) return (width, height);
    final size = LevelStrip(
      levels,
      pixels: layout.pixels,
      boxed: layout.share > 1,
      copy: Size(width.toDouble(), height.toDouble()),
      grid: Offset.zero,
    ).size;
    return (size.width.ceil(), size.height.ceil());
  }

  @override
  final Offset at;

  @override
  int get share => layout.share;

  @override
  int get fragmentsPerTexel => layout.share;

  @override
  DeviceBox get replayed => layout.imageBox!;

  /// The screen rect the copy holds, in logical pixels.
  Rect get rect => layout.imageRect!;

  @override
  Offset get zero => replayed.topLeft - at * fragmentsPerTexel.toDouble();

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
  /// the copy by [tap] device pixels, drawn under a canvas that takes the
  /// screen to the image.
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling frostSampling(
    Size image,
    double tap, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final rect = this.rect;
    final part = replayed.size / fragmentsPerTexel.toDouble();
    return FrostSampling(
      size: image,
      bounds: Rect.fromLTRB(
        at.dx + 0.5,
        at.dy + 0.5,
        at.dx + part.width - 0.5,
        at.dy + part.height - 0.5,
      ),
      frost: tap / fragmentsPerTexel,
      texelsPerFragment: 1,
      // The rect drawn bounds the frost.
      shown: Rect.largest,
      dissolve: dissolve.mapped(-rect.top, pixels).mapped(at.dy, 1),
    );
  }

  /// The copy's size in the image, in its pixels.
  Size get size {
    final (width, height) = sizeOf(layout);
    return Size(width.toDouble(), height.toDouble());
  }

  /// Where the copy lies in the image.
  Rect get bounds => at & size;

  @override
  double get baked => layout.bakedFrost;

  @override
  (Size, Rect) get _inPlaceInput => (size, Offset.zero & size);

  @override
  LevelStrip? get levels => switch (layout.drawnLevels) {
    final levels? => _stripOf(levels, size),
    null => null,
  };

  @override
  Offset get levelAt => at;

  /// From the screen's logical pixels to the copy's place in the image.
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
