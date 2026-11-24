import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/page_route.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// A column of a [GlassSplitView].
///
/// UIKit: `UISplitViewController.Column`.
enum GlassSplitViewColumn {
  /// The sidebar at the leading side.
  primary,

  /// The content beside the sidebar.
  secondary,
}

/// Which columns of a [GlassSplitView] show and how wide its primary column
/// is.
///
/// UIKit: `UISplitViewController`'s `show(_:)`, `hide(_:)`, `isShowing(_:)`,
/// `isCollapsed` and `preferredPrimaryColumnWidth`. Flutter: a controller as
/// `TabController` is one.
///
/// The view is the controller's only reader: a change from code moves the
/// view on a spring ([SplitViewMotion]) or pushes and pops its collapsed
/// stack, and a hand that drags the divider, taps the sidebar button or
/// goes back in the collapsed stack writes here, so an app that keeps what
/// the hand chose listens to the controller.
class GlassSplitViewController extends ChangeNotifier {
  /// Creates a controller whose primary column is `primaryWidth` wide, or
  /// the view's preferred width when it is null, and shows when
  /// `showsPrimary`.
  GlassSplitViewController({this._primaryWidth, this._showsPrimary = true});

  double? _primaryWidth;
  bool _showsPrimary;
  bool _collapsed = false;
  bool _secondaryOnTop = true;

  /// The width a hand or code gave the primary column, or null for the
  /// view's preferred width.
  ///
  /// The view keeps the column within its limits whatever this asks; a
  /// drag of the divider writes where the hand let go, already within
  /// them.
  double? get primaryWidth => _primaryWidth;
  set primaryWidth(double? value) {
    if (value == _primaryWidth) return;
    _primaryWidth = value;
    notifyListeners();
  }

  /// Forgets the width a hand gave the primary column: the column returns
  /// to the view's preferred width on a spring.
  void resetPrimaryWidth() => primaryWidth = null;

  /// Whether the view shows its columns as one stack, as of its last
  /// layout; the listeners hear a change after the frame it happened in.
  bool get isCollapsed => _collapsed;

  /// Whether [column] shows: side by side the secondary always does;
  /// collapsed, the column on top of the stack does.
  bool isShowing(GlassSplitViewColumn column) => switch (column) {
    GlassSplitViewColumn.primary =>
      _collapsed ? !_secondaryOnTop : _showsPrimary,
    GlassSplitViewColumn.secondary => !_collapsed || _secondaryOnTop,
  };

  /// Shows [column]: side by side, the primary column slides in at the
  /// leading side; collapsed, the stack pops to the primary column or
  /// pushes the secondary.
  ///
  /// An app shows the secondary column when its primary column chooses
  /// what the secondary shows: collapsed, that pushes it; side by side it
  /// already shows.
  void show(GlassSplitViewColumn column) {
    if (_collapsed) {
      _setTop(secondary: column == GlassSplitViewColumn.secondary);
    } else if (column == GlassSplitViewColumn.primary) {
      _setPrimary(true);
    }
  }

  /// Hides [column]: side by side, the primary column slides out and the
  /// secondary takes the whole width, and the secondary does not hide;
  /// collapsed, the stack shows the other column.
  void hide(GlassSplitViewColumn column) {
    if (_collapsed) {
      _setTop(secondary: column == GlassSplitViewColumn.primary);
    } else if (column == GlassSplitViewColumn.primary) {
      _setPrimary(false);
    }
  }

  void _setPrimary(bool shows) {
    if (shows == _showsPrimary) return;
    _showsPrimary = shows;
    notifyListeners();
  }

  void _collapsedChanged() => notifyListeners();

  void _setTop({required bool secondary}) {
    if (secondary == _secondaryOnTop) return;
    _secondaryOnTop = secondary;
    notifyListeners();
  }
}

