import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kinesis/src/motion/frame_time.dart';
import 'package:kinesis/src/motion/pointer_clock_stub.dart'
    if (dart.library.ffi) 'package:kinesis/src/motion/pointer_clock_io.dart';
import 'package:kinesis/src/motion/timeline.dart';
import 'package:kinesis/src/motion/transaction.dart';

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
/// listener does not stop the frame.
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
/// A frame runs in phases: scheduled actions (each at its own time), the
/// step (values and motions advance to the frame's time, running their due
/// reactions and delayed changes, and are declared at rest once they
/// rest), then publish (values tell their followers, derived values
/// recompute once each), all before build; then, after layout, resolve
/// (layouts place what they just laid out, and the values that change
/// tell their render followers before paint). Every read in a frame
/// answers at one time, and a value commanded while the frame runs, by a
/// step, a listener or a layout in resolve, joins that frame.
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
  /// time stamps with in debug builds, for tests that drive it like a
  /// device's.
  static Duration Function()? debugEngineNow;

  /// Replaces how far the engine clock runs ahead of pointer time stamps
  /// in debug builds.
  static Duration Function()? debugPointerClockOffset;

  /// Drops [instance] in debug builds, so the next read creates a fresh
  /// frame clock: for tests.
  static void debugReset() {
    if (!kDebugMode) return;
    final clock = _instance;
    if (clock is _BindingClock) clock._stop();
    _instance = null;
    clearLayoutSpring();
  }

  final MotionTimeline _timeline = MotionTimeline();
  final Set<MotionFollowed> _followed = {};
  final Set<MotionDerived> _dirty = {};
  final Set<MotionFollowed> _owed = {};
  final Set<MotionDerived> _owedDerived = {};

  // A frame runs in passes. A value followed in a step joins the pass that
  // steps; one commanded later is stepped and published in the next pass,
  // resolve's own in the resolve phase.
  bool _inFrame = false;
  bool _stepping = false;
  final List<MotionFollowed> _pass = [];
  final Set<MotionFollowed> _inPass = {};
  final Set<MotionFollowed> _commanded = {};
  final Set<MotionFollowed> _resolved = {};

  // The resolve phase is the frame's, not one clock's: the clocks whose
  // values it changed, and while it runs.
  static Set<MotionClock> _resolveClocks = {};
  static Set<MotionClock> _resolveRound = {};
  static bool _resolving = false;

  double? _inputTime;
  double _lastInput = double.negativeInfinity;

  /// The time the ambient forms read, in seconds: the stamp of the input
  /// being dispatched inside [input], the frame's time ([frameTime])
  /// otherwise.
  double get now => _inputTime ?? frameTime;

  /// The time of the current frame, or of the coming one between frames,
  /// in seconds.
  double get frameTime;

  /// Runs [body] as input stamped [time]: inside it [now] is that stamp,
  /// so `withSpring`, a `target` written and anything else that reads the
  /// clock's time starts where the input happened, often a frame or two
  /// before the frame that draws it.
  ///
  /// Inputs commit in the order they arrive: a stamp earlier than the
  /// previous input's takes that input's time.
  void input(double time, VoidCallback body) {
    final at = time < _lastInput ? _lastInput : time;
    _lastInput = at;
    final saved = _inputTime;
    _inputTime = at;
    try {
      body();
    } finally {
      _inputTime = saved;
    }
  }

  /// The display's frame period in seconds, or null before steady frames.
  double? get framePeriod;

  /// The frame rate the clock's frames come at: for the binding's clock, the
  /// display's refresh rate, or [assumedFrameRate] before a display reports
  /// one.
  double get frameRate;

  /// The frame rate a clock assumes when no display gives it one.
  static const double assumedFrameRate = 120;

  /// The time of an input event whose time stamp is [timeStamp].
  ///
  /// It does not wake the clock: what the input changes does, so a finger
  /// moving where nothing answers it costs no frame.
  double stamp(Duration timeStamp);

  /// Makes sure the clock produces a frame for work that is now pending.
  void wake();

  /// Runs [action] at [time], in the scheduled-actions phase of the frame
  /// that reaches it, with that time; the returned callback cancels it.
  ///
  /// For an input host's timed reactions, such as a long press coming due
  /// or a scroll delay ending: the action runs at its own time however late
  /// the frame that reaches it, so a timed reaction replays exactly.
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
    final publish = _PublishCallback(callback);
    markDirty(publish);
    return () {
      _dirty.remove(publish);
      _owedDerived.remove(publish);
      _idleCheck();
    };
  }

  /// Runs [callback] now, or in the coming publish phase when the framework is
  /// building, laying out or painting.
  void runOutsideBuild(VoidCallback callback) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      callback();
      return;
    }
    schedulePublish(callback);
  }

  void _follow(MotionFollowed value) {
    _followed.add(value);
    if (_stepping) {
      if (_inPass.add(value)) _pass.add(value);
    } else if (_resolving) {
      _resolved.add(value);
      _resolveClocks.add(this);
    } else if (_inFrame) {
      _commanded.add(value);
    } else {
      wake();
    }
  }

  void _unfollow(MotionFollowed value) {
    if (_followed.remove(value)) _idleCheck();
  }

  void _markDirty(MotionDerived derived) {
    if (!_dirty.add(derived)) return;
    if (_resolving) {
      _resolveClocks.add(this);
    } else if (!_inFrame) {
      wake();
    }
  }

  static void _resolve(Iterable<VoidCallback> steps, String context) {
    assert(!_resolving, 'The resolve phase does not nest.');
    _resolving = true;
    // What layout dirtied on the app's clock outside a step is recomputed
    // for its render followers here too.
    if (_instance case final ambient?) _resolveClocks.add(ambient);
    try {
      for (final step in steps) {
        guardMotion(step, context);
      }
      // Publishing one clock's values may command or dirty its own values
      // or another clock's.
      for (var round = 0; _resolveClocks.isNotEmpty; round++) {
        final clocks = _resolveClocks;
        _resolveClocks = _resolveRound;
        _resolveRound = clocks;
        if (round == _commandPasses) {
          _debugReportCommandCycle('while resolving a frame');
        }
        for (final clock in clocks) {
          if (round == _commandPasses) {
            clock._resolved.clear();
          } else {
            clock._publishResolved();
          }
          if (clock.needsFrame) clock.wake();
        }
        clocks.clear();
      }
    } finally {
      _resolving = false;
      _resolveClocks.clear();
      _resolveRound.clear();
    }
  }

  void _publishResolved() {
    assert(!_inFrame, 'A clock resolves outside its own frame.');
    _beginPass(_resolved);
    _resolved.clear();
    try {
      _runPass(frameTime, _resolved, widgets: false);
    } finally {
      _endPass();
    }
    _drain(widgets: false);
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
  ///
  /// A value followed while the frame runs does not [wake] the clock: what
  /// the frame leaves pending shows in [needsFrame] and [wakeTime] after it.
  @protected
  void runFrame(double time) {
    assert(!_inFrame, 'A clock runs one frame at a time.');
    _inFrame = true;
    try {
      _timeline.runDue(time);
      _beginPass(_followed);
      _runPass(time, _commanded, widgets: true);
      for (final value in _owed) {
        if (_inPass.contains(value)) continue;
        _commanded.remove(value);
        value.publish(widgets: true);
      }
      _owed.clear();
      // A listener that commands a value, such as a title that fades in
      // once a scroll passes it, has it drawn in this frame.
      for (var pass = 0; ; pass++) {
        _drain(widgets: true);
        if (_commanded.isEmpty) break;
        if (pass == _commandPasses) {
          _debugReportCommandCycle('while publishing a frame');
          break;
        }
        _endPass();
        _beginPass(_commanded);
        _commanded.clear();
        _runPass(time, _commanded, widgets: true);
      }
    } finally {
      _endPass();
      _commanded.clear();
      _inFrame = false;
    }
  }

  void _beginPass(Iterable<MotionFollowed> values) {
    _pass.addAll(values);
    _inPass.addAll(values);
  }

  void _endPass() {
    _pass.clear();
    _inPass.clear();
  }

  // A value [commanded] before its turn in the pass is heard once, in its
  // turn.
  void _runPass(
    double time,
    Set<MotionFollowed> commanded, {
    required bool widgets,
  }) {
    _stepping = true;
    try {
      for (var i = 0; i < _pass.length; i++) {
        final value = _pass[i];
        if (!value.stepTo(time)) _followed.remove(value);
      }
    } finally {
      _stepping = false;
    }
    for (final value in _pass) {
      commanded.remove(value);
      value.publish(widgets: widgets);
      if (!widgets && value.hasWidgetFollowers) _owed.add(value);
    }
  }

  // Listeners that keep commanding each other finish in the next frame.
  static const _commandPasses = 8;

  static void _debugReportCommandCycle(String context) {
    if (!kDebugMode) return;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'Motion values were still commanded after $_commandPasses '
          'passes of one frame.\n'
          'Listeners that command each other without settling move the '
          'rest of their work to the next frame, every frame.',
        ),
        library: 'kinesis',
        context: ErrorDescription(context),
      ),
    );
  }

  /// Whether anything moves or is pending.
  @protected
  bool get needsFrame =>
      _followed.isNotEmpty ||
      _dirty.isNotEmpty ||
      _owed.isNotEmpty ||
      _owedDerived.isNotEmpty ||
      !_timeline.isEmpty;

  /// The time before which no frame would change anything, or null when
  /// the next frame would.
  @protected
  double? get wakeTime {
    if (_dirty.isNotEmpty || _owed.isNotEmpty || _owedDerived.isNotEmpty) {
      return null;
    }
    var wake = _timeline.nextDue ?? double.infinity;
    for (final value in _followed) {
      final at = value.wakeTime;
      if (at == null) return null;
      if (at < wake) wake = at;
    }
    return wake.isFinite ? wake : null;
  }

  void _idleCheck() {}
}

