part of 'alert.dart';

class _AlertViewState extends State<_AlertView> {
  late final _press = GlassPress(clock: MotionClockScope.of(context));
  late final _lean = _press.select((p) => p.lean);
  late final _pressX = _press.select((p) => p.scaleX);
  late final _pressY = _press.select((p) => p.scaleY);
  // A scroll of the content takes the touch from the platter and from the
  // actions, which cancels the lift and the press.
  late final List<Interaction> _platter = [
    FollowInteraction(_press, role: InteractionRole.content),
  ];
  final _zones = InputZonesController<int>();
  final _scroll = ScrollController();
  // Bumped when the card's size settles, as the actions' frames read the
  // layout.
  final _layouts = ValueNotifier<int>(0);
  late final _frames = Listenable.merge([_scroll, _layouts]);
  final _card = GlobalKey(debugLabel: 'alert card');
  final _block = GlobalKey(debugLabel: 'alert actions');
  final List<List<Interaction>> _presses = [];
  final List<GlassHighlight> _highlights = [];
  late GlassHighlightLook _highlightLook;
  late final _opacity = widget.motion.select((m) => m.opacity);
  late final _scale = widget.motion.select(
    (m) => switch (m) {
      AlertMotion() => m.pose.scale,
      PopoverMotion() => m.pose.scale,
      _ => 1.0,
    },
  );
  ValueListenable<bool>? _dismissing;
  late final _frame = widget.motion.select(
    (m) => GlassFrame(shape: _platterShape, opacity: m.opacity),
  );
  static const _platterShape = LiquidRoundedSuperellipse(
    radius: _AlertLook.cornerRadius,
  );

  List<GlassAlertAction> _shown = const [];
  bool _row = false;
  bool _rtl = false;
  Listenable? _enablings;

  @override
  void initState() {
    super.initState();
    _hearEnablings();
  }

  // An action whose enabled state changes while the alert shows draws and
  // takes taps as it now stands.
  void _hearEnablings() {
    _enablings?.removeListener(_enablingChanged);
    _enablings = Listenable.merge([
      for (final action in widget.actions) ?action.enabledListenable,
    ])..addListener(_enablingChanged);
  }

  void _enablingChanged() => setState(() {});

  @override
  void dispose() {
    _enablings?.removeListener(_enablingChanged);
    _dismissing?.removeListener(_dismissingChanged);
    _zones.dispose();
    _scroll.dispose();
    _layouts.dispose();
    super.dispose();
  }

  // The presentation is inert from its dismissal on; a finger already down
  // stops lifting the platter.
  void _dismissingChanged() {
    if (_dismissing!.value && _press.isPressed) {
      _press.pointerCancel(widget.motion.clock.now);
    }
  }

  void _choose(GlassAlertAction action) {
    if (!action.isEnabled) return;
    PresentationHandle.of(
      context,
    ).dismiss(DismissTrigger.programmatic, action);
  }

  List<Interaction> _pressOf(int index) {
    while (_presses.length <= index) {
      final i = _presses.length;
      _presses.add([
        PressInteraction(
          role: InteractionRole.content,
          onTap: (t) => _choose(_shown[i]),
        ),
      ]);
    }
    return _presses[index];
  }

  GlassHighlight _highlightOf(int index) {
    while (_highlights.length <= index) {
      _highlights.add(
        GlassHighlight(
          look: _highlightLook,
          states: _zones.states(_highlights.length),
          clock: _press.clock,
        ),
      );
    }
    return _highlights[index];
  }

  // Where action [index] lies in the card: its slot in the block of
  // buttons, carried by the layout and the scroll to the card's box, and
  // cut to what the card shows.
  InputZoneFrame? _frameOf(int index) {
    final card = _card.currentContext?.findRenderObject();
    final block = _block.currentContext?.findRenderObject();
    if (card is! RenderBox ||
        block is! RenderBox ||
        !card.hasSize ||
        !block.hasSize ||
        !block.attached ||
        index >= _shown.length) {
      return null;
    }
    final slot = _slot(index, block.size.width);
    final rect = MatrixUtils.transformRect(block.getTransformTo(card), slot);
    return InputZoneFrame(
      rect.intersect(Offset.zero & card.size),
      borderRadius: BorderRadius.circular(_AlertLook.buttonHeight / 2),
    );
  }

