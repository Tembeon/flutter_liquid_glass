import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:apple_liquid_glass/src/chrome/bar_entry.dart';
import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/controls/button.dart';
import 'package:apple_liquid_glass/src/controls/search_field.dart';
import 'package:apple_liquid_glass/src/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:apple_liquid_glass/src/motion/search_motion.dart';
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
    this.searchField,
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

  /// A [GlassSearchField] stacked under the titles, or null for none.
  ///
  /// UIKit: `UINavigationItem.searchController` with the stacked placement.
  /// SwiftUI: `searchable` in a `NavigationStack`. Flutter:
  /// `CupertinoSliverNavigationBar.search`.
  ///
  /// At rest the field is 44 points tall on a plain fill, 16 points from
  /// the sides and 10 above the content. Scrolling the content first folds
  /// the field away, its height shrinking with the scroll, its text gone
  /// by a fifth of the way and its fill by the last fifth, then the large
  /// title goes (read from UIKit, notes private). Focusing the field
  /// presents the search on one spring (damping 0.8, response 0.34, read
  /// from UIKit): the page and its bar rise until the field sits under the
  /// status bar, the field narrows for a close button that slides in 40
  /// points from the side, and its plain fill turns to glass on a
  /// critically damped spring of response 0.32 (read from UIKit). The
  /// close button clears the field and ends the search; the page comes
  /// back down. A field folded away by a scroll presents from where it
  /// rests: the rise is not shortened (an approximation).
  final Widget? searchField;

  /// The look, over the theme's.
  final GlassNavigationBarStyle? style;

  /// The height of the row under the status bar (navigation bar passport).
  static const double height = 54;

  /// The height a large title adds under the row (navigation bar
  /// passport).
  static const double largeTitleHeight = 52;

  /// The height a stacked search field adds under the titles: the field
  /// and the 10 points below it (search passport).
  static const double searchFieldHeight = 54;

  double get _search => searchField == null ? 0 : searchFieldHeight;

  @override
  Size get preferredSize => Size.fromHeight(height + scrolledUnderAfter);

  @override
  ChromeBar get chromeBar => ChromeBar.navigation;

  @override
  double get scrolledUnderAfter =>
      (largeTitle == null ? 0 : largeTitleHeight) + _search;

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
                widget.scrolledUnderAfter - 0.5);
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
    link.host.liftedBy(link, PageLift.maybeOf(context));
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
              delay: widget._search,
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
        if (widget.searchField case final field?)
          _StackedSearch(
            field: field,
            scroll: _scroll,
            travel:
                GlassNavigationBar.height +
                (largeTitle == null ? 0 : GlassNavigationBar.largeTitleHeight),
            lift: PageLift.maybeOf(context),
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
  /// The space between the screen's sides and the outer items: 16 on a 402
  /// point screen; the Pro Max's 20 is not followed (approximation).
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
  const _ScrollAway({
    required this.scroll,
    required this.delay,
    required super.child,
  });

  final ValueListenable<MotionScrollObserver?> scroll;

  // How far the content scrolls before the title moves: a stacked search
  // field folds away first.
  final double delay;

  @override
  _RenderScrollAway createRenderObject(BuildContext context) =>
      _RenderScrollAway(scroll, delay);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollAway renderObject,
  ) {
    renderObject.scroll = scroll;
    renderObject.delay = delay;
  }
}

class _RenderScrollAway extends RenderProxyBox {
  _RenderScrollAway(this._scroll, this._delay);

  double _delay;
  double get delay => _delay;
  set delay(double value) {
    if (value == _delay) return;
    _delay = value;
    markNeedsPaint();
  }

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
    final offset = metrics.pixels - metrics.minScrollExtent;
    return offset < 0 ? offset : math.max(0, offset - _delay);
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

/// A search field stacked under the navigation bar's titles: folded away
/// by the content's scroll, presented under the status bar while focused,
/// ended by its close button.
class _StackedSearch extends StatefulWidget {
  const _StackedSearch({
    required this.field,
    required this.scroll,
    required this.travel,
    required this.lift,
  });

  final Widget field;
  final ValueListenable<MotionScrollObserver?> scroll;

  // How far the field rises to sit under the status bar.
  final double travel;

  // The page's lift, which this search writes.
  final ValueNotifier<double>? lift;

  @override
  State<_StackedSearch> createState() => _StackedSearchState();
}

class _StackedSearchState extends State<_StackedSearch>
    implements MotionDriver {
  final _shown = MotionValue<double>(0, spring: SearchTuning.stackedSpring);
  final _glass = MotionValue<double>(0, spring: _StackedMetrics.glassSpring);
  final _ends = _StackedEnds();
  final _closing = ValueNotifier<bool>(false);
  bool _active = false;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    MotionClock.instance.addDriver(this);
  }

  @override
  void dispose() {
    MotionClock.instance.removeDriver(this);
    widget.lift?.value = 0;
    _ends.dispose();
    _closing.dispose();
    super.dispose();
  }

