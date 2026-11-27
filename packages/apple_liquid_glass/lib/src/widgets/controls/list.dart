import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/list_accessory.dart';
import 'package:apple_liquid_glass/src/widgets/controls/list_style.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/src/widgets/controls/swipe_actions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_anchor.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_entries.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/sheet.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart'
    show MotionSelect, MotionSelection, RenderListening;
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/controls/list_marks.dart';
part 'package:apple_liquid_glass/src/widgets/controls/list_render.dart';
part 'package:apple_liquid_glass/src/widgets/controls/list_row.dart';

/// The page behind an inset grouped list.
///
/// UIKit: `systemGroupedBackground`. SwiftUI: a `List` with
/// `.insetGrouped`. Flutter: `CupertinoColors.systemGroupedBackground`.
///
/// In a [GlassSheet] it is clear while the sheet floats, so the sheet's
/// glass shows between the sections, and fades in with the sheet's opaque
/// background as the sheet docks, as UIKit's grouped table in a sheet does
/// (iPhone 16 Pro, iOS 27).
class GlassListBackground extends StatelessWidget {
  /// Creates the background.
  const GlassListBackground({
    this.color = GlassColors.systemGroupedBackground,
    this.child,
    super.key,
  });

  /// The color of the page.
  final Color color;

  /// The list.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = GlassDynamicColor.resolve(this.color, context);
    final fill = GlassSheet.fillOf(context);
    if (fill == null) return ColoredBox(color: color, child: child);
    final page = MotionTransition(
      opacity: fill,
      child: ColoredBox(color: color),
    );
    final list = child;
    if (list == null) return page;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: page),
        list,
      ],
    );
  }
}

/// Puts the list rows below it into editing, as UIKit's `isEditing` on a
/// table and SwiftUI's `editMode` do.
///
/// UIKit: `UITableView.isEditing`, `allowsMultipleSelectionDuringEditing`.
/// SwiftUI: `EditMode`, `List(selection:)`. Flutter: none.
///
/// While [editing], a [GlassListRow] shows a control at its leading side,
/// 19.17 points from the card's edge, and its text moves to 60 points from
/// it in every [GlassListLayout]: a red minus for a row with an
/// `onDelete`, whose tap reveals a trailing Delete action as a swipe does,
/// a green plus for one with an `onInsert`, and, with [onSelectionChanged],
/// a ring for each row with a `value`, filled with a check while the row is
/// in [selection], whose tap on the row selects or deselects it. Rows hide
/// their accessories and trailing controls, and take no tap of their own.
/// A row with none of these keeps its layout, as a UIKit row that does not
/// indent while editing. One scope above a list's sections holds one
/// selection across them.
///
/// The change into and out of editing runs on UIKit's table spring,
/// critically damped at 0.3: the text moves, the edit control slides in
/// from the start and fades in, and the reorder control fades in; the
/// accessories hide and show at once.
///
/// Fidelity. The places, colors and spring are UIKit 27.2's (list API
/// passport); the minus of a row showing its Delete action does not turn.
/// Rows reorder by hand in a [GlassSliverListSection] with
/// `onReorderItem`, whose rows then show UIKit's reorder control. NEAR:
/// UIKit also fades its accessories out and in.
class GlassListEditing extends InheritedWidget {
  /// Puts the rows below into editing while [editing].
  const GlassListEditing({
    required this.editing,
    required super.child,
    this.selection = const {},
    this.onSelectionChanged,
    super.key,
  });

  /// Whether the rows are in editing.
  final bool editing;

  /// The values of the selected rows, while [onSelectionChanged] selects.
  final Set<Object> selection;

  /// Called with the new selection as a tap selects or deselects a row;
  /// null for editing that does not select.
  final ValueChanged<Set<Object>>? onSelectionChanged;

  /// Whether editing selects rows.
  bool get selects => onSelectionChanged != null;

  /// The editing around [context], or null.
  static GlassListEditing? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassListEditing>();

  /// Selects the row of [value], or deselects it when it is selected.
  void toggle(Object value) => onSelectionChanged?.call(
    selection.contains(value)
        ? ({...selection}..remove(value))
        : {...selection, value},
  );

  @override
  bool updateShouldNotify(GlassListEditing oldWidget) =>
      editing != oldWidget.editing ||
      !setEquals(selection, oldWidget.selection) ||
      onSelectionChanged != oldWidget.onSelectionChanged;
}

