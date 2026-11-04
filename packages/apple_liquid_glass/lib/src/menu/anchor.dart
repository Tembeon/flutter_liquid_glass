import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/src/geometry/boxes.dart';
import 'package:apple_liquid_glass/src/menu/appearance.dart';
import 'package:apple_liquid_glass/src/menu/content.dart';
import 'package:apple_liquid_glass/src/menu/context_hold.dart';
import 'package:apple_liquid_glass/src/menu/entries.dart';
import 'package:apple_liquid_glass/src/menu/fusion.dart';
import 'package:apple_liquid_glass/src/menu/layout.dart';
import 'package:apple_liquid_glass/src/menu/motion.dart';
import 'package:apple_liquid_glass/src/menu/outline_math.dart';
import 'package:apple_liquid_glass/src/menu/rows.dart';
import 'package:apple_liquid_glass/src/motion/live.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/shape.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// Opens and closes the menu of a [RawGlassMenu], a `GlassButton` or a
/// [GlassContextMenu] from code.
///
/// Flutter: `MenuController`.
class GlassMenuController {
  _MenuHost<StatefulWidget>? _anchor;

  /// Whether the menu shows or is on its way to showing.
  bool get isOpen => _anchor?._isOpen ?? false;

  /// Opens the menu.
  void open() => _anchor?._openFromCode();

  /// Closes the menu.
  void close() => _anchor?._close();
}

/// A source whose glass grows into a menu of [entries], as a `UIButton`
/// with a menu does on iOS 27, with no look of its own: [child] draws the
/// source.
///
/// UIKit: `UIButton.menu`. SwiftUI: `Menu`. Flutter: `RawMenuAnchor`.
///
/// Without [onPressed] a tap opens the menu on its release and a hold
/// opens it under the finger (UIKit's `showsMenuAsPrimaryAction`); with it
/// a tap calls it and only a hold opens the menu. The menu shows on the
/// root overlay without a route, so a finger that pressed the source keeps
/// sliding over the open menu and chooses the row it lifts from. Escape,
/// Back and a tap outside close it; the tap outside reaches nothing under
/// it. While the menu shows, [child] paints nothing and the menu's glass
/// draws [label] as it grows out of the source; `GlassButton` with
/// `menuChildren` is this core with the button's glass.
class RawGlassMenu extends StatefulWidget {
  /// Creates the menu source drawn as [child].
  const RawGlassMenu({
    required this.entries,
    required this.child,
    required this.label,
    this.tint,
    this.radius,
    this.onPressed,
    this.enabled = true,
    this.controller,
    this.semanticLabel,
    this.order = GlassMenuOrder.automatic,
    this.style,
    @internal this.tuning = MenuTuning.standard,
    super.key,
  });

  /// The menu's entries.
  final List<GlassMenuEntry> entries;

  /// The source at rest, glass included.
  final Widget child;

  /// The source's label or glyph, drawn on the menu's glass while it grows
  /// out of the source.
  final Widget label;

  /// The color of the source's glass at rest, or null for untinted glass.
  /// The menu's glass takes it at both hand-offs and crosses it into its
  /// own while [label] fades, the fused body included (menu-button.md);
  /// the color hand-off of a tinted `UIButton` is not recorded.
  final Color? tint;

  /// The corner radius of the source's glass at rest; null for a capsule.
  final double? radius;

  /// Called on a tap; null makes a tap open the menu.
  final VoidCallback? onPressed;

  /// Whether the source takes touches.
  final bool enabled;

  /// Opens and closes the menu from code.
  final GlassMenuController? controller;

  /// What accessibility reads for the source.
  final String? semanticLabel;

  /// How the rows order in a menu that opens upward.
  final GlassMenuOrder order;

  /// The look of the menu's rows, over the theme's.
  final GlassMenuStyle? style;

  /// The measured behavior of the menu, read when it first opens.
  @internal
  final MenuTuning tuning;

  @override
  State<RawGlassMenu> createState() => _RawGlassMenuState();
}

