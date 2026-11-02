// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_underlay.dart';

/// A copy of what is painted under one glass layer, blurred by its frost,
/// that the layer paints its glass over instead of reading the backdrop.
///
/// A backdrop filter anywhere in a frame makes Impeller render the whole
/// frame offscreen, split the root pass at every read and blit the result to
/// the screen; a frame whose glass all paints over copies has none of that.
/// The copy is drawn from the layer tree itself while the frame composites:
/// everything painted before the layer, in a band around what its glass
/// samples, replayed into one image with every other copy the frame draws,
/// which the frame renders before the glass. It serves later frames while
/// the layers painted before the glass in that band are the same ones it was
/// drawn from (the same pictures under the same transforms, clips, opacities
/// and filters); a frame in which they changed draws a new one.
///
/// Inside a fractional opacity the copy holds what the screen shows under
/// the glass, the faded content of the glass's own group included, and the
/// glass fades with its group; the live path seeds the group's pass with the
/// backdrop instead (approximation, while a group fades).
///
/// A band that holds a backdrop filter (glass that reads live), a texture, a
/// platform view or a layer type it does not know is never copied, and the
/// glass reads its backdrop.
@internal
class BackdropUnderlay {
  /// Replaces [enabled] for a test.
  @visibleForTesting
  static bool? debugEnabledOverride;

  static final bool _defaultEnabled =
      !kIsWeb &&
      ui.ImageFilter.isShaderFilterSupported &&
      !runningUnderFlutterTest &&
      const bool.fromEnvironment('LIQUID_GLASS_UNDERLAY', defaultValue: true);

  /// Whether glass layers keep copies of what lies under them: wherever
  /// Impeller renders, not under `flutter test` unless a test turns it on.
  static bool get enabled => debugEnabledOverride ?? _defaultEnabled;

  // Room past the band a copy holds, in logical pixels, so glass that moves
  // or grows a little stays inside it.
  static const double _margin = 12;

  ui.Image? _image;
  Offset _offset = Offset.zero;
  _Tile? _tile;
  Rect _copied = Rect.zero;
  Object? _filterKey;
  Rect? _filterClip;
  BlendMode _filterBlendMode = BlendMode.src;
  double _devicePixelRatio = 0;
  List<Object?> _signature = const [];
  bool _changing = false;

  /// How many copies were taken.
  @visibleForTesting
  int debugCaptures = 0;

  /// Why the last frame did not serve the copy, for diagnostics.
  @visibleForTesting
  String? debugMiss;

  /// How many images the copies of all glass were drawn into.
  @visibleForTesting
  static int get debugImagesDrawn => _Atlas.drawn;

  /// The image that holds the copy, once it is drawn.
  @visibleForTesting
  ui.Image? get debugImage => _image;