/// Context menus over the list rows below it by their values, as SwiftUI's
/// context menus over a list's selection.
///
/// UIKit: `UICollectionViewDelegate`
/// `contextMenuConfigurationForItemsAt:point:`. SwiftUI:
/// `contextMenu(forSelectionType:menu:primaryAction:)`. Flutter: none.
///
/// A [GlassListRow] with a value below it, held, opens a [GlassContextMenu]
/// of the entries [menuBuilder] gives for the values it acts on: the whole
/// selection of a [GlassListEditing] that selects when the held row is in
/// it, the row's own value otherwise. No entries, no menu. [onPrimaryAction]
/// runs with the row's value on a tap of a row without an `onPressed` of
/// its own, out of editing, as SwiftUI's primary action on iOS.
///
/// Fidelity. Which values a menu acts on follows SwiftUI's documentation;
/// the hold, the menu and its preview of the held row are
/// [GlassContextMenu]'s. Not captured: how UIKit previews several selected
/// rows held together.
class GlassListContextMenu extends InheritedWidget {
  /// Gives the rows below context menus of [menuBuilder]'s entries.
  const GlassListContextMenu({
    required this.menuBuilder,
    required super.child,
    this.onPrimaryAction,
    super.key,
  });

  /// The entries of the menu over the values of the rows a held row acts
  /// on.
  final List<GlassMenuEntry> Function(BuildContext context, Set<Object> values)
  menuBuilder;

  /// Called with a tapped row's value, out of editing, for a row without
  /// an `onPressed` of its own; null for rows a tap leaves alone.
  final ValueChanged<Set<Object>>? onPrimaryAction;

  /// The menus around [context], or null.
  static GlassListContextMenu? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassListContextMenu>();

  @override
  bool updateShouldNotify(GlassListContextMenu oldWidget) =>
      menuBuilder != oldWidget.menuBuilder ||
      onPrimaryAction != oldWidget.onPrimaryAction;
}

// A card's margin from the list's edges, past the safe area's sides as
// UIKit's inset grouped table keeps its cards inside the safe area: on an
// iPhone in landscape, or beside a tab sidebar.
EdgeInsets _sectionMargin(BuildContext context, GlassListLayout layout) {
  final safe = MediaQuery.paddingOf(context);
  final margin = layout == GlassListLayout.insetGrouped
      ? GlassListSection.margin
      : 0.0;
  return EdgeInsets.only(left: margin + safe.left, right: margin + safe.right);
}

/// How a list section lays out its rows, as UIKit's table styles do.
///
/// UIKit: `UITableView.Style`. SwiftUI: `listStyle`. Flutter:
/// `CupertinoListSection` and `CupertinoListSection.insetGrouped`.
enum GlassListLayout {
  /// Rows on a card [GlassListSection.margin] in from the list's sides,
  /// with 26 point corners, their text [GlassListSection.contentInset]
  /// into it (UIKit `.insetGrouped`).
  insetGrouped,

  /// Rows on a card as wide as the list, square, with a separator across
  /// its whole width at its top and bottom and the text 16 points in;
  /// headers, footers and the space between sections are the inset
  /// grouped ones (UIKit `.grouped`).
  grouped,

  /// Rows as wide as the list on the page's own color, systemBackground,
  /// the text 16 points in: a header stands 22 points below the rows above
  /// it and 28 tall, a footer 28 tall, and a section without either runs
  /// straight on from the one above; the last row keeps its separator
  /// unless a footer follows (UIKit `.plain`).
  plain,
}

// The metrics a layout changes (list passport, table dumps of the three
// styles on the iOS 27.2 simulator, 402 wide).
extension on GlassListLayout {
  bool get _plain => this == GlassListLayout.plain;

  double get contentInset =>
      this == GlassListLayout.insetGrouped ? GlassListSection.contentInset : 16;

  double get headerTop => _plain ? 22 + 4 : _Metrics.headerTop;

  double get headerBottom => _plain ? 28 - 4 - 20.33 : _Metrics.headerBottom;

  double get noHeaderTop => _plain ? 0 : _Metrics.noHeaderTop;

  double get footerTop => _plain ? 6 : _Metrics.footerTop;

  double get footerBottom => _plain ? 28 - 6 - 15.67 : _Metrics.footerBottom;

  double get noFooterBottom => _plain ? 0 : _Metrics.noFooterBottom;
}

