import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// A render object that reads its parameters again on every notification
/// of a listenable: a motion pushes its frames into the render tree
/// without a rebuild.
mixin _LiveBinding on RenderObject {
  Listenable? _live;
  VoidCallback? _update;

  void bindLive(Listenable? live, VoidCallback update) {
    if (attached && !identical(live, _live)) {
      _live?.removeListener(_changed);
      live?.addListener(_changed);
    }
    _live = live;
    _update = update;
    update();
  }

  void _changed() => _update?.call();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live?.addListener(_changed);
    _update?.call();
  }

  @override
  void detach() {
    _live?.removeListener(_changed);
    super.detach();
  }
}

/// Transforms its child by [matrixOf], read again on every notification of
/// [live].
@internal
class LiveTransform extends SingleChildRenderObjectWidget {
  /// Creates a transform that follows [live].
  const LiveTransform({
    required this.live,
    required this.matrixOf,
    this.alignment = Alignment.center,
    super.child,
    super.key,
  });

  /// What tells the transform to read [matrixOf] again.
  final Listenable live;

  /// The transform now.
  final Matrix4 Function() matrixOf;

  /// The point the transform is about, or null for the child's origin.
  final AlignmentGeometry? alignment;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveTransform(
      alignment: alignment,
      textDirection: Directionality.maybeOf(context),
    );
    box.bindLive(live, () => box.transform = matrixOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveTransform;
    box.alignment = alignment;
    box.textDirection = Directionality.maybeOf(context);
    box.bindLive(live, () => box.transform = matrixOf());
  }
}

class _RenderLiveTransform extends RenderTransform with _LiveBinding {
  _RenderLiveTransform({super.alignment, super.textDirection})
    : super(transform: Matrix4.identity());
}

/// Lays its child out at the size of [rectOf] and places it at its
/// origin, read again on every notification of [live]: a moving rect
/// repaints, a resized one lays out again.
@internal
class LivePlacement extends SingleChildRenderObjectWidget {
  /// Creates a placement that follows [live].
  const LivePlacement({
    required this.live,
    required this.rectOf,
    super.child,
    super.key,
  });

  /// What tells the placement to read [rectOf] again.
  final Listenable live;

  /// Where the child is, in this box's coordinates.
  final Rect Function() rectOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLivePlacement(rectOf());
    box.bindLive(live, () => box.rect = rectOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLivePlacement;
    box.bindLive(live, () => box.rect = rectOf());
  }
}

class _RenderLivePlacement extends RenderProxyBox with _LiveBinding {
  _RenderLivePlacement(this._rect);

  Rect _rect;
  Rect get rect => _rect;
  set rect(Rect value) {
    if (value == _rect) return;
    final resized = value.size != _rect.size;
    _rect = value;
    if (resized) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void performLayout() {
    child?.layout(
      BoxConstraints.tightFor(width: _rect.width, height: _rect.height),
    );
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, _rect.topLeft + offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _rect.topLeft,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_rect.left, _rect.top, 0, 1);
  }
}

/// Shifts its child by [offsetOf] at paint, read again on every
/// notification of [live].
@internal
class LiveShift extends SingleChildRenderObjectWidget {
  /// Creates a shift that follows [live].
  const LiveShift({
    required this.live,
    required this.offsetOf,
    super.child,
    super.key,
  });

  /// What tells the shift to read [offsetOf] again.
  final Listenable live;

  /// The shift now.
  final Offset Function() offsetOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveShift(offsetOf());
    box.bindLive(live, () => box.shift = offsetOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveShift;
    box.bindLive(live, () => box.shift = offsetOf());
  }
}

class _RenderLiveShift extends RenderProxyBox with _LiveBinding {
  _RenderLiveShift(this._shift);

  Offset _shift;
  Offset get shift => _shift;
  set shift(Offset value) {
    if (value == _shift) return;
    _shift = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }
}

/// Fades its child to [opacityOf], read again on every notification of
/// [live].
@internal
class LiveFade extends SingleChildRenderObjectWidget {
  /// Creates a fade that follows [live].
  const LiveFade({
    required this.live,
    required this.opacityOf,
    super.child,
    super.key,
  });

  /// What tells the fade to read [opacityOf] again.
  final Listenable live;

  /// The opacity now.
  final double Function() opacityOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveFade();
    box.bindLive(live, () => box.opacity = opacityOf().clamp(0.0, 1.0));
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveFade;
    box.bindLive(live, () => box.opacity = opacityOf().clamp(0.0, 1.0));
  }
}

class _RenderLiveFade extends RenderOpacity with _LiveBinding {}

/// Clips its child to [rrectOf], read again on every notification of
/// [live]; touches outside the clip pass through.
@internal
class LiveClipRRect extends SingleChildRenderObjectWidget {
  /// Creates a clip that follows [live].
  const LiveClipRRect({
    required this.live,
    required this.rrectOf,
    super.child,
    super.key,
  });

  /// What tells the clip to read [rrectOf] again.
  final Listenable live;

  /// The clip now, in this box's coordinates.
  final RRect Function() rrectOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final box = _RenderLiveClipRRect(rrectOf());
    box.bindLive(live, () => box.rrect = rrectOf());
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final box = renderObject as _RenderLiveClipRRect;
    box.bindLive(live, () => box.rrect = rrectOf());
  }
}

class _RenderLiveClipRRect extends RenderProxyBox with _LiveBinding {
  _RenderLiveClipRRect(this._rrect);

  RRect _rrect;
  RRect get rrect => _rrect;
  set rrect(RRect value) {
    if (value == _rrect) return;
    _rrect = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipRRectLayer>();

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _rrect.contains(position) && super.hitTest(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _rrect,
      super.paint,
      oldLayer: _clip.layer,
    );
  }
}

/// A line of text whose color's alpha follows [opacityOf], read again on
/// every notification of [live]: a label dims without an opacity layer.
@internal
class LiveFadedText extends StatelessWidget {
  /// Creates the text [text] faded by [opacityOf].
  const LiveFadedText(
    this.text, {
    required this.live,
    required this.opacityOf,
    required this.style,
    this.maxLines,
    this.textScaler,
    super.key,
  });

  /// The text.
  final String text;

  /// What tells the text to read [opacityOf] again.
  final Listenable live;

  /// The opacity of the text's color now.
  final double Function() opacityOf;

  /// The style, whose color fades.
  final TextStyle style;

  /// The most lines the text takes.
  final int? maxLines;

  /// The text scaler.
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: live,
    builder: (context, _) {
      final color = style.color;
      final opacity = opacityOf().clamp(0.0, 1.0);
      return Text(
        text,
        maxLines: maxLines,
        textScaler: textScaler,
        style: color == null || opacity >= 1
            ? style
            : style.copyWith(color: color.withValues(alpha: color.a * opacity)),
      );
    },
  );
}
