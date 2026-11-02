// Layer setup reads as one statement per property, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';

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

/// The live read of a surface's backdrop: a backdrop filter clipped to the
/// surface's outline, painted in a seeded pass where seeds are on (see
/// [SeededBackdropPassLayer]).
///
/// The rig keeps its layers from frame to frame. While the pass is in effect
/// the clip is a rect the size of the pass, which keeps the filter's
/// offscreen target one size while the outline animates, and the pass cuts
/// the outline out with its outside-clear.
@internal
class BackdropRig {
  /// Creates a rig whose passes are placed by [plan] and whose reads share
  /// [share], if any.
  BackdropRig({
    required this.plan,
    this.share,
    this.seedWhileResizing = false,
  });

  /// Places the pass around a clip, given in the layer coordinates it is
  /// painted in, the paint offset from the owner, how far the blur reads
  /// past the clip, and the sizing that keeps the pass from resizing on
  /// every bucket step.
  final BackdropPassPlan Function(
    Rect inner,
    Offset offset,
    double reach,
    BackdropPassSizing sizing,
  )
  plan;

  /// The capture this rig shares with others, if any.
  final BackdropShare? share;

  /// Whether the pass stays seeded while its size changes (see
  /// [SeededBackdropPassLayer.seedWhileResizing]).
  final bool seedWhileResizing;

  final _filter = LayerHandle<BackdropFilterLayer>();
  final _clip = LayerHandle<ClipPathLayer>();
  final _pass = LayerHandle<SeededBackdropPassLayer>();

  /// Keeps the pass from resizing on every bucket step.
  final _sizing = BackdropPassSizing();

  // The clip around the filter, in the pass layer's parent's coordinates.
  Rect? _inner;
  Offset _offset = Offset.zero;

  // How far the blur reads past [_inner].
  double _reach = 0;

  // The outline the clip has without a pass.
  Path? _outline;

  Rect? _rectPathRect;
  Path? _rectPath;

  /// The filter layer the rig reads the backdrop with.
  BackdropFilterLayer? get filterLayer => _filter.layer;

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
    final backdrop = _filter.layer ??= BackdropFilterLayer();
    backdrop.filter = filter;
    backdrop.blendMode = BlendMode.srcOver;
    final key = share?._key;
    if (!SeededBackdropPassLayer.enabled || blur == null) {
      _clearPass();
      backdrop.backdropKey = key;
      _paintClip(context, offset, bounds, outline, backdrop);
      return;
    }
    final pass = _pass.layer ??= SeededBackdropPassLayer();
    pass.seedWhileResizing = seedWhileResizing;
    pass.onActiveChanged = _syncChildClip;
    _inner = bounds.shift(offset);
    _offset = offset;
    _reach = reach;
    sync();
    pass.bindFilter(backdrop, key, full: filter, blur: blur);
    context.pushLayer(
      pass,
      (passContext, passOffset) =>
          _paintClip(passContext, passOffset, bounds, outline, backdrop),
      offset,
    );
  }

  /// Places the pass where the surface is on screen now: retained motion
  /// moves it without a repaint.
  void sync() {
    final layer = _pass.layer;
    final inner = _inner;
    if (layer == null || inner == null) return;
    layer.apply(
      plan(inner, _offset, _reach, _sizing),
      inner,
    );
    _syncChildClip();
  }

  void _paintClip(
    PaintingContext context,
    Offset offset,
    Rect bounds,
    Path outline,
    BackdropFilterLayer backdrop,
  ) {
    final layer = context.pushClipPath(
      true,
      offset,
      bounds,
      outline,
      (clipContext, clipOffset) {
        clipContext.pushLayer(backdrop, (_, _) {}, clipOffset);
      },
      oldLayer: _clip.layer,
    );
    _clip.layer = layer;
    _outline = layer?.clipPath;
    _syncChildClip();
  }

  // The backdrop filter's saveLayer takes the size of its clip, and Impeller
  // reuses an offscreen target only at exactly the same size, so a clip that
  // is the exact outline of an animated shape allocates and frees a target
  // every frame. The pass rect is already on pixel buckets (see
  // planSeededBackdropPass) and contains the outline, so the filter paints
  // the whole of it and the pass clears everything outside the real outline
  // (SeededBackdropPassLayer.silhouette). Without a pass, the clip is the
  // outline itself.
  void _syncChildClip() {
    final clip = _clip.layer;
    final outline = _outline;
    if (clip == null || outline == null) return;
    final pass = _pass.layer;
    pass?.silhouette = outline;
    final rect = pass?.passRect;
    final wanted = rect == null ? outline : _rectPathOf(rect);
    if (!identical(clip.clipPath, wanted)) clip.clipPath = wanted;
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
  }

  /// Releases every layer of the rig.
  void clear() {
    _clearPass();
    _filter.layer = null;
    _clip.layer = null;
    _outline = null;
  }
}
