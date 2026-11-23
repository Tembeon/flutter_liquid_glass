import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/selection.dart' show settledNow;
import 'package:kinesis/src/widgets/follow.dart';
import 'package:kinesis/src/widgets/input_zone.dart';

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
/// rotation pivot on [alignment].
///
/// [pose] carries a whole look in one value, such as a
/// `SymbolEffectMotion`'s, and adds to the single values: moves and turns
/// add, scales and opacities multiply, blurs combine.
///
/// [width] and [height] take part in the parent's layout at their presented
/// value, so siblings follow them; the child is laid out at the model size
/// (a `MotionValue`'s target) and clipped to the presented one, with
/// [borderRadius]. A moving width or height lays out the parent and repaints
/// this widget every frame. Discrete layout changes belong to
/// `MotionLayout`.
///
/// Hit testing follows what is drawn, inside the clip. The transform,
/// opacity and blur reach accessibility when the values among them that
/// move come to rest. As with `FadeTransition`'s render object, a child
/// whose presented opacity rounds to 0 is left out of semantics, without a
/// build; below input's opacity threshold
/// (`InputZoneFrame.minimumOpacity`) it takes no hits. Under a muted
/// `TickerMode` it stops following its values.
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
    this.alignment = Alignment.center,
    this.opacity,
    this.blur,
    this.pose,
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

  /// A uniform scale about [alignment].
  final ValueListenable<double>? scale;

  /// A horizontal scale about [alignment], on top of [scale].
  final ValueListenable<double>? scaleX;

  /// A vertical scale about [alignment], on top of [scale].
  final ValueListenable<double>? scaleY;

  /// A rotation about [alignment], in radians.
  final ValueListenable<double>? rotation;

  /// The pivot point for [scale], [scaleX], [scaleY], and [rotation].
  final AlignmentGeometry alignment;

  /// The opacity, from 0 to 1.
  final ValueListenable<double>? opacity;

  /// The blur sigma, in logical pixels.
  final ValueListenable<double>? blur;

  /// A whole look, worn on top of the single values; its pivot is
  /// [alignment] and its `offsetFraction` is of this widget's size.
  final ValueListenable<MotionPose>? pose;

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
    pose: pose,
    width: width,
    height: height,
  );

  @override
  RenderMotionTransition createRenderObject(BuildContext context) =>
      RenderMotionTransition(
        inputs: _inputs,
        alignment: alignment,
        textDirection: Directionality.maybeOf(context),
        borderRadius: borderRadius,
        following: followsMotion(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMotionTransition renderObject,
  ) {
    renderObject.inputs = _inputs;
    renderObject.alignment = alignment;
    renderObject.textDirection = Directionality.maybeOf(context);
    renderObject.borderRadius = borderRadius;
    renderObject.following = followsMotion(context);
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
    this.pose,
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
  final ValueListenable<MotionPose>? pose;
  final ValueListenable<double>? width;
  final ValueListenable<double>? height;

  List<Listenable> get look => [
    ?offset,
    ?translateX,
    ?translateY,
    ?scale,
    ?scaleX,
    ?scaleY,
    ?rotation,
    ?opacity,
    ?blur,
    ?pose,
  ];

  List<Listenable> get size => [?width, ?height];

  bool get sized => width != null || height != null;

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
      identical(other.pose, pose) &&
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
    pose,
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
    this._alignment = Alignment.center,
    this._textDirection,
    this._borderRadius,
    bool following = true,
  }) : _follow = MotionFollow.render(following: following) {
    _hear();
    _wasTransparent = _transparent;
  }

  AlignmentGeometry _alignment;

  /// The pivot point for scale and rotation.
  AlignmentGeometry get alignment => _alignment;
  set alignment(AlignmentGeometry value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsCompositedLayerUpdate();
  }

  TextDirection? _textDirection;

  /// The text direction used to resolve directional [alignment].
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsCompositedLayerUpdate();
  }

  TransitionInputs _inputs;
  late List<Listenable> _look;
  late List<Listenable> _size;

  void _hear() {
    _look = _inputs.look;
    _size = _inputs.size;
    _follow.hear([
      for (final listenable in _look) (listenable, _lookChanged),
      for (final listenable in _size) (listenable, _sizeChanged),
    ]);
  }

  /// The values the transition follows.
  TransitionInputs get inputs => _inputs;
  set inputs(TransitionInputs value) {
    if (value == _inputs) return;
    _inputs = value;
    _hear();
    markNeedsLayout();
    markNeedsCompositedLayerUpdate();
    _syncTransparency();
  }

  BorderRadius? _borderRadius;

  /// The corners of the clip.
  BorderRadius? get borderRadius => _borderRadius;
  set borderRadius(BorderRadius? value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsCompositedLayerUpdate();
  }

  final MotionFollow _follow;

  /// Whether the transition follows its values ([followsMotion]).
  bool get following => _follow.following;
  set following(bool value) => _follow.following = value;

  bool _wasTransparent = false;

  bool get _transparent => ui.Color.getAlphaFromOpacity(_opacity) == 0;

  MotionPose get _pose => _inputs.pose?.value ?? MotionPose.identity;

  double get _opacity => (_inputs.opacity?.value ?? 1) * _pose.opacity;

  void _syncTransparency() {
    _wasTransparent = _transparent;
    markNeedsSemanticsUpdate();
  }

  void _lookChanged() {
    markNeedsCompositedLayerUpdate();
    final transparent = _transparent;
    if (transparent != _wasTransparent ||
        (_look.every(settledNow) && _size.every(settledNow))) {
      _wasTransparent = transparent;
      markNeedsSemanticsUpdate();
    }
  }

  void _sizeChanged() => markNeedsLayout();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow.attach();
  }

  @override
  void detach() {
    _follow.detach();
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_transparent) super.visitChildrenForSemantics(visitor);
  }

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
  Matrix4? get _transform => poseTransform(
    _pose,
    size,
    pivot: _alignment,
    textDirection: _textDirection,
    shift: (_inputs.offset?.value ?? Offset.zero).translate(
      _inputs.translateX?.value ?? 0,
      _inputs.translateY?.value ?? 0,
    ),
    scale: _inputs.scale?.value ?? 1,
    scaleX: _inputs.scaleX?.value ?? 1,
    scaleY: _inputs.scaleY?.value ?? 1,
    rotation: _inputs.rotation?.value ?? 0,
  );

  RRect? get _clip {
    final radius = _borderRadius;
    if (radius == null && !_inputs.sized) return null;
    return (radius ?? BorderRadius.zero).toRRect(Offset.zero & size);
  }

  double get _blurSigma {
    final own = math.max(0, _inputs.blur?.value ?? 0);
    final worn = _pose.blur;
    return worn == 0 ? own.toDouble() : math.sqrt(own * own + worn * worn);
  }

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    layer.update(
      transform: _transform,
      clip: _clip,
      opacity: _opacity,
      blur: _blurSigma,
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
    if (_opacity < InputZoneFrame.minimumOpacity) return false;
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

/// The transform that wears [pose] on content of [size]: its move plus
/// [shift], its scale times [scale] and then [scaleX] and [scaleY], and its
/// turn plus [rotation], about [pivot]; null at identity.
@internal
Matrix4? poseTransform(
  MotionPose pose,
  Size size, {
  AlignmentGeometry pivot = Alignment.center,
  TextDirection? textDirection,
  Offset shift = Offset.zero,
  double scale = 1,
  double scaleX = 1,
  double scaleY = 1,
  double rotation = 0,
}) {
  final offset = shift + pose.offsetFor(size);
  final scaled = scale * pose.scale;
  final x = scaled * scaleX;
  final y = scaled * scaleY;
  final turn = rotation + pose.rotation;
  if (offset == Offset.zero && x == 1 && y == 1 && turn == 0) return null;
  final at = pivot.resolve(textDirection).alongSize(size);
  final transform = Matrix4.translationValues(
    offset.dx + at.dx,
    offset.dy + at.dy,
    0,
  );
  if (turn != 0) transform.rotateZ(turn);
  return transform
    ..scaleByDouble(x, y, 1, 1)
    ..translateByDouble(-at.dx, -at.dy, 0, 1);
}

/// The composited layer of content that wears a look: a [MotionTransition],
/// a `MotionLayout` or `SliverMotionList` child, a `MotionContentTransition`
/// slot:
/// one layer that adds a transform, a clip, an opacity and a blur to the
/// scene, each only while it is not identity, and keeps each engine layer
/// for retained rendering. While fully transparent it adds nothing,
/// children included.
class MotionTransitionLayer extends OffsetLayer {
  Matrix4? _transform;
  RRect? _clip;
  int? _alpha;
  double _blur = 0;

  ui.ClipRRectEngineLayer? _clipLayer;
  ui.OpacityEngineLayer? _opacityLayer;
  ui.ImageFilterEngineLayer? _blurLayer;

  /// Whether the layer adds a transform beyond its offset.
  @visibleForTesting
  bool get addsTransform => _transform != null;

  /// Sets what the layer adds, marking it to be added again on a change.
  ///
  /// The opacity becomes an alpha as `RenderOpacity` turns it into one, so
  /// an opacity that rounds to an alpha of 255 adds no opacity, and one
  /// that rounds to the alpha already added changes nothing.
  void update({
    required Matrix4? transform,
    required RRect? clip,
    required double opacity,
    required double blur,
  }) {
    final rounded = ui.Color.getAlphaFromOpacity(opacity);
    final alpha = rounded == 255 ? null : rounded;
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

  /// The transform the layer adds, its offset included.
  Matrix4 get total {
    final total = Matrix4.translationValues(offset.dx, offset.dy, 0);
    final transform = _transform;
    if (transform != null) total.multiply(transform);
    return total;
  }

  /// The rounded clip the layer adds inside [total], or null.
  RRect? get clip => _clip;

  /// The opacity the layer adds inside the clip, or null.
  int? get alpha => _alpha;

  /// The blur sigma the layer adds innermost; zero adds none.
  double get blur => _blur;

  @override
  void addToScene(ui.SceneBuilder builder) {
    // A transparent subtree shows nothing, as RenderOpacity paints nothing
    // at zero; added, it would still pay for its blur.
    if (_alpha == 0) {
      engineLayer = null;
      _dropEngineLayers();
      return;
    }
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
        total.storage,
        oldLayer: old is ui.TransformEngineLayer ? old : null,
      );
    }
    final clip = _clip;
    _clipLayer = clip == null
        ? _drop(_clipLayer)
        : _keep(
            _clipLayer,
            builder.pushClipRRect(
              clip,
              clipBehavior: _roundedClip,
              oldLayer: _clipLayer,
            ),
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

  void _dropEngineLayers() {
    _clipLayer = _drop(_clipLayer);
    _opacityLayer = _drop(_opacityLayer);
    _blurLayer = _drop(_blurLayer);
  }

  @override
  bool findAnnotations<S extends Object>(
    AnnotationResult<S> result,
    Offset localPosition, {
    required bool onlyFirst,
  }) {
    final inverse = Matrix4.tryInvert(total);
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
    transform.multiply(total);
  }

  @override
  void dispose() {
    _dropEngineLayers();
    super.dispose();
  }
}

// The native scene builder's default. The web's has none and requires the
// argument, and a constant equal to the native default is reported as
// redundant, so it is not one.
Clip get _roundedClip => Clip.antiAlias;
