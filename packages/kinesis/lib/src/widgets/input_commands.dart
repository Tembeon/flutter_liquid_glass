import 'package:flutter/widgets.dart';

/// The commands of a part of the screen while the focus is in it, such as
/// a shell's key to show its sidebar.
///
/// UIKit: the `keyCommands` of a responder, asked from the first responder
/// up. Flutter: `Shortcuts` around `Actions`.
///
/// [shortcuts] map keys to intents and [actions] answer intents for the
/// focus inside [child]. An intent goes to the action closest to the
/// focus, so the innermost part that answers it does, and one that no
/// action here answers goes on to the commands above. An action here that
/// is disabled stops it all the same, as Flutter's do: a part that cannot
/// run a command leaves its action out. A control's own keys go through
/// `InputRegion` and `InputZones`.
class InputCommands extends StatelessWidget {
  /// Creates the commands of [child].
  const InputCommands({
    required this.child,
    this.shortcuts = const {},
    this.actions = const {},
    super.key,
  });

  /// The keys and the intents they ask for.
  final Map<ShortcutActivator, Intent> shortcuts;

  /// What answers each type of intent.
  final Map<Type, Action<Intent>> actions;

  /// The part of the screen.
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: shortcuts,
    child: Actions(actions: actions, child: child),
  );
}
