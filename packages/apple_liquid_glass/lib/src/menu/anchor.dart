import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/src/menu/appearance.dart';
import 'package:apple_liquid_glass/src/menu/content.dart';
import 'package:apple_liquid_glass/src/menu/entries.dart';
import 'package:apple_liquid_glass/src/menu/fusion.dart';
import 'package:apple_liquid_glass/src/menu/layout.dart';
import 'package:apple_liquid_glass/src/menu/motion.dart';
import 'package:apple_liquid_glass/src/menu/outline_math.dart';
import 'package:apple_liquid_glass/src/menu/rows.dart';
import 'package:apple_liquid_glass/src/motion/live.dart';
import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Opens and closes the menu of a glass button from code.
///
/// Flutter: `MenuController`.
class GlassMenuController {
  _MenuAnchorState? _anchor;

  /// Whether the menu shows or is on its way to showing.
  bool get isOpen => _anchor?._isOpen ?? false;

  /// Opens the menu.
  void open() => _anchor?._openFromCode();

  /// Closes the menu.
  void close() => _anchor?._close();
}

/// What opens a menu from its source.
@internal
enum MenuTrigger {
  /// A tap opens the menu on its release, a hold on the measured hold.
  tap,

  /// Only a hold opens the menu; a tap calls the source's own action.
  hold,
}

/// A source whose glass grows into its menu, as a `UIButton` with a menu
/// does on iOS 27.
///
/// The menu shows on the root overlay without a route, so a finger that
/// pressed the source keeps sliding over the open menu and chooses the
/// row it lifts from. Escape and Back close it; a tap outside closes it
/// without reaching what lies under it.
@internal
class MenuAnchor extends StatefulWidget {
  /// Creates the menu source drawn as [face].
  const MenuAnchor({
    required this.entries,
    required this.face,
    required this.look,
    this.sourceRadius,
    this.trigger = MenuTrigger.tap,
    this.onTap,
    this.enabled = true,
    this.controller,
    this.semanticLabel,
    this.order = GlassMenuOrder.automatic,
    this.tuning = MenuTuning.standard,
    super.key,
  });

  /// The menu's entries.
  final List<GlassMenuEntry> entries;

  /// The source at rest, glass included.
  final Widget face;

  /// The source's label or glyph, drawn on the glass while it grows into
  /// the menu.
  final Widget look;

  /// The corner radius of the source's glass at rest; null for a capsule.
  final double? sourceRadius;

  /// What opens the menu.
  final MenuTrigger trigger;

  /// Called on a tap of a [MenuTrigger.hold] source.
  final VoidCallback? onTap;

  /// Whether the source takes touches.
  final bool enabled;

  /// Opens and closes the menu from code.
  final GlassMenuController? controller;

  /// What accessibility reads for the source.
  final String? semanticLabel;

  /// How the rows order in a menu that opens upward.
  final GlassMenuOrder order;

  /// The measured behavior of the menu.
  final MenuTuning tuning;

  @override
  State<MenuAnchor> createState() => _MenuAnchorState();
}

/// The menu's progress, which shows the overlay when the menu opens.
class _ShowingProgress extends MenuProgress {
  _ShowingProgress(MenuTuning tuning, {required this.onOpen})
    : _spring = MenuProgress.spring(tuning);

  final VoidCallback onOpen;
  final MenuProgress _spring;

  @override
  double valueAt(double t) => _spring.valueAt(t);

  @override
  bool restsWithin(double t, double rest) => _spring.restsWithin(t, rest);

  @override
  void open(double t) {
    _spring.open(t);
    onOpen();
  }

  @override
  void close(double t) => _spring.close(t);
}

class _MenuAnchorState extends State<MenuAnchor> implements MotionDriver {
  final _portal = OverlayPortalController(debugLabel: 'glass menu');
  late final _content = MenuContent(onChanged: _contentChanged);
  final _frames = ValueNotifier<int>(0);
  final _showing = ValueNotifier<bool>(false);
  MenuMotion? _motion;
  OverlayState? _overlay;
  MenuAppearance _style = MenuAppearance.light;
  int? _pointer;
  int? _early;
  bool _routing = false;
  bool _delivering = false;

