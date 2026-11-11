import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// The measured layout of the inside of an iOS 27 menu.
///
/// Read from the view tree of `UIButton` menus on the iPhone 16 Pro (iOS
/// 27.0.1, light and dark, 2026-10-03): `_UIContextMenuListView`,
/// `_UIContextMenuCell`, `_UIContextMenuHeaderView`,
/// `_UIContextMenuSeparatorView`, `_UIContextMenuSubmenuTitleView`.
/// Lengths are points from the menu's leading edge or top.
class MenuMetrics {
  /// Creates metrics from explicit values.
  const MenuMetrics({
    this.width = 250,
    this.topInset = 10,
    this.bottomInset = 10,
    this.rowHeight = 42,
    this.subtitleRowHeight = 60,
    this.extraLineHeight = 22,
    this.imageCenter = 40,
    this.titleStart = 64,
    this.selectionCheckCenter = 27.7,
    this.selectionImageCenter = 55,
    this.selectionTitleStart = 79,
    this.selectionOnlyTitleStart = 52,
    this.plainTitleStart = 28,
    this.titleEnd = 222,
    this.chevronCenter = 219,
    this.headerHeight = 40.33,
    this.headerLabelTop = 12,
    this.headerStart = 28,
    this.selectionHeaderStart = 43,
    this.rowsAfterHeader = 38.33,
    this.cellsAfterHeader = 28.33,
    this.groupGap = 21,
    this.cellGroupGap = 1,
    this.separatorInset = 24,
    this.paletteCellWidth = 42.67,
    this.paletteMaxCellWidth = 62.67,
    this.paletteCellHeight = 54,
    this.paletteImageSize = 22,
    this.palettePlatter = 38,
    this.palettePlatterRadius = 10,
    this.cellInset = 8,
    this.smallCellHeight = 51.67,
    this.smallPerRow = 4,
    this.mediumCellHeight = 77,
    this.mediumPerRow = 3,
    this.mediumLabelTop = 44.67,
    this.cardHeaderHeight = 62,
    this.widgetInset = 16,
    this.maxHeight = 520,
  });

  /// The width of the menu.
  final double width;

  /// The space above the first row.
  final double topInset;

  /// The space below the last row.
  final double bottomInset;

  /// The height of a row.
  final double rowHeight;

  /// The height of a row with a subtitle (title 17 pt, subtitle 13 pt 23 pt
  /// below the title's top).
  final double subtitleRowHeight;

  /// The height a row gains per extra title line; not measured (the line
  /// height of the 17 pt title).
  final double extraLineHeight;

  /// The center of a row's glyph.
  final double imageCenter;

  /// The start of a row's title.
  final double titleStart;

  /// The center of the checkmark in a menu with a selection column.
  final double selectionCheckCenter;

  /// The center of a row's glyph in a menu with a selection column.
  final double selectionImageCenter;

  /// The start of a row's title in a menu with a selection column.
  final double selectionTitleStart;

  /// The start of a row's title in a menu with a selection column and no
  /// glyphs; not measured.
  final double selectionOnlyTitleStart;

  /// The start of a row's title in a menu without glyphs.
  final double plainTitleStart;

  /// The end of a row's title, before the trailing chevron.
  final double titleEnd;

  /// The center of a submenu row's chevron and of a card header's.
  final double chevronCenter;

  /// The height of a section header.
  final double headerHeight;

  /// The top of a section header's 13 pt label.
  final double headerLabelTop;

  /// The start of a section header's label.
  final double headerStart;

  /// The start of a section header's label in a menu with a selection
  /// column.
  final double selectionHeaderStart;

  /// The distance from a section header's top to its first row: the rows
  /// overlap the header's lower part.
  final double rowsAfterHeader;

  /// The distance from a section header's top to a row of cells.
  final double cellsAfterHeader;

  /// The gap between two groups of rows, with the hairline in its middle.
  final double groupGap;

