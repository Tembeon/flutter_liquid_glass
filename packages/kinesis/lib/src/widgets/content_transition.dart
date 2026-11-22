import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// How content of a [MotionContentTransition] looks while it comes in or
/// goes out.
///
/// SwiftUI: a `ContentTransition` or a view `Transition`. Subclass it for a
/// look of your own: [poseAt] answers a [MotionPose] for any progress, and
/// the content wears it about [alignment] on its own composited layer.
@immutable
abstract class ContentTransition {
  /// Allows subclasses to have const constructors.
  const ContentTransition();

  /// Cross-fade: SwiftUI `.opacity`.
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

  /// The pose of content [progress] of the way in when [incoming], or of
  /// the way out otherwise.
  ///
  /// Its `offsetFraction` is of the content's own size. The pose at
  /// progress 1 coming in and at progress 0 going out should be identity,
  /// which is how the content shows at rest.
  MotionPose poseAt(double progress, {required bool incoming});

  /// The point content scales and turns about.
  AlignmentGeometry get alignment => Alignment.center;
}

double _shown(double progress, {required bool incoming}) {
  final p = progress.clamp(0.0, 1.0);
  return incoming ? p : 1 - p;
}

final class _FadeContentTransition extends ContentTransition {
  const _FadeContentTransition();

  @override
  MotionPose poseAt(double progress, {required bool incoming}) =>
      MotionPose(opacity: _shown(progress, incoming: incoming));

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
  MotionPose poseAt(double progress, {required bool incoming}) {
    final shown = _shown(progress, incoming: incoming);
    final away = incoming ? 1 - progress : progress;
    return MotionPose(
      opacity: shown,
      scale: 1 - (1 - minScale) * away,
      blur: (1 - shown) * maxBlur,
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

  @override
  final AlignmentGeometry alignment;

  @override
  MotionPose poseAt(double progress, {required bool incoming}) {
    final away = incoming ? 1 - progress : progress;
    return MotionPose(
      opacity: _shown(progress, incoming: incoming),
      scale: 1 - (1 - scale) * away,
    );
  }

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
  MotionPose poseAt(double progress, {required bool incoming}) => MotionPose(
    opacity: _shown(progress, incoming: incoming),
    offset: incoming ? offset * (1 - progress) : -offset * progress,
  );

  @override
  bool operator ==(Object other) =>
      other is _SlideContentTransition && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;

  @override
  String toString() => 'ContentTransition.slide(offset: $offset)';
}

/// Transitions whenever [child] changes identity (`Widget.canUpdate` is
/// false, as with different `ValueKey`s): the old child leaves and the new
/// one arrives through [transition], each on a composited layer of its own,
/// with no rebuild per frame.
///
/// The size slides from the leaving child's to the arriving one's on the
/// same [animation], so what sits around this widget moves rather than
/// jumps. A change during a change carries on from what shows: a child
/// still arriving keeps arriving while it leaves. At most
/// [maxChanges] changes run at once; a further one ends the oldest.
///
/// Each child keeps its `State` from when it arrives until it has left, and
/// lays out under the constraints this widget gets. A leaving child takes
/// no hits and has no semantics. A child that comes back while it still
/// leaves arrives anew beside the leaving one, as in SwiftUI; one with a
/// `GlobalKey` takes the leaving one's place instead, `State` and all.
///
/// Under Reduce Motion (`MotionTraits.reduceMotion`) it cross-fades
/// ([ContentTransition.fade]).
class MotionContentTransition extends StatefulWidget {
  /// Creates a content transition host.
  const MotionContentTransition({
    required this.child,
    this.transition = const ContentTransition.blurReplace(),
    this.animation = defaultAnimation,
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.none,
    super.key,
  });

  /// `[approx]` Default spring for content transitions.
  static const MotionAnimation defaultAnimation = Spring.response(
    0.32,
    dampingRatio: 0.92,
  );

  /// How many changes may run at once.
  static const int maxChanges = 3;

  /// The current child. Give distinct keys to trigger transitions.
  final Widget child;

  /// How children come and go.
  final ContentTransition transition;

  /// The [Spring] or [TimingCurve] a change runs on.
  final MotionAnimation animation;

  /// Where children sit in this widget's sliding size.
  final AlignmentGeometry alignment;

  /// Whether children are clipped to this widget's size.
  final Clip clipBehavior;

  @override
  State<MotionContentTransition> createState() =>
      _MotionContentTransitionState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<ContentTransition>('transition', transition))
      ..add(DiagnosticsProperty<MotionAnimation>('animation', animation))
      ..add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment))
      ..add(EnumProperty<Clip>('clipBehavior', clipBehavior));
  }
}

