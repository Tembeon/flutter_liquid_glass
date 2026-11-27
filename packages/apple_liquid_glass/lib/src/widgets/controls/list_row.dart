part of 'list.dart';

/// A row of an inset grouped list: a title with an optional subtitle,
/// symbol, value, control and accessory.
///
/// UIKit: a `UITableViewCell` with a `UIListContentConfiguration` (cell,
/// subtitle cell, value cell). SwiftUI: a row of a `List`. Flutter:
/// `CupertinoListTile`.
///
/// Pass a [title], or a [child] that fills the text area instead. Add a
/// [subtitle], a [leading] symbol, a [detail] value, a [trailing] control
/// such as a `GlassSwitch`, and an [accessory] such as the disclosure
/// chevron. With [onPressed] the row is a button; [enabled] false turns it
/// off. Put rows in a [GlassListSection], which draws the card and the
/// separators.
///
/// ```dart
/// GlassListRow(
///   leading: const Icon(CupertinoIcons.bell),
///   title: const Text('Notifications'),
///   subtitle: const Text('Sounds, badges'),
///   accessory: GlassListAccessory.disclosureIndicator,
///   onPressed: () => debugPrint('open notifications'),
/// )
/// ```
///
/// It draws no glass on any renderer: a row looks the same under the
/// liquid, fake and flat renderers and with no `GlassScope` above.
///
/// The [title] reads 17 points in the label color with an optional 15 point
/// [subtitle] below it; a [detail] in the secondary color sits at the trailing
/// edge when the text and the detail fit side by side on one line each, and 4
/// points under the text, from its start, when they do not and at the
/// accessibility text sizes, as UIKit's value cell stacks them; a [leading]
/// symbol takes a 24 point slot where the text would start and moves the text
/// and the separator 40 points further in; a leading image wider than the
/// slot widens it and moves the text and separator along. A [trailing]
/// control and the chevron end 20 points from the card's edge, a 19 x 17.33
/// checkmark 22.5 and a 25.67 info button 19.17, centered in the row as UIKit
/// centers an accessory view.
/// A single-line row is 53 points tall, and each line of
/// text is as tall as UIKit makes a label: its line height rounded up to
/// the device pixel. The text styles of [GlassListStyle] and its
/// [GlassListStyle.minRowHeight] change these sizes for an app's own type.
///
/// A pressable row fills with its overlay color while a finger is down on
/// it, with UIKit's timing: inside a scroll view after its 0.15 s touch
/// delay, gone at once when a scroll takes the touch, faded out over 0.5 s
/// after a tap. Space and Enter press it. [onLongPress] is called when a
/// finger holds the row still for 0.5 s; the fill then goes at once and the
/// release presses nothing. A row with [onLongPress] alone does not fill. A
/// [selected] row keeps that fill
/// whatever touches do, pressable or not, and a screen reader reads it as
/// selected; when it stops being selected the fill fades out as after a tap.
/// Its text keeps the label color. Focused from the keyboard it
/// draws Flutter's Cupertino focus ring inside its edge, where the card
/// clips, and a mouse over it fills it with half its overlay color; its
/// info button does the same around its circle. A row that is not
/// [enabled] ignores touches and dims its text and leading symbol as
/// UIKit's content configuration does: the title and the symbol take
/// [GlassColors.tertiaryLabel], the subtitle and detail
/// [GlassColors.quaternaryLabel]; its control, accessory and fill keep
/// their look. A row without [onPressed] is not disabled and keeps its
/// colors. Inside a section the row draws the
/// separator below itself, except on the section's last row (a plain
/// section's last row draws one unless a footer follows). Right-to-left
/// text mirrors the row and the chevron.
///
/// Below a [GlassListEditing] that is editing, a row with [onDelete],
/// [onInsert] or, where the editing selects, a [value] shows its edit
/// control and moves its text to 60 points; see [GlassListEditing]. In a
/// [GlassSliverListSection] whose rows reorder it also shows the reorder
/// control at its trailing edge ([showsReorderControl]).
///
/// Fidelity. The sizes, insets and press timing are measured on iOS 27, the
/// selected fill on the iOS 27.2 simulator (inset grouped: a full-bleed
/// rectangle in the overlay color, light, dark and Increase Contrast), the
/// disabled colors in light mode on iOS 27.2 (dark takes the same label
/// colors), the stacked detail at the third accessibility text size on iOS 27.2
/// (its leading edge not read). The width at which a detail leaves the side of
/// the text is UIKit's documented rule
/// (`prefersSideBySideTextAndSecondaryText`), not measured. Not measured
/// either: the place of a leading image wider than 24 points, the disabled
/// accessories, and the focus ring and hover response, which are approximations
/// of the platform.
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
    this.onLongPress,
    this.enabled = true,
    this.selected = false,
    this.showsSeparator,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.accessorySemanticLabel,
    this.onDelete,
    this.onInsert,
    this.value,
    this.showsReorderControl = true,
    this.expanded = false,
    this.indentationLevel = 0,
    super.key,
  }) : assert(indentationLevel >= 0, 'A level is 0 or more.'),
       assert(
         title != null || child != null,
         'A row needs a title or a child.',
       );

  /// The primary text, usually a [Text].
  final Widget? title;

  /// The secondary line below [title].
  final Widget? subtitle;

  /// The value in the secondary color: at the trailing edge, or under the
  /// text when the two do not fit side by side.
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
  /// `accessoryButtonTappedForRowWith`), or the button of a
  /// [GlassListAccessory.outlineDisclosure].
  final VoidCallback? onAccessoryPressed;

  /// Whether an outline row shows its children: its
  /// [GlassListAccessory.outlineDisclosure] chevron points down, turning
  /// there and back on the critically damped 0.25 s spring of UIKit's
  /// collection view lists. The child rows themselves come and go as the
  /// list's rows do, on its table spring.
  final bool expanded;

  /// How deep in an outline the row stands: each level moves its content,
  /// separator and edit control 10 points in, and an indented row's
  /// content inset drops from 20 to 16 points, as UIKit's
  /// `indentationLevel` does (iOS 27.2 simulator).
  final int indentationLevel;

  /// Content that fills the text area instead of [title] and [subtitle].
  final Widget? child;

  /// Called when the row is pressed; null, with [onLongPress] null too,
  /// makes the row inert.
  final VoidCallback? onPressed;

  /// Called when a finger holds the row for 0.5 s, as a
  /// `UILongPressGestureRecognizer` on a cell sees it.
  final VoidCallback? onLongPress;

  /// Whether the row takes presses.
  final bool enabled;

  /// Whether the row is the selected one, such as the page a sidebar shows
  /// now (UIKit `isSelected` in a table that keeps its selection): it keeps
  /// its overlay fill until this turns false.
  final bool selected;

  /// Whether a separator stands below the row, or null for its section's
  /// choice ([GlassListSection.showsSeparators]); the last row of a section
  /// has none, but in a plain section without a footer.
  final bool? showsSeparator;

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

  /// Deletes the row in editing ([GlassListEditing]): a red minus stands at
  /// its leading side, and a tap on it reveals a trailing Delete action, as
  /// a swipe does, whose tap calls this, as UIKit's delete editing style.
  final VoidCallback? onDelete;

  /// Inserts after the row in editing: a green plus at its leading side
  /// calls this, as UIKit's insert editing style.
  final VoidCallback? onInsert;

  /// What identifies the row in a [GlassListEditing.selection]: in editing
  /// that selects, a row with a value shows a ring at its leading side,
  /// filled with a check while selected, and a tap on the row selects or
  /// deselects it.
  final Object? value;

  /// Whether the row shows UIKit's reorder control at its trailing edge in
  /// editing, inside a `GlassSliverListSection` whose rows reorder
  /// (`onReorderItem`): three lines 27 points wide whose touch lifts the
  /// row and moves it with the finger. Its content then ends 55 points from
  /// the card's edge, 8 before the control.
  final bool showsReorderControl;

  @override
  State<GlassListRow> createState() => _GlassListRowState();
}

