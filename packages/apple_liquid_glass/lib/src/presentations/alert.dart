import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/motions/alert_motion.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/popover_motion.dart';
import 'package:apple_liquid_glass/src/presentations/popover.dart';
import 'package:apple_liquid_glass/src/surfaces/highlight.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

enum _Role { normal, cancel, destructive }

/// The look of alerts and action sheets; a null field leaves it to the
/// theme's style, then the default (iPhone 16 Pro, iOS 27).
@immutable
class GlassAlertStyle extends GlassStyle<GlassAlertStyle> {
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

  /// The theme's [GlassAlertStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassAlertStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassAlertStyle>(context);

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
  @override
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

  /// The style between this one and [other] at [t].
  @override
  GlassAlertStyle lerp(GlassAlertStyle other, double t) {
    if (identical(this, other)) return this;
    final color = snapNull(GlassDynamicColor.lerp);
    final text = snapNull(TextStyle.lerp);
    return GlassAlertStyle(
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      messageTextStyle: text(messageTextStyle, other.messageTextStyle, t),
      actionTextStyle: text(actionTextStyle, other.actionTextStyle, t),
      actionColor: color(actionColor, other.actionColor, t),
      destructiveActionColor: color(
        destructiveActionColor,
        other.destructiveActionColor,
        t,
      ),
      defaultActionColor: color(
        defaultActionColor,
        other.defaultActionColor,
        t,
      ),
      actionFillColor: color(actionFillColor, other.actionFillColor, t),
      defaultActionFillColor: color(
        defaultActionFillColor,
        other.defaultActionFillColor,
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
  /// accent color, its label semibold, and it takes the focus when the
  /// alert opens, so Return chooses it.
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
/// once the alert has gone. Each button is a focus stop: the default
/// action has the focus when the alert opens, Tab and the arrows move
/// between the buttons, and Return and Space choose the focused one.
/// Escape, Back (Android's predictive back fading the alert with the
/// gesture) and a screen reader's dismiss choose the cancel action;
/// without one they do nothing, and neither does a tap outside. Screen
/// readers hear an alert dialog named by the title, or the message
/// without one, or [GlassLocalizations.alertLabel].
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
      strings: GlassLocalizations.of(context),
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
/// closes it without one, and screen readers find the dimming as
/// [GlassLocalizations.actionSheetDismissLabel]. The keys and screen
/// readers reach its buttons as an alert's.
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
      strings: GlassLocalizations.of(context),
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
  required GlassLocalizations strings,
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
    semanticsLabel: _text(title) ?? _text(message) ?? strings.alertLabel,
    // As Flutter's CupertinoActionSheet: a sheet of choices is a dialog,
    // only an alert interrupts.
    semanticsRole: actionSheet
        ? SemanticsRole.dialog
        : SemanticsRole.alertDialog,
    barrierLabel: actionSheet ? strings.actionSheetDismissLabel : null,
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
  // A scroll of the content takes the touch from the platter and from the
  // actions, which cancels the lift and the press.
  late final List<Interaction> _platter = [
    FollowInteraction(_press, role: InteractionRole.content),
  ];
  final _zones = InputZonesController<int>();
  final _scroll = ScrollController();
  // Bumped when the card's size settles, as the actions' frames read the
  // layout.
  final _layouts = ValueNotifier<int>(0);
  late final _frames = Listenable.merge([_scroll, _layouts]);
  final _card = GlobalKey(debugLabel: 'alert card');
  final _block = GlobalKey(debugLabel: 'alert actions');
  final List<List<Interaction>> _presses = [];
  final List<GlassHighlight> _highlights = [];
  late final MotionSelection<double> _opacity;
  late final MotionSelection<double> _scale;
  late final MotionSelection<bool> _leaving;
  late final MotionSelection<GlassFrame> _frame;
  static const _platterShape = GlassShape.superellipse(
    AlertTuning.cornerRadius,
  );

  List<GlassAlertAction> _shown = const [];
  bool _row = false;
  bool _rtl = false;

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
        (m) => GlassFrame(shape: _platterShape, opacity: m.opacity),
      );
    }
    _leaving.addListener(_left);
  }

