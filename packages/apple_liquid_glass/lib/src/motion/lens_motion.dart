import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motion/flex_integrator.dart';
import 'package:apple_liquid_glass/src/motion/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motion/flex_spec.dart';
import 'package:apple_liquid_glass/src/motion/glass_press.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The tuning of a selection lens, as measured on a UIKit control.
///
/// [segmented] and [tabBar] are fitted to frame-by-frame recordings of
/// UISegmentedControl and UITabBar on iOS 27; the two controls share the
/// travel and lift springs and differ in when they react, how far the lens
/// lifts and how strongly it deforms.
@internal
class LensTuning {
  /// Creates a tuning from explicit values.
  const LensTuning({
    required this.selectsOnPointerDown,
    required this.liftWidth,
    required this.liftHeight,
    required this.hangTime,
    required this.hangTimePerPixel,
    required this.hangFromTouch,
    required this.presentationSpring,
    required this.followSpring,
    required this.rubberBand,
    required this.pressDelay,
    this.pressHang = 0.25,
    this.releaseDelay = 0.03,
    this.travelSpring = const Spring.response(0.401, dampingRatio: 0.856),
    this.liftSpring = const Spring.response(0.25),
    this.startDelay = 0.02,
    this.flagLead = 0.025,
    this.hangReferenceDistance = 70,
    this.chromeFlexes = false,
    this.chromeLag = 0.02,
    this.chromeReleaseLag = 0.02,
    this.chromeLandingLag = 0.02,
    this.reducedMotionTravelSpring,
  });

  /// Whether a touch selects on contact (tab bar) or on release
  /// (segmented control).
  final bool selectsOnPointerDown;

  /// How many pixels the lens widens while lifted.
  final double liftWidth;

  /// How many pixels the lens grows taller while lifted.
  final double liftHeight;

  /// The spring that carries the lens between slots after a tap:
  /// 0.401/0.856 fitted to test/fixtures/ios27{,-device}/lens;
  /// lens_test.dart and lens_scrub_test.dart replay it.
  final Spring travelSpring;

  /// The spring that lifts and lands the lens and resizes it between
  /// slots of different widths.
  final Spring liftSpring;

  /// Seconds between a tap's selection and the start of the motion,
  /// counted from the touch's own time stamp.
  ///
  /// The tab bar's 0.045 is the median of 79 device taps (iPhone 16 Pro,
  /// `ios27-device/lens/tabbar*`, lift start fitted to the lift progress,
  /// 39 - 57 ms): UIKit delivers the touch 10 - 25 ms after its stamp,
  /// then sets up the lift on the main thread (the next display frame
  /// comes 26 - 39 ms after the one before instead of 8.3), and the lens
  /// moves from the frame after that. A touch on the selected tab shows
  /// the same setup before its [pressDelay].
  ///
  /// The segmented control's 0.04 is the median of 35 device taps on
  /// another segment, counted from the release that selects
  /// (`ios27-device/lens/segmented-*`, 31.5 - 56 ms): the same delivery and
  /// setup after the release (the next display frame comes 19.5 - 36 ms
  /// after the one before).
  final double startDelay;

  /// Seconds by which the deformation switches to its lifted response
  /// before the visible lift starts and before the visible landing.
  final double flagLead;

  /// Seconds a tapped lens stays lifted, counted from the start of the
  /// lift.
  final double hangTime;

  /// Whether [hangTime] counts from the touch that selected rather than
  /// from the start of the lift; the segmented control lands a fixed time
  /// after the release whatever the input latency.
  final bool hangFromTouch;

  /// Additional hang time per pixel of travel beyond
  /// [hangReferenceDistance].
  final double hangTimePerPixel;

  /// The travel distance at which [hangTime] applies unchanged.
  final double hangReferenceDistance;

  /// The spring that carries the deformation toward its target.
  ///
  /// The targets are UIKit's flex movement law for a loupe of the lens's
  /// size ([FlexSpec.loupeForSize] of the resting lens, or of the
  /// fully lifted one while it is lifted). Read from UIKit, notes private;
  /// fed UIKit's own filtered motion, the law reproduces the targets UIKit
  /// recorded on an iPhone 16 Pro (`ios27-device/lens`): scale x to
  /// 0.0053 / 0.0003 rms on the segmented control resting / lifted and
  /// 0.0028 / 0.00003 on the tab bar.
  final Spring presentationSpring;

