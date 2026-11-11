import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:meta/meta.dart';

/// How the final glass shader reads a copy: the one place that says where
/// its fragments lie and what its texture holds, written to the shader by
/// the glass alone.
///
/// The shader takes its fragments for the screen's device pixels, or for
/// [scale] of them where the glass is drawn inside a coarser copy. A copy
/// whose pixels are larger stands for a texture as many times larger
/// ([size]), or lies in the top-left share of a layer of the screen's pixels
/// ([reduced]).
@internal
@immutable
final class GlassSampling {
  /// Creates the sampling.
  const GlassSampling({
    required this.origin,
    required this.reduced,
    this.frost = 0,
    this.image,
    this.size,
    this.holds,
    this.scale = 1,
  });

  /// Where the shader's fragment coordinate zero lies on the screen, in
  /// device pixels.
  final Offset origin;

  /// How many device pixels along each side one fragment stands for: 1, or
  /// the share of the copy the glass is drawn in, whose pixels its layer is
  /// drawn at.
  final int scale;

  /// uBackdropReduced: 0 where every fragment reads its own texel of the
  /// copy; 1 for an image copy at fewer pixels than the screen, which [size]
  /// stretches; the share for a copy in the top-left share of a layer.
  final double reduced;

  /// uBackdropFrost: the sigma, in device pixels, the shader's taps frost
  /// the copy by, 0 for none. A reading takes the sigma of the Impeller blur
  /// the frost stands for, in the screen's logical pixels, and leaves out
  /// what the copy's pixels already blur by.
  final double frost;

  /// The image the shader samples, for glass painted over an image copy.
  /// Null where the glass filters a layer, whose texture the engine binds.
  final ui.Image? image;

  /// uSize for glass painted over [image]: the image as many times larger
  /// as the copy is smaller, so a texel spans as many fragments as device
  /// pixels. Null where the engine sets it to the filtered layer's size.
  final Size? size;

  /// The screen rect (logical pixels) past which the read holds nothing,
  /// and the shader mirrors at it. Null where the glass's own bounds say.
  final Rect? holds;
}

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
  });

  /// uSize: the size of the texture the shader reads, in its pixels.
  final Size size;

  /// uBounds: the copy in the texture, in the copy's pixels, half a pixel
  /// in from its edge.
  final Rect bounds;

  /// uFrost: the sigma, in the copy's pixels, the taps frost it by, as
  /// [GlassSampling.frost] says.
  final double frost;

  /// uScale: the copy's pixels per fragment.
  final double scale;

  /// uShown: the fragments the frost covers.
  final Rect shown;
}

/// The part [shown] (screen logical pixels) of a page that a surface paints
/// from its image.
@internal
final class PagePart {
  /// The part [shown] of [copy].
  PagePart(PageCopy copy, this.shown) : _copy = copy;

  final PageCopy _copy;

  /// The part painted, in the screen's logical pixels.
  final Rect shown;

  /// [shown] in the image's pixels.
  Rect get source {
    final pixels = _copy.geometry.lattice.pixels;
    final offset = _copy.offset;
    final rect = _copy.rect;
    return Rect.fromLTRB(
      (shown.left - rect.left) * pixels + offset.dx,
      (shown.top - rect.top) * pixels + offset.dy,
      (shown.right - rect.left) * pixels + offset.dx,
      (shown.bottom - rect.top) * pixels + offset.dy,
    );
  }

  /// Takes [canvas] from the screen's logical pixels to the image's, so
  /// that [source] drawn there lands on [shown].
  void toImage(Canvas canvas) {
    final source = this.source;
    canvas
      ..translate(shown.left, shown.top)
      ..scale(1 / _copy.geometry.lattice.pixels)
      ..translate(-source.left, -source.top);
  }

  /// How `backdrop_frost.frag` reads [source] drawn under [toImage] to frost
  /// it for Impeller's blur by [frost] (see [GlassSampling.frost]).
  FrostSampling frostSampling(double frost) {
    final geometry = _copy.geometry;
    final lattice = geometry.lattice;
    final pixels = lattice.pixels;
    final offset = _copy.offset;
    final image = _copy.image;
    return FrostSampling(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      bounds: Rect.fromLTRB(
        offset.dx + 0.5,
        offset.dy + 0.5,
        offset.dx + _copy.rect.width * pixels - 0.5,
        offset.dy + _copy.rect.height * pixels - 0.5,
      ),
      frost: frost == _copy.heldSigma
          ? 0
          : lattice.residual(geometry.frostFor(frost)) / lattice.share,
      scale: 1,
      // The rect drawn bounds the frost.
      shown: Rect.largest,
    );
  }
}