  /// The gap after a group of small or medium cells, which holds the
  /// hairline; a palette is followed by no gap and no line.
  final double cellGroupGap;

  /// The inset of the group hairline from both sides of the menu.
  final double separatorInset;

  /// The width of each of five palette cells; the row keeps five cells'
  /// width, so fewer cells widen and more narrow.
  final double paletteCellWidth;

  /// The widest palette cell (three cells, SwiftUI's palette picker).
  final double paletteMaxCellWidth;

  /// The height of a palette cell.
  final double paletteCellHeight;

  /// The size of a palette cell's glyph.
  final double paletteImageSize;

  /// The side of the platter under the selected palette cell, read from a
  /// screenshot.
  final double palettePlatter;

  /// The corner radius of the palette platter; not measured.
  final double palettePlatterRadius;

  /// The inset of small and medium cells from the menu's sides.
  final double cellInset;

  /// The height of a small cell.
  final double smallCellHeight;

  /// Small cells per line.
  final int smallPerRow;

  /// The height of a medium cell.
  final double mediumCellHeight;

  /// Medium cells per line.
  final int mediumPerRow;

  /// The top of a medium cell's 12 pt label.
  final double mediumLabelTop;

  /// The height of a submenu card's header.
  final double cardHeaderHeight;

  /// The inset of a free-form row from the menu's sides; morph's
  /// own (no native element).
  final double widgetInset;

  /// The tallest a menu gets; taller content scrolls inside it.
  final double maxHeight;

  /// The measured iOS 27 menu.
  static const standard = MenuMetrics();
}

/// How the elements of a group of a menu are laid out.
enum MenuSpecSize {
  /// Full-width rows.
  rows,

  /// Small cells, four to a row.
  small,

  /// Medium cells, three to a row.
  medium,

  /// One row of palette cells.
  palette,
}

/// What the layout of a menu reads of one of its entries: its kind, its
/// size and whether it has an icon, with no widget.
///
/// The presenter builds the specs from its entries and keeps each entry in
/// [entry], which the layout hands back on the elements and targets it
/// places for it without reading it.
@immutable
sealed class MenuSpec {
  const MenuSpec({this.entry});

  /// The presenter's entry behind the spec, opaque to the layout.
  final Object? entry;
}

/// An item or a submenu: a row, or a cell in a group of cells.
final class MenuRowSpec extends MenuSpec {
  /// Describes a row titled [title].
  const MenuRowSpec({
    required this.title,
    this.subtitle,
    this.hasIcon = false,
    this.enabled = true,
    this.keepsOpen = false,
    this.marked = false,
    this.submenu = false,
    super.entry,
  });

  /// The title, measured when it may wrap.
  final String title;

  /// The line under the title, or null; a row with one is taller.
  final String? subtitle;

  /// Whether the row shows an icon, which opens the icon column.
  final bool hasIcon;

  /// Whether choosing the row does anything; a disabled row is no target.
  final bool enabled;

  /// Whether the menu stays open after the row's action.
  final bool keepsOpen;

  /// Whether the row shows a selection mark, which opens the selection
  /// column.
  final bool marked;

  /// Whether the row opens a submenu card.
  final bool submenu;
}

/// A free-form row of the presenter's own.
final class MenuWidgetSpec extends MenuSpec {
  /// Describes a free-form row [height] high, or as high as measured under
  /// [key] when null.
  const MenuWidgetSpec({this.height, this.key, super.entry});

  /// The row's height, or null for its measured one.
  final double? height;

  /// The identity of the row's measured height, or null for its place
  /// among the free-form rows.
  final Object? key;
}

/// The line between two groups of a list.
final class MenuDividerSpec extends MenuSpec {
  /// Describes a divider.
  const MenuDividerSpec({super.entry});
}

/// A row that stands for a group still loading.
final class MenuLoadingSpec extends MenuSpec {
  /// Describes a loading row titled [title].
  const MenuLoadingSpec(this.title, {super.entry});

  /// The row's title.
  final String title;
}

