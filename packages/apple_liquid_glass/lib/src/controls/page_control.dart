import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/page_control_motion.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// When a page control shows the platter behind its dots.
///
/// UIKit: `UIPageControl.BackgroundStyle`.
enum GlassPageControlBackground {
  /// Only while the user interacts with the control.
  automatic,

  /// Always.
  prominent,

  /// Never.
  minimal,
}

/// Builds a page control from [details]; it runs again when the control's
/// states or progress change, never while it moves.
typedef GlassPageControlBuilder = Widget Function(
  BuildContext context,
  GlassPageControlDetails details,
);

/// What a [GlassPageControlBuilder] builds a page control from.
@immutable
final class GlassPageControlDetails {
  /// Describes a page control.
  const GlassPageControlDetails({
    required this.pose,
    required this.progress,
    required this.states,
  });

  /// Where the indicators sit and how they show, as the control moves.
  final MotionSelection<GlassPageControlPose> pose;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots.
  final double? progress;

  /// The states the control is in; [WidgetState.disabled] while it ignores
  /// input.
  final Set<WidgetState> states;
}

/// A page control's indicators at one moment, in the control's box.
@immutable
final class GlassPageControlPose {
  /// Describes the indicators.
  const GlassPageControlPose({
    required this.indicators,
    required this.fills,
    required this.platter,
    required this.page,
  });

  factory GlassPageControlPose._of(
    PageControlMotion motion, {
    required GlassPageControlBackground background,
    required bool rtl,
  }) {
    const dot = PageControlTuning.dotSize;
    const inset = (PageControlTuning.indicatorSize - dot) / 2;
    const cy = PageControlTuning.height / 2;
    final width = motion.contentWidth + 2 * PageControlTuning.padding;
    var x = 0.0;
    final indicators = <Rect>[];
    for (var i = 0; i < motion.count; i++) {
      final w = motion.width(i);
      var cx = PageControlTuning.padding + x + w / 2;
      x += w + PageControlTuning.spacing;
      if (rtl) cx = width - cx;
      indicators.add(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w - 2 * inset,
          height: dot,
        ),
      );
    }
    return GlassPageControlPose(
      indicators: indicators,
      fills: [for (var i = 0; i < motion.count; i++) motion.fillOpacity(i)],
      platter: switch (background) {
        GlassPageControlBackground.prominent => 1,
        GlassPageControlBackground.minimal => 0,
        GlassPageControlBackground.automatic => motion.platter,
      },
      page: motion.page,
    );
  }

  /// Each page's indicator box, a dot tall and as wide as the indicator, in
  /// which a look draws a capsule; mirrored in a right-to-left context.
  final List<Rect> indicators;

  /// How far each indicator's fill shows, 0 to 1: 1 on the current page,
  /// fading on the page just left, 0 elsewhere. The default look draws the
  /// fill only while the control shows a progress.
  final List<double> fills;

  /// How far the platter behind the indicators shows, 0 to 1.
  final double platter;

  /// The page the indicators show as current.
  final int page;

  @override
  bool operator ==(Object other) =>
      other is GlassPageControlPose &&
      other.platter == platter &&
      other.page == page &&
      listEquals(other.indicators, indicators) &&
      listEquals(other.fills, fills);

  @override
  int get hashCode => Object.hash(
    platter,
    page,
    Object.hashAll(indicators),
    Object.hashAll(fills),
  );
}

