import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/sheet_motion.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Shows an iOS 27 sheet over the page and completes with the result it
/// is closed with.
///
/// UIKit: `UISheetPresentationController`. SwiftUI: `sheet` with
/// `presentationDetents`. Flutter: `showModalBottomSheet`,
/// `showCupertinoSheet`.
///
/// The sheet rests at one of its `detents`, the first or `initialDetent`
/// to begin with. Below [GlassSheetDetent.large] it floats on glass 8
/// points from the screen's sides and bottom with the display's corners;
/// at the large detent it docks, opaque and square at the bottom. It moves
/// between them on UIKit's critically damped spring of response 0.344
/// (read from UIKit, replayed against the iPhone 16 Pro): a drag carries
/// it and rubber-bands past its largest and smallest detents, a release
/// picks the detent its speed projects to, a drag down past the smallest
/// dismisses it, and a tap at its top cycles to the next detent.
///
/// Detents at or below `largestUndimmedDetent` leave the page undimmed
/// and touchable; the others dim it 20 percent. A keyboard raises every
/// detent by its height. A drag on the content's main scrollable, driven
/// by [GlassSheet.scrollControllerOf], moves the sheet first while the
/// content is at its top, and expands it toward its largest detent when
/// `scrollingExpandsSheet`. Back and `Navigator.pop` close it; a drag
/// down, a tap on the dimming, Escape and a screen reader's dismiss close
/// it when `isDismissible` and no `PopScope` in it vetoes, and otherwise
/// call `onDismissAttempt`.
///
/// The liquid renderer draws the floating glass with the top corners'
/// radius all round, clipped at the bottom to the display's corners: its
/// rim light at the bottom corners follows a 38 point curve under a 54
/// point clip (near).
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  List<GlassSheetDetent> detents = const [GlassSheetDetent.large],
  GlassSheetDetent? initialDetent,
  GlassSheetDetent? largestUndimmedDetent,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool scrollingExpandsSheet = true,
  String? semanticLabel,
  ValueChanged<GlassSheetDetent>? onDetentChanged,
  VoidCallback? onDismissAttempt,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  GlassSheetRoute<T>(
    builder: builder,
    detents: detents,
    initialDetent: initialDetent,
    largestUndimmedDetent: largestUndimmedDetent,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    scrollingExpandsSheet: scrollingExpandsSheet,
    semanticLabel: semanticLabel,
    onDetentChanged: onDetentChanged,
    onDismissAttempt: onDismissAttempt,
  ),
  level: level,
);

/// The route [showGlassSheet] pushes.
final class GlassSheetRoute<T> extends PresentationRoute<T> {
  /// Creates the route of a sheet.
  GlassSheetRoute({
    required this.builder,
    this.detents = const [GlassSheetDetent.large],
    this.initialDetent,
    this.largestUndimmedDetent,
    this.showDragHandle = false,
    this.isDismissible = true,
    this.scrollingExpandsSheet = true,
    String? semanticLabel,
    this.onDetentChanged,
    this.onDismissAttempt,
    super.settings,
  }) : assert(detents.isNotEmpty, 'a sheet rests at a detent'),
       super(semanticsLabel: semanticLabel);

  /// Builds the sheet's content.
  final WidgetBuilder builder;

  /// The heights the sheet rests at.
  final List<GlassSheetDetent> detents;

  /// The detent the sheet presents at; null for the first of [detents].
  final GlassSheetDetent? initialDetent;

  /// The largest detent that leaves the page undimmed and touchable; null
  /// dims at every detent.
  final GlassSheetDetent? largestUndimmedDetent;

  /// Whether the grabber shows at the sheet's top.
  final bool showDragHandle;

  /// Whether the user may dismiss the sheet by a drag down, a tap outside,
  /// Escape or a screen reader's dismiss; Back and `Navigator.pop` close it
  /// either way.
  final bool isDismissible;

