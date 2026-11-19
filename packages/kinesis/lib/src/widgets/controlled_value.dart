import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// State mixin for a controlled widget whose parent owns the authoritative
/// value (such as a switch or slider).
///
/// When the user changes the control's motion value, the state notifies the
/// app via [notifyChanged]. On the following build, if the parent did not
/// accept the new value, [syncFromWidget] returns the motion to the widget's
/// authoritative value.
///
/// Subclasses override [buildControl] instead of [build].
mixin ControlledValue<T extends StatefulWidget> on State<T> {
  bool _notified = false;

  /// The clock the control's motion runs on.
  @protected
  MotionClock get valueClock;

  /// Whether the user is actively driving the value (dragging or gliding):
  /// [syncFromWidget] waits until [isUserDriving] becomes false. A control
  /// returning true calls [scheduleSync] when the interaction ends.
  @protected
  bool get isUserDriving => false;

  /// Synchronizes the control's motion back to the widget's authoritative
  /// value if it has diverged.
  @protected
  void syncFromWidget();

  /// Runs [notify] outside build/layout/paint so the parent callback can
  /// safely rebuild, then schedules a sync check in the build that follows.
  @protected
  void notifyChanged(VoidCallback notify) => runOutsideBuild(() {
    notify();
    if (mounted) setState(() => _notified = true);
  });

  /// Schedules a [syncFromWidget] check on the next build without notifying
  /// the parent callback.
  @protected
  void scheduleSync() => notifyChanged(() {});

  /// Runs [callback] immediately when safe, or defers it to the clock's next
  /// publish phase if Flutter is currently building, laying out, or painting;
  /// ignored once unmounted.
  @protected
  void runOutsideBuild(VoidCallback callback) => valueClock.runOutsideBuild(() {
    if (mounted) callback();
  });

  /// Builds the control widget.
  @protected
  Widget buildControl(BuildContext context);

  @override
  @nonVirtual
  Widget build(BuildContext context) {
    if (_notified && !isUserDriving) {
      _notified = false;
      syncFromWidget();
    }
    return buildControl(context);
  }
}