  /// The spring that makes a dragged lens follow the finger.
  final Spring followSpring;

  /// The rubber band past the first and last slots as (limit, stiffness): a
  /// lens dragged past an end slot travels at most limit pixels beyond it, in
  /// the form of kinesis's `Band`. Inside the slots the lens follows the
  /// finger's travel since the touch one to one, in the control's own
  /// coordinates; a flexing control ([chromeFlexes]) scales and shifts the lens
  /// with it on top of that.
  final (double, double) rubberBand;

  /// Seconds between a touch on the selected item and the start of its
  /// lift, counted from the touch's own time stamp.
  ///
  /// The segmented control's 0.047 is the median of 8 device presses on
  /// the selected segment (lift start fitted to the lift progress, 33 -
  /// 80 ms: delivery, then UIKit setting the lift up on the main thread,
  /// the next display frame 21 - 65 ms after the one before). The tab
  /// bar's 0.05 is measured on its device taps on the selected tab.
  final double pressDelay;

  /// The shortest time, in seconds from the touch, a pressed selected
  /// lens stays lifted.
  final double pressHang;

  /// Seconds between the release of a held lens and the start of its
  /// travel to the chosen slot and of its landing, counted from the
  /// release's own time stamp.
  ///
  /// The segmented control's 0.024 minimizes the release travel rms of its
  /// four device drags together (0.130 pt; 0.030 left 0.496): a release
  /// sets nothing up, so the travel follows UIKit's delivery and begin
  /// frame, as the glass button's return does 26 ms after the release.
  final double releaseDelay;

  /// Whether the whole control flexes under a finger: UIKit's dynamic flex
  /// of the control's size ([FlexInteraction], spec
  /// [FlexSpec.forSize]), fed the finger's travel since the touch.
  ///
  /// The control grows by the spec's lift points along its long side, its
  /// short side in proportion; a dragging finger stretches it along the
  /// drag, narrows it across by as much and shifts it after the finger,
  /// four times as far per point the finger travels beyond the control's
  /// edge. The flex follows the finger on the spec's tracking spring and
  /// returns on its scale spring. Read from UIKit, notes private.
  ///
  /// The floating UITabBar flexes so (62 pt tall: 14.14 pt of growth, a
  /// stretch threshold of 8793, springs 0.314/0.625 and 0.36/0.6). On an
  /// iPhone 16 Pro (iOS 27.0.1, `ios27-device/lens/tabbar*`) a still
  /// finger holds the bar 14.06 - 14.14 pt wider (five holds), every still
  /// hold of the six scrubs (16 holds, 30 - 330 pt from the touch and up
  /// to 55 pt past the bar's end, bars of three and five tabs) sits within
  /// 0.04 pt of the law in width and 1e-4 in the scale across, and the
  /// scrubs replay at their stamps to 0.08 - 0.2 pt rms in width (a fixed
  /// growth of 14.6 left 0.49 - 2.06). The lens shows the bar's shift, so
  /// it follows the finger one to one.
  final bool chromeFlexes;

  /// Seconds between a touch and the start of the control's flex
  /// ([chromeFlexes]), counted from the touch's own time stamp.
  ///
  /// The tab bar's 0.0465 is the median of 34 device touches (iPhone 16
  /// Pro, `ios27-device/lens/tabbar{2,3,4,5}-taps` and `-tap-selected`: 29
  /// taps and 5 holds, the flex's steps on its tracking spring to and on
  /// its scale spring from the growth fitted to the bar's swell, 41.5 -
  /// 56.75 ms): the bar swells on the frame its lens starts (each touch 1.5
  /// ms before to 4 ms after its lens's lift start), after UIKit's delivery
  /// and its main-thread setup of the lift ([startDelay]).
  final double chromeLag;

  /// Seconds between the release of a touch and the return of the
  /// control's flex, counted from the release's own time stamp, when the
  /// release does not land a held lens ([chromeLandingLag]); the flex
  /// never returns before it starts.
  ///
  /// The tab bar's 0.0185 is the median of the 29 taps (12.75 - 32.75 ms):
  /// a release that leaves the lens to its hang sets nothing up, so the
  /// bar follows UIKit's delivery and begin frame, as the segmented
  /// control's travel does ([releaseDelay]). A touch shorter than the two
  /// lags apart does not swell the bar (unmeasured).
  final double chromeReleaseLag;

