part of 'menu_rows.dart';

/// The checkmark or the dash of a row's selection mark.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.color, required this.mixed});

  final Color color;
  final bool mixed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    if (mixed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        paint,
      );
      return;
    }
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.1;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final path = Path();
    path.moveTo(size.width * 0.06, size.height * 0.55);
    path.lineTo(size.width * 0.36, size.height * 0.92);
    path.lineTo(size.width * 0.94, size.height * 0.08);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mixed != mixed;
}

/// A chevron pointing at the trailing edge; callers flip it for
/// right-to-left.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.12, h * 0.08);
    path.lineTo(w * 0.88, h * 0.5);
    path.lineTo(w * 0.12, h * 0.92);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}