// The control a row in editing shows at its leading side.
enum _EditKind { delete, insert, select }

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _GlassListRowState extends State<GlassListRow> {
  final _confirm = _Ping();

  // The width of the leading slot, which moves the separator's start.
  final _leadingWidth = ValueNotifier<double>(_Metrics.leadingWidth);

  // The change into and out of editing, made the first time the row goes
  // into editing, and the controls it shows while it runs, kept until the
  // row rests out of editing.
  ListEditMotion? _editMotion;
  MotionSelection<double>? _editProgress;
  MotionSelection<bool>? _editGone;
  bool? _editing;
  _EditKind? _shownEdit;
  bool _shownGrip = false;

  ListEditMotion get _edit {
    if (_editMotion case final motion?) return motion;
    final motion = _editMotion = ListEditMotion(
      clock: MotionClockScope.of(context),
    );
    _editProgress = motion.select(
      (m) => m.progress.valueAt(m.now).clamp(0.0, 1.0),
    );
    _editGone = motion.select((m) => m.restsOut)..addListener(_editEnded);
    return motion;
  }

  // The turn of an outline row's chevron, made the first time the row
  // shows one, following [GlassListRow.expanded] from then on.
  OutlineDisclosureMotion? _outline;
  MotionSelection<double>? _outlineTurnValue;

  ValueListenable<double> get _outlineTurn {
    final motion = _outline ??= OutlineDisclosureMotion(
      expanded: widget.expanded,
      clock: MotionClockScope.of(context),
    );
    motion.expand(motion.clock.now, expanded: widget.expanded);
    return _outlineTurnValue ??= motion.select(
      (m) => m.turn.valueAt(m.now),
    );
  }

  // How far into editing the row is: 0 for a row never edited.
  ValueListenable<double> get _progress =>
      _editProgress ?? const AlwaysStoppedAnimation<double>(0);

  @override
  void dispose() {
    _editGone?.removeListener(_editEnded);
    _confirm.dispose();
    _leadingWidth.dispose();
    super.dispose();
  }

  void _editEnded() {
    if (!mounted || !(_editGone?.value ?? false) || (_editing ?? false)) {
      return;
    }
    if (_shownEdit == null && !_shownGrip) return;
    setState(() {
      _shownEdit = null;
      _shownGrip = false;
    });
  }

  // Into or out of editing: at once at the first build, on the table
  // spring after.
  void _syncEdit({required _EditKind? edit, required bool grip}) {
    final editing = edit != null || grip;
    if (edit != null) _shownEdit = edit;
    if (grip) _shownGrip = true;
    if (_editing == editing) return;
    final first = _editing == null;
    _editing = editing;
    if (first && !editing) return;
    final motion = _edit;
    motion.edit(motion.clock.now, editing: editing, animated: !first);
  }

  void _measureLeading(double t, Size size) => _leadingWidth.value = size.width;

  @override
  Widget build(BuildContext context) {
    final place = _RowPlace.maybeOf(context);
    final look = (widget.style ?? const GlassListStyle()).merge(
      place?.look ?? _sectionLook(context, null),
    );
    final kind = widget.accessory;
    final chevron =
        kind == GlassListAccessory.disclosureIndicator ||
        kind == GlassListAccessory.detailDisclosureButton;
    final info =
        kind == GlassListAccessory.detailButton ||
        kind == GlassListAccessory.detailDisclosureButton;
    final check = kind == GlassListAccessory.checkmark;
    final outline = kind == GlassListAccessory.outlineDisclosure;
    final turn = outline ? _outlineTurn : null;
    final editing = GlassListEditing.maybeOf(context);
    final value = widget.value;
    final edit = editing == null || !editing.editing
        ? null
        : editing.selects && value != null
        ? _EditKind.select
        : widget.onDelete != null
        ? _EditKind.delete
        : widget.onInsert != null
        ? _EditKind.insert
        : null;
    final picked =
        edit == _EditKind.select && editing!.selection.contains(value);
    final grip =
        editing != null &&
        editing.editing &&
        widget.showsReorderControl &&
        RawGlassList.reordersOf(context);
    final edits = edit != null || grip;
    _syncEdit(edit: edit, grip: grip);
    final menus = value == null ? null : GlassListContextMenu.maybeOf(context);
    final primary = menus?.onPrimaryAction;
    final row = RawGlassListRow(
      onPressed: edit == _EditKind.select
          ? () => editing!.toggle(value!)
          : edits
          ? null
          : widget.onPressed ??
                (primary == null || (editing?.editing ?? false)
                    ? null
                    : () => primary({value!})),
      onLongPress: edits ? null : widget.onLongPress,
      enabled: widget.enabled,
      selected: edit == _EditKind.select
          ? picked
          : !edits && (widget.selected || check),
      highlighted: edit == _EditKind.select ? picked : widget.selected,
      statesController: widget.statesController,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onInfoPressed: widget.onAccessoryPressed,
      infoSemanticLabel:
          widget.accessorySemanticLabel ??
          (outline
              ? (widget.expanded
                    ? GlassLocalizations.of(context).collapseLabel
                    : GlassLocalizations.of(context).expandLabel)
              : null),
      infoCenterInset: outline
          ? _Metrics.outlineEndInset + _Metrics.outlineSize / 2
          : (chevron
                    ? _Metrics.accessoryInset +
                          _Metrics.chevronSize.width +
                          _Metrics.gap
                    : _Metrics.infoInset) +
                _Metrics.infoSize / 2,
      infoBuilder: turn != null && !edits
          ? (context, details) => GlassHighlightPaint.of(
              context,
              states: details.statesListenable,
              focusColor: look.focusColor,
              hoverColor: _hover(look, details.states, context),
              shape: const LiquidOval(),
              child: _OutlineChevron(
                turn: turn,
                color: StateColors(context, details.states)(
                  look.secondaryColor,
                ),
              ),
            )
          : info
          ? (context, details) => GlassHighlightPaint.of(
              context,
              states: details.statesListenable,
              focusColor: look.focusColor,
              hoverColor: _hover(look, details.states, context),
              shape: const LiquidOval(),
              child: _Glyph.info(
                StateColors(context, _enabledLook(details.states))(
                  look.iconColor,
                ),
              ),
            )
          : null,
      builder: (context, details) => _row(
        context,
        details,
        look: look,
        place: place,
        chevron: !edits && chevron,
        info: !edits && info,
        check: !edits && check,
        outline: !edits && outline,
        edit: edit,
        grip: grip,
        picked: picked,
      ),
    );
    final held = menus == null
        ? row
        : _held(context, menus, row, editing: editing, value: value!);
    if (edit != _EditKind.delete) return held;
    return GlassSwipeActions(
      fullSwipe: false,
      openOn: _confirm,
      trailing: [
        GlassSwipeAction(
          title: GlassLocalizations.of(context).deleteLabel,
          destructive: true,
          onPressed: widget.onDelete!,
        ),
      ],
      child: held,
    );
  }

  // A held row acts on the selection it is in, or on itself.
  static Widget _held(
    BuildContext context,
    GlassListContextMenu menus,
    Widget row, {
    required GlassListEditing? editing,
    required Object value,
  }) {
    final selected =
        editing != null &&
        editing.editing &&
        editing.selects &&
        editing.selection.contains(value);
    final entries = menus.menuBuilder(
      context,
      selected ? editing.selection : {value},
    );
    return GlassContextMenu(
      menuChildren: entries,
      enabled: entries.isNotEmpty,
      child: row,
    );
  }

  static Set<WidgetState> _enabledLook(Set<WidgetState> states) =>
      states.difference(const {WidgetState.disabled});

  static Color _hover(
    GlassListStyle look,
    Set<WidgetState> states,
    BuildContext context,
  ) {
    final fill = StateColors(context, states)(look.overlayColor);
    return look.hoverColor ??
        fill.withValues(alpha: fill.a * GlassHighlights.hoverGain);
  }

  Widget _row(
    BuildContext context,
    GlassListRowDetails details, {
    required GlassListStyle look,
    required _RowPlace? place,
    required bool chevron,
    required bool info,
    required bool check,
    required bool outline,
    required _EditKind? edit,
    required bool grip,
    required bool picked,
  }) {
    final states = details.states;
    final color = StateColors(context, states);
    final secondary = color(look.secondaryColor);
    final icon = color(look.iconColor);
    final markColor = StateColors(
      context,
      _enabledLook(states),
    )(look.iconColor);
    final scale = GlassTextScale.of(context);
    final titleStyle = scale.resolve(
      _Metrics.body
          .merge(look.titleTextStyle)
          .copyWith(color: color(look.foregroundColor)),
    );
    final detailStyle = scale.resolve(
      _Metrics.body.merge(look.detailTextStyle).copyWith(color: secondary),
    );
    final subtitleStyle = scale.resolve(
      _Metrics.subtitle
          .merge(look.subtitleTextStyle)
          .copyWith(color: secondary),
    );
    final inset = place?.layout.contentInset ?? GlassListSection.contentInset;
    final padding = look.contentPadding?.resolve(Directionality.of(context));
    final level = widget.indentationLevel;
    final indent = _Metrics.indentationWidth * level;
    final start =
        indent +
        switch (padding) {
          null when level > 0 => _Metrics.indentedInset,
          null => inset,
          final padding =>
            Directionality.of(context) == TextDirection.ltr
                ? padding.left
                : padding.right,
        };
    final end = switch (padding) {
      null => inset,
      final padding =>
        Directionality.of(context) == TextDirection.ltr
            ? padding.right
            : padding.left,
    };
    final leading = widget.leading;
    final subtitle = widget.subtitle;
    final detail = widget.detail;
    final trailing = edit == null && !grip ? widget.trailing : null;
    final mark = chevron || info || check || outline;
    final accessory = trailing != null || mark;
    final restEnd = outline
        ? _Metrics.outlineEndInset
        : check
        ? _Metrics.checkmarkInset
        : info && !chevron
        ? _Metrics.infoInset
        : accessory
        ? _Metrics.accessoryInset
        : end;
    final editStart = _shownEdit != null
        ? _Metrics.editingInset + indent
        : start;
    final editEnd = _shownGrip
        ? _Metrics.gripEndInset + _Metrics.gripWidth + _Metrics.gripGap
        : restEnd;
    // A row that highlights has more than the card's color under its control.
    final highlights =
        widget.onPressed != null || widget.selected || edit == _EditKind.select;
    final card = place != null && !highlights
        ? StateColors(context, const {})(place.look.backgroundColor)
        : null;
    final titles = DefaultTextStyle(
      style: titleStyle,
      child:
          widget.child ??
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title case final title?) _LabelHeight(child: title),
              if (subtitle != null)
                DefaultTextStyle(
                  style: subtitleStyle,
                  child: _LabelHeight(child: subtitle),
                ),
            ],
          ),
    );
    final text = Padding(
      padding: EdgeInsets.only(
        top: padding?.top ?? _Metrics.rowPadding,
        bottom: padding?.bottom ?? _Metrics.rowPadding,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            MotionMeasure(
              onSize: _measureLeading,
              child: _LeadingSlot(
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
            child: switch (detail) {
              null => titles,
              final detail => _ValueRow(
                stacked: scale.isAccessibilitySize,
                text: titles,
                detail: DefaultTextStyle(
                  style: detailStyle,
                  child: _LabelHeight(child: detail),
                ),
              ),
            },
          ),
        ],
      ),
    );
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: look.minRowHeight ?? _Metrics.minRowHeight,
      ),
      child: _EditPadding(
        start: start,
        editStart: editStart,
        end: restEnd,
        editEnd: editEnd,
        progress: _progress,
        direction: Directionality.of(context),
        child: Row(
          children: [
            Expanded(child: text),
            if (accessory) const SizedBox(width: _Metrics.gap),
            if (trailing != null)
              GlassSolidBackdrop(color: card, child: trailing),
            if (trailing != null && mark) const SizedBox(width: _Metrics.gap),
            if (check) _Glyph.checkmark(markColor),
            if (info) const SizedBox.square(dimension: _Metrics.infoSize),
            if (info && chevron) const SizedBox(width: _Metrics.gap),
            if (chevron) _Chevron(color: color(look.disclosureColor)),
            if (outline) const SizedBox.square(dimension: _Metrics.outlineSize),
          ],
        ),
      ),
    );
    final separated =
        place != null &&
        (!place.last || place.endSeparator) &&
        (widget.showsSeparator ?? place.separators);
    final surface = separated
        ? _RowSeparator(
            color: color(look.separatorColor),
            textStart: start,
            editTextStart: editStart,
            edit: _progress,
            indent: look.separatorIndent,
            endIndent: look.separatorEndIndent ?? inset,
            leadingWidth: leading == null ? null : _leadingWidth,
            direction: Directionality.of(context),
            child: row,
          )
        : row;
    final shownEdit = _shownEdit;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final slide = _Metrics.editingInset - start;
    final marked = Stack(
      children: [
        surface,
        if (shownEdit != null)
          PositionedDirectional(
            start: 0,
            width: _Metrics.editingInset,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: edit == null,
              child: MotionTransition(
                offset: _edit.select(
                  (m) => Offset(
                    (rtl ? 1 : -1) *
                        slide *
                        (1 - m.progress.valueAt(m.now).clamp(0.0, 1.0)),
                    0,
                  ),
                ),
                opacity: _editProgress,
                child: _EditMark(
                  kind: shownEdit,
                  picked: picked,
                  onPressed: switch (edit) {
                    _EditKind.delete => _confirm.ping,
                    _EditKind.insert => widget.onInsert,
                    _EditKind.select || null => null,
                  },
                ),
              ),
            ),
          ),
        if (_shownGrip)
          PositionedDirectional(
            end: 0,
            width: _Metrics.gripWidth + _Metrics.gripEndInset,
            top: 0,
            bottom: 0,
            child: MotionTransition(
              opacity: _editProgress,
              child: RawGlassReorderHandle(
                enabled: grip,
                child: _Grip(color: GlassTheme.tertiaryLabelColorOf(context)),
              ),
            ),
          ),
      ],
    );
    if (!highlights) return marked;
    return GlassHighlightPaint.of(
      context,
      states: details.statesListenable,
      focusColor: look.focusColor,
      hoverColor: look.hoverColor,
      pressColor: color(look.overlayColor),
      pressed: details.highlight,
      shape: const LiquidRoundedRectangle(radius: 0),
      inside: true,
      child: marked,
    );
  }
}

