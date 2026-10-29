import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/page_control_motion.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
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

/// The look of a [GlassPageControl], like Flutter's `ButtonStyle`: every
/// field is resolved against the control's states, and a property that
/// gives null for a state leaves it to the theme's style, then the
/// default.
///
/// The defaults are approximations, not measured; the platter is a flat
/// color on every renderer where UIKit uses a material (page control
/// passport). Under Increase Contrast the dots take UIKit's high-contrast
/// colors (read from UIKit, notes private).
@immutable
class GlassPageControlStyle {
  /// Creates a style.
  const GlassPageControlStyle({
    this.pageIndicatorColor,
    this.currentPageIndicatorColor,
    this.platterColor,
    this.platterIndicatorColor,
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
    );
  }

  /// The style between [a] and [b] at [t].
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassPageControlStyle &&
      other.pageIndicatorColor == pageIndicatorColor &&
      other.currentPageIndicatorColor == currentPageIndicatorColor &&
      other.platterColor == platterColor &&
      other.platterIndicatorColor == platterIndicatorColor;

  @override
  int get hashCode => Object.hash(
    pageIndicatorColor,
    currentPageIndicatorColor,
    platterColor,
    platterIndicatorColor,
  );
}

/// A page control that looks and steps like iOS 27's `UIPageControl`.
///
/// UIKit: `UIPageControl`. SwiftUI: the page style of a `TabView`.
/// Flutter: none.
///
/// Dots for [count] pages, the current one opaque. A tap on the trailing
/// half moves to the next page and one on the leading half to the
/// previous page, on the lift, as UIKit's does; a finger that moves more
/// than 10 points scrubs to the nearest dot and plays a selection haptic
/// for each page it reaches (read from UIKit, notes private). With
/// [progress] the current indicator is a capsule whose fill shows how far
/// the page has progressed (`UIPageControlProgress`), and a page change
/// grows and shrinks the capsules on the measured springs. The platter
/// shows per [backgroundStyle], fading in after a touch rests 0.193 s. The
/// arrow keys and the accessibility increase and decrease step through
/// the pages; in a right-to-left context the pages run from the right. A
/// disabled control looks like an enabled one and ignores input, as
/// UIKit's does.
class GlassPageControl extends StatefulWidget {
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

  @override
  State<GlassPageControl> createState() => _GlassPageControlState();
}

class _GlassPageControlState extends State<GlassPageControl> {
  late _PageControlBody _body = _create();
  late final _PageControlInput _input = _PageControlInput(this);
  late final List<Interaction> _interactions = [_input];

  int get _count => math.max(0, widget.count);

  int get _page => _count == 0 ? 0 : widget.page.clamp(0, _count - 1);

  bool get _enabled => widget.onChanged != null && _count > 0;

  _PageControlBody _create() {
    final body = _PageControlBody(
      PageControlMotion(
        count: _count,
        page: _page,
        showsProgress: widget.progress != null,
      ),
      _deliver,
    );
    MotionClock.instance.addDriver(body);
    return body;
  }

  @override
  void didUpdateWidget(GlassPageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count ||
        (widget.progress == null) != (oldWidget.progress == null)) {
      _dispose(_body);
      _body = _create();
      return;
    }
    _body.setPage(_page);
  }

  @override
  void dispose() {
    _dispose(_body);
    super.dispose();
  }

  void _dispose(_PageControlBody body) {
    MotionClock.instance.removeDriver(body);
    body.dispose();
  }

  void _deliver(PageControlEvent event) {
    switch (event) {
      case PageControlPicked(:final page, :final scrubbed):
        if (page != _page) widget.onChanged?.call(page);
        if (scrubbed) HapticFeedback.selectionClick().ignore();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _body.setPage(_page);
        });
    }
  }

  void _step(int delta) {
    if (!_enabled) return;
    final next = (_page + delta).clamp(0, _count - 1);
    if (next != _page) widget.onChanged?.call(next);
  }

  Size get _size => Size(
    _body.motion.contentWidth + 2 * PageControlTuning.padding,
    PageControlTuning.height,
  );

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _input.rtl = rtl;
    final count = _count;
    final page = _page;
    String value(int page) =>
        widget.semanticValueFormatter?.call(page, count) ??
        'page $page of $count';
    final back = rtl ? 1 : -1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(back),
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
          child: _PageControlLook(
            body: _body,
            size: _size,
            rtl: rtl,
            background: widget.backgroundStyle,
            progress: widget.progress,
            style: (widget.style ?? const GlassPageControlStyle()).merge(
              GlassTheme.of(context).pageControlStyle,
            ),
          ),
        ),
      ),
    );
  }
}

/// The motion of a page control, stepped on the motion clock; the look
/// repaints from it.
final class _PageControlBody extends ChangeNotifier implements MotionDriver {
  _PageControlBody(this.motion, this._deliver);

  final PageControlMotion motion;
  final void Function(PageControlEvent event) _deliver;