/// Internal clock registration hooks for motion parts and selections.
@internal
extension MotionClockInternal on MotionClock {
  /// Steps and publishes [value] every frame until it rests.
  void follow(MotionFollowed value) => _follow(value);

  /// Stops stepping [value].
  void unfollow(MotionFollowed value) => _unfollow(value);

  /// Recomputes [derived] in the coming publish phase, or in the current one.
  void markDirty(MotionDerived derived) => _markDirty(derived);
}

/// Runs [steps] in the frame's resolve phase, after layout and before
/// paint, each reporting what it throws on its own as the error of
/// [context], so one failing step does not stop the others.
@internal
void runResolvePhase(Iterable<VoidCallback> steps, String context) =>
    MotionClock._resolve(steps, context);

/// Calls [listeners] as they are when it starts, each under [guardMotion]
/// with [context], so a listener that adds or removes one changes only the
/// next call.
@internal
void notifyGuarded(List<VoidCallback> listeners, String context) {
  if (listeners.isEmpty) return;
  for (final listener in List<VoidCallback>.of(listeners)) {
    guardMotion(listener, context);
  }
}

/// [notifyGuarded] for listeners that take [value].
@internal
void notifyGuardedWith<T>(
  List<void Function(T)> listeners,
  T value,
  String context,
) {
  if (listeners.isEmpty) return;
  for (final listener in List<void Function(T)>.of(listeners)) {
    guardMotion(() => listener(value), context);
  }
}