/// The state of a widget whose menu shows on the overlay: the motion, the
/// commands and events, the touches of the open menu.
abstract class _MenuHost<W extends StatefulWidget> extends State<W> {
  static final Listenable _still = Listenable.merge(const []);

  final _portal = PresentationPortalController();
  late final _content = MenuContent(onChanged: _contentChanged);
  final _showing = ValueNotifier<bool>(false);
  final _source = MotionSource();
  MenuMotion? _motion;
  MotionSelection<MenuMotion>? _steps;
  OverlayState? _overlay;
  MenuAppearance _style = MenuAppearance.light;
  int? _pointer;
  int? _early;
  bool _routing = false;
  bool _delivering = false;

  double get _now => MotionClock.instance.now;

  bool get _isOpen => _motion?.isOpen ?? false;

  /// What the menu's live widgets follow: every frame that moved the
  /// motion and every command to it.
  Listenable get _frames => _steps ?? _still;

  List<GlassMenuEntry> get _entries;
  GlassMenuOrder get _order;
  GlassMenuController? get _controller;
  bool get _enabled;
  String? get _semanticLabel;
  VoidCallback? get _onTap;

  /// The source's look drawn on the glass while it grows into the menu,
  /// or null for a menu that does not grow out of its source's glass.
  Widget? get _look;

  /// The color of the source's glass at rest (see [RawGlassMenu.tint]).
  Color? get _sourceTint => null;

  /// The motion of a menu opening from [source], in the overlay's
  /// coordinates.
  MenuMotion _createMotion(Rect source, Size bounds, EdgeInsets padding);

  /// Lays a closed motion out again for [source].
  void _relayout(
    MenuMotion motion,
    Rect source,
    Size bounds,
    EdgeInsets padding,
  );

  /// What the layer draws under the menu.
  List<Widget> _backdrop(_MenuLayerState layer) => const [];

  @override
  void initState() {
    super.initState();
    _controller?._anchor = this;
    _content.entries = _entries;
    _content.order = _order;
  }

  /// Takes a new configuration of the host's widget.
  void _updated({
    required GlassMenuController? oldController,
    required bool wasEnabled,
  }) {
    if (oldController != _controller) {
      if (identical(oldController?._anchor, this)) {
        oldController?._anchor = null;
      }
      _controller?._anchor = this;
    }
    final changed =
        !identical(_entries, _content.entries) || _order != _content.order;
    _content.entries = _entries;
    _content.order = _order;
    if (changed) _contentChanged(animate: true);
    if (wasEnabled && !_enabled) _close();
  }

  @override
  void dispose() {
    if (identical(_controller?._anchor, this)) {
      _controller?._anchor = null;
    }
    _unroute();
    _steps?.removeListener(_stepped);
    _content.dispose();
    _showing.dispose();
    super.dispose();
  }

  void _adopt(MenuMotion motion) {
    _motion = motion;
    final steps = _steps = MotionSelect(
      motion,
    ).select((m) => m, equals: (_, _) => false);
    steps.addListener(_stepped);
  }

  void _stepped() {
    final motion = _motion;
    if (motion == null) return;
    _deliver(motion);
    if (_early == null && !motion.isOpenPending) _unroute();
  }

  void _command(
    void Function(MenuMotion motion, double t) command, {
    double? at,
  }) {
    final motion = _motion;
    if (motion == null) return;
    final t = at ?? _now;
    motion.advance(t);
    _deliver(motion);
    command(motion, t);
    _deliver(motion);
  }

  // Events a callback raises while others are delivered follow them, in
  // order, instead of interrupting them.
  void _deliver(MenuMotion motion) {
    if (motion.isOpen) _show();
    if (_delivering) return;
    _delivering = true;
    try {
      for (
        var events = motion.drainEvents();
        events.isNotEmpty;
        events = motion.drainEvents()
      ) {
        for (final event in events) {
          _receive(event);
        }
      }
    } finally {
      _delivering = false;
    }
  }

