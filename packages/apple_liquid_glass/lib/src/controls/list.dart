import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// The standard accessory of a [GlassListRow].
///
/// UIKit: `UITableViewCell.AccessoryType`. SwiftUI: a `NavigationLink`'s
/// chevron. Flutter: `CupertinoListTile.trailing` with
/// `CupertinoListTileChevron`.
///
/// The checkmark and the info button are drawn in the row's icon color.
/// UIKit draws the SF symbol `checkmark` at 17 point semibold, medium
/// scale, and the info button as `info.circle` (read from UIKit, notes
/// private); these are painted by eye in a 22 point box, not read.
enum GlassListAccessory {
  /// The disclosure chevron of a row that pushes a screen.
  disclosureIndicator,

  /// A checkmark: the row is the chosen one of a list of options.
  checkmark,

  /// An info button; a tap on it calls [GlassListRow.onAccessoryPressed]
  /// instead of the row's [GlassListRow.onPressed].
  detailButton,

  /// An info button followed by the disclosure chevron.
  detailDisclosureButton,
}

/// The look of an inset grouped list, like Flutter's `ButtonStyle`.
///
/// Each color property but [focusColor] and [hoverColor] resolves against
/// the row's states (pressed, focused, hovered, disabled) and falls
/// through, state by state, from the row's
/// style to its section's to the theme's to the defaults: a null for a
/// state leaves that state to the next one. The defaults
/// are the iOS 27 system colors the table resolves (list passport, light
/// and dark).
@immutable
class GlassListStyle extends GlassStyle<GlassListStyle> {
  /// Creates a style.
  const GlassListStyle({
    this.backgroundColor,
    this.overlayColor,
    this.separatorColor,
    this.foregroundColor,
    this.secondaryColor,
    this.iconColor,
    this.disclosureColor,
    this.focusColor,
    this.hoverColor,
  });

  /// The theme's [GlassListStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassListStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassListStyle>(context);

  /// The fill of a section's card;
  /// [GlassColors.secondarySystemGroupedBackground] by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The fill of a pressed row; [GlassColors.systemGray4], the
  /// grouped cell's highlighted color, by default.
  final WidgetStateProperty<Color?>? overlayColor;

  /// The separators between rows; [GlassListSection.separator] by
  /// default.
  final WidgetStateProperty<Color?>? separatorColor;

  /// A row's title; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// A row's subtitle and detail, and a section's header and footer;
  /// [GlassColors.secondaryLabel] by default.
  final WidgetStateProperty<Color?>? secondaryColor;

  /// A row's leading symbol, checkmark and info button; the theme's
  /// primary color, else [GlassColors.systemBlue], by default.
  final WidgetStateProperty<Color?>? iconColor;

  /// The disclosure chevron; [GlassColors.tertiaryLabel] by default.
  final WidgetStateProperty<Color?>? disclosureColor;

  /// The ring inside a row, and around an info button, focused from the
  /// keyboard; null derives it from systemBlue as Flutter's Cupertino
  /// controls do, and a transparent color draws none.
  final Color? focusColor;

