import 'dart:math' as math;

import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/widgets.dart';

/// A badge on a tab: a count, a short text or a dot.
///
/// UIKit: `UITabBarItem.badgeValue`, `UIBarButtonItem.Badge`. SwiftUI:
/// `badge(_:)`. Flutter: `Badge`.
///
/// It draws in [GlassColors.systemRed] with white text unless its colors
/// are given: a capsule as tall as its 12 point medium text line plus 2
/// points above and below, 4 points of side padding, at least as wide as it
/// is tall and at most 64 points wide; the dot is an 18 point circle. Its
/// text does not follow the text size setting. These metrics are read from
/// UIKit (notes private); how a badge appears, changes and leaves (UIKit
/// fades it with the bar's update animation) is not reproduced.
class GlassBadge extends StatelessWidget {
  /// A badge showing [count]; a count of zero or less shows no badge.
  const GlassBadge.count(
    int this.count, {
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  }) : text = null;

  /// A badge showing [text]; an empty text shows no badge.
  const GlassBadge.text(
    String this.text, {
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  }) : count = null;

  /// A dot without text (UIKit `Badge.indicator()`).
  const GlassBadge.indicator({this.backgroundColor, super.key})
    : count = null,
      text = null,
      foregroundColor = null;

  /// The number shown, or null.
  final int? count;

  /// The text shown, or null.
  final String? text;

  /// The color of the text; null is white.
  final Color? foregroundColor;

  /// The fill of the badge; null is [GlassColors.systemRed].
  final Color? backgroundColor;

  /// The size of the text.
  static const double fontSize = 12;

  /// The space above and below the text.
  static const double verticalPadding = 2;

  /// The space before and after the text.
  static const double horizontalPadding = 4;

  /// The widest a badge gets.
  static const double maxWidth = 64;

  /// The size of a badge without text.
  static const double dotSize = 18;

  bool get _visible => switch ((count, text)) {
    (final int n, _) => n > 0,
    (_, final String t) => t.isNotEmpty,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final label = count?.toString() ?? text;
    final fill = GlassDynamicColor.resolve(
      backgroundColor ?? GlassColors.systemRed,
      context,
    );
    return MediaQuery.withNoTextScaling(
      child: Builder(
        builder: (context) {
          if (label == null) {
            return Container(
              width: dotSize,
              height: dotSize,
              decoration: ShapeDecoration(
                color: fill,
                shape: const StadiumBorder(),
              ),
            );
          }
          final style = resolveGlassText(
            TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: GlassDynamicColor.resolve(
                foregroundColor ?? const Color(0xFFFFFFFF),
                context,
              ),
            ),
            context,
          );
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          );
          painter.layout();
          final line = painter.size;
          painter.dispose();
          final height = line.height + 2 * verticalPadding;
          final width = math.max(
            height,
            math.min(line.width + 2 * horizontalPadding, maxWidth),
          );
          return Semantics(
            label: label,
            child: Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
              ),
              decoration: ShapeDecoration(
                color: fill,
                shape: const StadiumBorder(),
              ),
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