  void _receive(MenuEvent event) {
    switch (event) {
      case MenuHighlightChanged(:final from, :final to, :final tracked):
        _content.highlight(from, to);
        if (tracked) MotionHaptic.selection.play();
      case MenuActivated(:final target):
        _content.activate(target);
      case MenuTapped():
        if (_enabled) _onTap?.call();
    }
  }

  void _contentChanged({required bool animate}) {
    final motion = _motion;
    if (motion == null || !(motion.isPresented || motion.isArming)) return;
    final animated = animate && motion.isPresented;
    _command((motion, t) => motion.updateLayout(t, animate: animated));
  }

  /// The motion, laid out for the source where it is now and advanced to
  /// [at] (now when null) if it is new.
  MenuMotion _prepare({double? at}) {
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
    final source =
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
    if (current != null) {
      _relayout(current, source, overlayBox.size, padding);
      motion = current;
    } else {
      motion = _createMotion(source, overlayBox.size, padding);
      motion.submenuLayout = _content.submenu;
      motion.advance(at ?? _now);
      _adopt(motion);
      setState(() {});
    }
    motion.lightsGlow = !GlassTraits.of(context).reduceTransparency;
    return motion;
  }

  void _show() {
    if (!mounted) return;
    _portal.present();
    _showing.value = true;
  }

  void _openFromCode() {
    if (!mounted || !_enabled || _isOpen) return;
    _prepare();
    _command((motion, t) => motion.open(t));
  }

  void _close() {
    final motion = _motion;
    if (motion == null) return;
    _command((motion, t) => motion.close(t), at: math.max(_now, motion.now));
  }