  /// What a mouse over a row or an info button fills under it; null for
  /// [overlayColor] at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// This style over [other], state by state.
  @override
  GlassListStyle merge(GlassListStyle? other) {
    if (other == null) return this;
    return GlassListStyle(
      backgroundColor: fallThrough(backgroundColor, other.backgroundColor),
      overlayColor: fallThrough(overlayColor, other.overlayColor),
      separatorColor: fallThrough(separatorColor, other.separatorColor),
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      secondaryColor: fallThrough(secondaryColor, other.secondaryColor),
      iconColor: fallThrough(iconColor, other.iconColor),
      disclosureColor: fallThrough(disclosureColor, other.disclosureColor),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassListStyle lerp(GlassListStyle other, double t) {
    if (identical(this, other)) return this;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassListStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      overlayColor: color(overlayColor, other.overlayColor),
      separatorColor: color(separatorColor, other.separatorColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      secondaryColor: color(secondaryColor, other.secondaryColor),
      iconColor: color(iconColor, other.iconColor),
      disclosureColor: color(disclosureColor, other.disclosureColor),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassListStyle &&
      other.backgroundColor == backgroundColor &&
      other.overlayColor == overlayColor &&
      other.separatorColor == separatorColor &&
      other.foregroundColor == foregroundColor &&
      other.secondaryColor == secondaryColor &&
      other.iconColor == iconColor &&
      other.disclosureColor == disclosureColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    overlayColor,
    separatorColor,
    foregroundColor,
    secondaryColor,
    iconColor,
    disclosureColor,
    focusColor,
    hoverColor,
  );
}

/// The page behind an inset grouped list.
///
/// UIKit: `systemGroupedBackground`. SwiftUI: a `List` with
/// `.insetGrouped`. Flutter: `CupertinoColors.systemGroupedBackground`.
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
  Widget build(BuildContext context) => ColoredBox(
    color: GlassDynamicColor.resolve(color, context),
    child: child,
  );
}

/// One section of an inset grouped list, as iOS 27 settings screens draw
/// it: an optional [header], the [children] on one rounded card inset from
/// the screen's edges, and an optional [footer].
///
/// UIKit: a `UITableView` section, `.insetGrouped`. SwiftUI: `Section` in a
/// `List`. Flutter: `CupertinoListSection.insetGrouped`.
///
/// [GlassListRow]s on the card draw the separators between them; other
/// children are laid out on the card as they are. Sections stack in a
/// column; the space between two of them comes from their own headers and
/// footers (35 points between a card without a footer and one without a
/// header). The card is 20 points in from the edges with 26 point corners,
/// and paints in a layer of its own, so a scroll moving it composites that
/// layer instead of repainting its rows (list passport).
class GlassListSection extends StatelessWidget {
  /// Creates a section.
  const GlassListSection({
    required this.children,
    this.header,
    this.footer,
    this.style,
    super.key,
  });

  /// The rows on the card.
  final List<Widget> children;

  /// The label above the card, usually a [Text]: 17 points semibold in the
  /// secondary color unless it sets its own style.
  final Widget? header;

  /// The label below the card, usually a [Text]: 13 points in the
  /// secondary color unless it sets its own style.
  final Widget? footer;

  /// The look of the section and its rows, over the theme's.
  final GlassListStyle? style;

  /// The separators of an iOS 27 table: 0x3C3C43 at 12 percent in light
  /// and 0x545458 at 50 percent in dark, lighter than the catalog's
  /// separator (list passport, simulator).
  static const separator = GlassDynamicColor.withBrightness(
    color: Color(0x1F3C3C43),
    darkColor: Color(0x80545458),
  );

  @override
  Widget build(BuildContext context) {
    final look = _sectionLook(context, style);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _Metrics.sectionInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel.header(look: look, label: header),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(_Metrics.cornerRadius),
              ),
              child: ColoredBox(
                color: _resolve(look.backgroundColor, const {}, context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++)
                      _RowPlace(
                        last: i == children.length - 1,
                        look: look,
                        child: children[i],
                      ),
                  ],
                ),
              ),
            ),
            _SectionLabel.footer(look: look, label: footer),
          ],
        ),
      ),
    );
  }
}

/// A [GlassListSection] as a sliver that builds its rows lazily, for a
/// long list in a [CustomScrollView].
///
/// UIKit: a `UITableView` section of many cells. SwiftUI: `Section` in a
/// `List`. Flutter: `SliverList.builder`.
///
/// It looks like [GlassListSection]: [header], the [itemCount] rows that
/// [itemBuilder] builds on one rounded card, [footer]. Rows are built only
/// while they are in view, each in a layer of its own. With [ids], rows
/// insert, delete and reorder on the app's `withSpring` ([RawGlassList]).
class GlassSliverListSection extends StatelessWidget {
  /// Creates a section of [itemCount] rows built by [itemBuilder].
  const GlassSliverListSection({
    required this.itemBuilder,
    required this.itemCount,
    this.ids,
    this.header,
    this.footer,
    this.style,
    super.key,
  }) : assert(ids == null || ids.length == itemCount, 'One id per row.');

