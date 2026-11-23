import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/follow.dart';

/// State mixin for a controlled widget whose parent owns the authoritative
/// value (such as a switch or slider).
///
/// When the user changes the control's motion value, the state notifies the
/// app via [notifyChanged]. In a build that follows, [syncFromWidget]
/// returns the motion to the widget's value if the parent did not take the
/// new one; so it does after the parent gives a new widget. While the user
/// drives the value ([userDriving]) the return waits, and it comes when
/// they let go: a parent's value set during a drag shows at the release,
/// as `CupertinoSlidingSegmentedControl` keeps its group value while its
/// thumb drags.
///
/// Subclasses override [buildControl] instead of [build].
mixin ControlledValue<T extends StatefulWidget> on State<T> {
  bool _pending = false;
  ValueListenable<bool>? _driving;
  final MotionFollow _follow = MotionFollow(following: false);

  /// The clock the control's motion runs on.
  @protected
  MotionClock get valueClock;

  /// Whether the user drives the value now: a finger on the control, or a
  /// glide it left behind. The same instance while the control's motion
  /// is; never by default.
  @protected
  ValueListenable<bool> get userDriving => const _Never();

  /// Returns the control's motion to the widget's value when they differ,
  /// and does nothing when they agree. [build] calls it.
  @protected
  @visibleForOverriding
  void syncFromWidget();

  /// Runs [notify] outside build/layout/paint so the parent callback can
  /// safely rebuild, then returns to the widget's value in the build that
  /// follows if the parent did not take the change.
  @protected
  void notifyChanged(VoidCallback notify) => runOutsideBuild(() {
    notify();
    if (mounted) setState(() => _pending = true);
  });

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
  void initState() {
    super.initState();
    _follow.attach();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pending = true;
  }

  @override
  void dispose() {
    _follow.detach();
    super.dispose();
  }

  void _drivingChanged() {
    if (_pending && !(_driving?.value ?? false)) {
      runOutsideBuild(() => setState(() {}));
    }
  }

  @override
  @nonVirtual
  Widget build(BuildContext context) {
    final driving = userDriving;
    if (!identical(driving, _driving)) {
      _driving = driving;
      _follow.heard = [(driving, _drivingChanged)];
    }
    _follow.following = followsMotion(context);
    if (_pending && !driving.value) {
      _pending = false;
      syncFromWidget();
    }
    return buildControl(context);
  }
}

final class _Never implements ValueListenable<bool> {
  const _Never();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
