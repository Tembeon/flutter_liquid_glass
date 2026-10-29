import 'package:apple_liquid_glass/src/motion/list_highlight.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
/// A row resolves every field against its states (pressed, focused,
/// hovered, disabled) and looks it up in its own style, then its section's,
/// then the theme's, then its defaults, state by state: a property that
/// gives null for a state leaves that state to the next one. The defaults
/// are the iOS 27 system colors the table resolves (list passport, light
/// and dark).
@immutable
class GlassListStyle {
  /// Creates a style.
  const GlassListStyle({
    this.backgroundColor,
    this.overlayColor,
    this.separatorColor,
    this.foregroundColor,
    this.secondaryColor,
    this.iconColor,
    this.disclosureColor,
  });

  /// The fill of a section's card;
  /// [GlassColors.secondarySystemGroupedBackground] by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The fill of a pressed or focused row; [GlassColors.systemGray4], the
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

  /// This style over [other], state by state.
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
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassListStyle? lerp(GlassListStyle? a, GlassListStyle? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
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
      backgroundColor: color(a.backgroundColor, b.backgroundColor),
      overlayColor: color(a.overlayColor, b.overlayColor),
      separatorColor: color(a.separatorColor, b.separatorColor),
      foregroundColor: color(a.foregroundColor, b.foregroundColor),
      secondaryColor: color(a.secondaryColor, b.secondaryColor),
      iconColor: color(a.iconColor, b.iconColor),
      disclosureColor: color(a.disclosureColor, b.disclosureColor),
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
      other.disclosureColor == disclosureColor;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    overlayColor,
    separatorColor,
    foregroundColor,
    secondaryColor,
    iconColor,
    disclosureColor,
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
/// while they are in view, each in a layer of its own.
class GlassSliverListSection extends StatelessWidget {
  /// Creates a section of [itemCount] rows built by [itemBuilder].
  const GlassSliverListSection({
    required this.itemBuilder,
    required this.itemCount,
    this.header,
    this.footer,
    this.style,
    super.key,
  });

  /// Builds the row at an index, usually a [GlassListRow].
  final IndexedWidgetBuilder itemBuilder;

  /// The number of rows.
  final int itemCount;

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
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _Metrics.sectionInset),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: _SectionLabel.header(look: look, label: header),
          ),
          SliverList.builder(
            itemCount: itemCount,
            itemBuilder: (context, i) {
              final first = i == 0;
              final last = i == itemCount - 1;
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: first ? radius : Radius.zero,
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
            },
          ),
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
/// separator to 56 points; a [trailing] control and the [accessory] end 20
/// points from the card's edge, centered in the row as UIKit centers an
/// accessory view. A single-line row is 53 points tall, and each line of
/// text is as tall as UIKit makes a label: its line height rounded up to
/// the device pixel (list passport). Instead of a title, a [child] can fill
/// the text area with any content.
///
/// With [onPressed] the row is a button: it fills with its overlay color
/// while a finger is down on it, with UIKit's timing (inside a scroll view
/// after its 0.15 s touch delay, gone at once when a scroll takes the
/// touch, faded out over 0.5 s after a tap), and while it has the keyboard
/// focus; Space and Enter press it. A disabled row ignores touches and
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

  /// The symbol before the text, usually an [Icon]; 22 points in the icon
  /// color unless it sets its own.
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

  /// What accessibility reads for the info button; `More info` when null.
  final String? accessorySemanticLabel;

  @override
  State<GlassListRow> createState() => _GlassListRowState();
}

class _GlassListRowState extends State<GlassListRow> {
  late final _RowBody _body = _RowBody();
  late final List<Interaction> _interactions = [
    PressInteraction(
      role: InteractionRole.content,
      onTap: () => widget.onPressed?.call(),
    ).simultaneously(_HighlightInput(_body)),
  ];
  WidgetStatesController? _ownStates;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownStates ??= WidgetStatesController());

  bool get _active => widget.onPressed != null && widget.enabled;

  @override
  void initState() {
    super.initState();
    _writeStates();
    _states.addListener(_statesChanged);
    MotionClock.instance.addDriver(_body);
  }

  @override
  void didUpdateWidget(GlassListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final states = oldWidget.statesController ?? _ownStates;
    if (!identical(states, _states)) {
      states?.removeListener(_statesChanged);
      _states.addListener(_statesChanged);
    }
    _writeStates();
    if (!_active) _body.cancel();
  }

  @override
  void dispose() {
    _states.removeListener(_statesChanged);
    _ownStates?.dispose();
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    super.dispose();
  }

  // The region writes disabled too, and ends a press when disabled;
  // writing both first makes its writes no-ops, so it never asks this
  // ancestor to rebuild while it builds.
  void _writeStates() {
    _states.update(WidgetState.disabled, !_active);
    if (!_active) _states.update(WidgetState.pressed, false);
  }

  void _statesChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final place = _RowPlace.maybeOf(context);
    final look = (widget.style ?? const GlassListStyle()).merge(
      place?.look ?? _sectionLook(context, null),
    );
    final states = _states.value;
    Color color(WidgetStateProperty<Color?>? property) =>
        _resolve(property, states, context);
    final secondary = color(look.secondaryColor);
    final icon = color(look.iconColor);
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
    final textStart =
        _Metrics.contentInset +
        (leading == null ? 0 : _Metrics.leadingWidth + _Metrics.leadingGap);
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: _Metrics.rowPadding),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (leading != null) ...[
              SizedBox(
                width: _Metrics.leadingWidth,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: _Metrics.leadingIconSize,
                      color: icon,
                    ),
                    child: leading,
                  ),
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
            ?trailing,
            if (trailing != null && mark) const SizedBox(width: _Metrics.gap),
            if (check) _Glyph(painter: _CheckPainter(icon)),
            if (info)
              Semantics(
                container: true,
                button: true,
                label: widget.accessorySemanticLabel ?? 'More info',
                onTap: widget.onAccessoryPressed,
                child: ExcludeSemantics(
                  child: MotionPressable(
                    onPressed: widget.onAccessoryPressed,
                    child: _Glyph(painter: _InfoPainter(icon)),
                  ),
                ),
              ),
            if (info && chevron) const SizedBox(width: _Metrics.gap),
            if (chevron) _Chevron(color: color(look.disclosureColor)),
          ],
        ),
      ),
    );
    final separated = place != null && !place.last;
    final surface = _RowSurface(
      strength: _body.strength,
      focused: states.contains(WidgetState.focused),
      fill: color(look.overlayColor),
      separator: separated ? color(look.separatorColor) : null,
      separatorStart: textStart,
      direction: Directionality.of(context),
      child: row,
    );
    return Semantics(
      container: true,
      button: widget.onPressed != null,
      selected: check ? true : null,
      child: widget.onPressed == null
          ? surface
          : InputRegion(
              interactions: _interactions,
              enabled: _active,
              statesController: _states,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              child: surface,
            ),
    );
  }
}