  /// Whether a drag up on content scrolled to its top expands the sheet
  /// toward its largest detent before the content scrolls (UIKit's
  /// `prefersScrollingExpandsWhenScrolledToEdge`).
  final bool scrollingExpandsSheet;

  /// Called with the detent the user moves the sheet to, by a drag or a
  /// tap at its top; [GlassSheet.animateTo] does not call it.
  final ValueChanged<GlassSheetDetent>? onDetentChanged;

  /// Called when the user tries to dismiss a sheet that stays (UIKit's
  /// `presentationControllerDidAttemptToDismiss`).
  final VoidCallback? onDismissAttempt;

  _SheetViewState? _view;

  @override
  bool allows(DismissTrigger trigger) => switch (trigger) {
    .back || .programmatic => true,
    .outsideTap || .escape || .accessibility || .interaction => isDismissible,
  };

  @override
  void didVetoDismiss(DismissTrigger trigger) => onDismissAttempt?.call();

  @override
  bool get modal => _view?._structure.value.dimmed ?? true;

  @override
  Widget buildContent(BuildContext context) => _SheetView(route: this);

  @override
  bool leave(DismissTrigger trigger) {
    final view = _view;
    if (view == null || !view.mounted) return false;
    view._leave();
    return true;
  }
}

/// What a sheet's content can do with its sheet.
abstract interface class GlassSheet {
  /// The detent the sheet rests at or heads to.
  GlassSheetDetent get detent;

  /// The sheet's detents.
  List<GlassSheetDetent> get detents;

  /// Moves the sheet to [detent] on the sheet's spring.
  void animateTo(GlassSheetDetent detent);

  /// The sheet around [context]; [context] rebuilds when its detent
  /// changes.
  static GlassSheet of(BuildContext context) {
    final sheet = maybeOf(context);
    if (sheet == null) {
      throw FlutterError('GlassSheet.of called outside a GlassSheetRoute.');
    }
    return sheet;
  }

  /// The sheet around [context], or null outside one.
  static GlassSheet? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_SheetScope>(
        context,
        aspect: _SheetAspect.sheet,
      )?.state;

  /// A scroll controller for the sheet's main scrollable that hands its
  /// drags to the sheet as UIKit does; [context] does not rebuild when the
  /// detent changes.
  static ScrollController scrollControllerOf(BuildContext context) {
    final scope = InheritedModel.inheritFrom<_SheetScope>(
      context,
      aspect: _SheetAspect.controller,
    );
    if (scope == null) {
      throw FlutterError(
        'GlassSheet.scrollControllerOf called outside a GlassSheetRoute.',
      );
    }
    return scope.state._scroll;
  }
}

enum _SheetAspect { sheet, controller }

class _SheetScope extends InheritedModel<_SheetAspect> {
  const _SheetScope({
    required this.state,
    required this.detent,
    required super.child,
  });

  final _SheetViewState state;
  final GlassSheetDetent detent;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) =>
      oldWidget.detent != detent || oldWidget.state != state;

  @override
  bool updateShouldNotifyDependent(
    _SheetScope oldWidget,
    Set<_SheetAspect> dependencies,
  ) =>
      oldWidget.state != state ||
      (oldWidget.detent != detent && dependencies.contains(_SheetAspect.sheet));
}

/// What the sheet's tree is built from; it rebuilds only when this changes.
typedef _Structure = ({bool opaque, bool filling, bool dimmed});

/// The sheet's geometry in one frame.
@immutable
class _Frame {
  const _Frame({
    required this.height,
    required this.transform,
    required this.body,
  });

  final double height;
  final Matrix4 transform;
  final RSuperellipse body;
}

/// The colors of a sheet, light and dark (simulator).
abstract final class _Colors {
  static const docked = GlassDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1C1E),
  );
  static const grabber = GlassDynamicColor.withBrightness(
    color: Color(0x4D3C3C43),
    darkColor: Color(0x4DEBEBF5),
  );
}

