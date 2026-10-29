import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:apple_liquid_glass/src/chrome/bar_entry.dart';
import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of a [GlassNavigationBar].
@immutable
class GlassNavigationBarStyle {
  /// Creates a style.
  const GlassNavigationBarStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.titleTextStyle,
    this.largeTitleTextStyle,
  });

  /// A fill behind the bar (UIKit `backgroundColor` of the bar's
  /// appearance); none by default, as iOS 27's bar shows the content under
  /// it through its edge effect.
  final Color? backgroundColor;

  /// The color of the titles; [GlassColors.label] by default.
  final Color? foregroundColor;

  /// The inline title's style: 17 points semibold by default.
  final TextStyle? titleTextStyle;

  /// The large title's style: 34 points bold by default.
  final TextStyle? largeTitleTextStyle;

  /// This style over [other]: a null field takes [other]'s.
  GlassNavigationBarStyle merge(GlassNavigationBarStyle? other) {
    if (other == null) return this;
    return GlassNavigationBarStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      foregroundColor: foregroundColor ?? other.foregroundColor,
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      largeTitleTextStyle:
          other.largeTitleTextStyle?.merge(largeTitleTextStyle) ??
          largeTitleTextStyle,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassNavigationBarStyle? lerp(
    GlassNavigationBarStyle? a,
    GlassNavigationBarStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    final color = snapNull(GlassDynamicColor.lerp);
    final text = snapNull(TextStyle.lerp);
    return GlassNavigationBarStyle(
      backgroundColor: color(a.backgroundColor, b.backgroundColor, t),
      foregroundColor: color(a.foregroundColor, b.foregroundColor, t),
      titleTextStyle: text(a.titleTextStyle, b.titleTextStyle, t),
      largeTitleTextStyle: text(
        a.largeTitleTextStyle,
        b.largeTitleTextStyle,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassNavigationBarStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.titleTextStyle == titleTextStyle &&
      other.largeTitleTextStyle == largeTitleTextStyle;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    titleTextStyle,
    largeTitleTextStyle,
  );
}

/// An iOS 27 navigation bar.
///
/// UIKit: `UINavigationBar` with a `UINavigationItem`. SwiftUI: the bar of
/// a `NavigationStack`. Flutter: `CupertinoNavigationBar`,
/// `CupertinoSliverNavigationBar`.
///
/// A row 54 points tall under the status bar: [leading] and [trailing]
/// glass capsules 16 points in from the sides, centered 22 points below
/// the status bar, and [title] centered on the bar when it fits between
/// them, else from the leading side, truncated (navigation bar passport,
/// 46 bars within 1 point). With a [largeTitle] the bar is 52 points
/// taller: the large title sits under the row and scrolls away with the
/// content of the page's [GlassContentScroll], after which the inline
/// title rises in, 0.45 s in and 0.7 s out, from 15 points below and
/// blurred (fitted on the device, read from UIKit); a jump of the content
/// switches it at once. A finger's release that leaves the large title
/// partly away springs to the nearer end. Put it in a [GlassPageScaffold].
///
/// The pages of one navigator pushed as `GlassPageRoute`s share one bar,
/// as UIKit's navigation controller does: on a push, a pop and an edge
/// swipe its glass stays in place and the capsules change into the next
/// page's, each side into itself, groups growing out of a capsule of
/// their side or appearing in place with a swell, items travelling,
/// timed from the push or pop call (device recordings, replayed); during
/// a swipe the capsules the page below also has lean halfway toward their
/// places there at most. The titles belong to the page and move with it.
/// A page with a glass page below gets a back button, named after that
/// page's title, as the first leading capsule; [leading] replaces it and
/// [automaticallyImplyLeading] false removes it. Elsewhere, the bar draws
/// its capsules for its page alone.
class GlassNavigationBar extends StatefulWidget implements ChromeBarWidget {
  /// Creates a navigation bar.
  const GlassNavigationBar({
    this.leading = const [],
    this.title,
    this.largeTitle,
    this.trailing = const [],
    this.automaticallyImplyLeading = true,
    this.previousPageTitle,
    this.backButtonDisplayMode = GlassBackButtonDisplayMode.title,
    this.style,
    super.key,
  });

  /// The capsules at the leading edge; when not empty they replace the
  /// back button (UIKit `leftBarButtonItems`).
  final List<GlassBarEntry> leading;

  /// The inline title; [largeTitle] when null.
  final Widget? title;

  /// The large title under the row, or null for an inline title only.
  final Widget? largeTitle;

  /// The capsules at the trailing edge (UIKit `rightBarButtonItems`).
  final List<GlassBarEntry> trailing;

  /// Whether the page gets a back button when [leading] is empty and a
  /// glass page lies below (UIKit `hidesBackButton` false).
  final bool automaticallyImplyLeading;

  /// The back button's name for the page below, in place of that page's
  /// title.
  final String? previousPageTitle;

  /// How the back button names the page below.
  final GlassBackButtonDisplayMode backButtonDisplayMode;

  /// The look, over the theme's.
  final GlassNavigationBarStyle? style;

  /// The height of the row under the status bar (navigation bar passport).
  static const double height = 54;

  /// The height a large title adds under the row (navigation bar
  /// passport).
  static const double largeTitleHeight = 52;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (largeTitle == null ? 0 : largeTitleHeight));

  @override
  ChromeBar get chromeBar => ChromeBar.navigation;

  @override
  double get scrolledUnderAfter => largeTitle == null ? 0 : largeTitleHeight;

  @override
  State<GlassNavigationBar> createState() => _GlassNavigationBarState();
}

class _GlassNavigationBarState extends State<GlassNavigationBar> {
  late final _title = MotionValue<double>(
    widget.largeTitle == null ? 1 : 0,
    spring: _Metrics.showSpring,
    restDistance: GlassRest.opacity,
  );
  late final _opacity = MotionComputed(() => _title.value.clamp(0.0, 1.0));
  late final _rise = MotionComputed(
    () => _reduceMotion ? 0.0 : _Metrics.hiddenOffset * (1 - _opacity.value),
  );
  late final _blur = MotionComputed(
    () => _reduceMotion ? 0.0 : _Metrics.hiddenBlur * (1 - _opacity.value),
  );
  final _scroll = ValueNotifier<MotionScrollObserver?>(null);
  ValueNotifier<MotionScrollObserver?>? _active;
  bool _reduceMotion = false;
  bool _laidOut = false;
  GlassPageBarLink? _link;
  GlassBarHost? _standalone;

  GlassPageBarLink get _barLink => _link ?? _standalone!.standaloneLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _link = GlassPageBarLink.maybeOf(context);
    if (_link == null) {
      _standalone ??= GlassBarHost.standalone();
    } else if (_standalone case final host?) {
      host.detach(host.standaloneLink);
      _standalone = null;
    }
    _reduceMotion = GlassTraits.of(context).reduceMotion;
    final active = GlassChrome.maybeOf(context)?.active;
    if (identical(active, _active)) return;
    _active?.removeListener(_follow);
    _active = active;
    active?.addListener(_follow);
    _follow();
  }

  @override
  void didUpdateWidget(GlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.largeTitle == null) != (widget.largeTitle == null)) {
      _laidOut = false;
      _scrolled();
    }
  }

  @override
  void dispose() {
    if (_standalone case final host?) host.detach(host.standaloneLink);
    _active?.removeListener(_follow);
    _scroll.value?.removeListener(_scrolled);
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    final next = _active?.value;
    final previous = _scroll.value;
    if (identical(next, previous)) return;
    previous?.removeListener(_scrolled);
    next?.addListener(_scrolled);
    _scroll.value = next;
    _laidOut = false;
    _scrolled();
  }

  void _scrolled() {
    final metrics = _scroll.value?.metrics;
    final laidOut = metrics != null && metrics.hasContentDimensions;
    final shown =
        widget.largeTitle == null ||
        (laidOut &&
            metrics.pixels - metrics.minScrollExtent >=
                GlassNavigationBar.largeTitleHeight - 0.5);
    final target = shown ? 1.0 : 0.0;
    final appears = !_laidOut;
    _laidOut = laidOut;
    if (_title.target == target) return;
    final now = MotionClock.instance.now;
    // A jump of the content switches the title at once, as UIKit does.
    final moving = _scroll.value?.position?.isScrollingNotifier.value ?? false;
    if (appears || _reduceMotion || !moving) {
      _title.snap(now, target);
    } else {
      _title.retarget(
        now,
        target,
        spring: shown ? _Metrics.showSpring : _Metrics.hideSpring,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final look = (widget.style ?? const GlassNavigationBarStyle()).merge(
      theme.navigationBarStyle,
    );
    final color = GlassDynamicColor.resolve(
      look.foregroundColor ?? theme.colorScheme?.label ?? GlassColors.label,
      context,
    );
    final title = widget.title ?? widget.largeTitle;
    final largeTitle = widget.largeTitle;
    final background = look.backgroundColor;
    final link = _barLink;
    link.host.declare(
      link,
      GlassBarDeclaration(
        leading: widget.leading,
        trailing: widget.trailing,
        automaticallyImplyLeading: widget.automaticallyImplyLeading,
        previousPageTitle: widget.previousPageTitle,
        backButtonDisplayMode: widget.backButtonDisplayMode,
        title: switch (title) {
          Text(:final data?) => data,
          _ => null,
        },
      ),
    );
    final standalone = _standalone;
    final row = SizedBox(
      height: GlassNavigationBar.height,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          if (standalone != null)
            MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: GlassBarView(
                host: standalone,
                only: GlassBarKind.navigation,
              ),
            ),
          if (title != null)
            CustomSingleChildLayout(
              delegate: _TitleLayout(
                link.titleRoom,
                Directionality.of(context),
              ),
              child: MotionTransition(
                opacity: _opacity,
                translateY: _rise,
                blur: _blur,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _Metrics.maxTextScale,
                  child: Builder(
                    builder: (context) => DefaultTextStyle(
                      style: resolveGlassText(
                        _Metrics.title
                            .merge(look.titleTextStyle)
                            .copyWith(color: color),
                        context,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: Semantics(header: true, child: title),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (largeTitle != null)
          SizedBox(
            height: GlassNavigationBar.largeTitleHeight,
            child: _ScrollAway(
              scroll: _scroll,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: _Metrics.largeTitleInset,
                  end: _Metrics.largeTitleInset,
                  top: _Metrics.largeTitleTop,
                ),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1,
                    child: Builder(
                      builder: (context) => DefaultTextStyle(
                        style: resolveGlassText(
                          _Metrics.largeTitle
                              .merge(look.largeTitleTextStyle)
                              .copyWith(color: color),
                          context,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: Semantics(header: true, child: largeTitle),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (background == null) return bar;
    return ColoredBox(
      color: GlassDynamicColor.resolve(background, context),
      child: bar,
    );
  }
}

abstract final class _Metrics {
  /// The space between the screen's sides and the outer items on a 402
  /// point wide screen (20 on the 440 point Pro Max).
  static const double sideInset = 16;

  /// How far below the status bar the capsules and the inline title are
  /// centered: the capsules sit at the row's top (device recordings).
  static const double capsuleCenter = 22;

  /// The leading inset of the large title.
  static const double largeTitleInset = 16;

  /// The space between the top of the large title area and its text.
  static const double largeTitleTop = 3.67;

  /// The largest text scale the inline title follows.
  static const double maxTextScale = 1.25;

  /// How far below its place the hidden inline title sits.
  static const double hiddenOffset = 15;

  /// The blur of the hidden inline title.
  static const double hiddenBlur = 4;

  /// The spring the inline title rises in on (fitted 0.45 - 0.48 s,
  /// damping 0.98 - 1.0).
  static const showSpring = Spring.response(0.45);

  /// The spring the inline title leaves on (fitted 0.68 s, damping 0.98).
  static const hideSpring = Spring.response(0.7);

  /// The inline title: UIKit's title role, 17 points semibold, in the
  /// line box UIKit's bar labels lay out in.
  static const title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// The large title: 34 points bold.
  static const largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// Lays the inline title out as UIKit does: on the bar's center, 22
/// points below the status bar like the capsules, when it fits in the
/// [room] between the page's capsules; else from the room's leading end,
/// truncated at the other.
class _TitleLayout extends SingleChildLayoutDelegate {
  _TitleLayout(this.room, this.direction) : super(relayout: room);

  final ValueListenable<GlassTitleRoom?> room;
  final TextDirection direction;

  GlassTitleRoom _roomIn(Size size) =>
      room.value ??
      (start: _Metrics.sideInset, end: size.width - _Metrics.sideInset);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = _roomIn(constraints.biggest);
    return BoxConstraints(
      maxWidth: math.max(0, room.end - room.start),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = _roomIn(size);
    final center = size.width / 2;
    final half = childSize.width / 2;
    final fits =
        center - half >= room.start - 0.01 && center + half <= room.end + 0.01;
    final left = fits
        ? center - half
        : direction == TextDirection.rtl
        ? room.end - childSize.width
        : room.start;
    return Offset(left, _Metrics.capsuleCenter - childSize.height / 2);
  }

  @override
  bool shouldRelayout(_TitleLayout oldDelegate) =>
      !identical(room, oldDelegate.room) || direction != oldDelegate.direction;
}

/// A large title that scrolls away with the content: it paints its child
/// moved by the content's offset and cut off at its own top, following the
/// scroll view without building or laying out.
class _ScrollAway extends SingleChildRenderObjectWidget {
  const _ScrollAway({required this.scroll, required super.child});

  final ValueListenable<MotionScrollObserver?> scroll;

  @override
  _RenderScrollAway createRenderObject(BuildContext context) =>
      _RenderScrollAway(scroll);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollAway renderObject,
  ) {
    renderObject.scroll = scroll;
  }
}

class _RenderScrollAway extends RenderProxyBox {
  _RenderScrollAway(this._scroll);

  final _clip = LayerHandle<ClipRectLayer>();
  MotionScrollObserver? _observer;

  ValueListenable<MotionScrollObserver?> _scroll;
  ValueListenable<MotionScrollObserver?> get scroll => _scroll;
  set scroll(ValueListenable<MotionScrollObserver?> value) {
    if (identical(value, _scroll)) return;
    if (attached) _unlisten();
    _scroll = value;
    if (attached) _listen();
    markNeedsPaint();
  }

  void _listen() {
    _scroll.addListener(_observe);
    _observe();
  }

  void _unlisten() {
    _scroll.removeListener(_observe);
    _observer?.removeListener(markNeedsPaint);
    _observer = null;
  }

  void _observe() {
    _observer?.removeListener(markNeedsPaint);
    _observer = _scroll.value;
    _observer?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  double get _offset {
    final metrics = _observer?.metrics;
    if (metrics == null || !metrics.hasContentDimensions) return 0;
    return metrics.pixels - metrics.minScrollExtent;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, -_offset, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final shift = _offset;
    if (shift >= size.height) {
      _clip.layer = null;
      return;
    }
    // Pulled down, the title follows the content below its area; pushed
    // up, it goes under the row above.
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(0, 0, size.width, size.height + math.max(0, -shift)),
      (context, offset) =>
          context.paintChild(child, offset.translate(0, -shift)),
      oldLayer: _clip.layer,
    );
  }
}
