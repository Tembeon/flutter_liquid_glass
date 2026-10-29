import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/popover_motion.dart';
import 'package:apple_liquid_glass/src/presentations/popover_shape.dart';
import 'package:apple_liquid_glass/src/presentations/sheet.dart';
import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/outline.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Shows [builder]'s content in an iOS 27 popover next to its source and
/// completes with the result it is closed with.
///
/// UIKit: a view controller presented with `.popover`. SwiftUI: `popover`.
/// Flutter: none.
///
/// The source is [anchor], a context inside the widget the popover points
/// at, which must be laid out, or [anchorRect] in global coordinates. The
/// content sizes itself up to the screen less 10 points a side; the
/// popover places it above, below, after or before the source as UIKit
/// does and joins an arrow to it, glass and arrow one body. It grows out
/// of the arrow's tip on UIKit's spring of response 0.345 and shrinks back
/// into it on one of 0.373 (read from UIKit, replayed on the iPhone 16
/// Pro); under Reduce Motion it only fades. A tap outside, Escape, Back
/// and a screen reader's dismiss close it.
///
/// On a phone (a screen whose shorter side is under 600 points, an
/// engineering stand-in for UIKit's compact width) the popover presents as
/// a sheet at its large detent, as UIKit adapts one, unless
/// [adaptsToSheet] is false.
Future<T?> showGlassPopover<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BuildContext? anchor,
  Rect? anchorRect,
  bool adaptsToSheet = true,
  String? semanticLabel,
  PresentationLevel level = PresentationLevel.window,
}) {
  if (adaptsToSheet && MediaQuery.sizeOf(context).shortestSide < 600) {
    return showGlassSheet<T>(
      context,
      builder: builder,
      semanticLabel: semanticLabel,
      level: level,
    );
  }
  return showPresentation(
    context,
    GlassPopoverRoute<T>(
      builder: builder,
      anchorRect: popoverSource(
        anchor: anchor,
        anchorRect: anchorRect,
        caller: 'showGlassPopover',
      ),
      semanticLabel: semanticLabel,
    ),
    level: level,
  );
}

/// The rect in global coordinates of [anchor], or [anchorRect] when given.
@internal
Rect popoverSource({
  required BuildContext? anchor,
  required Rect? anchorRect,
  required String caller,
}) {
  if (anchorRect != null) return anchorRect;
  if (anchor == null) {
    throw FlutterError('$caller needs an anchor or an anchorRect.');
  }
  if (!anchor.mounted) {
    throw FlutterError('The anchor of $caller is no longer mounted.');
  }
  final box = anchor.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) {
    throw FlutterError('The anchor of $caller must be laid out.');
  }
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

/// The route [showGlassPopover] pushes when it presents a popover.
final class GlassPopoverRoute<T> extends PresentationRoute<T> {
  /// Creates the route of a popover pointing at [anchorRect], in global
  /// coordinates.
  GlassPopoverRoute({
    required this.builder,
    required this.anchorRect,
    String? semanticLabel,
    super.settings,
  }) : super(semanticsLabel: semanticLabel);

  /// Builds the popover's content.
  final WidgetBuilder builder;

  /// The source the popover points at, in global coordinates.
  final Rect anchorRect;

  _PopoverViewState? _view;

  @override
  Widget buildContent(BuildContext context) => _PopoverView(route: this);

  @override
  bool leave(DismissTrigger trigger) {
    final view = _view;
    if (view == null || !view.mounted) return false;
    view._leave();
    return true;
  }
}

class _PopoverView extends StatefulWidget {
  const _PopoverView({required this.route});

  final GlassPopoverRoute<Object?> route;

  @override
  State<_PopoverView> createState() => _PopoverViewState();
}

class _PopoverViewState extends State<_PopoverView> implements MotionDriver {
  final _motion = PopoverMotion();
  final _scale = ValueNotifier<double>(PopoverTuning.hiddenScale);
  final _opacity = ValueNotifier<double>(0);
  bool _leaving = false;