/// Two columns side by side: a sidebar, the primary column, at the leading
/// side, and the content it opens, the secondary column, beside it.
///
/// UIKit: `UISplitViewController(style: .doubleColumn)`. SwiftUI:
/// `NavigationSplitView`. Flutter: none.
///
/// ```dart
/// GlassSplitView(
///   primary: GlassPageScaffold(
///     navigationBar: const GlassNavigationBar(title: Text('Mailboxes')),
///     child: mailboxes,
///   ),
///   secondary: GlassPageScaffold(
///     navigationBar: const GlassNavigationBar(title: Text('Inbox')),
///     child: inbox,
///   ),
/// )
/// ```
///
/// Each column has bars of its own: a [GlassNavigationBar] in a column
/// draws over that column alone, and a `Navigator` in a column gives the
/// pages pushed there the bars they share. The columns get media queries of
/// their own: their own size, and of the safe area the sides they touch.
///
/// The primary column is [preferredPrimaryWidth] wide, by default 320
/// points, or the [preferredPrimaryWidthFraction] of the view; it stays
/// between [minimumPrimaryWidth] and [maximumPrimaryWidth], and leaves the
/// secondary at least [minimumSecondaryWidth], by default 448 points. A
/// view too narrow for both minimums shares its width between the columns
/// as their minimums do. A [GlassPageScaffold] in the primary column takes
/// the sidebar's tint as its background.
///
/// A sidebar button, a glass bar button with the sidebar glyph, shows and
/// hides the primary column: it stands at the trailing end of the
/// navigation bar of the primary column's first page while the column
/// shows, and at the leading end of the secondary column's first page's
/// bar while it is hidden. [showsSidebarButton] false leaves it out. A
/// [controller] shows and hides the primary column from code.
///
/// With [resizable], a divider between the columns follows a finger or a
/// mouse, its cursor the column resize one; it is a Tab stop whose arrow
/// keys, like a screen reader's increment and decrement, step the primary
/// column by a twentieth of the view in whole points. A mouse over it
/// shows a grabber, and focus from the keyboard rings the grabber. Where
/// the hand lets go is written to the [controller], which keeps it.
///
/// Narrower than [collapseBelow], or always with [collapsed] true, the view
/// collapses its columns into one stack of glass pages: the primary column
/// at the bottom and, as [topColumnWhenCollapsed] says, the secondary pushed
/// on it, with a back button to the primary. Back, the back button and an
/// edge swipe pop it, and the [controller] hears it; showing the secondary
/// column from code pushes it again. Collapsed, the columns share one bar,
/// the sidebar has no tint and there is no sidebar button. Each column
/// keeps its state across a collapse and an expansion. A `Navigator` the
/// secondary column holds gets a back button to the primary column on its
/// first page.
///
/// Fidelity. The layout at rest follows the split view passport (iPhone
/// Duo unfolded and the 11 inch iPad, iOS 27.2 simulator): the default
/// widths, the 448 points the secondary keeps, the sidebar tint, the sidebar
/// button's ends. UIKit runs the secondary column under the sidebar; here
/// the columns tile, which shows the same at rest because the sidebar is
/// opaque. The bars keep the compact 54 point bar with its 16 point sides,
/// not the regular 58 point bar with 20 point sides UIKit uses at these
/// widths. The sidebar's slide, the divider and their springs are not
/// measured: UIKit's are not captured, and the numbers are the package's
/// own. UIKit collapses by the compact horizontal size class, which Flutter
/// has not: [collapseBelow] stands for it by width alone, so a phone held
/// sideways wider than it stays expanded, where UIKit collapses.
class GlassSplitView extends StatefulWidget {
  /// Creates a split view of [primary] beside [secondary].
  const GlassSplitView({
    required this.primary,
    required this.secondary,
    this.controller,
    this.preferredPrimaryWidth,
    this.preferredPrimaryWidthFraction,
    this.minimumPrimaryWidth = 0,
    this.maximumPrimaryWidth = double.infinity,
    this.minimumSecondaryWidth = defaultMinimumSecondaryWidth,
    this.resizable = false,
    this.showsSidebarButton = true,
    this.primaryBackgroundColor,
    this.semanticFormatterCallback,
    this.collapsed,
    this.topColumnWhenCollapsed = GlassSplitViewColumn.secondary,
    super.key,
  }) : assert(
         preferredPrimaryWidthFraction == null ||
             (preferredPrimaryWidthFraction >= 0 &&
                 preferredPrimaryWidthFraction <= 1),
         'a fraction of the view',
       ),
       assert(
         minimumPrimaryWidth <= maximumPrimaryWidth,
         'a minimum below the maximum',
       );