  /// The copy of the screen rect it holds, exact this frame for everything
  /// inside [region], or null when what lies there cannot be drawn again,
  /// and the caller reads its backdrop this frame.
  ///
  /// [anchor] is the layer the caller begins with in paint order: the copy
  /// holds what is painted before it, with [filter] applied as a backdrop
  /// filter with [filterBlendMode] inside [filterClip] (the whole copy when
  /// null), in screen logical pixels. [filterKey] stands for [filter]: a
  /// copy serves only callers that pass an equal key. [screen] is the view's
  /// rect. The copy taken in an earlier frame serves while the layers it was
  /// drawn from are unchanged; otherwise a new one is recorded now and drawn
  /// with every other copy recorded in the frame, in one image, when the
  /// first of them is read.
  ///
  /// Called while the frame composites, when the layers before [anchor] are
  /// final.
  UnderlayCopy? imageFor({
    required Layer anchor,
    required double devicePixelRatio,
    required Rect region,
    required Rect screen,
    ui.ImageFilter? filter,
    Object? filterKey,
    Rect? filterClip,
    BlendMode filterBlendMode = BlendMode.src,
  }) {
    final dpr = devicePixelRatio;
    final band = _snapOut(region, dpr).intersect(screen);
    if (band.isEmpty) return null;
    final root = _rootOf(anchor);
    final same =
        (_image != null || _tile != null) &&
        filterKey == _filterKey &&
        filterClip == _filterClip &&
        filterBlendMode == _filterBlendMode &&
        dpr == _devicePixelRatio;
    // Under content that changed in the last frame the copy is drawn first,
    // and the walk that draws it signs it too.
    final drawFirst = same && _changing && _copied == band;
    final held =
        same &&
        !drawFirst &&
        _same(_signPrefix(root, anchor, _copied, dpr), _signature);
    if (held && _contains(_copied, band)) {
      debugMiss = null;
      return UnderlayCopy._(this, _copied);
    }
    // A caller that moved over content that held still takes room to move
    // on; under content that changes, the copy holds no more than the band.
    final rect = held && filterClip == null
        ? _snapOut(band.inflate(_margin), dpr).intersect(screen)
        : band;
    final replay = _Prefix(
      anchor,
      rect,
      dpr,
      ui.PictureRecorder(),
      defer: true,
    );
    final content = replay.record(root, rect);
    if (content == null) {
      assert(() {
        debugMiss = 'blocked by ${_debugBlocker(root, anchor, band, dpr)}';
        return true;
      }(), 'Diagnose misses in debug builds.');
      return null;
    }
    if (drawFirst && replay.waits < 0 && _same(replay.out, _signature)) {
      content.dispose();
      _changing = false;
      debugMiss = null;
      return UnderlayCopy._(this, _copied);
    }
    _changing = same && !held;
    _release();
    final tile = _Tile(
      this,
      rect,
      dpr,
      filter,
      filterClip,
      filterBlendMode,
      level: replay.waits + 1,
    );
    if (replay.waits < 0) {
      tile.content = content;
      _signature = replay.out;
    } else {
      // It holds glass whose copy is drawn later in the frame: it is
      // recorded again once that glass has its picture.
      content.dispose();
      tile.redraw = () {
        final again = _Prefix(anchor, rect, dpr, ui.PictureRecorder());
        final picture = again.record(root, rect);
        if (picture != null) _signature = again.out;
        return picture;
      };
    }
    _tile = tile;
    _Atlas.add(tile);
    _copied = rect;
    _filterKey = filterKey;
    _filterClip = filterClip;
    _filterBlendMode = filterBlendMode;
    _devicePixelRatio = dpr;
    debugCaptures++;
    debugMiss = null;
    return UnderlayCopy._(this, rect);
  }

  /// Releases the copy.
  void dispose() => _release();

  /// Forgets the copy while the glass does not paint over one.
  void release() => _release();

  void _release() {
    _image?.dispose();
    _image = null;
    if (_tile case final tile?) _Atlas.cancel(tile);
    _tile = null;
    _signature = const [];
  }

  static Layer _rootOf(Layer layer) {
    var root = layer;
    while (root.parent != null) {
      root = root.parent!;
    }
    return root;
  }

  static Rect _snapOut(Rect rect, double dpr) => Rect.fromLTRB(
    (rect.left * dpr).floorToDouble() / dpr,
    (rect.top * dpr).floorToDouble() / dpr,
    (rect.right * dpr).ceilToDouble() / dpr,
    (rect.bottom * dpr).ceilToDouble() / dpr,
  );

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;

  static bool _same(List<Object?>? a, List<Object?>? b) {
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      // An image filter is unchanged only as the same object: comparing a
      // shader filter by value creates its native filter, which takes the
      // shader's uniforms then rather than when the scene is built.
      if (x is ui.ImageFilter) return false;
      if (x != y) return false;
    }
    return true;
  }

  static String _debugBlocker(Layer root, Layer anchor, Rect band, double dpr) {
    final prefix = _Prefix(anchor, band, dpr, null);
    prefix.walk(root, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1), null);
    return prefix.blocked ? '${prefix.blocker?.runtimeType}' : 'not reached';
  }

  // What is painted before [anchor] inside [band] (screen logical pixels),
  // or null when the copy could not draw it.
  static List<Object?>? _signPrefix(
    Layer root,
    Layer anchor,
    Rect band,
    double dpr,
  ) {
    final prefix = _Prefix(anchor, band, dpr, null);
    prefix.walk(root, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1), null);
    if (prefix.blocked || !prefix.reached) return null;
    return prefix.out;
  }
}

// Walks a layer tree in paint order up to [stop], collecting what draws into
// [band] and, with a [recorder], drawing it the way the engine draws each
// layer: canvas calls rather than a scene, which would make an engine layer
// and its Dart handle for every push.
class _Prefix {
  _Prefix(
    this.stop,
    this.band,
    this.devicePixelRatio,
    this.recorder, {
    this.defer = false,
  }) : canvas = recorder == null ? null : Canvas(recorder);

  final Layer stop;
  final Rect band;
  final double devicePixelRatio;
  final ui.PictureRecorder? recorder;
  final Canvas? canvas;
  // Whether glass over a copy that is not drawn yet is left out and noted
  // in [waits], rather than its copy drawn now.
  final bool defer;
  final out = <Object?>[];
  bool reached = false;
  bool blocked = false;
  Layer? blocker;