  /// Builds the row at an index, usually a [GlassListRow].
  final IndexedWidgetBuilder itemBuilder;

  /// The number of rows.
  final int itemCount;

  /// What identifies each row across changes of the rows, or null to
  /// identify them by position, which animates nothing.
  final List<Object>? ids;

  /// The label above the card; see [GlassListSection.header].
  final Widget? header;

  /// The label below the card; see [GlassListSection.footer].
  final Widget? footer;

  /// The look of the section and its rows, over the theme's.
  final GlassListStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = _sectionLook(context, style);
    const radius = Radius.circular(_Metrics.cornerRadius);
    final card = _resolve(look.backgroundColor, const {}, context);
    Widget piece(BuildContext context, int i) {
      final last = i == itemCount - 1;
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: i == 0 ? radius : Radius.zero,
            bottom: last ? radius : Radius.zero,
          ),
          child: ColoredBox(
            color: card,
            child: _RowPlace(
              last: last,
              look: look,
              child: itemBuilder(context, i),
            ),
          ),
        ),
      );
    }

    final indexOf = {for (final (i, id) in (ids ?? const []).indexed) id: i};
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _Metrics.sectionInset),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _SectionLabel.header(look: look, label: header),
          ),
          if (ids case final ids?)
            RawGlassList(
              ids: ids,
              itemBuilder: (context, id) => piece(context, indexOf[id]!),
            )
          else
            SliverList.builder(itemCount: itemCount, itemBuilder: piece),
          SliverToBoxAdapter(
            child: _SectionLabel.footer(look: look, label: footer),
          ),
        ],
      ),
    );
  }
}

/// A row of an inset grouped list.
///
/// UIKit: a `UITableViewCell` with a `UIListContentConfiguration` (cell,
/// subtitle cell, value cell). SwiftUI: a row of a `List`. Flutter:
/// `CupertinoListTile`.
///
/// The [title] reads 17 points in the label color with an optional 15
/// point [subtitle] below it; a [detail] sits at the trailing edge in the
/// secondary color, taking at most half the text area; a [leading] symbol
/// is centered 28 points from the card's edge and moves the text and the
/// separator to 56 points; a leading image wider than the symbol's 24
/// point slot widens it from the card's 16 point inset and moves the text
/// and separator along (not measured). A [trailing] control and the
/// [accessory] end 20 points from the card's edge, centered in the row as
/// UIKit centers an accessory view. A single-line row is 53 points tall,
/// and each line of text is as tall as UIKit makes a label: its line
/// height rounded up to the device pixel (list passport). Instead of a
/// title, a [child] can fill the text area with any content.
///
/// With [onPressed] the row is a button: it fills with its overlay color
/// while a finger is down on it, with UIKit's timing (inside a scroll view
/// after its 0.15 s touch delay, gone at once when a scroll takes the
/// touch, faded out over 0.5 s after a tap); Space and Enter press it.
/// Focused from the keyboard it draws Flutter's Cupertino focus ring
/// inside its edge, where the card clips, and a mouse over it fills it
/// with half its overlay color (the rule of the glass controls; an
/// approximation, not measured); its info button does the same around its
/// circle. A disabled row ignores touches and
/// keeps its look: the disabled cell is not measured. Inside a section the
/// row draws the separator below itself, except on the section's last row.
/// Right-to-left text mirrors the row and the chevron.
class GlassListRow extends StatefulWidget {
  /// Creates a row.
  const GlassListRow({
    this.title,
    this.subtitle,
    this.detail,
    this.leading,
    this.trailing,
    this.accessory,
    this.onAccessoryPressed,
    this.child,
    this.onPressed,
    this.enabled = true,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.accessorySemanticLabel,
    super.key,
  }) : assert(
         title != null || child != null,
         'A row needs a title or a child.',
       );

