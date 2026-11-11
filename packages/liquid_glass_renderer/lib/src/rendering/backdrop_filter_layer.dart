import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_frost.dart';
import 'package:liquid_glass_renderer/src/composer/band_look.dart';
import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_rig.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/form.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
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
  /// Creates the layer.
  LiquidGlassBackdropFilterLayer({
    required this._filter,
    required this._clip,
    required this._reach,
    required this._devicePixelRatio,
    this._blendMode = BlendMode.srcOver,
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
  }) : _frost = frost,
       _filter = frost.filter;

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
  final BlendMode _blendMode;

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

  @override
  SiteNode? formNode;

  // Where this layer's coordinates begin on the screen, while on it untouched.
  Offset? _origin;
  Fate _fate = const Hidden();

  // How this frame's read draws.
  _Scene? _scene;
  Object? _sceneKey;
  ui.ImageFilter? _frostFilter;
  Object? _frostKey;
  ui.Picture? _page;
  Object? _pageKey;
  ui.FragmentShader? _frostShader;

  /// The page this frame draws from, if it draws from one.
  @visibleForTesting
  PageCopy? debugPage;

  /// Whether this frame's frost is drawn in the filter of the glass over it.
  @internal
  bool get drawsGroup => _painterOf(_fate) != null;

  /// Whether this frame draws a copy in place of the backdrop read.
  @internal
  bool get serves => _scene != null || _page != null;

  /// Where this layer's coordinates begin on the screen this frame.
  @internal
  Offset get screenOrigin => _origin ?? Offset.zero;

  /// What the filter covers on the screen this frame.
  @internal
  Rect get shown => _clip.shift(screenOrigin);

  /// The glass that draws this layer's frost in its filter, if any.
  static ReadPainter? _painterOf(Fate fate) => switch (fate) {
    Leads(:final read) when read.members.length > 1 =>
      switch (read.members[1].ask.role) {
        PainterRole(:final painter) => painter,
        _ => null,
      },
    _ => null,
  };

  @override
  SiteAsk ask() {
    final paints = (_filter, _frost, bandPaint, _blendMode);
    final screen = formNode?.screenTransform(Offset.zero);
    final origin = screen == null
        ? screenOffsetOf(this, _devicePixelRatio)
        : MatrixUtils.getAsTranslation(screen);
    _origin = origin;
    if (origin == null) {
      final drawn = screen == null
          ? _clip
          : MatrixUtils.transformRect(screen, _clip);
      return SiteAsk(
        drawn: drawn,
        reads: drawn.inflate(_reach),
        noJoin: NoJoin.noMatte,
        turned: true,
        paints: paints,
      );
    }
    final shifted = _clip.shift(origin);
    final dpr = _devicePixelRatio;
    final frost = _frost;
    final need = frost == null
        ? null
        : frostNeed(frost.sigma, devicePixelRatio: dpr);
    if (frost == null || need == null) {
      return SiteAsk(
        drawn: shifted,
        reads: shifted.inflate(_reach),
        look: Look(
          key: null,
          need: CopyNeed(dpr),
          page: PageFilter(
            filter: _filter,
            clip: shifted,
            blendMode: _blendMode,
          ),
        ),
        noJoin: NoJoin.noMatte,
        paints: paints,
      );
    }
    final over = _blendMode == BlendMode.srcOver;
    final paint = over ? bandPaint : null;
    return SiteAsk(
      drawn: shifted,
      reads: shifted.inflate(need.reach),
      look: Look(
        key: 'band',
        need: need,
        page: over ? null : PageFilter.none,
      ),
      role: paint == null
          ? null
          : BandRole(
              BandLook(
                sigma: frost.sigma,
                paint: paint,
                origin: origin,
                shown: shifted,
                devicePixelRatio: dpr,
              ),
            ),
      noJoin: paint == null ? NoJoin.noMatte : null,
      paints: paints,
    );
  }

  @override
  void beginFate(Fate fate) {
    if (fate.runtimeType != _fate.runtimeType) markNeedsAddToScene();
    _fate = fate;
    if (fate is Hidden) _showNothing();
  }

  void _showNothing() {
    debugPage = null;
    if (_scene != null || _page != null) markNeedsAddToScene();
    _scene = null;
    _sceneKey = null;
    _page?.dispose();
    _page = null;
    _pageKey = null;
  }

  // The frost of the part [corner] holds, as a filter: a band over a scroll
  // keeps its place, so its filter too.
  ui.ImageFilter? _frostOf(CornerRead corner, {required bool held}) {
    final frosting = _frost!;
    final sampling = corner.frostSampling(shown, frosting.sigma, held: held);
    if (sampling == null) return null;
    final key = (
      sampling.size,
      sampling.bounds,
      sampling.frost,
      sampling.scale,
      sampling.shown,
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

  _Scene? _sceneOf(Read read, CornerRead corner) {
    if (_painterOf(_fate) case final painter?) {
      final inPlace = corner.inPlaceFilter();
      return (
        corner: corner,
        filter: painter.readFilter(read, corner, inPlace),
        inPlace: inPlace,
      );
    }
    // A band alone has its frost drawn into the copy, at the copy's pixels.
    final inPlace = corner.inPlaceFilter();
    final filter = _frostOf(corner, held: inPlace != null);
    return filter == null
        ? null
        : (corner: corner, filter: filter, inPlace: inPlace);
  }

  @override
  void show(Read read, ReadPixels pixels) {
    switch (pixels) {
      case InScene(:final corner):
        _showScene(read, corner);
      case OnPage(:final page):
        _showPage(read, page);
      case LiveBackdrop():
        _showNothing();
    }
  }

  void _showScene(Read read, CornerRead corner) {
    final scene = _sceneOf(read, corner);
    if (scene == null) {
      _showNothing();
      return;
    }
    debugPage = null;
    _page?.dispose();
    _page = null;
    _pageKey = null;
    final key = (scene.filter, scene.inPlace, read.geometry.layer, _origin);
    if (read.changed || key != _sceneKey || _scene == null) {
      markNeedsAddToScene();
    }
    _scene = scene;
    _sceneKey = key;
  }

  void _showPage(Read read, PageCopy page) {
    debugPage = page;
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
      ),
      null => recordFilteredCopy(page, region, origin),
    };
    markNeedsAddToScene();
  }

  @override
  void addOutput(SceneOut out, ReadCopy outer) {
    final fate = _fate;
    if (fate is! Leads) return;
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
      inPlace: scene.inPlace,
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
        inPlace: scene.inPlace,
      );
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
    _scene = null;
    super.dispose();
  }
}

// A frost or a group's glass drawn over a layer of the scene.
typedef _Scene = ({
  CornerRead corner,
  ui.ImageFilter filter,
  CopyFrost? inPlace,
});