  // The highest level of the copies not drawn yet that the band holds glass
  // over, or -1.
  int waits = -1;

  late final Set<Layer> _path = _ancestors(stop);

  static Set<Layer> _ancestors(Layer layer) {
    final path = Set<Layer>.identity();
    for (var node = layer.parent; node != null; node = node.parent) {
      path.add(node);
    }
    return path;
  }

  // Records what is painted before [stop] in [rect] (screen logical pixels)
  // in device pixels from the rect's origin, or returns null when that
  // cannot be drawn again.
  ui.Picture? record(Layer root, Rect rect) {
    final dpr = devicePixelRatio;
    canvas!.translate(-rect.left * dpr, -rect.top * dpr);
    walk(root, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1), null);
    final content = recorder!.endRecording();
    if (blocked || !reached) {
      content.dispose();
      return null;
    }
    return content;
  }

  void walk(
    Layer layer,
    Matrix4 transform,
    Rect? clip, {
    List<Object?> state = const [],
    bool filtered = false,
  }) {
    if (reached || blocked) return;
    if (identical(layer, stop)) {
      reached = true;
      return;
    }
    if (!filtered && layer is ContainerLayer && !_path.contains(layer)) {
      final extent = _Extent.of(layer);
      if (!extent.isInfinite) {
        var bounds = MatrixUtils.transformRect(transform, extent);
        if (clip != null) bounds = bounds.intersect(clip);
        if (!bounds.overlaps(band)) return;
      }
    }

    bool reaches(Rect local) {
      // A filter above can move pixels anywhere: its whole subtree counts.
      if (filtered) return true;
      var bounds = MatrixUtils.transformRect(transform, local);
      if (clip != null) bounds = bounds.intersect(clip);
      return bounds.overlaps(band);
    }

    Rect clipped(Rect local) {
      final bounds = MatrixUtils.transformRect(transform, local);
      return clip == null ? bounds : clip.intersect(bounds);
    }

    Matrix4 shifted(Offset offset) {
      final next = transform.clone();
      next.translateByDouble(offset.dx, offset.dy, 0, 1);
      return next;
    }

    final c = canvas;
    final depth = c?.getSaveCount() ?? 0;
    var next = transform;
    var nextClip = clip;
    var nextState = state;
    var nextFiltered = filtered;
    (Shader, Rect, BlendMode)? mask;
    switch (layer) {
      case UnderlayPictureLayer(picture: null):
        if (!reaches(layer.canvasBounds)) return;
        if (layer.pendingLevel case final level? when defer || c == null) {
          // Glass over a copy that is not drawn yet: a copy that holds it is
          // drawn after it, and a signature that holds it matches none.
          if (level > waits) waits = level;
          out.add(Object());
          return;
        }
        layer.resolve();
        if (layer.picture == null) return;
        walk(layer, transform, clip, state: state, filtered: filtered);
        return;
      case PictureLayer(:final picture?):
        if (!reaches(layer.canvasBounds)) return;
        out.add(picture);
        out.add(transform.clone());
        out.add(clip);
        out.addAll(state);
        out.add(#leaf);
        c?.drawPicture(picture);
        return;
      case PictureLayer():
        return;
      case TextureLayer(:final rect) || PlatformViewLayer(:final rect):
        if (reaches(rect)) {
          blocked = true;
          blocker ??= layer;
        }
        return;
      case OpacitySeedLayer(seeded: false):
        break;
      case BackdropFilterLayer():
        // Another glass, or a blur, that reads live: what it writes, inside
        // its clip, is not known until the frame renders.
        if (filtered || (clip ?? Rect.largest).overlaps(band)) {
          blocked = true;
          blocker ??= layer;
        }
        return;
      case SeededBackdropPassLayer(hidden: true):
        return;
      case SeededBackdropPassLayer(:final scenePass?):
        if (filtered || clipped(scenePass.rect).overlaps(band)) {
          blocked = true;
          blocker ??= layer;
        }
        return;
      case LiquidGlassBackdropFilterLayer(:final servedPicture?):
        out.add(servedPicture);
        out.add(transform.clone());
        out.add(clip);
        out.addAll(state);
        out.add(#leaf);
        c?.drawPicture(servedPicture);
      case LiquidGlassBackdropFilterLayer(clip: final rect, :final reach):
        // It reads live, and changes nothing past its reach.
        if (filtered || clipped(rect.inflate(reach)).overlaps(band)) {
          blocked = true;
          blocker ??= layer;
        }
        return;
      case TransformLayer(:final offset):
        final effective = Matrix4.translationValues(offset.dx, offset.dy, 0);
        if (layer.transform case final matrix?) effective.multiply(matrix);
        next = transform.multiplied(effective);
        c?.save();
        c?.transform(effective.storage);
      case OpacityLayer(:final offset):
        final alpha = layer.alpha ?? 255;
        next = shifted(offset);
        nextState = [...state, alpha];
        c?.save();
        c?.translate(offset.dx, offset.dy);
        if (alpha < 255) c?.saveLayer(null, _alpha(alpha));
      case ImageFilterLayer(:final imageFilter?, :final offset):
        next = shifted(offset);
        nextState = [...state, imageFilter];
        nextClip = null;
        nextFiltered = true;
        c?.save();
        c?.translate(offset.dx, offset.dy);
        c?.saveLayer(null, _filtering(imageFilter));
      case OffsetLayer(:final offset)
          when layer.runtimeType == OffsetLayer ||
              layer is GeometryTransformTrackingLayer:
        next = shifted(offset);
        c?.save();
        c?.translate(offset.dx, offset.dy);
      case ColorFilterLayer(:final colorFilter?):
        nextState = [...state, colorFilter];
        final paint = Paint();
        paint.colorFilter = colorFilter;
        c?.saveLayer(null, paint);
      case ShaderMaskLayer(
        :final shader?,
        :final maskRect?,
        :final blendMode?,
      ):
        // A FragmentShader keeps its identity while its uniforms change.
        final token = shader is ui.FragmentShader ? Object() : shader;
        nextState = [...state, token, maskRect, blendMode];
        c?.saveLayer(null, Paint());
        mask = (shader, maskRect, blendMode);
      case ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        nextClip = clipped(clipRect);
        nextState = [...state, clipRect, clipBehavior];
        if (c != null) {
          c.save();
          c.clipRect(clipRect, doAntiAlias: clipBehavior != Clip.hardEdge);
          _clipLayer(c, clipRect, clipBehavior);
        }
      case ClipRRectLayer(:final clipRRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        nextClip = clipped(clipRRect.outerRect);
        nextState = [...state, clipRRect, clipBehavior];
        if (c != null) {
          c.save();
          c.clipRRect(clipRRect, doAntiAlias: clipBehavior != Clip.hardEdge);
          _clipLayer(c, clipRRect.outerRect, clipBehavior);
        }
      case ClipRSuperellipseLayer(
            :final clipRSuperellipse?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        nextClip = clipped(clipRSuperellipse.outerRect);
        nextState = [...state, clipRSuperellipse, clipBehavior];
        if (c != null) {
          c.save();
          c.clipRSuperellipse(
            clipRSuperellipse,
            doAntiAlias: clipBehavior != Clip.hardEdge,
          );
          _clipLayer(c, clipRSuperellipse.outerRect, clipBehavior);
        }
      case ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none:
        nextClip = clipped(clipPath.getBounds());
        nextState = [...state, clipPath, clipBehavior];
        if (c != null) {
          c.save();
          c.clipPath(clipPath, doAntiAlias: clipBehavior != Clip.hardEdge);
          _clipLayer(c, clipPath.getBounds(), clipBehavior);
        }
      case NativeClipLayer(
            enabled: true,
            :final geometry?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        final bounds = switch (geometry) {
          final Rect rect => rect,
          final RRect rect => rect.outerRect,
          final RSuperellipse rect => rect.outerRect,
          final Path path => path.getBounds(),
          _ => Rect.largest,
        };
        nextClip = clipped(bounds);
        nextState = [...state, geometry, clipBehavior];
        if (c != null) {
          final antiAlias = clipBehavior != Clip.hardEdge;
          c.save();
          switch (geometry) {
            case final Rect rect:
              c.clipRect(rect, doAntiAlias: antiAlias);
            case final RRect rect:
              c.clipRRect(rect, doAntiAlias: antiAlias);
            case final RSuperellipse rect:
              c.clipRSuperellipse(rect, doAntiAlias: antiAlias);
            case final Path path:
              c.clipPath(path, doAntiAlias: antiAlias);
            default:
              c.restoreToCount(depth);
              blocked = true;
              blocker ??= layer;
              return;
          }
          _clipLayer(c, bounds, clipBehavior);
        }
      case LeaderLayer(:final offset):
        next = shifted(offset);
        c?.save();
        c?.translate(offset.dx, offset.dy);
      case ClipRectLayer() ||
          ClipRRectLayer() ||
          ClipRSuperellipseLayer() ||
          ClipPathLayer() ||
          NativeClipLayer() ||
          AnnotatedRegionLayer() ||
          SeededBackdropPassLayer():
        break;
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        break;
      case ContainerLayer() when LiquidGlassUnderlay.effectsOf(layer) != null:
        final effects = LiquidGlassUnderlay.effectsOf(layer)!;
        next = transform.multiplied(effects.transform);
        c?.save();
        c?.transform(effects.transform.storage);
        final effectState = <Object?>[];
        if (effects.clip case final rounded?) {
          final bounds = MatrixUtils.transformRect(next, rounded.outerRect);
          nextClip = clip == null ? bounds : clip.intersect(bounds);
          effectState.add(rounded);
          c?.clipRRect(rounded);
        }
        if (effects.alpha case final alpha?) {
          effectState.add(alpha);
          c?.saveLayer(null, _alpha(alpha));
        }
        if (effects.blur > 0) {
          effectState.add(effects.blur);
          nextClip = null;
          nextFiltered = true;
          c?.saveLayer(
            null,
            _filtering(
              ui.ImageFilter.blur(sigmaX: effects.blur, sigmaY: effects.blur),
            ),
          );
        }
        nextState = [...state, ...effectState];
        for (var c = layer.firstChild; c != null; c = c.nextSibling) {
          walk(c, next, nextClip, state: nextState, filtered: nextFiltered);
          if (reached || blocked) break;
        }
        c?.restoreToCount(depth);
        return;
      default:
        // A layer this walk cannot draw again: only one whose content stays
        // clear of the band leaves the copy exact.
        if (_mayReach(layer, transform, clip, filtered: filtered)) {
          blocked = true;
          blocker ??= layer;
        }
        return;
    }
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        walk(
          child,
          next,
          nextClip,
          state: nextState,
          filtered: nextFiltered,
        );
        if (reached || blocked) break;
      }
    }
    if (mask case (final shader, final rect, final blendMode)) {
      // The engine draws a shader mask over what it masks, in a layer.
      final paint = Paint();
      paint.shader = shader;
      paint.blendMode = blendMode;
      c!.translate(rect.left, rect.top);
      c.drawRect(Offset.zero & rect.size, paint);
    }
    c?.restoreToCount(depth);
  }

  static Paint _alpha(int alpha) {
    final paint = Paint();
    paint.color = Color.fromARGB(alpha, 0, 0, 0);
    return paint;
  }

  static Paint _filtering(ui.ImageFilter filter) {
    final paint = Paint();
    paint.imageFilter = filter;
    return paint;
  }

  // A clip that antialiases with a layer draws what it clips in a layer of
  // its bounds, as the engine's clip layers do.
  static void _clipLayer(Canvas canvas, Rect bounds, Clip behavior) {
    if (behavior == Clip.antiAliasWithSaveLayer) {
      canvas.saveLayer(bounds, Paint());
    }
  }

  // Whether anything [layer] draws may land in the band, judged by its
  // pictures placed through each layer's own transform and grown by a
  // generous blur reach, since what the layer adds besides is unknown.
  bool _mayReach(
    Layer layer,
    Matrix4 transform,
    Rect? clip, {
    required bool filtered,
  }) {
    if (filtered) return true;
    var reach = false;
    void visit(Layer node, Matrix4 m) {
      if (reach) return;
      if (identical(node, stop)) {
        // The glass sits inside it: the walk cannot stop there.
        reach = true;
        return;
      }
      switch (node) {
        case PictureLayer():
          var bounds = MatrixUtils.transformRect(m, node.canvasBounds);
          if (clip != null) bounds = bounds.intersect(clip);
          if (bounds.inflate(64).overlaps(band)) reach = true;
        case TextureLayer() || PlatformViewLayer():
          reach = true;
        case ContainerLayer():
          for (var c = node.firstChild; c != null; c = c.nextSibling) {
            final childTransform = m.clone();
            node.applyTransform(c, childTransform);
            visit(c, childTransform);
          }
        default:
          reach = true;
      }
    }

    visit(layer, transform);
    return reach;
  }
}

// What a layer paints, in the space its parent places it in, for the frame
// being composited: a walk skips a subtree that paints nothing in its band.
// Layers composite in paint order, and glass changes its own subtree as it
// composites, so a subtree before the glass that walks is final by then.
// Layers that read the backdrop or whose drawing is not known count as
// painting everywhere.
abstract final class _Extent {
  static final _cache = Expando<(int, Rect)>();
  static int _frame = 0;
  static bool _counting = false;

  static Rect of(Layer layer) {
    if (!_counting) {
      _counting = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) => _frame++);
    }
    if (_cache[layer] case (final frame, final rect) when frame == _frame) {
      return rect;
    }
    final rect = _measure(layer);
    _cache[layer] = (_frame, rect);
    return rect;
  }

  static Rect _measure(Layer layer) => switch (layer) {
    PictureLayer(:final picture) =>
      picture == null && layer is! UnderlayPictureLayer
          ? Rect.zero
          : layer.canvasBounds,
    TextureLayer(:final rect) || PlatformViewLayer(:final rect) => rect,
    LiquidGlassBackdropFilterLayer(:final clip, :final reach) => _children(
      layer,
      null,
    ).expandToInclude(clip.inflate(reach)),
    BackdropFilterLayer() ||
    SeededBackdropPassLayer() ||
    ImageFilterLayer() ||
    ColorFilterLayer() => Rect.largest,
    TransformLayer(:final offset, :final transform) => _children(
      layer,
      Matrix4.translationValues(
        offset.dx,
        offset.dy,
        0,
      ).multiplied(transform ?? Matrix4.identity()),
    ),
    final OpacityLayer opacity => _shifted(opacity, opacity.offset),
    final LeaderLayer leader => _shifted(leader, leader.offset),
    final OffsetLayer offsets
        when offsets.runtimeType == OffsetLayer ||
            offsets is GeometryTransformTrackingLayer =>
      _shifted(offsets, offsets.offset),
    NativeClipLayer(enabled: true, :final geometry?, :final clipBehavior)
        when clipBehavior != Clip.none =>
      _clipped(_children(layer as ContainerLayer, null), switch (geometry) {
        final Rect rect => rect,
        final RRect rect => rect.outerRect,
        final RSuperellipse rect => rect.outerRect,
        final Path path => path.getBounds(),
        _ => Rect.largest,
      }),
    final NativeClipLayer clip => _children(clip, null),
    ShaderMaskLayer(:final maskRect) => _union(
      _children(layer, null),
      maskRect ?? Rect.largest,
    ),
    ClipRectLayer(:final clipRect?, :final clipBehavior)
        when clipBehavior != Clip.none =>
      _clipped(_children(layer, null), clipRect),
    ClipRRectLayer(:final clipRRect?, :final clipBehavior)
        when clipBehavior != Clip.none =>
      _clipped(_children(layer, null), clipRRect.outerRect),
    ClipRSuperellipseLayer(:final clipRSuperellipse?, :final clipBehavior)
        when clipBehavior != Clip.none =>
      _clipped(_children(layer, null), clipRSuperellipse.outerRect),
    ClipPathLayer(:final clipPath?, :final clipBehavior)
        when clipBehavior != Clip.none =>
      _clipped(_children(layer, null), clipPath.getBounds()),
    final ContainerLayer group
        when group is ClipRectLayer ||
            group is ClipRRectLayer ||
            group is ClipRSuperellipseLayer ||
            group is ClipPathLayer ||
            group is AnnotatedRegionLayer ||
            group.runtimeType == ContainerLayer =>
      _children(group, null),
    _ => Rect.largest,
  };

  static Rect _shifted(ContainerLayer layer, Offset offset) =>
      _children(layer, Matrix4.translationValues(offset.dx, offset.dy, 0));

  static Rect _children(ContainerLayer layer, Matrix4? transform) {
    var bounds = Rect.zero;
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      final extent = of(child);
      if (extent.isInfinite) return Rect.largest;
      if (extent.isEmpty) continue;
      bounds = _union(
        bounds,
        transform == null
            ? extent
            : MatrixUtils.transformRect(transform, extent),
      );
    }
    return bounds;
  }

  static Rect _union(Rect a, Rect b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return a.expandToInclude(b);
  }

  static Rect _clipped(Rect content, Rect clip) {
    if (content.isInfinite) return clip;
    final rect = content.intersect(clip);
    return rect.isEmpty ? Rect.zero : rect;
  }
}

