import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kinesis/src/frame_grid.dart';
import 'package:kinesis/src/pointer_clock_stub.dart'
    if (dart.library.ffi) 'package:kinesis/src/pointer_clock_io.dart';
import 'package:kinesis/src/timeline.dart';
import 'package:kinesis/src/transaction.dart';

/// Something a [MotionClock] steps once per frame while it is active: a
/// control's measured motion, a UIKit-style per-frame loop.
///
/// A driver that becomes active, or whose [wakeTime] moves earlier, calls
/// [MotionClock.wake] with itself.
abstract class MotionDriver {
  /// Advances the driver to [time], in seconds.
  void step(double time);

  /// Whether the driver needs another frame.
  bool get isActive;

  /// The time before which the driver shows nothing new, or null when it
  /// changes every frame. A driver that would wait longer than two frames
  /// is not stepped until half a frame before then, and the clock dozes
  /// when every active driver waits.
  double? get wakeTime => null;
}

/// A value the clock steps and publishes while it moves and something
/// follows it.
@internal
abstract interface class MotionFollowed {
  /// Moves to [time] in the step phase; returns whether it needs another
  /// frame.
  bool stepTo(double time);

  /// The time before which it does not move, or null when it moves now.
  double? get wakeTime;

  /// Tells its render followers where it is, and its other followers too
  /// when [widgets]: in the resolve phase only render followers hear.
  void publish({required bool widgets});

  /// Whether it has followers that are not render followers.
  bool get hasWidgetFollowers;
}

/// A value derived from others and recomputed after the values publish.
@internal
abstract interface class MotionDerived {
  /// Recomputes and tells its render followers when the result changed,
  /// and its other followers too when [widgets].
  void recompute({required bool widgets});

  /// Whether it has followers that are not render followers.
  bool get hasWidgetFollowers;
}

/// Runs [body], reporting what it throws as the error of [context] in
/// kinesis, as `ChangeNotifier` does for its listeners, so one failing
/// listener or driver does not stop the frame.
@internal
void guardMotion(VoidCallback body, String context) {
  try {
    body();
  } on Object catch (exception, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'kinesis',
        context: ErrorDescription(context),
      ),
    );
  }
}

/// Owns motion time and the frame: the one ordered step in which every
/// value of the app advances.
///
/// A frame runs in phases: timelines (due actions, each at its own time),
/// drivers, the step (values start due delayed changes, come to rest and
/// snap), then publish (values tell their followers, derived values
/// recompute once each), all before build; then, after layout, resolve
/// (layouts place what they just laid out, and the values that change
/// tell their render followers before paint). Every read in a frame
/// answers at one time.
///
/// Times are seconds on one monotonic timeline. Every operation of a
/// `MotionValue` also has a form with an explicit time; a clock supplies
/// [now] for the ambient forms (`MotionValue.target`, `MotionValue.value`).
abstract class MotionClock {
  static MotionClock? _instance;

  /// The clock values use when none is given: the binding's frame clock,
  /// shared by every view, as Flutter frames all views in one pass.
  static MotionClock get instance => _instance ??= _BindingClock();

  /// Replaces [instance], for tests and apps that drive time themselves.
  static set instance(MotionClock clock) => _instance = clock;

  /// Replaces the engine clock the frame clock compares frame and input
  /// time stamps with, for tests that drive it like a device's.
  @visibleForTesting
  static Duration Function()? debugEngineNow;

  /// Replaces how far the engine clock runs ahead of pointer time stamps,
  /// or answers null for a platform that gives no usable time stamps.
  @visibleForTesting
  static Duration? Function()? debugPointerClockOffset;

  /// Drops [instance], so the next read creates a fresh frame clock.
  @visibleForTesting
  static void debugReset() {
    final clock = _instance;
    if (clock is _BindingClock) clock._dispose();
    _instance = null;
    MotionTransaction.clearLayout();
  }

  final MotionTimeline _timeline = MotionTimeline();
  final List<MotionDriver> _drivers = [];
  final Map<MotionDriver, double> _dozing = {};
  final Set<MotionFollowed> _followed = {};
  final Set<MotionDerived> _dirty = {};
  final Set<MotionFollowed> _owed = {};
  final Set<MotionDerived> _owedDerived = {};
  Set<MotionFollowed>? _resolved;
  bool _resolving = false;

  /// The current time, in seconds.
  double get now;

  /// The display's frame period in seconds, or null before steady frames.
  double? get framePeriod;

