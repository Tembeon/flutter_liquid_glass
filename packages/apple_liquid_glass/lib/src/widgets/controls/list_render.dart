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
    const end = GlassListSection.contentInset;
    final ltr = _direction == TextDirection.ltr;
    final start = _start?.value ?? GlassListSection.contentInset;
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

/// A row's text and its detail: side by side when each fits beside the
/// other on one line, the detail at the trailing edge, and the detail under
/// the text otherwise, or always while [stacked].
class _ValueRow extends MultiChildRenderObjectWidget {
  _ValueRow({
    required this.stacked,
    required Widget text,
    required Widget detail,
  }) : super(children: [text, detail]);

  final bool stacked;

  @override
  _RenderValueRow createRenderObject(BuildContext context) => _RenderValueRow(
    stacked: stacked,
    direction: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderValueRow renderObject) {
    renderObject.stacked = stacked;
    renderObject.direction = Directionality.of(context);
  }
}

class _ValueRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderValueRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ValueRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ValueRowParentData> {
  _RenderValueRow({required this._stacked, required this._direction});

  // What floating point leaves of two widths that fit exactly.
  static const double _fitTolerance = 1e-3;

  bool _stacked;
  bool get stacked => _stacked;
  set stacked(bool value) {
    if (value == _stacked) return;
    _stacked = value;
    markNeedsLayout();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  RenderBox get _text => firstChild!;
  RenderBox get _detail => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ValueRowParentData) {
      child.parentData = _ValueRowParentData();
    }
  }

  bool _stacks(double width) =>
      _stacked ||
      _text.getMaxIntrinsicWidth(double.infinity) +
              _Metrics.gap +
              _detail.getMaxIntrinsicWidth(double.infinity) >
          width + _fitTolerance;

  double _widthOf(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : getMaxIntrinsicWidth(double.infinity);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _text.getMinIntrinsicWidth(double.infinity),
    _detail.getMinIntrinsicWidth(double.infinity),
  );

  @override
  double computeMaxIntrinsicWidth(double height) {
    final text = _text.getMaxIntrinsicWidth(double.infinity);
    final detail = _detail.getMaxIntrinsicWidth(double.infinity);
    return _stacked ? math.max(text, detail) : text + _Metrics.gap + detail;
  }

  double _height(double width, double Function(RenderBox, double) of) {
    if (_stacks(width)) {
      return of(_text, width) + _Metrics.stackedDetailGap + of(_detail, width);
    }
    final detail = _detail.getMaxIntrinsicWidth(double.infinity);
    return math.max(
      of(_text, math.max(0, width - _Metrics.gap - detail)),
      of(_detail, detail),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(width, (child, width) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(width, (child, width) => child.getMaxIntrinsicHeight(width));

  // Lays the children out with [layout] and gives this row's size and
  // where the text and the detail go in it.
  (Size, Offset, Offset) _place(
    BoxConstraints constraints,
    ChildLayouter layout,
  ) {
    final width = _widthOf(constraints);
    final ltr = _direction == TextDirection.ltr;
    final detail = layout(_detail, BoxConstraints(maxWidth: width));
    if (_stacks(width)) {
      final text = layout(_text, BoxConstraints.tightFor(width: width));
      final size = constraints.constrain(
        Size(
          width,
          text.height + _Metrics.stackedDetailGap + detail.height,
        ),
      );
      return (
        size,
        Offset.zero,
        Offset(
          ltr ? 0 : width - detail.width,
          text.height + _Metrics.stackedDetailGap,
        ),
      );
    }
    final double textWidth = math.max(0, width - _Metrics.gap - detail.width);
    final text = layout(_text, BoxConstraints.tightFor(width: textWidth));
    final size = constraints.constrain(
      Size(width, math.max(text.height, detail.height)),
    );
    return (
      size,
      Offset(ltr ? 0 : width - textWidth, (size.height - text.height) / 2),
      Offset(
        ltr ? width - detail.width : 0,
        (size.height - detail.height) / 2,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _place(constraints, ChildLayoutHelper.dryLayoutChild).$1;

  @override
  void performLayout() {
    final (size, text, detail) = _place(
      constraints,
      ChildLayoutHelper.layoutChild,
    );
    this.size = size;
    (_text.parentData! as _ValueRowParentData).offset = text;
    (_detail.parentData! as _ValueRowParentData).offset = detail;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
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