/// A copy that [BackdropUnderlay.imageFor] serves: [rect] of the screen, in
/// logical pixels, at [offset] (device pixels) in [image].
///
/// A copy recorded this frame is drawn when its [image] or [offset] is first
/// read, together with every copy recorded before it: a caller that can
/// wait reads them when the scene is added ([UnderlayPictureLayer]).
@internal
final class UnderlayCopy {
  const UnderlayCopy._(this._underlay, this.rect);

  final BackdropUnderlay _underlay;

  /// The screen rect the copy holds, in logical pixels.
  final Rect rect;

  /// Whether [image] is drawn already.
  bool get ready => _underlay._image != null;

  /// The image that holds the copy, shared with other copies of the frame.
  ui.Image get image {
    if (!ready) _Atlas.flush();
    return _underlay._image!;
  }

  /// Where [rect]'s top left corner sits in [image], in device pixels.
  Offset get offset {
    if (!ready) _Atlas.flush();
    return _underlay._offset;
  }
}

/// A picture of glass over a copy that is recorded when the scene is added,
/// or earlier when another copy holds it, so that the copies of a frame are
/// drawn in one image.
@internal
class UnderlayPictureLayer extends PictureLayer {
  /// A layer whose [record] records its picture once [copy] is drawn.
  UnderlayPictureLayer(super.canvasBounds, this.copy, this.record);