  /// Seconds between a release that lands a held lens and the return of
  /// the control's flex, counted from the release's own time stamp.
  ///
  /// The tab bar's 0.035 is the median of 11 device releases of a lens
  /// held 0.3 - 5 s (iPhone 16 Pro, `ios27-device/lens/tabbar*`: five
  /// holds and six scrubs, 25.25 - 41.5 ms, the return on the flex's scale
  /// spring fitted to the bar's swell): such a release sets the lens's
  /// landing up on the main thread (the display link's next frame comes
  /// 19 - 33 ms after the one before instead of 8.3), and the bar returns
  /// on the frame the lens starts landing (one of the 11 a frame later),
  /// as it swells on the frame the lens lifts ([chromeLag]). A release
  /// during a tap's hang ([hangTime], [pressHang]) sets nothing up
  /// ([chromeReleaseLag]).
  final double chromeLandingLag;

  /// The spring that carries the lens between slots, and after a dragging
  /// finger, for Reduce Motion; null when the selection does not travel
  /// then.
  ///
  /// UITabBar keeps moving its selection under Reduce Motion on dampingRatio
  /// 0.9, response 0.2 for taps and scrubs alike (its own springs are 0.85
  /// over 0.4 for a tap, which [travelSpring] fits, and 0.85 over 0.2 while
  /// scrubbing). UISegmentedControl disables its sliding selection: each
  /// segment shows its own, so the selection appears on the new segment
  /// and a press on the selected one neither lifts nor drags it. Read
  /// from UIKit, notes private; whether the segment's selection fades in
  /// is not recorded yet (it appears at once here).
  final Spring? reducedMotionTravelSpring;

  /// The lens of a UISegmentedControl.
  static const segmented = LensTuning(
    selectsOnPointerDown: false,
    liftWidth: 24,
    liftHeight: 16,
    hangTime: 0.25,
    hangTimePerPixel: 0,
    hangFromTouch: true,
    presentationSpring: Spring.response(0.442, dampingRatio: 0.582),
    followSpring: Spring.response(0.225),
    rubberBand: (12, 0.55),
    pressDelay: 0.047,
    releaseDelay: 0.024,
    startDelay: 0.04,
  );

  /// The lens of a floating UITabBar.
  static const tabBar = LensTuning(
    selectsOnPointerDown: true,
    liftWidth: 16,
    liftHeight: 16,
    hangTime: 0.215,
    hangTimePerPixel: 0.000274,
    hangFromTouch: false,
    presentationSpring: Spring.response(0.5, dampingRatio: 0.73),
    followSpring: Spring.response(0.271, dampingRatio: 0.803),
    rubberBand: (4.55, 0.95),
    pressDelay: 0.05,
    startDelay: 0.045,
    chromeFlexes: true,
    chromeLag: 0.0465,
    chromeReleaseLag: 0.0185,
    chromeLandingLag: 0.035,
    reducedMotionTravelSpring: Spring.response(0.2, dampingRatio: 0.9),
  );
}

/// A slot the lens can rest in: its center and width along the track.
typedef LensSlot = ({double center, double width});