/// A group of its own, with an optional header.
final class MenuSectionSpec extends MenuSpec {
  /// Describes a section of [children].
  const MenuSectionSpec({
    required this.children,
    this.title,
    this.singleSelection = false,
    this.size = MenuSpecSize.rows,
    this.maxTitleLines,
    super.entry,
  });

  /// The section's entries.
  final List<MenuSpec> children;

  /// The header, or null for none.
  final String? title;

  /// Whether the section is a single choice, which opens the selection
  /// column.
  final bool singleSelection;

  /// How the section's entries are laid out.
  final MenuSpecSize size;

  /// The most lines a row title wraps to, or null for one.
  final int? maxTitleLines;
}

/// What choosing a [MenuTarget] does.
enum MenuTargetKind {
  /// Runs an item's action.
  action,

  /// Opens a submenu card.
  submenu,

  /// Closes the top submenu card.
  back,
}

/// A place in a menu that reacts to a touch.
class MenuTarget {
  /// Creates a target.
  const MenuTarget({
    required this.rect,
    this.kind = MenuTargetKind.action,
    this.keepsOpen = false,
    this.entry,
    this.element = -1,
  });

  /// The frame, in the coordinates of its card's content.
  final Rect rect;

  /// What choosing the target does.
  final MenuTargetKind kind;

  /// Whether the menu stays open after the target's action.
  final bool keepsOpen;

  /// The entry behind the target ([MenuSpec.entry]).
  final Object? entry;

  /// The index of the element the target belongs to in
  /// [MenuLayout.elements], or -1.
  final int element;
}

/// The kind of a [MenuPlaced] element.
enum MenuPlacedKind {
  /// A full-width row of an item or a submenu.
  row,

  /// A section header.
  header,

  /// The hairline between two groups.
  separator,

  /// A palette cell.
  palette,

  /// A small cell.
  small,

  /// A medium cell.
  medium,

  /// The row shown while a deferred group loads.
  loading,

  /// A free-form row.
  widget,

  /// The header of a submenu card.
  cardHeader,
}

/// One element of a laid out menu.
class MenuPlaced {
  /// Creates an element.
  const MenuPlaced({
    required this.kind,
    required this.rect,
    this.entry,
    this.title,
    this.checkCenter,
    this.imageCenter,
    this.titleStart = 0,
    this.titleEnd = 0,
    this.maxLines = 1,
    this.target = -1,
    this.key,
  });

  /// The kind of the element.
  final MenuPlacedKind kind;

  /// The frame, in the coordinates of its card's content.
  final Rect rect;

  /// The entry drawn ([MenuSpec.entry]), if any.
  final Object? entry;

  /// The text of a header or a loading row.
  final String? title;

  /// The center of the selection mark from the leading edge, when the
  /// menu has a selection column.
  final double? checkCenter;

  /// The center of the glyph from the leading edge, when the menu has a
  /// glyph column.
  final double? imageCenter;

  /// The start of the title from the leading edge.
  final double titleStart;

  /// The end of the title from the leading edge.
  final double titleEnd;

  /// The most lines the title wraps to.
  final int maxLines;

  /// The index of the element's target in [MenuLayout.targets], or -1.
  final int target;

  /// The identity of a free-form row's measured height.
  final Object? key;
}

/// The laid out content of one menu card: its height, what it draws and
/// where it reacts to touches.
class MenuLayout {
  /// Creates a layout.
  const MenuLayout({
    required this.height,
    this.width = 250,
    this.targets = const [],
    this.elements = const [],
    this.loading = false,
  });

  /// [rows] rows of [rowHeight] between [inset]s, reversed when
  /// [reversed]: target `i` is row `i`.
  factory MenuLayout.uniform(
    int rows, {
    double width = 250,
    double rowHeight = 42,
    double inset = 10,
    bool reversed = false,
  }) {
    return MenuLayout(
      height: 2 * inset + rowHeight * rows,
      width: width,
      targets: [
        for (var i = 0; i < rows; i++)
          MenuTarget(
            rect: Rect.fromLTWH(
              0,
              inset + rowHeight * (reversed ? rows - 1 - i : i),
              width,
              rowHeight,
            ),
          ),
      ],
    );
  }

