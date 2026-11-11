import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/motions/menu_fusion.dart';
import 'package:apple_liquid_glass/src/motions/menu_outline_math.dart';
import 'package:apple_liquid_glass/src/motions/outline_boxes.dart';
import 'package:apple_liquid_glass/src/presentations/menu_appearance.dart';
import 'package:apple_liquid_glass/src/presentations/menu_content.dart';
import 'package:apple_liquid_glass/src/presentations/menu_entries.dart';
import 'package:apple_liquid_glass/src/presentations/menu_rows.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
    @internal this.sourceOf,
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

  /// Where the menu grows out of in the coordinates of the given overlay,
  /// when that is not the control, or null to use the control.
  @internal
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

/// Merges the control into one node that is expanded while the menu shows
/// and opens it on a long press, as large as the anchor's minimum target.
class _ControlSemantics extends SingleChildRenderObjectWidget {
  const _ControlSemantics({
    required this.expanded,
    required this.onLongPress,
    required super.child,
  });

  final bool expanded;
  final VoidCallback? onLongPress;

  @override
  _RenderControlSemantics createRenderObject(BuildContext context) =>
      _RenderControlSemantics(
        expanded: expanded,
        onLongPress: onLongPress,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderControlSemantics renderObject,
  ) {
    renderObject.expanded = expanded;
    renderObject.onLongPress = onLongPress;
  }
}

class _RenderControlSemantics extends RenderProxyBox {
  _RenderControlSemantics({
    required this._expanded,
    required this._onLongPress,
  });

  static const _minimum = 44.0;

  bool get expanded => _expanded;
  bool _expanded;
  set expanded(bool value) {
    if (value == _expanded) return;
    _expanded = value;
    markNeedsSemanticsUpdate();
  }

  VoidCallback? get onLongPress => _onLongPress;
  VoidCallback? _onLongPress;
  set onLongPress(VoidCallback? value) {
    if ((value == null) == (_onLongPress == null)) {
      _onLongPress = value;
      return;
    }
    _onLongPress = value;
    markNeedsSemanticsUpdate();
  }

  @override
  Rect get semanticBounds => Rect.fromCenter(
    center: size.center(Offset.zero),
    width: math.max(size.width, _minimum),
    height: math.max(size.height, _minimum),
  );

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.isMergingSemanticsOfDescendants = true;
    config.isExpanded = _expanded;
    if (_onLongPress != null) config.onLongPress = () => _onLongPress?.call();
  }
}

/// The touches of a region over a menu's source or its layer, handed to
/// the menu in global coordinates at their stamps, with what the menu made
/// of them ([heard]) as the events the host plays haptics for.
///
/// It hears a touch at contact and claims it [claimAfter] later, when a
/// hold opens the menu under the finger, or at once without one: a scroll
/// view around the source takes a finger that moves before then and never
/// one that may choose from the menu.
final class _MenuInput extends Interaction {
  _MenuInput({
    required this.down,
    required this.move,
    required this.up,
    required this.cancel,
    required this.heard,
    this.claimAfter,
    this.contends = false,
  });

  final bool Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global) move;
  final void Function(int pointer, double t, Offset global) up;
  final void Function(int pointer, double t) cancel;
  final List<InteractionEvent> Function() heard;
  final double? claimAfter;
  final bool contends;

  int? _pointer;
  double? _claimAt;

  @override
  bool get contendsWithControls => contends;

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
    var claims = false;
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        if (!down(input.pointer, input.time, input.globalPosition)) {
          return InteractionUpdate.none;
        }
        _pointer = input.pointer;
        final after = claimAfter;
        if (after == null) {
          claims = true;
        } else {
          _claimAt = input.time + after;
        }
      case PointerMoveInput() when input.pointer == _pointer:
        move(input.pointer, input.time, input.globalPosition);
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        up(input.pointer, input.time, input.globalPosition);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        _claimAt = null;
        cancel(input.pointer, input.time);
      default:
    }
    final events = heard();
    if (!claims && events.isEmpty) return InteractionUpdate.none;
    return InteractionUpdate(claims: claims, events: events);
  }
}

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
          lastShown = _shown(
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
            child: LiveGlassSurface(
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
            child: LiveGlassSurface(
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

/// Escape on an open submenu card sends it back; on the root list it
/// dismisses the menu through the presentation, as an app's remapping of
/// `DismissIntent` does.
class _MenuEscape extends Action<DismissIntent> {
  _MenuEscape(this.layer);

  final _MenuLayerState layer;

  @override
  bool isEnabled(DismissIntent intent) => layer.mounted;

  @override
  Object? invoke(DismissIntent intent) {
    if (layer._current && layer._built.top > 0) {
      layer._back(keys: true);
      return null;
    }
    return Actions.maybeInvoke(layer.context, intent);
  }
}

/// A row's own input: Space, Enter and the accessibility tap choose it,
/// and the mouse resting on it moves the focus there. Touches stay with
/// the menu's region, whose motion follows the finger across the rows.
final class _RowInput extends Interaction {
  _RowInput({required this.onActivate, required this.onEnter});

  final VoidCallback onActivate;
  final VoidCallback onEnter;

  @override
  bool get activates => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case ActivateInput():
        onActivate();
      case PointerHoverInput(inside: true):
        onEnter();
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The mouse moving over the open menu, in the layer's coordinates.
final class _HoverInput extends Interaction {
  _HoverInput({required this.onHover});

  final ValueChanged<Offset> onHover;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input case PointerHoverInput(inside: true, :final position)) {
      onHover(position);
    }
    return InteractionUpdate.none;
  }
}

/// Paints the highlight of one card where the layer says it is now.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.layer,
    required this.card,
    required this.layout,
    required this.color,
  }) : super(repaint: Listenable.merge([layer._frames, layer._zones]));

  final _MenuLayerState layer;
  final int card;
  final MenuLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!layer.mounted) return;
    final rrect = layer._highlightOf(card, layout);
    if (rrect == null) return;
    final paint = Paint();
    paint.color = color;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      !identical(oldDelegate.layout, layout) ||
      oldDelegate.card != card ||
      oldDelegate.color != color;
}