// A grouped card's separators across its whole width at its top and
// bottom.
class _EdgeLines extends CustomPainter {
  _EdgeLines(this.color, {required this.top, required this.bottom});

  final Color color;
  final bool top;
  final bool bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint();
    line.color = color;
    const thickness = _Metrics.separatorThickness;
    if (top) canvas.drawRect(Rect.fromLTWH(0, 0, size.width, thickness), line);
    if (bottom) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - thickness, size.width, thickness),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgeLines oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.top != top ||
      oldDelegate.bottom != bottom;
}

// The card of a section, or a piece of it: its fill, its corners where the
// layout rounds them and a grouped card's edge lines.
Widget _card(
  BuildContext context, {
  required GlassListLayout layout,
  required GlassListStyle look,
  required bool separators,
  required BorderRadius radius,
  required bool top,
  required bool bottom,
  required Widget child,
  bool lifted = false,
}) {
  final color = StateColors(context, const {});
  final fill = color(look.backgroundColor);
  Widget card = ColoredBox(
    color: lifted ? fill.withValues(alpha: fill.a * _Metrics.liftedFill) : fill,
    child: child,
  );
  if (layout == GlassListLayout.grouped && separators && (top || bottom)) {
    card = CustomPaint(
      foregroundPainter: _EdgeLines(
        color(look.separatorColor),
        top: top,
        bottom: bottom,
      ),
      child: card,
    );
  }
  if (layout != GlassListLayout.insetGrouped) return card;
  return ClipRRect(borderRadius: radius, child: card);
}

/// One section of an inset grouped list, as iOS 27 settings screens draw
/// it: a header, rows on one rounded card, and a footer.
///
/// UIKit: a `UITableView` section, `.insetGrouped`. SwiftUI: `Section` in a
/// `List`. Flutter: `CupertinoListSection.insetGrouped`.
///
/// Pass the rows as [children], usually [GlassListRow]s, and an optional
/// [header] and [footer], usually [Text]. Sections stack in a scroll view,
/// such as a `ListView` over a [GlassListBackground]; for a long list
/// whose rows build lazily, use [GlassSliverListSection]. [style] changes
/// the look of the section and its rows.
///
/// ```dart
/// GlassListSection(
///   header: const Text('Network'),
///   footer: const Text('Shown to devices nearby.'),
///   children: [
///     GlassListRow(
///       leading: const Icon(CupertinoIcons.wifi),
///       title: const Text('Wi-Fi'),
///       detail: const Text('Home'),
///       accessory: GlassListAccessory.disclosureIndicator,
///       onPressed: () => debugPrint('open Wi-Fi'),
///     ),
///   ],
/// )
/// ```
///
/// It draws no glass on any renderer: the card is a plain fill that
/// looks the same under the liquid, fake and flat renderers and with no
/// `GlassScope` above.
///
/// [GlassListRow]s on the card draw the separators between them; other
/// children are laid out on the card as they are. The space between two
/// sections comes from their own headers and footers (35 points between a
/// card without a footer and one without a header). The card is [margin]
/// in from the safe area's sides with 26 point corners, its rows' text
/// [contentInset] inside it, and it paints in a layer of its own, so a
/// scroll moving it composites that layer instead of repainting its rows.
///
/// [layout] lays the section out as UIKit's grouped and plain tables do
/// instead: a plain list stands on [GlassColors.systemBackground], which a
/// [GlassListBackground] of that color gives it.
///
/// Fidelity. The insets, corners and spacing are measured on iOS 27: the
/// card's [margin] and the [contentInset] on 27.2, where 27.0 read 20 and
/// 16 to the same text x 36; the grouped and plain layouts on 27.2. NEAR: a
/// grouped or plain card stops at the safe area's sides, where UIKit's
/// rows run to the screen's edges with their content inside the safe area;
/// a plain header scrolls with its rows, where UIKit's stays pinned at the
/// list's top while its section scrolls under it; its label stands 0.67
/// points shorter than UIKit's 21.
class GlassListSection extends StatelessWidget {
  /// Creates a section.
  const GlassListSection({
    required this.children,
    this.header,
    this.footer,
    this.showsSeparators = true,
    this.layout = GlassListLayout.insetGrouped,
    this.style,
    super.key,
  });

  /// How far a section's card stands in from the list's edges, past the
  /// safe area's sides, in points: what to line up a page's own content
  /// with the cards' edges by.
  static const double margin = 16;