/// The listeners of a value the clock steps and publishes, and the clock it
/// follows: a value makes one at its first listener and keeps it.
///
/// A part reads its clock through its owner, which may change while it is
/// followed, so [follow] leaves the clock it followed before.
@internal
abstract base class ClockPublisher implements MotionFollowed {
  /// Creates a publisher that reports a failing listener as an error of
  /// [_context].
  ClockPublisher(this._context);

  final String _context;
  final List<VoidCallback> _listeners = [];
  final List<VoidCallback> _renderListeners = [];
  MotionClock? _clock;

  /// Whether anything listens.
  bool get hasListeners => _listeners.isNotEmpty || _renderListeners.isNotEmpty;

  @override
  bool get hasWidgetFollowers => _listeners.isNotEmpty;

  /// Adds a listener that hears the publish phase.
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// Adds a listener that hears the resolve phase as well.
  void addRenderListener(VoidCallback listener) =>
      _renderListeners.add(listener);

  /// Removes [listener]; the value leaves its clock when nothing listens.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (!hasListeners) unfollow();
  }

  /// Removes a listener added with [addRenderListener]; the value leaves
  /// its clock when nothing listens.
  void removeRenderListener(VoidCallback listener) {
    _renderListeners.remove(listener);
    if (!hasListeners) unfollow();
  }

  /// Steps the value on [clock], and no longer on the clock it followed
  /// before.
  void follow(MotionClock clock) {
    final previous = _clock;
    if (previous != null && !identical(previous, clock)) {
      previous._unfollow(this);
    }
    _clock = clock;
    clock._follow(this);
  }

  /// Stops stepping the value.
  void unfollow() {
    _clock?._unfollow(this);
    _clock = null;
  }

  @override
  void publish({required bool widgets}) {
    notifyGuarded(_renderListeners, _context);
    if (widgets) notifyGuarded(_listeners, _context);
  }
}