  /// The sidebar at the leading side.
  final Widget primary;

  /// The content beside the sidebar.
  final Widget secondary;

  /// Which columns show and how wide the primary is, or null for the
  /// view's own.
  final GlassSplitViewController? controller;

  /// The primary column's width while no hand or code gave it one, or null
  /// for [preferredPrimaryWidthFraction] of the view, else
  /// [defaultPrimaryWidth] (UIKit `preferredPrimaryColumnWidth`).
  final double? preferredPrimaryWidth;

  /// The primary column's share of the view while no hand or code gave it a
  /// width and [preferredPrimaryWidth] is null (UIKit
  /// `preferredPrimaryColumnWidthFraction`).
  final double? preferredPrimaryWidthFraction;

  /// The narrowest the primary column gets (UIKit
  /// `minimumPrimaryColumnWidth`).
  final double minimumPrimaryWidth;

  /// The widest the primary column gets (UIKit
  /// `maximumPrimaryColumnWidth`).
  final double maximumPrimaryWidth;

  /// The width the secondary column keeps however wide the primary is
  /// asked to be.
  final double minimumSecondaryWidth;

  /// Whether a divider between the columns resizes them.
  final bool resizable;

  /// Whether the sidebar button shows (UIKit
  /// `displayModeButtonVisibility`).
  final bool showsSidebarButton;

  /// The background of the primary column's pages, or null for
  /// [sidebarColor].
  final Color? primaryBackgroundColor;

  /// What a screen reader reads as the divider's value for the primary
  /// column's share of the view, 0 to 1, or null for a percentage.
  final String Function(double share)? semanticFormatterCallback;

  /// Whether the columns collapse into one stack, or null to collapse
  /// narrower than [collapseBelow].
  final bool? collapsed;

  /// The column on top of the stack each time the view collapses (UIKit
  /// `topColumnForCollapsingToProposedTopColumn`, which proposes the
  /// secondary).
  final GlassSplitViewColumn topColumnWhenCollapsed;

  /// The width below which a view collapses when [collapsed] is null:
  /// where UIKit stops using a phone's metrics
  /// (`TabBarLayout.phoneBelow`). The split view passport saw a 402 and a
  /// 417 point window collapse and 834 and 867 point ones stay expanded.
  static const double collapseBelow = TabBarLayout.phoneBelow;

  /// The primary column's width by default (split view passport).
  static const double defaultPrimaryWidth = 320;

  /// The width the secondary column keeps by default: UIKit clamps the
  /// primary column to the view's width less 448 points (split view
  /// passport, the Duo at 867 and the iPad at 834 points).
  static const double defaultMinimumSecondaryWidth = 448;

  /// The width of the divider's hit zone, centered on the boundary of the
  /// columns; the package's own.
  static const double dividerWidth = 16;

  /// The width of the grabber a mouse over the divider shows: a sheet's
  /// grabber stood upright, the package's own.
  static const double grabberWidth = 5;

  /// The length of the grabber a mouse over the divider shows.
  static const double grabberLength = 36;

  /// The tint of the primary column's background (split view passport,
  /// light and dark).
  static const sidebarColor = GlassDynamicColor.withBrightness(
    color: Color(0xFFEAEFF2),
    darkColor: Color(0xFF181D20),
  );