/// The motion of a liquid selection lens: a pure function of the touches
/// it is fed and the time it is advanced to.
///
/// The lens frame rides three motion values on two springs: the travel
/// spring for the center, and the lift spring for the lift and for width
/// changes between slots.
/// On top of that runs UIKit's closed deformation loop: every frame the
/// visible center is filtered three times, the rate of change of its
/// speed becomes a drift of the lens's trailing edge plus a matching
/// stretch, and both follow their targets on a presentation spring. The
/// leading edge therefore rides the travel spring exactly. The loop steps
/// on a fixed [frameRate] in motion time, so the deformation is the same
/// on any display and under any time dilation.
///
/// A control that flexes ([LensTuning.chromeFlexes]) carries its own
/// flex of [chromeSize] under the finger, read as [chrome].
///
/// Feed pointer events with their timestamps and read [center], [size],
/// [scaleX] and [scaleY] at [now]: on screen the clock advances the motion,
/// in a test [advance] does. All lengths are pixels along the track, all
/// times seconds.
///
/// Every part rests within [MotionRest]: a scale over the lens's extent on
/// its own axis (the lifted width along the track, which holds while it
/// lands, and the current height across it), the lift over its largest
/// growth. The deformation loop sleeps once the lens is undeformed and
/// still. A finger held still counts: the lens rests lifted under it until
/// the finger moves or lifts. Each selection goes to [onEvent] as the
/// command that makes it runs.
@internal
final class LensMotion extends Motion {
  /// Creates a lens resting in [selected] among [slots].
  /// Empty slots have selection -1 and ignore input; other indices clamp
  /// to the available slots.
  ///
  /// [startDelay] overrides the tuning's delay between a selecting touch
  /// and the start of the motion. [chromeSize] is the size of the whole
  /// control, which flexes when the tuning says so.
  LensMotion({
    required this.tuning,
    required List<LensSlot> slots,
    required int selected,
    required this.height,
    this.frameRate = 120,
    bool reducedMotion = false,
    Size chromeSize = Size.zero,
    double? startDelay,
    this.onEvent,
  }) : startDelay = startDelay ?? tuning.startDelay,
       _slots = List.of(slots),
       _selected = _index(selected, slots.length),
       _restWidth = slots.isEmpty
           ? 0
           : slots[_index(selected, slots.length)].width {
    final slot = _slot;
    _travel = own(
      MotionValue<double>(slot.center, spring: tuning.travelSpring),
      rest: _length,
    );
    _width = own(
      MotionValue<double>(slot.width, spring: tuning.liftSpring),
      rest: _length,
    );
    _lift = own(
      MotionValue<double>(0, spring: tuning.liftSpring),
      rest: _liftRest,
    );
    _chrome = own(
      GlassPress(
        size: tuning.chromeFlexes ? chromeSize : Size.zero,
        law: FlexLaw(activationDelay: tuning.chromeLag),
      ),
    );
    _drift = own(
      MotionValue<double>(0, spring: tuning.presentationSpring),
      rest: _length,
    );
    _scaleX = own(
      MotionValue<double>(1, spring: tuning.presentationSpring),
      rest: _scaleXRest,
    );
    _scaleY = own(
      MotionValue<double>(1, spring: tuning.presentationSpring),
      rest: _scaleYRest,
    );
    _loop = own(_LensLoop(this, rate: frameRate));
    _previousVisible = slot.center;
    this.reducedMotion = reducedMotion;
  }

  /// The measured behavior this lens reproduces.
  final LensTuning tuning;

  /// The resting height of the lens.
  final double height;

  /// The frames per second of motion time the deformation loop steps at:
  /// 120 for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// Seconds between a selecting touch and the start of the motion.
  final double startDelay;

  /// Hears each selection the lens makes.
  final void Function(LensEvent event)? onEvent;

  /// Whether the lens moves for Reduce Motion: it never lifts, as UIKit's
  /// lens does not (read from UIKit, notes private), and travels on the
  /// tuning's [LensTuning.reducedMotionTravelSpring] or not at all.
  /// Its deformation and the control's flex staying off are
  /// approximations, not recorded yet.
  bool get reducedMotion => _reducedMotion;

  set reducedMotion(bool value) {
    _reducedMotion = value;
    _chrome.reducedMotion = value;
  }

  bool _reducedMotion = false;

  bool get _slides =>
      !reducedMotion || tuning.reducedMotionTravelSpring != null;

  Spring get _travelSpring => reducedMotion
      ? tuning.reducedMotionTravelSpring ?? tuning.travelSpring
      : tuning.travelSpring;

  void _travelTo(double t, LensSlot slot) {
    if (_slides) {
      _travel.retarget(t, slot.center, spring: _travelSpring);
      _width.retarget(t, slot.width);
    } else {
      _travel.snap(t, slot.center);
      _width.snap(t, slot.width);
    }
    _loop.wake(t);
  }

  static double _length() => MotionRest.length;

  double _liftRest() =>
      MotionRest.length /
      math.max(math.max(tuning.liftWidth, tuning.liftHeight), 1);

  double _scaleXRest() => MotionRest.scale(_restWidth + tuning.liftWidth);

  double _scaleYRest() => MotionRest.scale(size.height);