class _RowPlace extends InheritedWidget {
  const _RowPlace({
    required this.last,
    required this.separators,
    required this.layout,
    required this.endSeparator,
    required this.look,
    required super.child,
  });

  final bool last;
  final bool separators;
  final GlassListLayout layout;
  // Whether the last row draws a separator too.
  final bool endSeparator;
  final GlassListStyle look;

  static _RowPlace? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowPlace>();

  @override
  bool updateShouldNotify(_RowPlace oldWidget) =>
      last != oldWidget.last ||
      separators != oldWidget.separators ||
      layout != oldWidget.layout ||
      endSeparator != oldWidget.endSeparator ||
      look != oldWidget.look;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel.header({
    required this.look,
    required this.layout,
    required this.label,
  }) : _header = true;

  const _SectionLabel.footer({
    required this.look,
    required this.layout,
    required this.label,
  }) : _header = false;

  final GlassListStyle look;
  final GlassListLayout layout;
  final Widget? label;
  final bool _header;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (label == null) {
      final empty = _header ? layout.noHeaderTop : layout.noFooterBottom;
      final spacing = look.sectionSpacing;
      return SizedBox(
        height: spacing == null || empty == 0
            ? empty
            : spacing *
                  empty /
                  (_Metrics.noHeaderTop + _Metrics.noFooterBottom),
      );
    }
    final style = GlassTextScale.of(context).resolve(
      (_header
              ? _Metrics.header.merge(look.headerTextStyle)
              : _Metrics.footer.merge(look.footerTextStyle))
          .copyWith(
            color: StateColors(context, const {})(look.secondaryColor),
          ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        layout.contentInset,
        _header ? layout.headerTop : layout.footerTop,
        layout.contentInset,
        _header ? layout.headerBottom : layout.footerBottom,
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
