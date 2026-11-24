import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// SF Symbols' `sidebar.leading`, drawn after the symbol at the icon
/// theme's size in its color: the button of a split view's sidebar and of
/// a tab scaffold's. Its strokes are not measured.
@internal
class GlassSidebarGlyph extends StatelessWidget {
  /// Creates the glyph.
  const GlassSidebarGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 22;
    return SizedBox(
      width: size * 25 / 22,
      height: size,
      child: CustomPaint(
        painter: _SidebarPainter(
          theme.color ?? GlassTheme.labelColorOf(context),
          Directionality.of(context),
        ),
      ),
    );
  }
}

class _SidebarPainter extends CustomPainter {
  const _SidebarPainter(this.color, this.direction);

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / 22;
    if (direction == TextDirection.rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * k
      ..strokeCap = StrokeCap.round;
    final box = Rect.fromLTWH(1.5 * k, 2.5 * k, 22 * k, 17 * k);
    canvas
      ..drawRRect(RRect.fromRectAndRadius(box, Radius.circular(4 * k)), paint)
      ..drawLine(
        Offset(box.left + 7.5 * k, box.top),
        Offset(box.left + 7.5 * k, box.bottom),
        paint,
      );
    for (final y in [4.0, 7.0, 10.0]) {
      canvas.drawLine(
        Offset(box.left + 2.5 * k, box.top + y * k),
        Offset(box.left + 5 * k, box.top + y * k),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SidebarPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.direction != direction;
}