  @override
  State<GlassSplitView> createState() => _GlassSplitViewState();
}

class _GlassSplitViewState extends State<GlassSplitView> {
  GlassSplitViewController? _own;
  late final MotionValue<double> _reveal;
  late final MotionValue<double> _share;
  final _drag = ValueNotifier<double?>(null);
  final _range = ValueNotifier(AdjustRange.open);
  final _dividerStates = WidgetStatesController();
  double _from = 0;
  double? _dragStart;
  late double? _width;
  late bool _shows;
  // The primary column's width in the last layout, within its limits.
  double _laid = 0;
  // The view's width in the last layout.
  double _viewWidth = 0;
  final _primaryKey = GlobalKey(debugLabel: 'GlassSplitView.primary');
  final _secondaryKey = GlobalKey(debugLabel: 'GlassSplitView.secondary');
  final _stack = GlobalKey<NavigatorState>(debugLabel: 'GlassSplitView');

  GlassSplitViewController get _controller =>
      widget.controller ?? (_own ??= GlassSplitViewController());

  late final _divider = DragInteraction(
    axis: Axis.horizontal,
    slop: 1,
    global: true,
    onStart: (details) {
      _dragStart = _laid;
      _dragged(details);
    },
    onUpdate: _dragged,
    onEnd: (details) => _release(),
    onCancel: (t) => _release(),
  );
  late final _steps = CommandInteraction(
    onAdjust: (input) => _step(input.command),
  );

  @override
  void initState() {
    super.initState();
    final clock = MotionClockScope.of(context);
    final controller = _controller;
    _width = controller.primaryWidth;
    _shows = controller._showsPrimary;
    _reveal = MotionValue<double>(_shows ? 1 : 0, clock: clock);
    _share = MotionValue<double>(1, clock: clock);
    controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(GlassSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _own)?.removeListener(_changed);
      if (widget.controller != null) {
        _own?.dispose();
        _own = null;
      }
      _controller.addListener(_changed);
      _follow();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    _drag.dispose();
    _range.dispose();
    _dividerStates.dispose();
    super.dispose();
  }

  void _changed() => setState(_follow);

  void _follow() {
    final controller = _controller;
    final shows = controller._showsPrimary;
    if (shows != _shows) {
      _shows = shows;
      SplitViewMotion.reveal(_reveal, shown: shows);
    }
    if (controller.primaryWidth != _width) {
      _width = controller.primaryWidth;
      _from = _laid;
      SplitViewMotion.resize(_share);
    }
  }

  void _dragged(DragInteractionDetails details) {
    final start = _dragStart;
    if (start == null) return;
    final dx = details.translation.dx;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final (low, high) = _limits(_viewWidth);
    _drag.value = (start + (rtl ? -dx : dx)).clamp(low, math.max(low, high));
  }

  void _release() {
    final dragged = _drag.value;
    _dragStart = null;
    if (dragged == null) return;
    _laid = dragged;
    _drag.value = null;
    _controller.primaryWidth = dragged;
  }

  void _step(ValueCommand command) {
    final (low, high) = _limits(_viewWidth);
    final step = math.max(1, (_viewWidth / 20).roundToDouble());
    final from = _settledWidth(_viewWidth);
    final next = switch (command) {
      ValueCommand.increase => from + step,
      ValueCommand.decrease => from - step,
      ValueCommand.increaseLarge => from + 5 * step,
      ValueCommand.decreaseLarge => from - 5 * step,
      ValueCommand.toMaximum => high,
      ValueCommand.toMinimum => low,
    };
    _controller.primaryWidth = next.clamp(low, math.max(low, high));
  }

  // The narrowest and widest the primary column gets in a view [width]
  // wide; the widest falls below the narrowest when the view is too narrow
  // for both minimums.
  (double, double) _limits(double width) => (
    widget.minimumPrimaryWidth,
    math.min(widget.maximumPrimaryWidth, width - widget.minimumSecondaryWidth),
  );

