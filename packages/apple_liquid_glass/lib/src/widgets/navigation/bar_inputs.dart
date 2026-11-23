part of 'bar.dart';

/// One item's input: a press that lifts its capsule under the finger and
/// calls the item, or, for an item with a menu, the lift alone (the menu's
/// source takes the touch) and the keys that open the menu.
final class _ItemInput extends PointerFollower {
  _ItemInput(this.bar, this.id);

  final _Bar bar;
  final Object id;

  /// What a tap, Space or Enter calls; for an item with a menu, null opens
  /// the menu.
  VoidCallback? onPressed;

  /// Opens the item's menu from the keyboard and assistive technology.
  final menu = GlassMenuController();

  late final List<Interaction> press = [
    PressInteraction(onTap: (_) => onPressed?.call()),
    FollowInteraction(this),
  ];

  late final List<Interaction> menuSource = [
    CommandInteraction(onActivate: (_) => (onPressed ?? menu.open)()),
    FollowInteraction(this),
  ];

  @override
  void down(PointerDownInput input) =>
      bar.pressDown(id, input.time, input.position);

  @override
  void move(PointerMoveInput input) =>
      bar.pressMove(input.time, input.position);

  @override
  void up(PointerUpInput input) => bar.pressUp(input.time, input.position);

  @override
  void cancel(PointerCancelInput input) => bar.pressCancel(input.time);
}
