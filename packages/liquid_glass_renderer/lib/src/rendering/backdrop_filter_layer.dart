import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/src/composer/band_look.dart';
import 'package:liquid_glass_renderer/src/composer/copy_place.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';
import 'package:liquid_glass_renderer/src/composer/screen_place.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';

/// A backdrop filter over [clip] that, wherever it can, filters a copy of
/// what is painted under it instead of reading the backdrop, so a frame
/// whose backdrop effects all draw from copies renders straight to the
/// screen.
///
/// A backdrop filter anywhere in a frame makes Impeller render the whole
/// frame offscreen, split the root pass at every read and blit the result to
/// the screen. This layer draws what lies under [clip] again from the layer
/// tree, as the frame's plan says. For a [frost] the shader can draw,
/// composited with [BlendMode.srcOver], the copy is drawn unblurred in the
/// frame itself and frosted as it is drawn.
/// Any other copy is drawn into a small image, filtered as the backdrop
/// would be, which serves later frames while those layers are unchanged. Under
/// a texture, a platform view, a live backdrop filter or a layer type the copy
/// cannot draw (see `LiquidGlassUnderlay`) it reads the backdrop like a
/// [BackdropFilterLayer].
///
/// The filter applies to the screen-aligned backdrop: under a transform that
/// scales or turns the layer, it reads the backdrop.
class LiquidGlassBackdropFilterLayer extends ContainerLayer
    with ComposedLayer
    implements PlanSite {
  /// Creates the layer for [filter], a blur by [sigma] logical pixels and
  /// whatever follows it.
  LiquidGlassBackdropFilterLayer({
    required this._filter,
    required this._sigma,
    required this._clip,
    this._blendMode = BlendMode.srcOver,
  });

  /// Creates the band of a scroll edge: what lies under [clip] frosted by
  /// [sigma] logical pixels, as [paint] says, and drawn in the filter of
  /// glass over it where glass is, with the layer's children left out.
  LiquidGlassBackdropFilterLayer.band({
    required double sigma,
    required FrostBandPaint paint,
    required Rect clip,
  }) : this._band(sigma, paint, clip, _bandFrost(sigma, paint, 1));

  LiquidGlassBackdropFilterLayer._band(
    this._sigma,
    this._bandPaint,
    this._clip,
    LiquidGlassBackdropFrost frost,
  ) : _frost = frost,
      _filter = frost.filter,
      _blendMode = BlendMode.srcOver;

  /// The filter applied to what lies under [clip], composited over it as a
  /// [BackdropFilterLayer] composites its output.
  ui.ImageFilter get filter => _filter;
  ui.ImageFilter _filter;
  set filter(ui.ImageFilter value) {
    assert(_bandPaint == null, "A band's filter follows its paint.");
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
    assert(_bandPaint == null, "A band's frost follows its paint.");
    _sigma = value.sigma;
    _setFrost(value);
  }

  void _setFrost(LiquidGlassBackdropFrost value) {
    if (value == _frost) return;
    _frost = value;
    _filter = value.filter;
    markNeedsAddToScene();
  }

  /// The blur asked of [filter], in logical pixels.
  double get sigma => _sigma;
  double _sigma;
  set sigma(double value) {
    if (value == _sigma) return;
    _sigma = value;
    if (_bandPaint != null) {
      _resolveBand();
    } else {
      markNeedsAddToScene();
    }
  }

  // How the filtered backdrop composites over the backdrop, as
  // BackdropFilterLayer.blendMode does.
  final BlendMode _blendMode;

  /// Where the filter applies, in this layer's coordinates.
  Rect get clip => _clip;
  Rect _clip;
  set clip(Rect value) {
    if (value == _clip) return;
    _clip = value;
    markNeedsAddToScene();
  }

  double _devicePixelRatio = 1;

  /// What a band paints over its frost, or null for a layer that is no
  /// band.
  FrostBandPaint? get bandPaint => _bandPaint;
  FrostBandPaint? _bandPaint;
  set bandPaint(FrostBandPaint value) {
    final old = _bandPaint;
    assert(old != null, 'Only a band has a band paint.');
    if (value == old) return;
    _bandPaint = value;
    if (value.dissolve != old?.dissolve) markNeedsAddToScene();
    _resolveBand();
  }

  void _resolveBand() =>
      _setFrost(_bandFrost(_sigma, _bandPaint!, _devicePixelRatio));

  static LiquidGlassBackdropFrost _bandFrost(
    double sigma,
    FrostBandPaint paint,
    double devicePixelRatio,
  ) => LiquidGlassBackdropFrost(
    sigma: ImpellerBlur.halfResolution(sigma, devicePixelRatio),
    colorMatrix: paint.colorMatrix,
  );

  // Where the frost dissolves into what lies under it, in this layer's rows:
  // where the fade over it does.
  FrostDissolve get _dissolve => switch (_bandPaint) {
    final paint? when _blendMode == BlendMode.srcOver => paint.dissolve,
    _ => FrostDissolve.none,
  };

  ui.Picture? _mask;
  Object? _maskKey;

  @override
  SiteNode? formNode;

  // Where this layer's coordinates begin on the screen, while on it untouched.
  Offset? _origin;
  SiteFate _fate = const HiddenFate();

  // How this frame's read draws.
  _Scene? _scene;
  Object? _sceneKey;

  // What the read of the scene keeps between the scenes it is added to.
  final _held = HeldLayers();
  ui.ImageFilter? _frostFilter;
  Object? _frostKey;
  ui.Picture? _page;
  Object? _pageKey;
  ui.FragmentShader? _frostShader;

  PageCopy? _debugPage;

  /// Whether this frame's frost is drawn in the filter of the glass over it.
  @visibleForTesting
  bool get drawsGroup => _painterOf(_fate) != null;

  /// Whether this frame draws a copy in place of the backdrop read.
  @visibleForTesting
  bool get serves => _scene != null || _page != null;

  /// Where this layer's coordinates begin on the screen this frame.
  @internal
  Offset get screenOrigin => _origin ?? Offset.zero;

  /// What the filter covers on the screen this frame.
  @internal
  Rect get shown => _clip.shift(screenOrigin);

  /// The glass that draws this layer's frost in its filter, if any.
  static ReadPainter? _painterOf(SiteFate fate) => switch (fate) {
    LeadFate(:final read) => switch (read.bandPainter?.ask.role) {
      PainterRole(:final painter) => painter,
      _ => null,
    },
    _ => null,
  };

  @override
  SiteAsk ask(ViewPixels view) {
    final dpr = view.devicePixelRatio;
    if (dpr != _devicePixelRatio) {
      _devicePixelRatio = dpr;
      if (_bandPaint != null) _resolveBand();
    }
    final screen = formNode?.screenTransform(Offset.zero);
    final place = screen == null
        ? screenPlaceOf(this, dpr)
        : ScreenPlace.of(screen);
    _origin = place is Shifted ? place.offset : null;
    final frost = _frost;
    final paint = bandPaint;
    return backdropFilterAsk(
      clip: _clip,
      place: place,
      toScreen: () => screen ?? Matrix4.identity(),
      filter: _filter,
      sigma: _sigma,
      frost: frost,
      blendMode: _blendMode,
      inScene: true,
      band: frost == null || paint == null
          ? null
          : (shown, origin) => BandLook(
              sigma: frost.sigma,
              paint: paint,
              origin: origin,
              shown: shown,
              devicePixelRatio: dpr,
            ),
      devicePixelRatio: dpr,
      paints: (_filter, frost, paint, _blendMode),
    );
  }

  @override
  void beginFate(SiteFate fate) {
    if (fate.runtimeType != _fate.runtimeType) markNeedsAddToScene();
    _fate = fate;
    if (fate is HiddenFate) _showNothing();
  }

  void _showNothing() {
    _debugPage = null;
    if (_scene != null || _page != null) markNeedsAddToScene();
    _scene = null;
    _sceneKey = null;
    _page?.dispose();
    _page = null;
    _pageKey = null;
  }

  // The frost of the part [corner] holds, as a filter: a band over a scroll
  // keeps its place, so its filter too.
  ui.ImageFilter? _frostOf(CornerRead corner) {
    final frosting = _frost!;
    final sampling = corner.frostSampling(
      shown,
      frosting.sigma,
      dissolve: _dissolve.mapped(screenOrigin.dy, 1),
    );
    if (sampling == null) return null;
    final key = (
      sampling.size,
      sampling.bounds,
      sampling.frost,
      sampling.scale,
      sampling.shown,
      sampling.dissolve,
      frosting.colorMatrix,
    );
    if (key != _frostKey || _frostFilter == null) {
      _frostFilter = frostFilter(
        sampling,
        frosting.colorMatrix,
        _frostShader ??= newFrostShader(),
      );
      _frostKey = key;
    }
    return _frostFilter;
  }

  _Scene? _sceneOf(GlassRead read, CornerRead corner) {
    if (_painterOf(_fate) case final painter?) {
      return (corner: corner, filter: painter.readFilter(read, corner));
    }
    // A band alone has its frost drawn into the copy, at the copy's pixels.
    final filter = _frostOf(corner);
    return filter == null ? null : (corner: corner, filter: filter);
  }

  @override
  void show(GlassRead read, ReadPixels pixels) {
    switch (pixels) {
      case ScenePixels(:final corner):
        _showScene(read, corner);
      case ImagePixels(:final page):
        _showPage(read, page);
      case LivePixels():
        _showNothing();
    }
  }

  void _showScene(GlassRead read, CornerRead corner) {
    final scene = _sceneOf(read, corner);
    if (scene == null) {
      _showNothing();
      return;
    }
    _debugPage = null;
    _page?.dispose();
    _page = null;
    _pageKey = null;
    final key = (
      scene.filter,
      scene.corner.inPlace.filter,
      read.geometry.layer,
      _origin,
    );
    if (read.changed || key != _sceneKey || _scene == null) {
      markNeedsAddToScene();
    }
    _scene = scene;
    _sceneKey = key;
  }

  void _showPage(GlassRead read, PageCopy page) {
    _debugPage = page;
    final painter = _painterOf(_fate);
    final origin = screenOrigin;
    final region = shown.intersect(page.rect);
    final key = (
      page.image,
      page.placement,
      region,
      origin,
      _frost,
      _blendMode,
      _dissolve,
      painter?.pageKey(read, page),
    );
    _scene = null;
    _sceneKey = null;
    if (key == _pageKey && _page != null) return;
    _page?.dispose();
    _pageKey = key;
    _page = switch (painter) {
      final painter? => painter.recordPage(
        read,
        page,
        frostToLocal(origin, _devicePixelRatio),
      ),
      null when read.lead.ask.look.page?.key == null => recordFrostedCopy(
        page,
        region,
        origin,
        frost: _frost!,
        shader: _frostShader ??= newFrostShader(),
        blendMode: _blendMode,
        dissolve: _dissolve.mapped(origin.dy, 1),
      ),
      null => recordFilteredCopy(
        page,
        region,
        origin,
        dissolve: _dissolve.mapped(origin.dy, 1),
      ),
    };
    markNeedsAddToScene();
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    final fate = _fate;
    if (fate is! LeadFate) return;
    final read = fate.read;
    if (read.source is ImageRead) {
      if (_page case final page?) out.picture(page);
      return;
    }
    final corner = outer.cornerOf(read);
    final scene = corner == null ? null : _sceneOf(read, corner);
    if (scene == null) return;
    out.settle();
    scene.corner.addToScene(
      out.builder,
      scene.filter,
      frostToLocal(screenOrigin, _devicePixelRatio),
      out.held,
    );
  }

  @override
  bool get drawsOwnChildren => drawsGroup;

  @override
  bool get outputsInPlace => true;

  @override
  void endFrame() {}

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_scene case final scene?) {
      scene.corner.addToScene(
        builder,
        scene.filter,
        frostToLocal(screenOrigin, _devicePixelRatio),
        _held,
      );
      _held.built();
      if (!drawsGroup) addChildrenToScene(builder);
      return;
    }
    if (_page case final page?) {
      builder.addPicture(Offset.zero, page);
      if (!drawsGroup) addChildrenToScene(builder);
      return;
    }
    builder
      ..pushClipRect(_clip, clipBehavior: Clip.hardEdge)
      ..pushBackdropFilter(_filter, blendMode: _blendMode);
    final dissolve = _dissolve;
    if (!dissolve.isNone) {
      final key = (_clip, dissolve);
      if (key != _maskKey || _mask == null) {
        _mask?.dispose();
        final recorder = ui.PictureRecorder();
        paintFrostDissolve(Canvas(recorder), _clip, dissolve);
        _mask = recorder.endRecording();
        _maskKey = key;
      }
      builder.addPicture(Offset.zero, _mask!);
    }
    addChildrenToScene(builder);
    builder
      ..pop()
      ..pop();
  }

  @override
  void dispose() {
    _frostShader?.dispose();
    _frostShader = null;
    _page?.dispose();
    _page = null;
    _mask?.dispose();
    _mask = null;
    _scene = null;
    _held.dispose();
    super.dispose();
  }
}

/// A render object that holds a [LiquidGlassBackdropFilterLayer].
///
/// While attached it is registered with the glass composer of its view, which
/// then plans each frame's scene before it is built, as it does for glass, and
/// lives until the last render object registered with it detaches. A view
/// whose backdrop filter layers are held by no such render object fails an
/// assertion in a debug build.
mixin LiquidGlassBackdropFilterHost on RenderObject {
  /// The [LiquidGlassBackdropFilterLayer] this render object holds, or null
  /// while it holds none.
  Layer? get composedLayer;

  @mustCallSuper
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlassComposer.host(owner, this);
  }

  @mustCallSuper
  @override
  void detach() {
    GlassComposer.unhost(owner!, this);
    super.detach();
  }
}

/// What a [LiquidGlassBackdropFilterLayer] drew, for the package's tests.
extension LiquidGlassBackdropFilterLayerDebug
    on LiquidGlassBackdropFilterLayer {
  /// The page this frame draws from, if it draws from one.
  PageCopy? get debugPage => _debugPage;
}

// A frost or a group's glass drawn over a layer of the scene.
typedef _Scene = ({CornerRead corner, ui.ImageFilter filter});