  @override
  void dispose() {
    _leaving.removeListener(_left);
    _zones.dispose();
    _scroll.dispose();
    _layouts.dispose();
    super.dispose();
  }

  // The presentation is inert from its leave on; a finger already down
  // stops lifting the platter.
  void _left() {
    if (_leaving.value && _press.isPressed) {
      _press.pointerCancel(widget.motion.clock.now);
    }
  }

  void _choose(GlassAlertAction action) {
    if (_leaving.value || !action.enabled) return;
    PresentationHandle.of(
      context,
    ).dismiss(DismissTrigger.programmatic, action);
  }

  List<Interaction> _pressOf(int index) {
    while (_presses.length <= index) {
      final i = _presses.length;
      _presses.add([
        PressInteraction(
          role: InteractionRole.content,
          onTap: (t) => _choose(_shown[i]),
        ),
      ]);
    }
    return _presses[index];
  }

  GlassHighlight _highlightOf(int index) {
    while (_highlights.length <= index) {
      _highlights.add(
        GlassHighlight(states: _ZoneStates(_zones, _highlights.length)),
      );
    }
    return _highlights[index];
  }

  // Where action [index] lies in the card: its slot in the block of
  // buttons, carried by the layout and the scroll to the card's box, and
  // cut to what the card shows.
  InputZoneFrame? _frameOf(int index) {
    final card = _card.currentContext?.findRenderObject();
    final block = _block.currentContext?.findRenderObject();
    if (card is! RenderBox ||
        block is! RenderBox ||
        !card.hasSize ||
        !block.hasSize ||
        !block.attached ||
        index >= _shown.length) {
      return null;
    }
    final slot = _slot(index, block.size.width);
    final rect = MatrixUtils.transformRect(block.getTransformTo(card), slot);
    return InputZoneFrame(
      rect.intersect(Offset.zero & card.size),
      radius: BorderRadius.circular(AlertTuning.buttonHeight / 2),
    );
  }

  Rect _slot(int index, double width) {
    const height = AlertTuning.buttonHeight;
    if (_row) {
      final each = (width - AlertTuning.buttonGap) / 2;
      final first = (index == 0) != _rtl;
      return Rect.fromLTWH(
        first ? 0 : each + AlertTuning.buttonGap,
        0,
        each,
        height,
      );
    }
    return Rect.fromLTWH(
      0,
      index * (height + AlertTuning.buttonGap),
      width,
      height,
    );
  }

  static MotionHaptic? _feedback(int action, InteractionEvent event) =>
      switch (event) {
        ScrubChangeEvent(atDown: false) => MotionHaptic.selection,
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
    final label = GlassTheme.labelColorOf(context);
    final color = !action.enabled
        ? GlassTheme.tertiaryLabelColorOf(context)
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
                  GlassTheme.primaryColorOf(context) ??
                  GlassColors.systemBlue
            : _look.actionFillColor ?? GlassColors.tertiarySystemFill,
        context,
      );

  @override
  Widget build(BuildContext context) {
    _look = (widget.style ?? const GlassAlertStyle()).merge(
      GlassAlertStyle.maybeOf(context),
    );
    final traits = GlassTraits.of(context);
    _rtl = Directionality.of(context) == TextDirection.rtl;
    final popover = widget.anchorRect;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(
      popover == null ? AlertTuning.width : AlertTuning.popoverWidth,
      screen.width - 2 * AlertTuning.screenMargin,
    );
    _row =
        !widget.actionSheet &&
        widget.actions.length == 2 &&
        _fitsInRow(width, context);
    _shown = _ordered(widget.actions, row: _row, popover: popover != null);
    for (final highlight in _highlights) {
      highlight.reduceMotion = traits.reduceMotion;
    }
    return MotionScope(
      motion: _press,
      child: _place(_buildCard(width, context), context),
    );
  }

