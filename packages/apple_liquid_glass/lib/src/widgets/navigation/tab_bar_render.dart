part of 'tab_bar.dart';

/// A tab's glyph, title and badge where UIKit places them, not as a column
/// or a row.
///
/// Under the glyph (a compact bar): the glyph's center 24 points from the
/// top and the title's bottom at 51, so a title in a taller script grows
/// upward and moves nothing; the badge's leading edge 5 points inside the
/// glyph's trailing edge and its top 2 points below the tab button's (tab
/// bar passport, iOS 27.2 simulator).
///
/// Beside the glyph (a wide bar): the glyph, 8 points and the title
/// centred in the button and on its middle line; the badge's leading edge
/// 6 points before the title's trailing edge and its top on the button's
/// (tab bar passport, iOS 27.2 simulator in landscape).
///
/// [morph] takes the title away by [titleGoneAt] as the bar turns into
/// its circle; without [titleGoneAt] the title stays, to go with the rest
/// of the bar's content.
class _TabItem extends MultiChildRenderObjectWidget {
  const _TabItem({
    required this.morph,
    required this.titleGoneAt,
    required this.metrics,
    required super.children,
    this.circleBadge = false,
  });

  final ValueListenable<double>? morph;
  final double? titleGoneAt;
  final TabBarMetrics metrics;

  /// Whether the badge moves to its place on the minimized circle as the
  /// bar turns into it: on the selected tab's copy, which travels there.
  final bool circleBadge;

  @override
  _RenderTabItem createRenderObject(BuildContext context) => _RenderTabItem(
    morph,
    titleGoneAt,
    metrics,
    Directionality.of(context),
    following: followsMotion(context),
    circleBadge: circleBadge,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTabItem renderObject) {
    renderObject.morph = morph;
    renderObject.titleGoneAt = titleGoneAt;
    renderObject.circleBadge = circleBadge;
    renderObject.metrics = metrics;
    renderObject.direction = Directionality.of(context);
    renderObject.following = followsMotion(context);
  }
}

class _TabItemParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTabItem extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabItemParentData> {
  _RenderTabItem(
    this._morph,
    this._titleGoneAt,
    this._metrics,
    this._direction, {
    required bool following,
    this._circleBadge = false,
  }) : _follow = MotionFollow.render(following: following) {
    _hear();
  }

  static const double _titleBottom = 51;
  static const double _badgeInset = 5;
  static const double _badgeDrop = 2;
  // On the minimized circle the badge's top is 2 below the circle's and its
  // leading edge 7 inside the glyph's trailing edge (iOS 27.2 simulator).
  static const double _circleBadgeDrop = 2;
  static const double _circleBadgeInset = 7;
  static const double _besideGap = 8;
  static const double _besideBadgeOverlap = 6;

  ValueListenable<double>? _morph;
  ValueListenable<double>? get morph => _morph;
  set morph(ValueListenable<double>? value) {
    if (identical(value, _morph)) return;
    _morph = value;
    _hear();
    markNeedsPaint();
  }

  void _hear() => _follow.hear([
    if (_morph case final morph?) (morph, markNeedsPaint),
  ]);

  final MotionFollow _follow;

  /// Whether it follows its motion ([followsMotion]).
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

  bool _circleBadge;
  bool get circleBadge => _circleBadge;
  set circleBadge(bool value) {
    if (value == _circleBadge) return;
    _circleBadge = value;
    markNeedsPaint();
  }

  double? _titleGoneAt;
  double? get titleGoneAt => _titleGoneAt;
  set titleGoneAt(double? value) {
    if (value == _titleGoneAt) return;
    _titleGoneAt = value;
    markNeedsPaint();
  }