  GlassPopoverRoute<Object?> get _route => widget.route;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    _route._view = this;
    _motion.present(_now);
    MotionClock.instance.addDriver(this);
  }

  @override
  void dispose() {
    if (identical(_route._view, this)) _route._view = null;
    MotionClock.instance.removeDriver(this);
    _scale.dispose();
    _opacity.dispose();
    super.dispose();
  }

  @override
  bool get isActive => !_motion.isSettled;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _motion.advance(time);
    if (_motion.isSettled) _motion.settle();
    _scale.value = _motion.scale;
    _opacity.value = _motion.opacity;
    if (_leaving) {
      if (_motion.isDismissed) _route.didLeave();
    } else if (_motion.isSettled) {
      _route.didOpen();
    }
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    _motion.dismiss(_now);
    setState(() {});
    MotionClock.instance.wake(this);
  }

  @override
  Widget build(BuildContext context) {
    _motion.reducedMotion = GlassTraits.of(context).reduceMotion;
    final media = MediaQuery.of(context);
    final label =
        GlassTheme.of(context).colorScheme?.label ?? GlassColors.label;
    return PopoverLayout(
      source: _route.anchorRect,
      scale: _scale,
      opacity: _opacity,
      maxWidth: media.size.width - 2 * PopoverTuning.margin,
      padding: media.padding.copyWith(
        bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
      ),
      direction: Directionality.of(context),
      card: IgnorePointer(
        ignoring: _leaving,
        child: MotionTransition(
          opacity: _opacity,
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(PopoverTuning.cornerRadius),
            child: DefaultTextStyle(
              style: resolveGlassText(
                TextStyle(
                  fontSize: 17,
                  color: GlassDynamicColor.resolve(label, context),
                ),
                context,
              ),
              child: Builder(builder: _route.builder),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays out a popover: its card at its own size within [maxWidth], the
/// placement from it ([placePopover]) next to [source], and the glass at
/// the placement's shape; both paint scaled by [scale] about the arrow's
/// tip, and nothing paints or takes touches while [opacity] is 0.
@internal
class PopoverLayout extends MultiChildRenderObjectWidget {
  /// Creates the layout of a popover pointing at [source], in global
  /// coordinates.
  PopoverLayout({
    required this.source,
    required this.scale,
    required this.opacity,
    required this.maxWidth,
    required this.padding,
    required this.direction,
    required Widget card,
    super.key,
  }) : super(
         children: [
           LayoutBuilder(
             builder: (context, box) => _PopoverGlass(
               shape: (box as _PopoverConstraints).shape,
               opacity: opacity,
             ),
           ),
           card,
         ],
       );

  /// The rect the popover points at, in global coordinates.
  final Rect source;

  /// The popover's scale about its arrow's tip.
  final ValueListenable<double> scale;

  /// The popover's opacity.
  final ValueListenable<double> opacity;

  /// The widest the card may be.
  final double maxWidth;

  /// The insets the popover stays inside: the safe area and the keyboard.
  final EdgeInsets padding;

  /// The direction that orders the sides the popover tries.
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPopover(
    source: source,
    scale: scale,
    opacity: opacity,
    maxWidth: maxWidth,
    padding: padding,
    direction: direction,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPopover).update(
      source: source,
      maxWidth: maxWidth,
      padding: padding,
      direction: direction,
    );
  }
}

/// The glass of a popover: its content box and arrow as one outline.
class _PopoverGlass extends StatefulWidget {
  const _PopoverGlass({required this.shape, required this.opacity});

  final PopoverShape shape;
  final ValueListenable<double> opacity;

  @override
  State<_PopoverGlass> createState() => _PopoverGlassState();
}

class _PopoverGlassState extends State<_PopoverGlass> {
  final _frame = ValueNotifier(const GlassFrame(opacity: 0));
  GlassOutline? _outline;

  @override
  void initState() {
    super.initState();
    widget.opacity.addListener(_publish);
  }

  @override
  void didUpdateWidget(_PopoverGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opacity != widget.opacity) {
      oldWidget.opacity.removeListener(_publish);
      widget.opacity.addListener(_publish);
    }
  }

  @override
  void dispose() {
    widget.opacity.removeListener(_publish);
    _frame.dispose();
    super.dispose();
  }

  void _publish() {
    _frame.value = GlassFrame(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: PopoverTuning.cornerRadius,
      ),
      opacity: widget.opacity.value,
      outline: _outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final flat = GlassTheme.rendererOf(context) is FlatGlassRenderer;
    _outline = widget.shape.outline(shaded: !flat);
    _publish();
    return GlassSurface.live(
      role: GlassRole.menu,
      frame: _frame,
      child: const SizedBox.expand(),
    );
  }
}

class _PopoverConstraints extends BoxConstraints {
  _PopoverConstraints(this.shape) : super.tight(shape.bounds.size);

  final PopoverShape shape;

  @override
  bool operator ==(Object other) =>
      other is _PopoverConstraints &&
      other.shape.content == shape.content &&
      other.shape.direction == shape.direction &&
      other.shape.arrowCenter == shape.arrowCenter;

  @override
  int get hashCode =>
      Object.hash(shape.content, shape.direction, shape.arrowCenter);
}

class _PopoverParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPopover extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PopoverParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PopoverParentData> {
  _RenderPopover({
    required this._source,
    required this.scale,
    required this.opacity,
    required this._maxWidth,
    required this._padding,
    required this._direction,
  });

  // The view's own notifiers, which live as long as the view.
  final ValueListenable<double> scale;
  final ValueListenable<double> opacity;

  Rect _source;
  double _maxWidth;
  EdgeInsets _padding;
  TextDirection _direction;

  void update({
    required Rect source,
    required double maxWidth,
    required EdgeInsets padding,
    required TextDirection direction,
  }) {
    if (source == _source &&
        maxWidth == _maxWidth &&
        padding == _padding &&
        direction == _direction) {
      return;
    }
    _source = source;
    _maxWidth = maxWidth;
    _padding = padding;
    _direction = direction;
    markNeedsLayout();
  }

  PopoverPlacement? _placement;

  // Where the last paint found the popover's box, which layout places the
  // popover by: no box's position can be read during layout.
  Offset _seen = Offset.zero;
  Offset _laidOutAt = Offset.zero;
  final _glassLayer = LayerHandle<TransformLayer>();
  final _cardLayer = LayerHandle<TransformLayer>();

  RenderBox get _glass => firstChild!;
  RenderBox get _card => lastChild!;

  bool get _shown => opacity.value > 0 && _placement != null;

  // Every frame of the motion repaints the popover alone.
  @override
  bool get isRepaintBoundary => true;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PopoverParentData) {
      child.parentData = _PopoverParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    scale.addListener(markNeedsPaint);
    opacity.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    scale.removeListener(markNeedsPaint);
    opacity.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _glassLayer.layer = null;
    _cardLayer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    _card.layout(
      BoxConstraints(
        maxWidth: math.max(0, _maxWidth),
        maxHeight: math.max(0, size.height - _padding.vertical),
      ),
      parentUsesSize: true,
    );
    _laidOutAt = _seen;
    final placement = _placement = placePopover(
      size: _card.size,
      source: _source.shift(-_laidOutAt),
      screen: size,
      padding: _padding,
      textDirection: _direction,
    );
    final bounds = placement.bounds;
    final vertical =
        placement.arrowDirection == PopoverArrowDirection.down ||
        placement.arrowDirection == PopoverArrowDirection.up;
    _glass.layout(
      _PopoverConstraints(
        PopoverShape(
          content: placement.content.shift(-bounds.topLeft),
          direction: placement.arrowDirection,
          arrowCenter:
              placement.arrowCenter - (vertical ? bounds.left : bounds.top),
        ),
      ),
    );
  }

  Matrix4 _around(Offset at) {
    final anchor = _placement!.anchor;
    final s = scale.value;
    final m = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    m.multiply(Matrix4.diagonal3Values(s, s, 1));
    m.multiply(
      Matrix4.translationValues(at.dx - anchor.dx, at.dy - anchor.dy, 0),
    );
    return m;
  }

  Matrix4 _transformOf(RenderBox child) => _around(
    identical(child, _glass)
        ? _placement!.bounds.topLeft
        : _placement!.content.topLeft,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    // Laid out for another position of its box (a popover in a nested
    // navigator, an overlay moved since), the popover is placed again in
    // the next frame; its first frame shows nothing, its opacity at 0.
    _seen = localToGlobal(Offset.zero);
    if (_seen != _laidOutAt) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) markNeedsLayout();
      });
    }
    if (!_shown) {
      _glassLayer.layer = null;
      _cardLayer.layer = null;
      return;
    }
    _glassLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transformOf(_glass),
      (context, offset) => context.paintChild(_glass, offset),
      oldLayer: _glassLayer.layer,
    );
    _cardLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transformOf(_card),
      (context, offset) => context.paintChild(_card, offset),
      oldLayer: _cardLayer.layer,
    );
  }

  // The popover takes taps across its frame, the arrow's strip included,
  // as UIKit's popover view does; the card takes its own first.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_shown) return false;
    final hit = result.addWithPaintTransform(
      transform: _transformOf(_card),
      position: position,
      hitTest: (result, position) => _card.hitTest(result, position: position),
    );
    if (hit) return true;
    final toGlass = Matrix4.tryInvert(_transformOf(_glass));
    if (toGlass == null) return false;
    return (Offset.zero & _glass.size).contains(
      MatrixUtils.transformPoint(toGlass, position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_placement == null) return;
    transform.multiply(_transformOf(child));
  }
}