GlassListStyle _sectionLook(BuildContext context, GlassListStyle? style) {
  final theme = GlassTheme.of(context);
  final label = theme.colorScheme?.label ?? GlassColors.label;
  return (style ?? const GlassListStyle())
      .merge(theme.listStyle)
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
            theme.primaryColor ?? GlassColors.systemBlue,
          ),
          disclosureColor: const WidgetStatePropertyAll(
            GlassColors.tertiaryLabel,
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

/// The highlight of a row, stepped on the motion clock.
final class _RowBody implements MotionDriver {
  final ListRowHighlight _highlight = ListRowHighlight();
  final strength = ValueNotifier<double>(0);

  double get _now => MotionClock.instance.now;

  // A fade can end between frames; one more step publishes its end.
  @override
  bool get isActive =>
      !_highlight.isSettled(_now) || strength.value != _highlight.opacity(_now);

  @override
  double? get wakeTime => _highlight.wakeTime(_now);

  @override
  void step(double time) => strength.value = _highlight.opacity(time);

  // The region delivers a touch inside a scroll view once the scroll's
  // delay has passed, or at its release if that comes sooner, so the
  // highlight shows when the touch arrives.
  void press(double contact, double time) {
    _highlight.press(contact, time, delay: 0);
    MotionClock.instance.wake(this);
  }

  void release(double time) {
    _highlight.release(time);
    MotionClock.instance.wake(this);
  }

  void cancel() {
    _highlight.cancel();
    strength.value = 0;
  }

  void dispose() => strength.dispose();
}

/// Feeds one touch of a row to its highlight; the press decides what the
/// touch does, this only follows it.
final class _HighlightInput extends Interaction {
  _HighlightInput(this._body) : super(role: InteractionRole.content);

  final _RowBody _body;
  int? _pointer;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null:
        _pointer = input.pointer;
        _body.press(input.contactTime, input.time);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _body.release(input.time);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _body.cancel();
      default:
    }
    return InteractionUpdate.none;
  }
}

/// Paints a row's highlight under it and its separator over it, following
/// the highlight's strength without building.
class _RowSurface extends SingleChildRenderObjectWidget {
  const _RowSurface({
    required this.strength,
    required this.focused,
    required this.fill,
    required this.separator,
    required this.separatorStart,
    required this.direction,
    required super.child,
  });

  final ValueListenable<double> strength;
  final bool focused;
  final Color fill;
  final Color? separator;
  final double separatorStart;
  final TextDirection direction;

  @override
  _RenderRowSurface createRenderObject(BuildContext context) =>
      _RenderRowSurface(
        strength: strength,
        focused: focused,
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
    renderObject.focused = focused;
    renderObject.fill = fill;
    renderObject.separator = separator;
    renderObject.separatorStart = separatorStart;
    renderObject.direction = direction;
  }
}

class _RenderRowSurface extends RenderProxyBox {
  _RenderRowSurface({
    required this._strength,
    required this._focused,
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

  bool _focused;
  bool get focused => _focused;
  set focused(bool value) {
    if (value == _focused) return;
    _focused = value;
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

  double _separatorStart;
  double get separatorStart => _separatorStart;
  set separatorStart(double value) {
    if (value == _separatorStart) return;
    _separatorStart = value;
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
  }

  @override
  void detach() {
    _strength.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shown = _focused ? 1.0 : _strength.value;
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
    final left = ltr ? _separatorStart : end;
    final right = size.width - (ltr ? end : _separatorStart);
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
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(22), painter: painter);
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