  List<LensSlot> _slots;
  int _selected;
  late final MotionValue<double> _travel;
  late final MotionValue<double> _width;
  late final MotionValue<double> _lift;
  late final GlassPress _chrome;
  _Pointer? _chromePointer;
  late final MotionValue<double> _drift;
  late final MotionValue<double> _scaleX;
  late final MotionValue<double> _scaleY;
  late final _LensLoop _loop;
  double _restWidth;

  final FlexIntegrator _flex = FlexIntegrator();
  Size? _loupeSize;
  FlexSpec _loupe = FlexSpec.smallLoupe;
  double? _previousVisible;
  bool _flag = false;

  _Pointer? _pointer;

  /// Whether the slot at an index can be selected; null makes every slot
  /// selectable.
  ///
  /// A touch landing on a slot that cannot be selected neither selects
  /// nor lifts the lens, but still swells the control (a disabled
  /// UITabBarItem on an iPhone 16 Pro, iOS 27.0.1: the bar grows under
  /// the finger, the lens stays). A drag released over such a slot
  /// returns to the selected one.
  bool Function(int index)? isSelectable;

  bool _selectable(int index) => isSelectable?.call(index) ?? true;

  /// The index of the selected slot, or -1 when there are no slots.
  int get selected => _selected;

  static int _index(int index, int count) =>
      count == 0 ? -1 : index.clamp(0, count - 1);

  LensSlot _slotFor(int index) => _slots.isEmpty
      ? (center: 0, width: 0)
      : _slots[_index(index, _slots.length)];

  LensSlot get _slot => _slotFor(_selected);

  /// The slots the lens can rest in.
  List<LensSlot> get slots => _slots;

  /// Replaces the slots, snapping the lens to the selected one.
  set slots(List<LensSlot> value) {
    _slots = List.of(value);
    _selected = _index(_selected, _slots.length);
    final slot = _slot;
    _travel.snap(now, slot.center);
    _width.snap(now, slot.width);
    _restWidth = slot.width;
    if (_slots.isEmpty) {
      unscheduleAll();
      _pointer = null;
      _flag = false;
      _lift.retarget(now, 0);
      _chrome.release(now);
    }
    _drift.snap(now, 0);
    _scaleX.snap(now, 1);
    _scaleY.snap(now, 1);
    _previousVisible = slot.center;
    _flex.reset(slot.center);
  }

  /// Replaces the slots after a change of the items around the lens, with
  /// [selected] its slot among them, at time [t].
  ///
  /// [shift] is how far the lens's coordinates moved under it along the
  /// track: the lens keeps its place on screen through it. On [spring] it
  /// then moves to its slot and takes the slot's width, as the items that
  /// stay do (not measured: UIKit's animated `insertSegment` and
  /// `setItems` were not captured); with no spring, an immediate one or a
  /// finger on the control, it snaps there as [slots] does.
  void reslot(
    double t,
    List<LensSlot> slots,
    int selected, {
    Spring? spring,
    double shift = 0,
  }) {
    advance(t);
    _selected = _index(selected, slots.length);
    if (spring == null ||
        spring.isImmediate ||
        _pointer != null ||
        slots.isEmpty ||
        _slots.isEmpty) {
      this.slots = slots;
      return;
    }
    _slots = List.of(slots);
    final slot = _slot;
    _restWidth = slot.width;
    if (shift != 0) {
      final velocity = _travel.velocityAt(t);
      _travel.snap(t, _travel.valueAt(t) + shift);
      _travel.setVelocity(t, velocity);
      _previousVisible = _visible(t);
      _flex.reset(_visible(t));
    }
    _travel.retarget(t, slot.center, spring: spring);
    _width.retarget(t, slot.width, spring: spring);
    _loop.wake(t);
  }

  /// The center the travel spring carries, before the deformation drift.
  double get travelCenter => _travel.valueAt(now);

  /// The visible center along the track, drift included.
  double get center => _visible(now);

  double _visible(double t) => _travel.valueAt(t) + _drift.valueAt(t);

  /// The lens bounds before the deformation scale: rest size plus lift.
  ({double width, double height}) get size {
    final lift = _lift.valueAt(now);
    return (
      width: _width.valueAt(now) + tuning.liftWidth * lift,
      height: height + tuning.liftHeight * lift,
    );
  }

  /// The deformation scale along the track.
  double get scaleX => _scaleX.valueAt(now);

