import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/search_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The search magnifier, scaled to its box.
@internal
class SearchMagnifierPainter extends CustomPainter {
  /// Paints the magnifier in [color].
  const SearchMagnifierPainter(this.color);

  /// The color of the strokes.
  final Color color;

  // SF Symbols' `magnifyingglass` as it reads on an iPhone 16 Pro's screen
  // in a 20.67 x 19.33 box: a ring 13.33 points across drawn 1.75 thick,
  // its center 8.67 and 7.67 points in from the top left, and a handle out
  // to 17.4 and 16.7; all of it scales with the box.
  @override
  void paint(Canvas canvas, Size size) {
    const box = SearchTuning.glyphSize;
    final k = math.min(size.width / box.width, size.height / box.height);
    final origin = Offset(
      (size.width - box.width * k) / 2,
      (size.height - box.height * k) / 2,
    );
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.75 * k;
    paint.strokeCap = StrokeCap.round;
    final c = origin + const Offset(8.67, 7.67) * k;
    final r = (13.33 - 1.75) / 2 * k;
    canvas.drawCircle(c, r, paint);
    final d = r * math.sqrt1_2;
    canvas.drawLine(
      c + Offset(d, d),
      origin + const Offset(17.4, 16.7) * k,
      paint,
    );
  }

  @override
  bool shouldRepaint(SearchMagnifierPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The close button's cross: two strokes 2.3 points thick whose ink, round
/// caps included, fills a square 16.67 points across (search passport).
@internal
class SearchCrossPainter extends CustomPainter {
  /// Paints the cross in [color].
  const SearchCrossPainter(this.color);

  /// The color of the strokes.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const ink = SearchTuning.closeInk;
    const stroke = SearchTuning.closeStroke;
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    const h = (ink - stroke) / 2;
    canvas.drawLine(c + const Offset(-h, -h), c + const Offset(h, h), paint);
    canvas.drawLine(c + const Offset(h, -h), c + const Offset(-h, h), paint);
  }

  @override
  bool shouldRepaint(SearchCrossPainter oldDelegate) =>
      oldDelegate.color != color;
}