  /// Lays out [specs] as the iOS 27 menu does.
  ///
  /// [header] makes it a submenu card under that submenu's header; [size]
  /// lays out the entries outside sections. [widgetHeight] answers the
  /// height of a free-form row (keyed by its key or its place);
  /// [titleLines] answers how many lines a title takes when it may wrap to
  /// more than one. [reversed] reverses the groups and the rows inside
  /// them, for a menu opening upward; [rtl] mirrors the frames.
  factory MenuLayout.build(
    List<MenuSpec> specs, {
    MenuMetrics metrics = MenuMetrics.standard,
    bool reversed = false,
    bool rtl = false,
    bool singleSelection = false,
    MenuSpecSize size = MenuSpecSize.rows,
    MenuRowSpec? header,
    double? Function(Object key)? widgetHeight,
    int Function(String title, double width, int maxLines)? titleLines,
  }) {
    final groups = <_Group>[];
    var loading = false;
    _Group? open;
    var widgetIndex = 0;
    void flush() {
      final group = open;
      if (group != null && group.items.isNotEmpty) groups.add(group);
      open = null;
    }

    void add(
      List<MenuSpec> list,
      MenuSpecSize kind,
      int maxLines, {
      required bool section,
    }) {
      for (final spec in list) {
        switch (spec) {
          case MenuRowSpec():
            (open ??= _Group(kind, maxLines)).items.add(spec);
          case MenuWidgetSpec():
            (open ??= _Group(
              kind,
              maxLines,
            )).items.add(_WidgetSlot(spec, spec.key ?? widgetIndex));
            widgetIndex++;
          case MenuDividerSpec():
            if (!section) flush();
          case MenuLoadingSpec():
            loading = true;
            (open ??= _Group(kind, maxLines)).items.add(spec);
          case MenuSectionSpec():
            flush();
            open = _Group(
              spec.size,
              spec.maxTitleLines ?? 1,
              header: spec.title,
              singleSelection: spec.singleSelection,
            );
            add(
              spec.children,
              spec.size,
              spec.maxTitleLines ?? 1,
              section: true,
            );
            flush();
        }
      }
    }

    add(specs, size, 1, section: false);
    flush();
    if (reversed) {
      groups.setAll(0, groups.reversed.toList());
      for (final group in groups) {
        if (group.kind == MenuSpecSize.rows) {
          group.items.setAll(0, group.items.reversed.toList());
        }
      }
    }

    var selection = singleSelection;
    for (final group in groups) {
      if (group.singleSelection) selection = true;
      if (group.kind != MenuSpecSize.rows) continue;
      for (final item in group.items) {
        if (item is MenuRowSpec && item.marked) selection = true;
      }
    }
    bool imagesOf(_Group group) => group.items.any(
      (Object item) => switch (item) {
        MenuRowSpec(:final hasIcon) => hasIcon,
        MenuLoadingSpec() => true,
        _ => false,
      },
    );
    final m = metrics;
    final width = m.width;
    final check = selection ? m.selectionCheckCenter : null;
    final headerStart = selection ? m.selectionHeaderStart : m.headerStart;

    final elements = <MenuPlaced>[];
    final targets = <MenuTarget>[];
    Rect mirror(Rect r) => rtl
        ? Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom)
        : r;
    void place(
      MenuPlaced Function(int target) element, {
      required Rect rect,
      MenuTargetKind? kind,
      bool keepsOpen = false,
      Object? entry,
    }) {
      final index = elements.length;
      var target = -1;
      if (kind != null) {
        target = targets.length;
        targets.add(
          MenuTarget(
            rect: mirror(rect),
            kind: kind,
            keepsOpen: keepsOpen,
            entry: entry,
            element: index,
          ),
        );
      }
      elements.add(element(target));
    }