class _SheetView extends StatefulWidget {
  const _SheetView({required this.route});

  final GlassSheetRoute<Object?> route;

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView>
    implements MotionDriver, GlassSheet {
  SheetMotion? _motion;
  late final _SheetScrollController _scroll = _SheetScrollController(this);
  final _frame = ValueNotifier(
    _Frame(
      height: 0,
      transform: Matrix4.identity(),
      body: RSuperellipse.zero,
    ),
  );
  final _dim = ValueNotifier<double>(0);
  final _fill = ValueNotifier<double>(0);
  final _glass = ValueNotifier(
    const GlassFrame(
      shape: LiquidRoundedSuperellipse(borderRadius: SheetTuning.topRadius),
    ),
  );
  final _structure = ValueNotifier<_Structure>((
    opaque: false,
    filling: false,
    dimmed: true,
  ));
  List<int> _order = const [];
  int _index = 0;
  Size _size = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;
  double _keyboard = 0;
  double? _fitted;
  double? _displayRadius;
  bool _leaving = false;
  double _dragY = 0;
  double _stamp = 0;
  double? _slopFrom;
  bool _awaitingSlop = false;
  int? _touch;
  Offset _touchFrom = Offset.zero;
  bool _touchDragged = false;

  // A move is stamped only when a drag consumes it, so a finger moving
  // over a resting sheet (a list scrolling inside it) costs no motion
  // frames.
  PointerMoveEvent? _unstampedMove;

  // The release velocity is the tracker's raw estimate with the lift's own
  // sample: DragEndDetails reads it without that sample, zeroes it below
  // the fling threshold and clamps it, so a replay of the same stamps would
  // end differently.
  VelocityTracker? _tracker;
  double? _releaseVelocity;

  GlassSheetRoute<Object?> get _route => widget.route;

  double get _now => MotionClock.instance.now;

  @override
  List<GlassSheetDetent> get detents => _route.detents;

  @override
  GlassSheetDetent get detent => detents[_index];

  @override
  void initState() {
    super.initState();
    _route._view = this;
    _index = math.max(0, detents.indexOf(_route.initialDetent ?? detents[0]));
    MotionClock.instance.addDriver(this);
  }

  @override
  void dispose() {
    if (identical(_route._view, this)) _route._view = null;
    MotionClock.instance.removeDriver(this);
    _scroll.dispose();
    _frame.dispose();
    _dim.dispose();
    _fill.dispose();
    _glass.dispose();
    _structure.dispose();
    super.dispose();
  }

  @override
  bool get isActive => !(_motion?.isSettled ?? true);

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    final motion = _motion;
    if (motion == null) return;
    motion.advance(time);
    _deliver();
    _publish();
    if (_leaving && motion.isDismissed) {
      _route.didLeave();
    } else if (!_leaving && motion.isSettled) {
      _route.didOpen();
    }
  }

  void _wake() => MotionClock.instance.wake(this);

  @override
  void animateTo(GlassSheetDetent detent) {
    final i = detents.indexOf(detent);
    final motion = _motion;
    if (i < 0 || motion == null || _leaving) return;
    motion.animateTo(_now, _order.indexOf(i));
    _deliver();
    _wake();
  }

  void _deliver() {
    final motion = _motion;
    if (motion == null) return;
    for (final event in motion.drainEvents()) {
      if (!mounted) return;
      switch (event) {
        case SheetDetentChanged(:final index, :final byUser):
          setState(() => _index = _order[index]);
          // UIKit reports a detent the user picks, not one set from code.
          if (byUser) _route.onDetentChanged?.call(detent);
        case SheetDismissed() || SheetDismissRefused():
          if (!_leaving) _route.dismiss(DismissTrigger.interaction);
      }
    }
  }

  void _leave() {
    _leaving = true;
    final motion = _motion;
    if (motion == null) {
      _route.didLeave();
      return;
    }
    if (motion.isDragging) motion.dragCancel(_now);
    if (!motion.isDismissing) motion.dismiss(_now);
    _wake();
  }

