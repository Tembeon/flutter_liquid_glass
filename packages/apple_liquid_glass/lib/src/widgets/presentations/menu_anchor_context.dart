part of 'menu_anchor.dart';

/// Shows a menu beside a lifted preview of [child] when it is held, as an
/// iOS 27 context menu does.
///
/// UIKit: `UIContextMenuInteraction`. SwiftUI: `contextMenu`. Flutter:
/// `CupertinoContextMenu`.
///
/// A finger resting on [child] grows it by UIKit's measured law (nothing for
/// 0.184 s, then 32 points a second to 8 points, then 20 a second to 15 points
/// along its longest side); a finger that moves drops it back, and so does one
/// that lifts before 0.42 s. From then on the hold takes the touch, so a
/// control in [child] does not run on the release, which opens the menu.
/// Held for 0.78 s, the page dims (20 percent light,
/// 48 percent dark), the preview lifts to 1.15 times its size (26 points at
/// most), fitted into the safe area, and the menu grows out of a blob at its
/// center beside it, on one spring of response 0.284 s (iPhone 16 Pro, iOS 27).
/// The finger then slides onto a row and chooses it on release; let go on the
/// preview, it leaves the menu open. A tap outside, Escape and Back close it.
/// [previewBuilder] draws the open preview in place of a copy of [child],
/// fading in as it lifts.
///
/// A press of the secondary mouse button opens the menu alone at the
/// pointer, at once, as UIKit's compact appearance does on iPadOS: no
/// preview and no dim, [child] stays in place, and the menu grows out of
/// the press and stands as beside a preview of no size there, 16 points
/// below the pointer (above it where it does not fit), centered on it or,
/// near the sides, with its edge on it. Not measured on iOS.
///
/// The context menu key and Shift+F10 open the menu beside its preview from
/// the keyboard focus: on [child], a Tab stop of its own, or on a control
/// inside it (a row under the menu), which is then the one stop and keeps
/// its own Space and Enter, ring and hover.
class GlassContextMenu extends StatefulWidget {
  /// Creates a context menu of [menuChildren] for [child].
  const GlassContextMenu({
    required this.menuChildren,
    required this.child,
    this.previewBuilder,
    this.controller,
    this.onOpen,
    this.onClose,
    this.enabled = true,
    this.semanticLabel,
    this.order = GlassMenuOrder.automatic,
    this.style,
    super.key,
  });

  /// The menu's entries.
  final List<GlassMenuEntry> menuChildren;

  /// What is held.
  final Widget child;

  /// Builds the preview shown while the menu is open, or null for a copy
  /// of [child].
  final WidgetBuilder? previewBuilder;

  /// Opens and closes the menu from code.
  final GlassMenuController? controller;

  /// Called when the menu starts to show.
  final VoidCallback? onOpen;

  /// Called when the menu has gone.
  final VoidCallback? onClose;

  /// Whether a hold opens the menu.
  final bool enabled;

  /// What accessibility reads for the menu.
  final String? semanticLabel;

  /// How the rows order in a menu that opens above the preview: in their
  /// own order by default, as UIKit's context menus keep them.
  final GlassMenuOrder order;

  /// The look of the menu's rows, over the theme's.
  final GlassMenuStyle? style;

  /// The scale of UIKit's open preview over a preview of natural [size]:
  /// 1.15 while that adds at most 26 points along its longest side, those
  /// points beyond (iPhone 16 Pro, iOS 27).
  @internal
  static double previewScale(Size size) {
    final longest = size.longestSide;
    if (longest <= 0) return 1;
    return 1 + math.min(0.15 * longest, 26) / longest;
  }

