import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motion/alert_motion.dart';
import 'package:apple_liquid_glass/src/motion/glass_button_motion.dart';
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
import 'package:kinesis/kinesis.dart';

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
  GlassAlertRoute(title: title, message: message, actions: actions),
  level: level,
);

/// Shows an iOS 27 action sheet and completes with the action chosen, or
/// null when it was closed without one.
///
/// UIKit: `UIAlertController` with the action sheet style. SwiftUI:
/// `confirmationDialog`. Flutter: `showCupertinoModalPopup` with a
/// `CupertinoActionSheet`.
///
/// On an iPhone without a source an action sheet is an alert whose actions
/// stand in a column with the cancel action last; a tap outside chooses
/// the cancel action, or closes it without one.
Future<GlassAlertAction?> showGlassActionSheet(
  BuildContext context, {
  Widget? title,
  Widget? message,
  List<GlassAlertAction> actions = const [],
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  GlassAlertRoute.actionSheet(
    title: title,
    message: message,
    actions: actions,
  ),
  level: level,
);

/// The route [showGlassAlert] and [showGlassActionSheet] push.
///
/// Back, Escape and a screen reader's dismiss choose the cancel action;
/// `Navigator.pop` closes it with its result, the cancel action for none.
final class GlassAlertRoute extends PresentationRoute<GlassAlertAction> {
  /// Creates the route of an alert.
  GlassAlertRoute({
    this.title,
    this.message,
    this.actions = const [],
    super.settings,
  }) : actionSheet = false,
       super(semanticsLabel: _text(title) ?? _text(message));

  /// Creates the route of an action sheet.
  GlassAlertRoute.actionSheet({
    this.title,
    this.message,
    this.actions = const [],
    super.settings,
  }) : actionSheet = true,
       super(semanticsLabel: _text(title) ?? _text(message));

  /// The bold line at the top.
  final Widget? title;

  /// The text below the title.
  final Widget? message;

  /// The buttons.
  final List<GlassAlertAction> actions;

  /// Whether this is an action sheet: a tap outside cancels it.
  final bool actionSheet;

  _AlertViewState? _view;
  bool _ran = false;

  static String? _text(Widget? widget) => switch (widget) {
    Text(:final data?) => data,
    _ => null,
  };

  @override
  Widget buildContent(BuildContext context) => _AlertView(route: this);

  @override
  GlassAlertAction? resultFor(GlassAlertAction? result) => result ?? _cancel;

  // An alert waits for an answer: without a cancel action only its buttons
  // close it.
  @override
  bool allows(DismissTrigger trigger) => switch (trigger) {
    DismissTrigger.outsideTap => actionSheet,
    DismissTrigger.escape ||
    DismissTrigger.back ||
    DismissTrigger.accessibility => actionSheet || _cancel != null,
    DismissTrigger.interaction || DismissTrigger.programmatic => true,
  };

  @override
  bool leave(DismissTrigger trigger) {
    final view = _view;
    if (view == null || !view.mounted) return false;
    view._leave();
    return true;
  }

  @override
  void didFinish(GlassAlertAction? result) {
    if (result != null && !_ran) {
      _ran = true;
      result.onPressed?.call();
    }
  }

  // A disabled cancel action answers nothing, as its button does nothing.
  GlassAlertAction? get _cancel {
    for (final action in actions) {
      if (action.isCancel) return action.enabled ? action : null;
    }
    return null;
  }
}

/// The actions in the order they show: the cancel action first in a row,
/// last in a column.
List<GlassAlertAction> _ordered(
  List<GlassAlertAction> actions, {
  required bool row,
}) {
  final cancel = [
    for (final a in actions)
      if (a.isCancel) a,
  ];
  final rest = [
    for (final a in actions)
      if (!a.isCancel) a,
  ];
  return row ? [...cancel, ...rest] : [...rest, ...cancel];
}

/// The colors of an alert, light and dark (UIKit's rendering on an iPhone
/// 16 Pro; the button fill is tertiarySystemFill).
abstract final class _Colors {
  static const message = GlassDynamicColor.withBrightness(
    color: Color(0x993C3C43),
    darkColor: Color(0x99EBEBF5),
  );
  static const button = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x1F767680),
    darkColor: Color(0x3D767680),
    highContrastColor: Color(0x33767680),
    darkHighContrastColor: Color(0x52767680),
  );
  static const destructive = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFFFF383C),
    darkColor: Color(0xFFFF4245),
    highContrastColor: Color(0xFFE9152D),
    darkHighContrastColor: Color(0xFFFF6165),
  );
  static const preferred = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFF0088FF),
    darkColor: Color(0xFF0091FF),
    highContrastColor: Color(0xFF1E6EF4),
    darkHighContrastColor: Color(0xFF5CB8FF),
  );
}

class _AlertView extends StatefulWidget {
  const _AlertView({required this.route});

  final GlassAlertRoute route;

  @override
  State<_AlertView> createState() => _AlertViewState();
}

class _AlertViewState extends State<_AlertView> implements MotionDriver {
  final _motion = AlertMotion();
  final _press = GlassButtonMotion(size: Size.zero);
  final _card = GlobalKey();
  late final List<GlobalKey> _keys = [
    for (final _ in widget.route.actions) GlobalKey(),
  ];
  final _highlighted = ValueNotifier<GlassAlertAction?>(null);
  final _dimming = ValueNotifier<double>(0);
  final _opacity = ValueNotifier<double>(0);
  final _scale = ValueNotifier<double>(AlertTuning.presentScale);
  final _lean = ValueNotifier<Offset>(Offset.zero);
  final _pressX = ValueNotifier<double>(1);
  final _pressY = ValueNotifier<double>(1);
  final _frame = ValueNotifier(const GlassFrame(opacity: 0));
  List<GlassAlertAction> _shown = const [];
  bool _leaving = false;
  int? _pointer;
  // A finger that scrolled the content chooses nothing until it lifts.
  bool _scrolled = false;

