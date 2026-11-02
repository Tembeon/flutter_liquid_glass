// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
class LiquidGlassBackdropFilterLayer extends ContainerLayer {
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
  ui.Picture? _served;
  Object? _servedKey;

  /// The filtered copy this frame draws in place of the backdrop read, in
  /// this layer's coordinates, or null while the layer reads the backdrop.
  @internal
  ui.Picture? get servedPicture => _served;

  /// Whether the last composited frame filtered a copy.
  @visibleForTesting
  bool get debugServed => _served != null;

  /// The copy this layer filters.
  @visibleForTesting
  BackdropUnderlay get debugUnderlay => _underlay;

  // Runs on every built scene, also when an ancestor stays retained, after
  // every layer has painted: the choice between the copy and the backdrop
  // is made here, where it can still mark the layer for adding.
  @override
  void updateSubtreeNeedsAddToScene() {
    final served = BackdropUnderlay.enabled ? _serve() : null;
    if (!identical(served, _served)) {
      _served?.dispose();
      _served = served;
      markNeedsAddToScene();
    }
    if (served == null) _underlay.release();
    super.updateSubtreeNeedsAddToScene();
  }

  // The copy drawn into this layer's coordinates, or null while the layer
  // reads the backdrop.
  ui.Picture? _serve() {
    final view = RendererBinding.instance.renderViews.firstOrNull;
    if (view == null || !attached) return null;
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
    final shown = clip.intersect(copy.rect);
    // Read now: a later copy that holds this layer draws its picture.
    final key = (copy.image, copy.offset, shown, m[12], m[13]);
    final served = _served;
    if (served != null && key == _servedKey) return served;
    _servedKey = key;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-m[12], -m[13]);
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
    final served = _served;
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
    _underlay.dispose();
    super.dispose();
  }
}
