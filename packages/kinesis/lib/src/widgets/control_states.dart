import 'package:flutter/widgets.dart';

/// Holds a control's [WidgetState] set in one [WidgetStatesController]: the
/// one the control's widget gives ([givenStates]) or one of the state's
/// own, which [writeStates] fills before it is listened to and again on
/// every widget update. A change of the states rebuilds the control.
///
/// The control hands [widgetStates] to its `InputRegion`, which writes
/// pressed, hovered, focused and dragged to it, and disabled too, ending a
/// press or a drag when disabled. [writeStates] writes what the widget says
/// first, so the region's writes are no-ops and it never asks this ancestor
/// to rebuild while it builds.
mixin ControlStates<T extends StatefulWidget> on State<T> {
  WidgetStatesController? _own;
  WidgetStatesController? _listened;

  /// The controller the widget gives, or null for one of the state's own.
  WidgetStatesController? get givenStates;

  /// The control's states.
  WidgetStatesController get widgetStates =>
      givenStates ?? (_own ??= WidgetStatesController());

  /// Writes what the widget says of [widgetStates], such as disabled and
  /// selected.
  void writeStates();

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
    writeStates();
    _listen();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    writeStates();
  }

  @override
  void dispose() {
    _listened?.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }
}