  /// The primary text, usually a [Text].
  final Widget? title;

  /// The secondary line below [title].
  final Widget? subtitle;

  /// The value at the trailing edge, in the secondary color.
  final Widget? detail;

  /// The symbol or image before the text, usually an [Icon]; 22 points in
  /// the icon color unless it sets its own. It keeps its own size.
  final Widget? leading;

  /// A control at the trailing edge, such as a switch.
  final Widget? trailing;

  /// The standard accessory at the trailing edge, after [trailing]; null
  /// shows none.
  final GlassListAccessory? accessory;

  /// Called when the info button of a [GlassListAccessory.detailButton] or
  /// [GlassListAccessory.detailDisclosureButton] is pressed (UIKit
  /// `accessoryButtonTappedForRowWith`).
  final VoidCallback? onAccessoryPressed;

  /// Content that fills the text area instead of [title] and [subtitle].
  final Widget? child;

  /// Called when the row is pressed; null makes the row inert.
  final VoidCallback? onPressed;

  /// Whether the row takes presses.
  final bool enabled;

  /// The look, over the section's and the theme's.
  final GlassListStyle? style;

  /// Where the row writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The row's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the row takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the info button; the localized
  /// [GlassLocalizations.moreInfoLabel] when null.
  final String? accessorySemanticLabel;

  @override
  State<GlassListRow> createState() => _GlassListRowState();
}

