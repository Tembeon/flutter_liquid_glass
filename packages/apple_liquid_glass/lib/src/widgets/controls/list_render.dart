part of 'list.dart';

/// Paints a row's separator over it.
class _RowSeparator extends SingleChildRenderObjectWidget {
  const _RowSeparator({
    required this.color,
    required this.start,
    required this.direction,
    required super.child,
  });

  final Color color;
  final ValueListenable<double>? start;
  final TextDirection direction;

  @override
  _RenderRowSeparator createRenderObject(BuildContext context) =>
      _RenderRowSeparator(
        color: color,
        start: start,
        direction: direction,
        following: followsMotion(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRowSeparator renderObject,
  ) {
    renderObject.color = color;
    renderObject.start = start;
    renderObject.direction = direction;
    renderObject.following = followsMotion(context);
  }
}

class _RenderRowSeparator extends RenderProxyBox {
  _RenderRowSeparator({
    required this._color,
    required this._start,
    required this._direction,
    required bool following,
  }) : _follow = MotionFollow.render(following: following) {
    _hear();
  }

  Color _color;
  Color get color => _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  ValueListenable<double>? _start;
  ValueListenable<double>? get start => _start;
  set start(ValueListenable<double>? value) {
    if (identical(value, _start)) return;
    _start = value;
    _hear();
    markNeedsPaint();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsPaint();
  }

  final MotionFollow _follow;

  bool get following => _follow.following;
  set following(bool value) => _follow.following = value;

  void _hear() => _follow.hear([
    if (_start case final start?) (start, markNeedsPaint),
  ]);

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
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    const end = _Metrics.contentInset;
    final ltr = _direction == TextDirection.ltr;
    final start = _start?.value ?? _Metrics.contentInset;
    final left = ltr ? start : end;
    final right = size.width - (ltr ? end : start);
    final line = Paint();
    line.color = _color;
    context.canvas.drawRect(
      Rect.fromLTRB(
        left,
        size.height - _Metrics.separatorThickness,
        right,
        size.height,
      ).shift(offset),
      line,
    );
  }
}

/// A row's leading slot: [_Metrics.leadingWidth] wide with the symbol
/// centered, or as wide as a wider image, which it never squeezes.
class _LeadingSlot extends SingleChildRenderObjectWidget {
  const _LeadingSlot({required super.child});

  @override
  _RenderLeadingSlot createRenderObject(BuildContext context) =>
      _RenderLeadingSlot();
}

class _RenderLeadingSlot extends RenderShiftedBox {
  _RenderLeadingSlot() : super(null);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(const Size(_Metrics.leadingWidth, 0));
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        math.max(_Metrics.leadingWidth, child.size.width),
        child.size.height,
      ),
    );
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }
}

/// Sizes a label as tall as a `UILabel` with its text: each line's height
/// rounded up to the device pixel, where the text engine rounds it to a
/// whole point (20.33 points for 17 point SF Pro at 3x).
class _LabelHeight extends SingleChildRenderObjectWidget {
  const _LabelHeight({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLabelHeight(GlassTraits.of(context).viewPixelRatio);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLabelHeight).pixelRatio = GlassTraits.of(context)
        .viewPixelRatio;
  }
}

class _RenderLabelHeight extends RenderProxyBox {
  _RenderLabelHeight(this._pixelRatio);

  // The engine reports line heights in single precision: a line of
  // exactly 47 pixels can come back a millionth of a pixel over.
  static const double _pixelTolerance = 1e-3;

  double _pixelRatio;
  double get pixelRatio => _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsLayout();
  }

  double? _line;

  double _height(double height) {
    final line = _line;
    if (line == null) return height;
    final rounded = line.roundToDouble();
    if (rounded <= 0) return height;
    final lines = (height / rounded).round();
    if (lines < 1 || (lines * rounded - height).abs() > 0.01) return height;
    return (lines * line * _pixelRatio - _pixelTolerance).ceilToDouble() /
        _pixelRatio;
  }

  static RenderParagraph? _paragraph(RenderBox child) {
    RenderObject? box = child;
    while (box is RenderProxyBox) {
      box = box.child;
    }
    return box is RenderParagraph && box.size == child.size ? box : null;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final size = child.getDryLayout(constraints);
    return constraints.constrain(Size(size.width, _height(size.height)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      _line = null;
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    _line = _paragraph(
      child,
    )?.getFullHeightForCaret(const TextPosition(offset: 0));
    size = constraints.constrain(
      Size(child.size.width, _height(child.size.height)),
    );
  }
}
