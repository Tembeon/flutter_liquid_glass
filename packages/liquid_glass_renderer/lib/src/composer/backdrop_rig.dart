// Layer setup reads as one statement per property, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_frost.dart';
import 'package:liquid_glass_renderer/src/composer/frame_report.dart';
import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/shader_filter.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// The shift from [anchor]'s coordinates to the screen's, in logical pixels,
/// or null when a transform above it scales or turns it.
@internal
Offset? screenOffsetOf(Layer anchor, double devicePixelRatio) {
  final m = _toScreen(anchor, devicePixelRatio).storage;
  if ((m[0] - 1).abs() > 1e-6 ||
      (m[5] - 1).abs() > 1e-6 ||
      m[1].abs() > 1e-6 ||
      m[4].abs() > 1e-6) {
    return null;
  }
  return Offset(m[12], m[13]);
}

Matrix4 _toScreen(Layer anchor, double devicePixelRatio) {
  final toScreen = Matrix4.diagonal3Values(
    1 / devicePixelRatio,
    1 / devicePixelRatio,
    1,
  );
  final chain = <Layer>[];
  for (Layer? node = anchor; node != null; node = node.parent) {
    chain.add(node);
  }
  for (var i = chain.length - 1; i > 0; i--) {
    applyTransformNow(chain[i] as ContainerLayer, chain[i - 1], toScreen);
  }
  return toScreen;
}

/// The need of a copy `backdrop_frost.frag` frosts by [sigma] logical
/// pixels, or null where it cannot: shader frost is off, the renderer is not
/// Impeller (its program is built for Impeller alone), the frost is too wide
/// for it, or the program is not loaded yet.
@internal
CopyNeed? frostNeed(double sigma, {required double devicePixelRatio}) {
  if (!LiquidGlassBackdropFrost.debugShaderFrost ||
      !ui.ImageFilter.isShaderFilterSupported) {
    return null;
  }
  if (!MultiShaderBuilder.isCached(ShaderKeys.backdropFrost)) {
    unawaited(MultiShaderBuilder.precacheShader(ShaderKeys.backdropFrost));
    return null;
  }
  return CopyNeed.edgeFrost(sigma, devicePixelRatio: devicePixelRatio);
}

/// A filtered [copy] drawn into coordinates that [origin] shifts to the
/// screen's: the part [shown], in screen coordinates, cut to [outline], in
/// the drawn coordinates, when there is one.
///
/// The copy already holds the filtered backdrop composited over the
/// backdrop: it replaces what lies under it.
@internal
ui.Picture recordFilteredCopy(
  PageCopy copy,
  Rect shown,
  Offset origin, {
  Path? outline,
}) {
  if (!kReleaseMode) GlassWork.pictures++;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (outline != null) canvas.clipPath(outline);
  canvas.translate(-origin.dx, -origin.dy);
  final paint = Paint();
  paint.blendMode = BlendMode.src;
  paint.filterQuality = FilterQuality.none;
  canvas.drawImageRect(copy.image, copy.readOf(shown).source, shown, paint);
  return recorder.endRecording();
}

/// The shader [recordFrostedCopy] frosts with;
/// its owner disposes it.
@internal
ui.FragmentShader newFrostShader() =>
    MultiShaderBuilder.cached(ShaderKeys.backdropFrost)!.fragmentShader();

/// [frost] drawn from the unblurred [copy] by [shader], into
/// coordinates that [origin] shifts to the screen's: the part [shown], in
/// screen coordinates, composited with [blendMode] and cut to [outline],
/// in the drawn coordinates, when there is one.
///
/// A rect drawn in the copy image's pixels, so that the shader's fragment
/// coordinate is the pixel of the image it frosts around.
@internal
ui.Picture recordFrostedCopy(
  PageCopy copy,
  Rect shown,
  Offset origin, {
  required LiquidGlassBackdropFrost frost,
  required ui.FragmentShader shader,
  BlendMode blendMode = BlendMode.srcOver,
  Path? outline,
}) {
  final read = copy.readOf(shown);
  _setFrost(shader, read.frostSampling(frost.sigma), frost.colorMatrix);
  shader.setImageSampler(0, copy.image, filterQuality: FilterQuality.low);
  if (!kReleaseMode) GlassWork.pictures++;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (outline != null) canvas.clipPath(outline);
  canvas.translate(-origin.dx, -origin.dy);
  read.toImage(canvas);
  final source = read.source;
  final paint = Paint();
  paint.shader = shader;
  paint.blendMode = blendMode;
  paint.isAntiAlias = false;
  canvas.drawRect(source, paint);
  return recorder.endRecording();
}

