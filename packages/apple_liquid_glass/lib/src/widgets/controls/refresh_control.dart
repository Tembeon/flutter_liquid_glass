import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Called when a refresh control starts to refresh; it refreshes until the
/// future completes.
typedef GlassRefreshCallback = Future<void> Function();

/// An iOS refresh control: pulled down from the top of a scroll view far
/// enough, it spins while the app refreshes the content.
///
/// UIKit: `UIRefreshControl`. SwiftUI: `refreshable(action:)`. Flutter:
/// `CupertinoSliverRefreshControl`.
///
/// ```dart
/// CustomScrollView(
///   physics: const AlwaysScrollableScrollPhysics(
///     parent: BouncingScrollPhysics(),
///   ),
///   slivers: [
///     GlassSliverRefreshControl(onRefresh: mail.fetch),
///     SliverList.builder(itemBuilder: ..., itemCount: ...),
///   ],
/// )
/// ```
///
/// It stands first in a `CustomScrollView` that scrolls past its top, as
/// iOS's scroll views do (`BouncingScrollPhysics`), and keeps the content
/// clear of what covers the top (`MediaQuery.paddingOf(context).top`, the
/// bars), as UIKit's adjusted content inset does, so the slivers after it
/// need no top padding of their own. Its control stands right under that,
/// [height] points tall, pinned to the top of what shows; what the pull
/// reveals of it shows, and the content covers the rest.
///
/// Pulled, its eight ticks come in one by one clockwise from 12 o'clock as
/// the content moves down. A pull of 174 points, the finger still down,
/// starts the refresh: [onRefresh] runs, the ticks settle into a tail and
/// spin, a step of 45 degrees every 0.125 s over a wind-up of half a turn,
/// and the control keeps its height of the content's inset, so the
/// content comes to rest under it once the finger lifts ([RefreshMotion]).
/// When the future completes the spin stops, the ticks turn on to the next
/// half turn, and the content scrolls back over the control in 0.33 s,
/// ease in and out; with the finger still down it gives the control's
/// height back at once. The ticks are the label's color while pulled and
/// the secondary label's once refreshing, or [color] throughout. A [title]
/// stands under the ticks in 12 point text, one line, and the control is
/// [titledHeight] tall.
///
/// Fidelity. The pull, the trigger, the reveal, the tail, the spin, the
/// wind-up and the end are measured on the iOS 27.2 simulator with real
/// drags (refresh control passport); the content's resistance is Flutter's
/// `BouncingScrollPhysics`, not UIKit's (360 points of finger move UIKit's
/// content about 193). Not reproduced: the control hidden inside a large
/// title, and a refresh begun from code.
class GlassSliverRefreshControl extends StatefulWidget {
  /// Creates a refresh control that calls [onRefresh].
  const GlassSliverRefreshControl({
    required this.onRefresh,
    this.color,
    this.title,
    super.key,
  });

  /// Refreshes the content; the control spins until the future completes.
  final GlassRefreshCallback onRefresh;

  /// The ticks' color, or null for the label's while pulled and the
  /// secondary label's while refreshing.
  final Color? color;

  /// What stands under the ticks, or null for nothing.
  final Widget? title;

  /// The control's height without a title.
  static const double height = 60;

  /// The control's height with a title.
  static const double titledHeight = 81.33;

  @override
  State<GlassSliverRefreshControl> createState() =>
      _GlassSliverRefreshControlState();
}

class _GlassSliverRefreshControlState extends State<GlassSliverRefreshControl> {
  late final _motion = RefreshMotion(clock: MotionClockScope.of(context));
  late final _drawn = _motion.select(
    (motion) => (
      opacity: motion.opacity,
      rotation: motion.rotation,
      refreshing: motion.refreshing,
      ticks: [
        for (var i = 0; i < RefreshMotion.steps; i++) motion.tickOpacity(i),
      ],
    ),
  );
  late final _titleOpacity = _motion.select((motion) => motion.opacity);
  ScrollPosition? _position;
  bool _holds = false;

