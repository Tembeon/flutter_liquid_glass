import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// How a [GlassProgressView] draws.
enum GlassProgressViewStyle {
  /// A capsule 4 points tall over a gray track (`UIProgressView.Style
  /// .default`).
  standard(4, minimumFill: 8),

  /// A line 2.67 points tall with no track, as in a toolbar
  /// (`UIProgressView.Style.bar`).
  bar(2.67, minimumFill: 5.33);

  const GlassProgressViewStyle(this.height, {required this.minimumFill});

  /// The bar's height.
  final double height;

  /// The narrowest the fill draws, however little the progress.
  final double minimumFill;
}

/// An iOS progress bar: a fill that covers the bar as far as a task has
/// come.
///
/// UIKit: `UIProgressView`. SwiftUI: `ProgressView(value:)`. Flutter:
/// `LinearProgressIndicator`.
///
/// ```dart
/// GlassProgressView(value: downloaded / size)
/// ```
///
/// It is as wide as it is let be. With [animated] a change of [value]
/// moves at one bar a second, linearly, and at least 0.2 s where the fill
/// appears from 0 or goes to it, fading as it does; changes that overlap
/// add up, as UIKit's do ([ProgressMotion]). Without, it jumps. The fill
/// is never narrower than [GlassProgressViewStyle.minimumFill] and is not
/// drawn at 0; it grows from the leading side, so from the right in a
/// right-to-left app. The fill takes the theme's primary color and the
/// track a gray of its own unless [progressColor] or [trackColor] say
/// otherwise. Screen readers read [semanticLabel] with the progress as a
/// percentage.
///
/// Fidelity. The sizes, the colors in light, dark and Increase Contrast,
/// the speed, the fade and the additive changes are UIKit's (progress view
/// passport: the motion confirmed on an iPhone frame for frame); the dark
/// track under Increase Contrast is not measured and keeps the dark one.
/// [GlassProgressView.timer] runs as SwiftUI's
/// `ProgressView(timerInterval:)` is documented to, not measured.
/// UIKit's track and progress images and `observedProgress` have no
/// counterpart.
class GlassProgressView extends StatefulWidget {
  /// Creates a progress bar at [value], from 0 to [total], as SwiftUI's
  /// `ProgressView(value:total:)`.
  const GlassProgressView({
    required this.value,
    this.total = 1,
    this.style = GlassProgressViewStyle.standard,
    this.animated = true,
    this.progressColor,
    this.trackColor,
    this.semanticLabel,
    super.key,
  }) : assert(total > 0, 'A progress has a total above 0.'),
       assert(value >= 0 && value <= total, 'A progress is from 0 to total.'),
       start = null,
       end = null,
       countsDown = false;

  /// Creates a progress bar that runs over the time from [start] to [end]
  /// at a constant speed, as SwiftUI's
  /// `ProgressView(timerInterval:countsDown:)`: it empties as the time
  /// passes when [countsDown], and fills otherwise. Outside the interval it
  /// stands at its end.
  const GlassProgressView.timer({
    required DateTime this.start,
    required DateTime this.end,
    this.countsDown = true,
    this.style = GlassProgressViewStyle.standard,
    this.progressColor,
    this.trackColor,
    this.semanticLabel,
    super.key,
  }) : value = 0,
       total = 1,
       animated = true;

  /// How far the task has come, from 0 to [total].
  final double value;

  /// The value of a finished task.
  final double total;

  /// Where a [GlassProgressView.timer] starts, or null for one of [value].
  final DateTime? start;

  /// Where a [GlassProgressView.timer] ends.
  final DateTime? end;

  /// Whether a [GlassProgressView.timer] empties as its time passes.
  final bool countsDown;

  /// How it draws.
  final GlassProgressViewStyle style;

  /// Whether a change of [value] moves there or jumps.
  final bool animated;

  /// The fill's color, or null for the theme's primary color.
  final Color? progressColor;

  /// The track's color, or null for its gray; the bar style draws none.
  final Color? trackColor;

  /// What screen readers read for it, or null for nothing but its value.
  final String? semanticLabel;

  /// The track: 120, 120, 128 at 0.2 in light, 0.36 in dark and about
  /// 0.28 with Increase Contrast.
  static const track = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x33787880),
    darkColor: Color(0x5C787880),
    highContrastColor: Color(0x47787880),
    darkHighContrastColor: Color(0x5C787880),
  );

  @override
  State<GlassProgressView> createState() => _GlassProgressViewState();
}

class _GlassProgressViewState extends State<GlassProgressView> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final _motion = _start();

  ProgressMotion _start() {
    final motion = ProgressMotion(progress: _fraction, clock: _clock);
    _runTimer(motion);
    return motion;
  }

  // The fraction the bar stands at now: of the value, or of the time.
  double get _fraction {
    final start = widget.start;
    final end = widget.end;
    if (start == null || end == null) return widget.value / widget.total;
    final span = end.difference(start).inMicroseconds;
    final passed = DateTime.now().difference(start).inMicroseconds;
    final share = span <= 0 ? 1.0 : (passed / span).clamp(0.0, 1.0);
    return widget.countsDown ? 1 - share : share;
  }

  void _runTimer(ProgressMotion motion) {
    final end = widget.end;
    if (widget.start == null || end == null) return;
    final left =
        end.difference(DateTime.now()).inMicroseconds /
        Duration.microsecondsPerSecond;
    motion.run(
      _clock.now,
      _fraction,
      widget.countsDown ? 0 : 1,
      left.clamp(0, double.infinity),
    );
  }

  @override
  void didUpdateWidget(GlassProgressView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.start != null) {
      if (widget.start != oldWidget.start ||
          widget.end != oldWidget.end ||
          widget.countsDown != oldWidget.countsDown) {
        _runTimer(_motion);
      }
      return;
    }
    _motion.set(_fraction, animated: widget.animated);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Semantics(
      label: widget.semanticLabel,
      value: GlassLocalizations.of(context).percentValue(_fraction),
      child: SizedBox(
        width: double.infinity,
        height: style.height,
        child: CustomPaint(
          painter: _ProgressPainter(
            fraction: _motion.fraction,
            opacity: _motion.opacity,
            style: style,
            fill: GlassDynamicColor.resolve(
              widget.progressColor ??
                  GlassTheme.primaryColorOf(context) ??
                  GlassColors.systemBlue,
              context,
            ),
            track: style == GlassProgressViewStyle.bar
                ? null
                : GlassDynamicColor.resolve(
                    widget.trackColor ?? GlassProgressView.track,
                    context,
                  ),
            direction: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.fraction,
    required this.opacity,
    required this.style,
    required this.fill,
    required this.track,
    required this.direction,
  }) : super(repaint: Listenable.merge([fraction, opacity]));

  final MotionValue<double> fraction;
  final MotionValue<double> opacity;
  final GlassProgressViewStyle style;
  final Color fill;
  final Color? track;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = this.track;
    if (track != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, radius),
        Paint()..color = track,
      );
    }
    final shown = opacity.value.clamp(0.0, 1.0);
    if (shown <= 0) return;
    final width = math.min(
      size.width,
      math.max(style.minimumFill, fraction.value * size.width),
    );
    final left = direction == TextDirection.rtl ? size.width - width : 0.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, width, size.height),
        radius,
      ),
      Paint()..color = fill.withValues(alpha: fill.a * shown),
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) =>
      !identical(fraction, oldDelegate.fraction) ||
      style != oldDelegate.style ||
      fill != oldDelegate.fill ||
      track != oldDelegate.track ||
      direction != oldDelegate.direction;
}