/// One layer of the screen's pixels holding a read's copy for the part
/// of it inside a region: the layer's top-left share holds the copy at its
/// own pixels, and a filter on the layer sees fragments of the screen's
/// pixels from the layer's corner. The only code that lays a copy out so.
///
/// NEAR: past the copy the layer is empty, and reads mirror at the copy's
/// edge.
@internal
final class CornerRead {
  /// A part of a copy's layer (screen logical pixels), drawn into a target
  /// whose pixels each stand for a number of device pixels.
  CornerRead(this._copy, this._cut, this._scale)
    : _grid = _copy.read.geometry.lattice.inside(_scale);

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerRead.inFrame(ReadCopy copy) {
    final layer = copy.read.geometry.layer;
    assert(!layer.isEmpty, 'A read that draws holds some of the screen.');
    return CornerRead(copy, layer, 1);
  }

  final ReadCopy _copy;
  // The part of the copy's layer read, in the screen's logical pixels.
  final Rect _cut;
  // How many device pixels one pixel of the target the layer is drawn into
  // stands for.
  final int _scale;
  // The grid the copy is drawn at: its own, or the target's where that is
  // coarser.
  final Lattice _grid;
  // The layer, in the screen's device pixels, on [_grid]: a layer off the
  // target's pixels starts its fragments at the pixel it is rounded out to.
  late final Rect _device = _grid.toDevice(_cut);

  ReadGeometry get _geometry => _copy.read.geometry;
  double get _dpr => _grid.devicePixelRatio;
  // The device pixels along each side one pixel of the layer holds of the
  // copy, past the target's own.
  int get _share => _grid.share ~/ _scale;
  // The copy's pixels per logical pixel, in the layer.
  double get _pixels => _dpr / _share;

  // Where the copy's top left lies in the layer, in the copy's pixels.
  Offset get _at => Offset(
    (_geometry.band.left * _dpr - _device.left) / _share,
    (_geometry.band.top * _dpr - _device.top) / _share,
  );

  // The sigma, in device pixels, the taps frost the copy by for Impeller's
  // blur by [frost].
  double _residual(double frost) => _grid.residual(_geometry.frostFor(frost));

  /// How the final shader reads the layer to frost it for Impeller's blur
  /// by [frost] (see [GlassSampling.frost]).
  GlassSampling glassSampling(double frost) => GlassSampling(
    origin: _device.topLeft,
    reduced: _share > 1 ? _share.toDouble() : 0,
    frost: _residual(frost),
    scale: _scale,
    holds: Rect.fromLTRB(
      _device.left / _dpr,
      _device.top / _dpr,
      _device.right / _dpr,
      _device.bottom / _dpr,
    ).intersect(_geometry.band),
  );

  /// How `backdrop_frost.frag` reads the layer to cover [shown] (screen
  /// logical pixels) pixel by pixel, frosted for Impeller's blur by [frost]
  /// (see [GlassSampling.frost]), or null where none of [shown] lies in it.
  /// With [held] the copy already holds the frost and is only read.
  FrostSampling? frostSampling(Rect shown, double frost, {bool held = false}) {
    final drawn = shown.intersect(_cut);
    if (drawn.isEmpty) return null;
    final at = _at;
    final band = _geometry.band;
    final pixels = _pixels;
    return FrostSampling(
      size: _device.size,
      bounds: Rect.fromLTRB(
        max(at.dx, 0) + 0.5,
        max(at.dy, 0) + 0.5,
        min(at.dx + band.width * pixels, _device.width / _share) - 0.5,
        min(at.dy + band.height * pixels, _device.height / _share) - 0.5,
      ),
      frost: held ? 0 : _residual(frost) / _share,
      scale: 1 / _share,
      shown: Rect.fromLTRB(
        drawn.left * _dpr,
        drawn.top * _dpr,
        drawn.right * _dpr,
        drawn.bottom * _dpr,
      ).shift(-_device.topLeft),
    );
  }

