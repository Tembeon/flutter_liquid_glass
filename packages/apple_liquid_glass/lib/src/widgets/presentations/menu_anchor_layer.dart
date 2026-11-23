part of 'menu_anchor.dart';

/// The open menu on the overlay: its glass, the source drawn live on it,
/// its rows and the submenu cards over them, each following the motion's
/// frames without a rebuild.
///
/// The targets of the top card are the zones of one host: one Tab stop,
/// whose arrows, Home and End move the focus among them, Space and Enter
/// choose, the arrow toward the trailing edge opens a submenu and the one
/// toward the leading edge or Escape goes back. The focused row is the
/// highlighted one; the mouse focuses the row it rests on. A finger slides
/// across the rows from a row, a header or a gap between sections: the row
/// under it lights, the one it lifts from is chosen, and a submenu row it
/// rests on opens its card. The motion follows that finger over the whole
/// menu for its stretch and glow: one that lands on the layer, and one its
/// source or the early capture hands on through the host's port once the
/// menu shows under it. Off the rows, where that finger lands and lifts
/// closes the menu or sends a submenu card back ([_OffRows]). A drag on a
/// root list taller than the menu scrolls it instead, and chooses nothing.
class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.host});

  final _MenuHost<StatefulWidget> host;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> implements MenuLayerScope {
  late final _scroll = MenuLayerScroll(this);
  final _ids = MenuZoneIds();
  late final _highlight = MenuLayerHighlight(this, zones: _zones, ids: _ids);
  late final _keys = MenuLayerKeys(
    this,
    zones: _zones,
    ids: _ids,
    scroll: _scroll,
  );
  late final _hover = MenuLayerHover(this, keys: _keys);
  late final _cards = MenuLayerCards(
    this,
    scroll: _scroll,
    highlight: _highlight,
  );
  final _zones = InputZonesController<int>();

  // A row's interactions by card, zone id and whether it opens a submenu:
  // new ones on another card end the touch on the old row.
  final Map<(int, int, bool), List<Interaction>> _rowInputs = {};
  late MenuLayerStructure _built;

  _MenuHost<StatefulWidget> get _host => widget.host;

  @override
  late final MotionSelection<MenuMotion> frames = _host._steps!;

  late final _follow = FollowInteraction(
    _FollowedTouch(
      onDown: _host._layerDown,
      onMove: _host._pointerMove,
      onUp: _host._pointerUp,
      onCancel: _host._pointerCancel,
    ),
    role: InteractionRole.content,
  );

  late final _offRows = _OffRows(_host);

  late final _hoverInput = _HoverInput(onHover: _hovered);

  @override
  MenuMotion get motion => _host._motion!;

  @override
  MenuLayerStructure get built => _built;

  @override
  MenuContent get content => _host._content;

  @override
  void command(
    void Function(MenuMotion motion, double t) command, {
    double? at,
  }) => _host._command(command, at: at);

  @override
  void initState() {
    super.initState();
    frames.addListener(_tick);
    _zones.addListener(_keys.focusMoved);
    _built = _structure();
  }

  @override
  void dispose() {
    frames.removeListener(_tick);
    _zones.removeListener(_keys.focusMoved);
    _zones.dispose();
    _scroll.dispose();
    super.dispose();
  }

  MenuLayerStructure _structure() {
    final cards = motion.cards;
    final root = cards[0].layout;
    return MenuLayerStructure(
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
    if (structure.top != _built.top) {
      _keys.cardChanged(structure.top);
      _hover.cardChanged();
    }
    setState(() => _built = structure);
  }

  @override
  bool get current => motion.isOpen && motion.topCard == _built.top;

  void _hovered(Offset local) => _hover.hovered(
    _host._local(
      (context.findRenderObject()! as RenderBox).localToGlobal(local),
    ),
  );

  List<Interaction> _inputsOf(int id, MenuTarget target) {
    final card = _built.top;
    final submenu = target.kind == MenuTargetKind.submenu;
    return _rowInputs.putIfAbsent(
      (card, id, submenu),
      () => [
        _HoverInput(onHover: (_) => _hover.rowEntered(id)),
        PressInteraction(
          role: InteractionRole.content,
          onHighlightChanged: (t, {required highlighted}) =>
              _rowPressed(card, id, t, highlighted: highlighted),
          onTap: (t) {
            if (_built.top != card) return;
            _keys.choose(_ids.targetOf(id), pending: -1, at: t);
          },
        ),
        if (submenu)
          DwellInteraction(
            duration: motion.tuning.hoverOpenDelay,
            hovers: false,
            onDwell: (t) {
              if (!current || _built.top != card) return;
              command(
                (motion, t) => motion.openCard(t, _ids.targetOf(id)),
                at: t,
              );
            },
          ),
      ],
    );
  }

  void _rowPressed(int card, int id, double t, {required bool highlighted}) {
    if (!current || _built.top != card) return;
    final index = _ids.targetOf(id);
    if (highlighted) {
      command((motion, t) => motion.highlight(t, index), at: t);
    } else if (motion.highlighted == index && motion.highlightedCard == card) {
      command((motion, t) => motion.highlight(t, null), at: t);
    }
  }

  int? _zoneAt(Offset position) {
    if (!_host._rowsTake) return null;
    final row = motion.rowAt(position);
    return row == null ? null : _ids.idOf(row);
  }

  static MotionHaptic? _feedback(int id, InteractionEvent event) =>
      switch (event) {
        ScrubChangeEvent() => MotionHaptic.selection,
        _ => null,
      };

  MotionDriven _driven(
    SingleChildRenderObjectWidget Function(MenuMotion motion) template, {
    Widget? child,
    Key? key,
  }) => menuDriven(frames, template, child: child, key: key);

  // A blur too small to see costs a layer and shows nothing.
  static double _visible(double sigma) => sigma > 0.01 ? sigma : 0;

  late final _contentBlur = MotionSelection<double>(() {
    final motion = frames.value;
    return _visible(motion.contentBlur / motion.contentScale);
  });

  late final _lookBlur = MotionSelection<double>(
    () => _visible(frames.value.buttonLookBlur),
  );

  Matrix4 _contentTransform() {
    final scale = motion.contentScale;
    final stretch = motion.contentStretch;
    return Matrix4.diagonal3Values(scale * stretch.dx, scale * stretch.dy, 1);
  }

  Matrix4 _lookTransform() {
    final blob = motion.buttonBlob;
    return Matrix4.diagonal3Values(
      blob.scale * motion.buttonLookStretch,
      blob.scale,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final structure = _built;
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
                for (var i = 0; i < under; i++)
                  _cards.card(i, layouts[i], style),
              ],
            ),
          ),
        ),
        if (top > 0) _cards.card(top, layouts[top], style),
      ],
    );
    final layer = InputZones<int>(
      zones: structure.open
          ? _keys.zonesOf(layouts[structure.top], _inputsOf)
          : const [],
      frameOf: _keys.frameOf,
      frames: frames,
      controller: _zones,
      port: _host._port,
      slides: true,
      slidesFrom: (position) => motion.areaAt(position) == MenuArea.list,
      zoneAt: _zoneAt,
      feedback: _feedback,
      arrows: InputZoneArrows.grid,
      stops: InputZoneStops.one,
      onEdge: _keys.edge,
      excludeChildSemantics: false,
      interactions: [_follow, _offRows, _hoverInput],
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._host._backdrop(this),
          IgnorePointer(
            child: MenuLiveGlass(
              live: frames,
              frameOf: () => menuFrame(
                motion,
                sourceTint: _host._sourceTint,
                drawsSourceWhole: _host._drawsSourceWhole,
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
                // The source, which screen readers read in its place.
                child: ExcludeSemantics(
                  child: MotionTransition(
                    blur: _lookBlur,
                    child: switch (_host._sourceLook) {
                      final look? => Center(child: look),
                      null => _SourceMirror(host: _host),
                    },
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
        child: _SourceFollower(host: _host, child: layer),
      ),
    );
  }
}

/// Tells the host's motion where the source stands, in every frame's
/// resolve phase while the menu shows.
class _SourceFollower extends SingleChildRenderObjectWidget {
  const _SourceFollower({required this.host, super.child});

  final _MenuHost<StatefulWidget> host;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSourceFollower(host);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSourceFollower renderObject,
  ) => renderObject.host = host;
}

class _RenderSourceFollower extends RenderProxyBox with MotionResolveHost {
  _RenderSourceFollower(this.host);

  _MenuHost<StatefulWidget> host;

  @override
  bool get resolvesEveryFrame => true;

  @override
  void resolve() => host._followSource();
}

/// The source's content as it is now, drawn where it stands in the source,
/// in a box of the source's size: its own layer, which leaves the hidden
/// source for the menu's while the menu holds the source.
class _SourceMirror extends LeafRenderObjectWidget {
  const _SourceMirror({required this.host});

  final _MenuHost<StatefulWidget> host;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSourceMirror(host);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSourceMirror renderObject,
  ) => renderObject.host = host;
}

class _RenderSourceMirror extends RenderBox {
  _RenderSourceMirror(this.host);

  _MenuHost<StatefulWidget> host;

  final _transform = LayerHandle<TransformLayer>();

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final content = host._sourceContent();
    final overlay = host._overlayBox;
    final motion = host._motion;
    if (content == null ||
        overlay == null ||
        motion == null ||
        !host._source.isHidden) {
      _transform.layer = null;
      return;
    }
    host._mirrored = content;
    _transform.layer = context.pushTransform(
      true,
      offset - motion.source.shape.topLeft,
      content.getTransformTo(overlay),
      (context, offset) => context.paintChild(content, offset),
      oldLayer: _transform.layer,
    );
  }

  @override
  void dispose() {
    _transform.layer = null;
    super.dispose();
  }
}
