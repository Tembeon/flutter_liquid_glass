import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// UIKit's tuning for glass bar items that change: the
/// `GlassContainerToolbarPTSettings` iOS 27 runs when a toolbar's items
/// are replaced and when a navigation bar's buttons change on a push or
/// a pop.
///
/// Read live from the tuning (springs in SwiftUI's duration / bounce
/// terms, here as response / damping ratio = 1 - bounce) and placed in
/// time by the frame-by-frame recordings of `setToolbarItems(_:animated:)`
/// and of pushes.
@internal
@immutable
class GlassBarTransitionSpec {
  /// Creates a spec from explicit values.
  const GlassBarTransitionSpec({
    this.frameSpring = const Spring.response(0.416, dampingRatio: 0.75),
    this.frameDelay = 0.05,
    this.birthStaggerDelay = 0.1,
    this.contentSpring = const Spring.response(0.416, dampingRatio: 0.75),
    this.contentDelay = 0.05,
    this.appearScale = 0.2,
    this.appearBlur = 10,
    this.pulseDelay = 0.065,
    this.pulseUpSpring = const Spring.response(0.292, dampingRatio: 0.5),
    this.pulseMaxScale = 1.2,
    this.pulseMaxPoints = 16,
    this.pulseHeightDownDelay = 0.113,
    this.pulseHeightDownSpring = const Spring.response(
      0.416,
      dampingRatio: 0.584,
    ),
    this.pulseWidthDownDelay = 0.142,
    this.pulseWidthDownSpring = const Spring.response(0.416, dampingRatio: 0.5),
    this.segmentDelay = 0.030,
    this.oversizedInPlace = true,
  });

  /// The spring a capsule's frame moves on: `transition.springDuration`
  /// 0.416 s, bounce 0.25.
  final Spring frameSpring;

  /// The time from the change to the start of the frame motion, in
  /// seconds (fitted jointly to the device and simulator recordings of
  /// `setToolbarItems(_:animated:)`, measured from the call).
  final double frameDelay;

  /// The time from the change to the start of the frame motion of a
  /// capsule that moves while a capsule of its side grows out of a
  /// survivor, in seconds: the survivor waits for the newborn (fitted
  /// 0.1 s; the tuning's `transition.minDelay` / `maxDelay` are 0.083 /
  /// 0.166).
  final double birthStaggerDelay;

  /// The spring items appear, leave and travel on (fitted 0.40 / 0.80 on
  /// the recordings, the transition spring within that spread).
  final Spring contentSpring;

  /// The time from the change to the start of the item motion, in
  /// seconds (fitted).
  final double contentDelay;

  /// The scale an item or a capsule is born at and leaves at:
  /// `appearance.scale`.
  final double appearScale;

  /// The blur of an item that is born or leaves, at its smallest:
  /// `appearance.blurRadius`.
  final double appearBlur;

  /// The time from the change to the start of the size pulse, in seconds
  /// (fitted 0.065 s from the call; a frame or two before the tuning's
  /// `transition.minDelay` 0.083, which counts from the commit).
  final double pulseDelay;

  /// The spring a changed capsule swells on: `scalePulse.scaleUp` 0.292 s,
  /// bounce 0.5.
  final Spring pulseUpSpring;

  /// The largest relative swell: `scalePulse.maxScaleWidth/Height`.
  final double pulseMaxScale;

  /// The largest swell in points: `scalePulse.maxPointScaleWidth/Height`.
  final double pulseMaxPoints;

  /// The time from the start of the swell to the return of the height:
  /// `scalePulse.scaleDownHeightDelay`.
  final double pulseHeightDownDelay;

  /// The spring the height returns on: 0.416 s, bounce 0.416.
  final Spring pulseHeightDownSpring;

  /// The time from the start of the swell to the return of the width:
  /// `scalePulse.scaleDownWidthDelay`.
  final double pulseWidthDownDelay;

  /// The spring the width returns on: 0.416 s, bounce 0.5.
  final Spring pulseWidthDownSpring;

