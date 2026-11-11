part of 'menu_anchor.dart';

/// What the layer's tree is built from; it builds only when this changes.
@immutable
class _Structure {
  const _Structure({
    required this.layouts,
    required this.hidden,
    required this.open,
    required this.scrolls,
    required this.top,
  });

  final List<MenuLayout> layouts;

  /// The row each card hides under the submenu card grown out of it.
  final List<int?> hidden;
  final bool open;
  final bool scrolls;

  /// The card whose rows take the keys, the mouse and the highlight.
  final int top;

  @override
  bool operator ==(Object other) {
    if (other is! _Structure ||
        other.open != open ||
        other.scrolls != scrolls ||
        other.top != top ||
        other.layouts.length != layouts.length) {
      return false;
    }
    for (var i = 0; i < layouts.length; i++) {
      if (!identical(other.layouts[i], layouts[i]) ||
          other.hidden[i] != hidden[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(open, scrolls, top, layouts.length);
}

/// The open menu on the overlay: its glass, the source's look on it, its
/// rows and the submenu cards over them, each following the motion's
/// frames without a rebuild.
///
/// The targets of the top card are the zones of one host: one Tab stop,
/// whose arrows, Home and End move the focus among them, Space and Enter
/// choose, the arrow toward the trailing edge opens a submenu and the one
/// toward the leading edge or Escape goes back. The focused row is the
/// highlighted one; the mouse focuses the row it rests on. Touches stay
/// with the motion, which follows the finger over the whole menu.
class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.host});

  final _MenuHost<StatefulWidget> host;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  final _scroll = ScrollController();
  final Map<MenuLayout, (int?, Widget)> _rows = Map.identity();
  final _zones = InputZonesController<int>();
  final Map<int, List<Interaction>> _rowInputs = {};
  MenuAppearance? _rowsStyle;
  late _Structure _built;
  bool _parentLocked = false;

  // A row's zone id is its target index on the top card, except that the
  // focused zone carries over a card change: its id then names the row the
  // keyboard moves to, swapped with that row's own index.
  int? _swapId;
  int? _swapTarget;

  // The row of the next top card the keyboard moves to: -1 for its first
  // row, else a target index; null when no key changed the card.
  int? _pending;
  int? _lastFocused;
  bool _cardEntered = false;

  _MenuHost<StatefulWidget> get _host => widget.host;

  late final MotionSelection<MenuMotion> _frames = _host._steps!;

  late final _input = _MenuInput(
    down: _host._pointerDown,
    move: _host._pointerMove,
    up: _host._pointerUp,
    cancel: _host._pointerCancel,
    heard: _host._takeHeard,
  );

  late final _hover = _HoverInput(onHover: _hovered);

  MenuMotion get _motion => _host._motion!;

  double get _width => _motion.menuWidth;

  bool get _rtl => _host._content.rtl;

  @override
  void initState() {
    super.initState();
    _frames.addListener(_tick);
    _scroll.addListener(_scrolled);
    _zones.addListener(_focusMoved);
    _built = _structure();
  }

  @override
  void dispose() {
    _frames.removeListener(_tick);
    _zones.removeListener(_focusMoved);
    _zones.dispose();
    _scroll.dispose();
    super.dispose();
  }

  _Structure _structure() {
    final motion = _motion;
    final cards = motion.cards;
    final root = cards[0].layout;
    return _Structure(
      layouts: [for (final card in cards) card.layout],
      hidden: [for (final card in cards.skip(1)) card.source, null],
      open: motion.isOpen,
      scrolls: root.height > motion.visibleRootHeight + 0.5,
      top: motion.topCard,
    );
  }

  void _tick() {
    final structure = _structure();
    if (structure == _built) return;
    if (structure.top != _built.top) _cardChanged(structure.top);
    setState(() => _built = structure);
  }

  int _idOf(int target) => target == _swapTarget
      ? _swapId!
      : target == _swapId
      ? _swapTarget!
      : target;

  // The swap is its own inverse.
  int _targetOf(int id) => _idOf(id);

  /// The top card is now [top]: the focus a key asked for moves onto its
  /// row, carried by the zone that has the focus.
  void _cardChanged(int top) {
    final pending = _pending;
    _pending = null;
    _cardEntered = false;
    final focused = _zones.focusedZone;
    _swapId = null;
    _swapTarget = null;
    if (pending == null || focused == null) return;
    final targets = _motion.cards[top].layout.targets;
    var target = pending;
    if (pending < 0) {
      target = targets.indexWhere(
        (MenuTarget t) => t.kind != MenuTargetKind.back,
      );
      if (target < 0) target = 0;
    }
    if (target >= targets.length || target == focused) return;
    _swapId = focused;
    _swapTarget = target;
  }

  void _scrolled() {
    if (_scroll.hasClients) _motion.scrollOffset = _scroll.offset;
  }

  bool _scrollStarted(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _scrollGesture();
    }
    return false;
  }