class _GlassListRowState extends State<GlassListRow>
    with ControlStates<GlassListRow> {
  final _highlight = ListRowHighlight();
  late final _strength = _highlight.select((h) => h.opacity);
  final _textStart = ValueNotifier<double>(_Metrics.contentInset);
  late final List<Interaction> _interactions = [
    PressInteraction(
      role: InteractionRole.content,
      onTap: (t) => widget.onPressed?.call(),
    ).simultaneously(
      FollowInteraction(_highlight, role: InteractionRole.content),
    ),
  ];
  late final List<Interaction> _accessoryInteractions = [
    PressInteraction(onTap: (t) => widget.onAccessoryPressed?.call()),
  ];
  final _accessoryStates = WidgetStatesController();

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  bool get _active => widget.onPressed != null && widget.enabled;

  @override
  void didUpdateWidget(GlassListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active) _highlight.clear(_highlight.clock.now);
  }

  @override
  void dispose() {
    _textStart.dispose();
    _accessoryStates.dispose();
    super.dispose();
  }

  @override
  void writeStates() {
    widgetStates.update(WidgetState.disabled, !_active);
    if (!_active) widgetStates.update(WidgetState.pressed, false);
  }

  @override
  Widget build(BuildContext context) {
    final place = _RowPlace.maybeOf(context);
    final look = (widget.style ?? const GlassListStyle()).merge(
      place?.look ?? _sectionLook(context, null),
    );
    final states = widgetStates.value;
    Color color(WidgetStateProperty<Color?>? property) =>
        _resolve(property, states, context);
    final secondary = color(look.secondaryColor);
    final icon = color(look.iconColor);
    final fill = color(look.overlayColor);
    final hover =
        look.hoverColor ??
        fill.withValues(alpha: fill.a * GlassHighlights.hoverGain);
    final titleStyle = resolveGlassText(
      _Metrics.body.copyWith(color: color(look.foregroundColor)),
      context,
    );
    final detailStyle = resolveGlassText(
      _Metrics.body.copyWith(color: secondary),
      context,
    );
    final subtitleStyle = resolveGlassText(
      _Metrics.subtitle.copyWith(color: secondary),
      context,
    );
    final leading = widget.leading;
    final subtitle = widget.subtitle;
    final detail = widget.detail;
    final trailing = widget.trailing;
    final kind = widget.accessory;
    final chevron =
        kind == GlassListAccessory.disclosureIndicator ||
        kind == GlassListAccessory.detailDisclosureButton;
    final info =
        kind == GlassListAccessory.detailButton ||
        kind == GlassListAccessory.detailDisclosureButton;
    final check = kind == GlassListAccessory.checkmark;
    final mark = chevron || info || check;
    final accessory = trailing != null || mark;
    // A row that highlights has more than the card's color under its control.
    final card = place != null && widget.onPressed == null
        ? _resolve(place.look.backgroundColor, const {}, context)
        : null;
    if (leading == null) _textStart.value = _Metrics.contentInset;
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: _Metrics.rowPadding),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (leading != null) ...[
              _LeadingSlot(
                textStart: _textStart,
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: _Metrics.leadingIconSize,
                    color: icon,
                  ),
                  child: leading,
                ),
              ),
              const SizedBox(width: _Metrics.leadingGap),
            ],
            Expanded(
              child: DefaultTextStyle(
                style: titleStyle,
                child:
                    widget.child ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.title case final title?)
                          _LabelHeight(child: title),
                        if (subtitle != null)
                          DefaultTextStyle(
                            style: subtitleStyle,
                            child: _LabelHeight(child: subtitle),
                          ),
                      ],
                    ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: _Metrics.gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth / 2,
                ),
                child: DefaultTextStyle(
                  style: detailStyle,
                  textAlign: TextAlign.end,
                  child: _LabelHeight(child: detail),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _Metrics.minRowHeight),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: _Metrics.contentInset,
          end: accessory ? _Metrics.accessoryInset : _Metrics.contentInset,
        ),
        child: Row(
          children: [
            Expanded(child: text),
            if (accessory) const SizedBox(width: _Metrics.gap),
            if (trailing != null)
              GlassSolidBackdrop(color: card, child: trailing),
            if (trailing != null && mark) const SizedBox(width: _Metrics.gap),
            if (check) _Glyph(painter: _CheckPainter(icon)),
            if (info) const SizedBox.square(dimension: _Metrics.glyphSize),
            if (info && chevron) const SizedBox(width: _Metrics.gap),
            if (chevron) _Chevron(color: color(look.disclosureColor)),
          ],
        ),
      ),
    );
    final separated = place != null && !place.last;
    final surface = _RowSurface(
      strength: _strength,
      fill: fill,
      separator: separated ? color(look.separatorColor) : null,
      separatorStart: _textStart,
      direction: Directionality.of(context),
      child: row,
    );
    final infoButton = info
        ? _InfoButton(
            interactions: _accessoryInteractions,
            enabled: widget.enabled && widget.onAccessoryPressed != null,
            states: _accessoryStates,
            label:
                widget.accessorySemanticLabel ??
                GlassLocalizations.of(context).moreInfoLabel,
            end:
                _Metrics.accessoryInset +
                (chevron ? _Metrics.chevronSize.width + _Metrics.gap : 0),
            child: GlassHighlightPaint.of(
              context,
              states: _accessoryStates,
              focusColor: look.focusColor,
              hoverColor: hover,
              shape: const GlassShape.oval(),
              child: _Glyph(painter: _InfoPainter(icon)),
            ),
          )
        : null;
    final described = Semantics(
      button: widget.onPressed != null,
      selected: check ? true : null,
      child: surface,
    );
    final rowNode = Semantics(
      container: true,
      child: widget.onPressed == null
          ? described
          : InputRegion(
              interactions: _interactions,
              enabled: _active,
              statesController: widgetStates,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              child: GlassHighlightPaint.of(
                context,
                states: widgetStates,
                focusColor: look.focusColor,
                hoverColor: hover,
                shape: const GlassShape.roundedRect(0),
                inside: true,
                child: described,
              ),
            ),
    );
    if (infoButton == null) return rowNode;
    // The info button is a target beside the row's, not inside it: a
    // region inside another one would hand its keys to the outer one.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Stack(children: [rowNode, infoButton]),
    );
  }
}

/// The info button of a row, laid over the row where the row leaves its
/// slot: a 22 point glyph that takes a finger in 44 by 44 points.
class _InfoButton extends StatelessWidget {
  const _InfoButton({
    required this.interactions,
    required this.enabled,
    required this.states,
    required this.label,
    required this.end,
    required this.child,
  });