  /// The time from the change to the start of a group that appears or
  /// leaves in place, in seconds: on a side of the bar that had no group
  /// or keeps none, or too large for its survivor (see [oversizedInPlace]).
  ///
  /// Such a group does not grow out of a neighbour: it stands at its own
  /// place, scaled by [pulseScaleFor] its length per axis, blurred by
  /// [appearBlur] and transparent, and comes in (or goes) on
  /// [frameSpring], scale, opacity and blur on one progress (free fits
  /// 0.39 - 0.41 s / 0.75 - 0.77 over 16 groups). Fitted to
  /// `setToolbarItems(_:animated:)` filling and emptying a toolbar side:
  /// 0.020 - 0.044 s from the call, replay optimum 0.026 - 0.030 (iPhone
  /// 16 Pro, iOS 27.0.1).
  final double segmentDelay;

  /// Whether a group too large for the group it would grow out of (or
  /// shrink into) appears (or leaves) in place instead.
  ///
  /// A group born beside a group of its side that stays grows out of that
  /// survivor: its own box fitted inside the survivor's box before the
  /// change (the size of each axis at most the survivor's, the place as
  /// near its own as fits), at [appearScale]; a group that goes shrinks
  /// into the survivor's box after the change the same way. When the group
  /// is wider or taller than the survivor, a toolbar shows it in place
  /// (`setToolbarItems(_:animated:)`: `[reply share folder]` beside `[compose]`
  /// or `[heart]` in place, `[heart]` out of `[Show Preferences]` and out of
  /// `[compose]`), while a navigation bar still grows it out of the
  /// survivor's own box (`[plus more]` out of `[1x]` on a push, back into it on
  /// a pop; iPhone 16 Pro, iOS 27.0.1, probe scene navseg set b).
  final bool oversizedInPlace;

  /// iOS 27's values for a toolbar whose items are replaced.
  static const standard = GlassBarTransitionSpec();

  /// iOS 27's values for a navigation bar on a push or a pop, which starts
  /// later than a toolbar's item replacement: the capsules' frames after
  /// 0.062 s (center replay optimum 0.060 - 0.062 over four pushes and
  /// four pops), groups coming or going in place after 0.058 s (0.050 -
  /// 0.063 over eight groups, replay optimum 0.058), measured from the
  /// `pushViewController` / `popViewController` call.
  static const navigation = GlassBarTransitionSpec(
    frameDelay: 0.062,
    segmentDelay: 0.058,
    oversizedInPlace: false,
  );

  /// The swell of a capsule [length] long, as a factor.
  double pulseScaleFor(double length) =>
      length <= 0 ? 1 : math.min(pulseMaxScale, 1 + pulseMaxPoints / length);
}

/// Where one item of a bar sits in a layout handed to [GlassBarMotion].
@internal
@immutable
class GlassBarItemLayout {
  /// Creates an item layout.
  const GlassBarItemLayout(this.id, this.rect);

  /// The identity of the item across layouts.
  final Object id;

  /// The item's box in the bar's coordinates.
  final Rect rect;
}

/// One glass capsule of a bar layout handed to [GlassBarMotion]: a group
/// of items that share one piece of glass.
@internal
@immutable
class GlassBarCapsuleLayout {
  /// Creates a capsule layout.
  const GlassBarCapsuleLayout(
    this.id,
    this.rect,
    this.items, {
    this.segment,
    this.anonymous = false,
  });

  /// The identity of the capsule across layouts.
  final Object id;

  /// Whether the capsule has no identity of its own, as a group without an
  /// id: it then continues the capsule without one of its segment whose
  /// center lies nearest (UIKit's bar groups carry no identity across a
  /// push: `[plus more]` `[1x]` -> `[Show Preferences]` keeps the inner group's
  /// glass, the nearer one).
  final bool anonymous;

  /// The side of the bar the capsule belongs to, such as its leading or
  /// trailing groups; null puts every such capsule on one side.
  ///
  /// A capsule changes only into a capsule of its own segment: an [id]
  /// found in another segment is a new capsule, and a newborn grows out of
  /// a capsule of its segment that stays only. When a segment keeps no
  /// capsule through the change, its capsules appear and leave in place
  /// (see [GlassBarTransitionSpec.segmentDelay]).
  final Object? segment;

