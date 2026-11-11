/// The measured laws of iOS motion: how the switch, slider, lens, sheet,
/// bars, menus, alert, search and page zoom move, as pure classes on
/// kinesis's `Motion`, and the bar and menu layouts as plain math.
///
/// For the controls of this package, and for the tests that replay
/// recordings from an iPhone against the same laws. Its public names
/// today are the values a control's parameters take: `GlassSheetDetent`
/// and `GlassTabBarMinimizeBehavior`; the laws themselves are the
/// package's own.
///
/// It promises that a number in a law carries its source, a measurement on
/// the device or UIKit's tuning, in its dartdoc.
///
/// It never imports Flutter's widgets or rendering libraries, and never
/// decides what is drawn.
library;

export 'src/motions/alert_motion.dart' show AlertMotion;
export 'src/motions/bar_layout.dart'
    show
        GlassBarButtonKind,
        GlassBarButtonSpec,
        GlassBarCapsuleSpec,
        GlassBarItemId,
        GlassBarMetrics,
        layoutGlassBar;
export 'src/motions/bar_motion.dart'
    show
        GlassBarCapsuleFrame,
        GlassBarCapsuleLayout,
        GlassBarItemFrame,
        GlassBarMotion,
        GlassBarTransitionSpec;
export 'src/motions/date_picker_motion.dart'
    show
        DatePickerCalendarMotion,
        DatePickerLabelMotion,
        DatePickerMotion,
        DatePickerPlacement,
        placeDatePicker;
export 'src/motions/flex_interaction.dart' show FlexValues;
export 'src/motions/glass_press.dart' show FlexLaw, GlassPress;
export 'src/motions/lens_motion.dart'
    show LensEvent, LensMotion, LensSelected, LensSlot;
export 'src/motions/list_highlight.dart' show ListRowHighlight;
export 'src/motions/menu_context_hold.dart' show ContextHold;
export 'src/motions/menu_layout.dart'
    show
        MenuDividerSpec,
        MenuLayout,
        MenuLoadingSpec,
        MenuMetrics,
        MenuPlaced,
        MenuPlacedKind,
        MenuRowSpec,
        MenuSectionSpec,
        MenuSpec,
        MenuSpecSize,
        MenuTarget,
        MenuTargetKind,
        MenuWidgetSpec;
export 'src/motions/menu_motion.dart'
    show
        MenuActivated,
        MenuAttachment,
        MenuCapsuleSource,
        MenuCard,
        MenuEvent,
        MenuHighlightChanged,
        MenuMotion,
        MenuSource,
        MenuTapped;
export 'src/motions/navigation_motion.dart'
    show NavigationPopMotion, PageMotion, PageSlideMotion;
export 'src/motions/page_control_motion.dart'
    show PageControlEvent, PageControlMotion, PageControlPicked;
export 'src/motions/popover_motion.dart'
    show PopoverArrowDirection, PopoverMotion, PopoverPlacement, placePopover;
export 'src/motions/search_motion.dart'
    show
        SearchBarGeometry,
        SearchMotion,
        SearchTabGeometry,
        searchBarLayout,
        searchTabLayout;
export 'src/motions/segment_highlight.dart' show SegmentHighlight;
export 'src/motions/sheet_motion.dart'
    show
        GlassSheetDetent,
        SheetDetentChanged,
        SheetDismissRefused,
        SheetDismissed,
        SheetEvent,
        SheetMotion;
export 'src/motions/slider_motion.dart'
    show
        SliderChangeEnded,
        SliderChanged,
        SliderEvent,
        SliderFelt,
        SliderMotion;
export 'src/motions/small_lens.dart' show SmallLens;
export 'src/motions/switch_motion.dart'
    show SwitchChanged, SwitchEvent, SwitchMotion, SwitchShown;
export 'src/motions/tab_bar_layout.dart' show TabBarLayout;
export 'src/motions/tab_minimize.dart'
    show GlassTabBarMinimizeBehavior, ScrollAway, TabBarMinimizeMotion;
export 'src/motions/touch_glow.dart' show TouchGlowMotion;
export 'src/motions/zoom_page_motion.dart' show ZoomPageMotion;