  Rect _slot(int index, double width) {
    const height = _AlertLook.buttonHeight;
    if (_row) {
      final each = (width - _AlertLook.buttonGap) / 2;
      final first = (index == 0) != _rtl;
      return Rect.fromLTWH(
        first ? 0 : each + _AlertLook.buttonGap,
        0,
        each,
        height,
      );
    }
    return Rect.fromLTWH(
      0,
      index * (height + _AlertLook.buttonGap),
      width,
      height,
    );
  }

  static MotionHaptic? _feedback(int action, InteractionEvent event) =>
      switch (event) {
        ScrubChangeEvent() => MotionHaptic.selection,
        _ => null,
      };

  GlassAlertStyle _look = const GlassAlertStyle();
  late GlassTextScale _text;

  bool _fitsInRow(double width, BuildContext context) {
    final each =
        (width - 2 * _AlertLook.buttonInset - _AlertLook.buttonGap) / 2;
    final direction = Directionality.of(context);
    for (final action in widget.actions) {
      final label = action.child;
      if (label is! Text || label.data == null) return false;
      final measured = _text.measure(
        label.data!,
        _labelStyle(action, context),
        textDirection: direction,
        maxLines: 1,
      );
      if (measured.size.width + 2 * _AlertLook.buttonTextInset > each) {
        return false;
      }
    }
    return true;
  }

  TextStyle _labelStyle(GlassAlertAction action, BuildContext context) {
    final look = _look;
    final label = GlassTheme.labelColorOf(context);
    final color = !action.isEnabled
        ? GlassTheme.tertiaryLabelColorOf(context)
        : action.isDefaultAction
        ? look.defaultActionColor ??
              GlassTheme.contentColorOf(context)(_fillOf(action, context))
        : action.isDestructive
        ? look.destructiveActionColor ?? GlassColors.systemRed
        : look.actionColor ?? label;
    return _text.resolve(
      TextStyle(
            fontSize: _AlertLook.textFontSize,
            height: _AlertLook.textHeight,
            fontWeight: action.isDefaultAction
                ? _AlertLook.preferredWeight
                : FontWeight.w500,
          )
          .merge(look.actionTextStyle)
          .copyWith(
            color: GlassDynamicColor.resolve(color, context),
          ),
    );
  }

  Color _fillOf(GlassAlertAction action, BuildContext context) =>
      GlassDynamicColor.resolve(
        action.isDefaultAction && action.isEnabled
            ? _look.defaultActionFillColor ??
                  GlassTheme.primaryColorOf(context) ??
                  GlassColors.systemBlue
            : _look.actionFillColor ?? GlassColors.tertiarySystemFill,
        context,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dismissing = PresentationHandle.of(context).dismissing;
    if (!identical(dismissing, _dismissing)) {
      _dismissing?.removeListener(_dismissingChanged);
      _dismissing = dismissing..addListener(_dismissingChanged);
    }
    _derive();
  }

  @override
  void didUpdateWidget(_AlertView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hearEnablings();
    _derive();
  }

  // Everything a handler or a slot reads is settled where its inputs
  // change, not in build: the look and direction from the context, the row
  // fit and the order from the actions.
  void _derive() {
    _look = (widget.style ?? const GlassAlertStyle()).merge(
      GlassAlertStyle.maybeOf(context),
    );
    _rtl = Directionality.of(context) == TextDirection.rtl;
    _text = GlassTextScale.of(context, max: _AlertLook.maxTextScale);
    _row =
        !widget.actionSheet &&
        widget.actions.length == 2 &&
        _fitsInRow(_cardWidth(context), context);
    _shown = _ordered(widget.actions, row: _row, popover: _inPopover);
  }

  bool get _inPopover => widget.anchorRect != null;

  double _cardWidth(BuildContext context) => math.min(
    _inPopover ? _AlertLook.popoverWidth : AlertMotion.width,
    MediaQuery.sizeOf(context).width -
        _onPart(context, EdgeInsets.zero).horizontal -
        2 * _AlertLook.screenMargin,
  );

  // A view split by a hinge keeps a centered alert on one part.
  EdgeInsets _onPart(BuildContext context, EdgeInsets insets) => _inPopover
      ? insets
      : MediaQuery.of(
          context,
        ).onSubScreen(insets, anchorPoint: widget.anchorPoint);

  @override
  Widget build(BuildContext context) {
    final width = _cardWidth(context);
    _highlightLook = GlassHighlightLook.of(context);
    for (final highlight in _highlights) {
      highlight.look = _highlightLook;
    }
    return MotionScope(
      motion: _press,
      child: _place(_buildCard(width, context), context),
    );
  }

