// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

// An identity backdrop filter: under a clip it gives the filter inside it a
// pass of the clip's size to read instead of the whole pass behind it.
const ui.ImageFilter _seed = ui.ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// A Gaussian blur followed by a color matrix: a backdrop filter that a
/// [LiquidGlassBackdropFilterLayer] draws from an unblurred copy at a
/// fraction of the screen's pixels, frosted by a shader as it is drawn.
///
/// NEAR: the shader's 24 taps over a smaller copy are not Impeller's blur
/// (see [LiquidGlassBackdropFilterLayer.debugShaderFrost]).
final class LiquidGlassBackdropFrost {
  /// Creates the filter: a blur by [sigma] logical pixels along both axes,
  /// then [colorMatrix] as [ui.ColorFilter.matrix] takes it, or none.
  LiquidGlassBackdropFrost({required this.sigma, this.colorMatrix})
    : assert(sigma > 0, 'A frost blurs.'),
      assert(colorMatrix == null || colorMatrix.length == 20, '5 x 4 values.');

  /// The blur's sigma, in logical pixels.
  final double sigma;

  /// The color matrix applied after the blur, row by row, as
  /// [ui.ColorFilter.matrix] takes it; null for none.
  final List<double>? colorMatrix;

  /// The same filter as a backdrop filter, for what reads the backdrop.
  late final ui.ImageFilter filter = _filterOf(sigma, colorMatrix);

  static ui.ImageFilter _filterOf(double sigma, List<double>? matrix) {
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    if (matrix == null) return blur;
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(matrix),
      inner: blur,
    );
  }
}

/// A backdrop filter over [clip] that, wherever it can, filters a copy of
/// what is painted under it instead of reading the backdrop, so a frame
/// whose backdrop effects all draw from copies renders straight to the
/// screen.
///
/// A backdrop filter anywhere in a frame makes Impeller render the whole
/// frame offscreen, split the root pass at every read and blit the result to
/// the screen. This layer draws what lies under [clip] again from the layer
/// tree into a small image, filtered as the backdrop would be, while the
/// frame composites; the image serves later frames while those layers are
/// unchanged. Under a texture, a platform view, a live backdrop filter or a
/// layer type the copy cannot draw (see `LiquidGlassUnderlay`) it reads the
/// backdrop like a [BackdropFilterLayer], confined to [reach] around [clip].
///
/// The filter applies to the screen-aligned backdrop: under a transform that
/// scales or turns the layer, it reads the backdrop.
class LiquidGlassBackdropFilterLayer extends ContainerLayer with ComposedLayer {
  /// Creates the layer.
  LiquidGlassBackdropFilterLayer({
    required this._filter,
    required this._clip,
    required this._reach,
    required this._devicePixelRatio,
    this._blendMode = BlendMode.srcOver,
    this.confinesRead = true,
  });

  /// Creates the layer for [frost], drawn from an unblurred copy wherever a
  /// copy serves.
  LiquidGlassBackdropFilterLayer.frosted({
    required LiquidGlassBackdropFrost frost,
    required this._clip,
    required this._reach,
    required this._devicePixelRatio,
    this._blendMode = BlendMode.srcOver,
    this.confinesRead = true,
  }) : _frost = frost,
       _filter = frost.filter;

  /// Whether a [frost] is drawn from an unblurred copy through a shader;
  /// without, its copy is filtered as [filter] filters the backdrop.
  ///
  /// NEAR: over the colored rows and white lines of apple_liquid_glass's
  /// scroll edge frost host test, the bands differ from the copy filtered as
  /// the backdrop by at most 16 channel levels at a device pixel ratio of
  /// 2.625 and 12 at 3, by under 0.5 on average. In return the copy holds a
  /// quarter of the pixels and takes no blur passes, and a change of the
  /// color matrix alone, as a band fades in, keeps it.
  @visibleForTesting
  static bool debugShaderFrost = true;

  /// Whether a live read is confined to [reach] around [clip]: a pass of
  /// that size, seeded with the backdrop, is what the filter reads. Without
  /// it the filter reads the pass it composites in, as a
  /// [BackdropFilterLayer] does, which inside a fractional opacity is the
  /// group's own layer.
  final bool confinesRead;

  /// The filter applied to what lies under [clip], composited over it as a
  /// [BackdropFilterLayer] composites its output.
  ui.ImageFilter get filter => _filter;
  ui.ImageFilter _filter;
  set filter(ui.ImageFilter value) {
    if (identical(value, _filter) && _frost == null) return;
    _filter = value;
    _frost = null;
    markNeedsAddToScene();
  }

