import 'dart:math' as math;

import 'package:flutter/widgets.dart';

@immutable
final class StudioPalette {
  const StudioPalette({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.well,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.blue,
    required this.orange,
    required this.green,
    required this.purple,
    required this.red,
    required this.teal,
    required this.indigo,
  });

  static const light = StudioPalette(
    isDark: false,
    canvas: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE9E9F0),
    well: Color(0xFFE5E5EC),
    hairline: Color(0x18000000),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF5A5A60),
    textTertiary: Color(0xFF8E8E93),
    blue: Color(0xFF007AFF),
    orange: Color(0xFFFF9500),
    green: Color(0xFF34C759),
    purple: Color(0xFFAF52DE),
    red: Color(0xFFFF3B30),
    teal: Color(0xFF30B0C7),
    indigo: Color(0xFF5856D6),
  );

  static const dark = StudioPalette(
    isDark: true,
    canvas: Color(0xFF0B0B0E),
    surface: Color(0xFF1A1A1F),
    surfaceAlt: Color(0xFF28282F),
    well: Color(0xFF131317),
    hairline: Color(0x22FFFFFF),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFAEAEB2),
    textTertiary: Color(0xFF7C7C82),
    blue: Color(0xFF0A84FF),
    orange: Color(0xFFFF9F0A),
    green: Color(0xFF30D158),
    purple: Color(0xFFBF5AF2),
    red: Color(0xFFFF453A),
    teal: Color(0xFF40C8E0),
    indigo: Color(0xFF5E5CE6),
  );

  final bool isDark;
  final Color canvas;
  final Color surface;
  final Color surfaceAlt;
  final Color well;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color blue;
  final Color orange;
  final Color green;
  final Color purple;
  final Color red;
  final Color teal;
  final Color indigo;

  TextStyle get title => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: textPrimary,
  );

  TextStyle get subtitle => TextStyle(
    fontSize: 13,
    height: 1.35,
    color: textSecondary,
  );

  TextStyle get label => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  TextStyle get mono => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: textSecondary,
  );
}

class StudioTheme extends InheritedWidget {
  const StudioTheme({
    required this.palette,
    required super.child,
    super.key,
  });

  final StudioPalette palette;

  static StudioPalette of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<StudioTheme>();
    return theme?.palette ?? StudioPalette.light;
  }

  @override
  bool updateShouldNotify(StudioTheme oldWidget) =>
      palette.isDark != oldWidget.palette.isDark;
}

enum StudioGlyph {
  spring,
  timeline,
  scroll,
  text,
  sparkle,
  grid,
  bell,
  heart,
  star,
  bolt,
  wifi,
  check,
  play,
  pause,
  reverse,
  stop,
  plus,
  minus,
  shuffle,
  sun,
  moon,
}

class StudioIcon extends StatelessWidget {
  const StudioIcon(
    this.glyph, {
    required this.color,
    this.size = 18,
    super.key,
  });

  final StudioGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GlyphPainter(glyph, color)),
  );
}