  final List<Interaction> interactions;
  final bool enabled;
  final WidgetStatesController states;
  final String label;
  final double end;
  final Widget child;

  static const double _target = 44;

  @override
  Widget build(BuildContext context) => PositionedDirectional(
    top: 0,
    bottom: 0,
    end: end - (_target - _Metrics.glyphSize) / 2,
    width: _target,
    child: Center(
      child: InputRegion(
        interactions: interactions,
        enabled: enabled,
        statesController: states,
        semantics: SemanticsProperties(label: label),
        minimumHitSize: const Size.square(_target),
        child: Semantics(button: true, child: child),
      ),
    ),
  );
}

GlassListStyle _sectionLook(BuildContext context, GlassListStyle? style) {
  final label = GlassTheme.labelColorOf(context);
  return (style ?? const GlassListStyle())
      .merge(GlassListStyle.maybeOf(context))
      .merge(
        GlassListStyle(
          backgroundColor: const WidgetStatePropertyAll(
            GlassColors.secondarySystemGroupedBackground,
          ),
          overlayColor: const WidgetStatePropertyAll(GlassColors.systemGray4),
          separatorColor: const WidgetStatePropertyAll(
            GlassListSection.separator,
          ),
          foregroundColor: WidgetStatePropertyAll(label),
          secondaryColor: const WidgetStatePropertyAll(
            GlassColors.secondaryLabel,
          ),
          iconColor: WidgetStatePropertyAll(
            GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
          ),
          disclosureColor: WidgetStatePropertyAll(
            GlassTheme.tertiaryLabelColorOf(context),
          ),
        ),
      );
}

Color _resolve(
  WidgetStateProperty<Color?>? property,
  Set<WidgetState> states,
  BuildContext context,
) => GlassDynamicColor.resolve(property!.resolve(states)!, context);

/// The metrics of an inset grouped list on a 402 point screen (list
/// passport, simulator view tree and screenshots).
abstract final class _Metrics {
  /// How far a section's card stands in from the screen's edges.
  static const double sectionInset = 20;

  /// The corner radius of a section's card, fitted to its outline (0.3
  /// pt).
  static const double cornerRadius = 26;

  /// The leading inset of a row's text, of the separators and of the
  /// header and footer labels, and the trailing inset of a row without an
  /// accessory.
  static const double contentInset = 16;

  /// The trailing inset of a row's accessory or control.
  static const double accessoryInset = 20;

  /// The gap between a row's title and its detail, and between the text
  /// and the accessory.
  static const double gap = 8;

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

  /// The box of a checkmark or an info button.
  static const double glyphSize = 22;

  /// A row's title and detail.
  static const body = TextStyle(fontSize: 17, fontWeight: FontWeight.w400);

  /// The line under a row's title.
  static const subtitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);

  /// A section's header.
  static const header = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  /// A section's footer.
  static const footer = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
}

class _RowPlace extends InheritedWidget {
  const _RowPlace({
    required this.last,
    required this.look,
    required super.child,
  });

  final bool last;
  final GlassListStyle look;

  static _RowPlace? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowPlace>();

  @override
  bool updateShouldNotify(_RowPlace oldWidget) =>
      last != oldWidget.last || look != oldWidget.look;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel.header({required this.look, required this.label})
    : _header = true;

  const _SectionLabel.footer({required this.look, required this.label})
    : _header = false;

  final GlassListStyle look;
  final Widget? label;
  final bool _header;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (label == null) {
      return SizedBox(
        height: _header ? _Metrics.noHeaderTop : _Metrics.noFooterBottom,
      );
    }
    final style = resolveGlassText(
      (_header ? _Metrics.header : _Metrics.footer).copyWith(
        color: _resolve(look.secondaryColor, const {}, context),
      ),
      context,
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        _Metrics.contentInset,
        _header ? _Metrics.headerTop : _Metrics.footerTop,
        _Metrics.contentInset,
        _header ? _Metrics.headerBottom : _Metrics.footerBottom,
      ),
      child: Semantics(
        header: _header,
        child: DefaultTextStyle.merge(
          style: style,
          child: _LabelHeight(child: label),
        ),
      ),
    );
  }
}

