import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// An input host's place in the gesture arena for one pointer: it waits for
/// the host to resolve it and tells the host when another gesture took the
/// pointer.
@internal
final class InputArenaMember extends GestureArenaMember {
  /// Creates a member that calls [onRejected] when it loses its pointer.
  InputArenaMember(this.onRejected);

  /// Called with the pointer another gesture took.
  final void Function(int pointer) onRejected;

  /// The arena entry, once the member joined.
  GestureArenaEntry? entry;

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) => onRejected(pointer);
}

/// The axes of the scroll views around [context].
@internal
Set<Axis> scrollAxesAround(BuildContext context) {
  final axes = <Axis>{};
  context.visitAncestorElements((element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      axes.add((element.state as ScrollableState).position.axis);
    }
    return true;
  });
  return axes;
}

/// Whether focus shows: as `InkWell` does, only after the keyboard was used
/// last, so a tap that focuses lights no ring; under directional navigation
/// (a TV remote) a disabled host that holds focus shows it too.
@internal
bool focusShows({
  required bool hasFocus,
  required bool enabled,
  required NavigationMode? navigation,
}) =>
    hasFocus &&
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional &&
    (enabled || navigation == NavigationMode.directional);

/// The cursor [given] resolves to in [states]; by default the adaptive
/// click cursor when the host [clickable] (it activates or adjusts), the
/// cursor of what lies below otherwise.
@internal
MouseCursor resolveCursor(
  MouseCursor? given, {
  required bool clickable,
  required Set<WidgetState> states,
}) => WidgetStateProperty.resolveAs<MouseCursor>(
  given ??
      (clickable
          ? WidgetStateMouseCursor.adaptiveClickable
          : MouseCursor.defer),
  states,
);

ActivationSource? _dispatching;

/// Whether no input host is handling a keyboard or accessibility input
/// now: haptics play only outside one.
@internal
bool get gestureInput =>
    _dispatching == null || _dispatching == ActivationSource.pointer;

/// Runs [body], which hands [input] to an input host's interactions, with
/// the input's source known to [gestureInput].
@internal
void dispatchInput(InteractionInput input, VoidCallback body) {
  final source = switch (input) {
    ActivateInput(:final source) || AdjustInput(:final source) => source,
    _ => ActivationSource.pointer,
  };
  final outer = _dispatching;
  _dispatching = source;
  try {
    body();
  } finally {
    _dispatching = outer;
  }
}

/// Tells the frame cadence how fast a followed pointer moves.
@internal
final class PointerSpeed {
  Duration? _movedAt;

  /// A pointer touched at [stamp].
  void touched(Duration stamp) {
    _movedAt = stamp;
    FrameCadence.instance.input(changed: true);
  }

  /// A followed pointer lifted.
  void lifted() => FrameCadence.instance.input(changed: true);

  /// A followed pointer moved; [devicePixelRatio] turns its travel into
  /// device pixels.
  void moved(PointerMoveEvent event, double devicePixelRatio) {
    final last = _movedAt;
    _movedAt = event.timeStamp;
    if (last == null) return;
    final seconds = (event.timeStamp - last).inMicroseconds / 1e6;
    if (seconds <= 0) return;
    FrameCadence.instance.input(
      pixelsPerSecond: event.delta.distance * devicePixelRatio / seconds,
    );
  }
}
