import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar_room.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/column_divider.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/page_route.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/sidebar_glyph.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Shows or hides the sidebar closest to the focus: the primary column of
/// a [GlassSplitView], or the tab sidebar of a `GlassTabScaffold`.
///
/// UIKit: the `toggleSidebar:` action, Toggle Sidebar in the View menu
/// (control-command-S). Flutter: an [Intent] that [Shortcuts] map keys to.
///
/// A split view handles it side by side while its sidebar button shows, as
/// the button does. A tab scaffold handles it for the list column of the
/// selected tab first, then for its tab sidebar where the layout lets the
/// sidebar hide or fold. Where neither can, the intent goes on to the
/// handlers above. Both bind [defaultShortcuts] unless given other
/// shortcuts, so an app maps other keys to the intent or binds none.
class GlassToggleSidebarIntent extends Intent {
  /// Creates the intent.
  const GlassToggleSidebarIntent();

  /// Control-command-S to [GlassToggleSidebarIntent], as UIKit's View menu
  /// binds Toggle Sidebar.
  static const Map<ShortcutActivator, Intent> defaultShortcuts = {
    SingleActivator(LogicalKeyboardKey.keyS, control: true, meta: true):
        GlassToggleSidebarIntent(),
  };
}

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
  /// `showsPrimary`, or as the view's [GlassSplitView.showsPrimaryByDefault]
  /// says when it is null.
  GlassSplitViewController({this._primaryWidth, this._showsPrimary});

  double? _primaryWidth;
  bool? _showsPrimary;
  bool _primaryByDefault = true;
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

  /// Whether a hand or code showed the primary column side by side, or
  /// null for [GlassSplitView.showsPrimaryByDefault].
  ///
  /// [show] and [hide] write here side by side; null gives the column back
  /// to the view, as an app restoring what the user chose does.
  bool? get showsPrimary => _showsPrimary;
  set showsPrimary(bool? value) {
    if (value == _showsPrimary) return;
    _showsPrimary = value;
    notifyListeners();
  }

  /// Whether the view shows its columns as one stack, as of its last
  /// layout; the listeners hear a change after the frame it happened in.
  bool get isCollapsed => _collapsed;

  /// Whether [column] shows: side by side the secondary always does;
  /// collapsed, the column on top of the stack does.
  bool isShowing(GlassSplitViewColumn column) => switch (column) {
    GlassSplitViewColumn.primary =>
      _collapsed ? !_secondaryOnTop : _showsPrimary ?? _primaryByDefault,
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
      showsPrimary = true;
    }
  }

  /// Hides [column]: side by side, the primary column slides out and the
  /// secondary takes the whole width, and the secondary does not hide;
  /// collapsed, the stack shows the other column.
  void hide(GlassSplitViewColumn column) {
    if (_collapsed) {
      _setTop(secondary: column == GlassSplitViewColumn.primary);
    } else if (column == GlassSplitViewColumn.primary) {
      showsPrimary = false;
    }
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
/// shows, and at the leading end of the bar of every page of the secondary
/// column while it is hidden, before a page's back button, as UIKit's
/// stands at every depth (split view passport). [showsSidebarButton] false
/// leaves it out. A [controller] shows and hides the primary column from
/// code, and [GlassToggleSidebarIntent] from the keys, control-command-S by
/// default ([shortcuts]), while the focus is in the view.
///
/// With [resizable], a divider between the columns follows a finger or a
/// mouse, its cursor the column resize one; it is a Tab stop whose arrow
/// keys, like a screen reader's increment and decrement, step the primary
/// column by a twentieth of the view in whole points. A mouse over it
/// shows a grabber, and focus from the keyboard rings the grabber. Where
/// the hand lets go is written to the [controller], which keeps it, and a
/// double tap forgets it. At [minimumPrimaryWidth] the divider stops while
/// the hand goes on, and [ColumnFold.defaultDistance] further the primary
/// column hides, as the sidebar button hides it; the same drag brings it
/// back, at the width it had, and a step down from the minimum hides it
/// too. Without the sidebar button the divider stops at the minimum, as
/// nothing would show the column again. A touch cannot hide a column whose
/// minimum lies closer than that distance to the screen's leading edge.
///
/// Where the window is compact across ([GlassEnvironment.horizontalSizeClass]),
/// or always with [collapsed] true, the view collapses its columns into one
/// stack of glass pages: the primary column
/// at the bottom and, as [topColumnWhenCollapsed] says, the secondary pushed
/// on it, with a back button to the primary. Back, the back button and an
/// edge swipe pop it, and the [controller] hears it; showing the secondary
/// column from code pushes it again. Collapsed, the columns share one bar,
/// the sidebar has no tint and there is no sidebar button. Each column
/// keeps its state across a collapse and an expansion. A `Navigator` the
/// secondary column holds gets a back button to the primary column on its
/// first page. Side by side, a back button the view's own page would get,
/// as a tab scaffold pushed as a page gives, goes to the column at the
/// leading side. Side by side, each column reads the size class of its own
/// width: regular from [GlassEnvironment.regularWidthFrom], so a view
/// nested in a column collapses alike on every platform.
///
/// Side by side on a hinge, or a fold half open, that splits the view from
/// top to bottom with room on both sides of what [leadingInset] covers, the
/// columns meet on the band's center line, as UIKit's split does on the
/// iPhone Duo at 99 degrees (fold passport: the primary 475.67 wide, the
/// crease at 475.5), in the frame the band comes or goes. Each column gets
/// its half of the band as the safe area of the side where they meet, its
/// bars standing past it, and no hand moves the border. A band at the
/// view's edge, past the inset, or across the view, as in the laptop
/// posture, splits nothing. The display features of `MediaQuery` are taken
/// in the view's own coordinates, as `DisplayFeatureSubScreen` takes them,
/// so a view placed elsewhere gets them from a `MediaQuery` of its own;
/// each column gets those it overlaps in its own coordinates, without the
/// band it was split at.
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
/// own. Which size class UIKit gives a column is not measured; here each
/// column side by side reads its own width's.
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
    this.showsPrimaryByDefault = true,
    this.primaryBackgroundColor,
    this.semanticFormatterCallback,
    this.collapsed,
    this.topColumnWhenCollapsed = GlassSplitViewColumn.secondary,
    this.leadingInset = 0,
    this.shortcuts = GlassToggleSidebarIntent.defaultShortcuts,
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

  /// The keys the view binds while the focus is in it: by default
  /// control-command-S to [GlassToggleSidebarIntent]. An empty map binds
  /// none, as a view inside another that binds them passes.
  final Map<ShortcutActivator, Intent> shortcuts;

  /// Whether the primary column shows side by side until a hand or code
  /// shows or hides it ([GlassSplitViewController.showsPrimary]): UIKit
  /// hides it on an iPad window too narrow for both columns.
  final bool showsPrimaryByDefault;

  /// The background of the primary column's pages, or null for
  /// [sidebarColor].
  final Color? primaryBackgroundColor;

  /// What a screen reader reads as the divider's value for the primary
  /// column's share of the view, 0 to 1, or null for a percentage.
  final String Function(double share)? semanticFormatterCallback;

  /// Whether the columns collapse into one stack, or null to collapse where
  /// the window is compact across.
  final bool? collapsed;

  /// The column on top of the stack each time the view collapses (UIKit
  /// `topColumnForCollapsingToProposedTopColumn`, which proposes the
  /// secondary).
  final GlassSplitViewColumn topColumnWhenCollapsed;

  /// How much of the view's leading side something drawn over it covers,
  /// such as a tab sidebar standing beside the content; 0 by default.
  ///
  /// The primary column runs under it and is that much wider than its
  /// width rule gives, which applies to the rest of the view, and the
  /// column at the leading side, the secondary while the primary is
  /// hidden, gets it as its leading safe area, with its bars starting past
  /// it and its titles centered on the rest. UIKit's split view in a tab
  /// beside the tab sidebar reports a primary column 600 points wide: the
  /// sidebar's 280 and its own 320 (iOS 27.2). A collapsed view ignores it.
  final double leadingInset;

  /// The primary column's width by default (split view passport).
  static const double defaultPrimaryWidth = 320;

  /// The width the secondary column keeps by default: UIKit clamps the
  /// primary column to the view's width less 448 points (split view
  /// passport, the Duo at 867 and the iPad at 834 points).
  static const double defaultMinimumSecondaryWidth = 448;

  /// The width of the divider's hit zone, centered on the boundary of the
  /// columns; the package's own.
  static const double dividerWidth = GlassColumnDivider.width;

  /// The tint of the primary column's background (split view passport,
  /// light and dark).
  static const sidebarColor = GlassDynamicColor.withBrightness(
    color: Color(0xFFEAEFF2),
    darkColor: Color(0xFF181D20),
  );

  /// The column of the nearest split view that [context] stands in, or
  /// null outside one; in a collapsed stack, the column of the page it
  /// stands on.
  static GlassSplitViewColumn? columnOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitColumn>()?.column;

  /// Whether the column [context] stands in shows beside the other one:
  /// side by side with the primary column shown. False in a collapsed
  /// stack, in the secondary column while the primary is hidden, and
  /// outside a split view: a page of the secondary column leaves out a way
  /// back to a list it stands beside, as UIKit's first detail page does.
  static bool besideOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitColumn>()?.beside ??
      false;

  @override
  State<GlassSplitView> createState() => _GlassSplitViewState();
}

