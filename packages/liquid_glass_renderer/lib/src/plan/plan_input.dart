import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/plan/plan.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/rects.dart' as rects;

/// All [compilePlan] needs of a frame. A form answers from a layer tree; a test
/// answers from a generated scene, ten thousand scenes in seconds.
abstract interface class PlanScenery {
  /// The frame's sites in paint order.
  List<SiteFacts> get sites;

  /// What changed this frame.
  DirtyLog get dirty;

  /// The screen in logical pixels, the most room an image can take.
  Rect get screen;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio;

  /// What the content under [site] allows a read over it to be.
  ReadLimit limitUnder(SiteFacts site);

  /// What makes [limitUnder] of [site] what it is, for a person, if anything.
  String? whyLimited(SiteFacts site);

  /// The frame something meeting [footprint] before [order] last changed, or
  /// the frame the scenery began.
  int lastChangedUnder(int order, Rect footprint);

  /// The passes a copy of [footprint] takes for what lies in it before [order],
  /// beyond its own: each opacity, filter or mask there is a layer drawn
  /// apart. A [flat] copy leaves out what its glass's frost hides.
  int savedUnder(int order, Rect footprint, {required bool flat});
}

/// Order and rect of what changed this frame: old and new bounds of a changed
/// leaf, every volatile leaf and a site whose output moved.
///
/// Past [capacity] spans merge, which only ever says more changed than did.
final class DirtyLog {
  /// Spans kept before they merge.
  static const int capacity = 16;

  final _orders = List<int>.filled(capacity, 0);
  final _rects = List<Rect>.filled(capacity, Rect.zero);
  int _count = 0;

  /// Whether nothing changed.
  bool get isEmpty => _count == 0;

  /// How many spans are kept.
  int get length => _count;

  /// Forgets the last frame.
  void clear() => _count = 0;

  /// Notes that what lies at [order] changed inside [rect].
  void add(int order, Rect rect) {
    if (rect.isEmpty) return;
    if (_count < capacity) {
      _orders[_count] = order;
      _rects[_count] = rect;
      _count++;
      return;
    }
    final last = _count - 1;
    _orders[last] = math.min(_orders[last], order);
    _rects[last] = _rects[last].expandToInclude(rect);
  }

  /// Whether a span before [before] meets [footprint].
  bool meets(int before, Rect footprint) {
    for (var i = 0; i < _count; i++) {
      if (_orders[i] >= before) continue;
      if (rects.meets(_rects[i], footprint)) return true;
    }
    return false;
  }
}