/// From the screen's device pixels to a frost's coordinates, which begin at
/// [origin] of the screen.
@internal
Matrix4 frostToLocal(Offset origin, double devicePixelRatio) {
  final toLocal = Matrix4.translationValues(-origin.dx, -origin.dy, 0);
  toLocal.scaleByDouble(1 / devicePixelRatio, 1 / devicePixelRatio, 1, 1);
  return toLocal;
}

/// The filter that frosts as [sampling] says, through [colorMatrix].
@internal
ui.ImageFilter frostFilter(
  FrostSampling sampling,
  List<double>? colorMatrix,
  ui.FragmentShader shader,
) {
  _setFrost(shader, sampling, colorMatrix);
  shader.setImageSampler(0, _bilinear, filterQuality: FilterQuality.low);
  return shaderFilterNow(shader);
}

ui.FragmentShader? _inPlaceFrost;

/// The filter that frosts a layer as [sampling] says, or null before its
/// shader is loaded.
@internal
ui.ImageFilter? frostFilterOf(FrostSampling sampling) {
  final shader = _inPlaceFrost ??= MultiShaderBuilder.cached(
    ShaderKeys.backdropFrost,
  )?.fragmentShader();
  if (shader == null) return null;
  final key = (sampling.size, sampling.bounds, sampling.frost, sampling.shown);
  if (_inPlaceFilters[key] case final held?) return held;
  if (_inPlaceFilters.length >= 32) _inPlaceFilters.clear();
  _setFrost(shader, sampling, null);
  shader.setImageSampler(0, _bilinear, filterQuality: FilterQuality.low);
  // The one shader holds other uniforms by the time a scene takes this.
  return _inPlaceFilters[key] = shaderFilterNow(shader);
}

// Chrome over a scroll keeps a copy's place, so its filter too.
final _inPlaceFilters = <Object, ui.ImageFilter>{};

// The uniforms of backdrop_frost.frag.
void _setFrost(
  ui.FragmentShader shader,
  FrostSampling sampling,
  List<double>? colorMatrix,
) {
  final FrostSampling(:size, :bounds, frost: taps, :scale, :shown) = sampling;
  final m = colorMatrix ?? _identityMatrix;
  var i = 0;
  void put(double value) => shader.setFloat(i++, value);
  put(size.width);
  put(size.height);
  put(bounds.left);
  put(bounds.top);
  put(bounds.right);
  put(bounds.bottom);
  put(taps);
  put(scale);
  put(shown.left);
  put(shown.top);
  put(shown.right);
  put(shown.bottom);
  for (var column = 0; column < 4; column++) {
    for (var row = 0; row < 4; row++) {
      put(m[row * 5 + column]);
    }
  }
  for (var row = 0; row < 4; row++) {
    put(m[row * 5 + 4] / 255);
  }
}

// Up to Flutter 3.47 a shader filter samples its input as the image bound
// to the shader's first sampler says (see bilinearShaderFilter).
final ui.Image _bilinear = () {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  return recorder.endRecording().toImageSync(1, 1);
}();

const _identityMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];

/// How a surface reads its backdrop: live, as a backdrop filter in a clip, or
/// over a copy of what lies under it, as the frame's plan says.
///
/// The clip is the surface's outline, or a rect, and the rig keeps its
/// layers from frame to frame.
@internal
class BackdropRig {
  /// Creates a rig whose live reads share the backdrop of [key], if any.
  BackdropRig({this.key});

  /// The backdrop this rig reads live, shared with every other rig of the key,
  /// when the frame's plan gives it no other.
  final BackdropKey? key;

  final _filter = LayerHandle<BackdropFilterLayer>();
  final _clipPath = LayerHandle<ClipPathLayer>();
  final _clipRect = LayerHandle<ClipRectLayer>();

  final _slot = LayerHandle<GlassSlotLayer>();
  final _read = LayerHandle<ReadLayer>();
  final _page = LayerHandle<PictureLayer>();
  Object? _pageKey;

  // What the last [paint] read, for a copy to stand in for. Null when the
  // rig takes no copies.
  _Asked? _asked;
  ui.FragmentShader? _frostShader;

  Path? _outline;

  /// The filter layer the rig reads the backdrop with.
  BackdropFilterLayer? get filterLayer => _filter.layer;

  /// Whether the rig has painted its clip.
  bool get hasClip => _clipRect.layer != null || _clipPath.layer != null;

