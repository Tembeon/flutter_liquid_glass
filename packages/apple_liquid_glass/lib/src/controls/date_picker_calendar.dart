part of 'date_picker.dart';

const double _weekdayHeight = 15.67;

class _Title extends StatelessWidget {
  const _Title({
    required this.details,
    required this.look,
    required this.style,
  });

  final GlassDatePickerTitle details;
  final GlassDatePickerStyle look;
  final TextStyle style;

  static const double _chevronGap = 7.67;
  static const Size _chevron = Size(6.33, 11.67);
  static const double _chevronStroke = 2.1;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            details.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              color: details.showsYearPicker
                  ? look.accentColor!
                  : look.labelColor!,
            ),
          ),
        ),
        const SizedBox(width: _chevronGap),
        MotionTransition(
          rotation: details.chevronAngle,
          child: CustomPaint(
            size: _chevron,
            painter: _ChevronPainter(
              color: look.accentColor!,
              forward: !rtl,
              stroke: _chevronStroke,
            ),
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.details, required this.look});

  final GlassDatePickerArrow details;
  final GlassDatePickerStyle look;

  static const Size _chevron = Size(10, 17.33);
  static const double _stroke = 2.6;
  static const double _shiftRight = 1;
  static const double _shiftLeft = -1.33;

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.translate(
      offset: Offset(details.pointsRight ? _shiftRight : _shiftLeft, 0),
      child: Opacity(
        opacity: details.enabled ? 1 : _unavailableDayOpacity,
        child: CustomPaint(
          size: _chevron,
          painter: _ChevronPainter(
            color: look.labelColor!,
            forward: details.pointsRight,
            stroke: _stroke,
          ),
        ),
      ),
    ),
  );
}

// A day is a handful of elements: the open frame builds every day of the
// month at once, and on a slow phone each element of it counts.
Widget _day(
  GlassDatePickerDay details, {
  required GlassDatePickerStyle look,
  required TextStyle style,
}) {
  final selected = details.selected;
  final today = details.today;
  final color = switch ((selected, today)) {
    (true, true) => _selectedDayColor,
    (true, false) => look.selectedDayTextColor!,
    (false, true) => look.accentColor!,
    (false, false) => look.labelColor!,
  };
  final fill = switch ((selected, today)) {
    (true, true) => look.accentColor!,
    (true, false) => look.labelColor!,
    (false, true) => look.todayFillColor!,
    (false, false) => null,
  };
  final cell = _DayCell(
    width: details.size.width,
    disc: math.min(details.size.width, details.size.height),
    fill: fill,
    states: details.states,
    focusColor: GlassHighlights.ringColor(
      look.focusColor,
      look.accentColor!,
      highContrast: false,
    ),
    hoverColor: look.hoverColor ?? GlassHighlights.hoverColor,
    child: Text(
      '${details.date.day}',
      textScaler: TextScaler.noScaling,
      style: style.copyWith(color: color),
    ),
  );
  return details.enabled
      ? cell
      : Opacity(opacity: _unavailableDayOpacity, child: cell);
}

/// One day of the grid: [width] wide and as tall as its row, a [disc]
/// across filled with [fill] at its center and the number centered on the
/// disc, with the focus ring inside the disc's edge and the hover's wash
/// over it. It lays out and paints as the Center, Container and Align it
/// stands for, offset for offset.
class _DayCell extends SingleChildRenderObjectWidget {
  const _DayCell({
    required this.width,
    required this.disc,
    required this.fill,
    required this.states,
    required this.focusColor,
    required this.hoverColor,
    required super.child,
  });

  final double width;
  final double disc;
  final Color? fill;
  final ValueListenable<Set<WidgetState>> states;
  final Color focusColor;
  final Color hoverColor;

  @override
  _RenderDayCell createRenderObject(BuildContext context) => _RenderDayCell(
    width: width,
    disc: disc,
    fill: fill,
    highlight: GlassHighlight(
      states: states,
      reduceMotion: GlassTraits.of(context).reduceMotion,
    ),
    focusColor: focusColor,
    hoverColor: hoverColor,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderDayCell renderObject) {
    if (renderObject.width != width || renderObject.disc != disc) {
      renderObject.width = width;
      renderObject.disc = disc;
      renderObject.markNeedsLayout();
    }
    if (renderObject.fill != fill ||
        renderObject.focusColor != focusColor ||
        renderObject.hoverColor != hoverColor) {
      renderObject.fill = fill;
      renderObject.focusColor = focusColor;
      renderObject.hoverColor = hoverColor;
      renderObject.markNeedsPaint();
    }
    renderObject.highlight.states = states;
    renderObject.highlight.reduceMotion = GlassTraits.of(
      context,
    ).reduceMotion;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('disc', disc));
    properties.add(ColorProperty('fill', fill, defaultValue: null));
  }
}

class _RenderDayCell extends RenderProxyBox {
  _RenderDayCell({
    required this.width,
    required this.disc,
    required this.fill,
    required this.highlight,
    required this.focusColor,
    required this.hoverColor,
  });

  double width;
  double disc;
  Color? fill;
  final GlassHighlight highlight;
  Color focusColor;
  Color hoverColor;

  Offset _discOffset = Offset.zero;
  Offset _childOffset = Offset.zero;
  Size _discSize = Size.zero;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    highlight.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    highlight.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    final discBox = BoxConstraints.tight(
      Size(disc, disc),
    ).enforce(BoxConstraints.loose(size));
    final discSize = discBox.constrain(Size.infinite);
    _discSize = discSize;
    _discOffset = Alignment.center.alongOffset(size - discSize as Offset);
    final child = this.child;
    if (child == null) return;
    child.layout(discBox.loosen(), parentUsesSize: true);
    _childOffset = Alignment.center.alongOffset(
      discSize - child.size as Offset,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => BoxConstraints.tightFor(
    width: width,
  ).enforce(constraints).constrain(Size.infinite);

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + _discOffset;
    final rect = origin & _discSize;
    final fill = this.fill;
    final canvas = context.canvas;
    if (fill != null) {
      final paint = Paint();
      paint.color = fill;
      canvas.drawCircle(rect.center, rect.shortestSide / 2.0, paint);
    }
    final child = this.child;
    if (child != null) context.paintChild(child, origin + _childOffset);
    const shape = GlassShape.oval();
    final hovered = highlight.hovered;
    if (hovered > 0) {
      GlassHighlights.paintHover(
        context.canvas,
        shape.pathIn(rect),
        hoverColor,
        hovered,
      );
    }
    if (highlight.focused) {
      GlassHighlights.paintRing(
        context.canvas,
        focusColor,
        shape: shape,
        body: rect,
        inside: true,
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_discOffset.dx, _discOffset.dy, 0, 1);
    transform.translateByDouble(_childOffset.dx, _childOffset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _discOffset + _childOffset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({
    required this.color,
    required this.forward,
    required this.stroke,
  });

  final Color color;
  final bool forward;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final inset = stroke / 2;
    final path = Path();
    if (forward) {
      path.moveTo(inset, inset);
      path.lineTo(size.width - inset, size.height / 2);
      path.lineTo(inset, size.height - inset);
    } else {
      path.moveTo(size.width - inset, inset);
      path.lineTo(inset, size.height / 2);
      path.lineTo(size.width - inset, size.height - inset);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.forward != forward ||
      oldDelegate.stroke != stroke;
}
