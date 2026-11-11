import 'dart:math' as math;

import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/motions/alert_motion.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/popover_motion.dart';
import 'package:apple_liquid_glass/src/presentations/popover.dart';
import 'package:apple_liquid_glass/src/raw/slot_map.dart';
import 'package:apple_liquid_glass/src/surfaces/glass.dart';
import 'package:apple_liquid_glass/src/surfaces/shape.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

enum _Role { normal, cancel, destructive }

/// The look of alerts and action sheets; a null field leaves it to the
/// theme's style, then the default (iPhone 16 Pro, iOS 27).
@immutable
class GlassAlertStyle {
  /// Creates a style.
  const GlassAlertStyle({
    this.titleTextStyle,
    this.messageTextStyle,
    this.actionTextStyle,
    this.actionColor,
    this.destructiveActionColor,
    this.defaultActionColor,
    this.actionFillColor,
    this.defaultActionFillColor,
  });

  /// The title, over the default 17 points in label, semibold above a
  /// message.
  final TextStyle? titleTextStyle;

  /// The message, over the default 15 points in secondaryLabel under a
  /// title, or the title's default (17 points in label) without one.
  final TextStyle? messageTextStyle;

  /// The action labels, over the default 17 points, medium; an alert
  /// measures [Text] labels in it to choose a row of two buttons over a
  /// column.
  final TextStyle? actionTextStyle;

  /// The label of an action; label by default.
  final Color? actionColor;

  /// The label of a destructive action; systemRed by default.
  final Color? destructiveActionColor;

  /// The label of the default action; white by default.
  final Color? defaultActionColor;

  /// The capsule behind an action; tertiarySystemFill by default.
  final Color? actionFillColor;

  /// The capsule behind the default action; the theme's primary color,
  /// then systemBlue, by default.
  final Color? defaultActionFillColor;

