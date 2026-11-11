import 'dart:math' as math;

import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/motions/sheet_motion.dart';
import 'package:apple_liquid_glass/src/surfaces/glass.dart';
import 'package:apple_liquid_glass/src/surfaces/shape.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of sheets, and of popovers that adapt to one; a null field
/// leaves it to the theme's style, then the default.
@immutable
class GlassSheetStyle {
  /// Creates a style.
  const GlassSheetStyle({
    this.backgroundColor,
    this.dragHandleColor,
    this.textStyle,
  });

  /// The opaque fill of a sheet that fills the screen or sits under
  /// another; white in light and 0x1C1C1E in dark by default (simulator).
  final Color? backgroundColor;

  /// The drag handle; 0x3C3C43 at 30 percent in light and 0xEBEBF5 at 30
  /// percent in dark (tertiaryLabel's color, simulator) by default.
  final Color? dragHandleColor;

  /// The default text of the content, over 17 points in label.
  final TextStyle? textStyle;

  /// This style over [other].
  GlassSheetStyle merge(GlassSheetStyle? other) {
    if (other == null) return this;
    return GlassSheetStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      dragHandleColor: dragHandleColor ?? other.dragHandleColor,
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassSheetStyle? lerp(
    GlassSheetStyle? a,
    GlassSheetStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    final color = snapNull(GlassDynamicColor.lerp);
    return GlassSheetStyle(
      backgroundColor: color(a.backgroundColor, b.backgroundColor, t),
      dragHandleColor: color(a.dragHandleColor, b.dragHandleColor, t),
      textStyle: snapNull(TextStyle.lerp)(a.textStyle, b.textStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSheetStyle &&
      other.backgroundColor == backgroundColor &&
      other.dragHandleColor == dragHandleColor &&
      other.textStyle == textStyle;

  @override
  int get hashCode => Object.hash(backgroundColor, dragHandleColor, textStyle);
}

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
/// point clip (NEAR).
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  List<GlassSheetDetent> detents = const [GlassSheetDetent.large],
  GlassSheetDetent? initialDetent,
  GlassSheetDetent? largestUndimmedDetent,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool scrollingExpandsSheet = true,
  GlassSheetStyle? style,
  String? semanticLabel,
  ValueChanged<GlassSheetDetent>? onDetentChanged,
  VoidCallback? onDismissAttempt,
  PresentationLevel level = PresentationLevel.window,
}) {
  assert(detents.isNotEmpty, 'a sheet rests at a detent');
  final spec = _SheetSpec(
    builder: builder,
    detents: detents,
    initialDetent: initialDetent,
    largestUndimmedDetent: largestUndimmedDetent,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    scrollingExpandsSheet: scrollingExpandsSheet,
    style: style,
    onDetentChanged: onDetentChanged,
  );
  return showPresentation(
    context,
    PresentationRoute(
      presentation: Presentation<T, _SheetPresented>(
        motion: (_) => _SheetPresented(),
        builder: (context, motion) => _SheetView(motion: motion, spec: spec),
        // Back and Navigator.pop close it either way.
        dismiss: isDismissible
            ? const DismissPolicy()
            : const DismissPolicy({DismissTrigger.back}),
        dim: (motion) =>
            SheetTuning.dimmingOpacity * (motion.sheet?.dimming ?? 0),
        modal: (motion) => (motion.sheet?.dimming ?? 1) > 0,
        onVeto: onDismissAttempt == null ? null : (_) => onDismissAttempt(),
        semanticsLabel: semanticLabel,
      ),
    ),
    level: level,
  );
}

/// What [showGlassSheet] was asked for.
@immutable
class _SheetSpec {
  const _SheetSpec({
    required this.builder,
    required this.detents,
    required this.initialDetent,
    required this.largestUndimmedDetent,
    required this.showDragHandle,
    required this.isDismissible,
    required this.scrollingExpandsSheet,
    required this.style,
    required this.onDetentChanged,
  });

  final WidgetBuilder builder;
  final List<GlassSheetDetent> detents;
  final GlassSheetDetent? initialDetent;
  final GlassSheetDetent? largestUndimmedDetent;
  final bool showDragHandle;
  final bool isDismissible;
  final bool scrollingExpandsSheet;
  final GlassSheetStyle? style;
  final ValueChanged<GlassSheetDetent>? onDetentChanged;

  GlassSheetStyle lookOf(BuildContext context) =>
      (style ?? const GlassSheetStyle()).merge(
        GlassTheme.of(context).sheetStyle,
      );
}

/// A sheet's presentation: its [SheetMotion] comes with the first layout,
/// whose detents it needs, and presents then.
final class _SheetPresented extends Motion with Presented {
  SheetMotion? _sheet;
  bool _opened = false;
  bool _left = false;

  // UIKit asks at least 80 Hz of this (read from UIKit, notes private).
  @override
  double get minFrameRate => 80;

  SheetMotion? get sheet => _sheet;

  /// Whether the presentation was dismissed.
  bool get left => _left;

  void attach(double t, SheetMotion sheet) {
    _sheet = own(sheet);
    if (_opened && !_left) sheet.present(t);
  }

  @override
  PresenceStatus get presence {
    final sheet = _sheet;
    if (sheet == null) return _opened && !_left ? .opening : .hidden;
    if (sheet.isDismissing) return sheet.isDismissed ? .hidden : .leaving;
    return isSettled ? .shown : .opening;
  }

  @override
  void open(double t) => _opened = true;

  @override
  bool leave(double t, DismissTrigger trigger) {
    _left = true;
    final sheet = _sheet;
    if (sheet == null) return false;
    if (sheet.isDragging) sheet.dragCancel(t);
    if (!sheet.isDismissing) sheet.dismiss(t);
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
      throw FlutterError('GlassSheet.of called outside a glass sheet.');
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
        'GlassSheet.scrollControllerOf called outside a glass sheet.',
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
  bool updateShouldNotify(_SheetScope oldWidget) => oldWidget.detent != detent;

  @override
  bool updateShouldNotifyDependent(
    _SheetScope oldWidget,
    Set<_SheetAspect> dependencies,
  ) => oldWidget.detent != detent && dependencies.contains(_SheetAspect.sheet);
}

/// What the sheet's tree is built from; it rebuilds only when this changes.
typedef _Structure = ({bool opaque, bool filling});

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
  const _SheetView({required this.motion, required this.spec});

  final _SheetPresented motion;
  final _SheetSpec spec;

  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView> implements GlassSheet {
  // Everything _publish reads, so a frame that moved the sheet publishes it
  // and one that did not costs nothing.
  late final MotionSelection<Object?> _frames = widget.motion.select((m) {
    final sheet = m.sheet;
    if (sheet == null) return null;
    return (
      sheet.height,
      sheet.visibleRect(_size.height),
      sheet.bottomRadius,
      sheet.fill,
      sheet.hasEvents,
    );
  });
  late final _SheetScrollController _scroll = _SheetScrollController(this);
  final _frame = ValueNotifier(
    _Frame(
      height: 0,
      transform: Matrix4.identity(),
      body: RSuperellipse.zero,
    ),
  );
  final _fill = ValueNotifier<double>(0);
  final _structure = ValueNotifier<_Structure>((
    opaque: false,
    filling: false,
  ));
  List<int> _order = const [];
  int _index = 0;
  Size _size = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;
  double _keyboard = 0;
  double? _fitted;
  double? _displayRadius;
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

  _SheetSpec get _spec => widget.spec;

  SheetMotion? get _motion => widget.motion.sheet;

  bool get _leaving => widget.motion.left;

  double get _now => MotionClock.instance.now;

  @override
  List<GlassSheetDetent> get detents => _spec.detents;

  @override
  GlassSheetDetent get detent => detents[_index];

  @override
  void initState() {
    super.initState();
    _index = math.max(0, detents.indexOf(_spec.initialDetent ?? detents[0]));
    _frames.addListener(_stepped);
  }

  @override
  void dispose() {
    _frames.removeListener(_stepped);
    _scroll.dispose();
    _frame.dispose();
    _fill.dispose();
    _structure.dispose();
    super.dispose();
  }

  void _stepped() {
    _deliver();
    _publish();
  }

  @override
  void animateTo(GlassSheetDetent detent) {
    final i = detents.indexOf(detent);
    final motion = _motion;
    if (i < 0 || motion == null || _leaving) return;
    motion.animateTo(_now, _order.indexOf(i));
    _deliver();
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
          if (byUser) _spec.onDetentChanged?.call(detent);
        case SheetDismissed() || SheetDismissRefused():
          if (!_leaving) {
            PresentationHandle.of(
              context,
            ).dismiss(DismissTrigger.interaction);
          }
      }
    }
  }

  bool get _dismissAllowed =>
      PresentationHandle.of(context).canDismiss(DismissTrigger.interaction);

  void _fittedHeight(double t, Size size) {
    if (!mounted || _fitted == size.height) return;
    _fitted = size.height;
    _layout(_size, _padding, _keyboard, at: t);
  }

  // A keyboard raises the sheet as UIKit's does (simulator capture): each
  // detent grows by the keyboard's height up to the maximum, and the sheet
  // moves to its largest detent while the keyboard shows, back to the
  // selected one when it hides, neither reported as a detent change.
  void _layout(
    Size size,
    EdgeInsets padding,
    double keyboard, {
    double? at,
  }) {
    if (at == null &&
        size == _size &&
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
    final undimmed = _spec.largestUndimmedDetent;
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
        dismissible: _spec.isDismissible,
        displayRadius: _displayRadius,
      );
      widget.motion.attach(_now, created);
    } else {
      motion.relayout(
        at ?? _now,
        heights,
        size.width,
        fullHeight: maximum + padding.bottom,
        index: raised == wasRaised ? null : index,
      );
    }
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
    final fill = motion.fill;
    _fill.value = fill;
    _structure.value = (opaque: fill >= 1, filling: fill > 0);
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
  }