final class _Entry {
  _Entry(this.key, this.child, {this.arrival});

  final int key;
  Widget child;
  MotionValue<double>? arrival;
  MotionValue<double>? departure;
}

class _MotionContentTransitionState extends State<MotionContentTransition> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final _Changes _changes = _Changes(clock: _clock);
  late final MotionSelection<int> _retired = _changes.select(
    (changes) => changes.retired,
  );
  late final MotionSelection<List<double>> _progress = _changes.select(
    (changes) => changes.progress,
    equals: listEquals,
  );
  late final List<_Entry> _entries = [_Entry(0, widget.child)];
  int _keys = 1;
  bool _reduceMotion = false;

  ContentTransition get _transition =>
      _reduceMotion ? const ContentTransition.fade() : widget.transition;

  @override
  void initState() {
    super.initState();
    _retired.addListener(_prune);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MotionTraitsOverride.of(context).reduceMotion;
  }

  @override
  void didUpdateWidget(MotionContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _entries.last;
    if (Widget.canUpdate(current.child, widget.child)) {
      current.child = widget.child;
      return;
    }
    final change = _changes.start(
      _clock.now,
      widget.animation.resolve(reduceMotion: _reduceMotion),
    );
    current.departure = change;
    if (widget.child.key case final GlobalKey key) {
      _entries.removeWhere((entry) => entry.child.key == key);
    }
    _entries.add(_Entry(_keys++, widget.child, arrival: change));
    _forgetRetired();
  }

  void _prune() => setState(_forgetRetired);

  void _forgetRetired() {
    _entries.removeWhere(
      (entry) => entry.departure != null && !_changes.runs(entry.departure!),
    );
    for (final entry in _entries) {
      if (entry.arrival case final arrival? when !_changes.runs(arrival)) {
        entry.arrival = null;
      }
    }
  }

  @override
  void dispose() {
    _retired.removeListener(_prune);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transition = _transition;
    return _ContentHost(
      alignment: widget.alignment,
      clipBehavior: widget.clipBehavior,
      progress: _progress,
      children: [
        for (final entry in _entries)
          _ContentSlot(
            key: ValueKey<int>(entry.key),
            arrival: entry.arrival,
            departure: entry.departure,
            transition: transition,
            child: entry.child,
          ),
      ],
    );
  }
}

// The changes of one MotionContentTransition, each a progress of its own;
// a change retires once its progress rests.
final class _Changes extends Motion {
  _Changes({super.clock});

  final List<MotionValue<double>> _running = [];
  int _retired = 0;

  int get retired => _retired;

  List<double> get progress => [
    for (final change in _running) change.valueAt(now),
  ];

  bool runs(MotionValue<double> change) => _running.contains(change);

  MotionValue<double> start(double t, MotionAnimation animation) {
    advance(t);
    if (_running.length >= MotionContentTransition.maxChanges) {
      final oldest = _running.first..snap(t, 1);
      _retire(oldest);
    }
    final change = own(
      MotionValue<double>(0, restDistance: MotionRest.opacity),
      rest: () => MotionRest.opacity,
    );
    _running.add(change);
    change.animate(t, 1, animation: animation);
    return change;
  }

  @override
  void didAdvance(double t) {
    for (final change in List<MotionValue<double>>.of(_running)) {
      if (change.restsAt(t, MotionRest.opacity)) _retire(change);
    }
  }

  void _retire(MotionValue<double> change) {
    _running.remove(change);
    disown(change);
    _retired++;
    changed();
  }
}