class _SplitColumn extends InheritedWidget {
  const _SplitColumn({
    required this.column,
    required this.beside,
    required super.child,
  });

  final GlassSplitViewColumn column;
  final bool beside;

  @override
  bool updateShouldNotify(_SplitColumn oldWidget) =>
      column != oldWidget.column || beside != oldWidget.beside;
}

class _GlassSplitViewState extends State<GlassSplitView> {
  GlassSplitViewController? _own;
  late final MotionValue<double> _reveal;
  late final MotionValue<double> _share;
  final _drag = ValueNotifier<double?>(null);
  ColumnFold? _fold;
  double _from = 0;
  late double? _width;
  late bool _shows;
  // The primary column's width in the last layout, within its limits.
  double _laid = 0;
  // The view's width in the last layout.
  double _viewWidth = 0;
  // The primary column's width past the inset where a band the hardware
  // splits the view at holds the border, or null.
  double? _bandWidth;
  final _primaryKey = GlobalKey(debugLabel: 'GlassSplitView.primary');
  final _secondaryKey = GlobalKey(debugLabel: 'GlassSplitView.secondary');
  final _stack = GlobalKey<NavigatorState>(debugLabel: 'GlassSplitView');
  final _primaryFocus = FocusNode(debugLabel: 'GlassSplitView primary');
  final _secondaryFocus = FocusNode(debugLabel: 'GlassSplitView secondary');

