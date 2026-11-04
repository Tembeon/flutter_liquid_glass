// Canvas setup reads as one statement per call, without cascades.
// ignore_for_file: cascade_invocations

part of 'backdrop_underlay.dart';

/// The pixel grid a copy is drawn on: one, two or four device pixels of
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
        _share == 1 || _share == 2 || _share == 4,
        'A copy holds one, two or four device pixels along each side.',
      );

  final double _devicePixelRatio;

  // How many device pixels along each side one pixel of the copy holds.
  final int _share;

  // The copy's pixels per logical pixel.
  double get _pixels => _devicePixelRatio / _share;

  // The same grid at the screen's pixels.
  CopyGrid get _screen => _share == 1 ? this : CopyGrid._(_devicePixelRatio, 1);

  // [rect] (logical pixels) grown to whole pixels of the copy.
  Rect _snapOut(Rect rect) => BackdropUnderlay._snapOut(rect, _pixels);

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
    required this.scale,
    required this.shown,
  });

  /// uSize: the size of the texture the shader reads, in its pixels.
  final Size size;

  /// uBounds: the copy in the texture, in the copy's pixels, half a pixel
  /// in from its edge.
  final Rect bounds;

  /// uScale: the copy's pixels per fragment.
  final double scale;

  /// uShown: the fragments the frost covers.
  final Rect shown;
}

/// The part [shown] (screen logical pixels) of an image copy that a
/// surface paints from its image.
@internal
final class ImageRead {
  ImageRead._(this._copy, this.shown);

  final UnderlayCopy _copy;

  /// The part painted, in the screen's logical pixels.
  final Rect shown;

  /// [shown] in the image's pixels.
  Rect get source {
    final pixels = _copy._grid._pixels;
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
    canvas.translate(shown.left, shown.top);
    canvas.scale(1 / _copy._grid._pixels);
    canvas.translate(-source.left, -source.top);
  }

  /// How `backdrop_frost.frag` reads [source] drawn under [toImage].
  FrostSampling get frostSampling {
    final pixels = _copy._grid._pixels;
    final offset = _copy.offset;
    final image = _copy.image;
    return FrostSampling._(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      bounds: Rect.fromLTRB(
        offset.dx + 0.5,
        offset.dy + 0.5,
        offset.dx + _copy.rect.width * pixels - 0.5,
        offset.dy + _copy.rect.height * pixels - 0.5,
      ),
      scale: 1,
      // The rect drawn bounds the frost.
      shown: Rect.largest,
    );
  }
}

/// One layer of the screen's pixels holding an in-frame copy for the part
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

  final InFrameCopy _copy;
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

  /// How the final shader reads the layer.
  GlassSampling get glassSampling => GlassSampling._(
    origin: _device.topLeft,
    reduced: _share > 1 ? _share.toDouble() : 0,
    holds: Rect.fromLTRB(
      _device.left / _dpr,
      _device.top / _dpr,
      _device.right / _dpr,
      _device.bottom / _dpr,
    ).intersect(_copy._band),
  );

  /// How `backdrop_frost.frag` reads the layer to cover [shown] (screen
  /// logical pixels) pixel by pixel, or null where none of [shown] lies in
  /// it.
  FrostSampling? frostSampling(Rect shown) {
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
      scale: 1 / _share,
      shown: Rect.fromLTRB(
        drawn.left * _dpr,
        drawn.top * _dpr,
        drawn.right * _dpr,
        drawn.bottom * _dpr,
      ).shift(-_device.topLeft),
    );
  }

  /// Records the layer with [filter] as its image filter, in coordinates
  /// [deviceToLocal] takes the screen's device pixels to. A shader filter
  /// takes its shader's uniforms now.
  ui.Picture record(ui.ImageFilter filter, Matrix4 deviceToLocal) {
    final paint = Paint();
    paint.imageFilter = filter;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.transform(deviceToLocal.storage);
    canvas.saveLayer(_device, paint);
    // Impeller sizes a layer by what is drawn in it: a pixel cleared at each
    // corner holds it to the layer where the copy is transparent.
    final clear = Paint();
    clear.blendMode = BlendMode.clear;
    canvas.drawRect(Rect.fromLTWH(_device.left, _device.top, 1, 1), clear);
    canvas.drawRect(
      Rect.fromLTRB(
        _device.right - 1,
        _device.bottom - 1,
        _device.right,
        _device.bottom,
      ),
      clear,
    );
    final at = _at;
    canvas.translate(_device.left + at.dx, _device.top + at.dy);
    canvas.drawPicture(_copy._content);
    canvas.restore();
    return recorder.endRecording();
  }
}

/// A copy drawn at the screen's pixels together with glass whose own copy
/// is not drawn yet, that the glass draws itself into as its filter: the
/// filter's fragments are the copy's pixels, which are the screen's.
@internal
final class FoldTarget {
  FoldTarget._(CopyGrid grid, this._rect, this._offset)
    : _devicePixelRatio = grid._devicePixelRatio,
      assert(grid._share == 1, 'Glass folds only into the screen pixels.');

  final double _devicePixelRatio;
  // The screen rect the copy holds, in logical pixels.
  final Rect _rect;
  // Where a fragment lies past the copy's pixel.
  final Offset _offset;

  /// How the final shader reads the copy as a filter inside it.
  GlassSampling get glassSampling => GlassSampling._(
    origin: _rect.topLeft * _devicePixelRatio - _offset,
    reduced: 0,
    holds: _rect,
  );
}