class _ContentHost extends MultiChildRenderObjectWidget {
  const _ContentHost({
    required this.alignment,
    required this.clipBehavior,
    required this.progress,
    super.children,
  });

  final AlignmentGeometry alignment;
  final Clip clipBehavior;
  final ValueListenable<List<double>> progress;

  @override
  _RenderContentHost createRenderObject(BuildContext context) =>
      _RenderContentHost(
        alignment: alignment,
        textDirection: Directionality.maybeOf(context),
        clipBehavior: clipBehavior,
        progress: progress,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderContentHost renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context)
      ..clipBehavior = clipBehavior
      ..progress = progress;
  }
}

class _ContentHostParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays every child out under its own constraints and takes the size of
/// the children blended by how far each has arrived and not yet left, so
/// the size slides through a change; children sit at [alignment]. While
/// the children differ in what it laid out or measured, it lays out again
/// on every frame of a change, so a parent that measures it by intrinsics
/// measures again; only then.
class _RenderContentHost extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ContentHostParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ContentHostParentData> {
  _RenderContentHost({
    required this._alignment,
    required this._textDirection,
    required this._clipBehavior,
    required this._progress,
  });

  AlignmentGeometry _alignment;
  AlignmentGeometry get alignment => _alignment;
  set alignment(AlignmentGeometry value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  TextDirection? _textDirection;
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  Clip _clipBehavior;
  Clip get clipBehavior => _clipBehavior;
  set clipBehavior(Clip value) {
    if (value == _clipBehavior) return;
    _clipBehavior = value;
    markNeedsPaint();
  }

  ValueListenable<List<double>> _progress;
  ValueListenable<List<double>> get progress => _progress;
  set progress(ValueListenable<List<double>> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeRenderListener(_progressed);
    _progress = value;
    if (attached) _progress.addRenderListener(_progressed);
  }

  // Set by a layout or a measure that blended children of different
  // extents, cleared by the next frame of a change: only such a blend
  // moves with the progress.
  bool _blendsDiffer = false;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle();

  void _progressed() {
    if (!_blendsDiffer) return;
    _blendsDiffer = false;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addRenderListener(_progressed);
  }

  @override
  void detach() {
    _progress.removeRenderListener(_progressed);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ContentHostParentData) {
      child.parentData = _ContentHostParentData();
    }
  }

  static double _weightOf(RenderBox child) {
    if (child is! _RenderContentSlot) return 1;
    final arrived = child.arrival?.value ?? 1;
    final left = child.departure?.value ?? 0;
    return arrived * (1 - left);
  }

