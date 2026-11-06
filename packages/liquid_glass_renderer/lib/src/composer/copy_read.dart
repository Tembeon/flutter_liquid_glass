// Canvas setup reads as one statement per call, without cascades.
// ignore_for_file: cascade_invocations

part of 'read.dart';

/// The pixel grid a copy is drawn on: one, two, four or eight device pixels of
/// the screen along each side of each of its pixels, on a grid anchored at
/// the screen's origin.
///
/// A copy's grid is the one it is drawn on, which a band holding glass that
/// a filter draws takes at the screen's pixels whatever was asked: that
/// glass takes its fragments for the screen's pixels. Only the copies make
/// grids, so a reader meets no other ratio than the one drawn.
@internal
@immutable
final class CopyGrid {
  const CopyGrid._(this._devicePixelRatio, this._share)
    : assert(
        _share == 1 || _share == 2 || _share == 4 || _share == 8,
        'A copy holds one, two, four or eight device pixels along each side.',
      );

  final double _devicePixelRatio;

  // How many device pixels along each side one pixel of the copy holds.
  final int _share;

  // The copy's pixels per logical pixel.
  double get _pixels => _devicePixelRatio / _share;

  // The same grid at the screen's pixels.
  CopyGrid get _screen => _share == 1 ? this : CopyGrid._(_devicePixelRatio, 1);

  // [rect] (logical pixels) grown to whole pixels of the copy.
  Rect _snapOut(Rect rect) => _snapOutAt(rect, _pixels);

  // From the coordinates of a form's root to a copy of [rect], its top left
  // at [origin]: one scale, and the layers' own transforms after it.
  //
  // Impeller sets text drawn at a translation and a scale alone on whole
  // pixels of its target (impeller/entity/contents/text_contents.cc): text
  // moving under glass would step a pixel of the copy, up to four of the
  // screen's, at a time. Under a skew too small to see it lies where it is
  // drawn, read from its atlas bilinearly.
  Matrix4 _copyMatrix(Rect rect, Offset origin) {
    final scale = 1 / _share;
    final skew = _share > 1 && GlassCopies.debugPlaceText ? 1e-6 : 0.0;
    final left = rect.left * _devicePixelRatio;
    final top = rect.top * _devicePixelRatio;
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

  // The sigma, in device pixels, the shaders' taps frost a copy on this grid
  // by for Impeller's blur by [sigma] screen logical pixels. The copy's own
  // pixels already blur by what they hold, which a band holding glass that
  // a filter draws, at the screen's pixels whatever was asked, holds less
  // of. NEAR there: the taps lie up to 14 of its pixels apart, past the 3.5
  // [shaderFrostDownscale] keeps to; under the scroll edge over glass the
  // frost is 0.55 levels off the live read on average at 2.625 dpr and 0.41
  // at 3 (host test).
  double _frost(double sigma) => sigma > 0
      ? shaderFrostResidual(sigma * _devicePixelRatio, share: _share)
      : 0;

  @override
  bool operator ==(Object other) =>
      other is CopyGrid &&
      other._devicePixelRatio == _devicePixelRatio &&
      other._share == _share;

  @override
  int get hashCode => Object.hash(_devicePixelRatio, _share);
}

/// How the final glass shader reads a copy: the one place that says where
/// its fragments lie and what its texture holds, written to the shader by
/// the glass alone.
///
/// The shader takes its fragments for the screen's device pixels. A copy
/// whose pixels are larger stands for a texture as many times larger
/// ([size]), or lies in the top-left share of a layer of the screen's pixels
/// ([reduced]).
@internal
@immutable
final class GlassSampling {
  const GlassSampling._({
    required this.origin,
    required this.reduced,
    this.frost = 0,
    this.image,
    this.size,
    this.holds,
  });

