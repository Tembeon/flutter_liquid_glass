import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// How large a [GlassActivityIndicator] is.
enum GlassActivityIndicatorSize {
  /// 20 points across (`UIActivityIndicatorView.Style.medium`).
  medium(20, inner: 3.5, outer: 10.17, spoke: 2.5),

  /// 37 points across (`UIActivityIndicatorView.Style.large`).
  large(37, inner: 5.9, outer: 17.4, spoke: 5);

  const GlassActivityIndicatorSize(
    this.extent, {
    required this.inner,
    required this.outer,
    required this.spoke,
  });

  /// The indicator's width and height.
  final double extent;

  /// How far from the center a spoke starts and ends, its rounded ends
  /// included.
  final double inner;

  /// How far from the center a spoke ends.
  final double outer;

  /// The width of a spoke.
  final double spoke;
}

/// An iOS activity indicator: eight spokes whose brightest one turns
/// round while a task runs.
///
/// UIKit: `UIActivityIndicatorView`. SwiftUI: `ProgressView()`. Flutter:
/// `CupertinoActivityIndicator`.
///
/// ```dart
/// GlassActivityIndicator(animating: loading)
/// ```
///
/// It turns once every 0.8 s in 16 steps of half a spoke, the brightest
/// spoke followed by a tail of four that fades to the rest
/// ([ActivityMotion]). Stopped, it keeps the step it stopped on and turns
/// on from it, and with [hidesWhenStopped] draws nothing while stopped,
/// keeping its place; it shows and hides at once, with no fade. Its color
/// is the secondary label's by default, darker with Increase Contrast.
/// Screen readers read it as [semanticLabel] while it shows.
///
/// Fidelity. The turn, the start and stop, the sizes and the spokes'
/// geometry are UIKit's (activity indicator passport: the turn confirmed
/// on an iPhone, the geometry from simulator stills); the brightness of a
/// spoke between two steps is this package's reading of UIKit's images.
class GlassActivityIndicator extends StatefulWidget {
  /// Creates an activity indicator.
  const GlassActivityIndicator({
    this.animating = true,
    this.size = GlassActivityIndicatorSize.medium,
    this.color,
    this.hidesWhenStopped = true,
    this.semanticLabel,
    super.key,
  });

  /// Whether it turns.
  final bool animating;

  /// How large it is.
  final GlassActivityIndicatorSize size;

  /// The spokes' color, or null for [GlassColors.secondaryLabel].
  final Color? color;

  /// Whether it draws nothing while it does not turn.
  final bool hidesWhenStopped;

  /// What screen readers read for it, or null for the localized loading
  /// label.
  final String? semanticLabel;

  @override
  State<GlassActivityIndicator> createState() => _GlassActivityIndicatorState();
}

class _GlassActivityIndicatorState extends State<GlassActivityIndicator> {
  late final _spin = ActivityMotion(clock: MotionClockScope.of(context));
  late final _image = _spin.select((spin) => spin.image);

  @override
  void initState() {
    super.initState();
    if (widget.animating) _spin.start(_spin.clock.now);
  }

  @override
  void didUpdateWidget(GlassActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _spin.start(_spin.clock.now);
    } else {
      _spin.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.animating || !widget.hidesWhenStopped;
    final spokes = _Spokes(
      image: _image,
      size: widget.size,
      color: GlassDynamicColor.resolve(
        widget.color ?? GlassColors.secondaryLabel,
        context,
      ),
      shown: shown,
    );
    if (!shown) return spokes;
    return Semantics(
      label:
          widget.semanticLabel ?? GlassLocalizations.of(context).loadingLabel,
      child: spokes,
    );
  }
}

class _Spokes extends LeafRenderObjectWidget {
  const _Spokes({
    required this.image,
    required this.size,
    required this.color,
    required this.shown,
  });

  final ValueListenable<int> image;
  final GlassActivityIndicatorSize size;
  final Color color;
  final bool shown;

  @override
  _RenderSpokes createRenderObject(BuildContext context) => _RenderSpokes(
    image: image,
    size: size,
    color: color,
    shown: shown,
    following: followsMotion(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSpokes renderObject) {
    renderObject
      ..indicatorSize = size
      ..color = color
      ..shown = shown
      ..following = followsMotion(context);
  }
}

class _RenderSpokes extends RenderBox {
  _RenderSpokes({
    required ValueListenable<int> image,
    required this._size,
    required this._color,
    required this._shown,
    required bool following,
  }) : _image = image,
       _follow = MotionFollow.render(following: following) {
    _follow.hear([(image, markNeedsPaint)]);
  }

  final ValueListenable<int> _image;
  final MotionFollow _follow;

  GlassActivityIndicatorSize _size;
  GlassActivityIndicatorSize get indicatorSize => _size;
  set indicatorSize(GlassActivityIndicatorSize value) {
    if (value == _size) return;
    _size = value;
    markNeedsLayoutForSizedByParentChange();
  }

  Color _color;
  Color get color => _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  bool _shown;
  bool get shown => _shown;
  set shown(bool value) {
    if (value == _shown) return;
    _shown = value;
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
      constraints.constrain(Size.square(_size.extent));

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_shown) return;
    final canvas = context.canvas;
    final image = _image.value;
    final center = size.center(offset);
    final width = _size.spoke;
    final paint = Paint()
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < ActivityMotion.spokes; i++) {
      paint.color = _color.withValues(
        alpha: _color.a * ActivityMotion.brightness(i, image),
      );
      final angle = 2 * math.pi * i / ActivityMotion.spokes - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (_size.inner + width / 2),
        center + direction * (_size.outer - width / 2),
        paint,
      );
    }
  }
}