  /// The blur and color matrix [filter] stands for, which a copy draws
  /// through a shader; null when [filter] was set.
  LiquidGlassBackdropFrost? get frost => _frost;
  LiquidGlassBackdropFrost? _frost;
  set frost(LiquidGlassBackdropFrost value) {
    if (identical(value, _frost)) return;
    _frost = value;
    _filter = value.filter;
    markNeedsAddToScene();
  }

  /// How the filtered backdrop composites over the backdrop, as
  /// [BackdropFilterLayer.blendMode] does.
  BlendMode get blendMode => _blendMode;
  BlendMode _blendMode;
  set blendMode(BlendMode value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsAddToScene();
  }

  /// Where the filter applies, in this layer's coordinates.
  Rect get clip => _clip;
  Rect _clip;
  set clip(Rect value) {
    if (value == _clip) return;
    _clip = value;
    markNeedsAddToScene();
  }

  /// How far outside [clip] the filter reads, in logical pixels.
  double get reach => _reach;
  double _reach;
  set reach(double value) {
    if (value == _reach) return;
    _reach = value;
    markNeedsAddToScene();
  }

  /// The device pixel ratio of the view the layer is composited into.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  final _underlay = BackdropUnderlay();
  FilteredCopyAsk? _asked;
  // How the shader frosts this frame's copy, in device px, or null when the
  // copy is filtered.
  ShaderFrost? _shaderFrost;
  ui.FragmentShader? _frostShader;
  UnderlayCopy? _copy;
  Rect _shown = Rect.zero;
  Offset _origin = Offset.zero;
  ui.Picture? _served;
  Object? _servedKey;

  /// Whether this frame draws a filtered copy in place of the backdrop read.
  @internal
  bool get serves => _copy != null;

  /// The filtered copy this frame draws in place of the backdrop read, in
  /// this layer's coordinates, or null while the layer reads the backdrop.
  /// Recorded when first read, once the copy is drawn with the other copies
  /// of the frame.
  @internal
  ui.Picture? get servedPicture {
    final copy = _copy;
    if (copy == null) return null;
    if (_served case final served?) return served;
    final served = switch ((_shaderFrost, _frost)) {
      (final taps?, final frost?) => _recordFrostedCopy(copy, frost, taps),
      _ => recordFilteredCopy(copy, _shown, _origin),
    };
    _servedKey = _keyOf(copy);
    return _served = served;
  }

  // What the picture is drawn from: an equal key draws an equal picture.
  Object _keyOf(UnderlayCopy copy) => (
    copy.image,
    copy.offset,
    _shown,
    _origin,
    _shaderFrost == null ? null : (_frost, _blendMode),
  );

