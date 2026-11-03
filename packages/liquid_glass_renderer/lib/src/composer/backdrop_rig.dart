// Layer setup reads as one statement per property, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_frost.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/shader_filter.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// The shift from [anchor]'s coordinates to the screen's, in logical pixels,
/// or null when a transform above it scales or turns it.
@internal
Offset? screenOffsetOf(Layer anchor, double devicePixelRatio) {
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
  final m = toScreen.storage;
  if ((m[0] - 1).abs() > 1e-6 ||
      (m[5] - 1).abs() > 1e-6 ||
      m[1].abs() > 1e-6 ||
      m[4].abs() > 1e-6) {
    return null;
  }
  return Offset(m[12], m[13]);
}

/// How a shader frosts a copy: the frost, and the taps that draw it.
@internal
typedef CopyFrosting = ({LiquidGlassBackdropFrost frost, ShaderFrost taps});

/// A copy [requestCopy] asked for: the part of the screen the clip covers,
/// the shift from the anchor's coordinates to the screen's, and how a shader
/// frosts the copy, or null when the copy is filtered.
@internal
typedef CopyAsk = ({Rect shifted, Offset origin, CopyFrosting? frosting});

/// Asks [underlay] for a copy of what lies under [clip], in [anchor]'s
/// coordinates, that [filter] composited with [blendMode] stands on;
/// [serveCopy] hands it over. Null where none can serve: [anchor] does not
/// lie on the screen untransformed.
///
/// Where [frost] stands for [filter] and the shader can draw it, the copy is
/// unblurred, at the fraction of the screen's pixels the frost allows, for
/// the frost shader to draw. The shader cannot when shader frost is off, the
/// renderer is not Impeller (its program is built for Impeller alone), the
/// frost is too wide for it, or the program is not loaded yet. Otherwise
/// the copy holds [reach] around [clip] run through [filter] as a backdrop
/// filter: with [filtersReach] over all of it, as a live filter that reads
/// a pass reaching past its clip does; without, inside [clip] only.
@internal
CopyAsk? requestCopy(
  BackdropUnderlay underlay,
  Layer anchor, {
  required ui.ImageFilter filter,
  required LiquidGlassBackdropFrost? frost,
  required BlendMode blendMode,
  required Rect clip,
  required double reach,
  required double devicePixelRatio,
  required bool filtersReach,
}) {
  final origin = screenOffsetOf(anchor, devicePixelRatio);
  if (origin == null) return null;
  final shifted = clip.shift(origin);
  if (frost != null) {
    if (_frostTaps(frost, devicePixelRatio) case final taps?) {
      // The taps reach 2.8 sigma, one copy pixel more sampled bilinearly.
      final frostReach = (2.8 * taps.frost + taps.downscale) / devicePixelRatio;
      underlay.request(
        anchor: anchor,
        devicePixelRatio: devicePixelRatio,
        region: shifted.inflate(frostReach),
        downscale: taps.downscale,
      );
      return (
        shifted: shifted,
        origin: origin,
        frosting: (frost: frost, taps: taps),
      );
    }
  }
  final region = shifted.inflate(reach);
  underlay.request(
    anchor: anchor,
    devicePixelRatio: devicePixelRatio,
    region: region,
    filter: filter,
    filterClip: filtersReach ? region : shifted,
    filterBlendMode: blendMode,
  );
  return (shifted: shifted, origin: origin, frosting: null);
}

// How the shader frosts [frost], or null where it cannot (see requestCopy).
ShaderFrost? _frostTaps(
  LiquidGlassBackdropFrost frost,
  double devicePixelRatio,
) {
  if (!LiquidGlassBackdropFrost.debugShaderFrost ||
      !ui.ImageFilter.isShaderFilterSupported) {
    return null;
  }
  if (!MultiShaderBuilder.isCached(ShaderKeys.backdropFrost)) {
    unawaited(MultiShaderBuilder.precacheShader(ShaderKeys.backdropFrost));
    return null;
  }
  // A copy whose pixels the frost spans by less than 1.5 is not halved
  // again: drawn smaller, its edges show through the frost.
  return shaderFrost(frost.sigma * devicePixelRatio, minTexels: 1.5);
}

