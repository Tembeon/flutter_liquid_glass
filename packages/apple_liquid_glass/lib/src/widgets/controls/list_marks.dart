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
    path.moveTo(x(3.64), 1.97);
    path.lineTo(x(8.7), 7);
    path.lineTo(x(3.64), 12.03);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.93;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      color != oldDelegate.color || mirrored != oldDelegate.mirrored;
}

/// A checkmark or an info button in its measured box, its ink and strokes
/// those of UIKit's symbol in that configuration (a 30x render, list
/// passport); where the strokes turn is drawn by eye.
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
    path.moveTo(3.15, 9.4);
    path.lineTo(7.38, 14.85);
    path.lineTo(15.85, 2.48);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.3;
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
    const ink = 21.67;
    const line = 1.53;
    const radius = (ink - line) / 2;
    final ring = Paint();
    ring.color = color;
    ring.style = PaintingStyle.stroke;
    ring.strokeWidth = line;
    canvas.drawCircle(center, radius, ring);
    final mark = Paint();
    mark.color = color;
    canvas.drawCircle(center.translate(0, -radius * 0.5), 1.3, mark);
    const stem = 1.43;
    const foot = 6.6;
    const top = -2.1;
    const bottom = top + 7.83;
    canvas.drawRect(
      const Rect.fromLTRB(-stem / 2, top, stem / 2, bottom).shift(center),
      mark,
    );
    canvas.drawRect(
      const Rect.fromLTRB(
        -foot / 2,
        bottom - stem,
        foot / 2,
        bottom,
      ).shift(center),
      mark,
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

/// UIKit's reorder control in the first 27 points of its region: three
/// lines 20.67 long and 1.33 thick, 4.67 apart, centered on the row (list
/// API passport, simulator pixels).
class _Grip extends StatelessWidget {
  const _Grip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: CustomPaint(
        size: const Size(_Metrics.gripWidth, 15),
        painter: _GripPainter(GlassDynamicColor.resolve(color, context)),
      ),
    ),
  );
}

class _GripPainter extends CustomPainter {
  const _GripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const inset = 3.0;
    const thickness = 1.33;
    for (final dy in const [-4.67, 0.0, 4.67]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: size.center(Offset(0, dy)),
            width: size.width - 2 * inset,
            height: thickness,
          ),
          const Radius.circular(thickness / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GripPainter oldDelegate) => color != oldDelegate.color;
}