  /// The frame rate the clock's frames come at: for the binding's clock, 60
  /// on a 60 Hz display and 120 otherwise.
  double get frameRate;

  /// The time of an input event whose time stamp is [timeStamp], waking
  /// the clock.
  double stamp(Duration timeStamp);

  /// Makes sure the clock produces a frame for work that is now pending,
  /// stepping [driver] in it if it was waiting.
  void wake([MotionDriver? driver]) {
    if (driver != null) _dozing.remove(driver);
    _wake();
  }

  void _wake();

  /// Steps [driver] once per frame while it [MotionDriver.isActive].
  void addDriver(MotionDriver driver) {
    _drivers.add(driver);
    if (driver.isActive) wake();
  }

  /// Stops stepping [driver].
  void removeDriver(MotionDriver driver) {
    _drivers.remove(driver);
    _dozing.remove(driver);
    _idleCheck();
  }

  /// Runs [action] at [time], in the timelines phase of the frame that
  /// reaches it, with that time; the returned callback cancels it.
  VoidCallback schedule(double time, void Function(double time) action) {
    void run(double t) =>
        guardMotion(() => action(t), 'while running a scheduled action');
    _timeline.insert(time, run);
    wake();
    return () {
      _timeline.remove(run);
      _idleCheck();
    };
  }

  /// Runs [callback] once in the coming publish phase, after the frame's
  /// motion values stepped and published and before build, where a widget
  /// may rebuild; the returned callback cancels it.
  ///
  /// A frame is asked for when none is coming; asking from within a
  /// publish phase runs [callback] in that phase. Every call schedules a
  /// run of its own.
  VoidCallback schedulePublish(VoidCallback callback) {
    final publisher = _Publisher(callback);
    markDirty(publisher);
    return () {
      _dirty.remove(publisher);
      _owedDerived.remove(publisher);
      _idleCheck();
    };
  }

  /// Steps and publishes [value] every frame until it rests.
  @internal
  void follow(MotionFollowed value) {
    _followed.add(value);
    final resolved = _resolved;
    if (resolved == null) {
      wake();
    } else {
      resolved.add(value);
    }
  }

  /// Stops stepping [value].
  @internal
  void unfollow(MotionFollowed value) {
    if (_followed.remove(value)) _idleCheck();
  }

  /// Recomputes [derived] in the coming publish phase, or in the current
  /// one when it runs.
  @internal
  void markDirty(MotionDerived derived) {
    if (_dirty.add(derived) && !_resolving) wake();
  }

  /// Whether the frame's resolve phase runs: after layout, before paint.
  @internal
  bool get isResolving => _resolving;

  /// Runs [body] in the frame's resolve phase, after layout and before
  /// paint.
  ///
  /// The values it changes are stepped and published to their render
  /// followers at once, so what draws them shows this frame's
  /// presentation; a render follower may mark paint and composited layers
  /// there, not layout. Their other followers, such as widgets that
  /// rebuild, hear them in the next frame's publish phase.
  @internal
  void resolve(VoidCallback body) {
    _resolving = true;
    try {
      final resolved = _resolved = {};
      try {
        body();
      } finally {
        _resolved = null;
      }
      final time = now;
      for (final value in resolved) {
        if (!value.stepTo(time)) _followed.remove(value);
      }
      for (final value in resolved) {
        value.publish(widgets: false);
      }
      _owed.addAll(resolved.where((value) => value.hasWidgetFollowers));
      _drain(widgets: false);
    } finally {
      _resolving = false;
    }
    if (needsFrame) wake();
  }

  void _drain({required bool widgets}) {
    if (widgets) {
      _dirty.addAll(_owedDerived);
      _owedDerived.clear();
    }
    while (_dirty.isNotEmpty) {
      final derived = _dirty.first;
      _dirty.remove(derived);
      derived.recompute(widgets: widgets);
      if (!widgets && derived.hasWidgetFollowers) _owedDerived.add(derived);
    }
  }