  double _contendedSlop = kTouchSlop;

  void _configureDrag(VerticalDragGestureRecognizer drag) {
    // A list in the sheet takes the touch at this slop, and asks first: at
    // UIKit's 12 the sheet would take a finger before any list could. Where
    // nothing else wants the touch it is accepted at once (see [_pastSlop]);
    // only over a control that wants it too, a drag starts past this slop.
    // NEAR: 18 points there, against 12 on the device.
    drag.gestureSettings = DeviceGestureSettings(touchSlop: _contendedSlop);
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
    final text = TextStyle(
      fontSize: 17,
      color: GlassTheme.of(context).labelColor,
    ).merge(_spec.lookOf(context).textStyle);
    final style = resolveGlassText(
      text.copyWith(color: GlassDynamicColor.resolve(text.color!, context)),
      context,
    );
    var content = _content;
    if (content == null || style != _style) {
      _style = style;
      _scope = null;
      content = _content = DefaultTextStyle(
        style: style,
        child: detents.any((d) => d.isFitted)
            ? Align(
                alignment: Alignment.topLeft,
                child: MotionMeasure(
                  onSize: _fittedHeight,
                  child: Builder(builder: _spec.builder),
                ),
              )
            : Builder(builder: _spec.builder),
      );
    }
    final scope = _scope;
    if (scope != null && scope.detent == detent) return scope;
    return _scope = _SheetScope(state: this, detent: detent, child: content);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    _contendedSlop = media.gestureSettings.touchSlop ?? kTouchSlop;
    _displayRadius = MediaQuery.maybeDisplayCornerRadiiOf(
      context,
    )?.bottomLeft.x;
    final content = _contentFor(context);
    final look = _spec.lookOf(context);
    final docked = GlassDynamicColor.resolve(
      look.backgroundColor ?? _Colors.docked,
      context,
    );
    final grabber = GlassDynamicColor.resolve(
      look.dragHandleColor ?? _Colors.grabber,
      context,
    );
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
          // Fitted content lays out up to the maximum, not the sheet's
          // height, so content that grows is measured at its new height
          // in the frame it grows, while the sheet follows a frame later.
          child: detents.any((d) => d.isFitted)
              ? OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: math.max(
                    0,
                    constraints.maxHeight -
                        media.padding.top -
                        media.padding.bottom,
                  ),
                  child: inner,
                )
              : inner,
          builder: (context, structure, child) => Stack(
            children: [
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
                              const GlassSurface(
                                shape: GlassShape.superellipse(
                                  SheetTuning.topRadius,
                                ),
                                role: GlassRole.panel,
                                part: GlassPart.sheet,
                                child: SizedBox.expand(),
                              ),
                            if (structure.opaque)
                              ColoredBox(color: docked)
                            else if (structure.filling)
                              MotionTransition(
                                opacity: _fill,
                                child: ColoredBox(color: docked),
                              ),
                            child!,
                            if (_spec.showDragHandle)
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

  // The glass renderer places a resting sheet's backdrop pass from its
  // ancestors' clips, as Impeller sizes the pass; without this clip the
  // sheet's glass sits off by the sheet's inset at rest.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    final frame = _frame.value;
    return MatrixUtils.transformRect(frame.transform, frame.body.outerRect);
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
        (delta < 0 && sheet._spec.scrollingExpandsSheet && sheet._canExpand)) {
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