    var y = 0.0;
    if (header != null) {
      final rect = Rect.fromLTWH(0, 0, width, m.cardHeaderHeight);
      place(
        (int target) => MenuPlaced(
          kind: MenuPlacedKind.cardHeader,
          rect: mirror(rect),
          entry: header.entry,
          title: header.title,
          imageCenter: header.hasIcon ? m.imageCenter : null,
          titleStart: header.hasIcon ? m.titleStart : m.plainTitleStart,
          titleEnd: m.titleEnd,
          target: target,
        ),
        kind: MenuTargetKind.back,
        entry: header.entry,
        rect: rect,
      );
      y = m.cardHeaderHeight;
    }
    MenuSpecSize? previous;
    for (final group in groups) {
      if (previous == null) {
        if (group.header == null) y += m.topInset;
      } else {
        final gap = switch (previous) {
          MenuSpecSize.rows => m.groupGap,
          MenuSpecSize.small || MenuSpecSize.medium => m.cellGroupGap,
          MenuSpecSize.palette => 0.0,
        };
        if (previous != MenuSpecSize.palette) {
          final line = y + gap / 2;
          elements.add(
            MenuPlaced(
              kind: MenuPlacedKind.separator,
              rect: Rect.fromLTRB(
                m.separatorInset,
                line - 0.5,
                width - m.separatorInset,
                line + 0.5,
              ),
            ),
          );
        }
        y += gap;
      }
      final title = group.header;
      if (title != null) {
        elements.add(
          MenuPlaced(
            kind: MenuPlacedKind.header,
            rect: mirror(Rect.fromLTWH(0, y, width, m.headerHeight)),
            title: title,
            titleStart: headerStart,
            titleEnd: m.titleEnd,
          ),
        );
        y += group.kind == MenuSpecSize.rows
            ? m.rowsAfterHeader
            : m.cellsAfterHeader;
      }
      switch (group.kind) {
        case MenuSpecSize.rows:
          final images = imagesOf(group);
          final image = images
              ? (selection ? m.selectionImageCenter : m.imageCenter)
              : null;
          final titleStart = switch ((selection, images)) {
            (true, true) => m.selectionTitleStart,
            (false, true) => m.titleStart,
            (true, false) => m.selectionOnlyTitleStart,
            (false, false) => m.plainTitleStart,
          };
          for (final item in group.items) {
            switch (item) {
              case MenuRowSpec():
                var lines = 1;
                if (!item.submenu && group.maxLines > 1 && titleLines != null) {
                  lines = math.min(
                    group.maxLines,
                    titleLines(
                      item.title,
                      m.titleEnd - titleStart,
                      group.maxLines,
                    ),
                  );
                }
                final height =
                    (item.subtitle == null
                        ? m.rowHeight
                        : m.subtitleRowHeight) +
                    (lines - 1) * m.extraLineHeight;
                final rect = Rect.fromLTWH(0, y, width, height);
                place(
                  (int target) => MenuPlaced(
                    kind: MenuPlacedKind.row,
                    rect: mirror(rect),
                    entry: item.entry,
                    checkCenter: check,
                    imageCenter: image,
                    titleStart: titleStart,
                    titleEnd: m.titleEnd,
                    maxLines: item.submenu ? 1 : group.maxLines,
                    target: target,
                  ),
                  kind: !item.enabled
                      ? null
                      : item.submenu
                      ? MenuTargetKind.submenu
                      : MenuTargetKind.action,
                  keepsOpen: item.keepsOpen,
                  entry: item.entry,
                  rect: rect,
                );
                y += height;
              case _WidgetSlot(:final spec, :final key):
                final height =
                    spec.height ?? widgetHeight?.call(key) ?? m.rowHeight;
                elements.add(
                  MenuPlaced(
                    kind: MenuPlacedKind.widget,
                    rect: mirror(Rect.fromLTWH(0, y, width, height)),
                    entry: spec.entry,
                    titleStart: m.widgetInset,
                    titleEnd: width - m.widgetInset,
                    key: key,
                  ),
                );
                y += height;
              case MenuLoadingSpec(:final title):
                elements.add(
                  MenuPlaced(
                    kind: MenuPlacedKind.loading,
                    rect: mirror(Rect.fromLTWH(0, y, width, m.rowHeight)),
                    title: title,
                    checkCenter: check,
                    imageCenter: image ?? m.imageCenter,
                    titleStart: images ? titleStart : m.titleStart,
                    titleEnd: m.titleEnd,
                  ),
                );
                y += m.rowHeight;
            }
          }
        case MenuSpecSize.palette:
          final cells = group.items.whereType<MenuRowSpec>().toList();
          final n = math.max(1, cells.length);
          final cell = math.min(
            m.paletteMaxCellWidth,
            m.paletteCellWidth * 5 / n,
          );
          var x = (width - cell * n) / 2;
          for (final entry in cells) {
            final rect = Rect.fromLTWH(x, y, cell, m.paletteCellHeight);
            _placeCell(place, entry, rect, mirror, MenuPlacedKind.palette);
            x += cell;
          }
          y += m.paletteCellHeight;
        case MenuSpecSize.small || MenuSpecSize.medium:
          final small = group.kind == MenuSpecSize.small;
          final perRow = small ? m.smallPerRow : m.mediumPerRow;
          final height = small ? m.smallCellHeight : m.mediumCellHeight;
          final cells = group.items.whereType<MenuRowSpec>().toList();
          final cell = (width - 2 * m.cellInset) / perRow;
          for (var i = 0; i < cells.length; i++) {
            final column = i % perRow;
            if (column == 0 && i > 0) y += height;
            final rect = Rect.fromLTWH(
              m.cellInset + column * cell,
              y,
              cell,
              height,
            );
            _placeCell(
              place,
              cells[i],
              rect,
              mirror,
              small ? MenuPlacedKind.small : MenuPlacedKind.medium,
            );
          }
          if (cells.isNotEmpty) y += height;
      }
      previous = group.kind;
    }
    y += groups.isEmpty && header == null ? m.topInset : m.bottomInset;
    return MenuLayout(
      height: y,
      width: width,
      targets: targets,
      elements: elements,
      loading: loading,
    );
  }

  /// The height of the content.
  final double height;

  /// The width of the content.
  final double width;

  /// The places that react to touches.
  final List<MenuTarget> targets;

  /// What the content draws.
  final List<MenuPlaced> elements;

  /// Whether a deferred group is still loading.
  final bool loading;

  /// The index of the target at [position] in content coordinates, or
  /// null.
  int? targetAt(Offset position) {
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].rect.contains(position)) return i;
    }
    return null;
  }
}

void _placeCell(
  void Function(
    MenuPlaced Function(int target) element, {
    required Rect rect,
    MenuTargetKind? kind,
    bool keepsOpen,
    Object? entry,
  })
  place,
  MenuRowSpec spec,
  Rect rect,
  Rect Function(Rect) mirror,
  MenuPlacedKind kind,
) {
  place(
    (int target) => MenuPlaced(
      kind: kind,
      rect: mirror(rect),
      entry: spec.entry,
      target: target,
    ),
    kind: !spec.enabled
        ? null
        : spec.submenu
        ? MenuTargetKind.submenu
        : MenuTargetKind.action,
    keepsOpen: spec.keepsOpen,
    entry: spec.entry,
    rect: rect,
  );
}

class _Group {
  _Group(this.kind, this.maxLines, {this.header, this.singleSelection = false});

  final MenuSpecSize kind;
  final int maxLines;
  final String? header;
  final bool singleSelection;
  final List<Object> items = [];
}

class _WidgetSlot {
  const _WidgetSlot(this.spec, this.key);

  final MenuWidgetSpec spec;
  final Object key;
}