/// Paints a row's highlight under it and its separator over it, following
/// the highlight's strength without building.
class _RowSurface extends SingleChildRenderObjectWidget {
  const _RowSurface({
    required this.strength,
    required this.fill,
    required this.separator,
    required this.separatorStart,
    required this.direction,
    required super.child,
  });

  final ValueListenable<double> strength;
  final Color fill;
  final Color? separator;
  final ValueListenable<double> separatorStart;
  final TextDirection direction;

  @override
  _RenderRowSurface createRenderObject(BuildContext context) =>
      _RenderRowSurface(
        strength: strength,
        fill: fill,
        separator: separator,
        separatorStart: separatorStart,
        direction: direction,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRowSurface renderObject,
  ) {
    renderObject.strength = strength;
    renderObject.fill = fill;
    renderObject.separator = separator;
    renderObject.separatorStart = separatorStart;
    renderObject.direction = direction;
  }
}

class _RenderRowSurface extends RenderProxyBox {
  _RenderRowSurface({
    required this._strength,
    required this._fill,
    required this._separator,
    required this._separatorStart,
    required this._direction,
  });

  ValueListenable<double> _strength;
  ValueListenable<double> get strength => _strength;
  set strength(ValueListenable<double> value) {
    if (identical(value, _strength)) return;
    if (attached) _strength.removeListener(markNeedsPaint);
    _strength = value;
    if (attached) _strength.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color _fill;
  Color get fill => _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color? _separator;
  Color? get separator => _separator;
  set separator(Color? value) {
    if (value == _separator) return;
    _separator = value;
    markNeedsPaint();
  }

  ValueListenable<double> _separatorStart;
  ValueListenable<double> get separatorStart => _separatorStart;
  set separatorStart(ValueListenable<double> value) {
    if (identical(value, _separatorStart)) return;
    if (attached) _separatorStart.removeListener(markNeedsPaint);
    _separatorStart = value;
    if (attached) _separatorStart.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  TextDirection _direction;
  TextDirection get direction => _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _strength.addListener(markNeedsPaint);
    _separatorStart.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _strength.removeListener(markNeedsPaint);
    _separatorStart.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shown = _strength.value;
    if (shown > 0) {
      final paint = Paint();
      paint.color = _fill.withValues(alpha: _fill.a * shown.clamp(0.0, 1.0));
      context.canvas.drawRect(offset & size, paint);
    }
    super.paint(context, offset);
    final separator = _separator;
    if (separator == null) return;
    const end = _Metrics.contentInset;
    final ltr = _direction == TextDirection.ltr;
    final start = _separatorStart.value;
    final left = ltr ? start : end;
    final right = size.width - (ltr ? end : start);
    final line = Paint();
    line.color = separator;
    context.canvas.drawRect(
      Rect.fromLTRB(
        left,
        size.height - _Metrics.separatorThickness,
        right,
        size.height,
      ).shift(offset),
      line,
    );
  }
}

/// A row's leading slot: [_Metrics.leadingWidth] wide with the symbol
/// centered, or as wide as a wider image, which it never squeezes. It
/// writes where the text starts, which the separator follows.
class _LeadingSlot extends SingleChildRenderObjectWidget {
  const _LeadingSlot({required this.textStart, required super.child});

  final ValueNotifier<double> textStart;

  @override
  _RenderLeadingSlot createRenderObject(BuildContext context) =>
      _RenderLeadingSlot(textStart);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLeadingSlot renderObject,
  ) {
    renderObject.textStart = textStart;
  }
}

class _RenderLeadingSlot extends RenderShiftedBox {
  _RenderLeadingSlot(this._textStart) : super(null);