/// The copy [asked] stands for and the part of it the clip shows, in
/// screen coordinates. Null where none serves.
@internal
({UnderlayCopy copy, Rect shown})? serveCopy(
  BackdropUnderlay underlay,
  CopyAsk asked,
) {
  final copy = underlay.serve();
  if (copy == null) return null;
  return (copy: copy, shown: asked.shifted.intersect(copy.rect));
}

/// Adds [filter] composited with [blendMode] as a backdrop filter inside
/// [clip] and [outline], in the caller's coordinates: glass a copy drawn
/// with its own holds (see [UnderlayFold]). A shader filter takes its
/// shader's uniforms now.
@internal
void addFoldedFilter(
  ui.SceneBuilder builder,
  Rect clip,
  ui.ImageFilter filter, {
  BlendMode blendMode = BlendMode.srcOver,
  Path? outline,
}) {
  builder.pushClipRect(clip, clipBehavior: Clip.hardEdge);
  if (outline != null) builder.pushClipPath(outline);
  builder.pushBackdropFilter(filter, blendMode: blendMode);
  builder.pop();
  if (outline != null) builder.pop();
  builder.pop();
}

/// A filtered [copy] drawn into coordinates that [origin] shifts to the
/// screen's: the part [shown], in screen coordinates, cut to [outline], in
/// the drawn coordinates, when there is one.
///
/// The copy already holds the filtered backdrop composited over the
/// backdrop: it replaces what lies under it.
@internal
ui.Picture recordFilteredCopy(
  UnderlayCopy copy,
  Rect shown,
  Offset origin, {
  Path? outline,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (outline != null) canvas.clipPath(outline);
  canvas.translate(-origin.dx, -origin.dy);
  final source = shown.shift(-copy.rect.topLeft);
  final offset = copy.offset;
  final paint = Paint();
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

/// The shader [recordFrostedCopy] and [recordFrostedInFrame] frost with;
/// its owner disposes it.
@internal
ui.FragmentShader newFrostShader() =>
    MultiShaderBuilder.cached(ShaderKeys.backdropFrost)!.fragmentShader();

/// [frost] drawn from the unblurred [copy] by [shader] as [taps] say, into
/// coordinates that [origin] shifts to the screen's: the part [shown], in
/// screen coordinates, composited with [blendMode] and cut to [outline],
/// in the drawn coordinates, when there is one.
///
/// A rect drawn in the copy image's pixels, so that the shader's fragment
/// coordinate is the pixel of the image it frosts around.
@internal
ui.Picture recordFrostedCopy(
  UnderlayCopy copy,
  Rect shown,
  Offset origin, {
  required LiquidGlassBackdropFrost frost,
  required ShaderFrost taps,
  required ui.FragmentShader shader,
  BlendMode blendMode = BlendMode.srcOver,
  Path? outline,
}) {
  final image = copy.image;
  final offset = copy.offset;
  final pixels = copy.pixelRatio;
  final source = Rect.fromLTRB(
    (shown.left - copy.rect.left) * pixels + offset.dx,
    (shown.top - copy.rect.top) * pixels + offset.dy,
    (shown.right - copy.rect.left) * pixels + offset.dx,
    (shown.bottom - copy.rect.top) * pixels + offset.dy,
  );
  _setFrost(
    shader,
    size: Size(image.width.toDouble(), image.height.toDouble()),
    bounds: Rect.fromLTRB(
      offset.dx + 0.5,
      offset.dy + 0.5,
      offset.dx + copy.rect.width * pixels - 0.5,
      offset.dy + copy.rect.height * pixels - 0.5,
    ),
    frost: frost,
    taps: taps,
    scale: 1,
    // The rect drawn bounds the frost.
    shown: Rect.largest,
  );
  shader.setImageSampler(0, image, filterQuality: FilterQuality.low);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (outline != null) canvas.clipPath(outline);
  canvas.translate(shown.left - origin.dx, shown.top - origin.dy);
  canvas.scale(1 / pixels);
  canvas.translate(-source.left, -source.top);
  final paint = Paint();
  paint.shader = shader;
  paint.blendMode = blendMode;
  paint.isAntiAlias = false;
  canvas.drawRect(source, paint);
  return recorder.endRecording();
}

/// [frost] drawn by [shader] as [taps] say from [copy], drawn in the frame
/// (see [BackdropUnderlay.serveInFrame]), into coordinates that [origin]
/// shifts to the screen's: the part of [shown] inside [region], both in
/// screen coordinates, or null where none of it is.
///
/// The shader filters a layer of the screen's pixels over the part of the
/// copy's layer inside [region], whose top-left corner holds the copy at its
/// own pixels, and covers each pixel as much as it lies inside [shown]: a
/// clip would also cut the copy the layer holds. NEAR: on a row of pixels
/// the edge of [shown] splits, up to 29 channel levels off the frost of an
/// image, which a clip covers otherwise (2.625 dpr, the scroll edge host
/// test). Composited with [BlendMode.srcOver] only: past [shown] the layer
/// is transparent.
@internal
ui.Picture? recordFrostedInFrame(
  InFrameCopy copy,
  Rect shown,
  Rect region,
  Offset origin, {
  required LiquidGlassBackdropFrost frost,
  required ShaderFrost taps,
  required ui.FragmentShader shader,
  required double devicePixelRatio,
}) {
  final cut = region.intersect(copy.layer);
  final drawn = shown.intersect(cut);
  if (drawn.isEmpty) return null;
  final dpr = devicePixelRatio;
  final pixels = copy.pixelRatio;
  final stretch = (dpr / pixels).roundToDouble();
  final layer = Rect.fromLTRB(
    (cut.left * pixels).floorToDouble() * stretch,
    (cut.top * pixels).floorToDouble() * stretch,
    (cut.right * pixels).ceilToDouble() * stretch,
    (cut.bottom * pixels).ceilToDouble() * stretch,
  );
  // Where the copy's top left lies in the layer, in the copy's pixels.
  final at = Offset(
    (copy.band.left * dpr - layer.left) / stretch,
    (copy.band.top * dpr - layer.top) / stretch,
  );
  _setFrost(
    shader,
    size: layer.size,
    bounds: Rect.fromLTRB(
      max(at.dx, 0) + 0.5,
      max(at.dy, 0) + 0.5,
      min(at.dx + copy.band.width * pixels, layer.width / stretch) - 0.5,
      min(at.dy + copy.band.height * pixels, layer.height / stretch) - 0.5,
    ),
    frost: frost,
    taps: taps,
    scale: 1 / stretch,
    shown: Rect.fromLTRB(
      drawn.left * dpr,
      drawn.top * dpr,
      drawn.right * dpr,
      drawn.bottom * dpr,
    ).shift(-layer.topLeft),
  );
  shader.setImageSampler(0, _bilinear, filterQuality: FilterQuality.low);
  final paint = Paint();
  paint.imageFilter = bilinearShaderFilter(shader);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(-origin.dx, -origin.dy);
  canvas.scale(1 / dpr);
  canvas.saveLayer(layer, paint);
  // Impeller sizes a layer by what is drawn in it: a pixel cleared at each
  // corner holds it to [layer] where the copy is transparent.
  final clear = Paint();
  clear.blendMode = BlendMode.clear;
  canvas.drawRect(Rect.fromLTWH(layer.left, layer.top, 1, 1), clear);
  canvas.drawRect(
    Rect.fromLTRB(layer.right - 1, layer.bottom - 1, layer.right, layer.bottom),
    clear,
  );
  canvas.translate(layer.left + at.dx, layer.top + at.dy);
  canvas.drawPicture(copy.content);
  canvas.restore();
  return recorder.endRecording();
}

// The uniforms of backdrop_frost.frag.
void _setFrost(
  ui.FragmentShader shader, {
  required Size size,
  required Rect bounds,
  required LiquidGlassBackdropFrost frost,
  required ShaderFrost taps,
  required double scale,
  required Rect shown,
}) {
  final m = frost.colorMatrix ?? _identityMatrix;
  var i = 0;
  void put(double value) => shader.setFloat(i++, value);
  put(size.width);
  put(size.height);
  put(bounds.left);
  put(bounds.top);
  put(bounds.right);
  put(bounds.bottom);
  put(taps.frost / taps.downscale);
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

/// Places a rig's pass around a clip, given in the layer coordinates it is
/// painted in, the paint offset from the owner, how far the blur reads past
/// the clip, and the [BackdropPassSizing] that holds the pass's size from
/// frame to frame.
@internal
typedef BackdropPassPlanner = BackdropPassPlan Function(
  Rect inner,
  Offset offset,
  double reach,
  BackdropPassSizing sizing,
);

/// How a surface reads its backdrop: live, as a backdrop filter in a clip,
/// the clip in a seeded pass where seeds are on (see
/// [SeededBackdropPassLayer]), or as a picture the surface draws over a copy
/// of what lies under it (see [BackdropUnderlay]), chosen per frame while
/// the scene composites.
///
/// The clip is the surface's outline, or a rect, and the rig keeps its
/// layers from frame to frame.
@internal
class BackdropRig {
  /// Creates a rig whose passes are placed by [plan] and whose reads share
  /// [share], if any.
  BackdropRig({
    required this.plan,
    this.share,
    this.seedWhileResizing = false,
    this.onActiveChanged,
  });

  /// Places the pass.
  final BackdropPassPlanner plan;

  /// The backdrop read this rig shares with others, if any.
  final BackdropShare? share;

  /// Whether the pass stays seeded while its size changes (see
  /// [SeededBackdropPassLayer.seedWhileResizing]).
  final bool seedWhileResizing;

  /// Runs, after the clip follows, when the pass starts or stops being in
  /// effect as it composes.
  final VoidCallback? onActiveChanged;

  final _filter = LayerHandle<BackdropFilterLayer>();
  final _clipPath = LayerHandle<ClipPathLayer>();
  final _clipRect = LayerHandle<ClipRectLayer>();
  final _pass = LayerHandle<SeededBackdropPassLayer>();
  final _sizing = BackdropPassSizing();

  final _underlay = BackdropUnderlay();
  final _slot = LayerHandle<ContainerLayer>();
  final _served = LayerHandle<PictureLayer>();
  Object? _servedKey;

  // What the last [paint] read, for a copy to stand in for. Null when the
  // rig takes no copies.
  _Read? _read;
  // The copy asked for this frame, until [compose].
  CopyAsk? _asked;
  ui.FragmentShader? _frostShader;

  Rect? _inner;
  Offset _offset = Offset.zero;
  double _reach = 0;
  BackdropPassPlan _plan = BackdropPassPlan.unsupported;

  // The clip without a pass: the outline, or the rect.
  Path? _outline;
  Rect? _clipBounds;

  Rect? _rectPathRect;
  Path? _rectPath;

  /// The filter layer the rig reads the backdrop with.
  BackdropFilterLayer? get filterLayer => _filter.layer;

  /// The pass the filter paints in, if the rig has one.
  SeededBackdropPassLayer? get passLayer => _pass.layer;

  /// The pass's plan while it is in effect, otherwise
  /// [BackdropPassPlan.unsupported].
  BackdropPassPlan get passPlan =>
      _pass.layer?.passRect != null ? _plan : BackdropPassPlan.unsupported;

  /// Whether the rig has painted its clip.
  bool get hasClip => _clipRect.layer != null || _clipPath.layer != null;

  /// The copy of what lies under the surface.
  BackdropUnderlay get underlay => _underlay;

  /// Whether the last paint left room for a picture over a copy (see
  /// [paintSite]).
  bool get hasSlot => _slot.layer != null;

  /// Paints the live read with [live]. With [copies], it paints in a slot
  /// that [show] can fill with a picture over a copy instead; without, the
  /// copy is released.
  void paintSite(
    PaintingContext context,
    Offset offset, {
    required bool copies,
    required PaintingContextCallback live,
  }) {
    if (copies) {
      context.pushLayer(_slot.layer ??= ContainerLayer(), live, offset);
      return;
    }
    _slot.layer = null;
    _underlay.release();
    live(context, offset);
  }

  /// Leaves no slot until the next [paintSite].
  void releaseSlot() {
    _slot.layer = null;
  }

  /// The picture [record] draws over [copy] inside [bounds]. A drawn copy
  /// keeps its picture while [keyOf] stays equal; a copy not drawn yet is
  /// recorded when the scene is added, after every copy of the frame is
  /// drawn: they are drawn together.
  PictureLayer servedPicture(
    UnderlayCopy copy,
    Rect bounds, {
    required Object Function() keyOf,
    required ui.Picture Function() record,
    required UnderlayFold fold,
  }) {
    if (!copy.ready) {
      final picture = UnderlayPictureLayer(bounds, copy, () {
        _servedKey = keyOf();
        return record();
      }, fold);
      _served.layer = picture;
      _servedKey = null;
      return picture;
    }
    final key = keyOf();
    final previous = _served.layer;
    if (previous != null && _servedKey == key) return previous;
    final picture = GlassPictureLayer(bounds);
    picture.picture = record();
    _served.layer = picture;
    _servedKey = key;
    return picture;
  }

  /// Keeps [picture], drawn over a copy in the frame (see
  /// [BackdropUnderlay.serveInFrame]), as the picture the slot shows.
  PictureLayer servedInFrame(InFrameGlassLayer picture) {
    _served.layer = picture;
    _servedKey = null;
    return picture;
  }

  /// Fills the slot with [served] over [under], or with the live read
  /// without [served].
  void show(PictureLayer? served, {Layer? under}) {
    assert(under == null || served != null, 'Only a copy covers [under].');
    final slot = _slot.layer;
    if (slot == null) return;
    final child = served ?? _pass.layer ?? _clipRect.layer ?? _clipPath.layer;
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

  /// Whether the rig has a pass.
  bool get usesPass => _pass.layer != null;

  /// Gives the rig a pass, or takes it away.
  set usesPass(bool value) {
    if (!value) {
      _clearPass();
      return;
    }
    if (_pass.layer != null) return;
    final pass = SeededBackdropPassLayer(
      seedWhileResizing: seedWhileResizing,
    );
    pass.onActiveChanged = _activeChanged;
    _pass.layer = pass;
  }

  void _activeChanged() {
    _syncChildClip();
    onActiveChanged?.call();
  }

  /// Hands [filter] to the filter layer, and to the pass, which takes over
  /// a [blur] when it seeds its backdrop with it (see
  /// [SeededBackdropPassLayer.bindFilter]).
  void bindFilter(ui.ImageFilter filter, PassBlur? blur) {
    final backdrop = _filter.layer ??= _newFilterLayer();
    backdrop.filter = filter;
    if (_pass.layer case final pass?) {
      pass.bindFilter(backdrop, share, blur: blur);
    } else {
      backdrop.backdropKey = share?.key;
    }
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

  /// Plans the pass around [inner], in the pass layer's parent's
  /// coordinates, [offset] from the owner, for a blur reaching [reach] past
  /// it. A null [inner] plans no pass.
  void place(Rect? inner, Offset offset, double reach) {
    _inner = inner;
    _offset = offset;
    _reach = reach;
    sync();
  }

  /// Places the pass where the surface is on screen now: retained motion
  /// moves it without a repaint.
  void sync() {
    final pass = _pass.layer;
    final inner = _inner;
    _plan = pass == null || inner == null
        ? BackdropPassPlan.unsupported
        : plan(inner, _offset, _reach, _sizing);
    pass?.apply(_plan);
    _syncChildClip();
  }

  /// Paints the pass, the clip [outline] (or the rect [bounds] without one)
  /// and the filter in it, [offset] from [context]'s layer. Without
  /// [drawsFilter] the clip is empty.
  void paintLive(
    PaintingContext context,
    Offset offset, {
    required Rect bounds,
    Path? outline,
    bool needsCompositing = true,
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
          needsCompositing,
          clipOffset,
          bounds,
          paintFilter,
          oldLayer: _clipRect.layer,
        );
      } else {
        _clipRect.layer = null;
        final layer = clipContext.pushClipPath(
          needsCompositing,
          clipOffset,
          bounds,
          outline,
          paintFilter,
          oldLayer: _clipPath.layer,
        );
        _clipPath.layer = layer;
        _outline = layer?.clipPath;
      }
      _syncChildClip();
    }

    if (_pass.layer case final pass?) {
      context.pushLayer(pass, paintClip, offset);
    } else {
      paintClip(context, offset);
    }
  }

  /// Paints [filter] over the backdrop inside [outline], whose bounds are
  /// [bounds]. With seeds on and a [blur] to crop, the filter paints in a
  /// pass reaching [reach] past [bounds], seeded by a small backdrop filter,
  /// and reads that pass; otherwise only the clip and the filter (and, with
  /// [copies], the slot around them). With [copies], [compose] can draw the
  /// filter over a copy of what lies under [outline] instead: where [frost]
  /// stands for [filter], an unblurred copy frosted by a shader.
  void paint(
    PaintingContext context,
    Offset offset, {
    required ui.ImageFilter filter,
    required PassBlur? blur,
    required Rect bounds,
    required Path outline,
    required double reach,
    required double devicePixelRatio,
    bool copies = false,
    LiquidGlassBackdropFrost? frost,
  }) {
    final seeds = SeededBackdropPassLayer.enabled && blur != null;
    usesPass = seeds;
    if (seeds) place(bounds.shift(offset), offset, reach);
    bindFilter(filter, blur);
    _read = copies
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
      copies: copies,
      live: (liveContext, liveOffset) =>
          paintLive(liveContext, liveOffset, bounds: bounds, outline: outline),
    );
  }

  /// Asks for this frame's copy of what lies under the outline, while the
  /// rig may draw over one. The owner calls it from its onPreparing, before
  /// any glass of the frame composes.
  void ask() {
    final slot = _slot.layer;
    final read = _read;
    if (slot == null ||
        read == null ||
        _outline == null ||
        !BackdropUnderlay.enabled) {
      _asked = null;
      return;
    }
    // The live filter reads a pass reaching past its clip (or the whole
    // backdrop), not the backdrop cut at the clip: the blur near the edge
    // takes what lies outside, so a filtered copy is filtered over all it
    // holds.
    _asked = requestCopy(
      _underlay,
      slot,
      filter: read.filter,
      frost: read.frost,
      blendMode: BlendMode.srcOver,
      clip: read.clip,
      reach: read.reach,
      devicePixelRatio: read.devicePixelRatio,
      filtersReach: true,
    );
  }

  /// Fills the slot with the filter drawn over the copy [ask] asked for, or
  /// with the live read where there is no copy; returns whether a copy
  /// serves. The owner calls it from its onCompositing, which the composer
  /// runs in paint order.
  bool compose() {
    final asked = _asked;
    _asked = null;
    final slot = _slot.layer;
    if (slot == null) return false;
    final served = asked == null || _read == null
        ? null
        : _serveCopy(_read!, asked);
    show(served);
    return served != null;
  }

  PictureLayer? _serveCopy(_Read read, CopyAsk asked) {
    final outline = _outline;
    if (outline == null) return null;
    final served = serveCopy(_underlay, asked);
    if (served == null) return null;
    final (:copy, :shown) = served;
    final (:origin, :frosting, shifted: _) = asked;
    return servedPicture(
      copy,
      read.clip,
      keyOf: () =>
          (copy.image, copy.offset, shown, origin, outline, frosting?.frost),
      record: () => switch (frosting) {
        (:final frost, :final taps) => recordFrostedCopy(
          copy,
          shown,
          origin,
          frost: frost,
          taps: taps,
          shader: _frostShader ??= newFrostShader(),
          outline: outline,
        ),
        null => recordFilteredCopy(copy, shown, origin, outline: outline),
      },
      fold: (builder, _, _) => addFoldedFilter(
        builder,
        shown.shift(-origin),
        read.filter,
        outline: outline,
      ),
    );
  }

  /// Sets the clip rect the rig has without a pass, in the pass layer's
  /// parent's coordinates, and makes the clip follow.
  void clipTo(Rect bounds) {
    _clipBounds = bounds;
    _syncChildClip();
  }

  // The backdrop filter's saveLayer takes the size of its clip, Impeller
  // crops it at the screen edge, and it reuses an offscreen target only at
  // exactly the same size, so a surface growing from a screen edge would
  // resize it nearly every frame. The pass rect is on a global pixel grid,
  // already cut to the screen, and contains the clip, so while the pass is
  // in effect the filter paints the whole of it and the pass clears
  // everything outside the real clip (SeededBackdropPassLayer.silhouette).
  void _syncChildClip() {
    final pass = _pass.layer;
    final rect = pass?.passRect;
    if (_clipPath.layer case final clip?) {
      final outline = _outline;
      if (outline == null) return;
      pass?.silhouette = outline;
      final wanted = rect == null ? outline : _rectPathOf(rect);
      if (!identical(clip.clipPath, wanted)) clip.clipPath = wanted;
      return;
    }
    final clip = _clipRect.layer;
    final inner = _clipBounds;
    if (clip == null || inner == null) return;
    if (pass == null || rect == null) {
      pass?.silhouette = null;
      if (clip.clipRect != inner) clip.clipRect = inner;
      return;
    }
    pass.silhouette = _rectPathOf(inner);
    if (clip.clipRect != rect) clip.clipRect = rect;
  }

  // A path of exactly [rect], the same object for the same rect.
  Path _rectPathOf(Rect rect) {
    if (_rectPath case final path? when _rectPathRect == rect) return path;
    final path = Path();
    path.addRect(rect);
    _rectPathRect = rect;
    return _rectPath = path;
  }

  void _clearPass() {
    _pass.layer?.onActiveChanged = null;
    _pass.layer = null;
    _inner = null;
    _plan = BackdropPassPlan.unsupported;
  }

  /// Releases every layer but the picture over the copy, and keeps the copy
  /// for the next paint.
  void clear() {
    _clearPass();
    _read = null;
    _slot.layer = null;
    _filter.layer = null;
    _clipPath.layer = null;
    _clipRect.layer = null;
    _outline = null;
    _clipBounds = null;
    _rectPath = null;
    _rectPathRect = null;
  }

  /// Releases every layer and the copy.
  void dispose() {
    clear();
    _served.layer = null;
    _underlay.release();
    _frostShader?.dispose();
    _frostShader = null;
  }
}

// A read a copy can stand in for; the clip is in the slot's coordinates.
typedef _Read = ({
  ui.ImageFilter filter,
  LiquidGlassBackdropFrost? frost,
  Rect clip,
  double reach,
  double devicePixelRatio,
});
