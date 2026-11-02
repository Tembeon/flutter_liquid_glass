// Layer setup reads as one statement per property, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';

/// One backdrop capture shared by several [BackdropRig]s.
///
/// Without seeded passes the rigs that share it read the backdrop once, at
/// the first of them: one that paints over another's output in overlapping
/// pixels then filters the backdrop, not the first one's output, so the two
/// transfers do not compound.
@internal
final class BackdropShare {
  final _key = BackdropKey();
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
/// The clip is the surface's outline, or a rect. The rig keeps its layers
/// from frame to frame. While the pass is in effect the clip is the pass's
/// rect, which keeps the filter's offscreen target one size while the
/// surface animates, and the pass cuts the real clip out with its
/// outside-clear.
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
  /// effect while the scene is prepared.
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

  // Where the pass goes: the clip, in the pass layer's parent's coordinates,
  // the paint offset, the blur's reach, the area the filter can change.
  Rect? _inner;
  Offset _offset = Offset.zero;
  double _reach = 0;
  Rect? _modified;
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

  /// The rig's outermost layer: the pass, or the clip.
  Layer? get live => _pass.layer ?? _clipRect.layer ?? _clipPath.layer;

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

  /// The copy of what lies under the surface; see [BackdropUnderlay.imageFor].
  UnderlayCopy? copyFor({
    required Layer anchor,
    required double devicePixelRatio,
    required Rect region,
    required Rect screen,
    OpacitySeedLayer? own,
    ui.ImageFilter? filter,
    Object? filterKey,
    int downscale = 1,
    Rect? body,
  }) => _underlay.imageFor(
    anchor: anchor,
    devicePixelRatio: devicePixelRatio,
    region: region,
    screen: screen,
    own: own,
    filter: filter,
    filterKey: filterKey,
    downscale: downscale,
    body: body,
  );

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
    final child = served ?? live;
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
    final pass = SeededBackdropPassLayer();
    pass.seedWhileResizing = seedWhileResizing;
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
    final backdrop = _filter.layer ??= BackdropFilterLayer();
    backdrop.filter = filter;
    final key = share?._key;
    if (_pass.layer case final pass?) {
      pass.bindFilter(backdrop, key, full: filter, blur: blur);
    } else {
      backdrop.backdropKey = key;
    }
  }

  /// Puts a filter layer made since the clip was painted into the clip.
  void adoptFilter() {
    final backdrop = _filter.layer;
    final clip = _clipRect.layer ?? _clipPath.layer;
    if (backdrop == null || clip == null || identical(backdrop.parent, clip)) {
      return;
    }
    backdrop.remove();
    clip.append(backdrop);
  }

  /// Takes the filter layer out of the tree.
  void releaseFilter() {
    _filter.layer?.remove();
    _filter.layer = null;
  }

  /// Plans the pass around [inner], in the pass layer's parent's
  /// coordinates, [offset] from the owner, for a blur reaching [reach] past
  /// it; the filter changes only [modified]. A null [inner] plans no pass.
  void place(Rect? inner, Offset offset, double reach, {Rect? modified}) {
    _inner = inner;
    _offset = offset;
    _reach = reach;
    _modified = modified;
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
    pass?.apply(_plan, _modified);
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
  /// and reads that pass; otherwise nothing but the clip and the filter is
  /// added to the layer tree.
  void paint(
    PaintingContext context,
    Offset offset, {
    required ui.ImageFilter filter,
    required PassBlur? blur,
    required Rect bounds,
    required Path outline,
    required double reach,
  }) {
    final seeds = SeededBackdropPassLayer.enabled && blur != null;
    usesPass = seeds;
    final backdrop = _filter.layer ??= BackdropFilterLayer();
    backdrop.blendMode = BlendMode.srcOver;
    if (seeds) {
      final inner = bounds.shift(offset);
      place(inner, offset, reach, modified: inner);
    }
    bindFilter(filter, blur);
    paintLive(context, offset, bounds: bounds, outline: outline);
  }

  /// Sets the clip rect the rig has without a pass, in the pass layer's
  /// parent's coordinates, and makes the clip follow.
  void clipTo(Rect bounds) {
    _clipBounds = bounds;
    _syncChildClip();
  }

  // The backdrop filter's saveLayer takes the size of its clip, and Impeller
  // reuses an offscreen target only at exactly the same size. The pass rect
  // is on pixel buckets and contains the clip, so while the pass is in effect
  // the filter paints the whole of it and the pass clears everything outside
  // the real clip (SeededBackdropPassLayer.silhouette).
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

  /// Releases every layer of the live read.
  void clear() {
    _clearPass();
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
    _slot.layer = null;
    _served.layer = null;
    _underlay.dispose();
  }
}
