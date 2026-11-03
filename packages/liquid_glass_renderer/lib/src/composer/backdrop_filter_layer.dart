// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';

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
    this._blendMode = BlendMode.srcOver,
    this.copyFilter,
    this.confinesRead = true,
  });

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
    if (identical(value, _filter)) return;
    _filter = value;
    markNeedsAddToScene();
  }

  /// [filter] as an image filter at the copy's own device pixels, for a
  /// filter that reads no further than [reach] and blurs by at most 14 sigma
  /// of those pixels: given, the copy is filtered with the frame's other
  /// copies in one layer instead of reading a backdrop of its own.
  ui.ImageFilter? copyFilter;

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
    final served = recordFilteredCopy(copy, _shown, _origin);
    _servedKey = _keyOf(copy);
    return _served = served;
  }

  // What the picture is drawn from: an equal key draws an equal picture.
  Object _keyOf(UnderlayCopy copy) =>
      (copy.image, copy.offset, _shown, _origin);

  /// The level of the copy in the frame's drawing order while it is not
  /// drawn, or null.
  @internal
  int? get pendingLevel => _copy?.pendingLevel;

  /// The copy this layer filters.
  @visibleForTesting
  BackdropUnderlay get debugUnderlay => _underlay;

  @internal
  @override
  void prepare() {
    _asked = BackdropUnderlay.enabled
        ? requestFilteredCopy(
            _underlay,
            this,
            filter: _filter,
            copyFilter: copyFilter,
            blendMode: _blendMode,
            clip: _clip,
            reach: _reach,
            devicePixelRatio: _devicePixelRatio,
            filtersReach: false,
          )
        : null;
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
    _served?.dispose();
    _served = null;
    _copy = null;
    _underlay.release();
    super.dispose();
  }
}
