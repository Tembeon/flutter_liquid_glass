// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_frost.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';

/// A backdrop filter over [clip] that, wherever it can, filters a copy of
/// what is painted under it instead of reading the backdrop, so a frame
/// whose backdrop effects all draw from copies renders straight to the
/// screen.
///
/// A backdrop filter anywhere in a frame makes Impeller render the whole
/// frame offscreen, split the root pass at every read and blit the result to
/// the screen. This layer draws what lies under [clip] again from the layer
/// tree while the frame composites. For a [frost] the shader can draw,
/// composited with [BlendMode.srcOver], the copy is drawn unblurred in the
/// frame itself and frosted as it is drawn.
/// Any other copy is drawn into a small image, filtered as the backdrop
/// would be, which serves later frames while those layers are unchanged;
/// a frosted copy falls back to an unblurred image at a fraction of the
/// screen's pixels where the frame cannot draw it. Under a texture, a
/// platform view, a live backdrop filter or a layer type the copy cannot
/// draw (see `LiquidGlassUnderlay`) it reads the backdrop like a
/// [BackdropFilterLayer], confined to [reach] around [clip] while
/// [confinesRead].
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
  /// through a shader; null while the filter was given alone, by the default
  /// constructor or the [filter] setter.
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

  /// What this layer's children paint over its frost, set by a caller whose
  /// children paint nothing else: glass over the layer can then draw the band
  /// in its own filter, and the children stay out of the scene.
  FrostBandPaint? bandPaint;

  FilterOffer? _offer;
  FilterGroup? _group;
  FilterGroup? _drawn;

  /// Whether this frame's frost is drawn in the filter of the glass over it.
  @internal
  bool get drawsGroup => _drawn != null;

  CopyAsk? _askCopy() => BackdropUnderlay.enabled
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

  /// Writes what the frame's plan reads of this scroll edge.
  void fillPlanFacts(SiteFacts facts) {
    final offer = _offer;
    facts.hidden = false;
    facts.overSolid = false;
    if (offer is BandOffer) {
      facts.drawn = offer.drawn;
      facts.reads = offer.reads;
      facts.noJoin = null;
      facts.look = Look(
        key: 'band',
        frost: offer.sigma,
        downscale: offer.downscale,
        isBand: true,
      );
      return;
    }
    facts.noJoin = NoJoin.noOffer;
    facts.look = Look.none;
    final origin = screenOffsetOf(this, _devicePixelRatio);
    if (origin == null) {
      facts.hidden = true;
      facts.turned = true;
      return;
    }
    facts.drawn = _clip.shift(origin);
    facts.reads = facts.drawn.inflate(reach);
  }

  FilterOffer? _offerBand() {
    final paint = bandPaint;
    final frost = _frost;
    final view = owner;
    if (paint == null ||
        frost == null ||
        _blendMode != BlendMode.srcOver ||
        !BackdropUnderlay.enabled ||
        view is! RenderView) {
      return null;
    }
    final frame = GlassComposer.planning(view);
    if (frame == null || !frame.groups) return null;
    final origin = screenOffsetOf(this, _devicePixelRatio);
    if (origin == null) return null;
    final sigma = frost.sigma * _devicePixelRatio;
    final downscale = shaderFrostDownscale(sigma, minTexels: 1.5) ?? 1;
    final shown = _clip.shift(origin);
    final offer = _BandOffer(
      this,
      anchor: this,
      underlay: _underlay,
      devicePixelRatio: _devicePixelRatio,
      drawn: shown,
      reads: shown.inflate(
        // The eight taps of the band shader reach 2.8 frosts.
        (2.8 * shaderFrostResidual(sigma, share: downscale) + downscale) /
            _devicePixelRatio,
      ),
      downscale: downscale,
      sigma: frost.sigma,
      origin: origin,
      paint: paint,
    );
    frame.offer(offer);
    return offer;
  }

  // The frost drawn by [group]'s filter: false when the group came apart.
  bool _composeGroup(FilterGroup group) {
    final copy = group.settle();
    if (copy == null) return false;
    final band = group.band!;
    _inFrame = (
      copy: copy,
      shown: band.drawn,
      origin: band.origin,
      frosting: _frost!,
    );
    _drawn = group;
    final read = copy.inScene ? copy.readIn(copy.layer) : null;
    if (read != null) {
      _sceneFilter = group.painter.filter(group, read);
      _sceneFilterKey = null;
      _sceneRead = read;
    } else {
      _served = servedWithin(copy.layer);
      if (_served == null) {
        copy.dispose();
        _inFrame = null;
        _drawn = null;
      }
    }
    return true;
  }

  final _underlay = BackdropUnderlay();
  CopyAsk? _asked;
  ui.FragmentShader? _frostShader;
  _Serving? _serving;
  _InFrame? _inFrame;
  ui.Picture? _served;
  Object? _servedKey;

  // The frost as layers of the scene, for a copy added to the scene too; it
  // is recorded only when a copy for other glass draws it.
  CornerRead? _sceneRead;
  late ui.ImageFilter _sceneFilter;
  Object? _sceneFilterKey;

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
    if (_drawn case final group?) {
      final read = inFrame.copy.readIn(region);
      return read?.record(
        group.painter.filter(group, read),
        frostToLocal(inFrame.origin, _devicePixelRatio),
      );
    }
    return recordFrostedInFrame(
      inFrame.copy,
      inFrame.shown,
      region,
      inFrame.origin,
      frost: inFrame.frosting,
      shader: _frostShader ??= newFrostShader(),
      devicePixelRatio: _devicePixelRatio,
    );
  }

  /// The copy this frame draws in place of the backdrop read, in
  /// this layer's coordinates, or null while the layer reads the backdrop.
  /// A frost drawn in the frame is recorded as the layer composes; one drawn
  /// from an image when first read, once the copy is drawn with the other
  /// copies of the frame.
  @internal
  ui.Picture? get servedPicture {
    if (_served case final served?) return served;
    if (_inFrame case final inFrame?) {
      return _served = servedWithin(inFrame.copy.layer);
    }
    final serving = _serving;
    if (serving == null) return null;
    final (:copy, :shown, :origin, :frosting) = serving;
    final served = switch (frosting) {
      final frost? => recordFrostedCopy(
        copy,
        shown,
        origin,
        frost: frost,
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
    serving.copy.placement,
    serving.shown,
    serving.origin,
    switch (serving.frosting) {
      final frost? => (frost, _blendMode),
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
  void addFold(ui.SceneBuilder builder, FoldTarget target) {
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
    _group = null;
    _offer = _offerBand();
    _asked = _offer == null ? _askCopy() : null;
  }

  // Runs for every built scene, also when an ancestor stays retained, after
  // every layer has painted: the choice between the copy and the backdrop
  // is made here, where it can still mark the layer for adding.
  @internal
  @override
  void compose() {
    var asked = _asked;
    _asked = null;
    final wasInFrame = _inFrame != null;
    _inFrame?.copy.dispose();
    _inFrame = null;
    _sceneRead = null;
    final group = _group;
    final drew = _drawn != null;
    _group = null;
    _drawn = null;
    if (drew || group != null) {
      markNeedsAddToScene();
      _served?.dispose();
      _served = null;
      _servedKey = null;
      _serving = null;
      _sceneFilterKey = null;
    }
    if (group != null) {
      if (_composeGroup(group)) return;
      _offer?.askAlone();
      asked = _asked;
      _asked = null;
    }
    if (asked?.frosting case final frosting?
        when _blendMode == BlendMode.srcOver &&
            _underlay.servesInFrame &&
            _composeInFrame(asked!, frosting)) {
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
  // False when the frame cannot draw the copy, and [serveCopy] takes the
  // request.
  bool _composeInFrame(CopyAsk asked, LiquidGlassBackdropFrost frosting) {
    markNeedsAddToScene();
    _served?.dispose();
    _served = null;
    _servedKey = null;
    _serving = null;
    final copy = _underlay.serveInFrame();
    if (copy == null) return false;
    _inFrame = (
      copy: copy,
      shown: asked.shifted,
      origin: asked.origin,
      frosting: frosting,
    );
    if (_frostInScene(copy, asked.shifted, frosting)) return true;
    _served = servedWithin(copy.layer);
    if (_served == null) {
      copy.dispose();
      _inFrame = null;
    }
    return true;
  }

  bool _frostInScene(
    InFrameCopy copy,
    Rect shown,
    LiquidGlassBackdropFrost frosting,
  ) {
    if (!copy.inScene) return false;
    final read = copy.readIn(copy.layer);
    final sampling = read?.frostSampling(shown, frosting.sigma);
    if (read == null || sampling == null) return false;
    final key = (
      sampling.size,
      sampling.bounds,
      sampling.frost,
      sampling.scale,
      sampling.shown,
      frosting.colorMatrix,
    );
    if (key != _sceneFilterKey) {
      _sceneFilter = frostFilter(
        sampling,
        frosting.colorMatrix,
        _frostShader ??= newFrostShader(),
      );
      _sceneFilterKey = key;
    }
    _sceneRead = read;
    return true;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_sceneRead case final read?) {
      read.addToScene(
        builder,
        _sceneFilter,
        frostToLocal(_inFrame!.origin, _devicePixelRatio),
      );
      if (_drawn == null) addChildrenToScene(builder);
      return;
    }
    final served = servedPicture;
    if (served != null) {
      builder.addPicture(Offset.zero, served);
      if (_drawn == null) addChildrenToScene(builder);
      return;
    }
    if (confinesRead) {
      builder.pushClipRect(_clip.inflate(_reach), clipBehavior: Clip.hardEdge);
      // Under the clip, an identity read gives the filter inside it a pass
      // of the clip's size to read instead of the whole pass behind it.
      builder.pushBackdropFilter(identityColorFilter, blendMode: BlendMode.src);
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
    _inFrame?.copy.dispose();
    _inFrame = null;
    _sceneRead = null;
    _underlay.release();
    super.dispose();
  }
}

final class _BandOffer extends BandOffer {
  _BandOffer(
    this.layer, {
    required super.anchor,
    required super.underlay,
    required super.devicePixelRatio,
    required super.drawn,
    required super.reads,
    required super.downscale,
    required super.sigma,
    required super.origin,
    required super.paint,
  });

  final LiquidGlassBackdropFilterLayer layer;

  @override
  void askAlone() => layer._asked = layer._askCopy();

  @override
  void enter(FilterGroup group) => layer._group = group;
}

/// What a scroll edge paints over its frost, in its layer's coordinates, and
/// how its frost changes the color.
@immutable
final class FrostBandPaint {
  /// Creates the paint.
  const FrostBandPaint({
    required this.fade,
    required this.whole,
    required this.gone,
    required this.lineStart,
    required this.lineEnd,
    required this.lineGray,
    required this.presence,
    required this.saturation,
    required this.brightness,
  });

  @override
  bool operator ==(Object other) =>
      other is FrostBandPaint &&
      other.fade == fade &&
      other.whole == whole &&
      other.gone == gone &&
      other.lineStart == lineStart &&
      other.lineEnd == lineEnd &&
      other.lineGray == lineGray &&
      other.presence == presence &&
      other.saturation == saturation &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(
    fade,
    whole,
    gone,
    lineStart,
    lineEnd,
    lineGray,
    presence,
    saturation,
    brightness,
  );

  /// The fade, straight.
  final Color fade;

  /// The row where the fade is whole.
  final double whole;

  /// The row where the fade is gone.
  final double gone;

  /// Where the hairline starts.
  final double lineStart;

  /// Where the hairline ends.
  final double lineEnd;

  /// The hairline's gray.
  final double lineGray;

  /// How much of the band shows.
  final double presence;

  /// The saturation of what lies under the band.
  final double saturation;

  /// The brightness added.
  final double brightness;
}

// The copy a frame draws in place of the backdrop read, the part of it the
// clip shows and the shift to the screen, as [requestCopy] asked for it.
typedef _Serving = ({
  UnderlayCopy copy,
  Rect shown,
  Offset origin,
  LiquidGlassBackdropFrost? frosting,
});

// A copy drawn in the frame that the frost is drawn from, the part of the
// screen the clip shows and the shift to the screen.
typedef _InFrame = ({
  InFrameCopy copy,
  Rect shown,
  Offset origin,
  LiquidGlassBackdropFrost frosting,
});
