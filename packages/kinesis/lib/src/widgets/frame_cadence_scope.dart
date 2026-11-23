import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/frame_cadence.dart';

/// Starts the app's frame cadence and tells it the scrolls below.
///
/// On a display faster than 90 Hz the app then draws about 60 frames a
/// second while nothing fast moves, and every vsync while a scroll below
/// this widget or a finger moves fast, or while a motion that needs the
/// full rate (`Motion.needsFullFrameRate`) moves. A scroll outside any
/// such scope stays at the lower rate. Only the outermost scope acts.
class FrameCadenceScope extends StatefulWidget {
  /// Starts the cadence for [child] unless a scope above already has.
  const FrameCadenceScope({required this.child, super.key});

  /// The subtree whose scrolls the cadence hears.
  final Widget child;

  @override
  State<FrameCadenceScope> createState() => _FrameCadenceScopeState();
}

class _FrameCadenceScopeState extends State<FrameCadenceScope> {
  bool get _outermost =>
      context.getInheritedWidgetOfExactType<_Cadenced>() == null;

  @override
  void initState() {
    super.initState();
    if (_outermost) FrameCadence.instance.start();
  }

  bool _scrolled(ScrollUpdateNotification notification) {
    if (notification.scrollDelta case final delta?) {
      FrameCadence.instance.scrolled(
        delta,
        notification.metrics.devicePixelRatio,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_outermost) return widget.child;
    return _Cadenced(
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: _scrolled,
        child: widget.child,
      ),
    );
  }
}

class _Cadenced extends InheritedWidget {
  const _Cadenced({required super.child});

  @override
  bool updateShouldNotify(_Cadenced oldWidget) => false;
}
