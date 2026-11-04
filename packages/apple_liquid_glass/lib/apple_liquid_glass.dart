/// iOS 27 Liquid Glass controls, bars and presentations for Flutter, with
/// UIKit's measured motion.
///
/// The app picks how glass draws in `GlassTheme`: `GlassRenderer.liquid()`,
/// `.fake()`, `.flat()` or `.adaptive(...)`. The motion the controls run on
/// is kinesis, exported here as its app library; an app's own control or
/// presentation is written with `package:apple_liquid_glass/motion.dart`,
/// and an app's own renderer with
/// `package:apple_liquid_glass/glass_renderer.dart`.
library;

export 'package:kinesis/kinesis.dart';

export 'src/chrome/bar_entry.dart'
    show
        GlassBackButtonDisplayMode,
        GlassBarEntry,
        GlassBarItem,
        GlassBarSpacer;
export 'src/chrome/chrome.dart'
    show
        GlassContentScroll,
        GlassPageScaffold,
        GlassScrollEdgeEffect,
        GlassScrollEdgeEffects;
export 'src/chrome/navigation_bar.dart'
    show GlassNavigationBar, GlassNavigationBarStyle;
export 'src/chrome/page_route.dart' show GlassPageRoute, GlassZoomSource;
export 'src/chrome/tab_scaffold.dart' show GlassTabScaffold;
export 'src/chrome/toolbar.dart' show GlassToolbar;
export 'src/controls/badge.dart' show GlassBadge, GlassBadgeStyle;
export 'src/controls/button.dart'
    show
        GlassButton,
        GlassButtonBuilder,
        GlassButtonDetails,
        GlassButtonStyle,
        GlassPressable;
export 'src/controls/date_picker.dart'
    show
        GlassDatePicker,
        GlassDatePickerLocalizations,
        GlassDatePickerMode,
        GlassDatePickerStyle,
        GlassDatePickerVariant;
export 'src/controls/list.dart'
    show
        GlassListAccessory,
        GlassListBackground,
        GlassListRow,
        GlassListSection,
        GlassListStyle,
        GlassSliverListSection;
export 'src/controls/page_control.dart'
    show
        GlassPageControl,
        GlassPageControlBackground,
        GlassPageControlBuilder,
        GlassPageControlDetails,
        GlassPageControlPose,
        GlassPageControlStyle,
        RawGlassPageControl;
export 'src/controls/search_controller.dart' show GlassSearchController;
export 'src/controls/search_field.dart'
    show
        GlassSearchField,
        GlassSearchFieldBuilder,
        GlassSearchFieldDetails,
        GlassSearchFieldStyle,
        RawGlassSearchField;
export 'src/controls/segmented_control.dart'
    show GlassSegment, GlassSegmentedControl, GlassSegmentedStyle;
export 'src/controls/selector.dart'
    show
        GlassSelectorBuilder,
        GlassSelectorDetails,
        GlassSelectorItemBuilder,
        GlassSelectorMotion,
        RawGlassSelector;
export 'src/controls/slider.dart'
    show
        GlassSlider,
        GlassSliderBuilder,
        GlassSliderDetails,
        GlassSliderStyle,
        RawGlassSlider;
export 'src/controls/stepper.dart'
    show
        GlassStepper,
        GlassStepperBuilder,
        GlassStepperDetails,
        GlassStepperHalf,
        GlassStepperStyle,
        RawGlassStepper;
export 'src/controls/switch.dart'
    show
        GlassSwitch,
        GlassSwitchBuilder,
        GlassSwitchDetails,
        GlassSwitchStyle,
        RawGlassSwitch;
export 'src/controls/tab_bar.dart'
    show
        GlassTabAccessoryPlacement,
        GlassTabBar,
        GlassTabBarStyle,
        GlassTabDestination;
export 'src/menu/anchor.dart'
    show GlassContextMenu, GlassMenuController, RawGlassMenu;
export 'src/menu/appearance.dart' show GlassMenuStyle;
export 'src/menu/entries.dart'
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
export 'src/motion/sheet_motion.dart' show GlassSheetDetent;
export 'src/motion/tab_minimize.dart' show GlassTabBarMinimizeBehavior;
export 'src/motion/touch_glow.dart' show GlassTouchGlow;
export 'src/presentations/alert.dart'
    show
        GlassAlertAction,
        GlassAlertStyle,
        showGlassActionSheet,
        showGlassAlert;
export 'src/presentations/popover.dart'
    show GlassPopoverStyle, showGlassPopover;
export 'src/presentations/sheet.dart'
    show GlassSheet, GlassSheetStyle, showGlassSheet;
export 'src/renderer/renderer.dart' show GlassRenderer;
export 'src/surface/clip.dart' show GlassClip;
export 'src/surface/frame.dart' show GlassFrame;
export 'src/surface/glass.dart' show Glass, GlassRole;
export 'src/surface/group.dart' show GlassGroup, GlassMerge;
export 'src/surface/outline.dart' show GlassOutline;
export 'src/surface/shape.dart' show GlassShape;
export 'src/surface/surface.dart' show GlassSurface;
export 'src/theme/colors.dart' show GlassColors, GlassDynamicColor;
export 'src/theme/theme.dart'
    show AnimatedGlassTheme, GlassColorScheme, GlassTheme, GlassThemeData;
export 'src/theme/traits.dart'
    show GlassInterfaceLevel, GlassTraits, GlassTraitsOverride;
export 'src/theme/typography.dart' show GlassDefaultTextStyle, GlassTextRole;