  /// The capsule's box in the bar's coordinates.
  final Rect rect;

  /// The items in the capsule.
  final List<GlassBarItemLayout> items;
}

/// A capsule of a bar in one frame.
@internal
@immutable
class GlassBarCapsuleFrame {
  /// Creates a frame.
  const GlassBarCapsuleFrame(
    this.id,
    this.rect, {
    required this.leaving,
    this.segment,
    this.opacity = 1,
    this.apart = false,
  });

  /// The identity of the capsule.
  final Object id;

  /// The capsule's box, swell included.
  final Rect rect;

  /// Whether the capsule is on its way out.
  final bool leaving;

  /// The segment of the capsule's layout.
  final Object? segment;

  /// How present the capsule's glass is, 0 to 1.
  final double opacity;

  /// Whether the capsule appears or leaves in place: UIKit draws it in a
  /// glass container of its own, so it never fuses with the other
  /// capsules of the bar.
  final bool apart;
}

/// An item of a bar in one frame.
@internal
@immutable
class GlassBarItemFrame {
  /// Creates a frame.
  const GlassBarItemFrame(
    this.id, {
    required this.center,
    required this.size,
    required this.scale,
    required this.presence,
    required this.blur,
    required this.leaving,
  });

  /// The identity of the item.
  final Object id;

  /// The center of the item.
  final Offset center;

  /// The item's laid-out size; [scale] applies on top.
  final Size size;

  /// The scale the item is drawn at.
  final double scale;

  /// How present the item is, 0 gone and 1 fully there; UIKit draws it at
  /// this opacity.
  final double presence;

  /// The blur the item is drawn with, in logical pixels.
  final double blur;

  /// Whether the item is on its way out.
  final bool leaving;
}

/// The identity a capsule on its way out takes when a capsule of the new
/// layout carries the id it had.
@internal
class GlassBarDepartedId {
  /// Wraps the [id] a leaving capsule had.
  GlassBarDepartedId(this.id);

  /// The id the capsule had.
  final Object id;

  @override
  String toString() => 'GlassBarDepartedId($id)';
}

// A capsule's identity across layouts: the key of its item in the
// capsules' layout motion.
final class _Capsule {
  _Capsule(this.id, this.segment, {required this.anonymous});

  Object id;
  final Object? segment;
  final bool anonymous;

  // Appears or leaves in place, in a glass container of its own.
  bool apart = false;
}

final class _Planner extends LayoutPlanner {
  _Planner(this._plan);

  final Map<Object, LayoutPlan> Function(LayoutChange change) _plan;

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) => _plan(change);
}

/// The motion of a glass bar whose items change: iOS 27's toolbar and
/// navigation bar item transition.
///
/// Feed it layouts with [setLayout]. A capsule that keeps its identity
/// moves and resizes to its new box on [GlassBarTransitionSpec.frameSpring]
/// and, when its items changed, swells by up to 16 points (20 percent at
/// most) and settles back - the height first, then the width. Items that
/// stay travel to their new place; new items appear at the old center of
/// their capsule, at a fifth of their size, blurred and transparent, and
/// grow into place; leaving items shrink, blur and fade into the new
/// center of their capsule. Every value retargets from its current state,
/// so a change in the middle of another change is continuous.
///
/// Capsules change only within their [GlassBarCapsuleLayout.segment]: the
/// leading groups of a bar into leading groups, the trailing ones into
/// trailing ones. A capsule with an id continues the capsule of its
/// segment with that id; an [GlassBarCapsuleLayout.anonymous] one the
/// nearest anonymous capsule of its segment.
///
/// One law places every capsule that comes or goes. A new capsule grows
/// out of the nearest capsule of its segment that stays: its own box
/// fitted inside that survivor's box before the change, at a fifth of the
/// fitted size; a capsule that goes shrinks into the survivor's box after
/// the change the same way, so it vanishes inside it. The survivor swells
/// as if its items changed. A capsule with no survivor on its side - and,
/// with [GlassBarTransitionSpec.oversizedInPlace], one too large for its
/// survivor - appears in place, swollen, blurred and transparent, settling
/// in, or swells and fades where it stands (see
/// [GlassBarTransitionSpec.segmentDelay]). Such capsules are
/// [GlassBarCapsuleFrame.apart]: they never fuse with the others.
///
/// The capsules and the items are two [LayoutMotion]s: the capsules' plan
/// is the law above, the items' follows it, and a frame composes an item
/// with its capsule's swell, lean and presence.
///
/// [setDrift] leans the capsules part of the way toward another layout
/// without changing the layout itself, as a navigation bar does during an
/// interactive pop; the next [setLayout] starts from where the drift put
/// them.
///
/// Times are seconds, positions logical pixels in the bar's own space.
@internal
final class GlassBarMotion extends Motion {
  /// Creates the motion with [spec].
  GlassBarMotion({this.spec = GlassBarTransitionSpec.standard});

