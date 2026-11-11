import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:liquid_glass_renderer/src/rendering/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

part 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object_frame.dart';

/// Shared base for render objects that assemble [RenderLiquidGlassGeometry]
/// shapes and paint one glass effect over the layer's foreground.
///
/// The base owns shape registration via [GeometryRenderLink], transform
/// polling ([FramePollMarker] and the compositor-translation poll), the
/// retained [GlassFrameState] with its encoded input snapshot, layer
/// shadows, effect bounds, retained ancestor clips ([RetainedGlassClip])
/// and compositor translation. Subclasses implement only their effect in
/// [paintFrame]: real glass renders a GPU matte plus the final shader
/// filter; fake glass draws a blur plus a surface shader.
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  /// Creates a layer of glass that draws the geometry [link] gathers.
  LiquidGlassRenderObject({
    required this._link,
    required this._settings,
    required this._defaultAppearance,
    required this._devicePixelRatio,
  });

  // MARK: Configuration

  GeometryRenderLink _link;

  /// The link its glass and blend groups register their geometry on.
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    if (attached) {
      _link.onMembershipChanged = null;
      value.onMembershipChanged = markNeedsPaint;
    }
    _link = value;
    markNeedsPaint();
  }

  /// The registered shapes that are painted when this layer paints (see
  /// [isGlassShapePainted]), in paint order.
  @protected
  List<RenderLiquidGlassGeometry> get paintedShapes => [
    for (final shape in link.shapes)
      if (isGlassShapePainted(shape, this)) shape,
  ];

  List<RenderLiquidGlassGeometry> _lastPaintedShapes = const [];

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // A glass or blend group that joins or leaves under a repaint boundary of
    // its own repaints only that boundary. Real glass would otherwise learn of
    // it in its compositing poll and draw it a frame late.
    _link.onMembershipChanged = markNeedsPaint;
  }

  @override
  void detach() {
    _link.onMembershipChanged = null;
    super.detach();
  }

  LiquidGlassSettings _settings;

  /// The settings its glass draws with.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    final old = _settings;
    _settings = value;
    onSettingsChanged(old);
    markNeedsPaint();
  }

  /// Called after [settings] changed, before [markNeedsPaint].
  @protected
  void onSettingsChanged(LiquidGlassSettings old) {}

  LiquidGlassAppearance _defaultAppearance;

  /// The appearance of glass that sets none of its own.
  LiquidGlassAppearance get defaultAppearance => _defaultAppearance;
  set defaultAppearance(LiquidGlassAppearance value) {
    if (_defaultAppearance == value) return;
    _defaultAppearance = value;
    onAppearanceChanged();
    markNeedsPaint();
  }

  /// Called after [defaultAppearance] changed, before [markNeedsPaint].
  @protected
  void onAppearanceChanged() {}

  double _devicePixelRatio;

  /// The device pixels per logical pixel it draws at.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    onDevicePixelRatioChanged();
    markNeedsPaint();
  }

  /// Called after [devicePixelRatio] changed, before [markNeedsPaint].
  @protected
  void onDevicePixelRatioChanged() {}

  // MARK: Retained frame state

  GlassFrameState _frameState = GlassFrameState.empty;

  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _shapesWithGeometry = [];

  /// The inputs the effect last encoded: each shape's render object,
  /// geometry cache and transform into this layer. The compositor-translation
  /// poll compares [shapesWithGeometry] instead, so this may stay stale while
  /// an idle frame keeps the last encode.
  final List<_EncodedGeometryInput> _encodedGeometryInputs = [];

  /// Layer-local bounds the retained frame was encoded for. Only effects
  /// that encode geometry (the GPU matte) read them.
  @protected
  Rect? encodedGeometryBounds;

  /// Bounds the current frame's effect occupies, in local coordinates;
  /// [paintFrame] implementations set it.
  @protected
  Rect effectPaintBounds = Rect.zero;

  @override
  Rect get paintBounds =>
      effectPaintBounds.isEmpty ? super.paintBounds : effectPaintBounds;

  /// Number of times [paint] has run. Ancestor motion should not increment
  /// this once the frame has been encoded.
  @visibleForTesting
  int debugPaintCount = 0;

  final _compositionProbe = GlassCompositionProbe();
  final _framePoll = FramePollMarker();
  final _effectLayer = LayerHandle<OffsetLayer>();
  final _originalShadows = LayerHandle<ContainerLayer>();
  final _shadowPicture = LayerHandle<PictureLayer>();
  final _ancestorClips = RetainedGlassClip();
  final _idleAncestorClips = RetainedGlassClip();
  List<Object> _retainedStructure = [];

  /// The offset this layer last painted at; retained updates reuse it.
  @protected
  Offset retainedPaintOffset = Offset.zero;
  Offset _effectTranslation = Offset.zero;

  /// The structural identity of the last committed frame: render objects,
  /// whether they carry shadows, and their ancestry to this layer.
  @protected
  List<Object> get retainedStructure => _retainedStructure;

  /// Whether the committed frame holds shapes but drew no active effect, so
  /// ancestor motion moves its retained layers without a repaint.
  @protected
  bool get hasReusableIdleContents =>
      _frameState != GlassFrameState.active && _shapesWithGeometry.isNotEmpty;

  /// Bounds of the clips between this object and its shapes that are
  /// re-applied around the glass filter, in local coordinates, or `null`.
  @protected
  Rect? get retainedClipBounds =>
      _frameState == GlassFrameState.idle ? null : _ancestorClips.ownerBounds;

  /// Translation applied to the retained layer-owned effect since paint.
  @protected
  Offset get compositorTranslation => _effectTranslation;

  /// The translation its effect layer last composited at.
  @visibleForTesting
  Offset get debugCompositorTranslation => _effectTranslation;

  /// Moves all layer-owned painting without recording it again.
  @protected
  bool setCompositorTranslation(Offset value) {
    if (_nearOffset(_effectTranslation, value)) return false;
    _effectTranslation = value;
    _effectLayer.layer?.offset = value;
    return true;
  }

  /// Decides whether the opacity pass around this glass is seeded, before
  /// the update pass.
  @protected
  void syncCompositionOpacity() => _compositionProbe.syncOpacity(this);

  /// Whether this layer paints inside a fractional-opacity pass that a live
  /// backdrop read needs seeded.
  @protected
  bool get compositionProbeSeeding => _compositionProbe.seeding;

  /// Leaves the fractional-opacity pass unseeded while this layer reads no
  /// backdrop.
  @protected
  bool get compositionSeedSuppressed => _compositionProbe.suppressed;
  @protected
  set compositionSeedSuppressed(bool value) =>
      _compositionProbe.suppressed = value;

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    _compositionProbe.paint(
      context,
      offset,
      _paintGlass,
      owner: this,
    );
  }

  void _paintGlass(PaintingContext context, Offset offset) {
    retainedPaintOffset = offset;
    assert(() {
      debugPaintCount++;
      return true;
    }(), 'Track layer paints in debug builds.');
    final bounds = prepareFrameGeometry();
    paintFrame(context, offset, bounds);
    // Foreground always paints in its own render ancestry, above the glass.
    super.paint(context, offset);
  }

  /// Brings every registered geometry up to date for this frame and returns the
  /// bounds of the shapes it draws, or null when it draws none.
  @protected
  Rect? prepareFrameGeometry() {
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    commitFrameGeometry(candidate);
    _frameState = _classifyFrame(candidate);
    return bounds;
  }

  /// Paints this layer's effect for the just-committed [frameState].
  ///
  /// [geometryBounds] is the union of the committed shapes' geometry bounds
  /// in this layer's coordinates, or `null` when no shape collected geometry
  /// this frame. The foreground is painted by the caller afterwards.
  @protected
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  );

  // The state a frame that collected [geometries] commits: empty when nothing
  // drawable remains, idle when every shape is invisible and the effect keeps
  // its matte, and active otherwise.
  GlassFrameState _classifyFrame(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (geometries.isEmpty) return GlassFrameState.empty;
    if (!_hasVisibleShape(geometries)) {
      return encodesMatte ? GlassFrameState.idle : GlassFrameState.empty;
    }
    return hasDrawableGlass(geometries)
        ? GlassFrameState.active
        : GlassFrameState.empty;
  }

  static bool _hasVisibleShape(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) => shape.appearance.visibility > 0,
    ),
  );

  /// Logical short side of the smallest visible committed shape, which sizes
  /// the layer-wide blur; null without one.
  @protected
  double? smallestVisibleShortSide() {
    double? shortest;
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shape.appearance.visibility <= 0) continue;
        // shapeBounds is already in the geometry's local space.
        final side = MatrixUtils.transformRect(
          geometryToLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        shortest = shortest == null ? side : min(shortest, side);
      }
    }
    return shortest;
  }

  /// The short side past which [LiquidGlassSettings.frostSigmaAt] no longer
  /// grows the blur.
  static const largestFittedShortSide = 150.0;

  /// Whether the effect encodes its shapes into a matte, as real glass does.
  ///
  /// A frame whose shapes are all hidden then idles and keeps the matte,
  /// a shape draws only where the matte can hold it, and a shape's encode is
  /// current while its matte revision holds. Without a matte every shape
  /// draws, a hidden frame is empty, and an encode is current while the
  /// shape's geometry is the one painted from.
  @protected
  bool get encodesMatte;

  /// The render objects of all committed shapes, in frame order.
  @protected
  Iterable<RenderBox> get shapeRenderObjects => _shapesWithGeometry.expand(
    (entry) => entry.$2.shapes.map((shape) => shape.renderObject),
  );

  /// Snapshots the committed shapes into the encoded inputs.
  @protected
  void rememberFrameInputs() {
    final inputs = _encodedGeometryInputs;
    final sharedLength = min(
      inputs.length,
      _shapesWithGeometry.length,
    );
    for (var index = 0; index < sharedLength; index++) {
      final current = _shapesWithGeometry[index];
      inputs[index].update(
        current.$1,
        current.$2,
        current.$3,
      );
    }
    if (inputs.length > _shapesWithGeometry.length) {
      inputs.removeRange(
        _shapesWithGeometry.length,
        inputs.length,
      );
    }
    for (
      var index = inputs.length;
      index < _shapesWithGeometry.length;
      index++
    ) {
      final current = _shapesWithGeometry[index];
      inputs.add(
        _EncodedGeometryInput(
          current.$1,
          current.$2,
          current.$3,
        ),
      );
    }
  }

  /// Drops the encoded input snapshot together with its bounds.
  @protected
  void clearFrameInputs() {
    _encodedGeometryInputs.clear();
    encodedGeometryBounds = null;
  }

  /// Polls the committed shapes ([shapesWithGeometry]) for one translation
  /// the compositor can apply without a repaint.
  @protected
  ({bool needsRepaint, Offset? translation}) pollCompositorTranslation() {
    // A shape going offstage or onstage changes this list, which repaints.
    final current = paintedShapes;
    final committed = _shapesWithGeometry;
    if (_framePoll.polledThisFrame && committed.length == current.length) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (current.isEmpty && committed.isEmpty) {
      return (needsRepaint: false, translation: Offset.zero);
    }
    if (committed.isEmpty || current.length != committed.length) {
      for (final geometry in current) {
        geometry.pollRelativeTransforms(this);
      }
      return (needsRepaint: true, translation: null);
    }

    var canTranslate = true;
    var needsRepaint = false;
    final transforms = <Matrix4>[];
    final translated = <RenderLiquidGlassGeometry>[];
    for (var index = 0; index < current.length; index++) {
      final geometry = current[index];
      final encoded = committed[index];
      final wasCurrent = _isSnapshotCurrent(geometry, encoded.$2);
      final poll = geometry.pollRelativeTransforms(this);
      final transform = poll.transform;
      if (poll.selfChanged || poll.childChanged) needsRepaint = true;
      if (!identical(geometry, encoded.$1) ||
          !wasCurrent ||
          poll.childChanged ||
          transform == null) {
        canTranslate = false;
        needsRepaint = true;
        continue;
      }
      transforms.add(transform);
      if (poll.selfChanged) translated.add(geometry);
    }

    if (!canTranslate) {
      return (needsRepaint: needsRepaint, translation: null);
    }
    final translation = _sharedTranslation(
      [for (final entry in committed) entry.$3],
      transforms,
    );
    if (translation == null) return (needsRepaint: true, translation: null);
    for (final geometry in translated) {
      geometry.acceptCompositorTranslation();
    }
    return (needsRepaint: false, translation: translation);
  }

  // Whether [geometry]'s inputs still match the snapshot it was encoded with
  // (see [encodesMatte]).
  bool _isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => encodesMatte
      ? geometry.hasCurrentMatteRevision(snapshot.matteRevision)
      : geometry.hasCurrentGeometryCache(snapshot);

  /// The one translation that maps every encoded transform in [before] to
  /// the matching transform in [current], or `null` when there is none.
  static Offset? _sharedTranslation(
    List<Matrix4> before,
    List<Matrix4> current,
  ) {
    Offset? shared;
    for (var index = 0; index < current.length; index++) {
      final delta = _translationDelta(before[index], current[index]);
      if (delta == null) return null;
      if (shared == null) {
        shared = delta;
      } else if (!_nearOffset(shared, delta)) {
        return null;
      }
    }
    return shared ?? Offset.zero;
  }

  static Offset? _translationDelta(Matrix4 before, Matrix4 after) {
    final a = before.storage;
    final b = after.storage;
    for (var index = 0; index < 16; index++) {
      if (index == 12 || index == 13) continue;
      if ((a[index] - b[index]).abs() > 1e-6) return null;
    }
    return Offset(b[12] - a[12], b[13] - a[13]);
  }

  static bool _nearOffset(Offset a, Offset b) =>
      (a.dx - b.dx).abs() <= 1e-6 && (a.dy - b.dy).abs() <= 1e-6;

  static bool _nearRect(Rect a, Rect b) =>
      (a.left - b.left).abs() <= 1e-6 &&
      (a.top - b.top).abs() <= 1e-6 &&
      (a.right - b.right).abs() <= 1e-6 &&
      (a.bottom - b.bottom).abs() <= 1e-6;

  /// The translation that maps the encoded inputs onto [bounds] when every
  /// committed shape still matches its snapshot and moved uniformly, or
  /// `null` otherwise.
  @protected
  Offset? encodedMatteDelta(Rect bounds) {
    final oldBounds = encodedGeometryBounds;
    if (oldBounds == null ||
        _encodedGeometryInputs.length != _shapesWithGeometry.length) {
      return null;
    }
    for (var index = 0; index < _shapesWithGeometry.length; index++) {
      final current = _shapesWithGeometry[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(current.$1, encoded.renderObject) ||
          current.$2.matteRevision != encoded.cache.matteRevision) {
        return null;
      }
    }
    final delta = _sharedTranslation(
      [for (final entry in _encodedGeometryInputs) entry.transform],
      [for (final entry in _shapesWithGeometry) entry.$3],
    );
    if (delta == null) return null;
    if (!_nearRect(bounds, oldBounds.shift(delta))) return null;
    return delta;
  }

  // MARK: Compositing

  /// Runs the per-frame compositing update: opacity seeding, clip sync, and
  /// the compositor-translation poll. Subclasses react through
  /// [onCompositorTranslated] and [onCompositorTranslationMissed].
  @protected
  void runCompositorPoll() {
    syncCompositionOpacity();
    syncAncestorClips();
    final motion = pollCompositorTranslation();
    if (motion.translation case final translation?) {
      setCompositorTranslation(translation);
      onCompositorTranslated(translation);
      if (_frameState == GlassFrameState.active &&
          _originalShadows.layer != null &&
          _ancestorClips.hasIndividualClips &&
          !_framePoll.polledThisFrame) {
        recordGlassShadows(retainedPaintOffset);
      }
      return;
    }
    onCompositorTranslationMissed(motion);
  }

  /// A shared translation was applied to the retained effect.
  @protected
  void onCompositorTranslated(Offset translation) {}

  /// No shared translation applies to the retained effect this frame.
  @protected
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  );

  /// Pushes the retained effect layer under the clips that are active for
  /// the current [frameState], then runs [painter] inside it.
  @protected
  void paintRetainedEffect(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter,
  ) {
    final layer = (_effectLayer.layer ??= ThinOffsetLayer())
      ..offset = _effectTranslation;
    (_frameState == GlassFrameState.idle ? _idleAncestorClips : _ancestorClips)
        .pushLayer(
          context,
          layer,
          painter,
          offset,
        );
  }

  /// Drops the retained effect layer.
  @protected
  void releaseRetainedEffectLayer() {
    _effectLayer.layer = null;
    clearGlassShadows();
  }

  /// Synchronizes the retained clips that are active for [frameState].
  @protected
  void syncAncestorClips() =>
      (_frameState == GlassFrameState.idle
              ? _idleAncestorClips
              : _ancestorClips)
          .sync();

  /// Updates the dormant-frame clip ancestry from the committed shapes.
  @protected
  void updateIdleAncestorClips() =>
      _idleAncestorClips.update(this, shapeRenderObjects);

  // MARK: Effect bounds and shadows

  /// Logical outset the effect paints around the geometry bounds: the SDF
  /// contour support for real glass, the surface outset for the fallback.
  @protected
  double get materialOutset;

  /// Grows [bounds] by this layer's [materialOutset] and the committed
  /// shapes' exterior shadows, in layer coordinates.
  @protected
  Rect expandEffectBounds(Rect bounds) => expandForGlassShadows(
    bounds.inflate(materialOutset),
    _shapesWithGeometry.map((entry) => (entry.$2.shapes, entry.$3)),
  );

  /// Whether [recordGlassShadows] records the shadows for a place under the
  /// glass, where the glass covers them inside its silhouettes, instead of
  /// over it, cut outside them. Only glass that paints every pixel of its
  /// silhouettes opaquely over what lies under it may set it, and only while
  /// no shape fades ([glassShadowsFade]).
  ///
  /// NEAR: over the glass the cut lets the shadow half a pixel into the
  /// glass's edge, so that no seam shows between them; under it the glass
  /// covers its edge pixels by their coverage and needs no reach. The two
  /// differ only along the edge: by up to 57 levels under a shadow of alpha
  /// 0.25 in the host test, and by up to 23 on the Pixel 6a's glass bench
  /// under the 0.08 to 0.1 of glass controls, in a line two device pixels
  /// wide and at corners, where the cut's path and the shader's shape part;
  /// elsewhere by at most 3 levels, as copies without shadows do.
  @protected
  bool shadowsUnderGlass = false;

  /// [shadowsUnderGlass], for tests.
  @visibleForTesting
  bool get debugShadowsUnderGlass => shadowsUnderGlass;

  /// Whether a committed shape is partly visible, which makes the shadows
  /// show through it by the part it has yet to fade in.
  @protected
  bool get glassShadowsFade => _anyShapeFading;

  /// The picture [recordGlassShadows] last recorded, wherever it lies now.
  @protected
  PictureLayer? get glassShadowPicture => _shadowPicture.layer;

  /// Draws every committed shape's exterior shadows into [canvas] at
  /// [offset], kept outside the silhouette of every shape above zero
  /// visibility so they do not darken the glass, or whole for the glass to
  /// cover with [shadowsUnderGlass]. Shadow color, blur and the cut-out
  /// silhouette scale with shape visibility.
  @protected
  void drawGlassShadows(Canvas canvas, Offset offset) {
    final hasShadows = _shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) return;
    final entry = _shapesWithGeometry.singleOrNull;
    final shape = entry?.$2.shapes.singleOrNull;
    final useNativeOuterBlur =
        shape != null &&
        identical(entry!.$1, shape.renderObject) &&
        shape.shadows.every(
          (shadow) => shadow.offset == Offset.zero && shadow.spreadRadius >= 0,
        );
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (useNativeOuterBlur) {
      _paintShadows(canvas, (_) => true, outer: true);
    } else if (_anyShapeFading) {
      _paintShadowsCutOffscreen(canvas);
    } else if (shadowsUnderGlass) {
      _paintShadows(canvas, (_) => true, outer: false);
    } else {
      // A clip, not an offscreen layer. Shadows whose bounds meet are
      // grouped, and each group is clipped to its own bounds less the
      // silhouettes, so glass scattered over a large layer clips only around
      // each group, not the whole layer.
      final silhouettes = _currentSilhouettes();
      for (final (:bounds, shapes: group) in _shadowGroups()) {
        canvas.save();
        _clipOutsideSilhouettes(canvas, bounds, silhouettes);
        _paintShadows(canvas, group.contains, outer: false);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  void _paintShadows(
    Canvas canvas,
    bool Function(ShapeGeometry shape) include, {
    required bool outer,
  }) {
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (shape.shadows.isEmpty || shapeVisibility <= 0) continue;
        if (!include(shape)) continue;
        _ancestorClips.paintWithIndividualClips(
          canvas,
          shape.renderObject,
          compositorTranslation,
          () {
            canvas
              ..save()
              ..transform(geometryToLayer.storage);
            if (shape.shapeToGeometry case final transform?) {
              canvas.transform(transform.storage);
            }
            final rect = Offset.zero & shape.renderObject.paintSize;
            for (final shadow in shape.shadows) {
              final paint = shadow
                  .copyWith(
                    color: shadow.color.withValues(
                      alpha: shadow.color.a * shapeVisibility,
                    ),
                    blurRadius: shadow.blurRadius * shapeVisibility,
                    blurStyle: outer ? BlurStyle.outer : BlurStyle.normal,
                  )
                  .toPaint();
              drawGlassShape(
                canvas,
                shape.shape,
                rect.shift(shadow.offset).inflate(shadow.spreadRadius),
                paint,
              );
            }
            canvas.restore();
          },
        );
      }
    }
  }

  // Asked several times a frame; the committed shapes change in
  // [commitFrameGeometry] alone.
  bool get _anyShapeFading => _fading ??= _shapesWithGeometry.any(
    (entry) => entry.$2.shapes.any(
      (shape) =>
          shape.appearance.visibility > 0 && shape.appearance.visibility < 1,
    ),
  );

  bool? _fading;

  // A clip cuts a silhouette whole, but a fading glass lets as much of the
  // shadow under it show as it has yet to fade in. Only an offscreen layer
  // cuts by a fraction; fades are brief, so only they pay for one.
  void _paintShadowsCutOffscreen(Canvas canvas) {
    // Bounds only: growing them to pixel buckets changes no pixel, and an
    // animated shape does not get a render target of a new size each frame.
    canvas.saveLayer(
      effectPaintBounds.expandToPixelBuckets(devicePixelRatio),
      Paint(),
    );
    _paintShadows(canvas, (_) => true, outer: false);
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        final visibility = shape.appearance.visibility.clamp(0.0, 1.0);
        if (visibility <= 0) continue;
        canvas
          ..save()
          ..transform(shapeTransformToLayer(shape, geometryToLayer).storage);
        drawGlassShape(
          canvas,
          shape.shape,
          (Offset.zero & shape.renderObject.paintSize).deflate(.5),
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, visibility)
            ..blendMode = BlendMode.dstOut,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  List<({Rect bounds, Set<ShapeGeometry> shapes})> _shadowGroups() {
    final groups = <({Rect bounds, Set<ShapeGeometry> shapes})>[];
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shape.shadows.isEmpty || shape.appearance.visibility <= 0) continue;
        var bounds = expandForGlassShadows(
          MatrixUtils.transformRect(
            shapeTransformToLayer(shape, geometryToLayer),
            Offset.zero & shape.renderObject.paintSize,
          ),
          [
            (<ShapeGeometry>[shape], geometryToLayer),
          ],
        );
        // By identity: ShapeGeometry compares by value, so its hash would walk
        // its appearance, shadows and transform on every lookup.
        final members = Set<ShapeGeometry>.identity()..add(shape);
        // Joining a group can make it meet another: merge until none meets.
        for (var i = groups.length - 1; i >= 0; i--) {
          final (bounds: other, shapes: otherMembers) = groups[i];
          if (!other.overlaps(bounds)) continue;
          bounds = bounds.expandToInclude(other);
          members.addAll(otherMembers);
          groups.removeAt(i);
          i = groups.length;
        }
        groups.add((bounds: bounds, shapes: members));
      }
    }
    return groups;
  }

  // The last draw's silhouettes, matched to shapes by position: an entry is
  // reused while its shape, size and transform stay the same, and only
  // re-mapped when just the transform changed. A size within a hair of the
  // last counts as the same: a moving shape's size, taken as the difference
  // of its moved edges, changes in its last bits from frame to frame.
  List<_Silhouette> _silhouettes = const [];

  static const double _sameSize = 1e-6;

  List<_Silhouette> _currentSilhouettes() {
    final previous = _silhouettes;
    final next = <_Silhouette>[];
    for (final (_, geometry, geometryToLayer) in _shapesWithGeometry) {
      for (final shape in geometry.shapes) {
        if (shape.appearance.visibility <= 0) continue;
        // A copy: the silhouette keeps it to compare with the next frame's.
        final transform = Matrix4.copy(
          shapeTransformToLayer(shape, geometryToLayer),
        );
        final size = shape.renderObject.paintSize;
        final old = next.length < previous.length
            ? previous[next.length]
            : null;
        final sameOutline =
            old != null &&
            old.shape == shape.shape &&
            (old.size.width - size.width).abs() < _sameSize &&
            (old.size.height - size.height).abs() < _sameSize;
        if (sameOutline && MatrixUtils.matrixEquals(old.transform, transform)) {
          next.add(old);
          continue;
        }
        // Half a pixel inside the outline, so the shadow reaches into the
        // glass's antialiased edge and no seam shows between them.
        final outline = (Offset.zero & (sameOutline ? old.size : size)).deflate(
          .5,
        );
        final local = sameOutline
            ? old.local
            : shape.shape.getOuterPath(outline);
        next.add(
          _Silhouette(
            shape.shape,
            sameOutline ? old.size : size,
            local,
            transform,
            // The outline fills its rect up to each side: the rect's bounds
            // are the path's, without asking the engine for them.
            MatrixUtils.transformRect(transform, outline),
          ),
        );
      }
    }
    return _silhouettes = next;
  }

  /// Clips [canvas] to [bounds] less each of [all] whose bounds meet it,
  /// without a path operation. While no two of those silhouettes' bounds
  /// meet, one even-odd path cuts them all as holes; otherwise even-odd would
  /// add back where two overlap, so each clips the bounds less itself and the
  /// clips intersect to the bounds less their union.
  void _clipOutsideSilhouettes(
    Canvas canvas,
    Rect bounds,
    List<_Silhouette> all,
  ) {
    final silhouettes = [
      for (final silhouette in all)
        if (silhouette.bounds.overlaps(bounds)) silhouette,
    ];
    var apart = true;
    for (var i = 0; i < silhouettes.length && apart; i++) {
      for (var j = i + 1; j < silhouettes.length; j++) {
        if (silhouettes[i].bounds.overlaps(silhouettes[j].bounds)) {
          apart = false;
          break;
        }
      }
    }
    Path outside() => Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds);
    if (apart) {
      final path = outside();
      for (final silhouette in silhouettes) {
        silhouette.addTo(path);
      }
      canvas.clipPath(path);
      return;
    }
    for (final silhouette in silhouettes) {
      final path = outside();
      silhouette.addTo(path);
      canvas.clipPath(path);
    }
  }

  /// Records the shadows of its shapes at [offset] into a layer of their own,
  /// or returns null when no shape casts one.
  @protected
  ContainerLayer? recordGlassShadows(Offset offset) {
    final hasShadows = _shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) {
      clearGlassShadows();
      return null;
    }
    final slot = (_originalShadows.layer ??= ContainerLayer())
      ..removeAllChildren();
    _shadowPicture.layer = null;
    if (!hasDrawableGlass(_shapesWithGeometry)) return slot;
    if (!kReleaseMode) GlassWork.pictures++;
    final recorder = ui.PictureRecorder();
    drawGlassShadows(Canvas(recorder), offset);
    final picture = PictureLayer(effectPaintBounds.shift(offset))
      ..picture = recorder.endRecording();
    slot.append(picture);
    _shadowPicture.layer = picture;
    return slot;
  }

  /// Drops the layer [recordGlassShadows] recorded.
  @protected
  void clearGlassShadows() {
    _originalShadows.layer = null;
    _shadowPicture.layer = null;
  }

  /// Forgets every registered geometry.
  @override
  @mustCallSuper
  void dispose() {
    _silhouettes = const [];
    _compositionProbe.dispose();
    _ancestorClips.dispose();
    _idleAncestorClips.dispose();
    clearFrameInputs();
    _effectLayer.layer = null;
    clearGlassShadows();
    super.dispose();
  }

  /// Runs after a frame's shapes are committed to [shapesWithGeometry],
  /// before the frame's state is decided.
  @protected
  void onFrameGeometryCommitted() {}
}