  double get _height => widget.title == null
      ? GlassSliverRefreshControl.height
      : GlassSliverRefreshControl.titledHeight;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position = Scrollable.maybeOf(context)?.position;
  }

  bool _dragging() => _position?.userScrollDirection == ScrollDirection.forward;

  // Called from the sliver's layout: the motion only takes the pull, and
  // the app's refresh runs once the frame is through, outside layout.
  void _pulled(double pull, {required bool triggered}) {
    _motion.pull(pull);
    if (!triggered) return;
    _holds = true;
    _motion.trigger(_motion.clock.now);
    scheduleMicrotask(_refresh);
  }

  Future<void> _refresh() async {
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) await _end();
    }
  }

  Future<void> _end() async {
    _motion.end(_motion.clock.now);
    final position = _position;
    if (position != null &&
        !_dragging() &&
        position.pixels < _height - 0.5 &&
        position.pixels >= 0) {
      await position.animateTo(
        _height,
        duration: const Duration(milliseconds: 330),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;
    setState(() => _holds = false);
    _motion.reset();
  }

  @override
  Widget build(BuildContext context) {
    final label = GlassDynamicColor.resolve(
      widget.color ?? GlassTheme.labelColorOf(context),
      context,
    );
    final refreshing = GlassDynamicColor.resolve(
      widget.color ?? GlassColors.secondaryLabel,
      context,
    );
    final title = widget.title;
    return _RefreshSliver(
      inset: MediaQuery.paddingOf(context).top,
      extent: _height,
      holds: _holds,
      dragging: _dragging,
      onPull: _pulled,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: title == null ? 0 : _Metrics.titledTicksTop,
              height: _Metrics.ticksBox,
              child: CustomPaint(
                painter: _Ticks(
                  drawn: _drawn,
                  pulled: label,
                  refreshing: refreshing,
                ),
              ),
            ),
            if (title != null)
              Positioned(
                left: _Metrics.titleInset,
                right: _Metrics.titleInset,
                top: _Metrics.titleTop,
                child: MotionTransition(
                  opacity: _titleOpacity,
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: _Metrics.titleSize,
                      color: GlassDynamicColor.resolve(
                        GlassTheme.labelColorOf(context),
                        context,
                      ),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The refresh control passport's numbers.
abstract final class _Metrics {
  // The ticks: 3.67 by 10, from 5 to 15 off the center, the center 30
  // under the control's top (40.67 with a title).
  static const Size tick = Size(3.67, 10);
  static const double tickInner = 5;
  static const double ticksBox = 60;
  static const double titledTicksTop = 40.67 - 30;

  // The title: 12 point, 10 in from each side, its top 59.17 down.
  static const double titleSize = 12;
  static const double titleInset = 10;
  static const double titleTop = 59.17;
}

typedef _Drawn = ({
  double opacity,
  double rotation,
  bool refreshing,
  List<double> ticks,
});

class _Ticks extends CustomPainter {
  _Ticks({
    required this.drawn,
    required this.pulled,
    required this.refreshing,
  }) : super(repaint: drawn);

  final MotionSelection<_Drawn> drawn;
  final Color pulled;
  final Color refreshing;

  @override
  void paint(Canvas canvas, Size size) {
    final now = drawn.value;
    if (now.opacity <= 0) return;
    final color = now.refreshing ? refreshing : pulled;
    final center = size.center(Offset.zero);
    const tick = _Metrics.tick;
    final shape = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -tick.width / 2,
        -_Metrics.tickInner - tick.height,
        tick.width,
        tick.height,
      ),
      Radius.circular(tick.width / 2),
    );
    final paint = Paint();
    for (var i = 0; i < RefreshMotion.steps; i++) {
      final alpha = color.a * now.opacity * now.ticks[i];
      if (alpha <= 0) continue;
      paint.color = color.withValues(alpha: alpha);
      final angle = 2 * math.pi * (now.rotation + i / RefreshMotion.steps);
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(angle)
        ..drawRRect(shape, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_Ticks oldDelegate) =>
      !identical(drawn, oldDelegate.drawn) ||
      pulled != oldDelegate.pulled ||
      refreshing != oldDelegate.refreshing;
}

class _RefreshSliver extends SingleChildRenderObjectWidget {
  const _RefreshSliver({
    required this.inset,
    required this.extent,
    required this.holds,
    required this.dragging,
    required this.onPull,
    required super.child,
  });

  final double inset;
  final double extent;
  final bool holds;
  final bool Function() dragging;
  final void Function(double pull, {required bool triggered}) onPull;

  @override
  _RenderRefreshSliver createRenderObject(BuildContext context) =>
      _RenderRefreshSliver(
        inset: inset,
        extent: extent,
        holds: holds,
        dragging: dragging,
        onPull: onPull,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRefreshSliver renderObject,
  ) {
    renderObject
      ..inset = inset
      ..extent = extent
      ..holds = holds
      ..dragging = dragging
      ..onPull = onPull;
  }
}

/// The control's sliver: the inset over the content, the control's
/// height in it while it refreshes, and the control painted pinned under
/// the inset, cut where the content starts.
class _RenderRefreshSliver extends RenderSliver
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderRefreshSliver({
    required this._inset,
    required this._extent,
    required this._holds,
    required this.dragging,
    required this.onPull,
  });

  double _inset;
  double get inset => _inset;
  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsLayout();
  }

  double _extent;
  double get extent => _extent;
  set extent(double value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsLayout();
  }

  bool _holds;
  bool get holds => _holds;
  set holds(bool value) {
    if (value == _holds) return;
    _holds = value;
    markNeedsLayout();
  }

  bool Function() dragging;
  void Function(double pull, {required bool triggered}) onPull;

  // The control's height the scroll offset was last corrected for, so a
  // change of it leaves the content where it shows.
  double _held = 0;
  double _pull = -1;

  @override
  void performLayout() {
    final constraints = this.constraints;
    final over = constraints.overlap < 0 ? -constraints.overlap : 0.0;
    final pull = _holds ? 0.0 : over;
    final triggered =
        !_holds && over >= RefreshMotion.triggerPull && dragging();
    if (triggered) _holds = true;
    if (pull != _pull || triggered) {
      _pull = pull;
      onPull(pull, triggered: triggered);
    }
    final held = _holds ? _extent : 0.0;
    if (held != _held) {
      geometry = SliverGeometry(scrollOffsetCorrection: held - _held);
      _held = held;
      return;
    }
    child!.layout(
      BoxConstraints.tightFor(
        width: constraints.crossAxisExtent,
        height: _extent,
      ),
    );
    final extent = _inset + held;
    final shown = math.max<double>(0, extent - constraints.scrollOffset);
    final painted = shown + over;
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintOrigin: -over,
      paintExtent: math.min(painted, constraints.remainingPaintExtent + over),
      maxPaintExtent: painted,
      layoutExtent: math.min(shown, constraints.remainingPaintExtent),
      hasVisualOverflow: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final open = geometry!.paintExtent - _inset;
    if (open <= 0) return;
    final top = offset + Offset(0, _inset);
    context.pushClipRect(
      needsCompositing,
      top,
      Offset.zero & Size(constraints.crossAxisExtent, open),
      (context, offset) => context.paintChild(child!, offset),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(0, _inset, 0, 1);

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => false;
}
