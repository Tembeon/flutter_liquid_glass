/// Menus and the context menu, the alert and the action sheet, the sheet,
/// the popover and the compact date picker.
///
/// For the app developer: `GlassMenuAnchor`, which grows a menu out of any
/// control, and `GlassContextMenu`, with their entries; `showGlassAlert`,
/// `showGlassActionSheet`, `showGlassSheet`, `showGlassPopover` and
/// `GlassCompactDatePicker`, each with its style.
///
/// It promises that a presentation moves by the measured laws of
/// `motions` on kinesis's presentations, and works with every renderer.
library;

export 'src/presentations/alert.dart'
    show
        GlassAlertAction,
        GlassAlertStyle,
        showGlassActionSheet,
        showGlassAlert;
export 'src/presentations/date_picker.dart'
    show GlassCompactDatePicker, GlassDatePickerMode;
export 'src/presentations/menu_anchor.dart'
    show
        GlassContextMenu,
        GlassMenuAnchor,
        GlassMenuAnchorChildBuilder,
        GlassMenuController;
export 'src/presentations/menu_appearance.dart' show GlassMenuStyle;
export 'src/presentations/menu_entries.dart'
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
export 'src/presentations/popover.dart'
    show GlassPopoverStyle, showGlassPopover;
export 'src/presentations/sheet.dart'
    show GlassSheet, GlassSheetStyle, showGlassSheet;