  /// The copy the picture is drawn over.
  final UnderlayCopy copy;

  /// Records the picture.
  final ui.Picture Function() record;

  /// The level of [copy] in the frame's drawing order while it is not drawn.
  int? get pendingLevel => copy.ready ? null : copy._underlay._tile?.level;

  /// Records the picture now, if it is not yet.
  void resolve() {
    if (picture == null && attached) picture = record();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    resolve();
    if (picture != null) super.addToScene(builder);
  }
}

class _Tile {
  _Tile(
    this.owner,
    this.rect,
    this.devicePixelRatio,
    this.filter,
    this.filterClip,
    this.filterBlendMode, {
    required this.level,
  }) : width = (rect.width * devicePixelRatio).round(),
       height = (rect.height * devicePixelRatio).round();

  final BackdropUnderlay owner;

  // Copies of one level are drawn together, after every lower level: a
  // copy that holds glass over another copy is a level above it.
  final int level;
  ui.Picture? content;
  ui.Picture? Function()? redraw;
  final Rect rect;
  final double devicePixelRatio;
  final ui.ImageFilter? filter;
  final Rect? filterClip;
  final BlendMode filterBlendMode;
  final int width;
  final int height;
  Offset offset = Offset.zero;

  Rect get bounds => offset & Size(width.toDouble(), height.toDouble());
}