  /// How far a row's text, the separators and the header and footer labels
  /// stand in from the card's leading edge, in points; and a row without an
  /// accessory ends its text as far in from the trailing edge.
  static const double contentInset = 20;

  /// The rows on the card.
  final List<Widget> children;

  /// The label above the card, usually a [Text]: 17 points semibold in the
  /// secondary color unless it sets its own style.
  final Widget? header;

  /// The label below the card, usually a [Text]: 13 points in the
  /// secondary color unless it sets its own style.
  final Widget? footer;

  /// Whether the rows draw the separators between them (UIKit
  /// `showsSeparators`, SwiftUI `listRowSeparator`); a row can say
  /// otherwise for itself ([GlassListRow.showsSeparator]).
  final bool showsSeparators;

  /// How the section lays out its card and rows.
  final GlassListLayout layout;

  /// The look of the section and its rows, over the theme's.
  final GlassListStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = _sectionLook(context, style, layout);
    final section = RepaintBoundary(
      child: Padding(
        padding: _sectionMargin(context, layout),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel.header(look: look, layout: layout, label: header),
            _card(
              context,
              layout: layout,
              look: look,
              separators: showsSeparators,
              radius: const BorderRadius.all(
                Radius.circular(_Metrics.cornerRadius),
              ),
              top: true,
              bottom: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++)
                    _RowPlace(
                      last: i == children.length - 1,
                      separators: showsSeparators,
                      layout: layout,
                      endSeparator: _endSeparator(layout, footer),
                      look: look,
                      child: children[i],
                    ),
                ],
              ),
            ),
            _SectionLabel.footer(look: look, layout: layout, label: footer),
          ],
        ),
      ),
    );
    return SwipeGroup(
      child: SwipeRevealColor(
        color: layout == GlassListLayout.plain
            ? GlassColors.systemBackground
            : GlassColors.systemGroupedBackground,
        child: section,
      ),
    );
  }
}

bool _endSeparator(GlassListLayout layout, Widget? footer) =>
    layout == GlassListLayout.plain && footer == null;

/// A [GlassListSection] as a sliver that builds its rows lazily, for a
/// long list in a [CustomScrollView].
///
/// UIKit: a `UITableView` section of many cells. SwiftUI: `Section` in a
/// `List`. Flutter: `SliverList.builder`.
///
/// It looks like [GlassListSection]: [header], the [itemCount] rows that
/// [itemBuilder] builds on one rounded card, [footer]. Rows are built only
/// while they are in view, each in a layer of its own. With [ids], a
/// change of the rows inside a `withSpring` animates as UIKit's table
/// animates `deleteRows`, `insertRows` and `moveRow` ([rowAnimation],
/// [RawGlassList]).
///
/// With [onReorderItem], rows reorder by hand in editing: below a
/// [GlassListEditing] that is editing, each [GlassListRow] shows UIKit's
/// reorder control at its trailing edge, whose touch lifts the row and
/// moves it with the finger. A lifted row stands above the others with a
/// shadow (black at 0.2, a blur of 16, 2 down) and its fill at 0.8, takes
/// the corners of the place it stands in and draws no separator; its
/// shadow falls as it lands, as UIKit's does. [onReorderItem] hears the
/// row's index and the index it takes, as Flutter's `onReorderItem`.
///
/// Fidelity. The lift is UIKit 27.2's (list API passport); UIKit blurs what
/// lies under the lifted row's fill, which this fill does not.
class GlassSliverListSection extends StatelessWidget {
  /// Creates a section of [itemCount] rows built by [itemBuilder].
  const GlassSliverListSection({
    required this.itemBuilder,
    required this.itemCount,
    this.ids,
    this.rowAnimation = GlassListRowAnimation.automatic,
    this.onReorderItem,
    this.header,
    this.footer,
    this.showsSeparators = true,
    this.layout = GlassListLayout.insetGrouped,
    this.style,
    super.key,
  }) : assert(ids == null || ids.length == itemCount, 'One id per row.'),
       assert(
         onReorderItem == null || ids != null,
         'Rows reorder by their ids.',
       );

  /// Builds the row at an index, usually a [GlassListRow].
  final IndexedWidgetBuilder itemBuilder;

  /// The number of rows.
  final int itemCount;

  /// What identifies each row across changes of the rows, or null to
  /// identify them by position, which animates nothing.
  final List<Object>? ids;