  Size _blend(Size Function(RenderBox child) sizeOf) {
    var width = 0.0;
    var height = 0.0;
    var weights = 0.0;
    Size? last;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final size = sizeOf(child);
      if (last != null && size != last) _blendsDiffer = true;
      final weight = _weightOf(child);
      width += size.width * weight;
      height += size.height * weight;
      weights += weight;
      last = size;
    }
    if (last == null) return Size.zero;
    if (weights.abs() < 1e-6) return last;
    return Size(width / weights, height / weights);
  }

  double _blendExtent(double Function(RenderBox child) extentOf) {
    var extent = 0.0;
    var weights = 0.0;
    double? last;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final weight = _weightOf(child);
      final value = extentOf(child);
      if (last != null && value != last) _blendsDiffer = true;
      last = value;
      extent += value * weight;
      weights += weight;
    }
    if (last == null) return 0;
    if (weights.abs() < 1e-6) return last;
    return extent / weights;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _blendExtent((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _blendExtent((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _blendExtent((child) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _blendExtent((child) => child.getMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(
        _blend((child) => child.getDryLayout(constraints)),
      );

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final current = lastChild;
    if (current == null) return null;
    final distance = current.getDryBaseline(constraints, baseline);
    if (distance == null) return null;
    final size = getDryLayout(constraints);
    final offset = _alignment
        .resolve(_textDirection)
        .alongOffset(size - current.getDryLayout(constraints) as Offset);
    return distance + offset.dy;
  }

  @override
  void performLayout() {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(constraints, parentUsesSize: true);
    }
    size = constraints.constrain(_blend((child) => child.size));
    final alignment = _alignment.resolve(_textDirection);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      (child.parentData! as _ContentHostParentData).offset = alignment
          .alongOffset(size - child.size as Offset);
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final current = lastChild;
    if (current == null) return null;
    final offset = (current.parentData! as _ContentHostParentData).offset;
    final distance = current.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance + offset.dy;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  bool get _overflows {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final offset = (child.parentData! as _ContentHostParentData).offset;
      if (offset.dx < 0 ||
          offset.dy < 0 ||
          offset.dx + child.size.width > size.width ||
          offset.dy + child.size.height > size.height) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_clipBehavior == Clip.none || !_overflows) {
      _clip.layer = null;
      defaultPaint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      defaultPaint,
      clipBehavior: _clipBehavior,
      oldLayer: _clip.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _clipBehavior != Clip.none && _overflows ? Offset.zero & size : null;
}

/// One child of a [MotionContentTransition], the same widget whether it
/// rests, arrives or leaves, so its element and `State` live on as it
/// changes role.
class _ContentSlot extends SingleChildRenderObjectWidget {
  const _ContentSlot({
    required this.arrival,
    required this.departure,
    required this.transition,
    super.key,
    super.child,
  });

  final ValueListenable<double>? arrival;
  final ValueListenable<double>? departure;
  final ContentTransition transition;

  @override
  _RenderContentSlot createRenderObject(BuildContext context) =>
      _RenderContentSlot(
        arrival: arrival,
        departure: departure,
        transition: transition,
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderContentSlot renderObject,
  ) {
    renderObject
      ..arrival = arrival
      ..departure = departure
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
    required this._arrival,
    required this._departure,
    required this._transition,
    required this._textDirection,
  });

  ValueListenable<double>? _arrival;
  ValueListenable<double>? get arrival => _arrival;
  set arrival(ValueListenable<double>? value) {
    if (identical(value, _arrival)) return;
    _change(() {
      if (attached) _arrival?.removeRenderListener(_moved);
      _arrival = value;
      if (attached) _arrival?.addRenderListener(_moved);
    });
  }

  ValueListenable<double>? _departure;
  ValueListenable<double>? get departure => _departure;
  set departure(ValueListenable<double>? value) {
    if (identical(value, _departure)) return;
    _change(() {
      if (attached) _departure?.removeRenderListener(_moved);
      _departure = value;
      if (attached) _departure?.addRenderListener(_moved);
    });
    markNeedsSemanticsUpdate();
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

  bool get _moving => _arrival != null || _departure != null;

  bool get _leaving => _departure != null;

  void _change(VoidCallback update) {
    final wasMoving = _moving;
    update();
    if (child != null && wasMoving != _moving) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsCompositedLayerUpdate();
  }

  void _moved() => markNeedsCompositedLayerUpdate();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _arrival?.addRenderListener(_moved);
    _departure?.addRenderListener(_moved);
  }

  @override
  void detach() {
    _arrival?.removeRenderListener(_moved);
    _departure?.removeRenderListener(_moved);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => child != null && _moving;

  MotionPose get _pose {
    var pose = MotionPose.identity;
    if (_arrival case final arrival?) {
      pose = _transition.poseAt(arrival.value, incoming: true);
    }
    if (_departure case final departure?) {
      pose = pose.compose(
        _transition.poseAt(departure.value, incoming: false),
      );
    }
    return pose;
  }

  Matrix4? _transformOf(MotionPose pose) => transformAbout(
    size,
    pivot: _transition.alignment,
    textDirection: _textDirection,
    offset: pose.offset,
    offsetFraction: pose.offsetFraction,
    scaleX: pose.scale,
    scaleY: pose.scale,
    rotation: pose.rotation,
  );

  Matrix4? get _transform => _moving ? _transformOf(_pose) : null;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    final pose = _pose;
    layer.update(
      transform: _transformOf(pose),
      clip: null,
      opacity: pose.opacity,
      blur: pose.blur,
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
    if (_leaving) return false;
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
    if (!_leaving) super.visitChildrenForSemantics(visitor);
  }
}
