import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const Set<WidgetState> _inputStates = {
  WidgetState.pressed,
  WidgetState.hovered,
  WidgetState.focused,
  WidgetState.dragged,
};

/// The states a control shows: what it says of itself ([declared]), disabled
/// when it is not [enabled], and the [inputStates] input keeps while it is.
///
/// A disabled control shows none of them but focus under directional
/// navigation (a TV remote), whose focus can rest on it.
@internal
Set<WidgetState> shownStates({
  required Set<WidgetState> declared,
  required bool enabled,
  required Set<WidgetState> inputStates,
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
  final focused = isFocused ?? inputStates.contains(WidgetState.focused);
  return {
    ...declared,
    if (!enabled) WidgetState.disabled,
    if (enabled)
      for (final state in inputStates)
        if (state != WidgetState.focused && _inputStates.contains(state)) state,
    if (focused && (enabled || navigation == NavigationMode.directional))
      WidgetState.focused,
  };
}

/// Holds a control's [WidgetState] set in one [WidgetStatesController]: the
/// one the control's widget gives ([statesController]) or one of the state's
/// own.
///
/// The control's `InputRegion` is the controller's one writer: the control
/// says its facts there (`enabled`, `states`, `isFocused`) and builds its
/// look as the region's child through [withStates], which reads them.
mixin ControlStates<T extends StatefulWidget> on State<T> {
  WidgetStatesController? _own;

  /// The controller supplied by the widget, or null to allocate an internal
  /// one.
  WidgetStatesController? get statesController;

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

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }
}
