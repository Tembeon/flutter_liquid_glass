// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_underlay.dart';

// An identity backdrop filter: under a clip it gives the filter inside it a
// pass of the clip's size to read instead of the whole pass behind it.
const ui.ImageFilter _seed = ui.ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
]);

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
  });

  /// The filter applied to what lies under [clip], composited over it as a
  /// [BackdropFilterLayer] composites its output.
  ui.ImageFilter get filter => _filter;
  ui.ImageFilter _filter;
  set filter(ui.ImageFilter value) {
    if (identical(value, _filter)) return;
    _filter = value;
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
  /// Recorded when first read: unless a copy taken earlier in the frame holds
  /// this layer, the copy is drawn with the other copies of the frame rather
  /// than on its own.
  @internal
  ui.Picture? get servedPicture {
    final copy = _copy;
    if (copy == null) return null;
    if (_served case final served?) return served;
    final served = _record(copy);
    _servedKey = _keyOf(copy);
    return _served = served;
  }

  // What the picture is drawn from: an equal key draws an equal picture.
  Object _keyOf(UnderlayCopy copy) =>
      (copy.image, copy.offset, _shown, _origin);

  /// Whether the last composited frame filtered a copy.
  @visibleForTesting
  bool get debugServed => _copy != null;

  /// The copy this layer filters.
  @visibleForTesting
  BackdropUnderlay get debugUnderlay => _underlay;

  // Runs for every built scene, also when an ancestor stays retained, after
  // every layer has painted: the choice between the copy and the backdrop
  // is made here, where it can still mark the layer for adding.
  @internal
  @override
  void compose() {
    final copy = BackdropUnderlay.enabled ? _serve() : null;
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
  UnderlayCopy? _serve() {
    final view = owner;
    if (view is! RenderView) return null;
    final dpr = _devicePixelRatio;
    final toScreen = Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1);
    final chain = <Layer>[];
    for (Layer? node = this; node != null; node = node.parent) {
      chain.add(node);
    }
    for (var i = chain.length - 1; i > 0; i--) {
      (chain[i] as ContainerLayer).applyTransform(chain[i - 1], toScreen);
    }
    final m = toScreen.storage;
    if ((m[0] - 1).abs() > 1e-6 ||
        (m[5] - 1).abs() > 1e-6 ||
        m[1].abs() > 1e-6 ||
        m[4].abs() > 1e-6) {
      return null;
    }
    final clip = _clip.shift(Offset(m[12], m[13]));
    final copy = _underlay.imageFor(
      anchor: this,
      devicePixelRatio: dpr,
      region: clip.inflate(_reach),
      screen: Offset.zero & view.size,
      filter: _filter,
      filterKey: _filter,
      filterClip: clip,
      filterBlendMode: BlendMode.srcOver,
    );
    if (copy == null) return null;
    _shown = clip.intersect(copy.rect);
    _origin = Offset(m[12], m[13]);
    return copy;
  }

  // The copy drawn into this layer's coordinates.
  ui.Picture _record(UnderlayCopy copy) {
    final shown = _shown;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-_origin.dx, -_origin.dy);
    final source = shown.shift(-copy.rect.topLeft);
    final offset = copy.offset;
    final paint = Paint();
    // The copy already holds the filtered backdrop composited over the
    // backdrop: it replaces what lies under it.
    paint.blendMode = BlendMode.src;
    paint.filterQuality = FilterQuality.none;
    canvas.drawImageRect(
      copy.image,
      Rect.fromLTRB(
        source.left * copy.pixelRatio + offset.dx,
        source.top * copy.pixelRatio + offset.dy,
        source.right * copy.pixelRatio + offset.dx,
        source.bottom * copy.pixelRatio + offset.dy,
      ),
      shown,
      paint,
    );
    return recorder.endRecording();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final served = servedPicture;
    if (served != null) {
      builder.addPicture(Offset.zero, served);
      addChildrenToScene(builder);
      return;
    }
    builder.pushClipRect(_clip.inflate(_reach), clipBehavior: Clip.hardEdge);
    builder.pushBackdropFilter(_seed, blendMode: BlendMode.src);
    builder.pushClipRect(_clip, clipBehavior: Clip.hardEdge);
    builder.pushBackdropFilter(_filter);
    addChildrenToScene(builder);
    builder.pop();
    builder.pop();
    builder.pop();
    builder.pop();
  }

  @override
  void dispose() {
    _served?.dispose();
    _served = null;
    _copy = null;
    _underlay.dispose();
    super.dispose();
  }
}