  /// This style over [other].
  GlassAlertStyle merge(GlassAlertStyle? other) {
    if (other == null) return this;
    return GlassAlertStyle(
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      messageTextStyle:
          other.messageTextStyle?.merge(messageTextStyle) ?? messageTextStyle,
      actionTextStyle:
          other.actionTextStyle?.merge(actionTextStyle) ?? actionTextStyle,
      actionColor: actionColor ?? other.actionColor,
      destructiveActionColor:
          destructiveActionColor ?? other.destructiveActionColor,
      defaultActionColor: defaultActionColor ?? other.defaultActionColor,
      actionFillColor: actionFillColor ?? other.actionFillColor,
      defaultActionFillColor:
          defaultActionFillColor ?? other.defaultActionFillColor,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassAlertStyle? lerp(
    GlassAlertStyle? a,
    GlassAlertStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    final color = snapNull(GlassDynamicColor.lerp);
    final text = snapNull(TextStyle.lerp);
    return GlassAlertStyle(
      titleTextStyle: text(a.titleTextStyle, b.titleTextStyle, t),
      messageTextStyle: text(a.messageTextStyle, b.messageTextStyle, t),
      actionTextStyle: text(a.actionTextStyle, b.actionTextStyle, t),
      actionColor: color(a.actionColor, b.actionColor, t),
      destructiveActionColor: color(
        a.destructiveActionColor,
        b.destructiveActionColor,
        t,
      ),
      defaultActionColor: color(a.defaultActionColor, b.defaultActionColor, t),
      actionFillColor: color(a.actionFillColor, b.actionFillColor, t),
      defaultActionFillColor: color(
        a.defaultActionFillColor,
        b.defaultActionFillColor,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassAlertStyle &&
      other.titleTextStyle == titleTextStyle &&
      other.messageTextStyle == messageTextStyle &&
      other.actionTextStyle == actionTextStyle &&
      other.actionColor == actionColor &&
      other.destructiveActionColor == destructiveActionColor &&
      other.defaultActionColor == defaultActionColor &&
      other.actionFillColor == actionFillColor &&
      other.defaultActionFillColor == defaultActionFillColor;

  @override
  int get hashCode => Object.hash(
    titleTextStyle,
    messageTextStyle,
    actionTextStyle,
    actionColor,
    destructiveActionColor,
    defaultActionColor,
    actionFillColor,
    defaultActionFillColor,
  );
}

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
  GlassAlertStyle? style,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  PresentationRoute(
    presentation: _alert(
      title: title,
      message: message,
      actions: actions,
      style: style,
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
  GlassAlertStyle? style,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  PresentationRoute(
    presentation: _alert(
      title: title,
      message: message,
      actions: actions,
      style: style,
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

Presentation<GlassAlertAction, Presented> _alert({
  required Widget? title,
  required Widget? message,
  required List<GlassAlertAction> actions,
  required GlassAlertStyle? style,
  required bool actionSheet,
  Rect? anchorRect,
}) {
  final cancel = _cancelOf(actions);
  // An alert without an enabled cancel action waits for one of its
  // buttons; an action sheet always closes on Escape, Back and a screen
  // reader's dismiss, with its cancel action or none.
  final closable = actionSheet || cancel != null;
  return Presentation(
    motion: (_) => anchorRect == null ? AlertMotion() : PopoverMotion(),
    builder: (context, motion) => _AlertView(
      motion: motion,
      title: title,
      message: message,
      actions: actions,
      style: style,
      actionSheet: actionSheet,
      anchorRect: anchorRect,
    ),
    dismiss: DismissPolicy({
      if (actionSheet) DismissTrigger.outsideTap,
      if (closable) ...{
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

extension on TextStyle {
  TextStyle resolvedColor(BuildContext context) => switch (color) {
    final color? => copyWith(color: GlassDynamicColor.resolve(color, context)),
    null => this,
  };
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
    required this.style,
    required this.actionSheet,
    required this.anchorRect,
  });

  // An AlertMotion, or a PopoverMotion for an action sheet with a source.
  final Presented motion;
  final Widget? title;
  final Widget? message;
  final List<GlassAlertAction> actions;
  final GlassAlertStyle? style;
  final bool actionSheet;
  final Rect? anchorRect;

  @override
  State<_AlertView> createState() => _AlertViewState();
}

class _AlertViewState extends State<_AlertView> {
  late final AlertMotion? _alert = switch (widget.motion) {
    final AlertMotion alert => alert,
    _ => null,
  };
  late final PopoverMotion? _popover = switch (widget.motion) {
    final PopoverMotion popover => popover,
    _ => null,
  };
  final _press = GlassPress();
  late final _lean = _press.select((p) => p.lean);
  late final _pressX = _press.select((p) => p.scaleX);
  late final _pressY = _press.select((p) => p.scaleY);
  final _slots = SlotMap<GlassAlertAction>();
  final _focus = FocusNode(skipTraversal: true);
  late final List<Interaction> _interactions = [
    if (_popover == null)
      _scrub.simultaneously(
        FollowInteraction(_press, role: InteractionRole.content),
      )
    else
      _scrub,
  ];
  // A scroll of the content takes the touch from the region, which cancels
  // the scrub and the press.
  late final _scrub = ScrubInteraction(
    hit: _actionAt,
    role: InteractionRole.content,
    onChanged: (action, t) {
      if (!_leaving.value) _highlighted.value = action as GlassAlertAction?;
    },
    onCommit: (action, t) {
      _highlighted.value = null;
      _choose(action as GlassAlertAction);
    },
  );
  final _highlighted = ValueNotifier<GlassAlertAction?>(null);
  late final MotionSelection<double> _opacity;
  late final MotionSelection<double> _scale;
  late final MotionSelection<bool> _leaving;
  late final MotionSelection<GlassFrame> _frame;
  static const _platter = GlassShape.superellipse(AlertTuning.cornerRadius);

  List<GlassAlertAction> _shown = const [];

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    if (_popover case final popover?) {
      _opacity = popover.select((m) => m.opacity);
      _scale = popover.select((m) => m.scale);
      _leaving = popover.select((m) => m.isLeaving);
    } else {
      final alert = _alert!;
      _opacity = alert.select((m) => m.opacity);
      _scale = alert.select((m) => m.scale);
      _leaving = alert.select((m) => m.isLeaving);
      _frame = alert.select(
        (m) => GlassFrame(shape: _platter, opacity: m.opacity),
      );
    }
    _leaving.addListener(_left);
  }

  @override
  void dispose() {
    _leaving.removeListener(_left);
    _highlighted.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _left() {
    if (!_leaving.value) return;
    if (_press.isPressed) _press.pointerCancel(_now);
    _highlighted.value = null;
    setState(() {});
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

  GlassAlertAction? _actionAt(Offset position) {
    final action = _slots.at(position);
    return action != null && action.enabled ? action : null;
  }

  static MotionHaptic? _feedback(InteractionEvent event) => switch (event) {
    ScrubChangeEvent(atDown: false, selected: _?) => MotionHaptic.selection,
    _ => null,
  };

  GlassAlertStyle _look = const GlassAlertStyle();

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
    final look = _look;
    final theme = GlassTheme.of(context);
    final label = theme.labelColor;
    final color = !action.enabled
        ? theme.tertiaryLabelColor
        : action.isDefaultAction
        ? look.defaultActionColor ?? const Color(0xFFFFFFFF)
        : action.isDestructive
        ? look.destructiveActionColor ?? GlassColors.systemRed
        : look.actionColor ?? label;
    return resolveGlassText(
      TextStyle(
            fontSize: AlertTuning.textFontSize,
            height: AlertTuning.textHeight,
            fontWeight: action.isDefaultAction
                ? AlertTuning.preferredWeight
                : FontWeight.w500,
          )
          .merge(look.actionTextStyle)
          .copyWith(
            color: GlassDynamicColor.resolve(color, context),
          ),
      context,
    );
  }

  Color _fillOf(GlassAlertAction action, BuildContext context) =>
      GlassDynamicColor.resolve(
        action.isDefaultAction && action.enabled
            ? _look.defaultActionFillColor ??
                  GlassTheme.of(context).primaryColor ??
                  GlassColors.systemBlue
            : _look.actionFillColor ?? GlassColors.tertiarySystemFill,
        context,
      );

  @override
  Widget build(BuildContext context) {
    _look = (widget.style ?? const GlassAlertStyle()).merge(
      GlassTheme.of(context).alertStyle,
    );
    final reduced = GlassTraits.of(context).reduceMotion;
    _alert?.reducedMotion = reduced;
    _popover?.reducedMotion = reduced;
    _press.reducedMotion = reduced;
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
    final card = _buildCard(width, row, context);
    Widget interactive(Widget child) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _return},
      child: FocusScope(
        autofocus: true,
        child: IgnorePointer(ignoring: _leaving.value, child: child),
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
    final label = GlassTheme.of(context).labelColor;
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
              color: label,
            ).merge(_look.titleTextStyle).resolvedColor(context),
            context,
          ),
          child: title,
        ),
      if (both) const SizedBox(height: AlertTuning.titleGap),
      if (message != null)
        DefaultTextStyle(
          style: resolveGlassText(
            (both
                    ? const TextStyle(
                        fontSize: 15,
                        height: AlertTuning.messageHeight,
                        color: _messageColor,
                      )
                    : TextStyle(
                        fontSize: AlertTuning.textFontSize,
                        height: AlertTuning.textHeight,
                        color: label,
                      ))
                .merge(_look.messageTextStyle)
                .resolvedColor(context),
            context,
          ),
          child: message,
        ),
    ];
    final buttons = [
      for (final action in _shown)
        SlotMapEntry(
          map: _slots,
          id: action,
          child: _AlertButton(
            action: action,
            highlighted: _highlighted,
            label: _labelStyle(action, context),
            fill: _fillOf(action, context),
            onChoose: _choose,
          ),
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
      child: InputRegion(
        interactions: _interactions,
        feedback: _feedback,
        focusNode: _focus,
        child: SlotMapOrigin(
          map: _slots,
          child: SizedBox(
            width: width,
            child: Stack(
              children: [
                if (_popover == null)
                  Positioned.fill(
                    child: GlassSurface.live(
                      role: GlassRole.panel,
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
    required this.fill,
    required this.onChoose,
  });

  final GlassAlertAction action;
  final ValueListenable<GlassAlertAction?> highlighted;
  final TextStyle label;
  final Color fill;
  final ValueChanged<GlassAlertAction> onChoose;

  @override
  Widget build(BuildContext context) {
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
