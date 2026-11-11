part of 'list.dart';

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