final class _PublishCallback implements MotionDerived {
  _PublishCallback(this.callback);

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
  ManualMotionClock({
    double start = 0,
    this.frameRate = MotionClock.assumedFrameRate,
  }) : _now = start;

  double _now;

  @override
  final double frameRate;

  @override
  double get frameTime => _now;

  @override
  double? get framePeriod => 1 / frameRate;

  @override
  double stamp(Duration timeStamp) => _now;

  @override
  void wake() {}

  /// Moves the clock to [t] and runs a frame there; time never runs
  /// backwards.
  void advanceTo(double t) {
    assert(t >= _now, 'time runs forward: $t is before $_now');
    _now = t;
    runFrame(t);
  }
}

/// The binding's frame clock.
///
/// Its time is its [FrameTime]'s, fed the scheduler's frame time stamps and
/// the input's. The clock asks for frames only while something is active.
/// With only a later change pending it dozes on a timer instead, and with
/// nothing pending it sleeps.
///
/// A frame's phases run in a microtask scheduled from the clock's frame
/// callback, so after every ticker of the frame and before build; a clock
/// woken by a ticker or by a microtask of a frame that has not built yet
/// runs them in that frame. The web engine flushes no microtasks between
/// beginning a frame and drawing it, so phases still queued when the frame
/// draws run first. The frame's time is computed once, by whichever
/// reads it first: a ticker that runs before the clock's callback reads the
/// time the frame steps at.
class _BindingClock extends MotionClock {
  late final FrameTime _frames = FrameTime(
    engineNow: _engineNow,
    pointerClockOffset: _pointerClockOffset,
    dilation: () => timeDilation,
    frameRate: () => frameRate,
  );
  bool _running = false;
  bool _phasesQueued = false;
  bool _phasesRan = false;
  int? _callbackId;
  Timer? _doze;

  @override
  double get frameTime {
    final scheduler = SchedulerBinding.instance;
    if (_callbackId != null &&
        scheduler.schedulerPhase == SchedulerPhase.transientCallbacks) {
      _frames.advance(
        scheduler.currentFrameTimeStamp,
        scheduler.currentSystemFrameTimeStamp,
      );
      return _frames.time;
    }
    return _frames.read(
      frameStamp: scheduler.schedulerPhase == SchedulerPhase.idle
          ? null
          : scheduler.currentFrameTimeStamp,
    );
  }