  void _scrollGesture() =>
      _host._command((motion, t) => motion.pointerScrolled(t));

  /// Whether the rows the zones stand for are the top card's now.
  bool get _current {
    final motion = _motion;
    return motion.isOpen && motion.topCard == _built.top;
  }

  MenuTarget? _targetAt(int index) {
    final targets = _built.layouts[_built.top].targets;
    return index >= 0 && index < targets.length ? targets[index] : null;
  }

  /// Chooses [index] of the top card; [pending] is where the focus moves
  /// when that changes the card, or null to leave it.
  void _choose(int index, {int? pending}) {
    if (!_current) return;
    final target = _targetAt(index);
    if (target == null) return;
    _pending = switch (target.kind) {
      MenuTargetKind.submenu => pending,
      MenuTargetKind.back =>
        pending == null ? null : _motion.cards[_built.top].source,
      MenuTargetKind.action => null,
    };
    _host._command((motion, t) => motion.select(t, index));
  }

  void _back({required bool keys}) {
    if (!_current || _built.top == 0) return;
    if (keys) _pending = _motion.cards[_built.top].source;
    _host._command((motion, t) => motion.back(t));
  }

  void _focusMoved() {
    final id = _zones.focusedZone;
    if (id == _lastFocused) return;
    _lastFocused = id;
    if (id == null || !_current) return;
    final index = _targetOf(id);
    if (_motion.highlighted != index || _motion.highlightedCard != _built.top) {
      _host._command((motion, t) => motion.highlight(t, index));
    }
    _reveal(index);
  }

  // A row the keys move to below or above the visible root list scrolls
  // into it.
  void _reveal(int index) {
    if (_built.top != 0 || !_scroll.hasClients) return;
    final target = _targetAt(index);
    if (target == null) return;
    final visible = _motion.visibleRootHeight;
    final offset = _scroll.offset;
    final rect = target.rect;
    if (rect.top < offset) {
      _scroll.jumpTo(rect.top);
    } else if (rect.bottom > offset + visible) {
      _scroll.jumpTo(rect.bottom - visible);
    }
  }

