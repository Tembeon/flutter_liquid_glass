/// The finished iOS widgets: controls, bars and presentations.
///
/// Controls: `GlassButton` (glass, and plain without glass), `GlassSwitch`,
/// `GlassSlider`, `GlassStepper`, `GlassSegmentedControl`, `GlassPageControl`,
/// `GlassSearchField` with its glyphs `GlassSearchIcon` and `GlassCloseIcon`,
/// `GlassTextField`, `GlassListRow` and its sections and `GlassListBackground`,
/// `GlassSwipeActions`, `GlassDatePicker`, `GlassTimePicker` and `GlassBadge`.
///
/// Bars and pages: `GlassNavigationBar`, `GlassToolbar`, `GlassTabBar` with
/// its action circle (`GlassTabBarAction`), `GlassTabScaffold`, which
/// `GlassFloatingTabBar` takes apart for an app that keeps its tabs' pages,
/// `GlassPageScaffold` with what scrolls under the bars
/// (large titles, scroll edge effects), `GlassPageRoute` with its zoom
/// transition, `GlassSplitView`, a sidebar beside its content, with its
/// `GlassSplitViewController`, and the bar items they hold (`GlassBarItem`:
/// `GlassBarButton`, `GlassBarProminentButton`, `GlassBarCustomItem`;
/// `GlassBarSpacer`).
///
/// Presentations: `GlassMenuAnchor`, which grows a menu out of any control,
/// and `GlassContextMenu`, with their entries; `showGlassAlert`,
/// `showGlassActionSheet`, `showGlassSheet`, `showGlassPopover`,
/// `GlassCompactDatePicker`, `GlassTooltip`, a mouse's hint, and
/// `showGlassToast`, which shows a `GlassToast` on a `GlassToaster`.
///
/// For the app developer: put one in and it works. Each widget has a
/// `*Style` beside it, shaped like Flutter's `ButtonStyle`, and looks a
/// field up in its own style, then in the theme's style of that type
/// (`GlassSwitchStyle.maybeOf`), then in its defaults. The prominent
/// buttons' theme style is a `GlassProminentButtonStyle`, the plain
/// button's a `GlassPlainButtonStyle`.
///
/// It promises that every widget moves by the measured laws of `motions`
/// and works with every renderer: no widget asks which renderer draws it.
library;

export 'src/widgets/controls/badge.dart' show GlassBadge, GlassBadgeStyle;
export 'src/widgets/controls/button.dart'
    show
        GlassButton,
        GlassButtonStyle,
        GlassPlainButtonStyle,
        GlassProminentButtonStyle;
export 'src/widgets/controls/date_picker.dart'
    show GlassDatePicker, GlassDatePickerStyle, GlassTimePicker;
export 'src/widgets/controls/list.dart'
    show
        GlassListBackground,
        GlassListRow,
        GlassListSection,
        GlassSliverListSection;
export 'src/widgets/controls/list_accessory.dart' show GlassListAccessory;
export 'src/widgets/controls/list_style.dart' show GlassListStyle;
export 'src/widgets/controls/page_control.dart'
    show GlassPageControl, GlassPageControlStyle;
export 'src/widgets/controls/search_field.dart'
    show GlassSearchField, GlassSearchFieldStyle;
export 'src/widgets/controls/search_glyphs.dart'
    show GlassCloseIcon, GlassSearchIcon;
export 'src/widgets/controls/segmented_control.dart'
    show GlassSegment, GlassSegmentedControl, GlassSegmentedStyle;
export 'src/widgets/controls/slider.dart' show GlassSlider, GlassSliderStyle;
export 'src/widgets/controls/stepper.dart' show GlassStepper, GlassStepperStyle;
export 'src/widgets/controls/swipe_actions.dart'
    show GlassSwipeAction, GlassSwipeActions;
export 'src/widgets/controls/switch.dart' show GlassSwitch, GlassSwitchStyle;
export 'src/widgets/controls/text_field.dart'
    show GlassTextField, GlassTextFieldStyle;
export 'src/widgets/navigation/bar_entry.dart'
    show
        GlassBackButtonDisplayMode,
        GlassBarButton,
        GlassBarCustomItem,
        GlassBarEntry,
        GlassBarItem,
        GlassBarItemStyle,
        GlassBarProminentButton,
        GlassBarSpacer;
export 'src/widgets/navigation/chrome.dart'
    show
        GlassContentScroll,
        GlassPageScaffold,
        GlassScrollEdgeEffect,
        GlassScrollEdgeEffects;
export 'src/widgets/navigation/column_divider.dart' show GlassColumnDivider;
export 'src/widgets/navigation/floating_tab_bar.dart' show GlassFloatingTabBar;
export 'src/widgets/navigation/navigation_bar.dart'
    show GlassNavigationBar, GlassNavigationBarStyle;
export 'src/widgets/navigation/page_route.dart'
    show GlassPageRoute, GlassZoomSource;
export 'src/widgets/navigation/split_view.dart'
    show
        GlassSplitView,
        GlassSplitViewColumn,
        GlassSplitViewController,
        GlassToggleSidebarIntent;
export 'src/widgets/navigation/tab_bar.dart'
    show
        GlassTabAccessoryPlacement,
        GlassTabBar,
        GlassTabBarAction,
        GlassTabBarStyle,
        GlassTabDestination;
export 'src/widgets/navigation/tab_layout.dart'
    show
        GlassTabLayout,
        GlassTabLayoutPolicy,
        GlassTabLayoutState,
        GlassTabListMode,
        GlassTabListState,
        GlassTabPlacement,
        GlassTabSidebarPanel,
        GlassWidthRange;
export 'src/widgets/navigation/tab_scaffold.dart'
    show
        GlassSelectTabIntent,
        GlassTab,
        GlassTabController,
        GlassTabPage,
        GlassTabScaffold,
        GlassTabSidebar,
        GlassTabSidebarRow,
        GlassTabSidebarRowBuilder,
        GlassTabSidebarRowDetails,
        GlassTabSidebarStyle,
        GlassTabStack;
export 'src/widgets/navigation/toolbar.dart'
    show GlassToolbar, GlassToolbarStyle;
export 'src/widgets/presentations/alert.dart'
    show
        GlassAlertAction,
        GlassAlertStyle,
        showGlassActionSheet,
        showGlassAlert;
export 'src/widgets/presentations/date_picker.dart'
    show GlassCompactDatePicker, GlassDatePickerMode;
export 'src/widgets/presentations/menu_anchor.dart'
    show
        GlassContextMenu,
        GlassMenuAnchor,
        GlassMenuAnchorChildBuilder,
        GlassMenuController;
export 'src/widgets/presentations/menu_appearance.dart' show GlassMenuStyle;
export 'src/widgets/presentations/menu_entries.dart'
    show
        GlassMenuDeferred,
        GlassMenuDivider,
        GlassMenuElementSize,
        GlassMenuEntry,
        GlassMenuIconVisibility,
        GlassMenuItem,
        GlassMenuItemState,
        GlassMenuOrder,
        GlassMenuSection,
        GlassMenuWidget,
        GlassSubmenu;
export 'src/widgets/presentations/popover.dart'
    show GlassPopoverStyle, showGlassPopover;
export 'src/widgets/presentations/sheet.dart'
    show GlassSheet, GlassSheetStyle, showGlassSheet;
export 'src/widgets/presentations/toast.dart'
    show
        GlassToast,
        GlassToastBuilder,
        GlassToastEntry,
        GlassToaster,
        showGlassToast;
export 'src/widgets/presentations/tooltip.dart' show GlassTooltip;