  double get _now => MotionClock.instance.now;

  bool get _isOpen => _motion?.isOpen ?? false;

  @override
  void initState() {
    super.initState();
    widget.controller?._anchor = this;
    _content.entries = widget.entries;
    _content.order = widget.order;
    MotionClock.instance.addDriver(this);
  }

  @override
  void didUpdateWidget(MenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (identical(oldWidget.controller?._anchor, this)) {
        oldWidget.controller?._anchor = null;
      }
      widget.controller?._anchor = this;
    }
    final changed =
        !identical(widget.entries, _content.entries) ||
        widget.order != _content.order;
    _content.entries = widget.entries;
    _content.order = widget.order;
    if (changed) _contentChanged(animate: true);
    if (oldWidget.enabled && !widget.enabled) _close();
  }

  @override
  void dispose() {
    if (identical(widget.controller?._anchor, this)) {
      widget.controller?._anchor = null;
    }
    _unroute();
    MotionClock.instance.removeDriver(this);
    _content.dispose();
    _frames.dispose();
    _showing.dispose();
    super.dispose();
  }

  // The motion clock.

  @override
  bool get isActive => !(_motion?.isSettled ?? true);

  @override
  double? get wakeTime => _motion?.wakeTime;

  @override
  void step(double time) {
    final motion = _motion;
    if (motion == null) return;
    motion.frameTime = time;
    motion.framePeriod = MotionClock.instance.framePeriod;
    _reach(motion, math.max(time, motion.time));
    if (motion.isSettled) motion.settle();
    if (_early == null && !motion.isOpenPending) _unroute();
    _frames.value++;
    if (!motion.isPresented && motion.isSettled && _showing.value) {
      _portal.hide();
      _showing.value = false;
      if (mounted) setState(() {});
    }
  }

  void _wake() => MotionClock.instance.wake(this);

  // Commands and events.

  void _command(
    void Function(MenuMotion motion, double t) command, {
    double? at,
  }) {
    final motion = _motion;
    if (motion == null) return;
    final t = at ?? _now;
    _reach(motion, t);
    command(motion, t);
    _deliver(motion);
    _wake();
  }

  void _reach(MenuMotion motion, double t) {
    while (!motion.advanceToRequest(t)) {
      _deliver(motion);
    }
    _deliver(motion);
  }

  // Events a callback raises while others are delivered follow them, in
  // order, instead of interrupting them.
  void _deliver(MenuMotion motion) {
    if (_delivering) return;
    _delivering = true;
    try {
      for (
        var events = motion.drainEvents();
        events.isNotEmpty;
        events = motion.drainEvents()
      ) {
        for (final event in events) {
          _receive(motion, event);
        }
      }
    } finally {
      _delivering = false;
    }
  }

  void _receive(MenuMotion motion, MenuEvent event) {
    switch (event) {
      case MenuHighlightChanged(:final from, :final to, :final tracked):
        _content.highlight(from, to);
        if (tracked) unawaited(HapticFeedback.selectionClick());
      case MenuActivated(:final target):
        _content.activate(target);
      case MenuTapped():
        if (widget.enabled) widget.onTap?.call();
      case MenuCloseRequested():
        if (!motion.admitClose(event) && motion.isOpen) {
          motion.close(math.max(_now, motion.time));
        }
    }
  }

  void _contentChanged({required bool animate}) {
    final motion = _motion;
    if (motion == null || !(motion.isPresented || motion.isArming)) return;
    final animated = animate && motion.isPresented;
    _command((motion, t) => motion.updateLayout(t, animate: animated));
  }

  // Opening.

  MenuMotion _prepare() {
    final current = _motion;
    if (current != null && current.isPresented) {
      if (current.isClosing) {
        _content.beginSession();
        _contentChanged(animate: true);
      }
      return current;
    }
    final overlay = _overlay = Overlay.of(context, rootOverlay: true);
    final box = context.findRenderObject()! as RenderBox;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final button =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    final media = MediaQuery.of(context);
    final padding = media.padding.copyWith(
      bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    _content.rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _content.titleStyle = resolveGlassText(_style.textStyle, context);
    _content.textScaler = MediaQuery.textScalerOf(context);
    _content.beginSession();
    final MenuMotion motion;
    if (current != null && identical(current.tuning, widget.tuning)) {
      current.relayout(
        button: button,
        bounds: overlayBox.size,
        padding: padding,
        sourceRadius: widget.sourceRadius,
      );
      motion = current;
    } else {
      motion = MenuMotion(
        button: button,
        layout: _content.root,
        bounds: overlayBox.size,
        padding: padding,
        sourceRadius: widget.sourceRadius,
        tuning: widget.tuning,
        progress: _ShowingProgress(widget.tuning, onOpen: _show),
      );
      motion.submenuLayout = _content.submenu;
      motion.advance(_now);
      _motion = motion;
    }
    motion.lightsGlow =
        GlassTheme.rendererOf(context) is! FlatGlassRenderer &&
        !GlassTraits.of(context).reduceTransparency;
    motion.opensOnTap = widget.trigger == MenuTrigger.tap;
    return motion;
  }

  void _show() {
    if (!mounted || _showing.value) return;
    _showing.value = true;
    _portal.show();
    setState(() {});
  }

  void _openFromCode() {
    if (!mounted || !widget.enabled || _isOpen) return;
    _prepare();
    _command((motion, t) => motion.open(t));
  }

  void _close() {
    final motion = _motion;
    if (motion == null) return;
    _command((motion, t) => motion.close(t), at: math.max(_now, motion.time));
  }

  Offset _local(Offset global) {
    final box = _overlay?.context.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  double _stamp(PointerEvent event) =>
      MotionClock.instance.stamp(event.timeStamp);

  // Touches of the source and of the open menu.

  void _sourceDown(PointerDownEvent event) {
    if (!widget.enabled ||
        event.buttons != kPrimaryButton ||
        _pointer != null ||
        _isOpen) {
      return;
    }
    _prepare();
    _pointerDown(event);
  }

  void _pointerDown(PointerDownEvent event) {
    if (_motion == null ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    final local = _local(event.position);
    _command((motion, t) => motion.pointerDown(t, local), at: _stamp(event));
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final local = _local(event.position);
    _command((motion, t) => motion.pointerMove(t, local), at: _stamp(event));
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final motion = _motion;
    if (motion == null) return;
    final local = _local(event.position);
    _command((motion, t) => motion.pointerUp(t, local), at: _stamp(event));
    if (motion.isOpenPending) _route();
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _command((motion, t) => motion.pointerCancel(t), at: _stamp(event));
  }

  // A touch made between a tap's release and the menu's opening belongs
  // to the menu, as UIKit's does.
  void _route() {
    if (_routing) return;
    _routing = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_earlyEvent);
  }

  void _unroute() {
    if (!_routing) return;
    _routing = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_earlyEvent);
  }

  void _earlyEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (!(_motion?.isOpenPending ?? false) ||
          _pointer != null ||
          event.buttons != kPrimaryButton) {
        return;
      }
      _early = event.pointer;
      _pointerDown(event);
    } else if (event.pointer == _early) {
      switch (event) {
        case PointerMoveEvent():
          _pointerMove(event);
        case PointerUpEvent():
          _early = null;
          _pointerUp(event);
        case PointerCancelEvent():
          _early = null;
          _pointerCancel(event);
        default:
      }
    }
  }

  void _activate() {
    if (!widget.enabled) return;
    if (widget.trigger == MenuTrigger.hold) {
      widget.onTap?.call();
    } else {
      _openFromCode();
    }
  }

  Matrix4 _pressTransform() {
    final box = context.findRenderObject();
    final motion = _motion;
    if (motion == null || box is! RenderBox || !box.hasSize) {
      return Matrix4.identity();
    }
    final s = motion.isPresented ? 1.0 : motion.pressScale;
    return Matrix4.diagonal3Values(s, s, 1);
  }

  @override
  Widget build(BuildContext context) {
    _style = MenuAppearance.resolve(context);
    final presented = _showing.value;
    final enabled = widget.enabled;
    final hold = widget.trigger == MenuTrigger.hold;
    return PopScope<Object?>(
      canPop: !presented,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayLocation: OverlayChildLocation.rootOverlay,
        overlayChildBuilder: (context) => _MenuLayer(anchor: this),
        child: FocusableActionDetector(
          enabled: enabled,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: Semantics(
            button: true,
            enabled: enabled,
            expanded: presented,
            label: widget.semanticLabel,
            excludeSemantics: widget.semanticLabel != null,
            onTap: enabled ? _activate : null,
            onLongPress: enabled && hold ? _openFromCode : null,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _sourceDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerCancel,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showing,
                child: LiveTransform(
                  live: _frames,
                  matrixOf: _pressTransform,
                  child: widget.face,
                ),
                builder: (context, showing, face) =>
                    Visibility.maintain(visible: !showing, child: face!),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the layer's tree is built from; it builds only when this changes.
@immutable
class _Structure {
  const _Structure({
    required this.layouts,
    required this.open,
    required this.scrolls,
    required this.highlighted,
    required this.highlightedCard,
    required this.sliding,
  });

  final List<MenuLayout> layouts;
  final bool open;
  final bool scrolls;
  final int? highlighted;
  final int highlightedCard;
  final bool sliding;

  @override
  bool operator ==(Object other) {
    if (other is! _Structure ||
        other.open != open ||
        other.scrolls != scrolls ||
        other.highlighted != highlighted ||
        other.highlightedCard != highlightedCard ||
        other.sliding != sliding ||
        other.layouts.length != layouts.length) {
      return false;
    }
    for (var i = 0; i < layouts.length; i++) {
      if (!identical(other.layouts[i], layouts[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    open,
    scrolls,
    highlighted,
    highlightedCard,
    sliding,
    layouts.length,
  );
}

/// The open menu on the overlay: its glass, the source's look on it, its
/// rows and the submenu cards over them, each following the motion's
/// frames without a rebuild.
class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.anchor});

  final _MenuAnchorState anchor;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  final _scroll = ScrollController();
  final Map<MenuLayout, ValueNotifier<int?>> _hidden = Map.identity();
  final Map<MenuLayout, Widget> _rows = Map.identity();
  MenuAppearance? _rowsStyle;
  _Structure? _built;
  bool _parentLocked = false;
  final _focus = FocusNode(debugLabel: 'glass menu');
  FocusNode? _restore;

  _MenuAnchorState get _anchor => widget.anchor;

  ValueListenable<int> get _frames => _anchor._frames;

  MenuMotion get _motion => _anchor._motion!;

  double get _width => _motion.tuning.menuWidth;

  @override
  void initState() {
    super.initState();
    _frames.addListener(_tick);
    _scroll.addListener(_scrolled);
    _built = _structure();
    // The menu takes the keyboard while it shows, as a presentation's
    // focus scope does, and hands it back when it goes.
    _restore = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    final restore = _restore;
    if (_focus.hasFocus && restore != null && restore.context != null) {
      restore.requestFocus();
    }
    _focus.dispose();
    _frames.removeListener(_tick);
    _scroll.dispose();
    for (final hidden in _hidden.values) {
      hidden.dispose();
    }
    super.dispose();
  }

  _Structure? _structure() {
    final motion = _anchor._motion;
    if (motion == null) return null;
    final cards = motion.cards;
    for (var i = 0; i < cards.length; i++) {
      _hiddenOf(cards[i].layout).value = i + 1 < cards.length
          ? cards[i + 1].source
          : null;
    }
    final root = cards.isEmpty ? motion.layout : cards[0].layout;
    return _Structure(
      layouts: [for (final card in cards) card.layout],
      open: motion.isOpen,
      scrolls: root.height > motion.visibleRootHeight + 0.5,
      highlighted: motion.highlighted,
      highlightedCard: motion.highlightedCard,
      sliding: motion.isSliding,
    );
  }

  void _tick() {
    final structure = _structure();
    if (structure == _built) return;
    setState(() => _built = structure);
  }

  ValueNotifier<int?> _hiddenOf(MenuLayout layout) =>
      _hidden.putIfAbsent(layout, () => ValueNotifier<int?>(null));

  void _scrolled() {
    final motion = _anchor._motion;
    if (motion == null || !_scroll.hasClients) return;
    motion.scrollOffset = _scroll.offset;
  }

  bool _scrollStarted(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _scrollGesture();
    }
    return false;
  }

  void _scrollGesture() =>
      _anchor._command((motion, t) => motion.pointerScrolled(t));

  void _select(MenuLayout layout, int target) {
    final motion = _anchor._motion;
    if (motion == null || !motion.isOpen) return;
    if (!identical(motion.cards[motion.topCard].layout, layout)) return;
    _anchor._command((motion, t) => motion.select(t, target));
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final motion = _anchor._motion;
    if (motion == null || !motion.isOpen) return KeyEventResult.ignored;
    final top = motion.topCard;
    final layout = motion.cards[top].layout;
    final order = [for (var i = 0; i < layout.targets.length; i++) i];
    order.sort((a, b) {
      final ra = layout.targets[a].rect;
      final rb = layout.targets[b].rect;
      final dy = ra.top.compareTo(rb.top);
      return dy != 0 ? dy : ra.left.compareTo(rb.left);
    });
    final current = motion.highlightedCard == top ? motion.highlighted : null;
    final rtl = _anchor._content.rtl;
    final key = event.logicalKey;
    void move(int step) {
      if (order.isEmpty) return;
      final at = current == null ? -1 : order.indexOf(current);
      final next = at < 0
          ? (step > 0 ? 0 : order.length - 1)
          : (at + step).clamp(0, order.length - 1);
      _anchor._command((motion, t) => motion.highlight(t, order[next]));
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move(-1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (current == null) return KeyEventResult.ignored;
      _anchor._command((motion, t) => motion.select(t, current));
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      if (current == null ||
          layout.targets[current].kind != MenuTargetKind.submenu) {
        return KeyEventResult.ignored;
      }
      _anchor._command((motion, t) => motion.select(t, current));
    } else if (key == LogicalKeyboardKey.escape ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)) {
      var back = false;
      _anchor._command((motion, t) => back = motion.back(t));

      if (!back) {
        if (key != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
        _anchor._close();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _rowsOf(MenuLayout layout, MenuAppearance style) {
    if (!identical(style, _rowsStyle)) {
      _rows.clear();
      _rowsStyle = style;
    }
    return _rows[layout] ??= RepaintBoundary(
      child: DefaultTextStyle(
        style: resolveGlassText(style.textStyle, context),
        child: MenuRows(
          layout: layout,
          style: style,
          hidden: _hiddenOf(layout),
          content: _anchor._content,
          onSelect: (target) => _select(layout, target),
        ),
      ),
    );
  }

  Widget? _highlight(MenuLayout layout, MenuAppearance style, int card) {
    final structure = _built!;
    final index = structure.highlighted;
    if (index == null || structure.highlightedCard != card) return null;
    if (index >= layout.targets.length) return null;
    final target = layout.targets[index];
    if (target.kind == MenuTargetKind.back) return null;
    if (target.kind == MenuTargetKind.submenu && !structure.sliding) {
      return null;
    }
    final element = target.element < 0 ? null : layout.elements[target.element];
    final cell = switch (element?.kind) {
      MenuPlacedKind.palette ||
      MenuPlacedKind.small ||
      MenuPlacedKind.medium => true,
      _ => false,
    };
    final inset = _motion.tuning.highlightInset;
    final rect = cell
        ? target.rect
        : Rect.fromLTRB(
            target.rect.left + inset,
            target.rect.top,
            target.rect.right - inset,
            target.rect.bottom,
          );
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.highlightColor,
          borderRadius: BorderRadius.circular(
            cell
                ? MenuTuning.cellHighlightRadius
                : math.min(rect.height / 2, _motion.tuning.rowHeight / 2),
          ),
        ),
      ),
    );
  }

  /// The frame card [index] shows at in the content, scale included, with
  /// the root list [visible] high.
  static Rect _shown(
    List<MenuCard> cards,
    int index,
    double width,
    double visible,
  ) {
    final card = cards[index];
    final s = card.scale;
    final rect = index == 0 ? Rect.fromLTWH(0, 0, width, visible) : card.rect;
    return Rect.fromLTWH(
      width / 2 + (rect.left - width / 2) * s,
      rect.top * s,
      rect.width * s,
      rect.height * s,
    );
  }

  /// Card [index]'s header now: its columns move from those of the row it
  /// grew out of, scaled by the parent's scale, to its own.
  static MenuPlaced _headerAt(
    List<MenuCard> cards,
    int index,
    MenuPlaced header,
  ) {
    final card = cards[index];
    final parent = cards[index - 1];
    final source = card.source;
    if (source == null || source >= parent.layout.targets.length) return header;
    final target = parent.layout.targets[source];
    if (target.element < 0) return header;
    final row = parent.layout.elements[target.element];
    final ratio = parent.scale / card.scale;
    final center = card.layout.width / 2;
    final q = card.progress.clamp(0.0, 1.0);
    double column(double source) {
      final from = center + (source - center) * ratio;
      return from + (source - from) * q;
    }

    final image = row.imageCenter;
    return MenuPlaced(
      kind: header.kind,
      rect: header.rect,
      entry: header.entry,
      title: header.title,
      imageCenter: image == null || header.imageCenter == null
          ? header.imageCenter
          : column(image),
      titleStart: column(row.titleStart),
      titleEnd: column(row.titleEnd),
      target: header.target,
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
        children: [?_highlight(layout, style, 0), _rowsOf(layout, style)],
      ),
    );
    final body = _built!.scrolls
        ? NotificationListener<ScrollNotification>(
            onNotification: _scrollStarted,
            child: RawScrollbar(
              controller: _scroll,
              thumbColor: style.secondaryColor,
              thickness: MenuTuning.scrollThickness,
              radius: const Radius.circular(MenuTuning.scrollThickness / 2),
              mainAxisMargin: _motion.tuning.cornerRadius / 2,
              crossAxisMargin: MenuTuning.scrollInset,
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
        locked ? _motion.tuning.cornerRadius : 0,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: locked ? (_) => _scrollGesture() : null,
        child: IgnorePointer(ignoring: locked, child: body),
      ),
    );
  }

  Widget _card(int index, MenuLayout layout, MenuAppearance style) {
    final width = _width;
    if (index == 0) {
      final locked = _built!.layouts.length > 1;
      if (locked && !_parentLocked && _scroll.hasClients) {
        (_scroll.position as ScrollPositionWithSingleContext).goIdle();
      }
      _parentLocked = locked;
      return LivePlacement(
        key: const ValueKey<int>(0),
        live: _frames,
        rectOf: () {
          final motion = _motion;
          final s = motion.cards.isEmpty ? 1.0 : motion.cards[0].scale;
          return Rect.fromLTWH(
            width / 2 * (1 - s),
            0,
            width,
            motion.visibleRootHeight,
          );
        },
        child: LiveTransform(
          live: _frames,
          alignment: Alignment.topLeft,
          matrixOf: () {
            final cards = _motion.cards;
            final s = cards.isEmpty ? 1.0 : cards[0].scale;
            return Matrix4.diagonal3Values(s, s, 1);
          },
          child: LiveFade(
            live: _frames,
            opacityOf: () {
              final cards = _motion.cards;
              return cards.isEmpty ? 1 : cards[0].rowOpacity;
            },
            child: _root(layout, style, locked: locked),
          ),
        ),
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
    double radius() =>
        math.min(_motion.tuning.cornerRadius, card().rect.height / 2);
    return LivePlacement(
      key: ValueKey<int>(index),
      live: _frames,
      rectOf: () {
        final motion = _motion;
        if (index < motion.cards.length) {
          lastShown = _shown(
            motion.cards,
            index,
            width,
            motion.visibleRootHeight,
          );
        }
        return lastShown.topLeft & card().rect.size;
      },
      child: LiveTransform(
        live: _frames,
        alignment: Alignment.topLeft,
        matrixOf: () {
          final s = card().scale;
          return Matrix4.diagonal3Values(s, s, 1);
        },
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(
              child: _CardGlass(
                frames: _frames,
                frameOf: () => GlassFrame(
                  shape: LiquidRoundedRectangle(borderRadius: radius()),
                  opacity: card().platterOpacity * _motion.cardMaterialOpacity,
                ),
              ),
            ),
            LiveClipRRect(
              live: _frames,
              rrectOf: () => RRect.fromRectAndRadius(
                Offset.zero & card().rect.size,
                Radius.circular(radius()),
              ),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: width,
                maxWidth: width,
                minHeight: layout.height,
                maxHeight: layout.height,
                child: LiveShift(
                  live: _frames,
                  offsetOf: () => Offset(-card().rect.left, card().contentTop),
                  child: SizedBox(
                    width: width,
                    height: layout.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ?_highlight(layout, style, index),
                        LiveFade(
                          live: _frames,
                          opacityOf: () {
                            final now = card();
                            return now.rowsOpacity *
                                now.rowOpacity *
                                now.closeOpacity;
                          },
                          child: _rowsOf(layout, style),
                        ),
                        if (header != null)
                          LiveFade(
                            live: _frames,
                            opacityOf: () {
                              final now = card();
                              return now.rowOpacity * now.closeOpacity;
                            },
                            child: DefaultTextStyle(
                              style: resolveGlassText(style.textStyle, context),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  MenuCardHeader(
                                    live: _frames,
                                    header: header,
                                    placed: () => index < _motion.cards.length
                                        ? _headerAt(
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
                                    content: _anchor._content,
                                    onSelect: (target) =>
                                        _select(layout, target),
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
      ),
    );
  }

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
    final motion = _anchor._motion;
    if (structure == null || motion == null || structure.layouts.isEmpty) {
      return const SizedBox.shrink();
    }
    final style = _anchor._style;
    final shaded = GlassTheme.rendererOf(context) is! FlatGlassRenderer;
    final layouts = structure.layouts;
    final top = layouts.length - 1;
    final under = top == 0 ? layouts.length : top;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        LiveFade(
          live: _frames,
          opacityOf: () =>
              _motion.cardGlassTransferred ? 0 : _motion.contentOpacity,
          child: _LiveBlur(
            live: _frames,
            sigmaOf: () => _motion.contentBlur / _motion.contentScale,
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
    final layer = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _anchor._pointerDown,
      onPointerMove: _anchor._pointerMove,
      onPointerUp: _anchor._pointerUp,
      onPointerCancel: _anchor._pointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: _MenuGlass(frames: _frames, motion: motion, shaded: shaded),
          ),
          if (motion.drawsSource)
            IgnorePointer(
              child: LivePlacement(
                live: _frames,
                rectOf: () => _motion.buttonBlob.localRect,
                child: LiveTransform(
                  live: _frames,
                  matrixOf: _lookTransform,
                  child: LiveFade(
                    live: _frames,
                    opacityOf: () => _motion.buttonLookOpacity,
                    child: _LiveBlur(
                      live: _frames,
                      sigmaOf: () => _motion.buttonLookBlur,
                      child: Center(child: _anchor.widget.look),
                    ),
                  ),
                ),
              ),
            ),
          LiveClipRRect(
            live: _frames,
            rrectOf: () => _motion.cards.length < 2
                ? _motion.menuBlob.rrect
                : RRect.fromRectAndRadius(Rect.largest, Radius.zero),
            child: LivePlacement(
              live: _frames,
              rectOf: () => _motion.contentRect.topLeft & _motion.menuRect.size,
              child: LiveTransform(
                live: _frames,
                alignment: Alignment.topLeft,
                matrixOf: _contentTransform,
                child: IgnorePointer(ignoring: !structure.open, child: content),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: ui.SemanticsRole.menu,
      label: _anchor.widget.semanticLabel,
      onDismiss: _anchor._close,
      child: BlockSemantics(
        child: Focus(focusNode: _focus, onKeyEvent: _key, child: layer),
      ),
    );
  }
}

/// A submenu card's glass, its frame read again on every tick of
/// [frames].
class _CardGlass extends StatefulWidget {
  const _CardGlass({required this.frames, required this.frameOf});

  final ValueListenable<int> frames;
  final GlassFrame Function() frameOf;

  @override
  State<_CardGlass> createState() => _CardGlassState();
}

class _CardGlassState extends State<_CardGlass> {
  late final _frame = ValueNotifier(widget.frameOf());

  void _changed() => _frame.value = widget.frameOf();

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_changed);
  }

  @override
  void didUpdateWidget(_CardGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames) {
      oldWidget.frames.removeListener(_changed);
      widget.frames.addListener(_changed);
    }
    _changed();
  }

  @override
  void dispose() {
    widget.frames.removeListener(_changed);
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassSurface.live(
    role: GlassRole.menu,
    frame: _frame,
    child: const SizedBox.expand(),
  );
}

/// The glass of an open menu: one body that is the menu and the source
/// fused while the fusion runs, their union on either side of it, and the
/// menu's own rounded box once the source is inside it.
class _MenuGlass extends StatefulWidget {
  const _MenuGlass({
    required this.frames,
    required this.motion,
    required this.shaded,
  });

  final ValueListenable<int> frames;
  final MenuMotion motion;

  /// Whether the renderer shades outlines from their field.
  final bool shaded;

  @override
  State<_MenuGlass> createState() => _MenuGlassState();
}

class _MenuGlassState extends State<_MenuGlass> {
  late final _frame = ValueNotifier(_frameNow());

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_changed);
  }

  @override
  void didUpdateWidget(_MenuGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames) {
      oldWidget.frames.removeListener(_changed);
      widget.frames.addListener(_changed);
    }
    _changed();
  }

  @override
  void dispose() {
    widget.frames.removeListener(_changed);
    _frame.dispose();
    super.dispose();
  }

  void _changed() => _frame.value = _frameNow();

  static bool _inside(RRect outer, RRect inner) {
    final corner = outer.tlRadiusX * (1 - math.sqrt1_2);
    return outer.outerRect.deflate(corner).contains(inner.outerRect.topLeft) &&
        outer.outerRect.deflate(corner).contains(inner.outerRect.bottomRight);
  }

  GlassFrame _frameNow() {
    final motion = widget.motion;
    final glow = motion.touchGlow;
    final root = motion.rootBlob.rrect;
    if (motion.fusionRadius >= MenuFusion.minimumRadius) {
      return GlassFrame(
        outline: motion.silhouetteFor(withField: widget.shaded),
        glow: glow,
      );
    }
    final source = motion.drawsSource ? motion.buttonBlob.rrect : null;
    if (source == null || _inside(root, source)) {
      return GlassFrame(
        shape: LiquidRoundedRectangle(borderRadius: root.tlRadiusX),
        rect: root.outerRect,
        glow: glow,
      );
    }
    final shapes = [root, source];
    return GlassFrame(
      outline: widget.shaded
          ? unionFieldOutline(shapes)
          : plainUnionOutline(shapes),
      glow: glow,
    );
  }

  @override
  Widget build(BuildContext context) => GlassSurface.live(
    role: GlassRole.menu,
    frame: _frame,
    child: const SizedBox.expand(),
  );
}

/// Blurs its child by [sigmaOf], read again on every notification of
/// [live]; no layer while the blur is too small to see.
class _LiveBlur extends SingleChildRenderObjectWidget {
  const _LiveBlur({required this.live, required this.sigmaOf, super.child});

  final Listenable live;
  final double Function() sigmaOf;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLiveBlur(live, sigmaOf);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLiveBlur).sigmaOf = sigmaOf;
  }
}

class _RenderLiveBlur extends RenderProxyBox {
  _RenderLiveBlur(this._live, this.sigmaOf);

  // The anchor's frame ticks, which live as long as the layer.
  final Listenable _live;
  double Function() sigmaOf;
  double _sigma = 0;
  final _layer = LayerHandle<ImageFilterLayer>();

  void _changed() {
    final sigma = sigmaOf();
    if (sigma == _sigma) return;
    _sigma = sigma;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _sigma > 0.01;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live.addListener(_changed);
    _sigma = sigmaOf();
  }

  @override
  void detach() {
    _live.removeListener(_changed);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_sigma <= 0.01) {
      _layer.layer = null;
      super.paint(context, offset);
      return;
    }
    final layer = _layer.layer ??= ImageFilterLayer();
    layer.imageFilter = ui.ImageFilter.blur(
      sigmaX: _sigma,
      sigmaY: _sigma,
      tileMode: TileMode.decal,
    );
    context.pushLayer(layer, super.paint, offset);
  }
}
