import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';

/// UIKit's reorder drag of a table row, frame by frame on the iOS 27.2
/// simulator (list API passport, reorder drag): where the held row stands
/// as it moves, how the rows that give way move, and how a dropped row
/// lands.
abstract final class ListReorder {
  // UIKit's table spring, critically damped, response 0.3 (fit rms
  // 0.07 pt).
  static const _giveWay = Spring.response(0.3, dampingRatio: 1);

  // A dropped row lands critically damped, with 0.0085 s of response for
  // each point it has to go, at most the table spring's 0.3 (2.33 points
  // 0.027, 31 points 0.27, 88 points 0.302).
  static const _responsePerPoint = 0.0085;

  /// Runs [change], a change of the rows' order, so the rows that give way
  /// move on UIKit's table spring.
  static void giveWay(VoidCallback change) => withSpring(_giveWay, change);

  /// Lets go of the held row [id] of [motion] at [t], [distance] points
  /// from its place, which it lands on.
  static void land(
    LayoutMotion motion,
    double t,
    Object id, {
    required double distance,
  }) => motion.releaseItem(
    t,
    id,
    spring: distance <= 0
        ? null
        : Spring.response(
            math.min(_giveWay.response, distance * _responsePerPoint),
            dampingRatio: 1,
          ),
  );

  /// Where a held row stands among [count] rows once its center reaches
  /// [center]: a neighbor gives way when the center passes the edge between
  /// the two as they will stand after the swap, the far side of the
  /// neighbor's room. [heightOf] gives the height of the row at an index in
  /// the order the drag started from (the held row's own at [at]), or null
  /// for one not laid out, which stops the walk; it is asked only for the
  /// rows next to the held one, outward. [slotTop] is where the held row's
  /// place starts; the answer gives the new index and place. Upward swaps
  /// mirror the downward ones UIKit was captured making.
  static ({int at, double slotTop}) place(
    int count,
    double? Function(int index) heightOf, {
    required int at,
    required double slotTop,
    required double center,
  }) {
    final own = heightOf(at)!;
    var index = at;
    var slot = slotTop;
    while (index + 1 < count) {
      final next = heightOf(index + 1);
      if (next == null || center < slot + next) break;
      slot += next;
      index++;
    }
    if (index != at) return (at: index, slotTop: slot);
    while (index > 0) {
      final previous = heightOf(index - 1);
      if (previous == null) break;
      final above = slot - previous;
      if (center > above + own) break;
      slot = above;
      index--;
    }
    return (at: index, slotTop: slot);
  }
}