  TabBarMetrics _metrics;
  TabBarMetrics get metrics => _metrics;
  set metrics(TabBarMetrics value) {
    if (value == _metrics) return;
    _metrics = value;
    markNeedsLayout();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  RenderBox get _glyph => firstChild!;
  RenderBox get _title => childAfter(_glyph)!;
  RenderBox? get _badge => childAfter(_title);

  bool get _rtl => _direction == TextDirection.rtl;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabItemParentData) {
      child.parentData = _TabItemParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final glyph = _glyph.getMaxIntrinsicWidth(double.infinity);
    final title = _title.getMaxIntrinsicWidth(double.infinity);
    return _metrics.titlesBeside
        ? glyph + _besideGap + title
        : math.max(glyph, title);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _metrics.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _metrics.height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : computeMaxIntrinsicWidth(_metrics.height),
          _metrics.height,
        ),
      );

  void _place(RenderBox child, Offset offset) =>
      (child.parentData! as _TabItemParentData).offset = offset;

  Offset _at(RenderBox child) =>
      (child.parentData! as _TabItemParentData).offset;

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    _glyph.layout(const BoxConstraints(), parentUsesSize: true);
    if (_metrics.titlesBeside) {
      _layOutBeside();
    } else {
      _layOutStacked();
    }
  }

  void _layOutStacked() {
    final glyph = _glyph.size;
    _place(
      _glyph,
      Offset(
        (size.width - glyph.width) / 2,
        _metrics.glyphCenter - glyph.height / 2,
      ),
    );
    _title.layout(
      BoxConstraints(
        maxWidth: math.max(0, size.width - TabBarLayout.titleMargin),
      ),
      parentUsesSize: true,
    );
    _place(
      _title,
      Offset(
        (size.width - _title.size.width) / 2,
        _titleBottom - _title.size.height,
      ),
    );
    final badge = _badge;
    if (badge == null) return;
    badge.layout(const BoxConstraints(), parentUsesSize: true);
    final at = _at(_glyph);
    _place(
      badge,
      Offset(
        _rtl
            ? at.dx + _badgeInset - badge.size.width
            : at.dx + glyph.width - _badgeInset,
        TabBarLayout.buttonInset + _badgeDrop,
      ),
    );
  }

  void _layOutBeside() {
    final glyph = _glyph.size;
    final outset = 2 * (_metrics.slotInset - TabBarLayout.buttonInset);
    _title.layout(
      BoxConstraints(
        maxWidth: math.max(
          0,
          size.width - outset - glyph.width - _besideGap,
        ),
      ),
      parentUsesSize: true,
    );
    final title = _title.size;
    final start = (size.width - glyph.width - _besideGap - title.width) / 2;
    final middle = size.height / 2;
    final glyphLeft = _rtl ? start + title.width + _besideGap : start;
    final titleLeft = _rtl ? start : start + glyph.width + _besideGap;
    _place(_glyph, Offset(glyphLeft, middle - glyph.height / 2));
    _place(_title, Offset(titleLeft, middle - title.height / 2));
    final badge = _badge;
    if (badge == null) return;
    badge.layout(const BoxConstraints(), parentUsesSize: true);
    _place(
      badge,
      Offset(
        _rtl
            ? titleLeft + _besideBadgeOverlap - badge.size.width
            : titleLeft + title.width - _besideBadgeOverlap,
        TabBarLayout.buttonInset,
      ),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  // How far the badge of the copy that travels to the minimized circle has
  // moved toward its place there, [morph] of the way.
  Offset _toCircle(double morph) {
    if (!_circleBadge || _metrics.titlesBeside || morph == 0) {
      return Offset.zero;
    }
    const along = _circleBadgeInset - _badgeInset;
    final up =
        (TabBarLayout.buttonInset + _badgeDrop - _metrics.glyphCenter) -
        (_circleBadgeDrop - _metrics.minimizedSize / 2);
    return Offset(_rtl ? along : -along, -up) * morph.clamp(0.0, 1.0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_glyph, offset + _at(_glyph));
    final title = offset + _at(_title);
    final morph = _morph?.value ?? 0;
    final goneAt = _titleGoneAt;
    if (morph == 0 || goneAt == null) {
      context.paintChild(_title, title);
    } else {
      final left = 1 - morph / goneAt;
      if (left > 0) {
        context.pushOpacity(
          title,
          Color.getAlphaFromOpacity(left.clamp(0.0, 1.0)),
          (context, offset) => context.paintChild(_title, offset),
        );
      }
    }
    if (_badge case final badge?) {
      context.paintChild(badge, offset + _at(badge) + _toCircle(morph));
    }
  }
}