  /// Runs the phases of one frame at [time].
  @protected
  void runFrame(double time) {
    _timeline.runDue(time);
    final period = 1 / frameRate;
    for (final driver in List.of(_drivers)) {
      if (!driver.isActive) continue;
      final until = _dozing[driver];
      if (until != null) {
        // Back half a frame early, so the frame that shows the change is
        // never missed.
        if (time < until - 0.5 * period) continue;
        _dozing.remove(driver);
      }
      guardMotion(() => driver.step(time), 'while stepping a motion driver');
      final wake = driver.wakeTime;
      if (wake != null && wake - time > 2 * period) _dozing[driver] = wake;
    }
    final stepped = List.of(_followed);
    for (final value in stepped) {
      if (!value.stepTo(time)) _followed.remove(value);
    }
    for (final value in stepped) {
      value.publish(widgets: true);
    }
    final owed = List.of(_owed.difference(stepped.toSet()));
    _owed.clear();
    for (final value in owed) {
      value.publish(widgets: true);
    }
    _drain(widgets: true);
  }

  /// Whether anything moves or is pending.
  @protected
  bool get needsFrame =>
      _followed.isNotEmpty ||
      _dirty.isNotEmpty ||
      _owed.isNotEmpty ||
      _owedDerived.isNotEmpty ||
      _drivers.any((driver) => driver.isActive) ||
      !_timeline.isEmpty;

  /// The time before which no frame would change anything, or null when
  /// the next frame would.
  @protected
  double? get wakeTime {
    if (_dirty.isNotEmpty || _owed.isNotEmpty || _owedDerived.isNotEmpty) {
      return null;
    }
    var wake = _timeline.nextDue ?? double.infinity;
    for (final driver in _drivers) {
      if (!driver.isActive) continue;
      final at = driver.wakeTime;
      if (at == null) return null;
      if (at < wake) wake = at;
    }
    for (final value in _followed) {
      final at = value.wakeTime;
      if (at == null) return null;
      if (at < wake) wake = at;
    }
    return wake.isFinite ? wake : null;
  }

  void _idleCheck() {}
}

final class _Publisher implements MotionDerived {
  _Publisher(this.callback);

  final VoidCallback callback;

  @override
  bool get hasWidgetFollowers => true;

  @override
  void recompute({required bool widgets}) {
    if (widgets) guardMotion(callback, 'while running a publish callback');
  }
}

/// A clock that moves only when told to: for tests, replays and apps that
/// drive time themselves. [advanceTo] runs a frame's phases at once.
class ManualMotionClock extends MotionClock {
  /// Creates a clock at [start] seconds for a display at [frameRate].
  ManualMotionClock({double start = 0, this.frameRate = 120}) : _now = start;

  double _now;

  @override
  final double frameRate;

  @override
  double get now => _now;

  @override
  double? get framePeriod => 1 / frameRate;

  @override
  double stamp(Duration timeStamp) => _now;

  @override
  void _wake() {}

  /// Moves the clock to [t] and runs a frame there; time never runs
  /// backwards.
  void advanceTo(double t) {
    assert(t >= _now, 'time runs forward: $t is before $_now');
    _now = t;
    runFrame(t);
  }

  /// Moves the clock forward by [seconds] and runs a frame there.
  void advanceBy(double seconds) => advanceTo(_now + seconds);
}

/// The binding's frame clock.
///
/// Its time is the scheduler's frame time stamp (so `timeDilation` and test
/// pumps apply), put on the display's frame grid ([FrameGrid]). The clock
/// asks for frames only while something is active. With only a later change
/// pending it dozes on a timer instead, and with nothing pending it sleeps.
/// Both count where the frame time stamps follow the engine clock, as on a
/// device: input stamped and changes made meanwhile get the time an
/// uninterrupted clock would give them, and so does the frame that ends the
/// wait, so a finger held still keeps its time. Under a test's fake frame
/// clock, which the engine clock does not follow, the time stands still
/// while the clock sleeps.
///
/// A frame's phases run in a microtask scheduled from the clock's frame
/// callback, so after every ticker of the frame and before build; a clock
/// woken by a ticker or by a microtask of a frame that has not built yet
/// runs them in that frame. The frame's time is computed once, by whichever
/// reads it first: a ticker that runs before the clock's callback reads the
/// time the frame steps at.
///
/// Input events are stamped at their own time stamp, moved onto the frame
/// clock by the pointer clock offset: UIKit's measured delays count from
/// the touch's time stamp. While the clock runs or dozes, an event's time is
/// the latest frame's time plus the time from that frame's time stamp to
/// the event's, usually a frame or two in the past. Events that arrive
/// before its first frame, or while it sleeps under a fake frame clock,
/// keep their spacing, measured by their own time stamps and slowed by
/// `timeDilation`, and the first frame after the wake continues from the
/// latest of them, so the clock never runs backwards. An
/// event whose time stamp does not land within [maxEventAge] before the
/// engine clock is taken as happening one frame after its delivery. When
/// the frame time stamps and the engine clock disagree by more than
/// [maxFrameLead] (a test's fake frame clock), an event gets the latest
/// frame's time while the clock runs, and the first frame after a wake
/// continues from the latest stamp itself.
class _BindingClock extends MotionClock {
  /// The largest distance, in seconds, between a frame's time stamp and
  /// the engine clock at its callback for which the two count as one.
  static const double maxFrameLead = 0.05;

