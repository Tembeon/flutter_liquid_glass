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

/// A row's activity indicator: eight spokes whose brightest one steps
/// round once a second, as UIKit's medium indicator does.
class _Spinner extends StatefulWidget {
  const _Spinner({required this.color});

  final Color color;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> {
  late final _spin = ActivityMotion(clock: MotionClockScope.of(context));
  late final _head = _spin.select((spin) => spin.head);

  @override
  void initState() {
    super.initState();
    _spin.start(_spin.clock.now);
  }

  @override
  Widget build(BuildContext context) =>
      _SpinnerSpokes(head: _head, color: widget.color);
}

class _SpinnerSpokes extends LeafRenderObjectWidget {
  const _SpinnerSpokes({required this.head, required this.color});

  final ValueListenable<int> head;
  final Color color;

  @override
  _RenderSpinner createRenderObject(BuildContext context) => _RenderSpinner(
    head: head,
    color: color,
    following: followsMotion(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSpinner renderObject) {
    renderObject.color = color;
    renderObject.following = followsMotion(context);
  }
}

class _RenderSpinner extends RenderBox {
  _RenderSpinner({
    required ValueListenable<int> head,
    required this._color,
    required bool following,
  }) : _head = head,
       _follow = MotionFollow.render(following: following) {
    _follow.hear([(head, markNeedsPaint)]);
  }

  final ValueListenable<int> _head;
  final MotionFollow _follow;

  Color _color;
  Color get color => _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  bool get following => _follow.following;
  set following(bool value) => _follow.following = value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow.attach();
  }

  @override
  void detach() {
    _follow.detach();
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(const Size.square(20));

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    const spokes = ActivityMotion.spokes;
    final head = _head.value;
    final center = size.center(offset);
    final radius = size.shortestSide / 2;
    final paint = Paint();
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    for (var i = 0; i < spokes; i++) {
      final age = (head - i) % spokes;
      paint.color = _color.withValues(alpha: _color.a * (1 - age / spokes));
      final angle = 2 * math.pi * i / spokes - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * radius * 0.45,
        center + direction * radius,
        paint,
      );
    }
  }
}
