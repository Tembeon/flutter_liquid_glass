import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How far in from its leading side something covers the box the bars
/// under it stand in, such as a tab sidebar over a column: their rows start
/// past it, and a bar's title centers on the rest, as UIKit's bars beside a
/// tab sidebar do (iOS 27.2).
@internal
class GlassBarInset extends InheritedWidget {
  /// Starts the bars of [child] [leading] points in.
  const GlassBarInset({required this.leading, required super.child, super.key});

  /// The covered part of the leading side.
  final double leading;

  /// The covered part around [context], or 0 for none.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassBarInset>()?.leading ?? 0;

  @override
  bool updateShouldNotify(GlassBarInset oldWidget) =>
      leading != oldWidget.leading;
}

/// The space between the screen's sides and a navigation bar's outer
/// items: 16 on a 402 point screen (bars passport); the Pro Max's 20 is not
/// followed (approximation).
@internal
const double navigationSideInset = 16;

/// How far a row of bar items stands from its box's left and right sides.
@internal
typedef BarSides = ({double left, double right});

/// What the window leaves a row of bars: the side padding, a sidebar over
/// the box ([GlassBarInset]), the window buttons
/// ([GlassEnvironment.windowControls]) and what the hardware covers
/// ([GlassEnvironment.occlusions]), as UIKit's bars make room for each.
@internal
abstract final class BarRoom {
  /// The navigation row's top on a phone without a status bar across its
  /// top: an iPhone in landscape and the iPhone Duo, whose row shares the
  /// status row with the status cluster (bars passport, duo report).
  static const double statusRowTop = 24;

  /// How far a bar's items reach into a side's safe area: UIKit's stand 38
  /// points in from an iPhone's 62 point inset in landscape (bars passport).
  static const double safeAreaReach = 24;

  /// The gap UIKit leaves between a bar's items and the iPhone Duo's column
  /// or status cluster: they end at 378 before a column at 382, and at 262
  /// before a status cluster at 266 (duo report).
  static const double coverGap = 4;

  static const double _tolerance = 0.5;

  /// The top of the navigation row in the box of [context]: below the top
  /// padding, or [statusRowTop] on a phone where nothing runs across the
  /// top: no padding there with a side inset (landscape, the Duo's
  /// column), or a top padding that only the status cluster's occlusion
  /// takes (the Duo without its column).
  static double rowTopOf(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final environment = GlassEnvironment.of(context);
    if (environment.formFactor != GlassFormFactor.phone) return padding.top;
    if (padding.top <= 0 && (padding.left > 0 || padding.right > 0)) {
      return statusRowTop;
    }
    if (padding.top <= statusRowTop) return padding.top;
    for (final occlusion in environment.occlusions) {
      if (occlusion.top <= _tolerance &&
          occlusion.bottom >= padding.top - _tolerance) {
        return statusRowTop;
      }
    }
    return padding.top;
  }

  /// How far a row of items [inset] in from its box's sides at rest stands
  /// in the box of [context].
  ///
  /// The row keeps out of a side's safe area but [safeAreaReach] of it, and
  /// out of the Duo's column, and starts past a sidebar over the box. Given
  /// the row's [top] and [height], it also starts past the window buttons
  /// whose line runs through it, unless [controls] is false, and keeps
  /// [coverGap] from what the hardware covers beside it.
  static BarSides sidesOf(
    BuildContext context, {
    required double inset,
    double? top,
    double height = 0,
    bool controls = true,
  }) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final environment = GlassEnvironment.of(context);
    final column = environment.barColumn;
    double safe(double padding, GlassBarColumnSide side) =>
        column.side == side && column.reservedWidth > 0
        ? column.reservedWidth + coverGap
        : padding - safeAreaReach;
    var left = math.max(inset, safe(padding.left, GlassBarColumnSide.left));
    var right = math.max(inset, safe(padding.right, GlassBarColumnSide.right));
    final covered = GlassBarInset.of(context);
    if (covered > 0) {
      if (Directionality.of(context) == TextDirection.rtl) {
        right = math.max(right, covered + inset);
      } else {
        left = math.max(left, covered + inset);
      }
    }
    if (top == null) return (left: left, right: right);
    final bottom = top + height;
    final buttons = environment.windowControls;
    final line =
        buttons.lineCenter ?? padding.top + GlassWindowControls.rowCenter;
    if (controls && line >= top && line <= bottom) {
      if (buttons.left case final reach?) left = math.max(left, reach + inset);
      if (buttons.right case final reach?) {
        right = math.max(right, reach + inset);
      }
    }
    final width = media.size.width;
    for (final occlusion in environment.occlusions) {
      if (occlusion.top >= bottom || occlusion.bottom <= top) continue;
      if (occlusion.center.dx >= width / 2) {
        right = math.max(right, width - occlusion.left + coverGap);
      } else {
        left = math.max(left, occlusion.right + coverGap);
      }
    }
    return (left: left, right: right);
  }
}