  /// The oldest an event's time stamp may be at its delivery, in seconds,
  /// for [stamp] to trust it.
  static const double maxEventAge = 0.25;

  final FrameGrid _grid = FrameGrid();
  double _base = 0;
  double _time = 0;
  double _tickTime = 0;
  bool _running = false;
  bool _phasesQueued = false;
  bool _phasesRan = false;
  bool _ticking = false;
  int? _callbackId;
  Duration? _start;
  Duration? _advanced;
  Duration? _tickStamp;
  bool _stampsAgree = false;
  Duration? _stampFrom;
  double _stampTime = 0;
  Duration? _wakeFrom;
  double _wakeTime = 0;
  Timer? _doze;
  Duration? _dozeStamp;
  Duration? _dozeSystemStamp;
  double _dozeTime = 0;

  @override
  double get now {
    if (_callbackId != null) {
      final scheduler = SchedulerBinding.instance;
      if (scheduler.schedulerPhase == SchedulerPhase.transientCallbacks) {
        _advance(scheduler.currentFrameTimeStamp);
        return _time;
      }
    }
    final dozed = _dozeSystemStamp;
    final dozedFrame = _dozeStamp;
    if (dozed != null && dozedFrame != null && _stampsAgree) {
      final scheduler = SchedulerBinding.instance;
      // Inside a frame the clock does not run, a change made now shows in
      // that frame: it gets the frame's time, as the clock's next frame
      // counts on from it.
      final t = scheduler.schedulerPhase == SchedulerPhase.idle
          ? _dozeTime +
                (_engineNow() - dozed).inMicroseconds / 1e6 / timeDilation
          : _dozeTime +
                (scheduler.currentFrameTimeStamp - dozedFrame).inMicroseconds /
                    1e6;
      if (t > _time) return t;
    }
    return _time;
  }

  @override
  double? get framePeriod => _grid.period;

  @override
  double get frameRate {
    final views = SchedulerBinding.instance.platformDispatcher.views;
    final rate = views.isEmpty ? null : views.first.display.refreshRate;
    return rate != null && rate.round() == 60 ? 60 : 120;
  }

  // The engine stamps frames on the Dart timeline clock: on iOS that is
  // CLOCK_MONOTONIC_RAW (iPhone 16 Pro, iOS 27.0.1, Flutter 3.47.2), while
  // touches count CLOCK_UPTIME_RAW (pointerClockOffset).
  Duration _engineNow() =>
      MotionClock.debugEngineNow?.call() ??
      Duration(microseconds: Timeline.now);

  Duration _occurred(Duration timeStamp, Duration now) {
    final hook = MotionClock.debugPointerClockOffset;
    final offset = hook == null ? pointerClockOffset() : hook();
    if (offset != null) {
      final at = timeStamp + offset;
      final age = (now - at).inMicroseconds / 1e6;
      if (age >= 0 && age < maxEventAge) return at;
    }
    return now + Duration(microseconds: (1e6 / frameRate).round());
  }

  @override
  double stamp(Duration timeStamp) {
    final now = _engineNow();
    wake();
    if (_ticking) {
      final tick = _tickStamp;
      if (!_stampsAgree || tick == null) return _time;
      final since = (_occurred(timeStamp, now) - tick).inMicroseconds / 1e6;
      if (since < -maxEventAge) return _time;
      return _tickTime + since / timeDilation;
    }
    _wakeFrom = _occurred(timeStamp, now);
    final from = _stampFrom;
    if (from == null) {
      _stampFrom = timeStamp;
      _stampTime = _time;
      _wakeTime = _time;
      return _time;
    }
    final elapsed = (timeStamp - from).inMicroseconds / 1e6;
    if (elapsed > 0) {
      final t = _stampTime + elapsed / timeDilation;
      if (t > _time) _time = t;
    }
    _wakeTime = _time;
    return _time;
  }

