import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The divider at the trailing edge of a column that a hand resizes: a split
/// view's between its columns, a tab scaffold's at its sidebar's edge.
///
/// UIKit: none; the edge of a column a hand resizes. SwiftUI: none. Flutter:
/// none.
///
/// It is a zone [width] wide, centered on the edge, with the column resize
/// cursor; a mouse over it shows an upright grabber, focus from the keyboard
/// rings it. A drag reports the hand's travel toward the trailing side, the
/// arrow keys and a screen reader's increment and decrement step it as a
/// slider over [range], and a double tap asks to forget the width a hand
/// gave the column.
///
/// The divider moves nothing itself: a shell of its own stands it as tall
/// as the column, centered on the column's edge, and sets the column's
/// width from what it reports, as `GlassSplitView` and the tab scaffold do.
/// A `ColumnFold` turns the travel into widths that stop at a minimum and
/// fold the column past it.
class GlassColumnDivider extends StatefulWidget {
  /// Creates the divider of a column whose width lies in [range].
  const GlassColumnDivider({
    required this.range,
    required this.value,
    required this.increasedValue,
    required this.decreasedValue,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onStep,
    required this.onReset,
    super.key,
  });

  /// The width of the zone a hand grabs: the package's own.
  static const double width = 16;

  /// The width of the grabber a mouse over the divider shows: a sheet's
  /// grabber stood upright, the package's own.
  static const double grabberWidth = 5;

  /// The length of the grabber a mouse over the divider shows.
  static const double grabberLength = 36;

  /// The column's width and its limits, as a screen reader's slider.
  final AdjustRange range;

  /// What a screen reader reads as the slider's value, and what it reads
  /// after a step up and down.
  final String value;

  /// What a screen reader reads after a step up.
  final String increasedValue;

  /// What a screen reader reads after a step down.
  final String decreasedValue;

  /// Called when a hand starts dragging the divider.
  final VoidCallback onDragStart;

  /// Called with the hand's travel since the start, toward the trailing
  /// side.
  final ValueChanged<double> onDragUpdate;

  /// Called when the hand lets go or the drag is cancelled.
  final VoidCallback onDragEnd;

  /// Called with a step of the keyboard or a screen reader.
  final ValueChanged<ValueCommand> onStep;

  /// Called on a double tap: the column returns to its preferred width.
  final VoidCallback onReset;

  @override
  State<GlassColumnDivider> createState() => _GlassColumnDividerState();
}

class _GlassColumnDividerState extends State<GlassColumnDivider> {
  late final _range = ValueNotifier(widget.range);
  final _states = WidgetStatesController();
  late final _drag = DragInteraction(
    axis: Axis.horizontal,
    slop: 1,
    global: true,
    onStart: (details) {
      widget.onDragStart();
      _moved(details);
    },
    onUpdate: _moved,
    onEnd: (details) => widget.onDragEnd(),
    onCancel: (t) => widget.onDragEnd(),
  );
  late final _steps = CommandInteraction(
    onAdjust: (input) => widget.onStep(input.command),
  );
  late final _reset = _PointerTaps(onTap: (t) => widget.onReset());

  void _moved(DragInteractionDetails details) {
    final dx = details.translation.dx;
    widget.onDragUpdate(
      Directionality.of(context) == TextDirection.rtl ? -dx : dx,
    );
  }

  @override
  void didUpdateWidget(GlassColumnDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _range.value = widget.range;
  }

  @override
  void dispose() {
    _range.dispose();
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: [_drag, _steps, _reset],
    mouseCursor: SystemMouseCursors.resizeColumn,
    adjustRange: _range,
    statesController: _states,
    semantics: SemanticsProperties(
      label: GlassLocalizations.of(context).columnDividerLabel,
      slider: true,
      value: widget.value,
      increasedValue: widget.increasedValue,
      decreasedValue: widget.decreasedValue,
    ),
    child: Center(
      child: GlassHighlightPaint.of(
        context,
        states: _states,
        hoverColor: GlassColors.tertiaryLabel,
        child: const SizedBox(
          width: GlassColumnDivider.grabberWidth,
          height: GlassColumnDivider.grabberLength,
        ),
      ),
    ),
  );
}

// A double tap of a pointer alone: a slider takes no Space, Enter or
// screen reader tap.
class _PointerTaps extends TapInteraction {
  _PointerTaps({super.onTap}) : super(count: 2);

  @override
  Set<InputKind> get takes => const {InputKind.pointer};
}