  /// How a deleted row leaves and an inserted one arrives when [ids]
  /// change inside a `withSpring`, as UIKit's `UITableView.RowAnimation`;
  /// every row moves on UIKit's table spring (critically damped, 0.3)
  /// whatever spring the change came with.
  final GlassListRowAnimation rowAnimation;

  /// Called when a row dragged by its reorder control is dropped somewhere
  /// else, with the index it had and the index it takes once moved; null
  /// for rows that do not reorder. Needs [ids].
  final void Function(int fromIndex, int toIndex)? onReorderItem;

  /// The label above the card; see [GlassListSection.header].
  final Widget? header;

  /// The label below the card; see [GlassListSection.footer].
  final Widget? footer;

  /// See [GlassListSection.showsSeparators].
  final bool showsSeparators;

  /// See [GlassListSection.layout].
  final GlassListLayout layout;

  /// The look of the section and its rows, over the theme's.
  final GlassListStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = _sectionLook(context, style, layout);
    Widget piece(BuildContext context, int i) => _SliverRow(
      index: i,
      count: itemCount,
      layout: layout,
      look: look,
      separators: showsSeparators,
      endSeparator: _endSeparator(layout, footer),
      row: itemBuilder(context, i),
    );

    final indexOf = {for (final (i, id) in (ids ?? const []).indexed) id: i};
    final section = SliverPadding(
      padding: _sectionMargin(context, layout),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _SectionLabel.header(
              look: look,
              layout: layout,
              label: header,
            ),
          ),
          if (ids case final ids?)
            RawGlassList(
              ids: ids,
              planner: ListRowPlanner(animation: rowAnimation),
              onReorderItem: onReorderItem,
              itemBuilder: (context, id) => piece(context, indexOf[id]!),
            )
          else
            SliverList.builder(itemCount: itemCount, itemBuilder: piece),
          SliverToBoxAdapter(
            child: _SectionLabel.footer(
              look: look,
              layout: layout,
              label: footer,
            ),
          ),
        ],
      ),
    );
    return SwipeGroup(
      child: SwipeRevealColor(
        color: layout == GlassListLayout.plain
            ? GlassColors.systemBackground
            : GlassColors.systemGroupedBackground,
        child: section,
      ),
    );
  }
}

/// A row of a [GlassSliverListSection] on its piece of the card: the
/// corners and separator of the place it stands in, a dragged row's new
/// place counted, and a lifted row's look.
class _SliverRow extends StatelessWidget {
  const _SliverRow({
    required this.index,
    required this.count,
    required this.layout,
    required this.look,
    required this.separators,
    required this.endSeparator,
    required this.row,
  });

  final int index;
  final int count;
  final GlassListLayout layout;
  final GlassListStyle look;
  final bool separators;
  final bool endSeparator;
  final Widget row;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(_Metrics.cornerRadius);
    final at = RawGlassList.positionOf(context) ?? index;
    final last = at == count - 1;
    final lift = RawGlassList.liftOf(context);
    final corners = BorderRadius.vertical(
      top: at == 0 ? radius : Radius.zero,
      bottom: last ? radius : Radius.zero,
    );
    return RepaintBoundary(
      child: _LiftShadow(
        lift: lift,
        radius: layout == GlassListLayout.insetGrouped
            ? corners
            : BorderRadius.zero,
        child: _card(
          context,
          layout: layout,
          look: look,
          separators: separators,
          radius: corners,
          top: at == 0,
          bottom: last,
          lifted: lift != null,
          child: _RowPlace(
            last: last,
            separators: separators && lift == null,
            layout: layout,
            endSeparator: endSeparator,
            look: look,
            child: row,
          ),
        ),
      ),
    );
  }
}

GlassListStyle _sectionLook(
  BuildContext context,
  GlassListStyle? style, [
  GlassListLayout layout = GlassListLayout.insetGrouped,
]) {
  final label = GlassTheme.labelColorOf(context);
  final tertiary = GlassTheme.tertiaryLabelColorOf(context);
  return (style ?? const GlassListStyle())
      .merge(GlassListStyle.maybeOf(context))
      .merge(
        GlassListStyle(
          backgroundColor: WidgetStatePropertyAll(
            layout == GlassListLayout.plain
                ? GlassColors.systemBackground
                : GlassColors.secondarySystemGroupedBackground,
          ),
          overlayColor: const WidgetStatePropertyAll(GlassColors.systemGray4),
          separatorColor: const WidgetStatePropertyAll(
            GlassColors.separator,
          ),
          foregroundColor: WidgetStateMapper<Color?>({
            WidgetState.disabled: tertiary,
            WidgetState.any: label,
          }),
          secondaryColor: const WidgetStateMapper<Color?>({
            WidgetState.disabled: GlassColors.quaternaryLabel,
            WidgetState.any: GlassColors.secondaryLabel,
          }),
          iconColor: WidgetStateMapper<Color?>({
            WidgetState.disabled: tertiary,
            WidgetState.any:
                GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
          }),
          disclosureColor: WidgetStatePropertyAll(tertiary),
        ),
      );
}