  @override
  double? get framePeriod => _frames.period;

  @override
  double get frameRate {
    final views = SchedulerBinding.instance.platformDispatcher.views;
    final rate = views.isEmpty ? null : views.first.display.refreshRate;
    return rate != null && rate > 0
        ? rate.roundToDouble()
        : MotionClock.assumedFrameRate;
  }

  // The engine stamps frames on the Dart timeline clock: on iOS that is
  // CLOCK_MONOTONIC_RAW (iPhone 16 Pro, iOS 27.0.1, Flutter 3.47.2), while
  // touches count CLOCK_UPTIME_RAW (pointerClockOffset).
  static Duration _engineNow() =>
      (kDebugMode ? MotionClock.debugEngineNow?.call() : null) ??
      Duration(microseconds: Timeline.now);

  static Duration _pointerClockOffset() {
    final hook = kDebugMode ? MotionClock.debugPointerClockOffset : null;
    return hook == null ? pointerClockOffset() : hook();
  }

  @override
  double stamp(Duration timeStamp) => _frames.stamp(timeStamp);

  @override
  void wake() {
    _endDozeTimer();
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
    // As a Ticker started inside a frame does, count from that frame, so
    // the next frame already moves by a frame.
    _frames.origin =
        phase.index > SchedulerPhase.idle.index &&
            phase.index < SchedulerPhase.postFrameCallbacks.index
        ? scheduler.currentFrameTimeStamp
        : null;
    if (building) {
      _frames.advance(
        scheduler.currentFrameTimeStamp,
        scheduler.currentSystemFrameTimeStamp,
      );
      _queuePhases();
      return;
    }
    _request();
  }

  void _queuePhases() {
    if (_phasesQueued) return;
    _phasesQueued = true;
    _drawAfterPhases(SchedulerBinding.instance.platformDispatcher);
    scheduleMicrotask(_runQueued);
  }

  void _runQueued() {
    if (_phasesQueued) _phases();
  }

  static PlatformDispatcher? _drawWrapped;

  static void _drawAfterPhases(PlatformDispatcher dispatcher) {
    if (identical(_drawWrapped, dispatcher)) return;
    final draw = dispatcher.onDrawFrame;
    // Before the binding's first frame: wrapping now would keep it from
    // registering its own.
    if (draw == null) return;
    _drawWrapped = dispatcher;
    dispatcher.onDrawFrame = () {
      if (MotionClock._instance case final _BindingClock clock) {
        clock._runQueued();
      }
      draw();
    };
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

  void _endDozeTimer() {
    _doze?.cancel();
    _doze = null;
  }

  void _sleep() {
    _frames.sleep();
    _cancel();
    _endDozeTimer();
  }

  void _stop() {
    _cancel();
    _endDozeTimer();
    _frames.stop();
  }

  void _onFrame(Duration timeStamp) {
    _callbackId = null;
    _phasesRan = false;
    if (!_running) return;
    _frames.advance(
      timeStamp,
      SchedulerBinding.instance.currentSystemFrameTimeStamp,
    );
    _queuePhases();
  }

  void _phases() {
    _phasesQueued = false;
    if (!_running) return;
    _phasesRan = false;
    runFrame(_frames.time);
    _phasesRan = true;
    if (!needsFrame) {
      _sleep();
      return;
    }
    final until = wakeTime;
    // A wait of two frames or less keeps the frames: dozing saves nothing.
    if (until != null && until - _frames.time > 2 / frameRate) {
      _frames.dozed();
      // Half a frame early, so the frame that shows the change is never
      // missed.
      final delay = (until - _frames.time - 0.5 / frameRate) * timeDilation;
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
    if (!_inFrame && !needsFrame) _sleep();
  }
}
