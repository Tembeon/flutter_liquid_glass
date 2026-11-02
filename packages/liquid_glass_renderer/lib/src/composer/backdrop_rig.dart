// Layer setup reads as one statement per property, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';

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
    (chain[i] as ContainerLayer).applyTransform(chain[i - 1], toScreen);
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

/// A copy of what lies under [clip], in [anchor]'s coordinates, run through
/// [filter] as a backdrop filter composited with [blendMode]: the copy, the
/// part of it [clip] shows in screen coordinates, and the shift from
/// [anchor]'s coordinates to the screen's. Null where none serves.
///
/// The copy holds [reach] around [clip]. With [filtersReach] the filter runs
/// over all of it, as a live filter that reads a pass reaching past its clip
/// does; without, inside [clip] only.
@internal
({UnderlayCopy copy, Rect shown, Offset origin})? filteredCopyFor(
  BackdropUnderlay underlay,
  Layer anchor, {
  required ui.ImageFilter filter,
  required BlendMode blendMode,
  required Rect clip,
  required double reach,
  required double devicePixelRatio,
  required bool filtersReach,
}) {
  final origin = screenOffsetOf(anchor, devicePixelRatio);
  if (origin == null) return null;
  final shifted = clip.shift(origin);
  final region = shifted.inflate(reach);
  final copy = underlay.imageFor(
    anchor: anchor,
    devicePixelRatio: devicePixelRatio,
    region: region,
    filter: filter,
    filterClip: filtersReach ? region : shifted,
    filterBlendMode: blendMode,
  );
  if (copy == null) return null;
  return (copy: copy, shown: shifted.intersect(copy.rect), origin: origin);
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

/// Places a rig's pass around a clip, given in the layer coordinates it is
/// painted in, the paint offset from the owner, how far the blur reads past
/// the clip, and the sizing that keeps the pass from resizing on every
/// bucket step.
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

  /// The capture this rig shares with others, if any.
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

  // What the last [paint] read, for a filtered copy to stand in for. Null
  // when the rig takes no copies.
  _Read? _read;

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
  }) {
    if (!copy.ready) {
      final picture = UnderlayPictureLayer(bounds, copy, () {
        _servedKey = keyOf();
        return record();
      });
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

  /// Fills the slot with [served], or with the live read without it.
  void show(PictureLayer? served) {
    final slot = _slot.layer;
    if (slot == null) return;
    final child = served ?? _pass.layer ?? _clipRect.layer ?? _clipPath.layer;
    if (child == null) {
      slot.removeAllChildren();
      return;
    }
    if (identical(slot.firstChild, child) && child.nextSibling == null) return;
    slot.removeAllChildren();
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
  /// filter over a copy of what lies under [outline] instead.
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
  }) {
    final seeds = SeededBackdropPassLayer.enabled && blur != null;
    usesPass = seeds;
    if (seeds) place(bounds.shift(offset), offset, reach);
    bindFilter(filter, blur);
    _read = copies
        ? (
            filter: filter,
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

  /// Fills the slot with the filter drawn over a copy of what lies under
  /// the outline, or with the live read where there is no copy; returns
  /// whether a copy serves. The owner calls it from its onCompositing, which
  /// the composer runs in paint order.
  bool compose() {
    final slot = _slot.layer;
    if (slot == null) return false;
    final served = _read == null || !BackdropUnderlay.enabled
        ? null
        : _serveFiltered(slot, _read!);
    show(served);
    return served != null;
  }

  PictureLayer? _serveFiltered(ContainerLayer slot, _Read read) {
    final outline = _outline;
    if (outline == null) return null;
    // The live filter reads a pass reaching past its clip (or the whole
    // backdrop), not the backdrop cut at the clip: the blur near the edge
    // takes what lies outside, so the copy is filtered over all it holds.
    final served = filteredCopyFor(
      _underlay,
      slot,
      filter: read.filter,
      blendMode: BlendMode.srcOver,
      clip: read.clip,
      reach: read.reach,
      devicePixelRatio: read.devicePixelRatio,
      filtersReach: true,
    );
    if (served == null) return null;
    final (:copy, :shown, :origin) = served;
    return servedPicture(
      copy,
      read.clip,
      keyOf: () => (copy.image, copy.offset, shown, origin, outline),
      record: () => recordFilteredCopy(copy, shown, origin, outline: outline),
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
  }
}

// A read a filtered copy can stand in for; the clip is in the slot's
// coordinates.
typedef _Read = ({
  ui.ImageFilter filter,
  Rect clip,
  double reach,
  double devicePixelRatio,
});