  @override
  bool get isActive => !motion.isSettled;

  @override
  double? get wakeTime => motion.wakeTime;

  @override
  void step(double time) {
    motion.advance(time);
    if (motion.isSettled) motion.settle();
    notifyListeners();
    _drain();
  }

  void _drain() {
    for (final event in motion.drainEvents()) {
      _deliver(event);
    }
  }

  void _wake() => MotionClock.instance.wake(this);

  void setPage(int page) {
    if (page == motion.page) return;
    motion.setPage(MotionClock.instance.now, page);
    notifyListeners();
    _wake();
  }

  void down(double t, double x) {
    motion.pointerDown(t, x);
    _wake();
  }

  void move(double t, double x) {
    motion.pointerMove(t, x);
    notifyListeners();
    _drain();
    _wake();
  }

  void up(double t, double x, double width) {
    motion.pointerUp(t, x, width: width);
    notifyListeners();
    _drain();
    _wake();
  }

  void cancel(double t) {
    motion.pointerCancel(t);
    _wake();
  }
}

/// A page control's touch: taps and scrubs anywhere on it, held against a
/// scroll.
final class _PageControlInput extends Interaction {
  _PageControlInput(this.state) : super(role: InteractionRole.control);

  final _GlassPageControlState state;
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
    final body = state._body;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        body.down(input.time, _x(input.position));
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        body.move(input.time, _x(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        body.up(input.time, _x(input.position), state._size.width);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        body.cancel(input.time);
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

class _PageControlLook extends StatelessWidget {
  const _PageControlLook({
    required this.body,
    required this.size,
    required this.rtl,
    required this.background,
    required this.progress,
    required this.style,
  });

  final _PageControlBody body;
  final Size size;
  final bool rtl;
  final GlassPageControlBackground background;
  final double? progress;
  final GlassPageControlStyle style;

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
    const states = <WidgetState>{};
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    return CustomPaint(
      size: size,
      painter: _PageControlPainter(
        body: body,
        rtl: rtl,
        platter: switch (background) {
          GlassPageControlBackground.prominent => true,
          GlassPageControlBackground.minimal => false,
          GlassPageControlBackground.automatic => null,
        },
        progress: progress,
        pageIndicator: resolve(style.pageIndicatorColor, _pageIndicator),
        currentPageIndicator: resolve(
          style.currentPageIndicatorColor,
          const Color(0xFFFFFFFF),
        ),
        platterColor: resolve(style.platterColor, _platter),
        platterIndicator: resolve(
          style.platterIndicatorColor,
          _platterIndicator,
        ),
      ),
    );
  }
}

class _PageControlPainter extends CustomPainter {
  _PageControlPainter({
    required this.body,
    required this.rtl,
    required this.platter,
    required this.progress,
    required this.pageIndicator,
    required this.currentPageIndicator,
    required this.platterColor,
    required this.platterIndicator,
  }) : super(repaint: body);

  final _PageControlBody body;
  final bool rtl;
  final bool? platter;
  final double? progress;
  final Color pageIndicator;
  final Color currentPageIndicator;
  final Color platterColor;
  final Color platterIndicator;

  @override
  void paint(Canvas canvas, Size size) {
    final motion = body.motion;
    final shown = switch (platter) {
      true => 1.0,
      false => 0.0,
      null => motion.platter,
    };
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
    const dot = PageControlTuning.dotSize;
    const inset = (PageControlTuning.indicatorSize - dot) / 2;
    final cy = size.height / 2;
    var x = 0.0;
    for (var i = 0; i < motion.count; i++) {
      final w = motion.width(i);
      var cx = PageControlTuning.padding + x + w / 2;
      x += w + PageControlTuning.spacing;
      if (rtl) cx = size.width - cx;
      final shape = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w - 2 * inset,
          height: dot,
        ),
        const Radius.circular(dot / 2),
      );
      final base = Paint();
      base.color = progress == null && i == motion.page
          ? currentPageIndicator
          : other;
      canvas.drawRRect(shape, base);
      final fill = progress == null ? 0.0 : motion.fillOpacity(i);
      if (fill <= 0) continue;
      final fraction = i == motion.page ? (progress ?? 0) : 1.0;
      final fillWidth = dot + (shape.width - dot) * fraction.clamp(0, 1);
      final left = rtl ? shape.right - fillWidth : shape.left;
      final paint = Paint();
      paint.color = currentPageIndicator.withValues(
        alpha: currentPageIndicator.a * fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, shape.top, fillWidth, dot),
          const Radius.circular(dot / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PageControlPainter oldDelegate) =>
      oldDelegate.body != body ||
      oldDelegate.rtl != rtl ||
      oldDelegate.platter != platter ||
      oldDelegate.progress != progress ||
      oldDelegate.pageIndicator != pageIndicator ||
      oldDelegate.currentPageIndicator != currentPageIndicator ||
      oldDelegate.platterColor != platterColor ||
      oldDelegate.platterIndicator != platterIndicator;
}
