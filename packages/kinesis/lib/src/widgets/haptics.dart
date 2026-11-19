import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:meta/meta.dart';

final Expando<_SelectionThrottle> _lastSelectionByClock =
    Expando<_SelectionThrottle>('kinesis.lastSelectionHaptic');

final class _SelectionThrottle {
  _SelectionThrottle(this.clockTime, this.frameStamp);

  double clockTime;
  Duration? frameStamp;
}

/// Turns the haptics of the input regions below it on or off, and optionally
/// provides a custom [onFeedback] sink (for example a native platform channel
/// for iOS soft/rigid/notification haptics or a test spy).
///
/// UIKit: the System Haptics setting and `UIFeedbackGenerator`. Flutter:
/// `HapticFeedback`.
///
/// An `InputRegion` or `InputZones` below a scope with [enabled] false
/// plays no feedback, and [MotionHapticPlay.play] plays nothing there. A
/// scope cannot turn haptics back on below one that turned them off.
///
/// [MotionHaptic.selection] is throttled to [selectionMinimumInterval]
/// (`0.04 s` / 25 Hz), matching UIKit's `UISelectionFeedbackGenerator`.
class MotionHapticScope extends StatelessWidget {
  /// Turns the haptics of [child] on or off, optionally routing played
  /// haptics through [onFeedback].
  const MotionHapticScope({
    required this.enabled,
    required this.child,
    this.onFeedback,
    super.key,
  });

  /// Minimum interval between consecutive [MotionHaptic.selection] ticks, in
  /// seconds (`0.04 s` = 40 ms / 25 Hz, matching UIKit's
  /// `UISelectionFeedbackGenerator`).
  static const double selectionMinimumInterval = 0.04;

  /// Whether the regions below play their haptics.
  final bool enabled;

  /// Optional custom feedback handler invoked instead of Flutter's default
  /// [HapticFeedback] when haptics are enabled. Inherits from an enclosing
  /// [MotionHapticScope] when null.
  final void Function(MotionHaptic haptic)? onFeedback;

  /// The subtree the scope governs.
  final Widget child;

  /// Whether haptics are on at [context]: false below any scope that turns
  /// them off, true otherwise. Rebuilds [context] when that changes.
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HapticScope>()?.enabled ??
      true;

  @override
  Widget build(BuildContext context) {
    final parent = context.dependOnInheritedWidgetOfExactType<_HapticScope>();
    return _HapticScope(
      enabled: enabled && (parent?.enabled ?? true),
      onFeedback: onFeedback ?? parent?.onFeedback,
      child: child,
    );
  }
}

/// Plays [haptic] for the control at [context], unless a scope there turns
/// haptics off, an input host is handling a keyboard or accessibility input,
/// or a [MotionHaptic.selection] tick arrived within
/// [MotionHapticScope.selectionMinimumInterval] of the previous one.
@internal
void playHaptic(BuildContext context, MotionHaptic haptic) {
  if (!context.mounted || !gestureInput) return;
  final scope = context.getInheritedWidgetOfExactType<_HapticScope>();
  if (!(scope?.enabled ?? true)) return;
  if (haptic == MotionHaptic.selection) {
    final scopedClock = context
        .getInheritedWidgetOfExactType<MotionClockScope>()
        ?.clock;
    final clock = scopedClock ?? MotionClockScope.of(context);
    final now = clock.now > clock.frameTime ? clock.now : clock.frameTime;
    final frameStamp = scopedClock == null
        ? SchedulerBinding.instance.currentSystemFrameTimeStamp
        : null;
    final last = _lastSelectionByClock[clock];
    if (last != null) {
      final clockDelta = now - last.clockTime;
      final frameDelta = frameStamp != null && last.frameStamp != null
          ? (frameStamp - last.frameStamp!).inMicroseconds / 1e6
          : 0.0;
      if (clockDelta >= 0 &&
          frameDelta >= 0 &&
          math.max(clockDelta, frameDelta) <
              MotionHapticScope.selectionMinimumInterval) {
        return;
      }
      last
        ..clockTime = now
        ..frameStamp = frameStamp;
    } else {
      _lastSelectionByClock[clock] = _SelectionThrottle(now, frameStamp);
    }
  }
  if (scope?.onFeedback case final handler?) {
    handler(haptic);
    return;
  }
  switch (haptic) {
    case .selection:
      HapticFeedback.selectionClick().ignore();
    case .lightImpact || .softImpact || .success:
      HapticFeedback.lightImpact().ignore();
    case .mediumImpact || .warning:
      HapticFeedback.mediumImpact().ignore();
    case .heavyImpact || .rigidImpact || .error:
      HapticFeedback.heavyImpact().ignore();
  }
}

class _HapticScope extends InheritedWidget {
  const _HapticScope({
    required this.enabled,
    required this.onFeedback,
    required super.child,
  });

  final bool enabled;
  final void Function(MotionHaptic haptic)? onFeedback;

  @override
  bool updateShouldNotify(_HapticScope oldWidget) =>
      enabled != oldWidget.enabled || onFeedback != oldWidget.onFeedback;
}

/// Plays a [MotionHaptic] for a control.
///
/// UIKit: `UIFeedbackGenerator`. SwiftUI: `sensoryFeedback`. Flutter:
/// `HapticFeedback`.
extension MotionHapticPlay on MotionHaptic {
  /// Plays the haptic for the control at [context], at once.
  ///
  /// This is how a control plays a haptic for something that is not an
  /// event of its interactions: a switch whose shown state flips under the
  /// finger, a slider that reaches its end stop, a wheel that turns to
  /// the next row. The haptics of the interactions' own events go through
  /// `InputRegion.feedback` and `InputZones.feedback`, which play the same
  /// way.
  ///
  /// It plays nothing below a [MotionHapticScope] that turns haptics off,
  /// and nothing while an input region or a zone handles a keyboard or
  /// accessibility input (an `ActivateInput` or `AdjustInput` whose source
  /// is not the pointer): a control that answers a key or an assistive
  /// action by calling it stays silent, as UIKit's controls are.
  ///
  /// Consecutive [MotionHaptic.selection] calls within
  /// [MotionHapticScope.selectionMinimumInterval] (40 ms) are dropped.
  void play(BuildContext context) => playHaptic(context, this);
}