  /// The deformation scale across the track.
  double get scaleY => _scaleY.valueAt(now);

  /// The lift progress, 0 resting and 1 fully lifted.
  double get lift => _lift.valueAt(now);

  /// The size of the whole control, which flexes under a finger when the
  /// tuning says so ([LensTuning.chromeFlexes]).
  Size get chromeSize => _chrome.size;

  set chromeSize(Size value) {
    if (tuning.chromeFlexes) _chrome.size = value;
  }

  /// The flex of the whole control now: its scales about its center and
  /// its drift along and across the track, [FlexInteraction.rest]
  /// exactly while it rests. The control shows the drift times the scale
  /// ([GlassPress.lean]).
  FlexValues get chrome => _chrome.values;

  /// Whether the finger currently drags the lens.
  bool get isDragging => _pointer?.dragging ?? false;

  /// The index of the slot under [x]: where slots overlap, as a tab bar's
  /// buttons do, the selected one if it is among them, else the first (read
  /// from UIKit; a lift 47 points from one tab and 38 from the next selected
  /// the first on an iPhone 16 Pro). Off every slot, the nearest.
  int slotAt(double x) {
    bool under(LensSlot slot) => (slot.center - x).abs() <= slot.width / 2;
    if (_selected >= 0 &&
        _selected < _slots.length &&
        under(_slots[_selected])) {
      return _selected;
    }
    for (var i = 0; i < _slots.length; i++) {
      if (under(_slots[i])) return i;
    }
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _slots.length; i++) {
      final distance = (_slots[i].center - x).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// A finger touched the track at [x], [y] across it; only the
  /// control's flex reads [y], in the control's own coordinates.
  void pointerDown(double t, double x, {double y = 0}) {
    advance(t);
    if (_slots.isEmpty || _pointer != null) return;
    final index = slotAt(x);
    if (!_selectable(index)) {
      final inert = _Pointer(offset: 0, pressedSelected: false, x: x);
      inert.inert = true;
      _pointer = inert;
      _pressChrome(t, inert, Offset(x, y));
      return;
    }
    final onSelected = index == _selected && _slides;
    final pointer = _Pointer(
      offset: center - x,
      pressedSelected: onSelected,
      x: x,
    );
    _pointer = pointer;
    _pressChrome(t, pointer, Offset(x, y));
    if (onSelected) {
      _flagOn(t);
      final liftAt = t + tuning.pressDelay;
      pointer.unliftNotBefore = t + tuning.pressHang;
      at(liftAt, (s) {
        if (!pointer.cancelled) _liftTo(s, 1);
      });
    } else if (tuning.selectsOnPointerDown) {
      pointer.pressedSelected = true;
      pointer.offset = 0;
      _selectWithLift(t, index, hold: true);
    }
  }

  /// A finger already on the control at [x], [y] across it takes the lens
  /// from where it rests and starts to drag it, selecting nothing until it
  /// lifts: a finger that slides off a tab bar's minimized circle.
  void pointerDrag(double t, double x, {double y = 0}) {
    advance(t);
    if (_slots.isEmpty || _pointer != null) return;
    final pointer = _Pointer(offset: 0, pressedSelected: true, x: x);
    pointer.dragging = true;
    pointer.unfollowed = true;
    _pointer = pointer;
    _pressChrome(t, pointer, Offset(x, y));
    _flagOn(t);
    pointer.unliftNotBefore = t + tuning.pressHang;
    at(t + tuning.pressDelay, (s) {
      if (!pointer.cancelled) _liftTo(s, 1);
    });
    _loop.wake(t);
  }

  /// The finger moved to [x], [y] across the track.
  void pointerMove(double t, double x, {double y = 0}) {
    advance(t);
    final pointer = _pointer;
    if (pointer != null && tuning.chromeFlexes) {
      _chrome.pointerMove(t, Offset(x, y));
    }
    if (pointer == null || !pointer.pressedSelected) return;
    pointer.dragging = true;
    pointer.x = x;
    pointer.unfollowed = true;
    _loop.wake(t);
  }

  /// The finger left the track at [x], [y] across it; the slot nearest the
  /// finger wins.
  void pointerUp(double t, double x, {double y = 0}) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    if (tuning.chromeFlexes) _chrome.pointerMove(t, Offset(x, y));
    final lands =
        pointer.pressedSelected &&
        !pointer.inert &&
        pointer.unliftNotBefore <= t + tuning.releaseDelay;
    _releaseChrome(
      t,
      pointer,
      lag: lands ? tuning.chromeLandingLag : tuning.chromeReleaseLag,
    );
    if (pointer.inert) return;
    final under = slotAt(x);
    final index = _selectable(under) ? under : _selected;
    if (pointer.pressedSelected) {
      if (index != _selected) _setSelected(index);
      final slot = _slots[_selected];
      _restWidth = slot.width;
      at(t + tuning.releaseDelay, (s) => _travelTo(s, _slotFor(index)));
      final unliftAt = math.max(
        t + tuning.releaseDelay,
        pointer.unliftNotBefore,
      );
      at(unliftAt - tuning.flagLead, (s) => _flag = false);
      at(unliftAt, (s) => _lift.retarget(s, 0));
    } else {
      _selectWithLift(t, index, hold: false);
    }
  }

