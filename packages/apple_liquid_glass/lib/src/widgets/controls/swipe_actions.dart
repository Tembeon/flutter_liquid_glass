import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// One swipe action of a list row.
///
/// UIKit: `UIContextualAction`. SwiftUI: a `Button` in `swipeActions`.
/// Flutter: `SlidableAction` of flutter_slidable.
@immutable
final class GlassSwipeAction {
  /// Creates an action titled [title].
  const GlassSwipeAction({
    required this.title,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// What the action is called: its label when it has no [icon], and what
  /// accessibility reads.
  final String title;

  /// Shown in place of [title], usually an [Icon]: the button is then a
  /// capsule 60 points wide.
  final Widget? icon;

  /// Called when the action is pressed, or performed by a full swipe.
  final VoidCallback onPressed;

  /// Whether the action destroys, as a delete does (UIKit `.destructive`):
  /// systemRed by default.
  final bool destructive;

  /// The action's fill: systemRed for a destructive action, systemGray3
  /// otherwise, by default.
  final Color? backgroundColor;

  /// The color of the action's label: by default white on the system fills,
  /// as UIKit draws it, and on a [backgroundColor] of the app's white or
  /// black, whichever reads on it (the prominent glass button's rule, not
  /// measured on an action).
  final Color? foregroundColor;
}

/// The color the open strip of a swiped row shows behind its buttons: the
/// page's background, as UIKit cuts the card there. A list section gives it
/// to its rows.
@internal
class SwipeRevealColor extends InheritedWidget {
  /// Gives the rows below [color].
  const SwipeRevealColor({
    required this.color,
    required super.child,
    super.key,
  });

  /// The color behind an open strip.
  final Color color;

  /// The color around [context], or null.
  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SwipeRevealColor>()?.color;

  @override
  bool updateShouldNotify(SwipeRevealColor oldWidget) =>
      color != oldWidget.color;
}

/// A row that a finger swipes sideways to show its actions: [trailing]
/// toward its trailing edge, [leading] toward its leading edge.
///
/// UIKit: `trailingSwipeActionsConfigurationForRowAt` and
/// `leadingSwipeActionsConfigurationForRowAt`. SwiftUI: `swipeActions`.
/// Flutter: `Slidable` of flutter_slidable.
///
/// Its behavior is [RawGlassSwipeActions]'s: the row follows the finger and
/// settles open or closed by the finger's last movement; a full swipe
/// ([fullSwipe], [leadingFullSwipe]) commits only where the row has moved
/// most of its width and performs the side's first action on release, as
/// UIKit's `performsFirstActionWithFullSwipe`; a quick short flick only
/// opens the row. A tap on the open row closes it, and so does a scroll, or
/// a swipe of another row of the same `GlassListSection` or
/// `GlassSliverListSection`.
///
/// It draws UIKit 27.2's look (swipe actions passport): the moved row turns
/// systemGray5 with a round end toward the actions, the strip behind them
/// shows the page's background, and each action is a button 44 points tall
/// in its fill (systemRed for a destructive one, systemGray3 otherwise),
/// a title in 13 point white, which keeps its size at every text size as
/// UIKit's does, with 12 points on each side on a rounded
/// rectangle of radius 16, or an [GlassSwipeAction.icon] on a capsule 60
/// points wide; the buttons of a side share the widest one's width. They
/// grow from nothing as the strip opens, the first stretching past the
/// others in a full swipe, and scale in on release.
///
/// Accessibility offers the actions as custom actions of the row, as UIKit
/// does, which is also how iOS's Full Keyboard Access reaches them (its
/// actions command, Tab-Z). A closed row's actions are no Tab stops; an
/// open row's actions are, before the row, and Space and Enter press the
/// focused one. A focused action draws Flutter's Cupertino focus ring
/// inside its edge and a mouse over it washes it, by the rule of the glass
/// controls (an approximation, not measured).
///
/// Fidelity. The geometry, colors, growth and springs are UIKit 27.2's on
/// the simulator. NEAR: UIKit's strip trails the row by a few points under
/// a finger; the buttons' fade follows their scale; a leading full swipe's
/// row springs home where UIKit's jumps and its strip collapses over 0.8 s;
/// the separator moves with the row, where a table keeps it in place. Not
/// built: an action with both an image and a title (87 wide in UIKit).
class GlassSwipeActions extends StatelessWidget {
  /// Creates a row that shows [trailing] and [leading] when swiped.
  const GlassSwipeActions({
    required this.trailing,
    required this.child,
    this.leading = const [],
    this.fullSwipe = true,
    this.leadingFullSwipe = true,
    @internal this.openOn,
    super.key,
  });

  /// The trailing actions, the first at the trailing edge.
  final List<GlassSwipeAction> trailing;

  /// The leading actions, the first at the leading edge.
  final List<GlassSwipeAction> leading;

  /// Whether a full swipe performs the first trailing action.
  final bool fullSwipe;

  /// Whether a full swipe performs the first leading action.
  final bool leadingFullSwipe;

  /// See [RawGlassSwipeActions.openOn].
  @internal
  final Listenable? openOn;

  /// The row.
  final Widget child;

  /// An action's title (swipe actions passport: 13 regular, white).
  static const TextStyle _titleStyle = TextStyle(fontSize: 13);

  /// The room on each side of a title, and an icon's width inside its
  /// 60 point capsule.
  static const double _titlePadding = 12;
  static const double _iconWidth = 36;

  @override
  Widget build(BuildContext context) => RawGlassSwipeActions(
    actionLabels: [for (final action in trailing) action.title],
    onAction: (i) => trailing[i].onPressed(),
    leadingActionLabels: [for (final action in leading) action.title],
    onLeadingAction: leading.isEmpty ? null : (i) => leading[i].onPressed(),
    fullSwipe: fullSwipe,
    leadingFullSwipe: leadingFullSwipe,
    openOn: openOn,
    swipedColor: GlassDynamicColor.resolve(GlassColors.systemGray5, context),
    revealColor: GlassDynamicColor.resolve(
      SwipeRevealColor.maybeOf(context) ?? GlassColors.systemGroupedBackground,
      context,
    ),
    actionBuilder: (context, details) => _ActionButton(
      action: (details.leading ? leading : trailing)[details.index],
      states: details.states,
    ),
    child: child,
  );
}

Color _fillOf(GlassSwipeAction action, BuildContext context) =>
    GlassDynamicColor.resolve(
      action.backgroundColor ??
          (action.destructive
              ? GlassColors.systemRed
              : GlassColors.systemGray3),
      context,
    );

/// An action's button: its fill on a rounded rectangle (a title) or a
/// capsule (an icon), at the width the row gives it, its label centered and
/// cut by the edge while it grows; the core's zone for it takes its input
/// and speaks for it.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.states});

  final GlassSwipeAction action;
  final ValueListenable<Set<WidgetState>> states;

  @override
  Widget build(BuildContext context) {
    final fill = _fillOf(action, context);
    final foreground = GlassDynamicColor.resolve(
      action.foregroundColor ??
          (action.backgroundColor == null
              ? const Color(0xFFFFFFFF)
              : GlassTheme.contentColorOf(context)(fill)),
      context,
    );
    final icon = action.icon;
    final label = icon != null
        ? SizedBox(
            width: GlassSwipeActions._iconWidth,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(color: foreground, size: 20),
                child: icon,
              ),
            ),
          )
        : Text(
            action.title,
            maxLines: 1,
            softWrap: false,
            style: GlassTextScale.fixed(context).resolve(
              GlassSwipeActions._titleStyle.copyWith(color: foreground),
            ),
          );
    final radius = icon != null
        ? const BorderRadius.all(Radius.circular(22))
        : const BorderRadius.all(Radius.circular(16));
    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: fill,
        child: GlassHighlightPaint.of(
          context,
          states: states,
          shape: LiquidRoundedRectangle(radius: radius.topLeft.x),
          inside: true,
          wash: true,
          child: Center(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassSwipeActions._titlePadding,
                ),
                child: label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