  /// Where the shader's fragment coordinate zero lies on the screen, in
  /// device pixels.
  final Offset origin;

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
  const FrostSampling._({
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
  PagePart._(this._copy, this.shown);

  final PageCopy _copy;

  /// The part painted, in the screen's logical pixels.
  final Rect shown;

  /// [shown] in the image's pixels.
  Rect get source {
    final pixels = _copy._grid._pixels;
    final offset = _copy._offset;
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
    canvas.translate(shown.left, shown.top);
    canvas.scale(1 / _copy._grid._pixels);
    canvas.translate(-source.left, -source.top);
  }

  /// How `backdrop_frost.frag` reads [source] drawn under [toImage] to frost
  /// it for Impeller's blur by [frost] (see [GlassSampling.frost]).
  FrostSampling frostSampling(double frost) {
    final grid = _copy._grid;
    final pixels = grid._pixels;
    final offset = _copy._offset;
    final image = _copy.image;
    return FrostSampling._(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      bounds: Rect.fromLTRB(
        offset.dx + 0.5,
        offset.dy + 0.5,
        offset.dx + _copy.rect.width * pixels - 0.5,
        offset.dy + _copy.rect.height * pixels - 0.5,
      ),
      frost: frost == _copy._heldFrost ? 0 : grid._frost(frost) / grid._share,
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
  CornerRead._(this._copy, this._cut)
    : _device = Rect.fromLTRB(
        (_cut.left * _copy._grid._pixels).floorToDouble() * _copy._grid._share,
        (_cut.top * _copy._grid._pixels).floorToDouble() * _copy._grid._share,
        (_cut.right * _copy._grid._pixels).ceilToDouble() * _copy._grid._share,
        (_cut.bottom * _copy._grid._pixels).ceilToDouble() * _copy._grid._share,
      );

  final ReadCopy _copy;
  // The part of the copy's layer read, in the screen's logical pixels.
  final Rect _cut;
  // The layer, in the screen's device pixels, on the copy's grid.
  final Rect _device;

  double get _dpr => _copy._grid._devicePixelRatio;
  int get _share => _copy._grid._share;

  // Where the copy's top left lies in the layer, in the copy's pixels.
  Offset get _at => Offset(
    (_copy._band.left * _dpr - _device.left) / _share,
    (_copy._band.top * _dpr - _device.top) / _share,
  );

  /// How the final shader reads the layer to frost it for Impeller's blur
  /// by [frost] (see [GlassSampling.frost]).
  GlassSampling glassSampling(double frost) => GlassSampling._(
    origin: _device.topLeft,
    reduced: _share > 1 ? _share.toDouble() : 0,
    frost: _copy._grid._frost(_copy._frostOver(frost)),
    holds: Rect.fromLTRB(
      _device.left / _dpr,
      _device.top / _dpr,
      _device.right / _dpr,
      _device.bottom / _dpr,
    ).intersect(_copy._band),
  );

  /// How `backdrop_frost.frag` reads the layer to cover [shown] (screen
  /// logical pixels) pixel by pixel, frosted for Impeller's blur by [frost]
  /// (see [GlassSampling.frost]), or null where none of [shown] lies in it.
  FrostSampling? frostSampling(Rect shown, double frost) {
    final drawn = shown.intersect(_cut);
    if (drawn.isEmpty) return null;
    final at = _at;
    final pixels = _copy._grid._pixels;
    return FrostSampling._(
      size: _device.size,
      bounds: Rect.fromLTRB(
        max(at.dx, 0) + 0.5,
        max(at.dy, 0) + 0.5,
        min(at.dx + _copy._band.width * pixels, _device.width / _share) - 0.5,
        min(at.dy + _copy._band.height * pixels, _device.height / _share) - 0.5,
      ),
      frost: _copy._grid._frost(frost) / _share,
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
    final pixels = _copy._grid._pixels;
    return Size(
      min(
        (max(at.dx, 0) + _copy._band.width * pixels).ceilToDouble(),
        _device.width,
      ),
      min(
        (max(at.dy, 0) + _copy._band.height * pixels).ceilToDouble(),
        _device.height,
      ),
    );
  }

  /// How `backdrop_frost.frag` frosts the copy where it lies in the layer, at
  /// its own pixels, for Impeller's blur by [frost], or null when the copy is
  /// too large for that to pay: glass then frosts it fragment by fragment.
  FrostSampling? inPlaceFrostSampling(double frost) {
    if (frost <= 0 || !_copy.read.bakesFrost) return null;
    final at = _at;
    final size = _copySize;
    final pixels = _copy._grid._pixels;
    return FrostSampling._(
      size: size,
      bounds: Rect.fromLTRB(
        max(at.dx, 0) + 0.5,
        max(at.dy, 0) + 0.5,
        min(at.dx + _copy._band.width * pixels, size.width) - 0.5,
        min(at.dy + _copy._band.height * pixels, size.height) - 0.5,
      ),
      frost: _copy._grid._frost(_copy._frostOver(frost)) / _share,
      scale: 1,
      shown: Offset.zero & size,
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
    ui.ImageFilter? inPlace,
  }) {
    final at = _at;
    final engine = builder.pushTransform(deviceToLocal.storage);
    if (clip != null) builder.pushClipPath(clip, clipBehavior: Clip.hardEdge);
    builder.pushImageFilter(filter);
    builder.addPicture(_device.topLeft, _corners(_device.size));
    if (inPlace != null) {
      builder.pushImageFilter(inPlace);
      builder.addPicture(_device.topLeft, _corners(_copySize));
    }
    _copy._addTo(
      builder,
      Offset(_device.left + at.dx, _device.top + at.dy),
      inPlace == null ? _device : _device.topLeft & _copySize,
    );
    if (inPlace != null) builder.pop();
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    return engine;
  }

  // A pixel cleared at each corner of a layer of [size], which holds Impeller
  // to the layer where the copy is transparent. Chrome keeps its few sizes
  // across frames.
  static final _cornersOf = <Size, ui.Picture>{};

  static ui.Picture _corners(Size size) {
    if (_cornersOf[size] case final held?) return held;
    if (_cornersOf.length >= 32) {
      for (final picture in _cornersOf.values) {
        picture.dispose();
      }
      _cornersOf.clear();
    }
    final clear = Paint();
    clear.blendMode = BlendMode.clear;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), clear);
    canvas.drawRect(
      Rect.fromLTRB(size.width - 1, size.height - 1, size.width, size.height),
      clear,
    );
    return _cornersOf[size] = recorder.endRecording();
  }
}