  @override
  State<GlassContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends _MenuHost<GlassContextMenu> {
  late final _holdGrowth = ContextHold(clock: MotionClockScope.of(context));
  late final _growth = _holdGrowth.select((hold) => hold.growth);

  late final _rest = FollowInteraction(
    _FollowedTouch(onDown: _down, onMove: _move),
    role: InteractionRole.observer,
  );

  late final _hold = _ContextSourceHold(
    this,
    duration: ContextHold.openAfter,
    armAfter: ContextHold.commitAfter,
    onStart: (t) => _openUnder(t, _holdGrowth.release(t)),
    onCommit: _lifted,
    onFail: _drop,
  ).sequenced(_port.forward);
  final _claimFocus = _AnchorFocusNode();

  // What the region reports of the keyboard focus and the mouse.
  final _states = WidgetStatesController();

  late final _shownStates = _AnchorStates(_states, _claimFocus);

  late final _secondary = _SecondaryClick(onClick: _click);

  // The press of the pointer's secondary button that opens the menu now, in
  // the anchor's coordinates, read only through that opening.
  Offset? _clicked;

  // Where the menu, open or last opened, stands alone at the pointer, in the
  // anchor's coordinates; null for a menu beside its preview.
  Offset? _compactAt;

  // What the anchor's box shows while the menu stands at the pointer: a
  // source no presentation holds, which keeps the anchor in place.
  final _unheld = MotionSource();

  @override
  void dispose() {
    _shownStates.dispose();
    _claimFocus.dispose();
    _states.dispose();
    super.dispose();
  }

  @override
  void _reportShowing(bool showing) =>
      (showing ? widget.onOpen : widget.onClose)?.call();

  Rect _heldRect = Rect.zero;
  Rect _previewRect = Rect.zero;

  // Where the preview grows out of and lands: the held view as the hold
  // grew it while the menu opens, at its natural size once it closes, as
  // the hidden view is by then.
  Rect _home = Rect.zero;

  @override
  List<GlassMenuEntry> get _entries => widget.menuChildren;

  @override
  GlassMenuOrder get _order => widget.order == GlassMenuOrder.automatic
      ? GlassMenuOrder.fixed
      : widget.order;

  @override
  GlassMenuController? get _controller => widget.controller;

  @override
  bool get _enabled => widget.enabled;

  @override
  String? get _semanticLabel => widget.semanticLabel;

  @override
  void didUpdateWidget(GlassContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updated(
      oldController: oldWidget.controller,
      wasEnabled: oldWidget.enabled,
    );
  }

  void _click(double t, Offset position) {
    _clicked = _secondary.byPointer ? position : null;
    _openFromCode();
    _clicked = null;
  }

  @override
  MenuMotion _prepare({double? at}) {
    if (!(_motion?.isPresented ?? false) && _clicked != _compactAt) {
      setState(() => _compactAt = _clicked);
    }
    return super._prepare(at: at);
  }

  // At the pointer the held view is the press, a preview of no size.
  @override
  MenuSource _sourceIn(RenderBox overlay, Rect box) {
    final at = _compactAt;
    return MenuSource(
      at == null
          ? box
          : Rect.fromCenter(center: box.topLeft + at, width: 0, height: 0),
    );
  }

  MenuAttachment _attach(Rect held, Size bounds, EdgeInsets padding) {
    final preferred = held.size * GlassContextMenu.previewScale(held.size);
    final fitted = MenuAttachment.fitPreview(
      preferred: preferred,
      bounds: bounds,
      padding: padding,
    );
    return MenuAttachment(
      held: held,
      preview: Rect.fromCenter(
        center: held.center,
        width: fitted.width,
        height: fitted.height,
      ),
    );
  }

  @override
  MenuMotion _createMotion(
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  ) {
    final attachment = _attach(source.shape, bounds, padding);
    final motion = MenuMotion.context(
      source: source,
      layout: _content.root,
      bounds: bounds,
      padding: padding,
      metrics: _content.metrics,
      attachment: attachment,
      clock: MotionClockScope.of(context),
    );
    _placePreview(motion, source.shape);
    return motion;
  }

  @override
  void _relayout(
    MenuMotion motion,
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  ) {
    motion.relayout(
      source: source,
      bounds: bounds,
      padding: padding,
      metrics: _content.metrics,
      attachment: _attach(source.shape, bounds, padding),
    );
    _placePreview(motion, source.shape);
  }

  void _placePreview(MenuMotion motion, Rect held) {
    _heldRect = held;
    _home = held;
    _previewRect = motion.attachment!.preview.shift(motion.previewShift);
  }

  @override
  void _stepped() {
    super._stepped();
    if (_motion?.isClosing ?? false) _home = _heldRect;
  }

  void _openUnder(double t, double growth) {
    final pointer = _held;
    if (pointer == null || !mounted || !_enabled || _isOpen) return;
    _prepare(at: t);
    final longest = _heldRect.size.longestSide;
    final grown = longest <= 0 ? 1.0 : 1 + growth / longest;
    _home = Rect.fromCenter(
      center: _heldRect.center,
      width: _heldRect.width * grown,
      height: _heldRect.height * grown,
    );
    _openByHold(pointer, t);
  }

  // The finger lifted after the hold opened the menu.
  void _lifted(double t) {
    final pointer = _held;
    _held = null;
    if (pointer != null) _sourceUp(pointer, t, _finger);
  }

  void _drop(double t) {
    _held = null;
    _holdGrowth.release(t);
  }

  void _down(int pointer, double t, Offset global) {
    if (!_enabled ||
        _held != null ||
        _pointer != null ||
        (_motion?.isPresented ?? false)) {
      return;
    }
    _held = pointer;
    _finger = global;
    _holdGrowth.down(t);
  }

  void _move(int pointer, double t, Offset global) {
    if (pointer == _held) _finger = global;
  }

  Matrix4 _growthTransform() {
    final size = _heldRect.isEmpty
        ? (context.findRenderObject() as RenderBox?)?.size ?? Size.zero
        : _heldRect.size;
    final longest = size.longestSide;
    final s = longest <= 0 ? 1.0 : 1 + _holdGrowth.growth / longest;
    return Matrix4.diagonal3Values(s, s, 1);
  }

  Rect _previewNow() {
    final motion = _motion;
    if (motion == null) return _home;
    return Rect.lerp(_home, _previewRect, motion.progress) ?? _previewRect;
  }

  // The page dims to 20 percent black in light mode, 48 in dark
  // (context-menu.md).
  @override
  double Function(MenuMotion motion) _dim(BuildContext context) {
    final full = GlassTraits.of(context).brightness == Brightness.dark
        ? 0.48
        : 0.2;
    return (motion) => _compactAt == null ? full * motion.dim : 0;
  }

  @override
  List<Widget> _backdrop(_MenuLayerState layer) {
    if (_compactAt != null) return const [];
    final natural = _heldRect.size;
    final builder = widget.previewBuilder;
    final frames = layer.frames;
    Widget carried(Size size, Widget child) => menuDriven(frames, (_) {
      final rect = _previewNow();
      return menuPlacement(
        rect.topLeft & size,
        Transform(
          alignment: Alignment.topLeft,
          transform: Matrix4.diagonal3Values(
            size.width <= 0 ? 1 : rect.width / size.width,
            size.height <= 0 ? 1 : rect.height / size.height,
            1,
          ),
        ),
      );
    }, child: child);
    double shown() => ((_motion?.progress ?? 0) * 2).clamp(0.0, 1.0);
    // The preview is a picture of the anchor, which screen readers read
    // in its place.
    return [
      IgnorePointer(
        child: ExcludeSemantics(
          child: Stack(
            children: [
              carried(
                natural,
                builder == null
                    ? widget.child
                    : menuDriven(
                        frames,
                        (_) => Opacity(opacity: 1 - shown()),
                        child: widget.child,
                      ),
              ),
              if (builder != null)
                carried(
                  _previewRect.size,
                  menuDriven(
                    frames,
                    (_) => Opacity(opacity: shown()),
                    child: Builder(builder: builder),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _style = MenuAppearance.of(context, widget.style);
    final enabled = widget.enabled;
    // The anchor is the region's one node, named by what it shows, with
    // the hold as its long press; the menu is read after it.
    return _host(
      InputRegion(
        interactions: [_rest, _hold, _secondary],
        feedback: (event) =>
            event is LongPressArmEvent ? MotionHaptic.heavyImpact : null,
        statesController: _states,
        mouseCursor: WidgetStateMouseCursor.adaptiveClickable,
        enabled: enabled,
        focusNode: _claimFocus,
        semantics: SemanticsProperties(
          onLongPress: enabled ? _openFromCode : null,
        ),
        child: MotionSourceBox(
          source: _compactAt == null ? _source : _unheld,
          child: MotionScope(
            motion: _holdGrowth,
            child: menuDriven(
              _growth,
              (_) => Transform(
                alignment: Alignment.center,
                transform: _growthTransform(),
              ),
              child: GlassHighlightPaint.of(
                context,
                states: _shownStates,
                shape: const LiquidRoundedRectangle(radius: 0),
                wash: true,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The focus of a context menu's anchor: a Tab stop of its own, where the
/// context menu key lands, unless what it holds has one. From a stop inside
/// it, a row under the menu, the key opens the menu all the same.
class _AnchorFocusNode extends FocusNode {
  _AnchorFocusNode() : super(debugLabel: 'GlassContextMenu');

  /// Whether a Tab stop lies inside the anchor.
  bool get holdsStop =>
      descendants.any((node) => node.canRequestFocus && !node.skipTraversal);

  @override
  bool get skipTraversal => super.skipTraversal || holdsStop;
}

/// What the ring and the hover wash around a context menu's anchor follow:
/// its region's states, focused only while the anchor itself has the focus,
/// and not hovered while it holds a Tab stop, whose control answers the
/// pointer itself.
class _AnchorStates extends ChangeNotifier
    implements ValueListenable<Set<WidgetState>> {
  _AnchorStates(this._states, this._focus) {
    _states.addListener(notifyListeners);
    _focus.addListener(notifyListeners);
  }

  final ValueListenable<Set<WidgetState>> _states;
  final _AnchorFocusNode _focus;

  @override
  Set<WidgetState> get value {
    final focused = _focus.hasPrimaryFocus;
    final hovered = !_focus.holdsStop;
    return {
      for (final state in _states.value)
        if ((state != WidgetState.focused || focused) &&
            (state != WidgetState.hovered || hovered))
          state,
    };
  }

  @override
  void dispose() {
    _states.removeListener(notifyListeners);
    _focus.removeListener(notifyListeners);
    super.dispose();
  }
}

/// A context menu's hold, which drops once the finger travels past the
/// touch's slop. Not measured on iOS.
final class _ContextSourceHold extends _SourceHold {
  _ContextSourceHold(
    super._host, {
    super.duration,
    super.armAfter,
    super.onStart,
    super.onCommit,
    super.onFail,
  });

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput && pointer == null && accepts(input)) {
      allowableMovement = input.tapSlop;
    }
    return super.handle(input);
  }
}

/// A secondary click that tells a press of the pointer's button from a key.
final class _SecondaryClick extends SecondaryClickInteraction {
  _SecondaryClick({super.onClick});

  /// Whether the click reported last was a press of the pointer's button.
  bool byPointer = false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput || input is ContextMenuInput) {
      byPointer = input is PointerDownInput;
    }
    return super.handle(input);
  }
}