  Offset _local(Offset global) {
    final box = _overlay?.context.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  Offset _toGlobal(Offset local) {
    final box = context.findRenderObject();
    return box is RenderBox ? box.localToGlobal(local) : local;
  }

  /// A finger touched the menu at [global] at time [t]; whether the menu
  /// takes the touch.
  bool _pointerDown(int pointer, double t, Offset global) {
    if (_motion == null || _pointer != null) return false;
    _pointer = pointer;
    final local = _local(global);
    _command((motion, t) => motion.pointerDown(t, local), at: t);
    return true;
  }

  void _pointerMove(int pointer, double t, Offset global) {
    if (pointer != _pointer) return;
    final local = _local(global);
    _command((motion, t) => motion.pointerMove(t, local), at: t);
  }

  void _pointerUp(int pointer, double t, Offset global) {
    if (pointer != _pointer) return;
    _pointer = null;
    final motion = _motion;
    if (motion == null) return;
    final local = _local(global);
    _command((motion, t) => motion.pointerUp(t, local), at: t);
    if (motion.isOpenPending) _route();
  }

  void _pointerCancel(int pointer, double t) {
    if (pointer != _pointer) return;
    _pointer = null;
    _command((motion, t) => motion.pointerCancel(t), at: t);
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

  // No region lies under such a touch yet: the menu shows only once it
  // opens.
  void _earlyEvent(PointerEvent event) {
    final t = MotionClock.instance.stamp(event.timeStamp);
    if (event is PointerDownEvent) {
      if (!(_motion?.isOpenPending ?? false) ||
          _pointer != null ||
          event.buttons != kPrimaryButton) {
        return;
      }
      _early = event.pointer;
      _pointerDown(event.pointer, t, event.position);
    } else if (event.pointer == _early) {
      switch (event) {
        case PointerMoveEvent():
          _pointerMove(event.pointer, t, event.position);
        case PointerUpEvent():
          _early = null;
          _pointerUp(event.pointer, t, event.position);
        case PointerCancelEvent():
          _early = null;
          _pointerCancel(event.pointer, t);
        default:
      }
    }
  }

  /// The opacity of the dim under the open menu, or null for none.
  double Function(MenuMotion motion)? _dim(BuildContext context) => null;

  /// The menu on the root overlay over [child], the source.
  Widget _host(Widget child) => PresentationPortal(
    controller: _portal,
    presentation: Presentation<Object?, MenuMotion>(
      motion: (_) => _motion!,
      builder: (context, motion) => _MenuLayer(anchor: this),
      source: _source,
      dim: _dim(context),
      semanticsLabel: _semanticLabel,
      onDismissed: (_) => _showing.value = false,
    ),
    child: child,
  );
}

class _RawGlassMenuState extends _MenuHost<RawGlassMenu> {
  @override
  List<GlassMenuEntry> get _entries => widget.entries;

  @override
  GlassMenuOrder get _order => widget.order;

  @override
  GlassMenuController? get _controller => widget.controller;

  @override
  bool get _enabled => widget.enabled;

  @override
  String? get _semanticLabel => widget.semanticLabel;

  @override
  VoidCallback? get _onTap => widget.onPressed;

  @override
  Widget? get _look => widget.label;

  @override
  Color? get _sourceTint => widget.tint;

  @override
  MenuMotion _createMotion(Rect source, Size bounds, EdgeInsets padding) {
    final motion = MenuMotion(
      button: source,
      layout: _content.root,
      bounds: bounds,
      padding: padding,
      sourceRadius: widget.radius,
      tuning: widget.tuning,
    );
    motion.opensOnTap = widget.onPressed == null;
    return motion;
  }

  @override
  void _relayout(
    MenuMotion motion,
    Rect source,
    Size bounds,
    EdgeInsets padding,
  ) {
    motion.relayout(
      button: source,
      bounds: bounds,
      padding: padding,
      sourceRadius: widget.radius,
    );
    motion.opensOnTap = widget.onPressed == null;
  }

  @override
  void didUpdateWidget(RawGlassMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updated(
      oldController: oldWidget.controller,
      wasEnabled: oldWidget.enabled,
    );
  }

  late final _input = _MenuInput(
    claimAfter: widget.tuning.holdDuration,
    toGlobal: _toGlobal,
    down: _sourceDown,
    move: _pointerMove,
    up: _pointerUp,
    cancel: _pointerCancel,
    activate: _activate,
  );

  bool _sourceDown(int pointer, double t, Offset global) {
    if (!widget.enabled || _pointer != null || _isOpen) return false;
    _prepare();
    return _pointerDown(pointer, t, global);
  }

  void _activate() {
    if (!widget.enabled) return;
    final onPressed = widget.onPressed;
    if (onPressed != null) {
      onPressed();
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
    _style = MenuAppearance.of(context, widget.style);
    final enabled = widget.enabled;
    final hold = widget.onPressed != null;
    return _host(
      InputRegion(
        interactions: [_input],
        enabled: enabled,
        semanticLabel: widget.semanticLabel,
        child: ValueListenableBuilder<bool>(
          valueListenable: _showing,
          child: MotionSourceBox(
            source: _source,
            child: LiveTransform(
              live: _frames,
              matrixOf: _pressTransform,
              child: widget.child,
            ),
          ),
          builder: (context, showing, face) => Semantics(
            button: true,
            expanded: showing,
            excludeSemantics: widget.semanticLabel != null,
            onLongPress: enabled && hold ? _openFromCode : null,
            child: face,
          ),
        ),
      ),
    );
  }
}

/// The touches of a region over a menu's source or its layer, handed to
/// the menu in global coordinates at their stamps.
///
/// It hears a touch at contact and holds it [claimAfter] later, when a
/// hold opens the menu under the finger, or at once without one: a scroll
/// view around the source takes a finger that moves before then and never
/// one that may choose from the menu.
final class _MenuInput extends Interaction {
  _MenuInput({
    required this.toGlobal,
    required this.down,
    required this.move,
    required this.up,
    required this.cancel,
    this.activate,
    this.claimAfter,
  });

  final Offset Function(Offset local) toGlobal;
  final bool Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global) move;
  final void Function(int pointer, double t, Offset global) up;
  final void Function(int pointer, double t) cancel;
  final VoidCallback? activate;
  final double? claimAfter;

  int? _pointer;
  double? _claimAt;

  @override
  bool get activates => activate != null;

  @override
  double? get nextDue => _claimAt;

  @override
  InteractionUpdate advance(double time) {
    final due = _claimAt;
    if (due == null || time < due) return InteractionUpdate.none;
    _claimAt = null;
    return const InteractionUpdate(claims: true);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        if (!down(input.pointer, input.time, toGlobal(input.position))) {
          return InteractionUpdate.none;
        }
        _pointer = input.pointer;
        final after = claimAfter;
        if (after == null) return const InteractionUpdate(claims: true);
        _claimAt = input.time + after;
      case PointerMoveInput() when input.pointer == _pointer:
        move(input.pointer, input.time, toGlobal(input.position));
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        up(input.pointer, input.time, toGlobal(input.position));
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        cancel(input.pointer, input.time);
      case ActivateInput():
        activate?.call();
      default:
    }
    return InteractionUpdate.none;
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

  final _MenuHost<StatefulWidget> anchor;

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

  _MenuHost<StatefulWidget> get _anchor => widget.anchor;

  late final MotionSelection<MenuMotion> _frames = _anchor._steps!;

  late final _input = _MenuInput(
    toGlobal: (local) =>
        (context.findRenderObject()! as RenderBox).localToGlobal(local),
    down: _anchor._pointerDown,
    move: _anchor._pointerMove,
    up: _anchor._pointerUp,
    cancel: _anchor._pointerCancel,
  );

  // The menu's own Focus takes the keys; the region's stays out of the
  // traversal.
  final _regionFocus = FocusNode(skipTraversal: true);

  MenuMotion get _motion => _anchor._motion!;

  double get _width => _motion.tuning.menuWidth;

  @override
  void initState() {
    super.initState();
    _frames.addListener(_tick);
    _scroll.addListener(_scrolled);
    _built = _structure();
  }

  @override
  void dispose() {
    _frames.removeListener(_tick);
    _regionFocus.dispose();
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
    final root = cards[0].layout;
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
      if (!back) return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _rowsOf(MenuLayout layout, MenuAppearance style) {
    if (style != _rowsStyle) {
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
          final s = motion.cards[0].scale;
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
            final s = cards[0].scale;
            return Matrix4.diagonal3Values(s, s, 1);
          },
          child: LiveFade(
            live: _frames,
            opacityOf: () {
              final cards = _motion.cards;
              return cards[0].rowOpacity;
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
              child: LiveGlassSurface(
                live: _frames,
                frameOf: () => GlassFrame(
                  shape: GlassShape.roundedRect(radius()),
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
    final layer = InputRegion(
      interactions: [_input],
      focusNode: _regionFocus,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ..._anchor._backdrop(this),
          IgnorePointer(
            child: LiveGlassSurface(
              live: _frames,
              frameOf: () => _menuFrame(
                motion,
                sourceTint: _anchor._sourceTint,
                opacity: motion.glassOpacity,
              ),
            ),
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
                      child: Center(child: _anchor._look),
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
      child: BlockSemantics(
        child: Focus(autofocus: true, onKeyEvent: _key, child: layer),
      ),
    );
  }
}

// The menu's glass in [motion]'s frame. A tinted source's color stays on
// the glass, fused body included, until its look has faded.
GlassFrame _menuFrame(
  MenuMotion motion, {
  Color? sourceTint,
  double opacity = 1,
}) {
  final glow = motion.touchGlow;
  final tint = motion.drawsSource ? sourceTint : null;
  final tintAmount = tint == null ? 1.0 : motion.buttonLookOpacity;
  final root = motion.rootBlob.rrect;
  if (motion.fusionRadius >= MenuFusion.minimumRadius) {
    return GlassFrame(
      outline: motion.silhouette,
      tint: tint,
      tintAmount: tintAmount,
      glow: glow,
      opacity: opacity,
    );
  }
  final source = motion.drawsSource ? motion.buttonBlob.rrect : null;
  if (source == null || encloses(root, source)) {
    return GlassFrame(
      shape: GlassShape.roundedRect(root.tlRadiusX),
      rect: root.outerRect,
      tint: tint,
      tintAmount: tintAmount,
      glow: glow,
      opacity: opacity,
    );
  }
  return GlassFrame(
    outline: unionOutline([root, source]),
    tint: tint,
    tintAmount: tintAmount,
    glow: glow,
    opacity: opacity,
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

/// Shows a menu beside a lifted preview of [child] when it is held, as an
/// iOS 27 context menu does.
///
/// UIKit: `UIContextMenuInteraction`. SwiftUI: `contextMenu`. Flutter:
/// `CupertinoContextMenu`.
///
/// A finger resting on [child] grows it by UIKit's measured law (nothing for
/// 0.184 s, then 32 points a second to 8 points, then 20 a second to 15 points
/// along its longest side); a finger that moves drops it back, and so does one
/// that lifts before 0.42 s. Held for 0.78 s, the page dims (20 percent light,
/// 48 percent dark), the preview lifts to 1.15 times its size (26 points at
/// most), fitted into the safe area, and the menu grows out of a blob at its
/// center beside it, on one spring of response 0.284 s (iPhone 16 Pro, iOS 27).
/// The finger then slides onto a row and chooses it on release; let go on the
/// preview, it leaves the menu open. A tap outside, Escape and Back close it.
/// [previewBuilder] draws the open preview in place of a copy of [child],
/// fading in as it lifts.
class GlassContextMenu extends StatefulWidget {
  /// Creates a context menu of [menuChildren] for [child].
  const GlassContextMenu({
    required this.menuChildren,
    required this.child,
    this.previewBuilder,
    this.controller,
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

  /// Whether a hold opens the menu.
  final bool enabled;

  /// What accessibility reads for the menu.
  final String? semanticLabel;

  /// How the rows order in a menu that opens upward.
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
  late final _hold = ContextHold(
    onCommit: MotionHaptic.heavyImpact.play,
    onOpen: _openUnder,
  );
  late final _growth = _hold.select((hold) => hold.growth);

  // The hold itself listens outside the gesture arena (see [_stamp]); this
  // member only claims the touch when the menu opens, so a surrounding
  // scroll view does not take the finger sliding into the rows.
  late final _claim = _MenuInput(
    claimAfter: ContextHold.openAfter,
    toGlobal: (local) => local,
    down: (pointer, t, global) => _enabled && !(_motion?.isPresented ?? false),
    move: (pointer, t, global) {},
    up: (pointer, t, global) {},
    cancel: (pointer, t) {},
  );
  final _claimFocus = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _claimFocus.dispose();
    super.dispose();
  }

  int? _held;
  Offset _from = Offset.zero;
  Offset _finger = Offset.zero;
  Rect _heldRect = Rect.zero;
  Rect _previewRect = Rect.zero;

  // Where the preview grows out of and lands: the held view as the hold
  // grew it while the menu opens, at its natural size once it closes, as
  // the hidden view is by then.
  Rect _home = Rect.zero;

  @override
  List<GlassMenuEntry> get _entries => widget.menuChildren;

  @override
  GlassMenuOrder get _order => widget.order;

  @override
  GlassMenuController? get _controller => widget.controller;

  @override
  bool get _enabled => widget.enabled;

  @override
  String? get _semanticLabel => widget.semanticLabel;

  @override
  VoidCallback? get _onTap => null;

  @override
  Widget? get _look => null;

  @override
  void didUpdateWidget(GlassContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updated(
      oldController: oldWidget.controller,
      wasEnabled: oldWidget.enabled,
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
  MenuMotion _createMotion(Rect source, Size bounds, EdgeInsets padding) {
    final attachment = _attach(source, bounds, padding);
    final motion = MenuMotion(
      button: source,
      layout: _content.root,
      bounds: bounds,
      padding: padding,
      tuning: MenuTuning.context,
      attachment: attachment,
    );
    _placePreview(motion, source);
    return motion;
  }

  @override
  void _relayout(
    MenuMotion motion,
    Rect source,
    Size bounds,
    EdgeInsets padding,
  ) {
    motion.relayout(
      button: source,
      bounds: bounds,
      padding: padding,
      attachment: _attach(source, bounds, padding),
    );
    _placePreview(motion, source);
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
    _held = null;
    if (pointer == null || !mounted || !_enabled || _isOpen) return;
    final motion = _prepare(at: t);
    final longest = _heldRect.size.longestSide;
    final grown = longest <= 0 ? 1.0 : 1 + growth / longest;
    _home = Rect.fromCenter(
      center: _heldRect.center,
      width: _heldRect.width * grown,
      height: _heldRect.height * grown,
    );
    _pointer = pointer;
    final local = _local(_finger);
    _command(
      (motion, t) => motion.holdOpen(t, local),
      at: math.max(t, motion.now),
    );
  }

  void _drop(double t) {
    _held = null;
    _hold.release(t);
  }

  // The hold listens outside the gesture arena: a child that claims its
  // touch at once, a glass button, would win it, and Flutter's arena
  // never hands a won touch on, where UIKit cancels the button's.
  static double _stamp(PointerEvent event) =>
      MotionClock.instance.stamp(event.timeStamp);

  void _down(PointerDownEvent event) {
    if (!_enabled ||
        event.buttons != kPrimaryButton ||
        _held != null ||
        _pointer != null ||
        (_motion?.isPresented ?? false)) {
      return;
    }
    _held = event.pointer;
    _from = event.position;
    _finger = event.position;
    _hold.down(_stamp(event));
  }

  void _move(PointerMoveEvent event) {
    final t = _stamp(event);
    if (event.pointer == _held) {
      _finger = event.position;
      if ((event.position - _from).distance > kTouchSlop) _drop(t);
      return;
    }
    _pointerMove(event.pointer, t, event.position);
  }

  void _up(PointerUpEvent event) {
    final t = _stamp(event);
    if (event.pointer == _held) {
      _finger = event.position;
      if (_hold.isCommitted) {
        _openUnder(t, _hold.release(t));
        _pointerUp(event.pointer, t, event.position);
      } else {
        _drop(t);
      }
      return;
    }
    _pointerUp(event.pointer, t, event.position);
  }

  void _cancel(PointerCancelEvent event) {
    final t = _stamp(event);
    if (event.pointer == _held) {
      _drop(t);
      return;
    }
    _pointerCancel(event.pointer, t);
  }

  Matrix4 _growthTransform() {
    final size = _heldRect.isEmpty
        ? (context.findRenderObject() as RenderBox?)?.size ?? Size.zero
        : _heldRect.size;
    final longest = size.longestSide;
    final s = longest <= 0 ? 1.0 : 1 + _hold.growth / longest;
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
    return (motion) => full * motion.dim;
  }

  @override
  List<Widget> _backdrop(_MenuLayerState layer) {
    final natural = _heldRect.size;
    final builder = widget.previewBuilder;
    Widget carried(Size size, Widget child) => LivePlacement(
      live: _frames,
      rectOf: () => _previewNow().topLeft & size,
      child: LiveTransform(
        live: _frames,
        alignment: Alignment.topLeft,
        matrixOf: () {
          final rect = _previewNow();
          return Matrix4.diagonal3Values(
            size.width <= 0 ? 1 : rect.width / size.width,
            size.height <= 0 ? 1 : rect.height / size.height,
            1,
          );
        },
        child: child,
      ),
    );
    double shown() => ((_motion?.progress ?? 0) * 2).clamp(0.0, 1.0);
    return [
      IgnorePointer(
        child: Stack(
          children: [
            carried(
              natural,
              builder == null
                  ? widget.child
                  : LiveFade(
                      live: _frames,
                      opacityOf: () => 1 - shown(),
                      child: widget.child,
                    ),
            ),
            if (builder != null)
              carried(
                _previewRect.size,
                LiveFade(
                  live: _frames,
                  opacityOf: shown,
                  child: Builder(builder: builder),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _style = MenuAppearance.of(context, widget.style);
    final enabled = widget.enabled;
    return _host(
      Semantics(
        enabled: enabled,
        onLongPress: enabled ? _openFromCode : null,
        child: InputRegion(
          interactions: [_claim],
          enabled: enabled,
          focusNode: _claimFocus,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: MotionSourceBox(
              source: _source,
              child: LiveTransform(
                live: _growth,
                matrixOf: _growthTransform,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
