import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/alert_motion.dart';
import 'package:apple_liquid_glass/src/motion/glass_press.dart';
import 'package:apple_liquid_glass/src/motion/popover_motion.dart';
import 'package:apple_liquid_glass/src/presentations/popover.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

enum _Role { normal, cancel, destructive }

/// One button of an alert or an action sheet.
///
/// UIKit: `UIAlertAction`. SwiftUI: a `Button` in `alert` or
/// `confirmationDialog`. Flutter: `CupertinoDialogAction`.
@immutable
class GlassAlertAction {
  /// Creates an action showing [child].
  const GlassAlertAction({
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.enabled = true,
  }) : _role = _Role.normal;

  /// Creates the action that cancels: it goes first in a row of two buttons
  /// and last in a column, and Escape, Back and a screen reader's dismiss
  /// choose it.
  const GlassAlertAction.cancel({
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.enabled = true,
  }) : _role = _Role.cancel;

  /// Creates an action that destroys data: its label is red.
  const GlassAlertAction.destructive({
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.enabled = true,
  }) : _role = _Role.destructive;

  /// The button's label.
  final Widget child;

  /// Called once the alert has gone after the user chose this action, as
  /// UIKit calls an action's handler after the dismissal.
  final VoidCallback? onPressed;

  /// Whether this is the preferred action: its button is filled with the
  /// accent color, its label semibold, and Return chooses it.
  final bool isDefaultAction;

  /// Whether the button takes taps; a disabled one keeps its fill and draws
  /// its label in tertiary label color, and a disabled default one loses
  /// its accent fill (iPhone 16 Pro, iOS 27.0.1).
  final bool enabled;

  final _Role _role;

  /// Whether this action cancels.
  bool get isCancel => _role == _Role.cancel;

  /// Whether this action destroys data.
  bool get isDestructive => _role == _Role.destructive;
}