  /// The touch was cancelled; the lens returns to the selected slot.
  void pointerCancel(double t) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    pointer.cancelled = true;
    _releaseChrome(t, pointer, lag: tuning.chromeReleaseLag);
    if (!pointer.pressedSelected) return;
    final slot = _slots[_selected];
    _travelTo(t, slot);
    _restWidth = slot.width;
    _flag = false;
    _lift.retarget(t, 0);
  }

  /// Selects the clamped [index] without a touch: the lens travels without
  /// lifting. With [notify] false, reconciles the parent's selection and
  /// cancels pending touch reactions without raising [LensSelected].
  void select(double t, int index, {bool notify = true}) {
    advance(t);
    if (_slots.isEmpty) return;
    final selected = _index(index, _slots.length);
    if (selected == _selected) return;
    if (!notify) {
      unscheduleAll();
      _flag = false;
      _lift.retarget(t, 0);
      if (_pointer == null) _chrome.release(t);
    }
    _selected = selected;
    if (notify) onEvent?.call(LensSelected(selected));
    final slot = _slots[selected];
    _flex.reset(_previousVisible ?? center);
    _travelTo(t, slot);
    _restWidth = slot.width;
  }

  /// Puts the lens at rest on the clamped [index] at once, without
  /// travel, lift or [LensSelected]: where a control that showed no selection
  /// shows one appear. Cancels a touch and pending reactions.
  void place(double t, int index) {
    advance(t);
    if (_slots.isEmpty) return;
    unscheduleAll();
    _pointer = null;
    _chrome.release(t);
    _flag = false;
    _selected = _index(index, _slots.length);
    _lift.snap(t, 0);
    slots = _slots;
  }

  void _frame(double t) {
    final pointer = _pointer;
    if (pointer != null && pointer.dragging) {
      _follow(t, pointer);
      pointer.unfollowed = false;
    }
    final visible = _visible(t);
    final previous = _previousVisible ?? visible;
    if (_flex.pf != null) {
      _flex.step(previous, _loop.frame);
      _retargetFlex(t);
    }
    _previousVisible = visible;
  }

  // Whether the deformation is still at [t] with nothing to follow:
  // undeformed, its targets at rest, the travel at rest and no move of the
  // finger waiting for the next frame.
  bool _still(double t) {
    if (_pointer?.unfollowed ?? false) return false;
    const length = MotionRest.length;
    final scaleX = _scaleXRest();
    final scaleY = _scaleYRest();
    return _travel.restsAt(t, length) &&
        _drift.target.abs() < length &&
        _drift.restsAt(t, length) &&
        (_scaleX.target - 1).abs() < scaleX &&
        _scaleX.restsAt(t, scaleX) &&
        (_scaleY.target - 1).abs() < scaleY &&
        _scaleY.restsAt(t, scaleY);
  }

  void _restDeformation(double t) {
    _drift.snap(t, 0);
    _scaleX.snap(t, 1);
    _scaleY.snap(t, 1);
    _previousVisible = _travel.target;
    _flex.reset(_travel.target);
  }

  void _retargetFlex(double t) {
    if (reducedMotion) {
      _drift.retarget(t, 0);
      _scaleX.retarget(t, 1);
      _scaleY.retarget(t, 1);
      return;
    }
    final width = _restWidth;
    if (width <= 0) return;
    final size = _flag
        ? Size(width + tuning.liftWidth, height + tuning.liftHeight)
        : Size(width, height);
    if (size != _loupeSize) {
      _loupeSize = size;
      _loupe = FlexSpec.loupeForSize(size);
    }
    final v = FlexInteraction.withMovement(
      FlexInteraction.rest,
      spec: _loupe,
      size: size,
      acceleration: Offset(_flex.af, 0),
      velocity: Offset(_flex.vf, 0),
    );
    _drift.retarget(t, v.driftX);
    _scaleX.retarget(t, v.scaleX);
    _scaleY.retarget(t, v.scaleY);
  }

  void _follow(double t, _Pointer pointer) {
    final first = _slots.first.center;
    final last = _slots.last.center;
    final u = pointer.x + pointer.offset;
    final (limit, stiffness) = tuning.rubberBand;
    final target = Band(
      first,
      last,
      dimension: limit,
      coefficient: stiffness,
    ).show(u);
    _travel.retarget(
      t,
      target,
      spring: reducedMotion
          ? tuning.reducedMotionTravelSpring ?? tuning.followSpring
          : tuning.followSpring,
    );
    final under = slotAt(_travel.valueAt(t));
    if (_slots[under].width != _width.target) {
      _width.retarget(t, _slots[under].width);
      _restWidth = _slots[under].width;
    }
  }

  void _selectWithLift(double t, int index, {required bool hold}) {
    final from = _slots[_selected].center;
    if (index != _selected) _setSelected(index);
    final slot = _slots[index];
    _flagOn(t);
    final start = t + startDelay;
    final distance = (slot.center - from).abs();
    final hang =
        tuning.hangTime +
        tuning.hangTimePerPixel *
            math.max(0, distance - tuning.hangReferenceDistance);
    _restWidth = slot.width;
    at(start, (s) {
      _travelTo(s, _slotFor(index));
      _liftTo(s, 1);
    });
    final landing = (tuning.hangFromTouch ? t : start) + hang;
    if (hold) {
      _pointer?.unliftNotBefore = landing;
    } else {
      at(landing - tuning.flagLead, (s) => _flag = false);
      at(landing, (s) => _lift.retarget(s, 0));
    }
  }

  void _flagOn(double t) {
    _flag = true;
    _flex.reset(_previousVisible ?? center);
  }

  void _pressChrome(double t, _Pointer pointer, Offset at) {
    if (!tuning.chromeFlexes) return;
    _chromePointer = pointer;
    pointer.swellsAt = t + tuning.chromeLag;
    _chrome.pointerDown(t, at);
  }

  void _releaseChrome(double t, _Pointer pointer, {required double lag}) {
    if (!tuning.chromeFlexes) return;
    at(math.max(t + lag, pointer.swellsAt), (s) {
      if (identical(_chromePointer, pointer)) _chrome.release(s);
    });
  }

  void _liftTo(double t, double target) {
    _lift.retarget(t, reducedMotion ? 0 : target);
  }

  void _setSelected(int index) {
    _selected = index;
    onEvent?.call(LensSelected(index));
  }
}

/// Steps the lens's deformation loop at its frame rate while the lens
/// travels, deforms or follows a finger; at rest it snaps the lens flat
/// onto its travel and primes the filter there.
final class _LensLoop extends MotionLoop {
  _LensLoop(this._lens, {required super.rate});

  final LensMotion _lens;

  @override
  bool step(double t) {
    _lens._frame(t);
    return !_lens._still(t);
  }

  @override
  void restFrom(double t) {
    super.restFrom(t);
    _lens._restDeformation(_lens.now);
  }
}

class _Pointer {
  _Pointer({
    required this.offset,
    required this.pressedSelected,
    required this.x,
  });

  double offset;
  bool pressedSelected;
  bool dragging = false;
  bool cancelled = false;
  bool inert = false;
  double x;
  double unliftNotBefore = 0;
  double swellsAt = 0;

  // A move the lens has not followed yet: the next frame follows it.
  bool unfollowed = false;
}

/// What a [LensMotion] tells its host.
sealed class LensEvent {
  const LensEvent();
}

/// The selection changed to [index].
final class LensSelected extends LensEvent {
  /// Creates the event.
  const LensSelected(this.index);

  /// The selected slot.
  final int index;
}
