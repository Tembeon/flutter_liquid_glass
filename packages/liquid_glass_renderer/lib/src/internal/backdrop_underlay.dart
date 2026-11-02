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
  double _pixelRatio = 0;
  List<Object?> _signature = const [];

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
  /// rect. The copy holds [downscale] device pixels in each of its pixels
  /// along each side: a copy blurred enough loses nothing drawn smaller.
  /// The copy taken in an earlier frame serves while the layers it was
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
    int downscale = 1,
  }) {
    final dpr = devicePixelRatio;
    final pixels = dpr / downscale;
    final band = _snapOut(region, pixels).intersect(screen);
    if (band.isEmpty) return null;
    final root = _rootOf(anchor);
    final scan = _Scan.of(root, dpr, anchor);
    final limit = scan.reach(anchor);
    final same =
        (_image != null || _tile != null) &&
        filterKey == _filterKey &&
        filterClip == _filterClip &&
        filterBlendMode == _filterBlendMode &&
        dpr == _devicePixelRatio &&
        pixels == _pixelRatio;
    // Signing replays no pictures: a copy is recorded only once it is
    // known to be drawn now.
    var signed = same
        ? _Prefix.signed(root, anchor, _copied, dpr, scan, limit)
        : null;
    final held = signed != null && _same(signed.out, _signature);
    if (held && _contains(_copied, band)) {
      debugMiss = null;
      return UnderlayCopy._(this, _copied, pixels);
    }
    // A caller that moved over content that held still takes room to move
    // on; under content that changes, the copy holds no more than the band.
    final rect = held && filterClip == null
        ? _snapOut(band.inflate(_margin), pixels).intersect(screen)
        : band;
    if (signed == null || signed.band != rect) {
      signed = _Prefix.signed(root, anchor, rect, dpr, scan, limit);
    }
    if (signed.blocked || !signed.reached) {
      assert(() {
        debugMiss = 'blocked by ${_debugBlocker(root, anchor, band, dpr)}';
        return true;
      }(), 'Diagnose misses in debug builds.');
      return null;
    }
    _release();
    final tile = _Tile(
      this,
      rect,
      pixels,
      filter,
      filterClip,
      filterBlendMode,
      level: signed.waits + 1,
    );
    ui.Picture? record() {
      final replay = _Prefix(
        anchor,
        rect,
        dpr,
        ui.PictureRecorder(),
        scan: scan,
        limit: limit,
      );
      final picture = replay.record(root, rect, pixels);
      if (picture != null) _signature = replay.out;
      return picture;
    }

    if (signed.waits < 0) {
      tile.content = record();
    } else {
      // It holds glass whose copy is drawn later in the frame: it is
      // recorded once that glass has its picture.
      tile.redraw = record;
    }
    _tile = tile;
    _Atlas.add(tile);
    _copied = rect;
    _filterKey = filterKey;
    _filterClip = filterClip;
    _filterBlendMode = filterBlendMode;
    _devicePixelRatio = dpr;
    _pixelRatio = pixels;
    debugCaptures++;
    debugMiss = null;
    return UnderlayCopy._(this, rect, pixels);
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
    this.scan,
    this.limit,
  }) : canvas = recorder == null ? null : Canvas(recorder);

  // What is painted before [stop] in [band], signed without drawing it.
  factory _Prefix.signed(
    Layer root,
    Layer stop,
    Rect band,
    double devicePixelRatio,
    _Scan scan,
    int limit,
  ) {
    final prefix = _Prefix(
      stop,
      band,
      devicePixelRatio,
      null,
      scan: scan,
      limit: limit,
    );
    prefix.run(root);
    return prefix;
  }

  final Layer stop;
  final Rect band;
  final double devicePixelRatio;
  final ui.PictureRecorder? recorder;
  // Without one, glass over a copy that is not drawn yet is left out and
  // noted in [waits]; with one, its copy is drawn now.
  final Canvas? canvas;
  final out = <Object?>[];

  // The pass's scan this walk replays, and where [stop] lies in it.
  _Scan? scan;
  int? limit;

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
  // at [pixels] per logical pixel from the rect's origin, or returns null
  // when that cannot be drawn again.
  ui.Picture? record(Layer root, Rect rect, double pixels) {
    final dpr = devicePixelRatio;
    final c = canvas!;
    // A picture drawn into a canvas clipped to the copy is culled to what
    // reaches it while it is recorded.
    c.clipRect(
      Rect.fromLTWH(0, 0, rect.width * pixels, rect.height * pixels),
      doAntiAlias: false,
    );
    if (pixels != dpr) c.scale(pixels / dpr);
    c.translate(-rect.left * dpr, -rect.top * dpr);
    run(root);
    final content = recorder!.endRecording();
    if (blocked || !reached) {
      content.dispose();
      return null;
    }
    return content;
  }

  // Draws what is painted before [stop] in [band] from the pass's scan, or
  // walks the layer tree itself when the scan does not reach [stop].
  void run(Layer root) {
    final dpr = devicePixelRatio;
    final scan = this.scan ??= _Scan.of(root, dpr, stop);
    final limit = this.limit ??= scan.reach(stop);
    if (limit < 0) {
      walk(root, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1), null);
    } else {
      scan.replay(this, limit);
      assert(_walksAlike(root), 'The scan replays what a walk draws.');
    }
  }

  // Whether walking the layer tree finds what the replay found.
  bool _walksAlike(Layer root) {
    final dpr = devicePixelRatio;
    final walked = _Prefix(stop, band, dpr, null);
    walked.walk(root, Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1), null);
    if (walked.blocked != blocked) return false;
    if (blocked) return true;
    if (walked.reached != reached || walked.waits != waits) return false;
    final a = walked.out;
    if (a.length != out.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = out[i];
      if (identical(x, y) || x == y) continue;
      // Glass over a copy not drawn yet signs as a fresh object.
      if (x.runtimeType == Object && y.runtimeType == Object) continue;
      return false;
    }
    return true;
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
        if (!_meets(bounds, band)) return;
      }
    }

    bool reaches(Rect local) {
      // A filter above can move pixels anywhere: its whole subtree counts.
      if (filtered) return true;
      var bounds = MatrixUtils.transformRect(transform, local);
      if (clip != null) bounds = bounds.intersect(clip);
      return _meets(bounds, band);
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
        if (layer.pendingLevel case final level? when c == null) {
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
        if (filtered || _meets(clip ?? Rect.largest, band)) {
          blocked = true;
          blocker ??= layer;
        }
        return;
      case SeededBackdropPassLayer(hidden: true):
        return;
      case SeededBackdropPassLayer(:final scenePass?):
        if (filtered || _meets(clipped(scenePass.rect), band)) {
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
        if (filtered || _meets(clipped(rect.inflate(reach)), band)) {
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
    if (mask case (final shader, final rect, final blendMode) when c != null) {
      // The engine draws a shader mask over what it masks, in a layer.
      final paint = Paint();
      paint.shader = shader;
      paint.blendMode = blendMode;
      c.translate(rect.left, rect.top);
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

// What a compositing pass paints, in paint order, walked once as far as the
// glass that composites last: each copy of the pass replays the part before
// its glass instead of walking the layer tree again. Glass composites in
// paint order and changes only its own subtree, so what lies before the
// glass that composites is final; the layers whose drawing glass decides
// while it composites are kept and read when a copy replays them.
final class _Scan {
  _Scan._(this.root, this.devicePixelRatio, this.frame) {
    _cursors.add(
      _Cursor(
        null,
        root,
        Matrix4.diagonal3Values(1 / devicePixelRatio, 1 / devicePixelRatio, 1),
        null,
        const [],
        filtered: false,
        open: -1,
      ),
    );
  }

  // The scan of the pass that composites [root], begun anew when the scan
  // walked to or past [anchor] already: the tree composites again. A pass
  // outside the frame's compositing, an image taken after the frame, scans
  // for itself alone.
  factory _Scan.of(Layer root, double devicePixelRatio, Layer anchor) {
    final frame = _Extent.frame;
    if (frame == null) return _Scan._(root, devicePixelRatio, -1);
    final scan = _current;
    if (scan != null &&
        identical(scan.root, root) &&
        scan.devicePixelRatio == devicePixelRatio &&
        scan.frame == frame &&
        !identical(_seen[anchor], scan)) {
      return scan;
    }
    return _current = _Scan._(root, devicePixelRatio, frame);
  }

  static _Scan? _current;
  static final _seen = Expando<_Scan>();

  final Layer root;
  final double devicePixelRatio;
  final int frame;
  final entries = <_Entry>[];
  final _cursors = <_Cursor>[];

  // Walks on to [anchor] and returns how many entries lie before it, or -1
  // when the walk cannot reach it.
  int reach(Layer anchor) {
    Set<Layer>? path;
    while (true) {
      final at = _cursors.last;
      final layer = at.next;
      if (layer == null) {
        if (at.layer == null) return -1;
        _close();
        continue;
      }
      if (identical(layer, anchor)) {
        _seen[anchor] = this;
        return entries.length;
      }
      at.next = layer.nextSibling;
      if (!_visit(layer, at)) {
        path ??= _Prefix._ancestors(anchor);
        if (path.contains(layer)) return -1;
      }
    }
  }

  void _add(_Cursor at, _Entry entry, Rect bounds) {
    entries.add(entry);
    at.include(bounds);
  }

  void _push(
    ContainerLayer layer,
    _Open open,
    Matrix4 transform,
    Rect? clip,
    List<Object?> state, {
    required bool filtered,
  }) {
    entries.add(open);
    _seen[layer] = this;
    _cursors.add(
      _Cursor(
        layer,
        layer.firstChild,
        transform,
        clip,
        state,
        filtered: filtered,
        open: entries.length - 1,
      ),
    );
  }

  void _close() {
    final at = _cursors.removeLast();
    final open = entries[at.open] as _Open;
    open.bounds = _Cursor.union(at.bounds, open.extra);
    open.end = entries.length;
    entries.add(const _Close());
    _cursors.last.include(open.bounds);
  }

  // Adds [layer] as a child of [at]; false when it is a container whose
  // children are not walked.
  bool _visit(Layer layer, _Cursor at) {
    final transform = at.transform;
    final clip = at.clip;
    final state = at.state;
    final filtered = at.filtered;

    Rect clipped(Rect local) {
      final bounds = MatrixUtils.transformRect(transform, local);
      return clip == null ? bounds : clip.intersect(bounds);
    }

    Rect reaching(Rect local) => filtered ? _everywhere : clipped(local);

    Matrix4 shifted(Offset offset) {
      final next = transform.clone();
      next.translateByDouble(offset.dx, offset.dy, 0, 1);
      return next;
    }

    void push(
      ContainerLayer layer,
      _Open open, {
      Matrix4? next,
      Rect? nextClip,
      bool keepClip = true,
      List<Object?>? nextState,
      bool nextFiltered = false,
    }) => _push(
      layer,
      open,
      next ?? transform,
      keepClip ? clip : nextClip,
      nextState ?? state,
      filtered: filtered || nextFiltered,
    );

    _Open clipping(
      Rect bounds,
      Clip behavior,
      void Function(Canvas c, {required bool antiAlias}) clipTo,
    ) => _Open((c) {
      c.save();
      clipTo(c, antiAlias: behavior != Clip.hardEdge);
      if (behavior != Clip.antiAliasWithSaveLayer) return 1;
      c.saveLayer(bounds, Paint());
      return 2;
    });

    switch (layer) {
      case UnderlayPictureLayer():
        final bounds = reaching(layer.canvasBounds);
        _add(at, _Glass(layer, transform, clip, state, bounds), bounds);
      case PictureLayer(:final picture?):
        final bounds = reaching(layer.canvasBounds);
        _add(at, _Leaf(picture, transform, clip, state, bounds), bounds);
      case PictureLayer():
        break;
      case TextureLayer(:final rect) || PlatformViewLayer(:final rect):
        final bounds = reaching(rect);
        _add(at, _Block(layer, bounds), bounds);
      case OpacitySeedLayer():
        final reads = filtered ? _everywhere : clip ?? _everywhere;
        push(layer, _Seed(layer, reads));
      case BackdropFilterLayer():
        final reads = filtered ? _everywhere : clip ?? _everywhere;
        _add(at, _Block(layer, reads), reads);
        return false;
      case SeededBackdropPassLayer():
        push(layer, _Pass(layer, transform, clip, filtered: filtered));
      case LiquidGlassBackdropFilterLayer(clip: final rect, :final reach):
        push(
          layer,
          _Served(
            layer,
            transform,
            clip,
            state,
            filtered ? _everywhere : clipped(rect.inflate(reach)),
          ),
        );
      case TransformLayer(:final offset):
        final effective = Matrix4.translationValues(offset.dx, offset.dy, 0);
        if (layer.transform case final matrix?) effective.multiply(matrix);
        push(
          layer,
          _Open((c) {
            c.save();
            c.transform(effective.storage);
            return 1;
          }),
          next: transform.multiplied(effective),
        );
      case OpacityLayer(:final offset):
        final alpha = layer.alpha ?? 255;
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            if (alpha == 255) return 1;
            c.saveLayer(null, _Prefix._alpha(alpha));
            return 2;
          }),
          next: shifted(offset),
          nextState: [...state, alpha],
        );
      case ImageFilterLayer(:final imageFilter?, :final offset):
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            c.saveLayer(null, _Prefix._filtering(imageFilter));
            return 2;
          }),
          next: shifted(offset),
          keepClip: false,
          nextState: [...state, imageFilter],
          nextFiltered: true,
        );
      case OffsetLayer(:final offset)
          when layer.runtimeType == OffsetLayer ||
              layer is GeometryTransformTrackingLayer:
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            return 1;
          }),
          next: shifted(offset),
        );
      case ColorFilterLayer(:final colorFilter?):
        push(
          layer,
          _Open((c) {
            final paint = Paint();
            paint.colorFilter = colorFilter;
            c.saveLayer(null, paint);
            return 1;
          }),
          nextState: [...state, colorFilter],
        );
      case ShaderMaskLayer(
        :final shader?,
        :final maskRect?,
        :final blendMode?,
      ):
        // A FragmentShader keeps its identity while its uniforms change.
        final token = shader is ui.FragmentShader ? Object() : shader;
        final open = _Open((c) {
          c.saveLayer(null, Paint());
          return 1;
        }, mask: (shader, maskRect, blendMode));
        open.extra = reaching(maskRect);
        push(
          layer,
          open,
          nextState: [...state, token, maskRect, blendMode],
        );
      case ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        push(
          layer,
          clipping(
            clipRect,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipRect(clipRect, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(clipRect),
          nextState: [...state, clipRect, clipBehavior],
        );
      case ClipRRectLayer(:final clipRRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        push(
          layer,
          clipping(
            clipRRect.outerRect,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipRRect(clipRRect, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(clipRRect.outerRect),
          nextState: [...state, clipRRect, clipBehavior],
        );
      case ClipRSuperellipseLayer(
            :final clipRSuperellipse?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        push(
          layer,
          clipping(
            clipRSuperellipse.outerRect,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipRSuperellipse(clipRSuperellipse, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(clipRSuperellipse.outerRect),
          nextState: [...state, clipRSuperellipse, clipBehavior],
        );
      case ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none:
        final bounds = clipPath.getBounds();
        push(
          layer,
          clipping(
            bounds,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipPath(clipPath, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(bounds),
          nextState: [...state, clipPath, clipBehavior],
        );
      case NativeClipLayer(
            enabled: true,
            :final geometry?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        final (bounds, clipTo) = switch (geometry) {
          final Rect rect => (
            rect,
            (Canvas c, {required bool antiAlias}) =>
                c.clipRect(rect, doAntiAlias: antiAlias),
          ),
          final RRect rect => (
            rect.outerRect,
            (Canvas c, {required bool antiAlias}) =>
                c.clipRRect(rect, doAntiAlias: antiAlias),
          ),
          final RSuperellipse rect => (
            rect.outerRect,
            (Canvas c, {required bool antiAlias}) =>
                c.clipRSuperellipse(rect, doAntiAlias: antiAlias),
          ),
          final Path path => (
            path.getBounds(),
            (Canvas c, {required bool antiAlias}) =>
                c.clipPath(path, doAntiAlias: antiAlias),
          ),
          _ => (Rect.largest, null),
        };
        push(
          layer,
          clipTo == null
              ? _Undrawable(layer)
              : clipping(bounds, clipBehavior, clipTo),
          keepClip: false,
          nextClip: clipped(bounds),
          nextState: [...state, geometry, clipBehavior],
        );
      case LeaderLayer(:final offset):
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            return 1;
          }),
          next: shifted(offset),
        );
      case ClipRectLayer() ||
          ClipRRectLayer() ||
          ClipRSuperellipseLayer() ||
          ClipPathLayer() ||
          NativeClipLayer() ||
          AnnotatedRegionLayer():
        push(layer as ContainerLayer, _Open.plain());
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        push(layer, _Open.plain());
      case ContainerLayer() when LiquidGlassUnderlay.effectsOf(layer) != null:
        final effects = LiquidGlassUnderlay.effectsOf(layer)!;
        final next = transform.multiplied(effects.transform);
        var nextClip = clip;
        final effectState = <Object?>[];
        final rounded = effects.clip;
        if (rounded != null) {
          final bounds = MatrixUtils.transformRect(next, rounded.outerRect);
          nextClip = clip == null ? bounds : clip.intersect(bounds);
          effectState.add(rounded);
        }
        final alpha = effects.alpha;
        if (alpha != null) effectState.add(alpha);
        final blur = effects.blur;
        if (blur > 0) {
          effectState.add(blur);
          nextClip = null;
        }
        push(
          layer,
          _Open((c) {
            c.save();
            c.transform(effects.transform.storage);
            if (rounded != null) c.clipRRect(rounded);
            var saves = 1;
            if (alpha != null) {
              c.saveLayer(null, _Prefix._alpha(alpha));
              saves++;
            }
            if (blur > 0) {
              c.saveLayer(
                null,
                _Prefix._filtering(
                  ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ),
              );
              saves++;
            }
            return saves;
          }),
          next: next,
          keepClip: false,
          nextClip: nextClip,
          nextState: [...state, ...effectState],
          nextFiltered: blur > 0,
        );
      default:
        _add(
          at,
          _Unknown(layer, transform, clip, filtered: filtered),
          _everywhere,
        );
        return layer is! ContainerLayer;
    }
    return true;
  }

  // Replays the entries before [limit] that reach [prefix]'s band onto its
  // canvas, if it has one, and signs them, as [_Prefix.walk] would.
  void replay(_Prefix prefix, int limit) {
    final band = prefix.band;
    final c = prefix.canvas;
    final out = prefix.out;
    final open = <(int, _Open)>[];
    var i = 0;
    var through = true;

    void sign(
      ui.Picture picture,
      Matrix4 transform,
      Rect? clip,
      List<Object?> state,
    ) {
      out.add(picture);
      out.add(transform);
      out.add(clip);
      out.addAll(state);
      out.add(#leaf);
      c?.drawPicture(picture);
    }

    // Steps past a group, or ends the replay when the stop lies inside it.
    void skip(_Open group) {
      if (group.end < 0 || group.end >= limit) {
        through = false;
      } else {
        i = group.end + 1;
      }
    }

    loop:
    while (i < limit) {
      final entry = entries[i];
      switch (entry) {
        case _Leaf(:final picture, :final transform, :final clip, :final state):
          if (_meets(entry.bounds, band)) {
            sign(picture, transform, clip, state);
          }
        case _Glass(:final layer, :final transform, :final clip, :final state):
          if (_meets(entry.bounds, band)) {
            if (layer.picture == null) {
              if (layer.pendingLevel case final level? when c == null) {
                // Glass over a copy that is not drawn yet: a copy that holds
                // it is drawn after it, and a signature that holds it
                // matches none.
                if (level > prefix.waits) prefix.waits = level;
                out.add(Object());
                i++;
                continue loop;
              }
              layer.resolve();
            }
            if (layer.picture case final picture?) {
              sign(picture, transform, clip, state);
            }
          }
        case _Block(:final layer, :final bounds):
          if (_meets(bounds, band)) {
            prefix.blocked = true;
            prefix.blocker ??= layer;
            break loop;
          }
        case _Unknown(:final layer, :final transform, :final clip):
          if (prefix._mayReach(
            layer,
            transform,
            clip,
            filtered: entry.filtered,
          )) {
            prefix.blocked = true;
            prefix.blocker ??= layer;
            break loop;
          }
        case _Close():
          final (saves, group) = open.removeLast();
          if (c != null) group.finish(c, saves);
        case _Open():
          if (entry.end >= 0 &&
              entry.end < limit &&
              !_meets(entry.bounds, band)) {
            i = entry.end + 1;
            continue loop;
          }
          switch (entry) {
            case _Seed(:final layer, :final reads) when layer.seeded:
              if (_meets(reads, band)) {
                prefix.blocked = true;
                prefix.blocker ??= layer;
                break loop;
              }
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Pass(:final layer) when layer.hidden:
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Pass(:final layer) when layer.scenePass != null:
              if (_meets(entry.reads(layer.scenePass!.rect), band)) {
                prefix.blocked = true;
                prefix.blocker ??= layer;
                break loop;
              }
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Served(:final layer) when layer.servedPicture == null:
              if (_meets(entry.reads, band)) {
                prefix.blocked = true;
                prefix.blocker ??= layer;
                break loop;
              }
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Served(:final layer, :final transform, :final clip):
              sign(layer.servedPicture!, transform, clip, entry.state);
            case _Undrawable(:final layer) when c != null:
              prefix.blocked = true;
              prefix.blocker ??= layer;
              break loop;
            default:
              break;
          }
          open.add((c == null ? 0 : entry.apply(c), entry));
      }
      i++;
    }
    prefix.reached = through && !prefix.blocked && i >= limit;
    if (c != null) {
      for (final (saves, group) in open.reversed) {
        group.finish(c, saves);
      }
    }
  }
}

const _everywhere = Rect.largest;

// Content clipped away reaches no band, even where its empty rect lies
// across one.
bool _meets(Rect bounds, Rect band) => !bounds.isEmpty && bounds.overlaps(band);

final class _Cursor {
  _Cursor(
    this.layer,
    this.next,
    this.transform,
    this.clip,
    this.state, {
    required this.filtered,
    required this.open,
  });

  final ContainerLayer? layer;
  Layer? next;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final bool filtered;
  final int open;
  Rect bounds = Rect.zero;

  void include(Rect rect) => bounds = union(bounds, rect);

  static Rect union(Rect a, Rect b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return a.expandToInclude(b);
  }
}

sealed class _Entry {
  const _Entry();
}

final class _Leaf extends _Entry {
  _Leaf(this.picture, this.transform, this.clip, this.state, this.bounds);

  final ui.Picture picture;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect bounds;
}

// Glass over a copy, whose picture is recorded once its copy is drawn.
final class _Glass extends _Entry {
  _Glass(this.layer, this.transform, this.clip, this.state, this.bounds);

  final UnderlayPictureLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect bounds;
}

// What a copy cannot draw: a copy whose band it reaches fails.
final class _Block extends _Entry {
  _Block(this.layer, this.bounds);

  final Layer layer;
  final Rect bounds;
}

// A layer of a type the copy does not know.
final class _Unknown extends _Entry {
  _Unknown(this.layer, this.transform, this.clip, {required this.filtered});

  final Layer layer;
  final Matrix4 transform;
  final Rect? clip;
  final bool filtered;
}

final class _Close extends _Entry {
  const _Close();
}

// A container: what it applies to the canvas around its children and how
// many saves that takes, and the extent of what it draws once its children
// are walked.
class _Open extends _Entry {
  _Open(this.apply, {this.mask});

  _Open.plain() : apply = _none, mask = null;

  static int _none(Canvas c) => 0;

  final int Function(Canvas c) apply;
  final (Shader, Rect, BlendMode)? mask;
  Rect extra = Rect.zero;
  Rect bounds = _everywhere;
  int end = -1;

  void finish(Canvas c, int saves) {
    if (mask case (final shader, final rect, final blendMode)) {
      // The engine draws a shader mask over what it masks, in a layer.
      final paint = Paint();
      paint.shader = shader;
      paint.blendMode = blendMode;
      c.translate(rect.left, rect.top);
      c.drawRect(Offset.zero & rect.size, paint);
    }
    for (var n = 0; n < saves; n++) {
      c.restore();
    }
  }
}

// A clip the copy cannot draw: a copy drawn under it fails.
final class _Undrawable extends _Open {
  _Undrawable(this.layer) : super(_Open._none);

  final Layer layer;
}

// An opacity pass that glass seeds with its backdrop while it reads it.
final class _Seed extends _Open {
  _Seed(this.layer, this.reads) : super(_Open._none) {
    extra = reads;
  }

  final OpacitySeedLayer layer;
  final Rect reads;
}

// A seeded backdrop pass, hidden or read as glass composites.
final class _Pass extends _Open {
  _Pass(this.layer, this.transform, this.clip, {required this.filtered})
    : super(_Open._none) {
    extra = _everywhere;
  }

  final SeededBackdropPassLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final bool filtered;

  Rect reads(Rect local) {
    if (filtered) return _everywhere;
    final bounds = MatrixUtils.transformRect(transform, local);
    return clip == null ? bounds : clip!.intersect(bounds);
  }
}

// A filter that draws its copy once it composites, or reads its backdrop.
final class _Served extends _Open {
  _Served(this.layer, this.transform, this.clip, this.state, this.reads)
    : super(_Open._none) {
    extra = reads;
  }

  final LiquidGlassBackdropFilterLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect reads;
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

  // Counts frames, changing once each frame has composited, or null outside
  // a frame's persistent callbacks: a pass between frames, such as an image
  // taken after one, sees layers the next frame may still change.
  static int? get frame {
    final scheduler = SchedulerBinding.instance;
    if (!_counting) {
      _counting = true;
      // The persistent callback first runs after the next frame composites:
      // the frame this one is counted in ends first.
      scheduler.addPostFrameCallback((_) => _frame++);
      scheduler.addPersistentFrameCallback((_) => _frame++);
    }
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return null;
    }
    return _frame;
  }

  static Rect of(Layer layer) {
    final frame = _Extent.frame;
    if (_cache[layer] case (final at, final rect) when at == frame) {
      return rect;
    }
    final rect = _measure(layer);
    if (frame != null) _cache[layer] = (frame, rect);
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
/// logical pixels, at [offset] (the image's pixels) in [image], at
/// [pixelRatio].
///
/// A copy recorded this frame is drawn when its [image] or [offset] is first
/// read, together with every copy recorded before it: a caller that can
/// wait reads them when the scene is added ([UnderlayPictureLayer]).
@internal
final class UnderlayCopy {
  const UnderlayCopy._(this._underlay, this.rect, this.pixelRatio);

  final BackdropUnderlay _underlay;

  /// The screen rect the copy holds, in logical pixels.
  final Rect rect;

  /// The copy's pixels per logical pixel along each side.
  final double pixelRatio;

  /// Whether [image] is drawn already.
  bool get ready => _underlay._image != null;

  /// The image that holds the copy, shared with other copies of the frame.
  ui.Image get image {
    if (!ready) _Atlas.flush();
    return _underlay._image!;
  }

  /// Where [rect]'s top left corner sits in [image], in its pixels.
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
    void place(Canvas canvas, _Tile tile) {
      canvas.save();
      canvas.translate(tile.offset.dx, tile.offset.dy);
      canvas.clipRect(Offset.zero & tile.bounds.size);
      canvas.drawPicture(tile.content!);
      canvas.restore();
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Copies that a filter replaces whole and that lie side by side share
    // one filtered layer: the blur reaches across a copy's edge no further
    // than the band a copy holds around what its glass samples, and the
    // layer is clipped to the copies so that it reaches no other. The layer
    // is filtered whole, so copies far apart are filtered each on its own,
    // and so are a pair: the shared layer saves the raster thread a layer a
    // copy, which pays for its larger area only with more.
    final shared = <(Object?, double), List<_Tile>>{};
    final isolated = <_Tile>[];
    for (final tile in tiles) {
      if (tile.filter == null) {
        place(canvas, tile);
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
    final clusters = <List<_Tile>>[];
    for (final group in shared.values) {
      for (final cluster in _clusters(group)) {
        if (cluster.length < 3) {
          isolated.addAll(cluster);
        } else {
          clusters.add(cluster);
        }
      }
    }
    final content = recorder.endRecording();
    final ui.Image image;
    if (isolated.isEmpty && clusters.isEmpty) {
      image = content.toImageSync(width, height);
    } else {
      // The filter reads copies as a backdrop filter reads the screen, in a
      // layer around them: it reads that layer alone, which a pass split at
      // the filter loads and stores. It stands under the view's scale, as
      // the backdrop filter it replaces does.
      final b = ui.SceneBuilder();
      b.addPicture(Offset.zero, content);
      final pictures = <ui.Picture>[];
      for (final cluster in clusters) {
        final dpr = cluster.first.devicePixelRatio;
        final area = Path();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final tile in cluster) {
          area.addRect(tile.bounds);
          place(canvas, tile);
        }
        final copies = recorder.endRecording();
        pictures.add(copies);
        final bounds = area.getBounds();
        b.pushClipPath(area, clipBehavior: Clip.antiAliasWithSaveLayer);
        b.addPicture(Offset.zero, copies);
        b.pushTransform(Matrix4.diagonal3Values(dpr, dpr, 1).storage);
        b.pushClipRect(
          Rect.fromLTRB(
            bounds.left / dpr,
            bounds.top / dpr,
            bounds.right / dpr,
            bounds.bottom / dpr,
          ),
          clipBehavior: Clip.hardEdge,
        );
        b.pushBackdropFilter(cluster.first.filter!);
        b.pop();
        b.pop();
        b.pop();
        b.pop();
      }
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
      for (final picture in pictures) {
        picture.dispose();
      }
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