  @override
  void _wake() {
    _doze?.cancel();
    _doze = null;
    final scheduler = SchedulerBinding.instance;
    final phase = scheduler.schedulerPhase;
    // What wakes the clock before build shows in the frame being made, not
    // the next, even after that frame's phases ran.
    final building =
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (_running) {
      if (building && _phasesRan) _queuePhases();
      return;
    }
    _running = true;
    _start = null;
    // As a Ticker started inside a frame does, count from that frame, so
    // the next frame already moves by a frame.
    if (phase.index > SchedulerPhase.idle.index &&
        phase.index < SchedulerPhase.postFrameCallbacks.index) {
      _start = scheduler.currentFrameTimeStamp;
    }
    if (building) {
      _advance(scheduler.currentFrameTimeStamp);
      _queuePhases();
      return;
    }
    _request();
  }

  void _queuePhases() {
    if (_phasesQueued) return;
    _phasesQueued = true;
    scheduleMicrotask(_phases);
  }

  void _request() {
    if (_callbackId != null) return;
    _callbackId = SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _cancel() {
    _running = false;
    final id = _callbackId;
    if (id == null) return;
    SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _callbackId = null;
  }

  void _sleep() {
    final frame = _advanced;
    if (!_stampsAgree || !_ticking || (_dozeStamp == null && frame == null)) {
      _stop();
      return;
    }
    _cancel();
    _advanced = null;
    _doze?.cancel();
    _doze = null;
    // Sleep counts as a doze without a timer: a finger held still while
    // nothing moves keeps its time.
    if (_dozeStamp == null) {
      _dozeStamp = frame;
      _dozeSystemStamp = _tickStamp;
      _dozeTime = _time;
    }
  }

  void _stop() {
    _cancel();
    _advanced = null;
    _doze?.cancel();
    _doze = null;
    _dozeStamp = null;
    _dozeSystemStamp = null;
    _base = _time;
    _ticking = false;
    _start = null;
  }

  void _advance(Duration timeStamp) {
    final start = _start ??= timeStamp;
    if (timeStamp == _advanced) return;
    _advanced = timeStamp;
    final seconds = (timeStamp - start).inMicroseconds / 1e6;
    final stamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    _stampsAgree =
        ((stamp - _engineNow()).inMicroseconds / 1e6).abs() < maxFrameLead;
    _tickStamp = stamp;
    if (_wakeFrom case final from?) {
      _wakeFrom = null;
      final lag = (stamp - from).inMicroseconds / 1e6;
      if (_stampsAgree && lag > 0 && lag < 1) {
        final woken = _wakeTime + lag / timeDilation;
        if (_base + seconds < woken) _base = woken - seconds;
      }
    }
    if (_dozeStamp case final dozed?) {
      final micros =
          (_dozeTime * 1e6).round() + (timeStamp - dozed).inMicroseconds;
      _base = micros / 1e6 - seconds;
      _dozeStamp = null;
      _dozeSystemStamp = null;
    }
    if (_base + seconds < _time) _base = _time - seconds;
    _tickTime = _base + seconds;
    final snapped = _grid.snap(_tickTime);
    _time = snapped >= _time ? snapped : _tickTime;
    _ticking = true;
    _stampFrom = null;
  }

  void _onFrame(Duration timeStamp) {
    _callbackId = null;
    _phasesRan = false;
    if (!_running) return;
    _advance(timeStamp);
    _queuePhases();
  }

  void _phases() {
    _phasesQueued = false;
    if (!_running) return;
    _phasesRan = false;
    runFrame(_time);
    _phasesRan = true;
    if (!needsFrame) {
      _sleep();
      return;
    }
    final until = wakeTime;
    // A wait of two frames or less keeps the frames: dozing saves nothing.
    if (until != null && until - _time > 2 / frameRate) {
      final scheduler = SchedulerBinding.instance;
      _dozeStamp = scheduler.currentFrameTimeStamp;
      _dozeSystemStamp = scheduler.currentSystemFrameTimeStamp;
      _dozeTime = _time;
      // Half a frame early, so the frame that shows the change is never
      // missed.
      final delay = (until - _time - 0.5 / frameRate) * timeDilation;
      _cancel();
      _doze = Timer(
        Duration(microseconds: (delay * 1e6).floor()),
        _endDoze,
      );
      return;
    }
    _request();
  }

  void _endDoze() {
    _doze = null;
    wake();
  }

  @override
  void _idleCheck() {
    if (!needsFrame) _sleep();
  }

  void _dispose() => _stop();
}
