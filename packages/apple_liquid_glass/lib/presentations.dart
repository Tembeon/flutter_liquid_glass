/// Menus and the context menu, the alert and the action sheet, the sheet and
/// the popover.
///
/// For the app developer: `GlassContextMenu`, `RawGlassMenu` with its
/// entries, `showGlassAlert`, `showGlassActionSheet`, `showGlassSheet` and
/// `showGlassPopover`, each with its style.
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
export 'src/presentations/menu_anchor.dart'
    show
        GlassContextMenu,
        GlassMenuAnchor,
        GlassMenuAnchorChildBuilder,
        GlassMenuController,
        RawGlassMenu;
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