  double _preferred(double width) =>
      widget.preferredPrimaryWidth ??
      switch (widget.preferredPrimaryWidthFraction) {
        final fraction? => fraction * width,
        null => GlassSplitView.defaultPrimaryWidth,
      };

  // The primary column's width in a view [width] wide: [asked] within the
  // limits, or shared as the minimums share a view too narrow for both.
  double _fit(double width, double asked) {
    final (low, high) = _limits(width);
    if (high >= low) return asked.clamp(low, high);
    final minimums = low + widget.minimumSecondaryWidth;
    return minimums <= 0 ? width / 2 : width * low / minimums;
  }

  double _settledWidth(double width) =>
      _fit(width, _width ?? _preferred(width));

  double _liveWidth(double width) {
    final dragged = _drag.value;
    if (dragged != null) return _fit(width, dragged);
    final rule = _width ?? _preferred(width);
    return _fit(width, lerpDouble(_from, rule, _share.value)!);
  }

  double _laidOut(double width) {
    _viewWidth = width;
    return _laid = _liveWidth(width);
  }

  GlassBarButton _sidebarButton(GlassLocalizations strings) => GlassBarButton(
    key: const ValueKey<Object>(GlassSplitView),
    icon: const _SidebarIcon(),
    semanticLabel: _shows ? strings.hideSidebarLabel : strings.showSidebarLabel,
    onPressed: () => _shows
        ? _controller.hide(GlassSplitViewColumn.primary)
        : _controller.show(GlassSplitViewColumn.primary),
  );

  static MediaQueryData _slice(
    MediaQueryData media,
    double width, {
    required bool start,
    required bool end,
    required TextDirection direction,
  }) {
    final left = direction == TextDirection.ltr ? start : end;
    final right = direction == TextDirection.ltr ? end : start;
    EdgeInsets cut(EdgeInsets insets) => insets.copyWith(
      left: left ? null : 0,
      right: right ? null : 0,
    );
    return media.copyWith(
      size: Size(width, media.size.height),
      padding: cut(media.padding),
      viewPadding: cut(media.viewPadding),
    );
  }