/// The metrics of an inset grouped list on a 402 point screen (list
/// passport, simulator view tree and screenshots).
abstract final class _Metrics {
  /// The corner radius of a section's card, fitted to its outline (0.3
  /// pt).
  static const double cornerRadius = 26;

  /// The trailing inset of a row's control and of the disclosure chevron.
  static const double accessoryInset = 20;

  /// The trailing inset of a checkmark.
  static const double checkmarkInset = 22.5;

  /// The trailing inset of an info button without a chevron after it.
  static const double infoInset = 19.17;

  /// The gap between a row's title and its detail, and between the text
  /// and the accessory.
  static const double gap = 8;

  /// The space between a row's text and the detail under it: 4 at the
  /// third accessibility text size, where a value row is 131 tall and its
  /// detail starts 67.5 down, under a title line 48 tall and 15.5 down.
  static const double stackedDetailGap = 4;

  /// The height of a single-line row.
  static const double minRowHeight = 53;

  /// The space above and below a row's text.
  static const double rowPadding = 15.5;

  /// The width of the leading slot, which centers a symbol 28 points from
  /// the card's edge.
  static const double leadingWidth = 24;

  /// The gap after the leading slot.
  static const double leadingGap = 16;

  /// The point size of a row's leading symbol.
  static const double leadingIconSize = 22;

  /// The thickness of a separator.
  static const double separatorThickness = 1;

  /// Where a row's text starts in editing, past its edit control, in every
  /// layout (list API passport, the three table styles).
  static const double editingInset = 60;

  /// The opacity of a lifted row's fill: UIKit's lifted fill reads
  /// (252,252,253) over systemGroupedBackground and white over a white row
  /// (list API passport, reorder drag).
  static const double liftedFill = 0.8;

  /// A lifted row's shadow: black at 0.2, a blur of 16, 2 down (UIKit's
  /// lift view, list API passport).
  static const double liftShadowOpacity = 0.2;
  static const double liftShadowBlur = 16;
  static const double liftShadowOffset = 2;

  /// UIKit's reorder control: 27 wide, the row's height, its end 20 from the
  /// card's edge in every layout, with a value ending 8 before it; its glyph
  /// three lines 1.33 thick, 4.67 apart.
  static const double gripWidth = 27;
  static const double gripEndInset = 20;
  static const double gripGap = 8;

  /// Where a row's edit control starts from the card's leading edge.
  static const double editMarkStart = 19.17;

  /// The box of a row's edit control, and the circle drawn in it.
  static const double editMarkBox = 25.67;
  static const double editMarkCircle = 22;

  /// The least start of a separator from the card's leading edge: a grouped
  /// or plain row's text starts 16 in and its separator 20.
  static const double separatorStart = 20;

  /// The space above a section header's label.
  static const double headerTop = 11.67;

  /// The space between a section header's label and its card.
  static const double headerBottom = 6;

  /// The space above a card without a header.
  static const double noHeaderTop = 17.67;

  /// The space between a card and its footer's label.
  static const double footerTop = 7.67;

  /// The space below a section footer's label.
  static const double footerBottom = 6.67;

  /// The space below a card without a footer.
  static const double noFooterBottom = 17.33;

  /// The size of the disclosure chevron's glyph box.
  static const Size chevronSize = Size(10.33, 14);

  /// The box of a checkmark.
  static const Size checkmarkSize = Size(19, 17.33);

  /// The diameter of an info button's circle.
  static const double infoSize = 25.67;

  /// A row's title and detail.
  static const body = TextStyle(fontSize: 17, fontWeight: FontWeight.w400);

  /// The line under a row's title.
  static const subtitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);

  /// A section's header.
  static const header = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  /// A section's footer.
  static const footer = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
}
