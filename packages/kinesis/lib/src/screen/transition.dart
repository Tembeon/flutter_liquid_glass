import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/listen.dart';
import 'package:kinesis/src/value.dart';

/// Moves, scales, rotates, fades, blurs, clips and sizes its child from
/// listenable values without building, laying out or repainting the child.
///
/// UIKit: a view's layer properties animated by `UIView.animate`. SwiftUI:
/// the `offset`, `scaleEffect`, `rotationEffect`, `opacity`, `blur` and
/// `frame` modifiers. Flutter: `FadeTransition` for many properties at once.
///
/// A change of the offset, scale, rotation, opacity or blur updates the
/// child's composited layer: no build, layout or repaint. Each of the
/// transform, clip, opacity and blur costs an engine layer only while it is
/// not identity, so an opacity of 1 costs no opacity layer. Scale and
/// rotation pivot on the center.
///
/// [width] and [height] take part in the parent's layout at their presented
/// value, so siblings follow them; the child is laid out at the model size
/// (a `MotionValue`'s target) and clipped to the presented one, with
/// [borderRadius]. A moving width or height lays out the parent and repaints
/// this widget every frame. Discrete layout changes belong to
/// `MotionLayout`: a width or height changed in the frame's resolve phase
/// asserts.
///
/// Hit testing follows what is drawn, inside the clip. The transform,
/// opacity and blur reach accessibility when the values among them that
/// move come to rest. Under a muted `TickerMode` it stops following its
/// values.
class MotionTransition extends SingleChildRenderObjectWidget {
  /// Creates a transition of [child] driven by the given values.
  const MotionTransition({
    super.key,
    this.offset,
    this.translateX,
    this.translateY,
    this.scale,
    this.scaleX,
    this.scaleY,
    this.rotation,
    this.opacity,
    this.blur,
    this.width,
    this.height,
    this.borderRadius,
    super.child,
  });

  /// The translation of the child.
  final ValueListenable<Offset>? offset;

  /// A horizontal translation added to [offset].
  final ValueListenable<double>? translateX;

  /// A vertical translation added to [offset].
  final ValueListenable<double>? translateY;

  /// A uniform scale about the center.
  final ValueListenable<double>? scale;

  /// A horizontal scale about the center, on top of [scale].
  final ValueListenable<double>? scaleX;

  /// A vertical scale about the center, on top of [scale].
  final ValueListenable<double>? scaleY;

  /// A rotation about the center, in radians.
  final ValueListenable<double>? rotation;

  /// The opacity, from 0 to 1.
  final ValueListenable<double>? opacity;

  /// The blur sigma, in logical pixels.
  final ValueListenable<double>? blur;

  /// The width this widget takes in its parent's layout.
  final ValueListenable<double>? width;

  /// The height this widget takes in its parent's layout.
  final ValueListenable<double>? height;

  /// The corners of the clip, which applies when this is set or when
  /// [width] or [height] size the widget.
  final BorderRadius? borderRadius;

  TransitionInputs get _inputs => TransitionInputs(
    offset: offset,
    translateX: translateX,
    translateY: translateY,
    scale: scale,
    scaleX: scaleX,
    scaleY: scaleY,
    rotation: rotation,
    opacity: opacity,
    blur: blur,
    width: width,
    height: height,
  );

  @override
  RenderMotionTransition createRenderObject(BuildContext context) =>
      RenderMotionTransition(
        inputs: _inputs,
        borderRadius: borderRadius,
        following: TickerMode.valuesOf(context).enabled,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMotionTransition renderObject,
  ) {
    renderObject.inputs = _inputs;
    renderObject.borderRadius = borderRadius;
    renderObject.following = TickerMode.valuesOf(context).enabled;
  }
}

/// The values a [MotionTransition] follows.
@internal
@immutable
final class TransitionInputs {
  /// Collects the values a [MotionTransition] follows.
  const TransitionInputs({
    this.offset,
    this.translateX,
    this.translateY,
    this.scale,
    this.scaleX,
    this.scaleY,
    this.rotation,
    this.opacity,
    this.blur,
    this.width,
    this.height,
  });

  final ValueListenable<Offset>? offset;
  final ValueListenable<double>? translateX;
  final ValueListenable<double>? translateY;
  final ValueListenable<double>? scale;
  final ValueListenable<double>? scaleX;
  final ValueListenable<double>? scaleY;
  final ValueListenable<double>? rotation;
  final ValueListenable<double>? opacity;
  final ValueListenable<double>? blur;
  final ValueListenable<double>? width;
  final ValueListenable<double>? height;

  Iterable<Listenable> get look => <Listenable?>[
    offset,
    translateX,
    translateY,
    scale,
    scaleX,
    scaleY,
    rotation,
    opacity,
    blur,
  ].nonNulls;

  Iterable<Listenable> get size => <Listenable?>[width, height].nonNulls;

  bool get sized => width != null || height != null;

