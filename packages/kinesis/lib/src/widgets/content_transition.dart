import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// Visual style of a [MotionContentTransition] when its child's identity
/// changes (matching SwiftUI's `ContentTransition` / UIKit's
/// `UIView.transition`).
@immutable
sealed class ContentTransition {
  /// Creates a content transition.
  const ContentTransition();

  /// Cross-dissolve fade between outgoing and incoming children.
  const factory ContentTransition.fade() = _FadeContentTransition;

  /// SwiftUI `.blurReplace`: outgoing content fades, blurs up to [maxBlur]
  /// sigma, and gently scales to [minScale] while incoming content sharpens
  /// and scales in (`[approx]` default parameters).
  const factory ContentTransition.blurReplace({
    double maxBlur,
    double minScale,
  }) = _BlurReplaceContentTransition;

  /// Scale and cross-fade about [alignment].
  const factory ContentTransition.scale({
    double scale,
    AlignmentGeometry alignment,
  }) = _ScaleContentTransition;

  /// Directional slide and cross-fade by [offset].
  const factory ContentTransition.slide({Offset offset}) =
      _SlideContentTransition;

  /// How a child looks at transition progress [p], arriving when [incoming]
  /// and leaving otherwise.
  _Look _lookAt(double p, {required bool incoming});

  /// The point the children scale about.
  AlignmentGeometry get _pivot => Alignment.center;
}

typedef _Look = ({double opacity, double scale, double blur, Offset offset});

_Look _faded(double p, {required bool incoming}) => (
  opacity: incoming ? p.clamp(0.0, 1.0) : (1 - p).clamp(0.0, 1.0),
  scale: 1,
  blur: 0,
  offset: Offset.zero,
);

final class _FadeContentTransition extends ContentTransition {
  const _FadeContentTransition();

  @override
  _Look _lookAt(double p, {required bool incoming}) =>
      _faded(p, incoming: incoming);

  @override
  bool operator ==(Object other) => other is _FadeContentTransition;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ContentTransition.fade()';
}

final class _BlurReplaceContentTransition extends ContentTransition {
  const _BlurReplaceContentTransition({
    this.maxBlur = 6,
    this.minScale = 0.92,
  });

  final double maxBlur;
  final double minScale;

  @override
  _Look _lookAt(double p, {required bool incoming}) {
    final faded = _faded(p, incoming: incoming);
    final shown = p.clamp(0.0, 1.0);
    return (
      opacity: faded.opacity,
      scale: incoming ? minScale + (1 - minScale) * p : 1 - (1 - minScale) * p,
      blur: (incoming ? 1 - shown : shown) * maxBlur,
      offset: Offset.zero,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _BlurReplaceContentTransition &&
      other.maxBlur == maxBlur &&
      other.minScale == minScale;

  @override
  int get hashCode => Object.hash(maxBlur, minScale);

  @override
  String toString() =>
      'ContentTransition.blurReplace(maxBlur: $maxBlur, minScale: $minScale)';
}

final class _ScaleContentTransition extends ContentTransition {
  const _ScaleContentTransition({
    this.scale = 0.85,
    this.alignment = Alignment.center,
  });

  final double scale;
  final AlignmentGeometry alignment;

  @override
  AlignmentGeometry get _pivot => alignment;

  @override
  _Look _lookAt(double p, {required bool incoming}) => (
    opacity: _faded(p, incoming: incoming).opacity,
    scale: incoming ? scale + (1 - scale) * p : 1 - (1 - scale) * p,
    blur: 0,
    offset: Offset.zero,
  );

  @override
  bool operator ==(Object other) =>
      other is _ScaleContentTransition &&
      other.scale == scale &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(scale, alignment);

  @override
  String toString() =>
      'ContentTransition.scale(scale: $scale, alignment: $alignment)';
}

final class _SlideContentTransition extends ContentTransition {
  const _SlideContentTransition({this.offset = const Offset(0, 12)});

  final Offset offset;

  @override
  _Look _lookAt(double p, {required bool incoming}) => (
    opacity: _faded(p, incoming: incoming).opacity,
    scale: 1,
    blur: 0,
    offset: incoming ? offset * (1 - p) : -offset * p,
  );

  @override
  bool operator ==(Object other) =>
      other is _SlideContentTransition && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;

  @override
  String toString() => 'ContentTransition.slide(offset: $offset)';
}

/// Transitions smoothly whenever [child] changes identity (`Widget.canUpdate`
/// returns false, e.g. different `ValueKey`s), driving composited
/// `MotionTransition` layers on `MotionClock` with zero per-frame widget
/// rebuilds.
///
/// Each child keeps its `State` from when it arrives until it has left, and
/// lays out under the constraints this widget gets, during a transition as
/// at rest.
///
/// Under Reduce Motion (`MotionTraits.reduceMotion`), falls back to
/// [ContentTransition.fade] automatically.
class MotionContentTransition extends StatefulWidget {
  /// Creates a content transition host.
  const MotionContentTransition({
    required this.child,
    this.transition = const ContentTransition.blurReplace(),
    this.animation = defaultAnimation,
    this.alignment = Alignment.center,
    super.key,
  });

  /// `[approx]` Default spring for content transitions.
  static const MotionAnimation defaultAnimation = Spring.response(
    0.32,
    dampingRatio: 0.92,
  );

  /// The active child widget. Give distinct keys to trigger transitions.
  final Widget child;

  /// The visual style of the transition.
  final ContentTransition transition;

  /// The [Spring] or [TimingCurve] driving the transition.
  final MotionAnimation animation;

  /// Alignment of outgoing and incoming children inside the stack.
  final AlignmentGeometry alignment;

  @override
  State<MotionContentTransition> createState() =>
      _MotionContentTransitionState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<ContentTransition>('transition', transition))
      ..add(DiagnosticsProperty<MotionAnimation>('animation', animation))
      ..add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
  }
}

