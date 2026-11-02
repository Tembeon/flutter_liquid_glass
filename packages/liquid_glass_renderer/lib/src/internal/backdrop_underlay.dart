// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
/// samples, replayed into a small image that the frame renders before the
/// glass. It serves later frames while the layers painted before the glass
/// in that band are the same ones it was drawn from (the same pictures under
/// the same transforms, clips, opacities and filters); a frame in which they
/// changed draws a new one.
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
  Rect _copied = Rect.zero;
  Object? _filterKey;
  Rect? _filterClip;
  BlendMode _filterBlendMode = BlendMode.src;
  double _devicePixelRatio = 0;
  List<Object?> _signature = const [];

  /// How many copies were taken.
  @visibleForTesting
  int debugCaptures = 0;

  /// Why the last frame did not serve the copy, for diagnostics.
  @visibleForTesting
  String? debugMiss;

  /// The copy and the screen rect it holds (logical pixels), exact this
  /// frame for everything inside [region], or null when what lies there
  /// cannot be drawn again, and the caller reads its backdrop this frame.
  ///
  /// [anchor] is the layer the caller begins with in paint order: the copy
  /// holds what is painted before it, with [filter] applied as a backdrop
  /// filter with [filterBlendMode] inside [filterClip] (the whole copy when
  /// null), in screen logical pixels. [filterKey] stands for [filter]: a
  /// copy serves only callers that pass an equal key. [screen] is the view's
  /// rect. The copy taken in an earlier frame serves while the layers it was
  /// drawn from are unchanged; otherwise a new one is drawn now, and the
  /// frame renders it before anything that samples it.
  ///
  /// Called while the frame composites, when the layers before [anchor] are
  /// final.
  ({ui.Image image, Rect rect})? imageFor({
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
    final held =
        _image != null &&
        filterKey == _filterKey &&
        filterClip == _filterClip &&
        filterBlendMode == _filterBlendMode &&
        dpr == _devicePixelRatio &&
        _same(_signPrefix(root, anchor, _copied, dpr), _signature);
    if (held && _contains(_copied, band)) {
      debugMiss = null;
      return (image: _image!, rect: _copied);
    }
    // A caller that moved over content that held still takes room to move
    // on; under content that changes, the copy holds no more than the band.
    final rect = held && filterClip == null
        ? _snapOut(band.inflate(_margin), dpr).intersect(screen)
        : band;
    final replay = _Prefix(anchor, rect, dpr, ui.PictureRecorder());
    final image = replay.draw(
      root,
      rect,
      filter: filter,
      filterClip: filterClip,
      filterBlendMode: filterBlendMode,
    );
    if (image == null) {
      assert(() {
        debugMiss = 'blocked by ${_debugBlocker(root, anchor, band, dpr)}';
        return true;
      }(), 'Diagnose misses in debug builds.');
      return null;
    }
    _image?.dispose();
    _image = image;
    _copied = rect;
    _signature = replay.out;
    _filterKey = filterKey;
    _filterClip = filterClip;
    _filterBlendMode = filterBlendMode;
    _devicePixelRatio = dpr;
    debugCaptures++;
    debugMiss = null;
    return (image: image, rect: rect);
  }

  /// Releases the copy.
  void dispose() => _release();

  /// Forgets the copy while the glass does not paint over one.
  void release() => _release();

  void _release() {
    _image?.dispose();
    _image = null;
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
  _Prefix(this.stop, this.band, this.devicePixelRatio, this.recorder)
    : canvas = recorder == null ? null : Canvas(recorder);

  final Layer stop;
  final Rect band;
  final double devicePixelRatio;
  final ui.PictureRecorder? recorder;
  final Canvas? canvas;
  final out = <Object?>[];
  bool reached = false;
  bool blocked = false;
  Layer? blocker;

  // Draws what is painted before [stop] in [rect] (screen logical pixels)
  // into an image, [filter] applied over it inside [filterClip], or returns
  // null when that cannot be drawn again.
  ui.Image? draw(
    Layer root,
    Rect rect, {
    required ui.ImageFilter? filter,
    required Rect? filterClip,
    required BlendMode filterBlendMode,
  }) {
    final c = canvas!;
    final dpr = devicePixelRatio;
    c.translate(-rect.left * dpr, -rect.top * dpr);
    walk(root, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1), null);
    final content = recorder!.endRecording();
    if (blocked || !reached) {
      content.dispose();
      return null;
    }
    final width = (rect.width * dpr).round();
    final height = (rect.height * dpr).round();
    if (filter == null) {
      final image = content.toImageSync(width, height);
      content.dispose();
      return image;
    }
    // The filter reads the copy as a backdrop filter reads the screen: the
    // same blur at the copy's edges as the live read.
    final b = ui.SceneBuilder();
    b.addPicture(Offset.zero, content);
    final toCopy = Matrix4.translationValues(
      -rect.left * dpr,
      -rect.top * dpr,
      0,
    );
    toCopy.scaleByDouble(dpr, dpr, 1, 1);
    b.pushTransform(toCopy.storage);
    b.pushClipRect(filterClip ?? rect, clipBehavior: Clip.hardEdge);
    b.pushBackdropFilter(filter, blendMode: filterBlendMode);
    b.pop();
    b.pop();
    b.pop();
    final scene = b.build();
    final image = scene.toImageSync(width, height);
    scene.dispose();
    content.dispose();
    return image;
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