  // [frost] drawn from [copy] over [_shown]: a rect drawn in the copy
  // image's pixels, so that the shader's fragment coordinate is the pixel
  // of the image it frosts around.
  ui.Picture _recordFrostedCopy(
    UnderlayCopy copy,
    LiquidGlassBackdropFrost frost,
    ShaderFrost taps,
  ) {
    final image = copy.image;
    final offset = copy.offset;
    final pixels = copy.pixelRatio;
    final source = Rect.fromLTRB(
      (_shown.left - copy.rect.left) * pixels + offset.dx,
      (_shown.top - copy.rect.top) * pixels + offset.dy,
      (_shown.right - copy.rect.left) * pixels + offset.dx,
      (_shown.bottom - copy.rect.top) * pixels + offset.dy,
    );
    final shader = _frostShader ??= MultiShaderBuilder.cached(
      ShaderKeys.backdropFrost,
    )!.fragmentShader();
    final m = frost.colorMatrix ?? _identity;
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(1 / image.width);
    put(1 / image.height);
    put(offset.dx + 0.5);
    put(offset.dy + 0.5);
    put(offset.dx + copy.rect.width * pixels - 0.5);
    put(offset.dy + copy.rect.height * pixels - 0.5);
    put(taps.frost / taps.downscale);
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        put(m[row * 5 + column]);
      }
    }
    for (var row = 0; row < 4; row++) {
      put(m[row * 5 + 4] / 255);
    }
    shader.setImageSampler(0, image, filterQuality: FilterQuality.low);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(_shown.left - _origin.dx, _shown.top - _origin.dy);
    canvas.scale(1 / pixels);
    canvas.translate(-source.left, -source.top);
    final paint = Paint();
    paint.shader = shader;
    paint.blendMode = _blendMode;
    paint.isAntiAlias = false;
    canvas.drawRect(source, paint);
    return recorder.endRecording();
  }

  static const _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  /// Whether the copy this frame filters is drawn with the frame's copies,
  /// not yet drawn.
  @internal
  bool get pending => _copy?.pending ?? false;

  /// Adds the filter to a copy drawn with the frame's copies that holds this
  /// layer while its own copy is not drawn yet (see [UnderlayFold]).
  @internal
  void addFold(ui.SceneBuilder builder, Rect rect, Offset offset) =>
      addFoldedFilter(
        builder,
        _shown.shift(-_origin),
        _filter,
        blendMode: _blendMode,
      );

  /// The copy this layer filters.
  @visibleForTesting
  BackdropUnderlay get debugUnderlay => _underlay;

  @internal
  @override
  void prepare() {
    _shaderFrost = null;
    if (!BackdropUnderlay.enabled) {
      _asked = null;
      return;
    }
    if (_askFrostedCopy() case final asked?) {
      _asked = asked;
      return;
    }
    _asked = requestFilteredCopy(
      _underlay,
      this,
      filter: _filter,
      blendMode: _blendMode,
      clip: _clip,
      reach: _reach,
      devicePixelRatio: _devicePixelRatio,
      filtersReach: false,
    );
  }

  // Asks for the unblurred copy the shader frosts, or returns null when the
  // copy is filtered: no frost, a frost too wide for the shader, or its
  // program not loaded yet.
  FilteredCopyAsk? _askFrostedCopy() {
    final frost = _frost;
    if (frost == null || !debugShaderFrost) return null;
    if (!MultiShaderBuilder.isCached(ShaderKeys.backdropFrost)) {
      unawaited(MultiShaderBuilder.precacheShader(ShaderKeys.backdropFrost));
      return null;
    }
    // A copy whose pixels the frost spans by less than 1.5 is not halved
    // again: drawn smaller, its edges show through the frost.
    final taps = shaderFrost(frost.sigma * _devicePixelRatio, minTexels: 1.5);
    final origin = taps == null
        ? null
        : screenOffsetOf(this, _devicePixelRatio);
    if (taps == null || origin == null) return null;
    final shifted = _clip.shift(origin);
    // The taps reach 2.8 sigma, one copy pixel more sampled bilinearly.
    final reach = (2.8 * taps.frost + taps.downscale) / _devicePixelRatio;
    _underlay.request(
      anchor: this,
      devicePixelRatio: _devicePixelRatio,
      region: shifted.inflate(reach),
      downscale: taps.downscale,
    );
    _shaderFrost = taps;
    return (shifted: shifted, origin: origin);
  }

  // Runs for every built scene, also when an ancestor stays retained, after
  // every layer has painted: the choice between the copy and the backdrop
  // is made here, where it can still mark the layer for adding.
  @internal
  @override
  void compose() {
    final asked = _asked;
    _asked = null;
    final copy = asked == null ? null : _serve(asked);
    // A copy drawn in an earlier frame keeps its picture while it lies where
    // it did; a copy not drawn yet is drawn with the frame's other copies.
    final key = copy != null && copy.ready ? _keyOf(copy) : null;
    if (copy == null || key == null || key != _servedKey) {
      if (_copy != null || copy != null) markNeedsAddToScene();
      _served?.dispose();
      _served = null;
    }
    _copy = copy;
    _servedKey = key;
    if (copy == null) _underlay.release();
  }

  // The copy this frame filters, or null while the layer reads the
  // backdrop.
  UnderlayCopy? _serve(FilteredCopyAsk asked) {
    final served = serveFilteredCopy(_underlay, asked);
    if (served == null) return null;
    _shown = served.shown;
    _origin = served.origin;
    return served.copy;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final served = servedPicture;
    if (served != null) {
      builder.addPicture(Offset.zero, served);
      addChildrenToScene(builder);
      return;
    }
    if (confinesRead) {
      builder.pushClipRect(_clip.inflate(_reach), clipBehavior: Clip.hardEdge);
      builder.pushBackdropFilter(_seed, blendMode: BlendMode.src);
    }
    builder.pushClipRect(_clip, clipBehavior: Clip.hardEdge);
    builder.pushBackdropFilter(_filter, blendMode: _blendMode);
    addChildrenToScene(builder);
    builder.pop();
    builder.pop();
    if (confinesRead) {
      builder.pop();
      builder.pop();
    }
  }

  @override
  void dispose() {
    _frostShader?.dispose();
    _frostShader = null;
    _served?.dispose();
    _served = null;
    _copy = null;
    _underlay.release();
    super.dispose();
  }
}