  void _menuFocused(bool focused) {
    if (!focused ||
        FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    final targets = _built.layouts[_built.top].targets;
    if (targets.isEmpty) return;
    _zones.requestFocus(_idOf(0));
  }

  // The arrow toward the trailing edge opens a submenu row's card, the one
  // toward the leading edge goes back; past the first or the last row the
  // focus stays.
  bool _edge(int id, TraversalDirection direction) {
    final into = _rtl ? TraversalDirection.left : TraversalDirection.right;
    final out = _rtl ? TraversalDirection.right : TraversalDirection.left;
    final index = _targetOf(id);
    if (direction == into && _targetAt(index)?.kind == MenuTargetKind.submenu) {
      _choose(index, pending: -1);
    } else if (direction == out) {
      _back(keys: true);
    }
    return true;
  }

  // The mouse that rests on a row moves the focus there, as Flutter's menu
  // items do; a row scrolled out of the list takes nothing.
  void _rowEntered(int id) {
    if (!_current) return;
    final rect = _motion.targetRect(_targetOf(id));
    if (rect == null) return;
    final frame = _motion.menuRect;
    if (!frame.contains(rect.center)) return;
    _zones.requestFocus(id);
  }

  void _dwelled(int id) {
    final index = _targetOf(id);
    if (_targetAt(index)?.kind != MenuTargetKind.submenu) return;
    _choose(index);
  }

  // The mouse that leaves an open submenu card for the menu beside it
  // sends the card back, as a menu on the Mac closes a submenu when the
  // pointer moves to another item.
  void _hovered(Offset local) {
    final motion = _motion;
    if (!_current || _built.top == 0) return;
    final position = _host._local(
      (context.findRenderObject()! as RenderBox).localToGlobal(local),
    );
    if (motion.isOnCard(position)) {
      _cardEntered = true;
    } else if (_cardEntered && motion.isBesideCard(position)) {
      _cardEntered = false;
      _back(keys: false);
    }
  }

  List<Interaction> _inputsOf(int id) => _rowInputs.putIfAbsent(
    id,
    () => [
      _RowInput(
        onActivate: () => _choose(_targetOf(id), pending: -1),
        onEnter: () => _rowEntered(id),
      ),
      HoverDwellInteraction(
        duration: MenuMotion.mouseSubmenuDelay,
        onDwell: (_) => _dwelled(id),
      ),
    ],
  );

  InputZoneFrame? _frameOf(int id) {
    if (!_current) return null;
    final rect = _motion.targetRect(_targetOf(id));
    return rect == null ? null : InputZoneFrame(rect);
  }

  List<InputZone<int>> _zonesOf(MenuLayout layout) {
    final zones = <InputZone<int>>[];
    for (var i = 0; i < layout.targets.length; i++) {
      final target = layout.targets[i];
      final element = target.element < 0
          ? null
          : layout.elements[target.element];
      final id = _idOf(i);
      final entry = target.entry;
      final (String label, String? value) = switch (entry) {
        GlassMenuItem(:final title, :final subtitle) ||
        GlassSubmenu(:final title, :final subtitle) => (title, subtitle),
        _ => (element?.title ?? '', null),
      };
      final state = entry is GlassMenuItem ? entry.state : null;
      final checkable = state != null && state != GlassMenuItemState.off;
      zones.add(
        InputZone<int>(
          id: id,
          interactions: _inputsOf(id),
          minimumHitSize: const Size.square(44),
          semantics: SemanticsProperties(
            label: label,
            value: value,
            button: true,
            checked: checkable ? state == GlassMenuItemState.on : null,
            mixed:
                target.kind == MenuTargetKind.action &&
                    state == GlassMenuItemState.mixed
                ? true
                : null,
            expanded: switch (target.kind) {
              MenuTargetKind.submenu => false,
              MenuTargetKind.back => true,
              MenuTargetKind.action => null,
            },
            role: checkable
                ? ui.SemanticsRole.menuItemCheckbox
                : ui.SemanticsRole.menuItem,
          ),
        ),
      );
    }
    return zones;
  }

  /// The target of [card] the highlight shows on now: the focused row of
  /// the top card while the keyboard or the mouse is in use, else the row
  /// the motion highlights (under the finger, or the one chosen).
  int? _lit(int card) {
    final motion = _motion;
    final focused = _zones.focusedZone;
    if (focused != null &&
        card == _built.top &&
        _current &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      return _targetOf(focused);
    }
    if (motion.highlightedCard != card) return null;
    final index = motion.highlighted;
    final targets = _built.layouts[card].targets;
    if (index == null || index >= targets.length) return null;
    // A tapped submenu row gives way to its card at once.
    return switch (targets[index].kind) {
      MenuTargetKind.back => null,
      MenuTargetKind.submenu when !motion.isSliding => null,
      _ => index,
    };
  }

  Widget _rowsOf(int card, MenuLayout layout, MenuAppearance style) {
    if (style != _rowsStyle) {
      _rows.clear();
      _rowsStyle = style;
    }
    final hidden = _built.hidden[card];
    final cached = _rows[layout];
    if (cached != null && cached.$1 == hidden) return cached.$2;
    final rows = RepaintBoundary(
      child: DefaultTextStyle(
        style: resolveGlassText(style.textStyle, context),
        child: MenuRows(
          layout: layout,
          style: style,
          hidden: hidden,
          content: _host._content,
        ),
      ),
    );
    _rows[layout] = (hidden, rows);
    return rows;
  }

  /// The highlight of [card], painted from the motion and the focus as they
  /// move: a row changing hands repaints it and rebuilds nothing.
  Widget _highlight(MenuLayout layout, MenuAppearance style, int card) =>
      Positioned.fill(
        child: CustomPaint(
          painter: _HighlightPainter(
            layer: this,
            card: card,
            layout: layout,
            color: style.highlightColor,
          ),
        ),
      );

  /// Where the highlight of [card] shows in its content, with its corner
  /// radius, or null for none.
  RRect? _highlightOf(int card, MenuLayout layout) {
    if (card >= _built.layouts.length) return null;
    final index = _lit(card);
    if (index == null || index >= layout.targets.length) return null;
    final target = layout.targets[index];
    final element = target.element < 0 ? null : layout.elements[target.element];
    final cell = switch (element?.kind) {
      MenuPlacedKind.palette ||
      MenuPlacedKind.small ||
      MenuPlacedKind.medium => true,
      _ => false,
    };
    const inset = MenuAppearance.highlightInset;
    final rect = cell
        ? target.rect
        : Rect.fromLTRB(
            target.rect.left + inset,
            target.rect.top,
            target.rect.right - inset,
            target.rect.bottom,
          );
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(
        cell
            ? MenuAppearance.cellHighlightRadius
            : math.min(rect.height / 2, _motion.rowHeight / 2),
      ),
    );
  }