  /// Whether the last paint left room for a picture over a copy (see
  /// [paintSite]).
  bool get hasSlot => _slot.layer != null;

  /// Paints the live read with [live]. With a [site], it paints in a slot the
  /// site's fate can fill with a read of a copy instead.
  void paintSite(
    PaintingContext context,
    Offset offset, {
    required PlanSite? site,
    required PaintingContextCallback live,
  }) {
    if (site != null) {
      final slot = _slot.layer ??= GlassSlotLayer();
      slot.site = site;
      context.pushLayer(slot, live, offset);
      return;
    }
    _slot.layer = null;
    live(context, offset);
  }

  /// The layer a read of the scene shows in.
  ReadLayer get readLayer => _read.layer ??= ReadLayer();

  /// The picture [record] draws, kept while [key] stays equal.
  PictureLayer pagePicture(
    Object key,
    Rect bounds,
    ui.Picture Function() record,
  ) {
    final previous = _page.layer;
    if (previous != null && _pageKey == key) return previous;
    final picture = PictureLayer(bounds);
    picture.picture = record();
    _page.layer = picture;
    _pageKey = key;
    return picture;
  }

  // Its picture holds the image it reads, an atlas other glass may have left.
  void _dropPage() {
    _page.layer = null;
    _pageKey = null;
  }

  /// The picture [pagePicture] last drew.
  ui.Picture? get pageShown => _page.layer?.picture;

  /// Shows the live read, taken from the backdrop of [group] where the frame's
  /// plan shares one between reads.
  void showLive(BackdropKey? group) {
    _filter.layer?.backdropKey = group ?? key;
    show(null);
  }

  /// Leaves no slot until the next [paintSite].
  void releaseSlot() {
    _slot.layer = null;
  }

  /// Fills the slot with [served] over [under], or with the live read
  /// without [served].
  void show(Layer? served, {Layer? under}) {
    assert(under == null || served != null, 'Only a copy covers [under].');
    if (!identical(served, _page.layer)) _dropPage();
    final slot = _slot.layer;
    if (slot == null) return;
    final child = served ?? _clipRect.layer ?? _clipPath.layer;
    if (child == null) {
      slot.removeAllChildren();
      return;
    }
    final first = under ?? child;
    if (identical(slot.firstChild, first) &&
        identical(first.nextSibling, under == null ? null : child) &&
        child.nextSibling == null) {
      return;
    }
    slot.removeAllChildren();
    if (under != null) {
      under.remove();
      slot.append(under);
    }
    child.remove();
    slot.append(child);
  }

  /// Leaves the slot empty: another layer draws this glass.
  void hide() {
    _dropPage();
    final slot = _slot.layer;
    if (slot?.firstChild != null) slot!.removeAllChildren();
  }

  /// Hands [filter] to the filter layer.
  void bindFilter(ui.ImageFilter filter) {
    final backdrop = _filter.layer ??= _newFilterLayer();
    backdrop.filter = filter;
    backdrop.backdropKey ??= key;
  }

  // A filter made after the clip was painted goes into the clip: a retained
  // refresh does not paint.
  BackdropFilterLayer _newFilterLayer() {
    final backdrop = BackdropFilterLayer();
    (_clipRect.layer ?? _clipPath.layer)?.append(backdrop);
    return backdrop;
  }

  /// Takes the filter layer out of the tree.
  void releaseFilter() {
    _filter.layer?.remove();
    _filter.layer = null;
  }

  /// Paints the clip [outline] (or the rect [bounds] without one) and the filter
  /// in it, [offset] from [context]'s layer. Without [drawsFilter] the clip is
  /// empty.
  void paintLive(
    PaintingContext context,
    Offset offset, {
    required Rect bounds,
    Path? outline,
    bool drawsFilter = true,
  }) {
    void paintFilter(PaintingContext clipContext, Offset clipOffset) {
      final backdrop = _filter.layer;
      if (!drawsFilter || backdrop == null) return;
      clipContext.pushLayer(backdrop, (_, _) {}, clipOffset);
    }

    void paintClip(PaintingContext clipContext, Offset clipOffset) {
      if (outline == null) {
        _clipPath.layer = null;
        _clipRect.layer = clipContext.pushClipRect(
          true,
          clipOffset,
          bounds,
          paintFilter,
          oldLayer: _clipRect.layer,
        );
      } else {
        _clipRect.layer = null;
        final layer = clipContext.pushClipPath(
          true,
          clipOffset,
          bounds,
          outline,
          paintFilter,
          oldLayer: _clipPath.layer,
        );
        _clipPath.layer = layer;
        _outline = layer?.clipPath;
      }
    }

    paintClip(context, offset);
  }