  GlassSplitViewController get _controller =>
      widget.controller ?? (_own ??= GlassSplitViewController());

  bool get _showsNow =>
      _controller._showsPrimary ?? widget.showsPrimaryByDefault;

  @override
  void initState() {
    super.initState();
    final clock = MotionClockScope.of(context);
    final controller = _controller;
    _width = controller.primaryWidth;
    controller._primaryByDefault = widget.showsPrimaryByDefault;
    _shows = _showsNow;
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
    _controller._primaryByDefault = widget.showsPrimaryByDefault;
    // A change of layout moves the column at once, as UIKit's does on a
    // rotation.
    final shows = _showsNow;
    if (shows != _shows) {
      _shows = shows;
      withoutAnimation(() => _reveal.target = shows ? 1 : 0);
      _keepFocus();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    _drag.dispose();
    _primaryFocus.dispose();
    _secondaryFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(_follow);

  // Moves the focus out of the primary column that hides to the secondary,
  // where the view's keys still reach it, as UIKit moves it to the
  // content.
  void _keepFocus() {
    if (_shows || !_primaryFocus.hasFocus) return;
    // After the frame: the frame that hides the column takes the focus out
    // of it, and where the focus lies draws nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_shows && !_secondaryFocus.hasFocus) {
        _secondaryFocus.requestFocus();
      }
    });
  }

  void _follow() {
    final controller = _controller;
    final shows = _showsNow;
    if (shows != _shows) {
      _shows = shows;
      SplitViewMotion.reveal(_reveal, shown: shows);
      _keepFocus();
    }
    if (controller.primaryWidth != _width) {
      _width = controller.primaryWidth;
      _from = _laid;
      SplitViewMotion.resize(_share);
    }
  }

  // The primary column's forms as a hand drags the divider: hidden, when
  // the sidebar button brings it back, and its width within its limits.
  List<ColumnForm> _forms() {
    final (low, high) = _limits(_viewWidth);
    return [
      if (widget.showsSidebarButton) const ColumnForm(width: 0),
      ColumnForm(
        width: _settledWidth(_viewWidth),
        min: low,
        max: math.max(low, high),
      ),
    ];
  }

  void _dragStarted() {
    final forms = _forms();
    setState(() {
      _fold = ColumnFold(forms, form: forms.length - 1, width: _laid);
    });
  }

  void _dragged(double travel) {
    final fold = _fold;
    if (fold == null) return;
    final folded = fold.update(travel);
    final shows = fold.form == fold.forms.length - 1;
    _drag.value = shows ? fold.width : null;
    if (!folded) return;
    shows
        ? _controller.show(GlassSplitViewColumn.primary)
        : _controller.hide(GlassSplitViewColumn.primary);
  }

  // Writes where the hand let the divider go, unless the column folded away
  // or came back to the width it had, which stays the controller's.
  void _released() {
    final dragged = _drag.value;
    final had = _fold?.forms.last.width;
    setState(() => _fold = null);
    if (dragged == null) return;
    _laid = dragged;
    _drag.value = null;
    if (dragged != had) _controller.primaryWidth = dragged;
  }

  void _step(ValueCommand command) {
    final forms = _forms();
    final column = forms.last;
    final step = math.max(1, (_viewWidth / 20).roundToDouble());
    final from = _settledWidth(_viewWidth);
    final by = switch (command) {
      ValueCommand.increase => step,
      ValueCommand.decrease => -step,
      ValueCommand.increaseLarge => 5 * step,
      ValueCommand.decreaseLarge => -5 * step,
      ValueCommand.toMaximum => column.max - from,
      ValueCommand.toMinimum => column.min - from,
    };
    if (by == 0) return;
    final (form, width) = ColumnFold.step(
      forms,
      form: forms.length - 1,
      width: from,
      by: by.toDouble(),
    );
    if (form < forms.length - 1) {
      _controller.hide(GlassSplitViewColumn.primary);
    } else {
      _controller.primaryWidth = width;
    }
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
      _bandWidth ?? _fit(width, _width ?? _preferred(width));

  double _liveWidth(double width) {
    if (_bandWidth case final band?) return band;
    final dragged = _drag.value;
    if (dragged != null) return _fit(width, dragged);
    final rule = _width ?? _preferred(width);
    return _fit(width, lerpDouble(_from, rule, _share.value)!);
  }

  double _laidOut(double width) {
    _viewWidth = width;
    return _laid = _liveWidth(width);
  }

  // The part of a view [width] wide the leading inset covers.
  double _inset(double width) => widget.leadingInset.clamp(0, width);

  // The band in [media] that splits a view [width] wide with room on both
  // sides of the part past [inset].
  static Rect? _bandIn(
    MediaQueryData media,
    double width,
    double inset, {
    required bool ltr,
  }) {
    final band = media.verticalBand;
    if (band == null || band.right >= width) return null;
    return (ltr ? band.left > inset : band.right < width - inset) ? band : null;
  }

  void _toggle() => _shows
      ? _controller.hide(GlassSplitViewColumn.primary)
      : _controller.show(GlassSplitViewColumn.primary);

  late final _toggleAction = CallbackAction<GlassToggleSidebarIntent>(
    onInvoke: (_) {
      _toggle();
      return null;
    },
  );

  GlassBarButton _sidebarButton(GlassLocalizations strings) => GlassBarButton(
    key: const ValueKey<Object>(GlassSplitView),
    icon: const GlassSidebarGlyph(),
    semanticLabel: _shows ? strings.hideSidebarLabel : strings.showSidebarLabel,
    onPressed: _toggle,
  );

  // What a column [width] wide at [left] in the view gets of [media]: the
  // safe area and the insets of the view's sides it touches ([start],
  // [end]), [inner] on a side it does not, and the display features it
  // overlaps in its own coordinates, but [band].
  static MediaQueryData _slice(
    MediaQueryData media, {
    required double left,
    required double width,
    required bool start,
    required bool end,
    required TextDirection direction,
    double inset = 0,
    double inner = 0,
    Rect? band,
  }) {
    final ltr = direction == TextDirection.ltr;
    final touchesLeft = ltr ? start : end;
    final touchesRight = ltr ? end : start;
    EdgeInsets cut(EdgeInsets insets) => insets.copyWith(
      left: !touchesLeft
          ? inner
          : ltr
          ? math.max(insets.left, inset)
          : null,
      right: !touchesRight
          ? inner
          : ltr
          ? null
          : math.max(insets.right, inset),
    );
    final size = Size(width, media.size.height);
    final box = Offset.zero & size;
    return media.copyWith(
      size: size,
      padding: cut(media.padding),
      viewPadding: cut(media.viewPadding),
      viewInsets: media.viewInsets.copyWith(
        left: touchesLeft ? null : 0,
        right: touchesRight ? null : 0,
      ),
      displayFeatures: [
        for (final feature in media.displayFeatures)
          if (feature.bounds != band)
            if (feature.bounds.shift(Offset(-left, 0)) case final bounds
                when bounds.overlaps(box))
              DisplayFeature(
                bounds: bounds,
                type: feature.type,
                state: feature.state,
              ),
      ],
    );
  }

  // Whether the view collapses, where the window is [compact] across
  // unless the widget says, telling the controller; the listeners hear a
  // change after the frame.
  bool _collapse({required bool compact}) {
    final collapsed = widget.collapsed ?? compact;
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
    return GlassNestedPop(
      navigator: _stack,
      active: secondaryOnTop,
      child: Navigator(
        key: _stack,
        pages: [
          _ColumnPage(
            key: const ValueKey(GlassSplitViewColumn.primary),
            child: _SplitColumn(
              column: GlassSplitViewColumn.primary,
              beside: false,
              child: GlassMovableSubtree(
                key: _primaryKey,
                child: widget.primary,
              ),
            ),
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
                child: _SplitColumn(
                  column: GlassSplitViewColumn.secondary,
                  beside: false,
                  child: KeyedSubtree(
                    key: _secondaryKey,
                    child: widget.secondary,
                  ),
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
    final back = GlassBarSupplement.maybeOf(context)?.back;
    final background = GlassDynamicColor.resolve(
      widget.primaryBackgroundColor ?? GlassSplitView.sidebarColor,
      context,
    );
    final compact = !GlassEnvironment.of(context).isRegularWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (_collapse(compact: compact)) {
          return InputCommands(
            shortcuts: widget.shortcuts,
            child: _collapsedStack(strings),
          );
        }
        final ltr = direction == TextDirection.ltr;
        final inset = _inset(width);
        final rest = width - inset;
        final band = _bandIn(media, width, inset, ltr: ltr);
        _bandWidth = band == null
            ? null
            : (ltr ? band.left : width - band.right) + band.width / 2 - inset;
        final columnWidth = _settledWidth(rest);
        final primaryWidth = inset + columnWidth;
        final share = rest > 0 ? columnWidth / rest : 0.0;
        final primaryLeft = ltr ? 0.0 : width - primaryWidth;
        final secondaryLeft = _shows && ltr ? primaryWidth : 0.0;
        final secondaryWidth = _shows ? width - primaryWidth : width;
        final secondaryBand = _shows ? band : null;
        double inner(Rect? band, double left, double width) => band == null
            ? 0
            : math.max(
                0,
                math.min(band.right, left + width) - math.max(band.left, left),
              );
        final primaryInner = inner(band, primaryLeft, primaryWidth);
        final secondaryInner = inner(
          secondaryBand,
          secondaryLeft,
          secondaryWidth,
        );
        final primary = Focus(
          focusNode: _primaryFocus,
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          descendantsAreFocusable: _shows,
          child: ExcludeSemantics(
            excluding: !_shows,
            child: MediaQuery(
              data: _slice(
                media,
                left: primaryLeft,
                width: primaryWidth,
                start: true,
                end: false,
                direction: direction,
                inset: inset,
                inner: primaryInner,
                band: band,
              ),
              child: GlassPageBackground(
                color: background,
                child: GlassBarSupplement(
                  trailing: _shows ? button : null,
                  back: _shows ? back : null,
                  child: GlassBarInset(
                    leading: inset,
                    trailing: primaryInner,
                    child: GlassOwnBars(
                      child: _ColumnEnvironment(
                        left: primaryLeft,
                        width: primaryWidth,
                        whole: width,
                        ownWidth: columnWidth,
                        child: _SplitColumn(
                          column: GlassSplitViewColumn.primary,
                          beside: _shows,
                          child: GlassMovableSubtree(
                            key: _primaryKey,
                            child: widget.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final secondary = Focus(
          focusNode: _secondaryFocus,
          skipTraversal: true,
          includeSemantics: false,
          child: MediaQuery(
            data: _slice(
              media,
              left: secondaryLeft,
              width: secondaryWidth,
              start: !_shows,
              end: true,
              direction: direction,
              inset: inset,
              inner: secondaryInner,
              band: secondaryBand,
            ),
            child: GlassBarSupplement(
              beforeBack: _shows ? null : button,
              back: _shows ? null : back,
              child: GlassBarInset(
                leading: _shows ? secondaryInner : inset,
                child: GlassOwnBars(
                  child: _ColumnEnvironment(
                    left: secondaryLeft,
                    width: secondaryWidth,
                    whole: width,
                    ownWidth: _shows ? rest - columnWidth : rest,
                    child: _SplitColumn(
                      column: GlassSplitViewColumn.secondary,
                      beside: _shows,
                      child: KeyedSubtree(
                        key: _secondaryKey,
                        child: widget.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final (low, high) = _limits(rest);
        String value(double share) =>
            widget.semanticFormatterCallback?.call(share) ??
            strings.percentValue(share);
        final step = rest > 0 ? 1 / 20 : 0.0;
        final divider =
            widget.resizable && band == null && (_shows || _fold != null)
            ? GlassColumnDivider(
                range: AdjustRange.of(
                  columnWidth,
                  min: widget.showsSidebarButton ? 0 : low,
                  max: high,
                ),
                value: value(share),
                increasedValue: value(math.min(share + step, 1)),
                decreasedValue: value(math.max(share - step, 0)),
                onDragStart: _dragStarted,
                onDragUpdate: _dragged,
                onDragEnd: _released,
                onStep: _step,
                onReset: _controller.resetPrimaryWidth,
              )
            : null;
        // Each column is a semantics container of its own: a modal route
        // in the primary column's navigator blocks the semantics painted
        // before it in its container, which would be the secondary column.
        return InputCommands(
          shortcuts: widget.shortcuts,
          actions: {
            if (button != null) GlassToggleSidebarIntent: _toggleAction,
          },
          child: ClipRect(
            child: _SplitLayout(
              state: this,
              direction: direction,
              children: [
                Semantics(container: true, child: secondary),
                Semantics(container: true, child: primary),
                ?divider,
              ],
            ),
          ),
        );
      },
    );
  }
}

// A column side by side reads the size class of its own width, the window
// buttons at the window's edges it touches, and what the hardware covers in
// its own coordinates: a status cluster beside the column still tells its
// rows they share the status row.
class _ColumnEnvironment extends StatelessWidget {
  const _ColumnEnvironment({
    required this.left,
    required this.width,
    required this.whole,
    required this.ownWidth,
    required this.child,
  });

  // Where the column's box starts in the view's, and how wide it is.
  final double left;
  final double width;

  // The view's width.
  final double whole;

  // The column's width past what covers its leading side.
  final double ownWidth;

  final Widget child;

  static const double _tolerance = 0.5;

  @override
  Widget build(BuildContext context) {
    final environment = GlassEnvironment.of(context);
    final buttons = environment.windowControls;
    final right = left + width;
    return GlassEnvironmentOverride(
      horizontalSizeClass: ownWidth >= GlassEnvironment.regularWidthFrom
          ? GlassSizeClass.regular
          : GlassSizeClass.compact,
      windowControls: GlassWindowControls(
        left: left <= _tolerance ? buttons.left : null,
        right: right >= whole - _tolerance ? buttons.right : null,
        lineCenter: buttons.lineCenter,
      ),
      occlusions: [
        for (final occlusion in environment.occlusions)
          occlusion.shift(Offset(-left, 0)),
      ],
      child: child,
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
    final inset = _state._inset(width);
    final primaryWidth = inset + _state._laidOut(width - inset);
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