final class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final StudioGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w * 0.095)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case StudioGlyph.spring:
        final path = Path()..moveTo(w * 0.12, h * 0.65);
        for (var i = 0; i <= 24; i++) {
          final t = i / 24;
          final x = w * (0.12 + 0.76 * t);
          final env = math.exp(-3.2 * t);
          final y = h * (0.5 - 0.34 * env * math.cos(t * math.pi * 4.5));
          path.lineTo(x, y);
        }
        canvas.drawPath(path, stroke);
      case StudioGlyph.timeline:
        canvas.drawLine(
          Offset(w * 0.12, h * 0.5),
          Offset(w * 0.88, h * 0.5),
          stroke,
        );
        canvas.drawCircle(Offset(w * 0.24, h * 0.5), w * 0.1, fill);
        canvas.drawCircle(Offset(w * 0.56, h * 0.5), w * 0.13, fill);
        canvas.drawCircle(Offset(w * 0.82, h * 0.5), w * 0.09, fill);
      case StudioGlyph.scroll:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.24, h * 0.12, w * 0.52, h * 0.76),
            Radius.circular(w * 0.26),
          ),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.5, h * 0.3),
          Offset(w * 0.5, h * 0.48),
          stroke,
        );
      case StudioGlyph.text:
        canvas.drawLine(
          Offset(w * 0.18, h * 0.22),
          Offset(w * 0.82, h * 0.22),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.5, h * 0.22),
          Offset(w * 0.5, h * 0.8),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.35, h * 0.8),
          Offset(w * 0.65, h * 0.8),
          stroke,
        );
      case StudioGlyph.sparkle:
        final path = Path()
          ..moveTo(w * 0.5, h * 0.08)
          ..quadraticBezierTo(w * 0.52, h * 0.48, w * 0.92, h * 0.5)
          ..quadraticBezierTo(w * 0.52, h * 0.52, w * 0.5, h * 0.92)
          ..quadraticBezierTo(w * 0.48, h * 0.52, w * 0.08, h * 0.5)
          ..quadraticBezierTo(w * 0.48, h * 0.48, w * 0.5, h * 0.08)
          ..close();
        canvas.drawPath(path, fill);
      case StudioGlyph.grid:
        final r = Radius.circular(w * 0.1);
        for (final dx in [0.14, 0.54]) {
          for (final dy in [0.14, 0.54]) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(w * dx, h * dy, w * 0.32, h * 0.32),
                r,
              ),
              stroke,
            );
          }
        }
      case StudioGlyph.bell:
        final body = Path()
          ..moveTo(w * 0.22, h * 0.7)
          ..lineTo(w * 0.28, h * 0.42)
          ..cubicTo(w * 0.28, h * 0.22, w * 0.72, h * 0.22, w * 0.72, h * 0.42)
          ..lineTo(w * 0.78, h * 0.7)
          ..close();
        canvas.drawPath(body, fill);
        canvas.drawCircle(Offset(w * 0.5, h * 0.82), w * 0.09, fill);
        canvas.drawCircle(Offset(w * 0.5, h * 0.17), w * 0.06, fill);
      case StudioGlyph.heart:
        final heart = Path()
          ..moveTo(w * 0.5, h * 0.84)
          ..cubicTo(w * 0.14, h * 0.58, w * 0.08, h * 0.32, w * 0.28, h * 0.2)
          ..cubicTo(w * 0.4, h * 0.13, w * 0.5, h * 0.26, w * 0.5, h * 0.32)
          ..cubicTo(w * 0.5, h * 0.26, w * 0.6, h * 0.13, w * 0.72, h * 0.2)
          ..cubicTo(w * 0.92, h * 0.32, w * 0.86, h * 0.58, w * 0.5, h * 0.84)
          ..close();
        canvas.drawPath(heart, fill);
      case StudioGlyph.star:
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final angle = -math.pi / 2 + i * math.pi / 5;
          final radius = i.isEven ? w * 0.42 : w * 0.19;
          final p = Offset(
            w * 0.5 + radius * math.cos(angle),
            h * 0.5 + radius * math.sin(angle),
          );
          if (i == 0) {
            star.moveTo(p.dx, p.dy);
          } else {
            star.lineTo(p.dx, p.dy);
          }
        }
        star.close();
        canvas.drawPath(star, fill);
      case StudioGlyph.bolt:
        final bolt = Path()
          ..moveTo(w * 0.56, h * 0.1)
          ..lineTo(w * 0.22, h * 0.54)
          ..lineTo(w * 0.48, h * 0.54)
          ..lineTo(w * 0.42, h * 0.9)
          ..lineTo(w * 0.78, h * 0.44)
          ..lineTo(w * 0.52, h * 0.44)
          ..close();
        canvas.drawPath(bolt, fill);
      case StudioGlyph.wifi:
        canvas.drawCircle(Offset(w * 0.5, h * 0.78), w * 0.075, fill);
        for (final r in [0.22, 0.38, 0.54]) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset(w * 0.5, h * 0.76), radius: w * r),
            -math.pi * 0.78,
            math.pi * 0.56,
            false,
            stroke,
          );
        }
      case StudioGlyph.check:
        final check = Path()
          ..moveTo(w * 0.2, h * 0.52)
          ..lineTo(w * 0.42, h * 0.74)
          ..lineTo(w * 0.82, h * 0.28);
        canvas.drawPath(check, stroke);
      case StudioGlyph.play:
        final play = Path()
          ..moveTo(w * 0.28, h * 0.18)
          ..lineTo(w * 0.82, h * 0.5)
          ..lineTo(w * 0.28, h * 0.82)
          ..close();
        canvas.drawPath(play, fill);
      case StudioGlyph.pause:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.24, h * 0.2, w * 0.18, h * 0.6),
            Radius.circular(w * 0.06),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.58, h * 0.2, w * 0.18, h * 0.6),
            Radius.circular(w * 0.06),
          ),
          fill,
        );
      case StudioGlyph.reverse:
        final tri = Path()
          ..moveTo(w * 0.74, h * 0.2)
          ..lineTo(w * 0.22, h * 0.5)
          ..lineTo(w * 0.74, h * 0.8)
          ..close();
        canvas.drawPath(tri, fill);
      case StudioGlyph.stop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.22, w * 0.56, h * 0.56),
            Radius.circular(w * 0.12),
          ),
          fill,
        );
      case StudioGlyph.plus:
        canvas.drawLine(
          Offset(w * 0.5, h * 0.2),
          Offset(w * 0.5, h * 0.8),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.2, h * 0.5),
          Offset(w * 0.8, h * 0.5),
          stroke,
        );
      case StudioGlyph.minus:
        canvas.drawLine(
          Offset(w * 0.2, h * 0.5),
          Offset(w * 0.8, h * 0.5),
          stroke,
        );
      case StudioGlyph.shuffle:
        final p1 = Path()
          ..moveTo(w * 0.15, h * 0.3)
          ..cubicTo(w * 0.45, h * 0.3, w * 0.55, h * 0.7, w * 0.84, h * 0.7);
        final p2 = Path()
          ..moveTo(w * 0.15, h * 0.7)
          ..cubicTo(w * 0.45, h * 0.7, w * 0.55, h * 0.3, w * 0.84, h * 0.3);
        canvas.drawPath(p1, stroke);
        canvas.drawPath(p2, stroke);
      case StudioGlyph.sun:
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.2, fill);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(
            Offset(
              w * (0.5 + 0.31 * math.cos(a)),
              h * (0.5 + 0.31 * math.sin(a)),
            ),
            Offset(
              w * (0.5 + 0.42 * math.cos(a)),
              h * (0.5 + 0.42 * math.sin(a)),
            ),
            stroke,
          );
        }
      case StudioGlyph.moon:
        final moon = Path()
          ..addOval(
            Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: w * 0.34),
          );
        final cut = Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(w * 0.66, h * 0.38),
              radius: w * 0.29,
            ),
          );
        canvas.drawPath(
          Path.combine(PathOperation.difference, moon, cut),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
