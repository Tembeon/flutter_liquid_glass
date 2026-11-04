import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/screen/resolve.dart';

/// Tells [onSize] the size layout gave [child], in the frame that laid it
/// out, before paint: a motion that sizes itself from its content, such as
/// a menu card from its rows or a sheet from its fitted content, commands
/// from it in that frame and draws the new size at once.
///
/// [onSize] hears the frame's time and the new size after the first layout
/// and after each layout that changes the size. It runs in the frame's
/// resolve phase: it may command motions, and must not mark layout or
/// rebuild.
class MotionMeasure extends SingleChildRenderObjectWidget {
  /// Reports the size of [child] to [onSize].
  const MotionMeasure({required this.onSize, super.child, super.key});

  /// Hears the frame's time and the size of [child].
  final void Function(double t, Size size) onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasure(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasure).onSize = onSize;
  }
}

class _RenderMeasure extends RenderProxyBox with MotionResolveHost {
  _RenderMeasure(this.onSize);

  void Function(double t, Size size) onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) scheduleResolve();
  }

  @override
  void resolve() {
    if (size == _reported) return;
    _reported = size;
    onSize(MotionClock.instance.now, size);
  }
}