  Widget _place(Widget card, BuildContext context) {
    final popover = widget.anchorRect;
    if (popover != null) {
      return PopoverLayout(
        source: popover,
        permitted: widget.permitted,
        scale: _scale,
        opacity: _opacity,
        maxWidth: _AlertLook.popoverWidth,
        padding: GlassMediaQueryData.overlayPaddingOf(
          context,
          anchorPoint: popover.center,
        ),
        direction: Directionality.of(context),
        card: card,
      );
    }
    return Padding(
      padding: _onPart(context, MediaQuery.of(context).paddingAboveKeyboard),
      child: Center(
        child: MotionTransition(
          scale: _scale,
          child: MotionTransition(
            offset: _lean,
            scaleX: _pressX,
            scaleY: _pressY,
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(double width, BuildContext context) {
    final label = GlassTheme.labelColorOf(context);
    final title = widget.title;
    final message = widget.message;
    final both = title != null && message != null;
    final header = <Widget>[
      if (title != null)
        DefaultTextStyle(
          style: _text.resolve(
            TextStyle(
              fontSize: _AlertLook.textFontSize,
              height: _AlertLook.textHeight,
              fontWeight: both
                  ? FontWeight.w600
                  : _AlertLook.singleHeaderWeight,
              color: label,
            ).merge(_look.titleTextStyle).resolvedColor(context),
          ),
          child: title,
        ),
      if (both) const SizedBox(height: _AlertLook.titleGap),
      if (message != null)
        DefaultTextStyle(
          style: _text.resolve(
            (both
                    ? const TextStyle(
                        fontSize: 15,
                        height: _AlertLook.messageHeight,
                        color: GlassColors.secondaryLabel,
                      )
                    : TextStyle(
                        fontSize: _AlertLook.textFontSize,
                        height: _AlertLook.textHeight,
                        color: label,
                      ))
                .merge(_look.messageTextStyle)
                .resolvedColor(context),
          ),
          child: message,
        ),
    ];
    final buttons = [
      for (final (i, action) in _shown.indexed)
        _AlertButton(
          action: action,
          states: _zones.states(i),
          highlight: _highlightOf(i),
          label: _labelStyle(action, context),
          fill: _fillOf(action, context),
        ),
    ];
    final block = _row
        ? Row(
            key: _block,
            children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: _AlertLook.buttonGap),
              Expanded(child: buttons[1]),
            ],
          )
        : Column(
            key: _block,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: _AlertLook.buttonGap),
                buttons[i],
              ],
            ],
          );
    final content = Padding(
      padding: EdgeInsets.only(
        top: header.isNotEmpty ? _AlertLook.headerTop : 0,
        bottom: _AlertLook.buttonInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: _AlertLook.textInset,
                right: _AlertLook.textInset,
                bottom: both
                    ? _AlertLook.headerBottom
                    : _AlertLook.singleHeaderBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: header,
              ),
            ),
          if (widget.textFields.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: header.isEmpty
                    ? 0
                    : _AlertLook.fieldsTop -
                          (both
                              ? _AlertLook.headerBottom
                              : _AlertLook.singleHeaderBottom),
                left: _AlertLook.fieldInset,
                right: _AlertLook.fieldInset,
              ),
              child: _AlertFields(fields: widget.textFields),
            ),
          if (buttons.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: widget.textFields.isEmpty
                    ? _AlertLook.buttonInset
                    : _AlertLook.buttonsBelowFields,
                left: _AlertLook.buttonInset,
                right: _AlertLook.buttonInset,
              ),
              child: block,
            ),
        ],
      ),
    );
    return _text.apply(
      InputZones<int>(
        zones: [
          for (final (i, action) in _shown.indexed)
            InputZone<int>(
              id: i,
              interactions: _pressOf(i),
              enabled: action.isEnabled,
              reach: glassTargetReach,
              autofocus:
                  widget.textFields.isEmpty &&
                  action.isDefaultAction &&
                  action.isEnabled,
              semantics: SemanticsProperties(
                label: glassLabelTextOf(action.child),
                button: true,
              ),
            ),
        ],
        frameOf: _frameOf,
        frames: _frames,
        controller: _zones,
        arrows: _row ? InputZoneArrows.horizontal : InputZoneArrows.vertical,
        slides: true,
        feedback: _feedback,
        excludeChildSemantics: false,
        // The platter's lift sits below the zones: a region above them
        // would answer their Space and Enter.
        child: _inPopover
            ? _measured(width, content)
            : InputRegion(
                interactions: _platter,
                child: _measured(width, content),
              ),
      ),
    );
  }

  Widget _measured(double width, Widget content) => MotionMeasure(
    onSize: (t, size) => _layouts.value++,
    child: SizedBox(
      key: _card,
      width: width,
      child: Stack(
        children: [
          if (!_inPopover)
            Positioned.fill(
              child: GlassSurface.live(
                role: GlassRole.panel,
                frame: _frame,
                child: const SizedBox.expand(),
              ),
            ),
          MotionTransition(
            opacity: _opacity,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(
                _inPopover ? popoverCornerRadius : _AlertLook.cornerRadius,
              ),
              child: ListView(
                controller: _scroll,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                children: [content],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// An alert's text fields: one group of 48 point rows, each on its own fill,
/// the group's outer corners round and the joints square, a hairline under
/// every row but the last (alerts passport, 27.2); the first takes the
/// focus, as UIKit's raises the keyboard.
class _AlertFields extends StatelessWidget {
  const _AlertFields({required this.fields});

  final List<GlassAlertTextField> fields;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, field) in fields.indexed)
        RawGlassTextField(
          controller: field.controller,
          autofocus: i == 0,
          obscureText: field.obscureText,
          keyboardType: field.keyboardType,
          textInputAction: field.textInputAction,
          textCapitalization: field.textCapitalization,
          autocorrect: field.autocorrect,
          enableSuggestions: field.enableSuggestions,
          autofillHints: field.autofillHints,
          inputFormatters: field.inputFormatters,
          onChanged: field.onChanged,
          onSubmitted: field.onSubmitted,
          semanticLabel: field.semanticLabel,
          semanticHint: field.placeholder,
          contextMenuBuilder: (context, state) =>
              GlassEditMenu.editableText(editableTextState: state),
          builder: (context, details) => _AlertFieldLook(
            details: details,
            placeholder: field.placeholder,
            first: i == 0,
            last: i == fields.length - 1,
          ),
        ),
    ],
  );
}

class _AlertFieldLook extends StatelessWidget {
  const _AlertFieldLook({
    required this.details,
    required this.placeholder,
    required this.first,
    required this.last,
  });

  final GlassTextFieldDetails details;
  final String? placeholder;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scale = GlassTextScale.of(context, max: _AlertLook.maxTextScale);
    final text = scale.resolve(
      TextStyle(
        fontSize: _AlertLook.textFontSize,
        color: GlassDynamicColor.resolve(
          GlassTheme.labelColorOf(context),
          context,
        ),
      ),
    );
    const radius = Radius.circular(_AlertLook.buttonHeight / 2);
    final placeholder = this.placeholder;
    final field = DecoratedBox(
      decoration: BoxDecoration(
        color: GlassDynamicColor.resolve(
          GlassColors.tertiarySystemFill,
          context,
        ),
        borderRadius: BorderRadius.vertical(
          top: first ? radius : Radius.zero,
          bottom: last ? radius : Radius.zero,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: _AlertLook.buttonHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _AlertLook.fieldTextInset,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Stack(
              children: [
                if (placeholder != null)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: ListenableBuilder(
                        listenable: details.controller,
                        builder: (context, _) => Visibility(
                          visible: details.controller.text.isEmpty,
                          child: Text(
                            placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: scale.scaler,
                            style: text.copyWith(
                              color: GlassDynamicColor.resolve(
                                GlassColors.tertiaryLabel,
                                context,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                details.text(
                  style: text,
                  cursorColor: _AlertLook.cursor,
                  selectionColor: _AlertLook.cursor.withValues(alpha: 0.2),
                  scale: scale,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (last) return field;
    return CustomPaint(
      foregroundPainter: _FieldSeparator(
        color: GlassDynamicColor.resolve(_AlertLook.fieldSeparator, context),
        direction: Directionality.of(context),
      ),
      child: field,
    );
  }
}

class _FieldSeparator extends CustomPainter {
  const _FieldSeparator({required this.color, required this.direction});

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = _AlertLook.fieldTextInset;
    canvas.drawRect(
      Rect.fromLTRB(inset, size.height - 1, size.width - inset, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FieldSeparator oldDelegate) =>
      color != oldDelegate.color || direction != oldDelegate.direction;
}