  Widget _place(Widget card, BuildContext context) {
    final popover = widget.anchorRect;
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
        card: card,
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
        child: MotionTransition(
          scale: _scale,
          child: MotionTransition(
            offset: _lean,
            scaleX: _pressX,
            scaleY: _pressY,
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(double width, BuildContext context) {
    final label = GlassTheme.labelColorOf(context);
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
      for (final (i, action) in _shown.indexed)
        _AlertButton(
          action: action,
          states: _ZoneStates(_zones, i),
          highlight: _highlightOf(i),
          label: _labelStyle(action, context),
          fill: _fillOf(action, context),
        ),
    ];
    final block = _row
        ? Row(
            key: _block,
            children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: AlertTuning.buttonGap),
              Expanded(child: buttons[1]),
            ],
          )
        : Column(
            key: _block,
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
      child: InputZones<int>(
        zones: [
          for (final (i, action) in _shown.indexed)
            InputZone<int>(
              id: i,
              interactions: _pressOf(i),
              enabled: action.enabled,
              minimumHitSize: const Size.square(44),
              autofocus: action.isDefaultAction && action.enabled,
              semantics: SemanticsProperties(
                label: _text(action.child),
                button: true,
              ),
            ),
        ],
        frameOf: _frameOf,
        frames: _frames,
        controller: _zones,
        axis: _row ? Axis.horizontal : Axis.vertical,
        slides: true,
        feedback: _feedback,
        excludeChildSemantics: false,
        // The platter's lift sits below the zones: a region above them
        // would answer their Space and Enter.
        child: _popover != null
            ? _measured(width, content)
            : InputRegion(
                interactions: _platter,
                child: _measured(width, content),
              ),
      ),
    );
  }

  Widget _measured(double width, Widget content) => MotionMeasure(
    onSize: (t, size) => _layouts.value++,
    child: SizedBox(
      key: _card,
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
                controller: _scroll,
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

/// One action's states, read from the zones of all of them.
final class _ZoneStates implements ValueListenable<Set<WidgetState>> {
  _ZoneStates(this.zones, this.id);

  final InputZonesController<int> zones;
  final int id;

  @override
  Set<WidgetState> get value => zones.statesOf(id);

  @override
  void addListener(VoidCallback listener) => zones.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => zones.removeListener(listener);
}

/// An action's capsule and label. Its zone of the alert's [InputZones]
/// takes its input and speaks for it to assistive technology, so a label
/// that is plain text is not read twice.
class _AlertButton extends StatelessWidget {
  const _AlertButton({
    required this.action,
    required this.states,
    required this.highlight,
    required this.label,
    required this.fill,
  });

  final GlassAlertAction action;
  final ValueListenable<Set<WidgetState>> states;
  final GlassHighlight highlight;
  final TextStyle label;
  final Color fill;

  @override
  Widget build(BuildContext context) => GlassHighlightPaint.of(
    context,
    states: states,
    hoverColor: const Color(0x00000000),
    child: CustomPaint(
      painter: _CapsulePainter(
        states: states,
        highlight: highlight,
        fill: fill,
      ),
      child: SizedBox(
        height: AlertTuning.buttonHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlertTuning.buttonTextInset,
          ),
          child: Center(
            child: ExcludeSemantics(
              excluding: _text(action.child) != null,
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
    ),
  );
}

/// An action's capsule: its fill at [AlertTuning.pressedFillOpacity] of
/// itself while pressed, and at [GlassHighlights.hoverGain] of that change
/// under the pointer. The hover look is an approximation by the rule of
/// [GlassHighlights], not measured on the platform.
class _CapsulePainter extends CustomPainter {
  _CapsulePainter({
    required this.states,
    required this.highlight,
    required this.fill,
  }) : super(repaint: Listenable.merge([states, highlight]));

  final ValueListenable<Set<WidgetState>> states;
  final GlassHighlight highlight;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final press = states.value.contains(WidgetState.pressed)
        ? 1.0
        : GlassHighlights.hoverGain * highlight.hovered;
    final paint = Paint();
    paint.color = fill.withValues(
      alpha: fill.a * (1 + (AlertTuning.pressedFillOpacity - 1) * press),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.shortestSide / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CapsulePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.highlight != highlight ||
      oldDelegate.states.value != states.value;
}
