import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const Set<WidgetState> _inputStates = {
  WidgetState.pressed,
  WidgetState.hovered,
  WidgetState.focused,
  WidgetState.dragged,
};

/// The states a control shows: what it says of itself ([declared]), disabled
/// when it is not [enabled], and the [live] states input keeps while it is.
///
/// A disabled control shows no live state but focus under directional
/// navigation (a TV remote), whose focus can rest on it.
@internal
Set<WidgetState> shownStates({
  required Set<WidgetState> declared,
  required bool enabled,
  required Set<WidgetState> live,
  bool? isFocused,
  NavigationMode? navigation,
}) {
  assert(
    declared.every(
      (s) => s != WidgetState.disabled && !_inputStates.contains(s),
    ),
    'A control declares neither disabled (controlled by enabled) nor an '
    'input-owned state: $declared',
  );
  final focused = isFocused ?? live.contains(WidgetState.focused);
  return {
    ...declared,
    if (!enabled) WidgetState.disabled,
    if (enabled)
      for (final state in live)
        if (state != WidgetState.focused && _inputStates.contains(state)) state,
    if (focused && (enabled || navigation == NavigationMode.directional))
      WidgetState.focused,
  };
}

/// Writes [states] to [controller] when they differ from its value.
@internal
void publishStates(
  WidgetStatesController controller,
  Set<WidgetState> states,
) {
  if (!setEquals(controller.value, states)) controller.value = states;
}

/// Holds a control's [WidgetState] set in one [WidgetStatesController]: the
/// one the control's widget gives ([statesController]) or one of the state's
/// own. A change of the states rebuilds the control.
///
/// The control declares [enabled], [declaredStates], and optionally
/// [isFocused]. It passes [widgetStates] to its `InputRegion`, which
/// publishes live input states (pressed, hovered, focused, dragged) alongside
/// the declared states.
mixin ControlStates<T extends StatefulWidget> on State<T> {
  WidgetStatesController? _own;
  WidgetStatesController? _listened;
  NavigationMode? _navigation;

  /// The controller supplied by the widget, or null to allocate an internal
  /// one.
  WidgetStatesController? get statesController;

  /// Whether the control accepts input now.
  bool get enabled;

  /// Non-input states declared by the control (such as `WidgetState.selected`):
  /// never `disabled` (controlled by [enabled]) nor input-owned states.
  Set<WidgetState> get declaredStates => const {};

  /// Explicit focus override for controls whose focus is not owned by their
  /// `InputRegion`; null defers to the region's live focus state.
  bool? get isFocused => null;

  /// The resolved [WidgetStatesController] for this control.
  WidgetStatesController get widgetStates =>
      statesController ?? (_own ??= WidgetStatesController());

  /// Builds the control's look with its states, as a child of the
  /// `InputRegion` that writes them: its first build and each change show
  /// what the region wrote, and a change rebuilds only the look.
  @protected
  Widget withStates(
    Widget Function(BuildContext context, Set<WidgetState> states) builder,
  ) => ValueListenableBuilder(
    valueListenable: widgetStates,
    builder: (context, states, _) => builder(context, {...states}),
  );

  /// Publishes current states; call when [enabled], [declaredStates], or
  /// [isFocused] change outside a widget update.
  ///
  /// Controls composed of multiple parts may pass gathered [live] input
  /// states; otherwise the currently published live states are preserved.
  @protected
  void updateStates({Set<WidgetState>? live}) =>
      _publish(live ?? widgetStates.value);

  void _publish(Set<WidgetState> live) => publishStates(
    widgetStates,
    shownStates(
      declared: declaredStates,
      enabled: enabled,
      live: live,
      isFocused: isFocused,
      navigation: _navigation,
    ),
  );

  void _listen() {
    final now = widgetStates;
    if (identical(now, _listened)) return;
    _listened?.removeListener(_changed);
    now.addListener(_changed);
    _listened = now;
  }

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _publish(const {});
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = MediaQuery.maybeNavigationModeOf(context);
    if (navigation == _navigation) return;
    _navigation = navigation;
    updateStates();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final live = (_listened ?? widgetStates).value;
    _listen();
    _publish(live);
  }

  @override
  void dispose() {
    _listened?.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }
}