  bool get _dismissAllowed => _route.canDismiss(DismissTrigger.interaction);

  void _outside() {
    if (!_leaving) _route.dismiss(DismissTrigger.outsideTap);
  }

  void _fittedHeight(double height) {
    if (!mounted || _fitted == height) return;
    setState(() => _fitted = height);
  }

  // A keyboard raises the sheet as UIKit's does (simulator capture): each
  // detent grows by the keyboard's height up to the maximum, and the sheet
  // moves to its largest detent while the keyboard shows, back to the
  // selected one when it hides, neither reported as a detent change.
  void _layout(Size size, EdgeInsets padding, double keyboard) {
    if (size == _size &&
        padding == _padding &&
        keyboard == _keyboard &&
        _motion != null) {
      return;
    }
    final raised = keyboard > 0;
    final wasRaised = _keyboard > 0;
    _size = size;
    _padding = padding;
    _keyboard = keyboard;
    final maximum = math.max<double>(
      0,
      size.height - padding.top - padding.bottom,
    );
    final values = [
      for (final d in detents)
        math.min(
              d.resolve(maximum, fittedHeight: _fitted) + keyboard,
              maximum,
            ) +
            padding.bottom,
    ];
    final order = List<int>.generate(detents.length, (i) => i);
    order.sort((a, b) => values[a].compareTo(values[b]));
    _order = order;
    final heights = [for (final i in order) values[i]];
    final docked = order.indexWhere((i) => detents[i].isLarge);
    final undimmed = _route.largestUndimmedDetent;
    final undimmedAt = undimmed == null
        ? -1
        : order.indexWhere((i) => detents[i] == undimmed);
    final index = raised ? order.length - 1 : order.indexOf(_index);
    final motion = _motion;
    if (motion == null) {
      final created = SheetMotion(
        heights: heights,
        width: size.width,
        initial: index,
        fullHeight: maximum + padding.bottom,
        dockedIndex: docked < 0 ? null : docked,
        undimmedIndex: undimmedAt < 0 ? null : undimmedAt,
        dismissible: _route.isDismissible,
        displayRadius: _displayRadius,
      );
      created.present(_now);
      _motion = created;
    } else {
      motion.relayout(
        _now,
        heights,
        size.width,
        fullHeight: maximum + padding.bottom,
        index: raised == wasRaised ? null : index,
      );
    }
    _wake();
  }

  void _publish() {
    final motion = _motion;
    if (motion == null) return;
    final h = motion.height;
    final drawn = motion.visibleRect(_size.height);
    final k = _size.width <= 0 ? 1.0 : drawn.width / _size.width;
    final ky = motion.stretch != 1 && h > 0 ? drawn.height / h : k;
    final transform = Matrix4.translationValues(drawn.left, drawn.top, 0);
    transform.multiply(Matrix4.diagonal3Values(k, ky, 1));
    final bottom = Radius.circular(motion.bottomRadius);
    const top = Radius.circular(SheetTuning.topRadius);
    _frame.value = _Frame(
      height: h,
      transform: transform,
      body: RSuperellipse.fromLTRBAndCorners(
        0,
        0,
        _size.width,
        h,
        topLeft: top,
        topRight: top,
        bottomLeft: bottom,
        bottomRight: bottom,
      ),
    );
    final dim = SheetTuning.dimmingOpacity * motion.dimming;
    final fill = motion.fill;
    _dim.value = dim;
    _fill.value = fill;
    final structure = (opaque: fill >= 1, filling: fill > 0, dimmed: dim > 0);
    if (structure != _structure.value) {
      _structure.value = structure;
      _route.modalityChanged();
    }
  }

  void _stampEvent(PointerEvent event) {
    _unstampedMove = null;
    _stamp = MotionClock.instance.stamp(event.timeStamp);
  }

