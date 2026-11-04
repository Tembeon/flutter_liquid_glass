import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/screen/resolve.dart';
import 'package:meta/meta.dart';

/// Where a presentation grows from, in global coordinates.
@immutable
final class SourceGeometry {
  /// Creates the geometry of a source at [rect] with [radius].
  const SourceGeometry({required this.rect, this.radius = BorderRadius.zero});

  /// The source's bounds, in global coordinates.
  final Rect rect;

  /// The source's corners.
  final BorderRadius radius;

  @override
  bool operator ==(Object other) =>
      other is SourceGeometry && other.rect == rect && other.radius == radius;

  @override
  int get hashCode => Object.hash(rect, radius);
}

/// A motion that grows out of a source and back into it: the shell tells
/// it where the source is when it commits and in every frame's resolve
/// phase after that, before paint.
mixin Sourced on Motion {
  /// The source is at [geometry] at time [t]; null once nothing shows it
  /// (its widget went away), and the motion decides how to end without it.
  void sourceMoved(double t, SourceGeometry? geometry);
}

/// The identity of what a presentation grows out of, held like a
/// `LayerLink`: a [MotionSourceBox] shows it, a presentation leases it.
///
/// While a lease is held the box paints nothing, from the frame the
/// presentation commits, and stays hit-testable, as UIKit hides a zoom
/// transition's source view.
final class MotionSource {
  /// Creates a source.
  MotionSource({this.debugLabel});

  /// A name for debugging.
  final String? debugLabel;

  RenderMotionSourceBox? _box;
  int _leases = 0;

  /// Whether a presentation holds the source.
  bool get isHidden => _leases > 0;

  /// Where the source is now, or null when no laid-out box shows it.
  SourceGeometry? get geometry {
    final box = _box;
    if (box == null || !box.attached || !box.hasSize) return null;
    return SourceGeometry(
      rect: MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      ),
      radius: box.radius,
    );
  }

  /// Hides the source until the lease is released.
  @internal
  SourceLease lease() {
    _leases++;
    _box?.markNeedsPaint();
    return SourceLease._(this);
  }

  void _release() {
    _leases--;
    _box?.markNeedsPaint();
  }

  @override
  String toString() => 'MotionSource(${debugLabel ?? ''})';
}

/// A presentation's hold on a [MotionSource].
@internal
final class SourceLease {
  SourceLease._(this._source);

  MotionSource? _source;

  /// Shows the source again; later calls do nothing.
  void release() {
    _source?._release();
    _source = null;
  }
}

/// Shows [source] around [child]: it reports where the source is and paints
/// nothing while a presentation leases it.
class MotionSourceBox extends SingleChildRenderObjectWidget {
  /// Shows [source] with [radius] corners around [child].
  const MotionSourceBox({
    required this.source,
    this.radius = BorderRadius.zero,
    super.child,
    super.key,
  });

  /// The source shown.
  final MotionSource source;

  /// The source's corners.
  final BorderRadius radius;

  @override
  RenderMotionSourceBox createRenderObject(BuildContext context) =>
      RenderMotionSourceBox(source: source, radius: radius);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMotionSourceBox renderObject,
  ) {
    renderObject.source = source;
    renderObject.radius = radius;
  }
}

/// The render object of a [MotionSourceBox].
@internal
class RenderMotionSourceBox extends RenderProxyBox {
  /// Creates the box of [source].
  RenderMotionSourceBox({
    required this._source,
    required this.radius,
  });

  MotionSource _source;

  /// The source's corners.
  BorderRadius radius;

  /// The source shown.
  MotionSource get source => _source;
  set source(MotionSource value) {
    if (identical(value, _source)) return;
    if (attached) _detachSource();
    _source = value;
    if (attached) value._box = this;
    markNeedsPaint();
  }

  void _detachSource() {
    if (identical(_source._box, this)) _source._box = null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source._box = this;
  }

  @override
  void detach() {
    _detachSource();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_source.isHidden) return;
    super.paint(context, offset);
  }
}

/// Keeps [motion] told where [source] is, in every frame's resolve phase
/// while it is shown.
@internal
class SourceFollower extends SingleChildRenderObjectWidget {
  /// Tells [motion] where [source] is.
  const SourceFollower({
    required this.source,
    required this.motion,
    super.child,
    super.key,
  });

  /// The source followed.
  final MotionSource source;

  /// The motion told.
  final Sourced motion;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSourceFollower(source, motion);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final follower = renderObject as _RenderSourceFollower;
    follower.source = source;
    follower.motion = motion;
  }
}

class _RenderSourceFollower extends RenderProxyBox with MotionResolveHost {
  _RenderSourceFollower(this.source, this.motion);

  MotionSource source;
  Sourced motion;
  SourceGeometry? _told;
  bool _first = true;

  @override
  bool get resolvesEveryFrame => true;

  @override
  void resolve() {
    final geometry = source.geometry;
    if (!_first && geometry == _told) return;
    _first = false;
    _told = geometry;
    motion.sourceMoved(motion.clock.now, geometry);
  }
}