  bool get resting {
    for (final listenable in [...look, ...size]) {
      if (listenable is MotionValue && listenable.value != listenable.target) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is TransitionInputs &&
      identical(other.offset, offset) &&
      identical(other.translateX, translateX) &&
      identical(other.translateY, translateY) &&
      identical(other.scale, scale) &&
      identical(other.scaleX, scaleX) &&
      identical(other.scaleY, scaleY) &&
      identical(other.rotation, rotation) &&
      identical(other.opacity, opacity) &&
      identical(other.blur, blur) &&
      identical(other.width, width) &&
      identical(other.height, height);

  @override
  int get hashCode => Object.hash(
    offset,
    translateX,
    translateY,
    scale,
    scaleX,
    scaleY,
    rotation,
    opacity,
    blur,
    width,
    height,
  );
}

/// The render object of a [MotionTransition].
@internal
class RenderMotionTransition extends RenderProxyBox {
  /// Creates the render object of a [MotionTransition].
  RenderMotionTransition({
    required this._inputs,
    this._borderRadius,
    this._following = true,
  });

  TransitionInputs _inputs;

  /// The values the transition follows.
  TransitionInputs get inputs => _inputs;
  set inputs(TransitionInputs value) {
    if (value == _inputs) return;
    _unfollow();
    _inputs = value;
    _follow();
    markNeedsLayout();
    markNeedsCompositedLayerUpdate();
  }

  BorderRadius? _borderRadius;

  /// The corners of the clip.
  BorderRadius? get borderRadius => _borderRadius;
  set borderRadius(BorderRadius? value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsCompositedLayerUpdate();
  }

  bool _following;

  /// Whether the transition follows its values: false under a muted
  /// `TickerMode`.
  bool get following => _following;
  set following(bool value) {
    if (value == _following) return;
    _unfollow();
    _following = value;
    _follow();
    if (value) {
      markNeedsLayout();
      markNeedsCompositedLayerUpdate();
    }
  }

  bool _followed = false;

  void _follow() {
    if (!attached || !_following || _followed) return;
    _followed = true;
    for (final listenable in _inputs.look) {
      listenForRender(listenable, _lookChanged);
    }
    for (final listenable in _inputs.size) {
      listenForRender(listenable, _sizeChanged);
    }
  }

  void _unfollow() {
    if (!_followed) return;
    _followed = false;
    for (final listenable in _inputs.look) {
      unlistenForRender(listenable, _lookChanged);
    }
    for (final listenable in _inputs.size) {
      unlistenForRender(listenable, _sizeChanged);
    }
  }

  void _lookChanged() {
    markNeedsCompositedLayerUpdate();
    if (_inputs.resting) markNeedsSemanticsUpdate();
  }

  void _sizeChanged() {
    assert(
      !MotionClock.instance.isResolving,
      'A MotionTransition width or height changed in the resolve phase, '
      'after layout: discrete layout changes belong to MotionLayout.',
    );
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow();
  }

  @override
  void detach() {
    _unfollow();
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  static double? _model(ValueListenable<double>? listenable) =>
      switch (listenable) {
        null => null,
        final MotionValue<double> value => value.target,
        _ => listenable.value,
      };

  @override
  void performLayout() {
    if (!_inputs.sized) {
      super.performLayout();
      return;
    }
    final child = this.child;
    var laidOut = Size.zero;
    if (child != null) {
      child.layout(
        constraints.tighten(
          width: _model(_inputs.width),
          height: _model(_inputs.height),
        ),
        parentUsesSize: true,
      );
      laidOut = child.size;
    }
    size = constraints.constrain(
      Size(
        _inputs.width?.value ?? laidOut.width,
        _inputs.height?.value ?? laidOut.height,
      ),
    );
    markNeedsCompositedLayerUpdate();
  }

  /// The move, scale and rotation of the child, or null at identity.
  Matrix4? get _transform {
    final offset = (_inputs.offset?.value ?? Offset.zero).translate(
      _inputs.translateX?.value ?? 0,
      _inputs.translateY?.value ?? 0,
    );
    final scale = _inputs.scale?.value ?? 1;
    final scaleX = scale * (_inputs.scaleX?.value ?? 1);
    final scaleY = scale * (_inputs.scaleY?.value ?? 1);
    final rotation = _inputs.rotation?.value ?? 0;
    if (offset == Offset.zero && scaleX == 1 && scaleY == 1 && rotation == 0) {
      return null;
    }
    final center = size.center(Offset.zero);
    final transform = Matrix4.translationValues(
      offset.dx + center.dx,
      offset.dy + center.dy,
      0,
    );
    if (rotation != 0) transform.rotateZ(rotation);
    transform.scaleByDouble(scaleX, scaleY, 1, 1);
    transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    return transform;
  }

  RRect? get _clip {
    final radius = _borderRadius;
    if (radius == null && !_inputs.sized) return null;
    return (radius ?? BorderRadius.zero).toRRect(Offset.zero & size);
  }

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    final opacity = (_inputs.opacity?.value ?? 1).clamp(0.0, 1.0);
    final alpha = (opacity * 255).round();
    layer.update(
      transform: _transform,
      clip: _clip,
      alpha: alpha == 255 ? null : alpha,
      blur: math.max(0, _inputs.blur?.value ?? 0),
    );
    return layer;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_transform case final move?) transform.multiply(move);
  }

  // As RenderTransform does, a moved child is hit where it is drawn, not
  // within this box's own untransformed size.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_transform == null) return super.hitTest(result, position: position);
    return hitTestChildren(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    bool inside(BoxHitTestResult result, Offset position) {
      final clip = _clip;
      if (clip != null && !clip.contains(position)) return false;
      return super.hitTestChildren(result, position: position);
    }

    final move = _transform;
    if (move == null) return inside(result, position);
    return result.addWithPaintTransform(
      transform: move,
      position: position,
      hitTest: inside,
    );
  }
}

/// The composited layer of a [MotionTransition] or a `MotionLayout` child:
/// one layer that adds a transform, a clip, an opacity and a blur to the
/// scene, each only while it is not identity, and keeps each engine layer
/// for retained rendering.
@internal
class MotionTransitionLayer extends OffsetLayer {
  Matrix4? _transform;
  RRect? _clip;
  int? _alpha;
  double _blur = 0;