/// A page control with the measured motion of iOS 27's `UIPageControl` and
/// no look of its own: [builder] decides how it looks.
///
/// UIKit: `UIPageControl`. SwiftUI: the page style of a `TabView`.
/// Flutter: none.
///
/// It has an indicator for each of [count] pages. A tap on the trailing
/// half moves to the next page and one on the leading half to the
/// previous page, on the lift, as UIKit's does; a finger that moves more
/// than 10 points scrubs to the nearest indicator and plays a selection
/// haptic each time it changes the page (read from UIKit, notes private).
/// With [progress] the current indicator widens into a capsule
/// (`UIPageControlProgress`), and a page change grows and shrinks the
/// capsules on the measured springs. The platter shows per
/// [backgroundStyle], fading in after a touch rests 0.193 s. The arrow keys
/// and the accessibility increase and decrease step through the pages; in a
/// right-to-left context the pages run from the right.
class RawGlassPageControl extends StatefulWidget {
  /// Creates a page control of [count] pages showing [page].
  const RawGlassPageControl({
    required this.count,
    required this.page,
    required this.onChanged,
    required this.builder,
    this.progress,
    this.backgroundStyle = GlassPageControlBackground.automatic,
    this.semanticLabel,
    this.semanticValueFormatter,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control. A
  /// control whose [page] does not follow returns to it.
  final ValueChanged<int>? onChanged;

  /// Builds the control's look.
  final GlassPageControlBuilder builder;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// indicators.
  final double? progress;

  /// When the platter shows.
  final GlassPageControlBackground backgroundStyle;

  /// What accessibility reads for the control.
  final String? semanticLabel;

  /// Formats the adjustable value from a one-based page and the page count;
  /// null reads "page n of count". An empty control has no value.
  final String Function(int page, int count)? semanticValueFormatter;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  @override
  State<RawGlassPageControl> createState() => _RawGlassPageControlState();
}

class _RawGlassPageControlState extends State<RawGlassPageControl> {
  late PageControlMotion _motion = _create();
  late MotionSelection<GlassPageControlPose> _pose = _poseOf();
  late final _PageControlInput _input = _PageControlInput(this);
  late final List<Interaction> _interactions = [_input];

  int get _count => math.max(0, widget.count);

  int get _page => _count == 0 ? 0 : widget.page.clamp(0, _count - 1);

  bool get _enabled => widget.onChanged != null && _count > 0;

  PageControlMotion _create() => PageControlMotion(
    count: _count,
    page: _page,
    showsProgress: widget.progress != null,
    onEvent: _deliver,
  );

  MotionSelection<GlassPageControlPose> _poseOf() {
    final background = widget.backgroundStyle;
    final rtl = _input.rtl;
    return _motion.select(
      (m) => GlassPageControlPose._of(m, background: background, rtl: rtl),
    );
  }

  @override
  void didUpdateWidget(RawGlassPageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count ||
        (widget.progress == null) != (oldWidget.progress == null)) {
      _motion = _create();
      _pose = _poseOf();
      return;
    }
    if (widget.backgroundStyle != oldWidget.backgroundStyle) _pose = _poseOf();
    _setPage(_page);
  }

  void _setPage(int page) {
    if (page == _motion.page) return;
    _motion.setPage(MotionClock.instance.now, page);
  }

  void _deliver(PageControlEvent event) {
    switch (event) {
      case PageControlPicked(:final page, :final scrubbed):
        if (page != _page) widget.onChanged?.call(page);
        if (scrubbed) MotionHaptic.selection.play();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setPage(_page);
        });
    }
  }

  void _step(int delta) {
    if (!_enabled) return;
    final next = (_page + delta).clamp(0, _count - 1);
    if (next != _page) widget.onChanged?.call(next);
  }

  Size get _size => Size(
    _motion.contentWidth + 2 * PageControlTuning.padding,
    PageControlTuning.height,
  );

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl != _input.rtl) {
      _input.rtl = rtl;
      _pose = _poseOf();
    }
    final count = _count;
    final page = _page;
    String value(int page) =>
        widget.semanticValueFormatter?.call(page, count) ??
        'page $page of $count';
    final back = rtl ? 1 : -1;
    return MotionScope(
      motion: _motion,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _step(back),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _step(-back),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _step(1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _step(-1),
        },
        child: Semantics(
          container: true,
          label: widget.semanticLabel,
          value: count == 0 ? null : value(page + 1),
          increasedValue: page + 1 < count ? value(page + 2) : null,
          decreasedValue: page > 0 ? value(page) : null,
          onIncrease: _enabled && page + 1 < count ? () => _step(1) : null,
          onDecrease: _enabled && page > 0 ? () => _step(-1) : null,
          child: InputRegion(
            interactions: _interactions,
            enabled: _enabled,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            child: SizedBox.fromSize(
              size: _size,
              child: widget.builder(
                context,
                GlassPageControlDetails(
                  pose: _pose,
                  progress: widget.progress,
                  states: {if (!_enabled) WidgetState.disabled},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page control's touch: taps and scrubs anywhere on it, held against a
/// scroll.
final class _PageControlInput extends Interaction {
  _PageControlInput(this.state) : super(role: InteractionRole.control);

  final _RawGlassPageControlState state;
  bool rtl = false;
  int? _pointer;

  @override
  bool get pressed => _pointer != null;

  double _x(Offset position) {
    final width = state._size.width;
    final x = rtl ? width - position.dx : position.dx;
    return x - PageControlTuning.padding;
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    final motion = state._motion;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        motion.pointerDown(input.time, _x(input.position));
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        motion.pointerMove(input.time, _x(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        motion.pointerUp(
          input.time,
          _x(input.position),
          width: state._size.width,
        );
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        motion.pointerCancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The look of a [GlassPageControl], like Flutter's `ButtonStyle`. Every
/// field but [builder] resolves against the control's states
/// ([WidgetState.disabled] while it ignores input); a null leaves the field
/// to the theme's style, then the default.
///
/// The defaults are approximations, not measured, except the dots'
/// Increase Contrast colors, read from UIKit (notes private); the platter
/// is a flat color on every renderer where UIKit uses a material (page
/// control passport).
@immutable
class GlassPageControlStyle {
  /// Creates a style.
  const GlassPageControlStyle({
    this.pageIndicatorColor,
    this.currentPageIndicatorColor,
    this.platterColor,
    this.platterIndicatorColor,
    this.builder,
  });

  /// The dots of the other pages (UIKit `pageIndicatorTintColor`).
  final WidgetStateProperty<Color?>? pageIndicatorColor;

  /// The dot of the current page and a progress's fill (UIKit
  /// `currentPageIndicatorTintColor`).
  final WidgetStateProperty<Color?>? currentPageIndicatorColor;

  /// The platter behind the dots.
  final WidgetStateProperty<Color?>? platterColor;

  /// The dots of the other pages over the platter.
  final WidgetStateProperty<Color?>? platterIndicatorColor;

  /// Builds the control in place of its default look, which then ignores
  /// the other fields. Null leaves it to the theme's builder, then the
  /// default look.
  final GlassPageControlBuilder? builder;

  /// This style over [other], state by state.
  GlassPageControlStyle merge(GlassPageControlStyle? other) {
    if (other == null) return this;
    return GlassPageControlStyle(
      pageIndicatorColor: fallThrough(
        pageIndicatorColor,
        other.pageIndicatorColor,
      ),
      currentPageIndicatorColor: fallThrough(
        currentPageIndicatorColor,
        other.currentPageIndicatorColor,
      ),
      platterColor: fallThrough(platterColor, other.platterColor),
      platterIndicatorColor: fallThrough(
        platterIndicatorColor,
        other.platterIndicatorColor,
      ),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// half.
  static GlassPageControlStyle? lerp(
    GlassPageControlStyle? a,
    GlassPageControlStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassPageControlStyle(
      pageIndicatorColor: color(a.pageIndicatorColor, b.pageIndicatorColor),
      currentPageIndicatorColor: color(
        a.currentPageIndicatorColor,
        b.currentPageIndicatorColor,
      ),
      platterColor: color(a.platterColor, b.platterColor),
      platterIndicatorColor: color(
        a.platterIndicatorColor,
        b.platterIndicatorColor,
      ),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassPageControlStyle &&
      other.pageIndicatorColor == pageIndicatorColor &&
      other.currentPageIndicatorColor == currentPageIndicatorColor &&
      other.platterColor == platterColor &&
      other.platterIndicatorColor == platterIndicatorColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    pageIndicatorColor,
    currentPageIndicatorColor,
    platterColor,
    platterIndicatorColor,
    builder,
  );
}

/// A page control that looks and steps like iOS 27's `UIPageControl`.
///
/// UIKit: `UIPageControl`. SwiftUI: the page style of a `TabView`.
/// Flutter: none.
///
/// Dots for [count] pages, the current one opaque; with [progress] the
/// current indicator is a capsule whose fill shows how far the page has
/// progressed. Its motion and input are [RawGlassPageControl]'s. A
/// disabled control looks like an enabled one and ignores input, as
/// UIKit's does.
class GlassPageControl extends StatelessWidget {
  /// Creates a page control of [count] pages showing [page].
  const GlassPageControl({
    required this.count,
    required this.page,
    required this.onChanged,
    this.progress,
    this.backgroundStyle = GlassPageControlBackground.automatic,
    this.style,
    this.semanticLabel,
    this.semanticValueFormatter,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control. A
  /// control whose [page] does not follow returns to it.
  final ValueChanged<int>? onChanged;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots.
  final double? progress;

  /// When the platter shows.
  final GlassPageControlBackground backgroundStyle;

  /// The look, over the theme's and the control's defaults.
  final GlassPageControlStyle? style;

  /// What accessibility reads for the control.
  final String? semanticLabel;

  /// Formats the adjustable value from a one-based page and the page count;
  /// null reads "page n of count". An empty control has no value.
  final String Function(int page, int count)? semanticValueFormatter;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassPageControlStyle styleFrom({
    Color? pageIndicatorColor,
    Color? currentPageIndicatorColor,
    Color? platterColor,
    Color? platterIndicatorColor,
  }) => GlassPageControlStyle(
    pageIndicatorColor: allStates(pageIndicatorColor),
    currentPageIndicatorColor: allStates(currentPageIndicatorColor),
    platterColor: allStates(platterColor),
    platterIndicatorColor: allStates(platterIndicatorColor),
  );

  static const _pageIndicator = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x73FFFFFF),
    darkColor: Color(0x73FFFFFF),
    highContrastColor: Color(0x8CFFFFFF),
    darkHighContrastColor: Color(0x8CFFFFFF),
  );
  static const _platter = GlassDynamicColor.withBrightness(
    color: Color(0xFFF0F0F2),
    darkColor: Color(0xFF1F1F1F),
  );
  static const _platterIndicator = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x40000000),
    darkColor: Color(0x4DFFFFFF),
    highContrastColor: Color(0x73000000),
    darkHighContrastColor: Color(0x73FFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassPageControlStyle()).merge(
      GlassTheme.of(context).pageControlStyle,
    );
    return RawGlassPageControl(
      count: count,
      page: page,
      onChanged: onChanged,
      progress: progress,
      backgroundStyle: backgroundStyle,
      semanticLabel: semanticLabel,
      semanticValueFormatter: semanticValueFormatter,
      focusNode: focusNode,
      autofocus: autofocus,
      builder:
          look.builder ??
          (context, details) => _defaultBody(context, details, look),
    );
  }

  Widget _defaultBody(
    BuildContext context,
    GlassPageControlDetails details,
    GlassPageControlStyle look,
  ) {
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(details.states) ?? fallback,
          context,
        );
    return CustomPaint(
      painter: _PageControlPainter(
        pose: details.pose,
        rtl: Directionality.maybeOf(context) == TextDirection.rtl,
        progress: details.progress,
        pageIndicator: resolve(look.pageIndicatorColor, _pageIndicator),
        currentPageIndicator: resolve(
          look.currentPageIndicatorColor,
          const Color(0xFFFFFFFF),
        ),
        platterColor: resolve(look.platterColor, _platter),
        platterIndicator: resolve(
          look.platterIndicatorColor,
          _platterIndicator,
        ),
      ),
    );
  }
}

class _PageControlPainter extends CustomPainter {
  _PageControlPainter({
    required this.pose,
    required this.rtl,
    required this.progress,
    required this.pageIndicator,
    required this.currentPageIndicator,
    required this.platterColor,
    required this.platterIndicator,
  }) : super(repaint: pose);

  final ValueListenable<GlassPageControlPose> pose;
  final bool rtl;
  final double? progress;
  final Color pageIndicator;
  final Color currentPageIndicator;
  final Color platterColor;
  final Color platterIndicator;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = pose.value;
    final shown = frame.platter;
    if (shown > 0) {
      final paint = Paint();
      paint.color = platterColor.withValues(alpha: platterColor.a * shown);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        paint,
      );
    }
    final other = Color.lerp(pageIndicator, platterIndicator, shown)!;
    for (var i = 0; i < frame.indicators.length; i++) {
      final rect = frame.indicators[i];
      final radius = Radius.circular(rect.height / 2);
      final base = Paint();
      base.color = progress == null && i == frame.page
          ? currentPageIndicator
          : other;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), base);
      final fill = progress == null ? 0.0 : frame.fills[i];
      if (fill <= 0) continue;
      final fraction = i == frame.page ? (progress ?? 0) : 1.0;
      final fillWidth =
          rect.height + (rect.width - rect.height) * fraction.clamp(0, 1);
      final left = rtl ? rect.right - fillWidth : rect.left;
      final paint = Paint();
      paint.color = currentPageIndicator.withValues(
        alpha: currentPageIndicator.a * fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, rect.top, fillWidth, rect.height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PageControlPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.rtl != rtl ||
      oldDelegate.progress != progress ||
      oldDelegate.pageIndicator != pageIndicator ||
      oldDelegate.currentPageIndicator != currentPageIndicator ||
      oldDelegate.platterColor != platterColor ||
      oldDelegate.platterIndicator != platterIndicator;
}
