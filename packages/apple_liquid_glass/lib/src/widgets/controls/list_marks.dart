part of 'list.dart';

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: _Metrics.chevronSize,
    painter: _ChevronPainter(
      color: color,
      mirrored: Directionality.of(context) == TextDirection.rtl,
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => mirrored ? size.width - v : v;
    final path = Path();
    path.moveTo(x(3.7), 1.8);
    path.lineTo(x(8.7), 7);
    path.lineTo(x(3.7), 12.2);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      color != oldDelegate.color || mirrored != oldDelegate.mirrored;
}

/// A checkmark or an info button in its measured box; the strokes inside
/// are drawn by eye.
class _Glyph extends StatelessWidget {
  _Glyph.checkmark(Color color)
    : painter = _CheckPainter(color),
      size = _Metrics.checkmarkSize;

  _Glyph.info(Color color)
    : painter = _InfoPainter(color),
      size = const Size.square(_Metrics.infoSize);

  final CustomPainter painter;
  final Size size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: size, painter: painter);
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width * 0.08, size.height * 0.55);
    path.lineTo(size.width * 0.36, size.height * 0.9);
    path.lineTo(size.width * 0.92, size.height * 0.1);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

class _InfoPainter extends CustomPainter {
  const _InfoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 0.75;
    final ring = Paint();
    ring.color = color;
    ring.style = PaintingStyle.stroke;
    ring.strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ring);
    final dot = Paint();
    dot.color = color;
    canvas.drawCircle(center.translate(0, -radius * 0.45), 1.3, dot);
    final stem = Paint();
    stem.color = color;
    stem.strokeWidth = 2;
    stem.strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(0, -radius * 0.12),
      center.translate(0, radius * 0.5),
      stem,
    );
  }

  @override
  bool shouldRepaint(_InfoPainter oldDelegate) => color != oldDelegate.color;
}

/// A row's edit control over the first 60 points of its leading side: the
/// delete or insert disc, which takes a tap, or the selection ring.
class _EditMark extends StatefulWidget {
  const _EditMark({required this.kind, required this.picked, this.onPressed});

  final _EditKind kind;
  final bool picked;
  final VoidCallback? onPressed;

  @override
  State<_EditMark> createState() => _EditMarkState();
}

class _EditMarkState extends State<_EditMark> {
  late final _tap = TapInteraction(onTap: (_) => widget.onPressed?.call());
  late final List<Interaction> _interactions = [_tap];

  @override
  Widget build(BuildContext context) {
    Color resolve(Color color) => GlassDynamicColor.resolve(color, context);
    final mark = Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: _Metrics.editMarkStart,
        ),
        child: CustomPaint(
          size: const Size.square(_Metrics.editMarkBox),
          painter: _EditMarkPainter(
            kind: widget.kind,
            picked: widget.picked,
            fill: resolve(switch (widget.kind) {
              _EditKind.delete => GlassColors.systemRed,
              _EditKind.insert => GlassColors.systemGreen,
              _EditKind.select when widget.picked =>
                GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
              _EditKind.select => GlassColors.tertiaryLabel,
            }),
          ),
        ),
      ),
    );
    if (widget.kind == _EditKind.select) return ExcludeSemantics(child: mark);
    final strings = GlassLocalizations.of(context);
    return InputRegion(
      interactions: _interactions,
      enabled: widget.onPressed != null,
      semantics: SemanticsProperties(
        label: widget.kind == _EditKind.delete
            ? strings.deleteLabel
            : strings.insertLabel,
        button: true,
      ),
      child: mark,
    );
  }
}

class _EditMarkPainter extends CustomPainter {
  const _EditMarkPainter({
    required this.kind,
    required this.picked,
    required this.fill,
  });

  final _EditKind kind;
  final bool picked;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(const Offset(0, 1));
    const radius = _Metrics.editMarkCircle / 2;
    final disc = Paint()..color = fill;
    if (kind == _EditKind.select && !picked) {
      canvas.drawCircle(
        center,
        radius - 0.665,
        disc
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.33,
      );
      return;
    }
    canvas.drawCircle(center, radius, disc);
    final white = Paint()..color = const Color(0xFFFFFFFF);
    final bar = Rect.fromCenter(center: center, width: 9.67, height: 1.33);
    switch (kind) {
      case _EditKind.delete:
        canvas.drawRect(bar, white);
      case _EditKind.insert:
        canvas.drawRect(bar, white);
        canvas.drawRect(
          Rect.fromCenter(center: center, width: 1.33, height: 9.67),
          white,
        );
      case _EditKind.select:
        final path = Path()
          ..moveTo(center.dx - 4.5, center.dy + 0.2)
          ..lineTo(center.dx - 1.5, center.dy + 3.2)
          ..lineTo(center.dx + 4.6, center.dy - 3.6);
        canvas.drawPath(
          path,
          white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  @override
  bool shouldRepaint(_EditMarkPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      picked != oldDelegate.picked ||
      fill != oldDelegate.fill;
}