  /// Paints [filter] over the backdrop inside [outline], whose bounds are
  /// [bounds], reading [reach] past them. With a [site], its fate can draw the
  /// filter over a copy of what lies under [outline] instead: where [frost]
  /// stands for [filter], an unblurred copy frosted by a shader.
  void paint(
    PaintingContext context,
    Offset offset, {
    required ui.ImageFilter filter,
    required Rect bounds,
    required Path outline,
    required double reach,
    required double devicePixelRatio,
    PlanSite? site,
    LiquidGlassBackdropFrost? frost,
  }) {
    bindFilter(filter);
    _asked = site != null
        ? (
            filter: filter,
            frost: frost,
            clip: bounds.shift(offset),
            reach: reach,
            devicePixelRatio: devicePixelRatio,
          )
        : null;
    paintSite(
      context,
      offset,
      site: site,
      live: (liveContext, liveOffset) =>
          paintLive(liveContext, liveOffset, bounds: bounds, outline: outline),
    );
  }

  /// Writes what the frame's plan reads of the filter this rig last painted,
  /// which reads an image whenever it reads a copy: the live filter reads the
  /// whole backdrop, not the backdrop cut at the clip, so a filtered copy is
  /// filtered over all it holds.
  void fillPlanFacts(SiteFacts facts) {
    final asked = _asked;
    final anchor = _slot.layer;
    _frosts = false;
    if (anchor == null || asked == null || _outline == null) {
      facts.hidden = true;
      return;
    }
    facts.noJoin = NoJoin.noMatte;
    final origin = screenOffsetOf(anchor, asked.devicePixelRatio);
    _origin = origin;
    if (origin == null) {
      facts.turned = true;
      facts.drawn = MatrixUtils.transformRect(
        _toScreen(anchor, asked.devicePixelRatio),
        asked.clip,
      );
      facts.reads = facts.drawn.inflate(asked.reach);
      return;
    }
    final shifted = asked.clip.shift(origin);
    facts.drawn = shifted;
    final dpr = asked.devicePixelRatio;
    if (asked.frost case final frost?) {
      if (frostNeed(frost.sigma, devicePixelRatio: dpr) case final need?) {
        facts.reads = shifted.inflate(need.reach);
        _frosts = true;
        facts.look = Look(key: null, need: need, page: PageFilter.none);
        return;
      }
    }
    final region = shifted.inflate(asked.reach);
    facts.reads = region;
    facts.look = Look(
      key: null,
      need: CopyNeed.exact(dpr),
      page: PageFilter(filter: asked.filter, clip: region),
    );
  }

  // Where the last [fillPlanFacts] found the clip's coordinates on the screen,
  // and whether a shader frosts the copy there.
  Offset? _origin;
  bool _frosts = false;

  /// Fills the slot with the filter drawn over [page].
  void showPage(PageCopy page) {
    final asked = _asked!;
    final outline = _outline!;
    final origin = _origin!;
    final frost = _frosts ? asked.frost : null;
    final shown = asked.clip.shift(origin).intersect(page.rect);
    show(
      pagePicture(
        (page.image, page.placement, shown, origin, outline, frost),
        asked.clip,
        () => switch (frost) {
          final frost? => recordFrostedCopy(
            page,
            shown,
            origin,
            frost: frost,
            shader: _frostShader ??= newFrostShader(),
            outline: outline,
          ),
          null => recordFilteredCopy(page, shown, origin, outline: outline),
        },
      ),
    );
  }

  /// Sets the clip rect the rig has in place of an outline.
  void clipTo(Rect bounds) {
    final clip = _clipRect.layer;
    if (clip != null && clip.clipRect != bounds) clip.clipRect = bounds;
  }

  /// Releases every layer but the picture over the copy.
  void clear() {
    _asked = null;
    _slot.layer = null;
    _filter.layer = null;
    _clipPath.layer = null;
    _clipRect.layer = null;
    _outline = null;
  }

  /// Releases every layer.
  void dispose() {
    clear();
    _page.layer = null;
    _read.layer = null;
    _frostShader?.dispose();
    _frostShader = null;
  }
}

// A read a copy can stand in for; the clip is in the slot's coordinates.
typedef _Asked = ({
  ui.ImageFilter filter,
  LiquidGlassBackdropFrost? frost,
  Rect clip,
  double reach,
  double devicePixelRatio,
});