  // The part of the layer the copy's own pixels fill, in the layer's own
  // pixels.
  Size get _copySize {
    final at = _at;
    final band = _geometry.band;
    final pixels = _pixels;
    return Size(
      min(ceilPixels(max(at.dx, 0) + band.width * pixels), _device.width),
      min(ceilPixels(max(at.dy, 0) + band.height * pixels), _device.height),
    );
  }

  /// What frosts the copy where it lies in the layer, at its own pixels, by
  /// the frost its geometry holds, which glass then reads as it is; null
  /// where the glass frosts it fragment by fragment.
  ///
  /// Null too where the layer is drawn into a coarser copy, which draws the
  /// frost's filter at its pixels as well, and the frost's taps take them for
  /// device pixels; and before the frost's program is loaded.
  CopyFrost? inPlaceFilter() {
    final frost = _geometry.bakedFrost;
    if (frost <= 0 || _scale > 1) return null;
    final at = _at;
    final size = _copySize;
    final band = _geometry.band;
    final pixels = _pixels;
    return frostFilterOf(
      FrostSampling(
        size: size,
        bounds: Rect.fromLTRB(
          max(at.dx, 0) + 0.5,
          max(at.dy, 0) + 0.5,
          min(at.dx + band.width * pixels, size.width) - 0.5,
          min(at.dy + band.height * pixels, size.height) - 0.5,
        ),
        frost: _residual(frost) / _share,
        scale: 1,
        shown: Offset.zero & size,
      ),
    );
  }

  /// Adds the layer to [builder] with [filter] as its image filter, in
  /// coordinates [deviceToLocal] takes the screen's device pixels to. The
  /// copy passes through [inPlace] first. Returns the outermost engine layer.
  ui.TransformEngineLayer addToScene(
    ui.SceneBuilder builder,
    ui.ImageFilter filter,
    Matrix4 deviceToLocal, {
    ui.Path? clip,
    CopyFrost? inPlace,
  }) {
    final at = _at;
    final engine = builder.pushTransform(
      (deviceToLocal.clone()..translateByDouble(-_below, -_below, 0, 1))
          .storage,
    );
    if (clip != null) builder.pushClipPath(clip, clipBehavior: Clip.hardEdge);
    builder
      ..pushImageFilter(filter)
      ..addPicture(_device.topLeft, corners(_device.size));
    inPlace?.push(builder, _device.topLeft, corners(_copySize));
    _copy.addTo(
      builder,
      Lattice(_dpr, _share),
      Offset(_device.left + at.dx, _device.top + at.dy),
      inPlace == null ? _device : _device.topLeft & _copySize,
    );
    inPlace?.pop(builder);
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    return engine;
  }

  // How far above and left of its pixels a read's layers are added, in
  // device pixels.
  //
  // Impeller places a layer drawn inside another, such as the one a
  // paragraph that fades at its edge is painted through, by the floor of its
  // origin less the origin of the layer around it. Where the copy's edge
  // cuts such a layer the two origins are the same number, less what 32-bit
  // floats lose on the way: the copy's passes through the place of the glass
  // on the screen, a fraction that moves with it. A hair above a whole pixel
  // the floor is one pixel short, and the layer's content, all of the text,
  // stood one pixel of the copy aside, up to four of the screen's, for the
  // frames the glass spent there (a lens sweeping over faded text on a
  // Pixel 6a: 46 to 58 frames in 12 s, none without the fade). Drawn a
  // little below whole pixels the floor always falls the same way. The
  // read's own layers are placed by rounding, so nothing on the screen
  // moves.
  static const double _below = 1 / 32;

  static final _cornersOf = <Size, ui.Picture>{};

  /// A pixel cleared at each corner of a layer of [size], which holds
  /// Impeller to the layer where the copy is transparent. Chrome keeps its
  /// few sizes across frames.
  static ui.Picture corners(Size size) {
    if (_cornersOf[size] case final held?) return held;
    if (_cornersOf.length >= 32) {
      for (final picture in _cornersOf.values) {
        picture.dispose();
      }
      _cornersOf.clear();
    }
    final clear = Paint()..blendMode = BlendMode.clear;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(const Rect.fromLTWH(0, 0, 1, 1), clear)
      ..drawRect(
        Rect.fromLTRB(size.width - 1, size.height - 1, size.width, size.height),
        clear,
      );
    return _cornersOf[size] = recorder.endRecording();
  }
}
