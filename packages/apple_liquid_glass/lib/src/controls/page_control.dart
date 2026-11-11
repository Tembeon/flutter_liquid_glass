import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/page_control_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