  GlassAlertRoute get _route => widget.route;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    _route._view = this;
    _motion.present(_now);
    MotionClock.instance.addDriver(this);
  }

  @override
  void dispose() {
    if (identical(_route._view, this)) _route._view = null;
    MotionClock.instance.removeDriver(this);
    for (final notifier in [
      _dimming,
      _opacity,
      _scale,
      _pressX,
      _pressY,
    ]) {
      notifier.dispose();
    }
    _highlighted.dispose();
    _lean.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  bool get isActive => !_motion.isSettled || !_press.isSettled;

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    _motion.advance(time);
    _press.advance(time);
    if (_motion.isSettled) _motion.settle();
    if (_press.isSettled) _press.settle();
    _publish();
    if (_leaving) {
      if (_motion.isDismissed) _route.didLeave();
    } else if (_motion.isSettled) {
      _route.didOpen();
    }
  }

  void _publish() {
    final opacity = _motion.opacity;
    _dimming.value = _motion.dimming;
    _opacity.value = opacity;
    _scale.value = _motion.scale;
    _lean.value = _press.lean;
    _pressX.value = _press.scaleX;
    _pressY.value = _press.scaleY;
    _frame.value = GlassFrame(opacity: opacity);
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    final t = _now;
    _motion.dismiss(t);
    if (_press.isPressed) _press.pointerCancel(t);
    _pointer = null;
    _highlighted.value = null;
    setState(() {});
    MotionClock.instance.wake(this);
  }

  void _choose(GlassAlertAction action) {
    if (_leaving || !action.enabled) return;
    _route.dismiss(DismissTrigger.programmatic, action);
  }

  void _outside() {
    if (_leaving || !_route.actionSheet) return;
    final cancel = _route._cancel;
    _route.dismiss(DismissTrigger.outsideTap, cancel);
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
      final key = _keys[_route.actions.indexOf(action)];
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
    if (_leaving || _pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    final local = _cardLocal(event.position);
    if (local == null) return;
    _pointer = event.pointer;
    _scrolled = false;
    _press.reducedMotion = GlassTraits.of(context).reduceMotion;
    _press.pointerDown(MotionClock.instance.stamp(event.timeStamp), local);
    _highlighted.value = _actionAt(event.position);
    MotionClock.instance.wake(this);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _scrolled) return;
    final local = _cardLocal(event.position);
    if (local == null) return;
    _press.pointerMove(MotionClock.instance.stamp(event.timeStamp), local);
    final over = _actionAt(event.position);
    if (!identical(over, _highlighted.value)) {
      if (over != null) HapticFeedback.selectionClick();
      _highlighted.value = over;
    }
    MotionClock.instance.wake(this);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_scrolled) return;
    final local = _cardLocal(event.position) ?? Offset.zero;
    _press.pointerUp(MotionClock.instance.stamp(event.timeStamp), local);
    final chosen = _actionAt(event.position);
    _highlighted.value = null;
    MotionClock.instance.wake(this);
    if (chosen != null) _choose(chosen);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_scrolled) return;
    _press.pointerCancel(MotionClock.instance.stamp(event.timeStamp));
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
    _press.pointerCancel(_now);
    _highlighted.value = null;
    MotionClock.instance.wake(this);
    return false;
  }

  bool _fitsInRow(double width, BuildContext context) {
    final each =
        (width - 2 * AlertTuning.buttonInset - AlertTuning.buttonGap) / 2;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    for (final action in _route.actions) {
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
        ? _Colors.destructive
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
    _motion.reducedMotion = GlassTraits.of(context).reduceMotion;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(
      AlertTuning.width,
      screen.width - 2 * AlertTuning.screenMargin,
    );
    final row =
        !_route.actionSheet &&
        _route.actions.length == 2 &&
        _fitsInRow(width, context);
    _shown = _ordered(_route.actions, row: row);
    final card = _buildCard(width, row, context);
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _outside,
            child: MotionTransition(
              opacity: _dimming,
              child: const ColoredBox(
                color: Color.fromRGBO(0, 0, 0, AlertTuning.dimmingOpacity),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              safe.left,
              safe.top,
              safe.right,
              math.max(safe.bottom, keyboard),
            ),
            child: Center(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): _return,
                },
                child: FocusScope(
                  autofocus: true,
                  child: IgnorePointer(
                    ignoring: _leaving,
                    child: Listener(
                      onPointerDown: _down,
                      onPointerMove: _move,
                      onPointerUp: _up,
                      onPointerCancel: _cancel,
                      child: MotionTransition(
                        scale: _scale,
                        child: MotionTransition(
                          offset: _lean,
                          scaleX: _pressX,
                          scaleY: _pressY,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _scrolledContent,
                            child: card,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(double width, bool row, BuildContext context) {
    final label =
        GlassTheme.of(context).colorScheme?.label ?? GlassColors.label;
    final title = _route.title;
    final message = _route.message;
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
                    color: GlassDynamicColor.resolve(_Colors.message, context),
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
          key: _keys[_route.actions.indexOf(action)],
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
            Positioned.fill(
              child: GlassSurface.live(
                role: GlassRole.menu,
                frame: _frame,
                child: const SizedBox.expand(),
              ),
            ),
            MotionTransition(
              opacity: _opacity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AlertTuning.cornerRadius),
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
          ? GlassTheme.of(context).primaryColor ?? _Colors.preferred
          : _Colors.button,
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