  void _stampMove() {
    final move = _unstampedMove;
    if (move != null) _stampEvent(move);
  }

  void _down(PointerDownEvent event) {
    _stampEvent(event);
    final motion = _motion;
    if (motion == null ||
        _leaving ||
        _touch != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _touch = event.pointer;
    _touchFrom = event.localPosition;
    _slopFrom = event.position.dy;
    _touchDragged = false;
    final tracker = _tracker = VelocityTracker.withKind(event.kind);
    tracker.addPosition(event.timeStamp, event.position);
    _releaseVelocity = null;
    motion.press(_stamp);
    _wake();
  }

  void _move(PointerMoveEvent event) {
    _unstampedMove = event;
    if (event.pointer != _touch) return;
    _tracker?.addPosition(event.timeStamp, event.position);
    if ((event.localPosition - _touchFrom).distance > kTouchSlop) {
      _touchDragged = true;
    }
  }

  void _up(PointerEvent event) {
    _stampEvent(event);
    if (event.pointer != _touch) return;
    _touch = null;
    final tracker = _tracker;
    _tracker = null;
    if (event is PointerUpEvent && tracker != null) {
      tracker.addPosition(event.timeStamp, event.position);
      _releaseVelocity = tracker.getVelocity().pixelsPerSecond.dy;
    }
    final motion = _motion;
    if (motion == null) return;
    if (!motion.isDragging) motion.unpress(_stamp);
    if (event is PointerUpEvent &&
        !_touchDragged &&
        _touchFrom.dy < SheetTuning.grabberHitHeight) {
      if (motion.isDragging) motion.dragCancel(_stamp);
      motion.tapGrabber(_stamp);
    }
    _deliver();
    _wake();
  }

  void _configureDrag(VerticalDragGestureRecognizer drag) {
    drag.gestureSettings = const DeviceGestureSettings(
      touchSlop: SheetTuning.dragSlop,
    );
    drag.onStart = _dragStart;
    drag.onUpdate = _dragUpdate;
    drag.onEnd = _dragEnd;
    drag.onCancel = _dragCancel;
  }

  void _dragCancel() {
    if (_awaitingSlop) {
      _awaitingSlop = false;
      return;
    }
    _motion?.dragCancel(_now);
    _wake();
  }

  // Alone in the gesture arena the drag is accepted at the touch, so the
  // sheet waits out UIKit's slop itself: it starts where the finger is
  // SheetTuning.dragSlop from the touch, as the device does.
  bool _pastSlop(double y) =>
      (y - (_slopFrom ?? y)).abs() >= SheetTuning.dragSlop;

  void _dragStart(DragStartDetails details) {
    _stampMove();
    _awaitingSlop = !_pastSlop(details.globalPosition.dy);
    if (!_awaitingSlop) _beginDrag(details.globalPosition.dy);
  }

  void _beginDrag(double y) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    motion.dismissible = _dismissAllowed;
    _dragY = y;
    motion.dragStart(_stamp, _dragY);
    _wake();
  }

  void _dragUpdate(DragUpdateDetails details) {
    _stampMove();
    final y = details.globalPosition.dy;
    if (_awaitingSlop) {
      if (!_pastSlop(y)) return;
      _awaitingSlop = false;
      _beginDrag(y);
      return;
    }
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    _dragY = y;
    motion.dragUpdate(_stamp, _dragY);
  }

  void _dragEnd(DragEndDetails details) {
    final velocity = _releaseVelocity;
    _releaseVelocity = null;
    _release(velocity ?? details.velocity.pixelsPerSecond.dy);
  }

  void _release(double velocity) {
    _stampMove();
    if (_awaitingSlop) {
      _awaitingSlop = false;
      return;
    }
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragEnd(math.max(_stamp, _now), velocity);
    _deliver();
    _wake();
  }