  // Whether a view [width] wide collapses, telling the controller; the
  // listeners hear a change after the frame.
  bool _collapse(double width) {
    final collapsed = widget.collapsed ?? width < GlassSplitView.collapseBelow;
    final controller = _controller;
    if (collapsed == controller._collapsed) return collapsed;
    controller._collapsed = collapsed;
    if (collapsed) {
      controller._secondaryOnTop =
          widget.topColumnWhenCollapsed == GlassSplitViewColumn.secondary;
    }
    // After the frame: a layout cannot notify the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(controller, _controller)) {
        controller._collapsedChanged();
      }
    });
    return collapsed;
  }

  Widget _collapsedStack(GlassLocalizations strings) {
    final controller = _controller;
    final secondaryOnTop = controller._secondaryOnTop;
    return NavigatorPopHandler(
      enabled: secondaryOnTop,
      onPopWithResult: (result) => _stack.currentState?.maybePop(result),
      child: Navigator(
        key: _stack,
        pages: [
          _ColumnPage(
            key: const ValueKey(GlassSplitViewColumn.primary),
            child: KeyedSubtree(key: _primaryKey, child: widget.primary),
          ),
          if (secondaryOnTop)
            _ColumnPage(
              key: const ValueKey(GlassSplitViewColumn.secondary),
              child: GlassBarSupplement(
                leading: GlassBarButton(
                  icon: const GlassBackChevron(),
                  semanticLabel: strings.backButtonLabel,
                  onPressed: () =>
                      controller.hide(GlassSplitViewColumn.secondary),
                ),
                child: KeyedSubtree(
                  key: _secondaryKey,
                  child: widget.secondary,
                ),
              ),
            ),
        ],
        onDidRemovePage: (page) {
          if (page.key == const ValueKey(GlassSplitViewColumn.secondary)) {
            controller.hide(GlassSplitViewColumn.secondary);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = GlassLocalizations.of(context);
    final direction = Directionality.of(context);
    final media = MediaQuery.of(context);
    final button = widget.showsSidebarButton ? _sidebarButton(strings) : null;
    final background = GlassDynamicColor.resolve(
      widget.primaryBackgroundColor ?? GlassSplitView.sidebarColor,
      context,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (_collapse(width)) return _collapsedStack(strings);
        final primaryWidth = _settledWidth(width);
        final share = width > 0 ? primaryWidth / width : 0.0;
        final primary = ExcludeFocus(
          excluding: !_shows,
          child: ExcludeSemantics(
            excluding: !_shows,
            child: MediaQuery(
              data: _slice(
                media,
                primaryWidth,
                start: true,
                end: false,
                direction: direction,
              ),
              child: GlassPageBackground(
                color: background,
                child: GlassBarSupplement(
                  trailing: _shows ? button : null,
                  child: GlassOwnBars(
                    child: KeyedSubtree(
                      key: _primaryKey,
                      child: widget.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final secondary = MediaQuery(
          data: _slice(
            media,
            _shows ? width - primaryWidth : width,
            start: !_shows,
            end: true,
            direction: direction,
          ),
          child: GlassBarSupplement(
            leading: _shows ? null : button,
            child: GlassOwnBars(
              child: KeyedSubtree(key: _secondaryKey, child: widget.secondary),
            ),
          ),
        );
        final (low, high) = _limits(width);
        String value(double share) =>
            widget.semanticFormatterCallback?.call(share) ??
            strings.percentValue(share);
        final step = width > 0 ? 1 / 20 : 0.0;
        _range.value = AdjustRange.of(primaryWidth, min: low, max: high);
        final divider = widget.resizable && _shows
            ? InputRegion(
                interactions: [_divider, _steps],
                mouseCursor: SystemMouseCursors.resizeColumn,
                adjustRange: _range,
                statesController: _dividerStates,
                semantics: SemanticsProperties(
                  label: strings.columnDividerLabel,
                  slider: true,
                  value: value(share),
                  increasedValue: value(math.min(share + step, 1)),
                  decreasedValue: value(math.max(share - step, 0)),
                ),
                child: Center(
                  child: GlassHighlightPaint.of(
                    context,
                    states: _dividerStates,
                    hoverColor: GlassColors.tertiaryLabel,
                    child: const SizedBox(
                      width: GlassSplitView.grabberWidth,
                      height: GlassSplitView.grabberLength,
                    ),
                  ),
                ),
              )
            : null;
        return ClipRect(
          child: _SplitLayout(
            state: this,
            direction: direction,
            children: [secondary, primary, ?divider],
          ),
        );
      },
    );
  }
}

// A column as a glass page of the collapsed stack; the page's latest child
// shows.
class _ColumnPage extends Page<void> {
  const _ColumnPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => GlassPageRoute<void>(
    settings: this,
    builder: (context) =>
        (ModalRoute.settingsOf(context)! as _ColumnPage).child,
  );
}

class _SplitLayout extends MultiChildRenderObjectWidget {
  const _SplitLayout({
    required this.state,
    required this.direction,
    required super.children,
  });

  final _GlassSplitViewState state;
  final TextDirection direction;

  @override
  _RenderSplit createRenderObject(BuildContext context) =>
      _RenderSplit(state, direction);

  @override
  void updateRenderObject(BuildContext context, _RenderSplit renderObject) {
    renderObject
      ..direction = direction
      ..markNeedsLayout();
  }
}

class _SplitParentData extends ContainerBoxParentData<RenderBox> {}

// Lays out the secondary column, the primary column and the divider, in
// that order, from the split view's live widths: a frame of the sidebar's
// slide or of a drag lays out again without a build.
class _RenderSplit extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SplitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SplitParentData> {
  _RenderSplit(this._state, this._direction);

  final _GlassSplitViewState _state;

  TextDirection get direction => _direction;
  TextDirection _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  double get _reveal => _state._reveal.value.clamp(0.0, 1.0);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SplitParentData) {
      child.parentData = _SplitParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _state._reveal.addRenderListener(markNeedsLayout);
    _state._share.addRenderListener(markNeedsLayout);
    _state._drag.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _state._reveal.removeRenderListener(markNeedsLayout);
    _state._share.removeRenderListener(markNeedsLayout);
    _state._drag.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final width = size.width;
    final height = size.height;
    final primaryWidth = _state._laidOut(width);
    final shown = primaryWidth * _reveal;
    final secondary = firstChild!;
    final primary = childAfter(secondary)!;
    final divider = childAfter(primary);
    double x(double start, double extent) =>
        _direction == TextDirection.ltr ? start : width - start - extent;
    secondary.layout(
      BoxConstraints.tight(Size(width - shown, height)),
    );
    (secondary.parentData! as _SplitParentData).offset = Offset(
      x(shown, width - shown),
      0,
    );
    primary.layout(
      BoxConstraints.tight(Size(primaryWidth, height)),
    );
    (primary.parentData! as _SplitParentData).offset = Offset(
      x(shown - primaryWidth, primaryWidth),
      0,
    );
    if (divider != null) {
      const zone = GlassSplitView.dividerWidth;
      divider.layout(
        BoxConstraints.tight(Size(zone, height)),
      );
      (divider.parentData! as _SplitParentData).offset = Offset(
        x(shown - zone / 2, zone),
        0,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final secondary = firstChild!;
    final primary = childAfter(secondary)!;
    context.paintChild(
      secondary,
      offset + (secondary.parentData! as _SplitParentData).offset,
    );
    if (_reveal > 0) {
      context.paintChild(
        primary,
        offset + (primary.parentData! as _SplitParentData).offset,
      );
    }
    if (childAfter(primary) case final divider?) {
      context.paintChild(
        divider,
        offset + (divider.parentData! as _SplitParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final secondary = firstChild!;
    final primary = childAfter(secondary)!;
    for (final child in [
      ?childAfter(primary),
      if (_reveal > 0) primary,
      secondary,
    ]) {
      final offset = (child.parentData! as _SplitParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final secondary = firstChild!;
    final primary = childAfter(secondary)!;
    visitor(secondary);
    if (_reveal > 0) visitor(primary);
    if (childAfter(primary) case final divider?) visitor(divider);
  }
}

// SF Symbols' `sidebar.leading`, drawn after the symbol at the bar's icon
// size; its strokes are not measured.
class _SidebarIcon extends StatelessWidget {
  const _SidebarIcon();

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 22;
    return SizedBox(
      width: size * 25 / 22,
      height: size,
      child: CustomPaint(
        painter: _SidebarPainter(
          theme.color ?? GlassTheme.labelColorOf(context),
          Directionality.of(context),
        ),
      ),
    );
  }
}

class _SidebarPainter extends CustomPainter {
  const _SidebarPainter(this.color, this.direction);

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / 22;
    if (direction == TextDirection.rtl) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * k
      ..strokeCap = StrokeCap.round;
    final box = Rect.fromLTWH(1.5 * k, 2.5 * k, 22 * k, 17 * k);
    canvas
      ..drawRRect(RRect.fromRectAndRadius(box, Radius.circular(4 * k)), paint)
      ..drawLine(
        Offset(box.left + 7.5 * k, box.top),
        Offset(box.left + 7.5 * k, box.bottom),
        paint,
      );
    for (final y in [4.0, 7.0, 10.0]) {
      canvas.drawLine(
        Offset(box.left + 2.5 * k, box.top + y * k),
        Offset(box.left + 5 * k, box.top + y * k),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SidebarPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.direction != direction;
}
