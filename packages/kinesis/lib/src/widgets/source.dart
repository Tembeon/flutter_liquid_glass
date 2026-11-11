import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

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

  /// Hides the source until the returned callback releases it; later
  /// calls of the callback do nothing.
  @internal
  VoidCallback lease() {
    _leases++;
    _box?.markNeedsPaint();
    var held = true;
    return () {
      if (!held) return;
      held = false;
      _leases--;
      _box?.markNeedsPaint();
    };
  }

  @override
  String toString() => 'MotionSource(${debugLabel ?? ''})';
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