  Widget _root(
    MenuLayout layout,
    MenuAppearance style, {
    required bool locked,
  }) {
    final content = SizedBox(
      width: _width,
      height: layout.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _highlight(layout, style, 0),
          _rowsOf(0, layout, style),
        ],
      ),
    );
    final body = _built.scrolls
        ? NotificationListener<ScrollNotification>(
            onNotification: _scrollStarted,
            child: RawScrollbar(
              controller: _scroll,
              thumbColor: style.secondaryColor,
              thickness: MenuAppearance.scrollThickness,
              radius: const Radius.circular(MenuAppearance.scrollThickness / 2),
              mainAxisMargin: _motion.cornerRadius / 2,
              crossAxisMargin: MenuAppearance.scrollInset,
              child: CustomScrollView(
                controller: _scroll,
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                slivers: [SliverToBoxAdapter(child: content)],
              ),
            ),
          )
        : OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: layout.height,
            maxHeight: layout.height,
            child: content,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        locked ? _motion.cornerRadius : 0,
      ),
      child: IgnorePointer(ignoring: locked, child: body),
    );
  }

  Widget _card(int index, MenuLayout layout, MenuAppearance style) {
    final width = _width;
    if (index == 0) {
      final locked = _built.layouts.length > 1;
      if (locked && !_parentLocked && _scroll.hasClients) {
        (_scroll.position as ScrollPositionWithSingleContext).goIdle();
      }
      _parentLocked = locked;
      return _driven(
        key: const ValueKey<int>(0),
        (motion) {
          final root = motion.cards[0];
          final s = root.scale;
          return menuPlacement(
            Rect.fromLTWH(
              width / 2 * (1 - s),
              0,
              width,
              motion.visibleRootHeight,
            ),
            Transform(
              alignment: Alignment.topLeft,
              transform: Matrix4.diagonal3Values(s, s, 1),
              child: Opacity(opacity: root.rowOpacity.clamp(0.0, 1.0)),
            ),
          );
        },
        child: _root(layout, style, locked: locked),
      );
    }
    // A card that has just gone keeps its last frame until the layer
    // builds without it: the render objects hear the tick first.
    var last = _motion.cards[index];
    MenuCard card() {
      final cards = _motion.cards;
      if (index < cards.length) last = cards[index];
      return last;
    }

    var lastShown = Rect.zero;
    MenuPlaced? header;
    for (final element in layout.elements) {
      if (element.kind == MenuPlacedKind.cardHeader) header = element;
    }
    double radius() => math.min(_motion.cornerRadius, card().rect.height / 2);
    return _driven(
      key: ValueKey<int>(index),
      (motion) {
        if (index < motion.cards.length) {
          lastShown = menuCardShown(
            motion.cards,
            index,
            width,
            motion.visibleRootHeight,
          );
        }
        final flex = motion.cardFlex(index);
        final center = lastShown.center + flex.shift;
        final now = card();
        final size = now.rect.size;
        final s = now.scale;
        return menuPlacement(
          Offset(
                center.dx - (lastShown.width + flex.width) / 2,
                center.dy - (lastShown.height + flex.height) / 2,
              ) &
              size,
          Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.diagonal3Values(
              s + flex.width / size.width,
              s + flex.height / size.height,
              1,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: _LiveGlassSurface(
              live: _frames,
              frameOf: () => GlassFrame(
                shape: GlassShape.roundedRect(radius()),
                glow: _motion.cardGlow(index),
                opacity: card().platterOpacity * _motion.cardMaterialOpacity,
              ),
            ),
          ),
          _driven(
            (_) => ClipRRect(
              clipper: MenuClip(
                RRect.fromRectAndRadius(
                  Offset.zero & card().rect.size,
                  Radius.circular(radius()),
                ),
              ),
            ),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: width,
              maxWidth: width,
              minHeight: layout.height,
              maxHeight: layout.height,
              child: _driven(
                (_) => Transform.translate(
                  offset: Offset(-card().rect.left, card().contentTop),
                ),
                child: SizedBox(
                  width: width,
                  height: layout.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _highlight(layout, style, index),
                      _driven((_) {
                        final now = card();
                        return Opacity(
                          opacity:
                              (now.rowsOpacity *
                                      now.rowOpacity *
                                      now.closeOpacity)
                                  .clamp(0.0, 1.0),
                        );
                      }, child: _rowsOf(index, layout, style)),
                      if (header != null)
                        _driven(
                          (_) {
                            final now = card();
                            return Opacity(
                              opacity: (now.rowOpacity * now.closeOpacity)
                                  .clamp(0.0, 1.0),
                            );
                          },
                          child: DefaultTextStyle(
                            style: resolveGlassText(style.textStyle, context),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                MenuCardHeader(
                                  frames: _frames,
                                  header: header,
                                  placed: () => index < _motion.cards.length
                                      ? menuCardHeaderAt(
                                          _motion.cards,
                                          index,
                                          header!,
                                        )
                                      : header!,
                                  values: () {
                                    final now = card();
                                    return (
                                      bold: now.headerBold.clamp(0.0, 1.0),
                                      turn: now.chevronTurn.clamp(0.0, 1.0),
                                      separator: now.platterOpacity.clamp(
                                        0.0,
                                        1.0,
                                      ),
                                    );
                                  },
                                  style: style,
                                  width: layout.width,
                                  content: _host._content,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  MotionDriven _driven(
    SingleChildRenderObjectWidget Function(MenuMotion motion) template, {
    Widget? child,
    Key? key,
  }) => menuDriven(_frames, template, child: child, key: key);

  // A blur too small to see costs a layer and shows nothing.
  static double _visible(double sigma) => sigma > 0.01 ? sigma : 0;

  late final _contentBlur = MotionSelection<double>(() {
    final motion = _frames.value;
    return _visible(motion.contentBlur / motion.contentScale);
  });

  late final _lookBlur = MotionSelection<double>(
    () => _visible(_frames.value.buttonLookBlur),
  );

  Matrix4 _contentTransform() {
    final motion = _motion;
    final scale = motion.contentScale;
    final stretch = motion.contentStretch;
    return Matrix4.diagonal3Values(scale * stretch.dx, scale * stretch.dy, 1);
  }

  Matrix4 _lookTransform() {
    final blob = _motion.buttonBlob;
    return Matrix4.diagonal3Values(
      blob.scale * _motion.buttonLookStretch,
      blob.scale,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final structure = _built;
    final motion = _motion;
    final style = _host._style;
    final layouts = structure.layouts;
    final top = layouts.length - 1;
    final under = top == 0 ? layouts.length : top;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        // A fade in a chain drops what it hides from screen readers, as
        // a transition's would not.
        _driven(
          (motion) => Opacity(
            opacity: motion.cardGlassTransferred
                ? 0
                : motion.contentOpacity.clamp(0.0, 1.0),
          ),
          child: MotionTransition(
            blur: _contentBlur,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < under; i++) _card(i, layouts[i], style),
              ],
            ),
          ),
        ),
        if (top > 0) _card(top, layouts[top], style),
      ],
    );
    final layer = InputZones<int>(
      zones: structure.open ? _zonesOf(layouts[structure.top]) : const [],
      frameOf: _frameOf,
      frames: _frames,
      controller: _zones,
      axis: null,
      stops: InputZoneStops.one,
      onEdge: _edge,
      excludeChildSemantics: false,
      interactions: [_input, _hover],
      hostFeedback: _MenuHost._feedback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._host._backdrop(this),
          IgnorePointer(
            child: _LiveGlassSurface(
              live: _frames,
              frameOf: () => _menuFrame(
                motion,
                sourceTint: _host._sourceTint,
                opacity: motion.glassOpacity,
              ),
            ),
          ),
          if (motion.drawsSource)
            IgnorePointer(
              child: _driven(
                (motion) => menuPlacement(
                  motion.buttonBlob.localRect,
                  Transform(
                    alignment: Alignment.center,
                    transform: _lookTransform(),
                    child: Opacity(
                      opacity: motion.buttonLookOpacity.clamp(0.0, 1.0),
                    ),
                  ),
                ),
                // A picture of the source, which screen readers read in its
                // place.
                child: ExcludeSemantics(
                  child: MotionTransition(
                    blur: _lookBlur,
                    child: Center(child: _host._look),
                  ),
                ),
              ),
            ),
          _driven(
            (motion) => ClipRRect(
              clipper: MenuClip(
                motion.cards.length < 2
                    ? motion.menuBlob.rrect
                    : RRect.fromRectAndRadius(Rect.largest, Radius.zero),
              ),
              child: menuPlacement(
                motion.contentRect.topLeft & motion.menuRect.size,
                Transform(
                  alignment: Alignment.topLeft,
                  transform: _contentTransform(),
                ),
              ),
            ),
            child: IgnorePointer(ignoring: !structure.open, child: content),
          ),
        ],
      ),
    );
    return Actions(
      actions: {DismissIntent: _MenuEscape(this)},
      child: Focus(
        focusNode: _host._menuFocus,
        includeSemantics: false,
        onFocusChange: _menuFocused,
        child: layer,
      ),
    );
  }
}
