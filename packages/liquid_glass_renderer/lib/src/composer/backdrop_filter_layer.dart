// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_frost.dart';
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
/// tree into a small image while the frame composites: filtered as the
/// backdrop would be, or, for a [frost], unblurred at a fraction of the
/// screen's pixels and frosted by a shader as it is drawn. The image serves
/// later frames while those layers are unchanged. Under a texture, a
/// platform view, a live backdrop filter or a layer type the copy cannot
/// draw (see `LiquidGlassUnderlay`) it reads the backdrop like a
/// [BackdropFilterLayer], confined to [reach] around [clip].
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
  /// copy serves and the frost is narrow enough for the shader; otherwise
  /// the copy is filtered.
  LiquidGlassBackdropFilterLayer.frosted({
    required LiquidGlassBackdropFrost frost,
    required this._clip,
    required this._reach,
    required this._devicePixelRatio,
    this._blendMode = BlendMode.srcOver,
    this.confinesRead = true,
  }) : _frost = frost,
       _filter = frost.filter;

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
  /// through a shader; null for a layer made with [filter] alone.
  LiquidGlassBackdropFrost? get frost => _frost;
  LiquidGlassBackdropFrost? _frost;
  set frost(LiquidGlassBackdropFrost value) {
    if (value == _frost) return;
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
  CopyAsk? _asked;
  ui.FragmentShader? _frostShader;
  _Serving? _serving;
  _InFrame? _inFrame;
  ui.Picture? _served;
  Object? _servedKey;

  /// Whether this frame draws a copy in place of the backdrop read.
  @internal
  bool get serves => _serving != null || _inFrame != null;

  /// The rect of the layer the frost filters, in the screen's logical
  /// pixels, when this frame frosts a copy drawn in the frame.
  @internal
  Rect? get inFrameLayer => _inFrame?.copy.layer;

  /// The frost of a copy drawn in the frame, in this layer's coordinates,
  /// over the part of its layer inside [region] of the screen, or null when
  /// none of it is; a copy for other glass whose pass does not hold
  /// [inFrameLayer] draws it so (see [InFrameGlassLayer]).
  @internal
  ui.Picture? servedWithin(Rect region) {
    final inFrame = _inFrame;
    if (inFrame == null) return null;
    return recordFrostedInFrame(
      inFrame.copy,
      inFrame.shown,
      region,
      inFrame.origin,
      frost: inFrame.frosting.frost,
      taps: inFrame.frosting.taps,
      shader: _frostShader ??= newFrostShader(),
      devicePixelRatio: _devicePixelRatio,
    );
  }

  /// The copy this frame draws in place of the backdrop read, in
  /// this layer's coordinates, or null while the layer reads the backdrop.
  /// Recorded when first read, once the copy is drawn with the other copies
  /// of the frame.
  @internal
  ui.Picture? get servedPicture {
    if (_served case final served?) return served;
    final serving = _serving;
    if (serving == null) return null;
    final (:copy, :shown, :origin, :frosting) = serving;
    final served = switch (frosting) {
      (:final frost, :final taps) => recordFrostedCopy(
        copy,
        shown,
        origin,
        frost: frost,
        taps: taps,
        shader: _frostShader ??= newFrostShader(),
        blendMode: _blendMode,
      ),
      null => recordFilteredCopy(copy, shown, origin),
    };
    _servedKey = _keyOf(serving);
    return _served = served;
  }

  // What the picture is drawn from: an equal key draws an equal picture.
  Object _keyOf(_Serving serving) => (
    serving.copy.image,
    serving.copy.offset,
    serving.shown,
    serving.origin,
    switch (serving.frosting) {
      (:final frost, taps: _) => (frost, _blendMode),
      null => null,
    },
  );

  /// Whether the copy this frame filters is drawn with the frame's copies,
  /// not yet drawn.
  @internal
  bool get pending => _serving?.copy.pending ?? false;

  /// Adds the filter to a copy drawn with the frame's copies that holds this
  /// layer while its own copy is not drawn yet (see [UnderlayFold]).
  @internal
  void addFold(ui.SceneBuilder builder, Rect rect, Offset offset) {
    final serving = _serving;
    if (serving == null) return;
    addFoldedFilter(
      builder,
      serving.shown.shift(-serving.origin),
      _filter,
      blendMode: _blendMode,
    );
  }

  /// The copy this layer filters.
  @visibleForTesting
  BackdropUnderlay get debugUnderlay => _underlay;

  @internal
  @override
  void prepare() {
    _asked = BackdropUnderlay.enabled
        ? requestCopy(
            _underlay,
            this,
            filter: _filter,
            frost: _frost,
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
    final wasInFrame = _inFrame != null;
    _inFrame?.copy.content.dispose();
    _inFrame = null;
    if (asked?.frosting case final frosting?
        when _blendMode == BlendMode.srcOver && _underlay.servesInFrame) {
      _composeInFrame(asked!, frosting);
      return;
    }
    final served = asked == null ? null : serveCopy(_underlay, asked);
    final serving = served == null
        ? null
        : (
            copy: served.copy,
            shown: served.shown,
            origin: asked!.origin,
            frosting: asked.frosting,
          );
    // A copy drawn in an earlier frame keeps its picture while it lies where
    // it did; a copy not drawn yet is drawn with the frame's other copies.
    final key = serving != null && serving.copy.ready ? _keyOf(serving) : null;
    if (serving == null || key == null || key != _servedKey) {
      if (wasInFrame || _serving != null || serving != null) {
        markNeedsAddToScene();
      }
      _served?.dispose();
      _served = null;
    }
    _serving = serving;
    _servedKey = key;
    if (serving == null) _underlay.release();
  }

  // A frost drawn from a copy the frame draws again: a picture each frame.
  void _composeInFrame(CopyAsk asked, CopyFrosting frosting) {
    markNeedsAddToScene();
    _served?.dispose();
    _served = null;
    _servedKey = null;
    _serving = null;
    final copy = _underlay.serveInFrame();
    if (copy == null) {
      _underlay.release();
      return;
    }
    _inFrame = (
      copy: copy,
      shown: asked.shifted,
      origin: asked.origin,
      frosting: frosting,
    );
    _served = servedWithin(copy.layer);
    if (_served == null) {
      copy.content.dispose();
      _inFrame = null;
    }
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
    _serving = null;
    _inFrame?.copy.content.dispose();
    _inFrame = null;
    _underlay.release();
    super.dispose();
  }
}

// The copy a frame draws in place of the backdrop read, the part of it the
// clip shows and the shift to the screen, as [requestCopy] asked for it.
typedef _Serving = ({
  UnderlayCopy copy,
  Rect shown,
  Offset origin,
  CopyFrosting? frosting,
});

// A copy drawn in the frame that the frost is drawn from, the part of the
// screen the clip shows and the shift to the screen.
typedef _InFrame = ({
  InFrameCopy copy,
  Rect shown,
  Offset origin,
  CopyFrosting frosting,
});