  ui.ClipRRectEngineLayer? _clipLayer;
  ui.OpacityEngineLayer? _opacityLayer;
  ui.ImageFilterEngineLayer? _blurLayer;

  /// Whether the layer adds an opacity: only while it is not 1.
  @visibleForTesting
  bool get addsOpacity => _alpha != null;

  /// Whether the layer adds a transform beyond its offset.
  @visibleForTesting
  bool get addsTransform => _transform != null;

  /// Sets what the layer adds, marking it to be added again on a change.
  void update({
    required Matrix4? transform,
    required RRect? clip,
    required int? alpha,
    required double blur,
  }) {
    if (MatrixUtils.matrixEquals(transform, _transform) &&
        clip == _clip &&
        alpha == _alpha &&
        blur == _blur) {
      return;
    }
    _transform = transform;
    _clip = clip;
    _alpha = alpha;
    _blur = blur;
    markNeedsAddToScene();
  }

  Matrix4 get _total {
    final total = Matrix4.translationValues(offset.dx, offset.dy, 0);
    final transform = _transform;
    if (transform != null) total.multiply(transform);
    return total;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    var pushed = 1;
    if (_transform == null) {
      final old = engineLayer;
      engineLayer = builder.pushOffset(
        offset.dx,
        offset.dy,
        oldLayer: old is ui.OffsetEngineLayer ? old : null,
      );
    } else {
      final old = engineLayer;
      engineLayer = builder.pushTransform(
        _total.storage,
        oldLayer: old is ui.TransformEngineLayer ? old : null,
      );
    }
    final clip = _clip;
    _clipLayer = clip == null
        ? _drop(_clipLayer)
        : _keep(
            _clipLayer,
            builder.pushClipRRect(clip, oldLayer: _clipLayer),
          );
    if (clip != null) pushed++;
    final alpha = _alpha;
    _opacityLayer = alpha == null
        ? _drop(_opacityLayer)
        : _keep(
            _opacityLayer,
            builder.pushOpacity(alpha, oldLayer: _opacityLayer),
          );
    if (alpha != null) pushed++;
    if (_blur > 0) {
      _blurLayer = _keep(
        _blurLayer,
        builder.pushImageFilter(
          ui.ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          oldLayer: _blurLayer,
        ),
      );
      pushed++;
    } else {
      _blurLayer = _drop(_blurLayer);
    }
    addChildrenToScene(builder);
    for (var i = 0; i < pushed; i++) {
      builder.pop();
    }
  }

  static T _keep<T extends ui.EngineLayer>(T? old, T next) {
    if (!identical(old, next)) old?.dispose();
    return next;
  }

  static T? _drop<T extends ui.EngineLayer>(T? old) {
    old?.dispose();
    return null;
  }

  @override
  bool findAnnotations<S extends Object>(
    AnnotationResult<S> result,
    Offset localPosition, {
    required bool onlyFirst,
  }) {
    final inverse = Matrix4.tryInvert(_total);
    if (inverse == null) return false;
    final inside = MatrixUtils.transformPoint(inverse, localPosition);
    return super.findAnnotations(
      result,
      inside + offset,
      onlyFirst: onlyFirst,
    );
  }

  @override
  void applyTransform(Layer? child, Matrix4 transform) {
    transform.multiply(_total);
  }

  @override
  void dispose() {
    _clipLayer = _drop(_clipLayer);
    _opacityLayer = _drop(_opacityLayer);
    _blurLayer = _drop(_blurLayer);
    super.dispose();
  }
}