// The copies recorded in a frame, drawn into one image: every image drawn
// on its own costs the raster thread a render pass, a texture and a command
// buffer, and the GPU driver a submission.
abstract final class _Atlas {
  // Gap between copies, in device pixels: sampling between pixels at a
  // copy's edge reads no neighbour.
  static const int _gap = 2;
  static const int _rowWidth = 2048;
  static const int _maxHeight = 4096;

  static final _pending = <_Tile>[];
  static bool _scheduled = false;
  static bool _flushing = false;
  static int drawn = 0;

  static void add(_Tile tile) {
    _pending.add(tile);
    if (_scheduled) return;
    _scheduled = true;
    // A copy no caller read this frame is drawn after it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      flush();
    });
  }

  static void cancel(_Tile tile) {
    if (_pending.remove(tile)) tile.content?.dispose();
  }

  static void flush() {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty) {
        var level = _pending.first.level;
        for (final tile in _pending) {
          if (tile.level < level) level = tile.level;
        }
        final batch = [
          for (final tile in _pending)
            if (tile.level == level) tile,
        ];
        _pending.removeWhere((tile) => tile.level == level);
        for (final tile in batch) {
          if (tile.content != null) continue;
          final picture = tile.redraw?.call();
          assert(picture != null, 'A copy recorded again is never blocked.');
          tile.content = picture ?? ui.PictureRecorder().endRecording();
        }
        // Copies under one filter lie side by side, to share its layer.
        final runs = <Object?, List<_Tile>>{};
        for (final tile in batch) {
          runs
              .putIfAbsent(
                tile.filter == null
                    ? null
                    : (tile.owner._filterKey, tile.devicePixelRatio),
                () => [],
              )
              .add(tile);
        }
        _pack([for (final run in runs.values) ...run]);
      }
    } finally {
      _flushing = false;
    }
  }

  static void _pack(List<_Tile> batch) {
    var start = 0;
    while (start < batch.length) {
      final tiles = <_Tile>[];
      var x = 0;
      var y = 0;
      var row = 0;
      var width = 0;
      for (final tile in batch.skip(start)) {
        final limit = tile.width > _rowWidth ? tile.width : _rowWidth;
        if (x > 0 && x + tile.width > limit) {
          x = 0;
          y += row + _gap;
          row = 0;
        }
        if (tiles.isNotEmpty && y + tile.height > _maxHeight) break;
        tile.offset = Offset(x.toDouble(), y.toDouble());
        tiles.add(tile);
        x += tile.width + _gap;
        if (x - _gap > width) width = x - _gap;
        if (tile.height > row) row = tile.height;
      }
      start += tiles.length;
      _draw(tiles, width, y + row);
    }
  }

  // Runs of copies whose bounds together cover little more than the copies.
  static List<List<_Tile>> _clusters(List<_Tile> tiles) {
    final clusters = <List<_Tile>>[];
    var bounds = Rect.zero;
    var area = 0.0;
    for (final tile in tiles) {
      final rect = tile.bounds;
      final size = rect.width * rect.height;
      final joined = bounds.expandToInclude(rect);
      if (clusters.isNotEmpty &&
          joined.width * joined.height <= (area + size) * 1.25) {
        clusters.last.add(tile);
        bounds = joined;
        area += size;
      } else {
        clusters.add([tile]);
        bounds = rect;
        area = size;
      }
    }
    return clusters;
  }

  static void _draw(List<_Tile> tiles, int width, int height) {
    drawn++;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    void place(_Tile tile) {
      canvas.save();
      canvas.translate(tile.offset.dx, tile.offset.dy);
      canvas.clipRect(Offset.zero & tile.bounds.size);
      canvas.drawPicture(tile.content!);
      canvas.restore();
    }

    // Copies that a filter replaces whole and that lie side by side share
    // one filtered layer: the blur reaches across a copy's edge no further
    // than the band a copy holds around what its glass samples, and the
    // layer is clipped to the copies so that it reaches no other. The layer
    // is filtered whole, so copies far apart are filtered each on its own.
    final shared = <(Object?, double), List<_Tile>>{};
    final isolated = <_Tile>[];
    for (final tile in tiles) {
      if (tile.filter == null) {
        place(tile);
      } else if (tile.filterClip == null &&
          tile.filterBlendMode == BlendMode.src) {
        shared
            .putIfAbsent(
              (tile.owner._filterKey, tile.devicePixelRatio),
              () => [],
            )
            .add(tile);
      } else {
        isolated.add(tile);
      }
    }
    for (final group in shared.values) {
      for (final cluster in _clusters(group)) {
        if (cluster.length == 1) {
          isolated.add(cluster.single);
          continue;
        }
        final dpr = cluster.first.devicePixelRatio;
        final area = Path();
        for (final tile in cluster) {
          area.addRect(tile.bounds);
        }
        final bounds = area.getBounds();
        final paint = Paint();
        paint.imageFilter = cluster.first.filter;
        canvas.save();
        canvas.clipPath(area, doAntiAlias: false);
        // The filter is in logical pixels, as the backdrop filter it stands
        // for is under the view's scale.
        canvas.scale(dpr);
        canvas.saveLayer(
          Rect.fromLTRB(
            bounds.left / dpr,
            bounds.top / dpr,
            bounds.right / dpr,
            bounds.bottom / dpr,
          ),
          paint,
        );
        canvas.scale(1 / dpr);
        cluster.forEach(place);
        canvas.restore();
        canvas.restore();
      }
    }
    final content = recorder.endRecording();
    final ui.Image image;
    if (isolated.isEmpty) {
      image = content.toImageSync(width, height);
    } else {
      // The filter reads a copy as a backdrop filter reads the screen, in a
      // layer of the copy's size: it reads that layer alone, which a pass
      // split at the filter loads and stores, and its blur meets the copy's
      // edges as it would meet the edges of an image of its own.
      final b = ui.SceneBuilder();
      b.addPicture(Offset.zero, content);
      for (final tile in isolated) {
        final filter = tile.filter!;
        final dpr = tile.devicePixelRatio;
        b.pushClipRect(tile.bounds, clipBehavior: Clip.antiAliasWithSaveLayer);
        b.addPicture(tile.offset, tile.content!);
        final toAtlas = Matrix4.translationValues(
          tile.offset.dx - tile.rect.left * dpr,
          tile.offset.dy - tile.rect.top * dpr,
          0,
        );
        toAtlas.scaleByDouble(dpr, dpr, 1, 1);
        b.pushTransform(toAtlas.storage);
        b.pushClipRect(
          tile.filterClip?.intersect(tile.rect) ?? tile.rect,
          clipBehavior: Clip.hardEdge,
        );
        b.pushBackdropFilter(filter, blendMode: tile.filterBlendMode);
        b.pop();
        b.pop();
        b.pop();
        b.pop();
      }
      final scene = b.build();
      image = scene.toImageSync(width, height);
      scene.dispose();
    }
    for (final tile in tiles) {
      tile.content!.dispose();
    }
    content.dispose();
    for (final tile in tiles) {
      final owner = tile.owner;
      owner._tile = null;
      owner._image = image.clone();
      owner._offset = tile.offset;
    }
    image.dispose();
  }
}
