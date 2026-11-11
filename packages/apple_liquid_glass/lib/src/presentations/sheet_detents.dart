part of 'sheet.dart';

class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);

  final _SheetViewState sheet;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    sheet: sheet,
    physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
    context: context,
    oldPosition: oldPosition,
  );
}

/// A scroll position that hands its drags to the sheet: a drag down on
/// content at its top moves the sheet, and a drag up expands it first when
/// it may; the content scrolls once the sheet has nowhere to go.
class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheet,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _SheetViewState sheet;
  bool _owns = false;

  @override
  void applyUserOffset(double delta) {
    if (_owns && delta < 0 && !sheet._canExpand) {
      _owns = false;
      sheet._release(sheet._stamp, 0);
      super.applyUserOffset(delta);
      return;
    }
    final atTop = pixels <= minScrollExtent;
    if (_owns ||
        (delta > 0 && atTop) ||
        (delta < 0 && sheet._spec.scrollingExpandsSheet && sheet._canExpand)) {
      _owns = true;
      sheet._scrollDragBy(delta);
      if (!sheet._scrollDragging) _owns = false;
      return;
    }
    super.applyUserOffset(delta);
  }

  @override
  void goBallistic(double velocity) {
    if (_owns) {
      _owns = false;
      sheet._release(sheet._stamp, -velocity);
      super.goBallistic(0);
      return;
    }
    super.goBallistic(velocity);
  }

  @override
  void dispose() {
    if (_owns) sheet._release(sheet._stamp, 0);
    super.dispose();
  }
}

/// Which ways the detents can step from the one the sheet rests at.
final class _DetentRange implements ValueListenable<AdjustRange> {
  _DetentRange(this.sheet);

  final _SheetViewState sheet;

  @override
  AdjustRange get value {
    final at = sheet._order.indexOf(sheet._detent.value);
    return AdjustRange(
      canIncrease: at >= 0 && at + 1 < sheet._order.length,
      canDecrease: at > 0,
    );
  }

  @override
  void addListener(VoidCallback listener) =>
      sheet._detent.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      sheet._detent.removeListener(listener);
}

/// The value commands of the keyboard and screen readers on the grabber;
/// no finger reaches it: a finger there is the sheet's drag and tap.
final class _DetentStep extends Interaction {
  _DetentStep(this.step);

  final void Function(double t, ValueCommand command) step;

  @override
  bool get adjusts => true;

  @override
  bool get takesPointers => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) step(input.time, input.command);
    return InteractionUpdate.none;
  }
}

// The side of the grabber's target on screen, the smallest UIKit's
// guidelines allow.
const double _target = 44;

/// Tells screen readers the detent the sheet rests at, and the ones a step
/// up and down reach, as the grabber's value; rebuilds when the detent
/// changes.
class _DetentValue extends StatelessWidget {
  const _DetentValue({required this.state, required this.child});

  final _SheetViewState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_DetentScope>();
    final strings = GlassLocalizations.of(context);
    final order = state._order;
    final detent = state._detent.value;
    final at = order.indexOf(detent);
    String? name(int i) => state._detentName(strings, order[i]);
    return Semantics(
      value: at < 0 ? null : state._detentName(strings, detent),
      increasedValue: at >= 0 && at + 1 < order.length ? name(at + 1) : null,
      decreasedValue: at > 0 ? name(at - 1) : null,
      textDirection: Directionality.of(context),
      child: child,
    );
  }
}
