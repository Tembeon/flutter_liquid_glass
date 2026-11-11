import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/presentations/menu_content.dart';
import 'package:apple_liquid_glass/src/presentations/menu_entries.dart';
import 'package:apple_liquid_glass/src/presentations/menu_rows.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

part 'menu_anchor_context.dart';
part 'menu_anchor_inputs.dart';
part 'menu_anchor_layer.dart';
part 'menu_anchor_look.dart';
part 'menu_anchor_semantics.dart';

/// Opens and closes the menu of a [GlassMenuAnchor] or a
/// [GlassContextMenu] from code.
///
/// Flutter: `MenuController`.
class GlassMenuController {
  _MenuHost<StatefulWidget>? _host;

  /// Whether the menu shows or is on its way to showing.
  bool get isOpen => _host?._isOpen ?? false;

  /// Opens the menu.
  void open() => _host?._openFromCode();

  /// Closes the menu.
  void close() => _host?._close();
}

/// The state of a widget whose menu shows on the overlay: the motion, the
/// commands and events, the touches of the open menu.
abstract class _MenuHost<W extends StatefulWidget> extends State<W> {
  final _portal = PresentationPortalController();
  late final _content = MenuContent(onChanged: _contentChanged);
  bool _showing = false;
  final _source = MotionSource();

  // The node the open menu holds while no row has the focus, so Escape
  // reaches the menu's own action before the presentation's.
  final _menuFocus = FocusNode(debugLabel: 'Menu', skipTraversal: true);
  MenuMotion? _motion;
  MotionSelection<MenuMotion>? _steps;
  OverlayState? _overlay;
  MenuAppearance _style = MenuAppearance.light;
  int? _pointer;
  int? _early;

  // The release of a tap on the source, until the source's own control has
  // heard it in the same event.
  double? _tapAt;

  // What the menu made of the pointer command running now, for the haptics
  // of the input host that heard the pointer.
  final List<InteractionEvent> _heard = [];
  bool _routing = false;
  bool _delivering = false;

  // Only read while there is a motion, whose clock it is.
  double get _now => _motion!.clock.now;

  bool get _isOpen => _motion?.isOpen ?? false;

  List<GlassMenuEntry> get _entries;
  GlassMenuOrder get _order;
  GlassMenuController? get _controller;
  bool get _enabled;
  String? get _semanticLabel;

  /// The source's look drawn on the glass while it grows into the menu,
  /// or null for a menu that does not grow out of its source's glass.
  Widget? get _look;

  /// The color of the source's glass at rest (see
  /// [GlassSourceDescription.tint]).
  Color? get _sourceTint => null;

  /// Where the menu grows out of in [overlay]'s coordinates, or null for
  /// this widget's box.
  MenuSource _sourceIn(RenderBox overlay, Rect box) => MenuSource(box);

  /// The motion of a menu opening from [source], in the overlay's
  /// coordinates.
  MenuMotion _createMotion(MenuSource source, Size bounds, EdgeInsets padding);

  /// Lays a closed motion out again for [source].
  void _relayout(
    MenuMotion motion,
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  );

  /// What the layer draws under the menu.
  List<Widget> _backdrop(_MenuLayerState layer) => const [];

  @override
  void initState() {
    super.initState();
    _controller?._host = this;
    _content.entries = _entries;
    _content.order = _order;
  }

  /// Takes a new configuration of the host's widget.
  void _updated({
    required GlassMenuController? oldController,
    required bool wasEnabled,
  }) {
    if (oldController != _controller) {
      if (identical(oldController?._host, this)) {
        oldController?._host = null;
      }
      _controller?._host = this;
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
    if (identical(_controller?._host, this)) {
      _controller?._host = null;
    }
    _unroute();
    _steps?.removeListener(_stepped);
    _content.dispose();
    _menuFocus.dispose();
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
        if (tracked) _heard.add(ScrubChangeEvent(time: _now, selected: to));
      case MenuActivated(:final target):
        _content.activate(target);
      // The source's own control runs its action on its tap; an action
      // that opens the menu opens it after UIKit's tap delay.
      case MenuTapped(:final time):
        _tapAt = time;
        scheduleMicrotask(() => _tapAt = null);
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
    final source = _sourceIn(
      overlayBox,
      box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size,
    );
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
      motion.advance(at ?? motion.clock.now);
      _adopt(motion);
      setState(() {});
    }
    motion.lightsGlow = !GlassTraits.of(context).reduceTransparency;
    return motion;
  }