/// Shows an iOS 27 alert and completes with the action chosen, or null
/// when it was closed without one.
///
/// UIKit: `UIAlertController` with the alert style. SwiftUI: `alert`.
/// Flutter: `showCupertinoDialog` with a `CupertinoAlertDialog`.
///
/// A glass platter 320 points wide with corners of 34 holds the [title],
/// the [message] and the [actions], two side by side when their labels fit
/// and a column otherwise, over a black dimming at 20 percent. It presents
/// by fading in with the dimming while it shrinks from 1.199 times its
/// size, and leaves by fading, on one critically damped spring of response
/// 0.275 s (read from UIKit's `CASpringAnimation`, replayed on the iPhone
/// 16 Pro); under Reduce Motion it presents at its size. A finger slides
/// between the buttons and chooses the one it lifts from, lifting the
/// whole platter as a glass button lifts. The chosen action's handler runs
/// once the alert has gone. Escape, Back and a screen reader's dismiss
/// choose the cancel action; without one they do nothing, and neither
/// does a tap outside.
Future<GlassAlertAction?> showGlassAlert(
  BuildContext context, {
  Widget? title,
  Widget? message,
  List<GlassAlertAction> actions = const [],
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  PresentationRoute(
    presentation: _alert(
      title: title,
      message: message,
      actions: actions,
      actionSheet: false,
    ),
  ),
  level: level,
);

/// Shows an iOS 27 action sheet and completes with the action chosen, or
/// null when it was closed without one.
///
/// UIKit: `UIAlertController` with the action sheet style. SwiftUI:
/// `confirmationDialog`. Flutter: `showCupertinoModalPopup` with a
/// `CupertinoActionSheet`.
///
/// With a source, [anchor] (a context inside the control that summoned
/// it, laid out) or [anchorRect] (in global coordinates), the action sheet
/// is a glass popover 240 points wide next to the source, as iOS 27
/// presents one on an iPhone: it grows out of its arrow's tip and shrinks
/// back into it (see [showGlassPopover]), does not lift under a finger and
/// leaves the cancel action out, which a tap outside chooses. Without a
/// source an action sheet is an alert whose actions stand in a column with
/// the cancel action last; a tap outside chooses the cancel action, or
/// closes it without one.
Future<GlassAlertAction?> showGlassActionSheet(
  BuildContext context, {
  Widget? title,
  Widget? message,
  List<GlassAlertAction> actions = const [],
  BuildContext? anchor,
  Rect? anchorRect,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  PresentationRoute(
    presentation: _alert(
      title: title,
      message: message,
      actions: actions,
      actionSheet: true,
      anchorRect: anchor == null && anchorRect == null
          ? null
          : popoverSource(
              anchor: anchor,
              anchorRect: anchorRect,
              caller: 'showGlassActionSheet',
            ),
    ),
  ),
  level: level,
);

// An alert waits for an answer: without a cancel action only its buttons
// close it. Back, Escape and a screen reader's dismiss choose the cancel
// action, and its handler runs once the alert has gone.
Presentation<GlassAlertAction, Presented> _alert({
  required Widget? title,
  required Widget? message,
  required List<GlassAlertAction> actions,
  required bool actionSheet,
  Rect? anchorRect,
}) {
  final cancel = _cancelOf(actions);
  final keys = actionSheet || cancel != null;
  return Presentation(
    motion: (_) => anchorRect == null ? AlertMotion() : PopoverMotion(),
    builder: (context, motion) => _AlertView(
      motion: motion,
      title: title,
      message: message,
      actions: actions,
      actionSheet: actionSheet,
      anchorRect: anchorRect,
    ),
    dismiss: DismissPolicy({
      if (actionSheet) DismissTrigger.outsideTap,
      if (keys) ...{
        DismissTrigger.escape,
        DismissTrigger.back,
        DismissTrigger.accessibility,
      },
      DismissTrigger.interaction,
    }),
    dim: anchorRect == null
        ? (motion) =>
              AlertTuning.dimmingOpacity * (motion as AlertMotion).dimming
        : null,
    result: (result) => result ?? cancel,
    onDismissed: (action) => action?.onPressed?.call(),
    semanticsLabel: _text(title) ?? _text(message),
  );
}

String? _text(Widget? widget) => switch (widget) {
  Text(:final data?) => data,
  _ => null,
};

// A disabled cancel action answers nothing, as its button does nothing.
GlassAlertAction? _cancelOf(List<GlassAlertAction> actions) {
  for (final action in actions) {
    if (action.isCancel) return action.enabled ? action : null;
  }
  return null;
}

/// The actions in the order they show: the cancel action first in a row,
/// last in a column, and left out of a popover.
List<GlassAlertAction> _ordered(
  List<GlassAlertAction> actions, {
  required bool row,
  required bool popover,
}) {
  final cancel = [
    for (final a in actions)
      if (a.isCancel) a,
  ];
  final rest = [
    for (final a in actions)
      if (!a.isCancel) a,
  ];
  if (popover) return rest;
  return row ? [...cancel, ...rest] : [...rest, ...cancel];
}

// The message color of an alert, light and dark (UIKit's rendering on an
// iPhone 16 Pro).
const _messageColor = GlassDynamicColor.withBrightness(
  color: Color(0x993C3C43),
  darkColor: Color(0x99EBEBF5),
);

class _AlertView extends StatefulWidget {
  const _AlertView({
    required this.motion,
    required this.title,
    required this.message,
    required this.actions,
    required this.actionSheet,
    required this.anchorRect,
  });

  // An AlertMotion, or a PopoverMotion for an action sheet with a source.
  final Presented motion;
  final Widget? title;
  final Widget? message;
  final List<GlassAlertAction> actions;
  final bool actionSheet;
  final Rect? anchorRect;

  @override
  State<_AlertView> createState() => _AlertViewState();
}

class _AlertViewState extends State<_AlertView> implements MotionDriver {
  late final AlertMotion? _alert = switch (widget.motion) {
    final AlertMotion alert => alert,
    _ => null,
  };
  late final PopoverMotion? _popover = switch (widget.motion) {
    final PopoverMotion popover => popover,
    _ => null,
  };
  final _press = GlassPress();
  final _card = GlobalKey();
  late final List<GlobalKey> _keys = [
    for (final _ in widget.actions) GlobalKey(),
  ];
  final _highlighted = ValueNotifier<GlassAlertAction?>(null);
  late final MotionSelection<double> _opacity;
  late final MotionSelection<double> _scale;
  late final MotionSelection<bool> _leaving;
  late final MotionSelection<GlassFrame> _frame;
  final _lean = ValueNotifier<Offset>(Offset.zero);
  final _pressX = ValueNotifier<double>(1);
  final _pressY = ValueNotifier<double>(1);
  static const LiquidShape _platter = LiquidRoundedSuperellipse(
    borderRadius: AlertTuning.cornerRadius,
  );

  List<GlassAlertAction> _shown = const [];
  int? _pointer;
  // A finger that scrolled the content chooses nothing until it lifts.
  bool _scrolled = false;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    if (_popover case final popover?) {
      _opacity = popover.select((m) => m.opacity);
      _scale = popover.select((m) => m.scale);
      _leaving = popover.select((m) => m.isLeaving);
      _frame = popover.select((m) => GlassFrame(opacity: m.opacity));
    } else {
      final alert = _alert!;
      _opacity = alert.select((m) => m.opacity);
      _scale = alert.select((m) => m.scale);
      _leaving = alert.select((m) => m.isLeaving);
      _frame = alert.select(
        (m) => GlassFrame(shape: _platter, opacity: m.opacity),
      );
      MotionClock.instance.addDriver(this);
    }
    _leaving.addListener(_left);
  }

  @override
  void dispose() {
    _leaving.removeListener(_left);
    MotionClock.instance.removeDriver(this);
    _pressX.dispose();
    _pressY.dispose();
    _highlighted.dispose();
    _lean.dispose();
    super.dispose();
  }

  // The press runs on its own until it is a part of the alert's motion.
  @override
  bool get isActive => !_press.isSettled;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _press.advance(time);
    if (_press.isSettled) _press.settle();
    _lean.value = _press.lean;
    _pressX.value = _press.scaleX;
    _pressY.value = _press.scaleY;
  }

  void _left() {
    if (!_leaving.value) return;
    if (_press.isPressed) _press.pointerCancel(_now);
    _pointer = null;
    _highlighted.value = null;
    setState(() {});
    MotionClock.instance.wake(this);
  }

  void _choose(GlassAlertAction action) {
    if (_leaving.value || !action.enabled) return;
    PresentationHandle.of(
      context,
    ).dismiss(DismissTrigger.programmatic, action);
  }

  void _return() {
    for (final action in _shown) {
      if (action.isDefaultAction) {
        _choose(action);
        return;
      }
    }
  }

  GlassAlertAction? _actionAt(Offset global) {
    for (var i = 0; i < _shown.length; i++) {
      final action = _shown[i];
      final key = _keys[widget.actions.indexOf(action)];
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if ((Offset.zero & box.size).contains(box.globalToLocal(global))) {
        return action.enabled ? action : null;
      }
    }
    return null;
  }

  Offset? _cardLocal(Offset global) {
    final box = _card.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    _press.size = box.size;
    return box.globalToLocal(global);
  }

  void _down(PointerDownEvent event) {
    if (_leaving.value || _pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    final local = _cardLocal(event.position);
    if (local == null) return;
    _pointer = event.pointer;
    _scrolled = false;
    if (_popover == null) {
      _press.reducedMotion = GlassTraits.of(context).reduceMotion;
      _press.pointerDown(MotionClock.instance.stamp(event.timeStamp), local);
    }
    _highlighted.value = _actionAt(event.position);
    MotionClock.instance.wake(this);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _scrolled) return;
    final local = _cardLocal(event.position);
    if (local == null) return;
    if (_popover == null) {
      _press.pointerMove(MotionClock.instance.stamp(event.timeStamp), local);
    }
    final over = _actionAt(event.position);
    if (!identical(over, _highlighted.value)) {
      if (over != null) MotionHaptic.selection.play();
      _highlighted.value = over;
    }
    MotionClock.instance.wake(this);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_scrolled) return;
    final local = _cardLocal(event.position) ?? Offset.zero;
    if (_popover == null) {
      _press.pointerUp(MotionClock.instance.stamp(event.timeStamp), local);
    }
    final chosen = _actionAt(event.position);
    _highlighted.value = null;
    MotionClock.instance.wake(this);
    if (chosen != null) _choose(chosen);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_scrolled) return;
    if (_popover == null) {
      _press.pointerCancel(MotionClock.instance.stamp(event.timeStamp));
    }
    _highlighted.value = null;
    MotionClock.instance.wake(this);
  }

  bool _scrolledContent(ScrollNotification notification) {
    if (_pointer == null ||
        _scrolled ||
        notification.depth != 0 ||
        notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return false;
    }
    _scrolled = true;
    if (_popover == null) _press.pointerCancel(_now);
    _highlighted.value = null;
    MotionClock.instance.wake(this);
    return false;
  }

  bool _fitsInRow(double width, BuildContext context) {
    final each =
        (width - 2 * AlertTuning.buttonInset - AlertTuning.buttonGap) / 2;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    for (final action in widget.actions) {
      final label = action.child;
      if (label is! Text || label.data == null) return false;
      final painter = TextPainter(
        text: TextSpan(text: label.data, style: _labelStyle(action, context)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      );
      painter.layout();
      final fits = painter.width + 2 * AlertTuning.buttonTextInset <= each;
      painter.dispose();
      if (!fits) return false;
    }
    return true;
  }

  TextStyle _labelStyle(GlassAlertAction action, BuildContext context) {
    final label =
        GlassTheme.of(context).colorScheme?.label ?? GlassColors.label;
    final color = !action.enabled
        ? GlassColors.tertiaryLabel
        : action.isDefaultAction
        ? const Color(0xFFFFFFFF)
        : action.isDestructive
        ? GlassColors.systemRed
        : label;
    return resolveGlassText(
      TextStyle(
        fontSize: AlertTuning.textFontSize,
        height: AlertTuning.textHeight,
        fontWeight: action.isDefaultAction
            ? AlertTuning.preferredWeight
            : FontWeight.w500,
        color: GlassDynamicColor.resolve(color, context),
      ),
      context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = GlassTraits.of(context).reduceMotion;
    _alert?.reducedMotion = reduced;
    _popover?.reducedMotion = reduced;
    final popover = widget.anchorRect;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(
      popover == null ? AlertTuning.width : AlertTuning.popoverWidth,
      screen.width - 2 * AlertTuning.screenMargin,
    );
    final row =
        !widget.actionSheet &&
        widget.actions.length == 2 &&
        _fitsInRow(width, context);
    _shown = _ordered(widget.actions, row: row, popover: popover != null);
    final card = NotificationListener<ScrollNotification>(
      onNotification: _scrolledContent,
      child: _buildCard(width, row, context),
    );
    Widget interactive(Widget child) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _return},
      child: FocusScope(
        autofocus: true,
        child: IgnorePointer(
          ignoring: _leaving.value,
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: child,
          ),
        ),
      ),
    );
    if (popover != null) {
      final media = MediaQuery.of(context);
      return PopoverLayout(
        source: popover,
        scale: _scale,
        opacity: _opacity,
        maxWidth: AlertTuning.popoverWidth,
        padding: media.padding.copyWith(
          bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
        ),
        direction: Directionality.of(context),
        card: interactive(card),
      );
    }
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        safe.left,
        safe.top,
        safe.right,
        math.max(safe.bottom, keyboard),
      ),
      child: Center(
        child: interactive(
          MotionTransition(
            scale: _scale,
            child: MotionTransition(
              offset: _lean,
              scaleX: _pressX,
              scaleY: _pressY,
              child: card,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(double width, bool row, BuildContext context) {
    final label =
        GlassTheme.of(context).colorScheme?.label ?? GlassColors.label;
    final title = widget.title;
    final message = widget.message;
    final both = title != null && message != null;
    final header = <Widget>[
      if (title != null)
        DefaultTextStyle(
          style: resolveGlassText(
            TextStyle(
              fontSize: AlertTuning.textFontSize,
              height: AlertTuning.textHeight,
              fontWeight: both
                  ? FontWeight.w600
                  : AlertTuning.singleHeaderWeight,
              color: GlassDynamicColor.resolve(label, context),
            ),
            context,
          ),
          child: title,
        ),
      if (both) const SizedBox(height: AlertTuning.titleGap),
      if (message != null)
        DefaultTextStyle(
          style: resolveGlassText(
            both
                ? TextStyle(
                    fontSize: 15,
                    height: AlertTuning.messageHeight,
                    color: GlassDynamicColor.resolve(_messageColor, context),
                  )
                : TextStyle(
                    fontSize: AlertTuning.textFontSize,
                    height: AlertTuning.textHeight,
                    color: GlassDynamicColor.resolve(label, context),
                  ),
            context,
          ),
          child: message,
        ),
    ];
    final buttons = [
      for (final action in _shown)
        _AlertButton(
          key: _keys[widget.actions.indexOf(action)],
          action: action,
          highlighted: _highlighted,
          label: _labelStyle(action, context),
          onChoose: _choose,
        ),
    ];
    final block = row
        ? Row(
            children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: AlertTuning.buttonGap),
              Expanded(child: buttons[1]),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: AlertTuning.buttonGap),
                buttons[i],
              ],
            ],
          );
    final content = Padding(
      padding: EdgeInsets.only(
        top: header.isNotEmpty ? AlertTuning.headerTop : 0,
        bottom: AlertTuning.buttonInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: AlertTuning.textInset,
                right: AlertTuning.textInset,
                bottom: both
                    ? AlertTuning.headerBottom
                    : AlertTuning.singleHeaderBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: header,
              ),
            ),
          if (buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: AlertTuning.buttonInset,
                left: AlertTuning.buttonInset,
                right: AlertTuning.buttonInset,
              ),
              child: block,
            ),
        ],
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: AlertTuning.maxTextScale,
      child: SizedBox(
        key: _card,
        width: width,
        child: Stack(
          children: [
            if (_popover == null)
              Positioned.fill(
                child: GlassSurface.live(
                  role: GlassRole.menu,
                  frame: _frame,
                  child: const SizedBox.expand(),
                ),
              ),
            MotionTransition(
              opacity: _opacity,
              child: ClipRSuperellipse(
                borderRadius: BorderRadius.circular(
                  _popover == null
                      ? AlertTuning.cornerRadius
                      : PopoverTuning.cornerRadius,
                ),
                child: ListView(
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
}

class _AlertButton extends StatelessWidget {
  const _AlertButton({
    required this.action,
    required this.highlighted,
    required this.label,
    required this.onChoose,
    super.key,
  });

  final GlassAlertAction action;
  final ValueListenable<GlassAlertAction?> highlighted;
  final TextStyle label;
  final ValueChanged<GlassAlertAction> onChoose;

  @override
  Widget build(BuildContext context) {
    final preferred = action.isDefaultAction && action.enabled;
    final fill = GlassDynamicColor.resolve(
      preferred
          ? GlassTheme.of(context).primaryColor ?? GlassColors.systemBlue
          : GlassColors.tertiarySystemFill,
      context,
    );
    return Semantics(
      container: true,
      button: true,
      enabled: action.enabled,
      onTap: action.enabled ? () => onChoose(action) : null,
      child: ValueListenableBuilder<GlassAlertAction?>(
        valueListenable: highlighted,
        builder: (context, over, child) => DecoratedBox(
          decoration: ShapeDecoration(
            color: identical(over, action)
                ? fill.withValues(
                    alpha: fill.a * AlertTuning.pressedFillOpacity,
                  )
                : fill,
            shape: const StadiumBorder(),
          ),
          child: child,
        ),
        child: SizedBox(
          height: AlertTuning.buttonHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlertTuning.buttonTextInset,
            ),
            child: Center(
              child: DefaultTextStyle(
                style: label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                child: action.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