  ValueNotifier<double> _textStart;
  ValueNotifier<double> get textStart => _textStart;
  set textStart(ValueNotifier<double> value) {
    if (identical(value, _textStart)) return;
    _textStart = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(const Size(_Metrics.leadingWidth, 0));
    } else {
      child.layout(constraints.loosen(), parentUsesSize: true);
      size = constraints.constrain(
        Size(
          math.max(_Metrics.leadingWidth, child.size.width),
          child.size.height,
        ),
      );
      (child.parentData! as BoxParentData).offset = Offset(
        (size.width - child.size.width) / 2,
        (size.height - child.size.height) / 2,
      );
    }
    _textStart.value = _Metrics.contentInset + size.width + _Metrics.leadingGap;
  }
}

/// Sizes a label as tall as a `UILabel` with its text: each line's height
/// rounded up to the device pixel, where the text engine rounds it to a
/// whole point (20.33 points for 17 point SF Pro at 3x).
class _LabelHeight extends SingleChildRenderObjectWidget {
  const _LabelHeight({required super.child});

  static double _pixelRatio(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ??
      View.maybeOf(context)?.devicePixelRatio ??
      1;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLabelHeight(_pixelRatio(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLabelHeight).pixelRatio = _pixelRatio(context);
  }
}

class _RenderLabelHeight extends RenderProxyBox {
  _RenderLabelHeight(this._pixelRatio);

  // The engine reports line heights in single precision: a line of
  // exactly 47 pixels can come back a millionth of a pixel over.
  static const double _pixelTolerance = 1e-3;

  double _pixelRatio;
  double get pixelRatio => _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsLayout();
  }

  double? _line;

  double _height(double height) {
    final line = _line;
    if (line == null) return height;
    final rounded = line.roundToDouble();
    if (rounded <= 0) return height;
    final lines = (height / rounded).round();
    if (lines < 1 || (lines * rounded - height).abs() > 0.01) return height;
    return (lines * line * _pixelRatio - _pixelTolerance).ceilToDouble() /
        _pixelRatio;
  }

  static RenderParagraph? _paragraph(RenderBox child) {
    RenderObject? box = child;
    while (box is RenderProxyBox) {
      box = box.child;
    }
    return box is RenderParagraph && box.size == child.size ? box : null;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final size = child.getDryLayout(constraints);
    return constraints.constrain(Size(size.width, _height(size.height)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      _line = null;
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    _line = _paragraph(
      child,
    )?.getFullHeightForCaret(const TextPosition(offset: 0));
    size = constraints.constrain(
      Size(child.size.width, _height(child.size.height)),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: _Metrics.chevronSize,
    painter: _ChevronPainter(
      color: color,
      mirrored: Directionality.of(context) == TextDirection.rtl,
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => mirrored ? size.width - v : v;
    final path = Path();
    path.moveTo(x(3.7), 1.8);
    path.lineTo(x(8.7), 7);
    path.lineTo(x(3.7), 12.2);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      color != oldDelegate.color || mirrored != oldDelegate.mirrored;
}

/// The box of a checkmark or an info button: 22 points, the size of a body
/// symbol (by eye, not measured).
class _Glyph extends StatelessWidget {
  const _Glyph({required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(_Metrics.glyphSize),
    painter: painter,
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.52);
    path.lineTo(size.width * 0.42, size.height * 0.74);
    path.lineTo(size.width * 0.82, size.height * 0.26);
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.2;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

class _InfoPainter extends CustomPainter {
  const _InfoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 0.75;
    final ring = Paint();
    ring.color = color;
    ring.style = PaintingStyle.stroke;
    ring.strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ring);
    final dot = Paint();
    dot.color = color;
    canvas.drawCircle(center.translate(0, -radius * 0.45), 1.3, dot);
    final stem = Paint();
    stem.color = color;
    stem.strokeWidth = 2;
    stem.strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(0, -radius * 0.12),
      center.translate(0, radius * 0.5),
      stem,
    );
  }

  @override
  bool shouldRepaint(_InfoPainter oldDelegate) => color != oldDelegate.color;
}