  @override
  bool get isActive =>
      !_shown.isWithin(_now, GlassRest.opacity) ||
      !_glass.isWithin(_now, GlassRest.opacity);

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    for (final value in [_shown, _glass]) {
      if (value.valueAt(time) != value.target &&
          value.isWithin(time, GlassRest.opacity)) {
        value.snap(time, value.target);
      }
    }
    widget.lift?.value = -widget.travel * _shown.valueAt(time);
  }

  void _focusChanged(bool focused) {
    if (!focused || _active) return;
    _active = true;
    _closing.value = true;
    final t = _now;
    _shown.retarget(t, 1);
    _glass.retarget(t, 1);
    MotionClock.instance.wake(this);
  }

  void _end() {
    if (!_active) return;
    _active = false;
    _closing.value = false;
    _ends.end();
    final t = _now;
    _shown.retarget(t, 0);
    _glass.retarget(t, 0);
    MotionClock.instance.wake(this);
  }

  @override
  Widget build(BuildContext context) {
    final glyph = GlassDynamicColor.resolve(
      GlassTheme.of(context).colorScheme?.label ?? GlassColors.label,
      context,
    );
    return SizedBox(
      height: GlassNavigationBar.searchFieldHeight,
      child: _StackedLayout(
        shown: _shown,
        glass: _glass,
        scroll: widget.scroll,
        fill: GlassDynamicColor.resolve(_StackedMetrics.fill, context),
        children: [
          SearchEnds(
            ends: _ends,
            child: SearchFieldStacking(
              height: _StackedMetrics.fieldHeight,
              glass: _glass,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: _focusChanged,
                child: widget.field,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _closing,
            builder: (context, closing, child) =>
                IgnorePointer(ignoring: !closing, child: child),
            child: GlassButton(
              onPressed: _end,
              child: Semantics(
                label: 'Close',
                child: SizedBox.fromSize(
                  size: SearchTuning.closeGlyphSize,
                  child: CustomPaint(painter: SearchCrossPainter(glyph)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StackedEnds extends ChangeNotifier {
  void end() => notifyListeners();
}

abstract final class _StackedMetrics {
  /// The height of a stacked field (iOS 27 simulator: 44 points at rest
  /// and presented).
  static const double fieldHeight = 44;

  /// The space between the screen's sides and the field (16 points).
  static const double sideInset = 16;

  /// The space between the presented field and its close button.
  static const double closeGap = 10;

  /// How far toward the trailing side the close button starts.
  static const double closeTravel = 40;

  /// The plain fill of the field at rest: 0x767680 at 12 percent on white
  /// (simulator); the dark 24 percent is not measured.
  static const fill = GlassDynamicColor.withBrightness(
    color: Color(0x1F767680),
    darkColor: Color(0x3D767680),
  );

  /// The spring the field's plain fill turns to glass on and back
  /// (`backgroundMaterialSpring`, damping 1.0, response 0.32, read from
  /// UIKit).
  static const glassSpring = Spring.response(0.32);

  /// The share of the field's fold at which its text is gone (read from
  /// UIKit).
  static const double textGone = 0.2;

  /// The share of the field's fold at which its fill starts to fade, and
  /// the share over which it does (read from UIKit).
  static const double fillFadeStart = 0.8;

  /// See [fillFadeStart].
  static const double fillFade = 0.15;
}

class _StackedLayout extends MultiChildRenderObjectWidget {
  const _StackedLayout({
    required this.shown,
    required this.glass,
    required this.scroll,
    required this.fill,
    required super.children,
  });

  final ValueListenable<double> shown;
  final ValueListenable<double> glass;
  final ValueListenable<MotionScrollObserver?> scroll;
  final Color fill;

  @override
  _RenderStackedLayout createRenderObject(BuildContext context) =>
      _RenderStackedLayout(
        shown: shown,
        glass: glass,
        scroll: scroll,
        fill: fill,
        rtl: Directionality.of(context) == TextDirection.rtl,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStackedLayout renderObject,
  ) {
    renderObject.fill = fill;
    renderObject.rtl = Directionality.of(context) == TextDirection.rtl;
  }
}

class _StackedData extends ContainerBoxParentData<RenderBox> {}

/// Lays the field out as wide as the presentation leaves it and paints it
/// folded by the scroll, over its plain fill, with the close button
/// arriving beside it; nothing builds per frame.
class _RenderStackedLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StackedData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StackedData> {
  _RenderStackedLayout({
    required this.shown,
    required this.glass,
    required this._scroll,
    required this._fill,
    required this._rtl,
  });

  final ValueListenable<double> shown;
  final ValueListenable<double> glass;
  final ValueListenable<MotionScrollObserver?> _scroll;
  MotionScrollObserver? _observer;
  final _layers = LayerHandle<OpacityLayer>();
  final _clip = LayerHandle<ClipRRectLayer>();
  final _closeLayer = LayerHandle<OpacityLayer>();

  Color _fill;
  Color get fill => _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StackedData) child.parentData = _StackedData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    shown.addListener(markNeedsLayout);
    glass.addListener(markNeedsPaint);
    _scroll.addListener(_observe);
    _observe();
  }

  @override
  void detach() {
    shown.removeListener(markNeedsLayout);
    glass.removeListener(markNeedsPaint);
    _scroll.removeListener(_observe);
    _observer?.removeListener(markNeedsPaint);
    _observer = null;
    super.detach();
  }

  @override
  void dispose() {
    _layers.layer = null;
    _clip.layer = null;
    _closeLayer.layer = null;
    super.dispose();
  }

  void _observe() {
    _observer?.removeListener(markNeedsPaint);
    _observer = _scroll.value;
    _observer?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double get _offset {
    final metrics = _observer?.metrics;
    if (metrics == null || !metrics.hasContentDimensions) return 0;
    return metrics.pixels - metrics.minScrollExtent;
  }

  double get _shown => shown.value.clamp(0.0, 1.0);

  // How far the field has folded, 0 to its height; a presented field does
  // not fold.
  double get _fold =>
      _offset.clamp(0.0, _StackedMetrics.fieldHeight) * (1 - _shown);

  double get _pull => math.max(0, -_offset);

  Rect get _field {
    const side = _StackedMetrics.sideInset;
    const h = _StackedMetrics.fieldHeight;
    final width =
        size.width - 2 * side - (h + _StackedMetrics.closeGap) * shown.value;
    final left = _rtl ? size.width - side - width : side;
    return Rect.fromLTWH(left, 0, math.max(0, width), h);
  }

  Rect get _close {
    const side = _StackedMetrics.sideInset;
    const h = _StackedMetrics.fieldHeight;
    final away = _StackedMetrics.closeTravel * (1 - shown.value);
    final left = _rtl ? side - away : size.width - side - h + away;
    return Rect.fromLTWH(left, 0, h, h);
  }

  @override
  void performLayout() {
    size = constraints.constrain(
      Size(constraints.maxWidth, GlassNavigationBar.searchFieldHeight),
    );
    final field = firstChild!;
    final close = childAfter(field)!;
    field.layout(BoxConstraints.tight(_field.size));
    close.layout(BoxConstraints.tight(_close.size));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final field = firstChild!;
    final close = childAfter(field)!;
    final down = Offset(0, _pull);
    if (_shown > 0.5) {
      final at = _close.topLeft + down;
      if (result.addWithPaintOffset(
        offset: at,
        position: position,
        hitTest: (result, local) => close.hitTest(result, position: local),
      )) {
        return true;
      }
    }
    if (_fold / _StackedMetrics.fieldHeight >= 0.5) return false;
    final at = _field.topLeft + down;
    return result.addWithPaintOffset(
      offset: at,
      position: position,
      hitTest: (result, local) => field.hitTest(result, position: local),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final at = (identical(child, firstChild) ? _field : _close).topLeft;
    transform.translateByDouble(at.dx, at.dy + _pull, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final field = firstChild!;
    final close = childAfter(field)!;
    final rest = _field.shift(offset + Offset(0, _pull));
    final fold = _fold;
    final r = fold / _StackedMetrics.fieldHeight;
    final body = Rect.fromLTWH(
      rest.left,
      rest.top,
      rest.width,
      rest.height - fold,
    );
    final capsule = RRect.fromRectAndRadius(
      body,
      Radius.circular(body.height / 2),
    );
    final fillShown =
        (1 - glass.value.clamp(0.0, 1.0)) *
        (1 -
            ((r - _StackedMetrics.fillFadeStart) / _StackedMetrics.fillFade)
                .clamp(0.0, 1.0));
    if (fillShown > 0 && body.height > 0) {
      final paint = Paint();
      paint.color = _fill.withValues(alpha: _fill.a * fillShown);
      context.canvas.drawRRect(capsule, paint);
    }
    final text = 1 - (r / _StackedMetrics.textGone).clamp(0.0, 1.0);
    if (text <= 0) {
      _layers.layer = null;
      _clip.layer = null;
    } else {
      void drawField(PaintingContext context, Offset at) =>
          context.paintChild(field, at);
      void clipped(PaintingContext context, Offset at) {
        if (fold <= 0) {
          _clip.layer = null;
          drawField(context, at);
          return;
        }
        _clip.layer = context.pushClipRRect(
          needsCompositing,
          at,
          Offset.zero & body.size,
          RRect.fromRectAndRadius(
            Offset.zero & body.size,
            Radius.circular(body.height / 2),
          ),
          drawField,
          oldLayer: _clip.layer,
        );
      }

      if (text >= 1) {
        _layers.layer = null;
        clipped(context, rest.topLeft);
      } else {
        _layers.layer = context.pushOpacity(
          rest.topLeft,
          (text * 255).round(),
          clipped,
          oldLayer: _layers.layer,
        );
      }
    }
    final present = _shown;
    if (present <= 0.001) {
      _closeLayer.layer = null;
      return;
    }
    _closeLayer.layer = context.pushOpacity(
      _close.shift(offset + Offset(0, _pull)).topLeft,
      (present * 255).round(),
      (context, at) => context.paintChild(close, at),
      oldLayer: _closeLayer.layer,
    );
  }

  @override
  bool get alwaysNeedsCompositing => true;
}
