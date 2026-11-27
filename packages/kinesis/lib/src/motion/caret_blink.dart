import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/keyframes.dart';
import 'package:kinesis/src/motion/motion.dart';

/// UIKit text cursor blink motion (`UIStandardTextCursorView` `_uitcvba`).
///
/// Replays the measured iOS 27 stepped opacity timeline, [blinkKeyframes],
/// forever: solid, a stepped fade out, off, a stepped fade back in.
///
/// Call [reset] on focus, text insertion, or selection changes to restart the
/// cycle at its solid start. Call [hide] while a non-collapsed
/// range is selected or unfocused so the clock sleeps with zero idle frames.
final class CaretBlinkMotion extends Motion {
  /// Creates a caret blink motion starting [visible] (hidden by default).
  CaretBlinkMotion({bool visible = false, super.clock}) : _visible = visible {
    _blink = own(KeyframeValue<double>(blinkKeyframes, playing: visible));
  }

  /// Duration of one full blink cycle, in seconds.
  static const double cycleDuration = 1;

  /// Exact measured UIKit `_uitcvba` discrete keyframe sequence.
  static const MotionKeyframes<double> blinkKeyframes = MotionKeyframes<double>(
    duration: cycleDuration,
    mode: KeyframeMode.discrete,
    repeatCount: double.infinity,
    stops: [
      KeyframeStop(0, 1),
      KeyframeStop(0.5, 1),
      KeyframeStop(0.5375, 0.75),
      KeyframeStop(0.575, 0.5),
      KeyframeStop(0.6125, 0.25),
      KeyframeStop(0.65, 0),
      KeyframeStop(0.85, 0),
      KeyframeStop(0.8875, 0.25),
      KeyframeStop(0.925, 0.5),
      KeyframeStop(0.9625, 0.75),
      KeyframeStop(1, 1),
    ],
  );

  bool _visible;
  late final KeyframeValue<double> _blink;
  late final ValueListenable<double> _opacityListenable = select(
    (m) => m.opacity,
  );

  /// Whether the caret is currently shown and blinking.
  bool get isVisible => _visible;

  /// The caret opacity at [now]: `0` when hidden, otherwise along
  /// [blinkKeyframes].
  double get opacity => _visible ? _blink.valueAt(now) : 0;

  /// The caret opacity at an explicit time [t].
  double opacityAt(double t) => _visible ? _blink.valueAt(t) : 0;

  /// A listenable opacity for render-level widgets such as `MotionTransition`.
  ValueListenable<double> get opacityListenable => _opacityListenable;

  /// Shows the caret at [t] and restarts its blink cycle solid at opacity `1`.
  void show(double t) {
    advance(t);
    _visible = true;
    _blink.play(t);
    changed();
  }

  /// Hides the caret at [t] and pauses blinking so no frames are scheduled.
  void hide(double t) {
    advance(t);
    _visible = false;
    _blink.pause(t);
    changed();
  }

  /// Restarts the blink cycle solid at opacity `1` at [t] (call on every
  /// keystroke or selection move while focused).
  void reset(double t) {
    advance(t);
    if (!_visible) return;
    _blink.reset(t);
    changed();
  }
}