class _MotionContentTransitionState extends State<MotionContentTransition> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _progress = MotionValue<double>(
    1,
    restDistance: MotionRest.opacity,
    clock: _clock,
  );
  late Widget _current = widget.child;
  int _currentEntry = 0;
  Widget? _outgoing;
  bool _reduceMotion = false;

  ContentTransition get _effectiveTransition =>
      _reduceMotion ? const ContentTransition.fade() : widget.transition;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_onProgress);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MotionTraitsOverride.of(context).reduceMotion;
  }

  @override
  void didUpdateWidget(MotionContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!Widget.canUpdate(_current, widget.child)) {
      _outgoing = _current;
      _current = widget.child;
      _currentEntry++;
      final t = _clock.now;
      _progress.snap(t, 0);
      _progress.animate(
        t,
        1,
        animation: widget.animation.resolve(reduceMotion: _reduceMotion),
      );
    } else {
      _current = widget.child;
    }
  }

  void _onProgress() {
    if (_outgoing != null && _progress.restsAt(_clock.now)) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void dispose() {
    _progress.removeListener(_onProgress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transition = _effectiveTransition;
    final outgoing = _outgoing;
    return Stack(
      alignment: widget.alignment,
      fit: StackFit.passthrough,
      children: [
        if (outgoing != null)
          _ContentSlot(
            key: ValueKey<int>(_currentEntry - 1),
            role: _ContentRole.outgoing,
            progress: _progress,
            transition: transition,
            child: outgoing,
          ),
        _ContentSlot(
          key: ValueKey<int>(_currentEntry),
          role: outgoing == null ? _ContentRole.resting : _ContentRole.incoming,
          progress: _progress,
          transition: transition,
          child: _current,
        ),
      ],
    );
  }
}

enum _ContentRole { resting, incoming, outgoing }

/// One child of a [MotionContentTransition], the same widget whether it
/// rests, arrives or leaves, so its element and `State` live on as its role
/// changes.
class _ContentSlot extends SingleChildRenderObjectWidget {
  const _ContentSlot({
    required this.role,
    required this.progress,
    required this.transition,
    super.key,
    super.child,
  });

  final _ContentRole role;
  final MotionValue<double> progress;
  final ContentTransition transition;

  @override
  _RenderContentSlot createRenderObject(BuildContext context) =>
      _RenderContentSlot(
        role: role,
        progress: progress,
        transition: transition,
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderContentSlot renderObject,
  ) {
    renderObject
      ..role = role
      ..progress = progress
      ..transition = transition
      ..textDirection = Directionality.maybeOf(context);
  }
}

/// Paints a resting child as it is, with no layer of its own. While the
/// child arrives or leaves it becomes a repaint boundary, as
/// `FadeTransition`'s render object does while it fades, and each frame
/// updates only its composited layer; a leaving child takes no hits and
/// has no semantics.
class _RenderContentSlot extends RenderProxyBox {
  _RenderContentSlot({
    required this._role,
    required this._progress,
    required this._transition,
    required this._textDirection,
  });

  _ContentRole _role;
  _ContentRole get role => _role;
  set role(_ContentRole value) {
    if (value == _role) return;
    final wasMoving = _moving;
    _role = value;
    if (child != null && wasMoving != _moving) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsCompositedLayerUpdate();
    markNeedsSemanticsUpdate();
  }

  MotionValue<double> _progress;
  MotionValue<double> get progress => _progress;
  set progress(MotionValue<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeRenderListener(_progressChanged);
    _progress = value;
    if (attached) _progress.addRenderListener(_progressChanged);
    markNeedsCompositedLayerUpdate();
  }

  ContentTransition _transition;
  ContentTransition get transition => _transition;
  set transition(ContentTransition value) {
    if (value == _transition) return;
    _transition = value;
    markNeedsCompositedLayerUpdate();
  }

  TextDirection? _textDirection;
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsCompositedLayerUpdate();
  }

  bool get _moving => _role != _ContentRole.resting;

  void _progressChanged() {
    if (_moving) markNeedsCompositedLayerUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addRenderListener(_progressChanged);
  }

  @override
  void detach() {
    _progress.removeRenderListener(_progressChanged);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => child != null && _moving;

  _Look get _look => _transition._lookAt(
    _progress.value,
    incoming: _role == _ContentRole.incoming,
  );

  Matrix4? get _transform {
    if (!_moving) return null;
    final look = _look;
    if (look.offset == Offset.zero && look.scale == 1) return null;
    final pivot = _transition._pivot.resolve(_textDirection).alongSize(size);
    return Matrix4.translationValues(
        look.offset.dx + pivot.dx,
        look.offset.dy + pivot.dy,
        0,
      )
      ..scaleByDouble(look.scale, look.scale, 1, 1)
      ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
  }

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    final look = _look;
    final alpha = (look.opacity * 255).round();
    layer.update(
      transform: _transform,
      clip: null,
      alpha: alpha == 255 ? null : alpha,
      blur: look.blur,
    );
    return layer;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_transform case final move?) transform.multiply(move);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_role == _ContentRole.outgoing) return false;
    if (_transform == null) return super.hitTest(result, position: position);
    return hitTestChildren(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final move = _transform;
    if (move == null) {
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: move,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_role != _ContentRole.outgoing) {
      super.visitChildrenForSemantics(visitor);
    }
  }
}