  void _scrollDragBy(double delta) {
    _stampMove();
    final motion = _motion;
    if (motion == null || _leaving) return;
    final t = math.max(_stamp, _now);
    if (!motion.isDragging) {
      motion.dismissible = _dismissAllowed;
      _dragY = 0;
      motion.dragStart(t, 0);
      _wake();
    }
    _dragY += delta;
    motion.dragUpdate(t, _dragY);
  }

  bool get _canExpand {
    final motion = _motion;
    if (motion == null) return false;
    return motion.height < motion.heights.last - 0.5;
  }

  bool get _scrollDragging => _motion?.isDragging ?? false;

  // The content widget is reused while its inputs hold, so a rebuild of
  // the chrome (each keyboard-inset frame) leaves the app's builder alone.
  // A detent change hands the scope a new detent over the same content:
  // only what reads the sheet through GlassSheet.of rebuilds.
  Widget? _content;
  TextStyle? _style;
  _SheetScope? _scope;

  Widget _contentFor(BuildContext context) {
    final style = resolveGlassText(
      TextStyle(
        fontSize: 17,
        color: GlassDynamicColor.resolve(
          GlassTheme.of(context).colorScheme?.label ?? GlassColors.label,
          context,
        ),
      ),
      context,
    );
    var content = _content;
    if (content == null || style != _style) {
      _style = style;
      _scope = null;
      content = _content = DefaultTextStyle(
        style: style,
        child: detents.any((d) => d.isFitted)
            ? _FitReport(
                onHeight: _fittedHeight,
                child: Builder(builder: _route.builder),
              )
            : Builder(builder: _route.builder),
      );
    }
    final scope = _scope;
    if (scope != null && scope.detent == detent) return scope;
    return _scope = _SheetScope(state: this, detent: detent, child: content);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    _displayRadius = MediaQuery.maybeDisplayCornerRadiiOf(
      context,
    )?.bottomLeft.x;
    final content = _contentFor(context);
    final docked = GlassDynamicColor.resolve(_Colors.docked, context);
    final grabber = GlassDynamicColor.resolve(_Colors.grabber, context);
    final inner = MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          top: 0,
          bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
        ),
        viewPadding: media.viewPadding.copyWith(top: 0),
        viewInsets: EdgeInsets.zero,
      ),
      child: content,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _layout(
          constraints.biggest,
          EdgeInsets.only(top: media.padding.top, bottom: media.padding.bottom),
          media.viewInsets.bottom,
        );
        _motion!.displayRadius = _displayRadius;
        _publish();
        return ValueListenableBuilder<_Structure>(
          valueListenable: _structure,
          child: inner,
          builder: (context, structure, child) => Stack(
            children: [
              if (structure.dimmed)
                Positioned.fill(
                  key: const ValueKey('dim'),
                  child: Semantics(
                    onTap: _route.isDismissible ? _outside : null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _outside,
                      child: MotionTransition(
                        opacity: _dim,
                        child: const ColoredBox(color: Color(0xFF000000)),
                      ),
                    ),
                  ),
                ),
              // Keyed so the dimming appearing mid-drag does not re-inflate
              // the sheet and dispose its drag recognizer.
              Positioned.fill(
                key: const ValueKey('sheet'),
                child: _SheetBox(
                  frame: _frame,
                  child: Semantics(
                    explicitChildNodes: true,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _down,
                      onPointerMove: _move,
                      onPointerUp: _up,
                      onPointerCancel: _up,
                      child: RawGestureDetector(
                        behavior: HitTestBehavior.opaque,
                        gestures: {
                          VerticalDragGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                VerticalDragGestureRecognizer
                              >(
                                () => VerticalDragGestureRecognizer(
                                  debugOwner: this,
                                ),
                                _configureDrag,
                              ),
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (!structure.opaque)
                              GlassSurface.live(
                                role: GlassRole.sheet,
                                frame: _glass,
                                child: const SizedBox.expand(),
                              ),
                            if (structure.opaque)
                              ColoredBox(color: docked)
                            else if (structure.filling)
                              MotionTransition(
                                opacity: _fill,
                                child: ColoredBox(color: docked),
                              ),
                            child!,
                            if (_route.showDragHandle)
                              Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    top:
                                        SheetTuning.grabberOffset -
                                        SheetTuning.grabberSize.height / 2,
                                  ),
                                  child: DecoratedBox(
                                    decoration: ShapeDecoration(
                                      color: grabber,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: SizedBox.fromSize(
                                      size: SheetTuning.grabberSize,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lays the sheet out as tall as its frame and draws it moved, scaled and
/// clipped to its body by the frame, laying out again only when its height
/// changes.
class _SheetBox extends SingleChildRenderObjectWidget {
  const _SheetBox({required this.frame, required super.child});

  final ValueListenable<_Frame> frame;

  @override
  _RenderSheetBox createRenderObject(BuildContext context) =>
      _RenderSheetBox(frame);
}

class _RenderSheetBox extends RenderProxyBox {
  _RenderSheetBox(this._frame);

  // The view's own notifier, which lives as long as the view.
  final ValueListenable<_Frame> _frame;

  double _laidOut = -1;
  final _clip = LayerHandle<ClipRSuperellipseLayer>();

  void _changed() {
    if (_frame.value.height != _laidOut) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_changed);
  }

  @override
  void detach() {
    _frame.removeListener(_changed);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void performLayout() {
    size = constraints.biggest;
    final h = _frame.value.height;
    _laidOut = h;
    child?.layout(BoxConstraints.tight(Size(size.width, math.max(0, h))));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final frame = _frame.value;
    return result.addWithPaintTransform(
      transform: frame.transform,
      position: position,
      hitTest: (result, local) =>
          frame.body.contains(local) && child.hitTest(result, position: local),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_frame.value.transform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final frame = _frame.value;
    context.pushTransform(needsCompositing, offset, frame.transform, (
      context,
      offset,
    ) {
      _clip.layer = context.pushClipRSuperellipse(
        needsCompositing,
        offset,
        Offset.zero & child.size,
        frame.body,
        (context, offset) => context.paintChild(child, offset),
        oldLayer: _clip.layer,
      );
    });
  }
}

class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);

  final _SheetViewState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet: sheet,
    physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
    context: context,
    oldPosition: oldPosition,
  );
}

/// A scroll position that hands its drags to the sheet: a drag down on
/// content at its top moves the sheet, and a drag up expands it first when
/// it may; the content scrolls once the sheet has nowhere to go.
class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheet,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _SheetViewState sheet;
  bool _owns = false;

  @override
  void applyUserOffset(double delta) {
    if (_owns && delta < 0 && !sheet._canExpand) {
      _owns = false;
      sheet._release(0);
      super.applyUserOffset(delta);
      return;
    }
    final atTop = pixels <= minScrollExtent;
    if (_owns ||
        (delta > 0 && atTop) ||
        (delta < 0 && sheet._route.scrollingExpandsSheet && sheet._canExpand)) {
      _owns = true;
      sheet._scrollDragBy(delta);
      if (!sheet._scrollDragging) _owns = false;
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    if (_owns) {
      _owns = false;
      sheet._release(-velocity);
      super.goBallistic(0);
      return;
    }
    super.goBallistic(velocity);
  }

  @override
  void dispose() {
    if (_owns) sheet._release(0);
    super.dispose();
  }
}

/// Lays its child out with a loose height at its top and reports the
/// child's height after layout: the content height a fitted detent rests
/// at.
class _FitReport extends SingleChildRenderObjectWidget {
  const _FitReport({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  _RenderFitReport createRenderObject(BuildContext context) =>
      _RenderFitReport(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderFitReport renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderFitReport extends RenderProxyBox {
  _RenderFitReport(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      constraints.hasBoundedHeight
          ? Size(child.size.width, constraints.maxHeight)
          : child.size,
    );
    final height = child.size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