  /// The tuning of the latest change.
  GlassBarTransitionSpec spec;

  /// Whether the platform asks for reduced motion: changes then snap.
  bool reducedMotion = false;

  late final LayoutMotion _capsules = own(
    LayoutMotion(planner: _Planner(_planCapsules)),
  );
  late final LayoutMotion _items = own(
    LayoutMotion(planner: _Planner(_planItems)),
  );
  final Map<Object, _Capsule> _capsuleOf = {};
  bool _hasLayout = false;
  Map<Object, Rect> _driftTo = const {};
  List<GlassBarCapsuleLayout>? _driftPaired;
  double _drift = 0;

  // The change being planned: the capsule each of its layouts goes to, the
  // capsule of each of its items, and what the capsules' plan decided.
  Map<_Capsule, GlassBarCapsuleLayout> _layoutOf = const {};
  Map<Object, _Capsule> _nextCapsuleOf = const {};
  Map<_Capsule, Offset> _births = const {};
  Map<_Capsule, Offset> _deaths = const {};
  Map<_Capsule, Offset> _oldCenters = const {};
  Set<_Capsule> _bornInPlace = const {};

  Iterable<_Capsule> get _all => _capsules.ids.cast<_Capsule>();

  @override
  void didAdvance(double t) {
    for (final c in _all) {
      if (c.apart && !_capsules.isLeaving(c) && _capsules.presenceRests(c)) {
        c.apart = false;
      }
    }
  }