// The menu's glass in [motion]'s frame. A tinted source's color stays on
// the glass, fused body included, until its look has faded.
GlassFrame _menuFrame(
  MenuMotion motion, {
  Color? sourceTint,
  double opacity = 1,
}) {
  final glow = motion.rootGlow;
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
    onCommit: () => MotionHaptic.heavyImpact.play(context),
    onOpen: _openUnder,
  );
  late final _growth = _hold.select((hold) => hold.growth);

  // The hold hears the touch outside the gesture arena: a child that claims
  // its touch at once, a glass button, would win it, and Flutter's arena
  // never hands a won touch on, where UIKit cancels the button's.
  late final _hear = _ObservedTouch(
    down: _down,
    move: _move,
    up: _up,
    cancel: _cancel,
    heard: _takeHeard,
  );

  // Only claims the touch when the menu opens, so a surrounding scroll view
  // does not take the finger sliding into the rows.
  late final _claim = _MenuInput(
    claimAfter: ContextHold.openAfter,
    down: (pointer, t, global) => _enabled && !(_motion?.isPresented ?? false),
    move: (pointer, t, global) {},
    up: (pointer, t, global) {},
    cancel: (pointer, t) {},
    heard: () => const [],
  );
  // One Tab stop, where the keyboard's context menu key lands.
  final _claimFocus = FocusNode(debugLabel: 'GlassContextMenu');

  // What the region reports of the keyboard focus and the mouse, which the
  // ring and the hover response around the anchor follow.
  final _states = WidgetStatesController();

  // A mouse opens the menu at the press of its secondary button, as a
  // context menu does on iPadOS and macOS.
  late final _secondary = SecondaryClickInteraction(
    onClick: (t, position) => _openFromCode(),
  );

  @override
  void dispose() {
    _claimFocus.dispose();
    _states.dispose();
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
      attachment: attachment,
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

  void _down(int pointer, double t, Offset global) {
    if (!_enabled ||
        _held != null ||
        _pointer != null ||
        (_motion?.isPresented ?? false)) {
      return;
    }
    _held = pointer;
    _from = global;
    _finger = global;
    _hold.down(t);
  }

  void _move(int pointer, double t, Offset global) {
    if (pointer == _held) {
      _finger = global;
      if ((global - _from).distance > kTouchSlop) _drop(t);
      return;
    }
    _pointerMove(pointer, t, global);
  }

  void _up(int pointer, double t, Offset global) {
    if (pointer == _held) {
      _finger = global;
      if (_hold.isCommitted) {
        _openUnder(t, _hold.release(t));
        _pointerUp(pointer, t, global);
      } else {
        _drop(t);
      }
      return;
    }
    _pointerUp(pointer, t, global);
  }

  void _cancel(int pointer, double t) {
    if (pointer == _held) {
      _drop(t);
      return;
    }
    _pointerCancel(pointer, t);
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
    final frames = layer._frames;
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
        interactions: [_hear, _claim, _secondary],
        feedback: _MenuHost._feedback,
        statesController: _states,
        mouseCursor: WidgetStateMouseCursor.adaptiveClickable,
        enabled: enabled,
        focusNode: _claimFocus,
        child: Semantics(
          onLongPress: enabled ? _openFromCode : null,
          child: MotionSourceBox(
            source: _source,
            child: menuDriven(
              _growth,
              (_) => Transform(
                alignment: Alignment.center,
                transform: _growthTransform(),
              ),
              child: GlassHighlightPaint.of(
                context,
                states: _states,
                shape: const GlassShape.roundedRect(0),
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

/// Every touch on a region, heard outside the gesture arena however it
/// decides (a `Listener`'s view), handed on in global coordinates at its
/// stamps, with what the menu made of it ([heard]) as the events the
/// region plays haptics for.
final class _ObservedTouch extends Interaction {
  _ObservedTouch({
    required this.down,
    required this.move,
    required this.up,
    required this.cancel,
    required this.heard,
  }) : super(role: InteractionRole.observer);

  final void Function(int pointer, double t, Offset global) down;
  final void Function(int pointer, double t, Offset global) move;
  final void Function(int pointer, double t, Offset global) up;
  final void Function(int pointer, double t) cancel;
  final List<InteractionEvent> Function() heard;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        down(input.pointer, input.time, input.globalPosition);
      case PointerMoveInput():
        move(input.pointer, input.time, input.globalPosition);
      case PointerUpInput():
        up(input.pointer, input.time, input.globalPosition);
      case PointerCancelInput():
        cancel(input.pointer, input.time);
      default:
        return InteractionUpdate.none;
    }
    final events = heard();
    return events.isEmpty
        ? InteractionUpdate.none
        : InteractionUpdate(events: events);
  }
}