  // Showing is a change of structure: the source says it is expanded.
  void _shown(bool showing) {
    if (showing == _showing || !mounted) return;
    setState(() => _showing = showing);
    _reportShowing(showing);
  }

  /// Tells the app the menu now shows or no longer does.
  void _reportShowing(bool showing) {}

  void _show() {
    if (!mounted) return;
    _portal.present();
    _shown(true);
  }

  void _openFromCode() {
    if (!mounted || !_enabled || _isOpen) return;
    // The action of a tap on the source opens the menu after UIKit's tap
    // delay, as a source whose tap is the menu's does, whether the source's
    // control hears the release before the menu or after it.
    final motion = _motion;
    if (motion != null && !motion.isPresented) {
      final tap = _tapAt ?? (_pointer != null ? _now : null);
      if (tap != null) {
        motion.openAfterTap(tap);
        _deliver(motion);
        if (_pointer == null && motion.isOpenPending) _route();
        return;
      }
    }
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

  /// The events of the pointer commands given since the last call: a
  /// finger that slid onto another row.
  List<InteractionEvent> _takeHeard() {
    if (_heard.isEmpty) return const [];
    final heard = [..._heard];
    _heard.clear();
    return heard;
  }

  /// The haptic an input host plays for an event of the menu's pointer.
  static MotionHaptic? _feedback(InteractionEvent event) =>
      event is ScrubChangeEvent ? MotionHaptic.selection : null;

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
    final motion = _motion;
    if (motion == null) return;
    final t = motion.clock.stamp(event.timeStamp);
    if (event is PointerDownEvent) {
      if (!motion.isOpenPending ||
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
    // No input host hears such a touch, so the menu plays its haptics.
    for (final event in _takeHeard()) {
      _feedback(event)?.play(context);
    }
  }

  /// The opacity of the dim under the open menu, or null for none.
  double Function(MenuMotion motion)? _dim(BuildContext context) => null;

  /// The menu on the root overlay over [child], the source.
  Widget _host(Widget child) => PresentationPortal(
    controller: _portal,
    presentation: Presentation<Object?, MenuMotion>(
      motion: (_) => _motion!,
      builder: (context, motion) => _MenuLayer(host: this),
      source: _source,
      dim: _dim(context),
      semanticsLabel:
          _semanticLabel ?? GlassLocalizations.of(context).menuLabel,
      barrierLabel: GlassLocalizations.of(context).menuDismissLabel,
      semanticsRole: ui.SemanticsRole.menu,
      initialFocus: _menuFocus,
      onDismissed: (_) => _shown(false),
    ),
    child: child,
  );
}

/// Builds the control a [GlassMenuAnchor] wraps, given the anchor's
/// [controller] and its `child`.
///
/// Flutter: `MenuAnchorChildBuilder`.
typedef GlassMenuAnchorChildBuilder = Widget Function(
  BuildContext context,
  GlassMenuController controller,
  Widget? child,
);

/// Wraps a control, such as a `GlassButton`, whose glass grows into a menu
/// of [menuChildren], as a `UIButton` with a menu does on iOS 27.
///
/// UIKit: `UIButton.menu`. SwiftUI: `Menu`. Flutter: `MenuAnchor`,
/// `CupertinoMenuAnchor`.
///
/// [builder] builds the control and opens the menu from its action with
/// the controller it is given: `onPressed: controller.open` makes the tap
/// open the menu after UIKit's delay, as `showsMenuAsPrimaryAction`;
/// another action keeps the tap and leaves the menu to a hold. Either way a
/// hold opens it under the finger. The control keeps its own touches, keys,
/// focus, states and semantics; the anchor watches the same touch, presses
/// the control by the menu's measured press, takes the touch once a hold
/// opens the menu, and lets the finger keep sliding over the open menu to
/// choose the row it lifts from. The control reads as expanded while the
/// menu shows and a long press opens it; focus returns to the control when
/// the menu closes. The menu shows on the root overlay without a route;
/// Escape, Back and a tap outside close it, and the tap outside reaches
/// nothing under it. The menu grows out of the control on UIKit's liquid
/// morph springs, the control's glass and the menu one body joined by a
/// neck while they part (read from UIKit and replayed against iPhone 16
/// Pro recordings).
///
/// A control that describes its glass with a [GlassSource] (a
/// `GlassButton` or [RawGlassButton] does) hands the menu its glass: the
/// menu's glass grows out of its shape, takes its tint at both hand-offs
/// and carries its look as it fades. Anything else keeps showing under the
/// menu, whose untinted glass grows out of the anchor's box as a capsule.
class GlassMenuAnchor extends StatefulWidget {
  /// Creates an anchor of [menuChildren] around what [builder] builds, or
  /// around [child] without one.
  const GlassMenuAnchor({
    required this.menuChildren,
    this.builder,
    this.child,
    this.controller,
    this.onOpen,
    this.onClose,
    this.enabled = true,
    this.semanticLabel,
    this.order = GlassMenuOrder.automatic,
    this.style,
    this.sourceOf,
    @internal this.scalesOnPress = true,
    super.key,
  }) : assert(builder != null || child != null, 'Give a builder or a child.');

  /// The menu's entries.
  final List<GlassMenuEntry> menuChildren;

  /// Builds the control the menu grows out of; null shows [child].
  final GlassMenuAnchorChildBuilder? builder;

  /// What [builder] is given to place, or the control itself without a
  /// builder.
  final Widget? child;

  /// Opens and closes the menu from code; null for the anchor's own, which
  /// [builder] is given either way.
  final GlassMenuController? controller;

  /// Called when the menu starts to show.
  final VoidCallback? onOpen;

  /// Called when the menu has gone.
  final VoidCallback? onClose;

  /// Whether a hold and the controller open the menu.
  final bool enabled;

  /// What accessibility calls the menu; null names it after the control's
  /// [GlassSourceDescription.semanticLabel], or the menu's default name.
  final String? semanticLabel;

  /// How the rows order in a menu that opens upward.
  final GlassMenuOrder order;

  /// The look of the menu's rows, over the theme's.
  final GlassMenuStyle? style;

  /// What the menu grows out of, in the coordinates of the overlay it is
  /// given, when that is not the control; null, or a call that returns
  /// null, grows it out of the control.
  ///
  /// A bar hands the menu of one of its items a [MenuCapsuleSource]: the
  /// whole capsule around the item morphs into the menu, which lands where
  /// the capsule says.
  final MenuSource? Function(RenderBox overlay)? sourceOf;

  /// Whether the control scales under a finger; false when something
  /// around it already does.
  @internal
  final bool scalesOnPress;

  @override
  State<GlassMenuAnchor> createState() => _GlassMenuAnchorState();
}

class _GlassMenuAnchorState extends _MenuHost<GlassMenuAnchor> {
  final _ownController = GlassMenuController();

  // The box of the control's described body; nothing leases it, the menu
  // only reads where it is.
  final _body = MotionSource(debugLabel: 'GlassMenuAnchor');

  // What the control told of its glass, read when the menu prepares.
  GlassSourceDescription? _described;

  @override
  List<GlassMenuEntry> get _entries => widget.menuChildren;

  @override
  GlassMenuOrder get _order => widget.order;

  @override
  GlassMenuController get _controller => widget.controller ?? _ownController;

  @override
  bool get _enabled => widget.enabled;

  @override
  String? get _semanticLabel =>
      widget.semanticLabel ?? _described?.semanticLabel;

  @override
  Widget? get _look => _described?.look;

  @override
  Color? get _sourceTint => _described?.tint;

  @override
  MenuMotion _prepare({double? at}) {
    _described = _describe();
    return super._prepare(at: at);
  }

  // The first GlassSource in the control, which the control built: read,
  // never written, so the build stays the control's own.
  GlassSourceDescription? _describe() {
    GlassSourceDescription? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is GlassSource) {
        found = widget.description;
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return found;
  }

  @override
  MenuSource _sourceIn(RenderBox overlay, Rect box) {
    final given = widget.sourceOf?.call(overlay);
    if (given != null) return given;
    final described = _described;
    final shown = described == null ? null : _body.geometry?.rect;
    final rect = shown == null
        ? box
        : Rect.fromPoints(
            overlay.globalToLocal(shown.topLeft),
            overlay.globalToLocal(shown.bottomRight),
          );
    final shape = described?.shape ?? GlassShape.capsule;
    return MenuSource(
      rect,
      radius: shape == GlassShape.capsule ? null : shape.radiusIn(rect),
    );
  }

  @override
  void dispose() {
    if (_showing) widget.onClose?.call();
    super.dispose();
  }

  @override
  void _reportShowing(bool showing) =>
      (showing ? widget.onOpen : widget.onClose)?.call();

  @override
  MenuMotion _createMotion(
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  ) {
    final motion = MenuMotion(
      source: source,
      layout: _content.root,
      bounds: bounds,
      padding: padding,
    );
    motion.opensOnTap = false;
    return motion;
  }

  @override
  void _relayout(
    MenuMotion motion,
    MenuSource source,
    Size bounds,
    EdgeInsets padding,
  ) => motion.relayout(source: source, bounds: bounds, padding: padding);

  @override
  void didUpdateWidget(GlassMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updated(
      oldController: oldWidget.controller ?? _ownController,
      wasEnabled: oldWidget.enabled,
    );
  }

  // Watches the control's touch at its stamps, however the arena decides.
  late final _watch = _ObservedTouch(
    down: _sourceDown,
    move: _pointerMove,
    up: _pointerUp,
    cancel: _pointerCancel,
    heard: _takeHeard,
  );

  // Takes the touch from the control once a hold opens the menu; until then
  // the control's claims do not hold it, so its release still taps.
  late final _hold = _MenuInput(
    claimAfter: MenuMotion.holdDuration,
    contends: true,
    down: (pointer, t, global) => pointer == _pointer,
    move: (pointer, t, global) {},
    up: (pointer, t, global) {},
    cancel: _pointerCancel,
    heard: () => const [],
  );

  void _sourceDown(int pointer, double t, Offset global) {
    if (!widget.enabled || _pointer != null || _isOpen) return;
    _prepare();
    _pointerDown(pointer, t, global);
  }

  // Read through the steps, so the press follows the motion's frames once
  // there is one.
  Matrix4 _pressTransform() {
    final motion = _steps?.value;
    if (motion == null || !widget.scalesOnPress) return Matrix4.identity();
    final s = motion.isPresented ? 1.0 : motion.pressScale;
    return Matrix4.diagonal3Values(s, s, 1);
  }

  @override
  Widget build(BuildContext context) {
    _style = MenuAppearance.of(context, widget.style);
    final enabled = widget.enabled;
    final control =
        widget.builder?.call(context, _controller, widget.child) ??
        widget.child!;
    return _host(
      InputRegion(
        interactions: [_watch, _hold],
        feedback: _MenuHost._feedback,
        enabled: enabled,
        minimumHitSize: const Size(44, 44),
        child: _ControlSemantics(
          expanded: _showing,
          onLongPress: enabled ? _openFromCode : null,
          child: MotionDriven(
            template: () => Transform(
              transform: _pressTransform(),
              alignment: Alignment.center,
            ),
            child: GlassSourceScope(source: _body, child: control),
          ),
        ),
      ),
    );
  }
}