  /// Pairs the capsules of [layout] (all but [skip]) with the [candidates]
  /// that continue into them: a capsule with an id continues the
  /// candidate of its segment with that id, an anonymous one the anonymous
  /// candidate of its segment whose place ([from]) lies nearest, nearest
  /// pairs first.
  Map<int, _Capsule> _pair(
    List<GlassBarCapsuleLayout> layout,
    List<_Capsule> candidates,
    Rect Function(_Capsule c) from, {
    Set<int> skip = const {},
  }) {
    final out = <int, _Capsule>{};
    final taken = <_Capsule>{};
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      if (c.anonymous || skip.contains(k)) continue;
      for (final candidate in candidates) {
        if (!candidate.anonymous &&
            candidate.id == c.id &&
            candidate.segment == c.segment &&
            !taken.contains(candidate)) {
          out[k] = candidate;
          taken.add(candidate);
          break;
        }
      }
    }
    final pairs = <(double, int, int)>[];
    for (var k = 0; k < layout.length; k++) {
      final c = layout[k];
      if (!c.anonymous || skip.contains(k)) continue;
      for (var n = 0; n < candidates.length; n++) {
        final candidate = candidates[n];
        if (!candidate.anonymous || candidate.segment != c.segment) continue;
        pairs.add(((from(candidate).center - c.rect.center).distance, k, n));
      }
    }
    pairs.sort(
      (a, b) => switch (a.$1.compareTo(b.$1)) {
        0 => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3),
        final order => order,
      },
    );
    for (final (_, k, n) in pairs) {
      final candidate = candidates[n];
      if (out.containsKey(k) || taken.contains(candidate)) continue;
      out[k] = candidate;
      taken.add(candidate);
    }
    return out;
  }

  /// The box of [size] at [center] moved and cut to lie inside [into]:
  /// each axis at most as long as [into]'s, as near [center] as it fits.
  static Rect _inside(Size size, Offset center, Rect into) {
    final w = math.min(size.width, into.width);
    final h = math.min(size.height, into.height);
    double fit(double v, double lo, double hi) =>
        math.min(math.max(v, lo), math.max(lo, hi));
    return Rect.fromCenter(
      center: Offset(
        fit(center.dx, into.left + w / 2, into.right - w / 2),
        fit(center.dy, into.top + h / 2, into.bottom - h / 2),
      ),
      width: w,
      height: h,
    );
  }

  /// Whether a capsule of [size] grows out of (or shrinks into) a survivor
  /// whose box is [into] rather than appearing (or leaving) in place.
  bool _fits(Size size, Rect into) =>
      !spec.oversizedInPlace ||
      (size.width <= into.width + 1e-6 && size.height <= into.height + 1e-6);

  Rect _shrunk(Rect box) => Rect.fromCenter(
    center: box.center,
    width: box.width * spec.appearScale,
    height: box.height * spec.appearScale,
  );

  LayoutAccent _pulse(Size size) => LayoutAccent(
    scale: Size(
      spec.pulseScaleFor(size.width),
      spec.pulseScaleFor(size.height),
    ),
    up: spec.pulseUpSpring,
    delay: spec.pulseDelay,
    widthDown: spec.pulseWidthDownSpring,
    widthDownDelay: spec.pulseWidthDownDelay,
    heightDown: spec.pulseHeightDownSpring,
    heightDownDelay: spec.pulseHeightDownDelay,
  );

  /// Leans every capsule that [toward] also has (paired as [setLayout]
  /// pairs them) [amount] of the way from where it is toward its box there,
  /// its items riding along; null or 0 removes the lean at once.
  ///
  /// The lean is drawn on top of the motion, a pure function of [amount];
  /// a [setLayout] while leaning starts from the leaning capsules. The
  /// pairing is kept while [toward] is the same list and the layout has
  /// not changed, so a lean that follows a gesture pairs once.
  void setDrift(List<GlassBarCapsuleLayout>? toward, double amount) {
    if (toward == null || amount == 0) {
      _driftTo = const {};
      _driftPaired = null;
      _drift = 0;
      _capsules.lean(null, 0);
      return;
    }
    if (!identical(toward, _driftPaired)) {
      _driftPaired = toward;
      final live = [
        for (final c in _all)
          if (!_capsules.isLeaving(c)) c,
      ];
      _driftTo = {
        for (final MapEntry(key: k, value: c) in _pair(
          toward,
          live,
          (c) => _capsules.laidOut(c)!,
        ).entries)
          c: toward[k].rect,
      };
    }
    _drift = amount;
    _capsules.lean(_driftTo, amount);
  }

  /// Whether capsules lean toward a [setDrift] layout.
  bool get isDrifting => _drift != 0 && _driftTo.isNotEmpty;

  /// Ends a [setDrift] lean at time [t] without a jump: the capsules spring
  /// home on [GlassBarTransitionSpec.frameSpring] from where they lean.
  void endDrift(double t) {
    advance(t);
    _keepDrift(t, commit: false);
  }

  void _keepDrift(double t, {required bool commit}) {
    _driftPaired = null;
    if (isDrifting) {
      final riding = <Object, Rect>{
        for (final id in _items.ids)
          if (!_items.isLeaving(id))
            if (_capsuleOf[id] case final c?)
              if (_capsules.leanOf(c) case final d when d != Offset.zero)
                id: _items.itemAt(id).rect.shift(d),
      };
      _items.lean(riding, 1);
      _items.endLean(t, commit: commit);
      _capsules.endLean(t, commit: commit);
    } else {
      _capsules.lean(null, 0);
    }
    _driftTo = const {};
    _drift = 0;
  }

  /// Shows [layout] from time [t], under [transition] when given; with
  /// [animated] false (and on the first layout) everything snaps.
  void setLayout(
    double t,
    List<GlassBarCapsuleLayout> layout, {
    bool animated = true,
    GlassBarTransitionSpec? transition,
  }) {
    if (transition != null) spec = transition;
    advance(t);
    _capsuleOf.removeWhere((id, _) => !_items.contains(id));
    if (!_hasLayout || !animated || reducedMotion) {
      _hasLayout = true;
      _snap(t, layout);
      return;
    }
    _keepDrift(t, commit: true);
    final live = [
      for (final c in _all)
        if (!_capsules.isLeaving(c)) c,
    ];
    final paired = _pair(layout, live, (c) => _capsules.laidOut(c)!);
    final leaving = [
      for (final c in _all)
        if (_capsules.isLeaving(c)) c,
    ];
    paired.addAll(
      _pair(
        layout,
        leaving,
        (c) => _capsules.itemAt(c).rect,
        skip: paired.keys.toSet(),
      ),
    );
    final resolved = [
      for (var k = 0; k < layout.length; k++)
        if (paired[k] case final existing?)
          existing
        else
          _Capsule(
            layout[k].id,
            layout[k].segment,
            anonymous: layout[k].anonymous,
          ),
    ];
    for (var k = 0; k < layout.length; k++) {
      if (resolved[k].anonymous) resolved[k].id = layout[k].id;
    }
    final liveIds = {for (final c in resolved) c.id};
    for (final c in _all) {
      if (!resolved.contains(c) && liveIds.contains(c.id)) {
        c.id = GlassBarDepartedId(c.id);
      }
    }
    _layoutOf = {
      for (var k = 0; k < layout.length; k++) resolved[k]: layout[k],
    };
    _nextCapsuleOf = {
      for (var k = 0; k < layout.length; k++)
        for (final item in layout[k].items) item.id: resolved[k],
    };
    _capsules.layout(t, {
      for (var k = 0; k < layout.length; k++) resolved[k]: layout[k].rect,
    }, spring: spec.frameSpring);
    _items.layout(t, {
      for (final c in layout)
        for (final item in c.items) item.id: item.rect,
    }, spring: spec.contentSpring);
    _capsuleOf.addAll(_nextCapsuleOf);
    _layoutOf = const {};
    _nextCapsuleOf = const {};
  }

  Map<Object, LayoutPlan> _planCapsules(LayoutChange change) {
    if (change.spring == null) return const {};
    final spring = spec.frameSpring;
    final entries = change.entries;
    final survivors = {
      for (final MapEntry(:key, :value) in entries.entries)
        if (value.phase == LayoutPhase.staying) key as _Capsule: value,
    };
    (_Capsule, Rect)? nearestSurvivor(
      Object? segment,
      Offset from, {
      required bool after,
    }) {
      (_Capsule, Rect)? best;
      var distance = double.infinity;
      for (final MapEntry(key: c, value: entry) in survivors.entries) {
        if (c.segment != segment) continue;
        final d = (entry.to!.center - from).distance;
        if (d < distance) {
          distance = d;
          best = (c, after ? entry.to! : entry.shown!);
        }
      }
      return best;
    }

    final plans = <Object, LayoutPlan>{};
    final births = <_Capsule, Offset>{};
    final bornInPlace = <_Capsule>{};
    final hosts = <_Capsule>{};
    final birthSegments = <Object?>{};
    for (final MapEntry(:key, value: entry) in entries.entries) {
      if (entry.phase != LayoutPhase.entering || entry.shown != null) continue;
      final c = key as _Capsule;
      final to = entry.to!;
      final (host, source) =
          nearestSurvivor(c.segment, to.center, after: false) ??
          (null, Rect.zero);
      if (host != null && _fits(to.size, source)) {
        final box = _inside(to.size, to.center, source);
        births[c] = box.center;
        hosts.add(host);
        birthSegments.add(c.segment);
        plans[c] = LayoutPlan(
          spring: spring,
          delay: spec.frameDelay,
          origin: _shrunk(box),
          accent: _pulse(to.size),
        );
      } else {
        c.apart = true;
        bornInPlace.add(c);
        plans[c] = LayoutPlan(spring: spring, delay: spec.segmentDelay);
      }
    }
    final deaths = <_Capsule, Offset>{};
    for (final MapEntry(:key, value: entry) in entries.entries) {
      if (entry.phase != LayoutPhase.leaving) continue;
      final c = key as _Capsule;
      final here = entry.shown!.center;
      final size = entry.from!.size;
      final (host, sink) =
          nearestSurvivor(c.segment, here, after: true) ?? (null, Rect.zero);
      if (host == null || !_fits(size, sink)) {
        c.apart = true;
        plans[c] = LayoutPlan(spring: spring, delay: spec.segmentDelay);
        continue;
      }
      final box = _inside(size, here, sink);
      deaths[c] = box.center;
      hosts.add(host);
      plans[c] = LayoutPlan(
        spring: spring,
        delay: spec.frameDelay,
        destination: _shrunk(box),
        rest: _landing,
      );
    }
    for (final MapEntry(:key, value: entry) in entries.entries) {
      if (entry.phase == LayoutPhase.leaving || plans.containsKey(key)) {
        continue;
      }
      final c = key as _Capsule;
      final target = _layoutOf[c]!;
      final moves = _capsules.laidOut(c) != target.rect;
      final changed = hosts.contains(c) || _itemsChanged(c, target.items);
      plans[c] = LayoutPlan(
        spring: spring,
        delay: entry.phase == LayoutPhase.entering && c.apart
            ? spec.segmentDelay
            : birthSegments.contains(c.segment) && moves
            ? spec.birthStaggerDelay
            : spec.frameDelay,
        accent: changed ? _pulse(target.rect.size) : null,
      );
    }
    _births = births;
    _deaths = deaths;
    _bornInPlace = bornInPlace;
    _oldCenters = {
      for (final MapEntry(key: c, value: entry) in survivors.entries)
        c: entry.shown!.center,
    };
    return plans;
  }

  // Finer than the visible rest: the device replacement replay keeps the
  // remaining capsules' centers within 1.2 pt rms only when a shrunk
  // capsule is dropped at a 0.05 pt landing or later (0.1 pt gives 1.31).
  static const double _landing = 0.05;

  bool _itemsChanged(_Capsule capsule, List<GlassBarItemLayout> items) {
    final next = {for (final i in items) i.id};
    final before = [
      for (final id in _items.ids)
        if (identical(_capsuleOf[id], capsule) &&
            (!_items.isLeaving(id) || next.contains(id)))
          id,
    ];
    if (before.length != items.length) return true;
    for (var k = 0; k < items.length; k++) {
      if (before[k] != items[k].id) return true;
    }
    return false;
  }

  Map<Object, LayoutPlan> _planItems(LayoutChange change) {
    if (change.spring == null) return const {};
    final spring = spec.contentSpring;
    final delay = spec.contentDelay;
    final plans = <Object, LayoutPlan>{};
    for (final MapEntry(key: id, value: entry) in change.entries.entries) {
      switch (entry.phase) {
        case LayoutPhase.leaving:
          final c = _capsuleOf[id];
          final end =
              (c == null ? null : _deaths[c] ?? _layoutOf[c]?.rect.center) ??
              entry.shown!.center;
          plans[id] = LayoutPlan(
            spring: spring,
            delay: delay,
            destination: Rect.fromCenter(
              center: end,
              width: entry.from!.width,
              height: entry.from!.height,
            ),
          );
        case LayoutPhase.entering when entry.shown == null:
          final c = _nextCapsuleOf[id]!;
          final to = entry.to!;
          if (_bornInPlace.contains(c)) {
            plans[id] = const LayoutPlan();
            continue;
          }
          final start = _oldCenters[c] ?? _births[c] ?? to.center;
          plans[id] = LayoutPlan(
            spring: spring,
            delay: delay,
            origin: Rect.fromCenter(
              center: start,
              width: to.width,
              height: to.height,
            ),
          );
        case LayoutPhase.entering || LayoutPhase.staying:
          plans[id] = LayoutPlan(spring: spring, delay: delay);
      }
    }
    return plans;
  }

  void _snap(double t, List<GlassBarCapsuleLayout> layout) {
    _driftTo = const {};
    _driftPaired = null;
    _drift = 0;
    _capsules.lean(null, 0);
    final capsules = [
      for (final c in layout) _Capsule(c.id, c.segment, anonymous: c.anonymous),
    ];
    _capsules.layout(t, {
      for (var k = 0; k < layout.length; k++) capsules[k]: layout[k].rect,
    }, jump: true);
    _items.layout(t, {
      for (final c in layout)
        for (final item in c.items) item.id: item.rect,
    }, jump: true);
    _capsuleOf.clear();
    for (var k = 0; k < layout.length; k++) {
      for (final item in layout[k].items) {
        _capsuleOf[item.id] = capsules[k];
      }
    }
  }

  /// The capsules at the current time, leaving ones included.
  List<GlassBarCapsuleFrame> get capsules => [
    for (final c in _all)
      GlassBarCapsuleFrame(
        c.id,
        _drawn(c),
        leaving: _capsules.isLeaving(c),
        segment: c.segment,
        opacity: c.apart ? _capsules.presenceAt(c).clamp(0.0, 1.0) : 1,
        apart: c.apart,
      ),
  ];

  /// The swell of a capsule that appears or leaves in place, per axis.
  Offset _apartScale(_Capsule c) {
    if (!c.apart) return const Offset(1, 1);
    final rest = 1 - _capsules.presenceAt(c);
    final target = _capsules.laidOut(c)!;
    return Offset(
      1 + (spec.pulseScaleFor(target.width) - 1) * rest,
      1 + (spec.pulseScaleFor(target.height) - 1) * rest,
    );
  }

  Rect _drawn(_Capsule c) {
    final rect = _capsules.itemAt(c).rect;
    final apart = _apartScale(c);
    return Rect.fromCenter(
      center: rect.center,
      width: math.max(0, rect.width * apart.dx),
      height: math.max(0, rect.height * apart.dy),
    );
  }

  /// The items at the current time, leaving ones included.
  List<GlassBarItemFrame> get items => [
    for (final id in _items.ids)
      if (_frameOf(id) case final frame?) frame,
  ];

  GlassBarItemFrame? _frameOf(Object id) {
    final capsule = _capsuleOf[id];
    if (capsule == null) return null;
    final present = _capsules.contains(capsule);
    if (capsule.apart && !present) return null;
    final leaving = _items.isLeaving(id);
    final riding = present && !_capsules.isLeaving(capsule);
    final p = _items.presenceAt(id);
    var center =
        _items.itemAt(id).rect.center +
        (riding && !leaving ? _capsules.leanOf(capsule) : Offset.zero);
    var scale =
        lerpDouble(spec.appearScale, 1, p)! *
        (riding ? _capsules.accentAt(capsule).height : 1);
    var presence = p.clamp(0.0, 1.0);
    var blur = math.max<double>(0, spec.appearBlur * (1 - p));
    if (capsule.apart) {
      final q = _capsules.presenceAt(capsule);
      final f = _apartScale(capsule);
      final origin = _capsules.itemAt(capsule).rect.center;
      center =
          origin +
          Offset(
            (center.dx - origin.dx) * f.dx,
            (center.dy - origin.dy) * f.dy,
          );
      scale *= f.dy;
      presence *= q.clamp(0.0, 1.0);
      blur = math.max(blur, spec.appearBlur * (1 - q));
    }
    return GlassBarItemFrame(
      id,
      center: center,
      size: _items.laidOut(id)!.size,
      scale: math.max(0, scale),
      presence: presence,
      blur: blur,
      leaving: leaving,
    );
  }

  /// The frame of the item [id], or null when it is not in the bar.
  GlassBarItemFrame? itemFrame(Object id) =>
      _items.contains(id) ? _frameOf(id) : null;

  /// The frame of the capsule [id], or null when it is not in the bar.
  GlassBarCapsuleFrame? capsuleFrame(Object id) {
    for (final f in capsules) {
      if (f.id == id) return f;
    }
    return null;
  }
}
