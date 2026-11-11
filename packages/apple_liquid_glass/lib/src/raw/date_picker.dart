import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// What a [GlassDatePickerDayBuilder] builds one day of the month from.
@immutable
final class GlassDatePickerDay {
  /// Describes a day.
  const GlassDatePickerDay({
    required this.date,
    required this.size,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.states,
  });

  /// The day, at midnight.
  final DateTime date;

  /// The day's cell: as wide as a seventh of the grid, as tall as its
  /// week's row.
  final Size size;

  /// Whether the day is the picked one.
  final bool selected;

  /// Whether the day is today.
  final bool today;

  /// Whether the day lies between the picker's first and last dates and
  /// the picker is enabled.
  final bool enabled;

  /// The day's states as they change: pressed, hovered and focused (only
  /// while focus should show), selected and disabled.
  final ValueListenable<Set<WidgetState>> states;
}

/// Builds one day of a [RawGlassDatePicker]; it runs when the picker builds
/// a month, never on a frame of its motion.
typedef GlassDatePickerDayBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerDay day,
);

/// What a [GlassDatePickerTitleBuilder] builds the month title from.
@immutable
final class GlassDatePickerTitle {
  /// Describes the title.
  const GlassDatePickerTitle({
    required this.text,
    required this.showsYearPicker,
    required this.chevronAngle,
    required this.states,
  });

  /// The shown month and its year, such as "October 2026".
  final String text;

  /// Whether the picker shows, or turns to, its month and year wheels.
  final bool showsYearPicker;

  /// The angle in radians the title's chevron turns by from pointing
  /// toward the trailing side: a quarter turn, toward pointing down, as
  /// the wheels show, mirrored in right-to-left.
  final MotionSelection<double> chevronAngle;

  /// The title's states as they change: pressed, hovered, focused and
  /// disabled.
  final ValueListenable<Set<WidgetState>> states;
}

/// Builds the month title of a [RawGlassDatePicker], a button that shows
/// and hides the month and year wheels.
typedef GlassDatePickerTitleBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerTitle title,
);

/// What a [GlassDatePickerArrowBuilder] builds a month arrow from.
@immutable
final class GlassDatePickerArrow {
  /// Describes an arrow.
  const GlassDatePickerArrow({
    required this.next,
    required this.pointsRight,
    required this.enabled,
    required this.states,
  });

  /// Whether the arrow turns to the next month, or else the previous one.
  final bool next;

  /// Whether the arrow points to the right: the next month's arrow in a
  /// left-to-right context, the previous month's in a right-to-left one.
  final bool pointsRight;

  /// Whether the month it turns to may be shown.
  final bool enabled;

  /// The arrow's states as they change: pressed, hovered, focused and
  /// disabled.
  final ValueListenable<Set<WidgetState>> states;
}

/// Builds a month arrow of a [RawGlassDatePicker].
typedef GlassDatePickerArrowBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerArrow arrow,
);

/// What a [GlassDatePickerMonthYearBuilder] builds the month and year
/// wheels from.
@immutable
final class GlassDatePickerMonthYear {
  /// Describes the wheels.
  const GlassDatePickerMonthYear({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
  });

  /// The shown month, its first day at midnight.
  final DateTime month;

  /// The earliest day that may be picked, or null for no limit.
  final DateTime? firstDate;

  /// The latest day that may be picked, or null for no limit.
  final DateTime? lastDate;

  /// Called with the month and year a wheel comes to rest on: the picker
  /// shows that month and moves the picked day there.
  final void Function(int year, int month) onChanged;
}

/// Builds the month and year wheels a [RawGlassDatePicker] shows in place
/// of its day grid while its title is turned.
typedef GlassDatePickerMonthYearBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerMonthYear details,
);

/// A month calendar with the measured motion and layout of iOS 27's
/// inline `UIDatePicker` and no look of its own: its builders decide how
/// each part looks.
///
/// UIKit: `UIDatePicker` with `.inline` (its calendar). SwiftUI:
/// `DatePicker` with `.graphical`. Flutter: `CalendarDatePicker`.
///
/// It lays out UIKit's calendar, 320 by 332 points: the month title with
/// its chevron, the two month arrows, the weekday initials and the days of
/// the shown month in weeks starting at [firstDayOfWeek]; a month of six
/// weeks packs its rows into the five rows' height. An arrow turns the
/// month with a slide (0.3 s on a sine ease); a tap on the
/// title fades the grid out and [monthYearBuilder]'s wheels in, and a
/// wheel at rest moves the picked day to its month and year, keeping its
/// day of the month where the month has it (the 31st turned to November is
/// the 30th). A tap on a day picks it; the time of [value] is kept.
///
/// Keys and accessibility follow Flutter's `CalendarDatePicker`. The title
/// and each arrow are buttons and Tab stops of their own, with targets of
/// 44 points; Space and Enter press them. The days are one Tab stop,
/// entered at the picked day ([focusNode] stands for them): an arrow key
/// moves the focus a day back or forward, or a week up or down, mirrored
/// in a right-to-left context, and turns the month when it leaves it;
/// Space and Enter pick the focused day. Screen readers read each day as
/// its number and its full date, "Today" after today's, as a button, with
/// the picked day selected and the days outside [minimumDate] and
/// [maximumDate] disabled. A frame of motion rebuilds no builder.
class RawGlassDatePicker extends StatefulWidget {
  /// Creates a calendar showing [value]'s month with [value] picked.
  const RawGlassDatePicker({
    required this.value,
    required this.onChanged,
    required this.dayBuilder,
    required this.titleBuilder,
    required this.arrowBuilder,
    required this.weekdayBuilder,
    required this.monthYearBuilder,
    this.minimumDate,
    this.maximumDate,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.focusNode,
    this.autofocus = false,
    @internal this.defersDays = false,
    super.key,
  });

  /// The picked day; its time of day is kept when another day is picked.
  final DateTime value;

  /// Called with the day the user picks, at [value]'s time of day; null
  /// disables the picker.
  final ValueChanged<DateTime>? onChanged;

  /// Builds each day.
  final GlassDatePickerDayBuilder dayBuilder;

  /// Builds the month title.
  final GlassDatePickerTitleBuilder titleBuilder;

  /// Builds each month arrow.
  final GlassDatePickerArrowBuilder arrowBuilder;

  /// Builds the initial of a weekday, given its text.
  final Widget Function(BuildContext context, String label) weekdayBuilder;

  /// Builds the month and year wheels.
  final GlassDatePickerMonthYearBuilder monthYearBuilder;

  /// The earliest moment that can be picked; null for no limit. Later
  /// than [maximumDate], both are ignored, as UIKit ignores them.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit.
  final DateTime? maximumDate;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to show as today; null for the current day.
  final DateTime? today;

  /// The focus node of the days, or null for the picker's own: focusing
  /// it focuses the picked day.
  final FocusNode? focusNode;

  /// Whether the days take focus when they first appear.
  final bool autofocus;

  /// Whether the days mount a frame after the rest, as an overlay that
  /// opens with them spreads its layout over two frames.
  @internal
  final bool defersDays;

  /// The size of UIKit's calendar.
  static const Size size = DatePickerCalendarMotion.calendarSize;

  @override
  State<RawGlassDatePicker> createState() => _RawGlassDatePickerState();
}

extension on RawGlassDatePicker {
  bool get _boundsHold {
    final first = minimumDate;
    final last = maximumDate;
    return first == null || last == null || !last.isBefore(first);
  }

  DateTime? get _minimum => _boundsHold ? minimumDate : null;

  DateTime? get _maximum => _boundsHold ? maximumDate : null;
}

int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether the calendar may turn from [month] by [direction] months: the
/// next month must not start before [first]'s month or after [last]'s.
bool _canTurnMonth(
  DateTime month,
  int direction,
  DateTime? first,
  DateTime? last,
) {
  final next = DateTime(month.year, month.month + direction);
  return !(first != null && next.isBefore(DateTime(first.year, first.month))) &&
      !(last != null && next.isAfter(DateTime(last.year, last.month)));
}

/// The layout of the calendar, read from UIKit's views at 320 points wide.
abstract final class _Metrics {
  static const double top = 16;
  static const double headerHeight = 37.67;
  static const double titleInset = 20.33;
  static const double titleButtonStart = 16;
  static const double titleButtonEnd = 4;
  static const double weekdayTop = 16;
  static const double weekdayHeight = 15.67;
  static const double gridInset = 10.33;
  static const double cell = 42.67;
  static const double row = 45.67;
  static const double gridTop = 1;
  static const double chevronButton = 43.33;
  static const double chevronEnd = 2;
  static const double grid = 7 * cell;

  /// How far a day's 44-point target reaches past its cell on each side.
  static const double reach = (44 - cell) / 2;

  /// Where the month and year wheels sit in the calendar
  /// (`_UICalendarMonthYearSelector`, iPhone 16 Pro, fixture
  /// ios27-device/date_picker/month-year.json): 288 x 216 at 16 x 76.84.
  static const double wheelsStart = 16;
  static const double wheelsTop = 76.84;
  static const double wheelsWidth = 288;
  static const double wheelsHeight = 216;
}

/// The smallest target of a part, the size Apple's guidelines ask for.
const Size _target = Size(44, 44);

/// A [Listenable] that never notifies: the days' frames, which move only
/// with the grid around them.
final class _Still implements Listenable {
  const _Still();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _RawGlassDatePickerState extends State<RawGlassDatePicker> {
  final DatePickerCalendarMotion _motion = DatePickerCalendarMotion();
  final InputZonesController<DateTime> _zones =
      InputZonesController<DateTime>();
  final WidgetStatesController _title = WidgetStatesController();
  final WidgetStatesController _previous = WidgetStatesController();
  final WidgetStatesController _next = WidgetStatesController();
  final Map<DateTime, _DayStates> _dayStates = {};
  final Map<DateTime, List<Interaction>> _presses = {};
  late final List<Interaction> _titlePress = [
    PressInteraction(role: InteractionRole.content, onTap: _toggleYearPicker),
  ];
  late final List<Interaction> _previousPress = [
    PressInteraction(role: InteractionRole.content, onTap: (t) => _turn(t, -1)),
  ];
  late final List<Interaction> _nextPress = [
    PressInteraction(role: InteractionRole.content, onTap: (t) => _turn(t, 1)),
  ];
  late final MotionSelection<bool> _pageTurning = _motion.select(
    (m) => m.page < 1,
  );
  late final MotionSelection<bool> _yearsVisible = _motion.select(
    (m) => m.yearPicker.clamp(0.0, 1.0) > 0,
  );
  late final MotionSelection<double> _gridOpacity = _motion.select(
    (m) => 1 - m.yearPicker.clamp(0.0, 1.0),
  );
  late final MotionSelection<double> _wheelsOpacity = _motion.select(
    (m) => m.yearPicker.clamp(0.0, 1.0),
  );
  late MotionSelection<double> _chevronAngle = _angle(rtl: false);
  bool _rtl = false;
  late DateTime _month = DateTime(_shown.year, _shown.month);
  DateTime? _previousMonth;
  DateTime? _focusAfterTurn;
  late bool _daysReady = !widget.defersDays;
  VoidCallback? _cancelDays;
  VoidCallback? _cancelFocus;

  DateTime get _shown => _bounded(widget.value);

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _motion.onTurn = _turned;
    if (!_daysReady) {
      _cancelDays = _motion.clock.schedulePublish(() {
        _cancelDays = null;
        if (mounted) setState(() => _daysReady = true);
      });
    }
  }

  @override
  void didUpdateWidget(RawGlassDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _shown;
    if (!_sameDay(_bounded(oldWidget.value), value) &&
        !(value.year == _month.year && value.month == _month.month)) {
      _month = DateTime(value.year, value.month);
      _previousMonth = null;
    }
  }

  @override
  void dispose() {
    _cancelDays?.call();
    _cancelFocus?.call();
    _motion.onTurn = null;
    for (final states in _dayStates.values) {
      states.dispose();
    }
    _zones.dispose();
    _title.dispose();
    _previous.dispose();
    _next.dispose();
    super.dispose();
  }

  MotionSelection<double> _angle({required bool rtl}) => _motion.select(
    (m) => (rtl ? -1 : 1) * m.yearPickerTurn * math.pi / 2,
  );

  DateTime _bounded(DateTime value) {
    final first = widget._minimum;
    final last = widget._maximum;
    if (first != null && value.isBefore(first)) return first;
    if (last != null && value.isAfter(last)) return last;
    return value;
  }

  bool _inRange(DateTime day) {
    final first = widget._minimum;
    final last = widget._maximum;
    return !(first != null && day.isBefore(_dateOnly(first))) &&
        !(last != null && day.isAfter(_dateOnly(last)));
  }

  bool _canTurn(int direction) =>
      _canTurnMonth(_month, direction, widget._minimum, widget._maximum);

  void _turn(double t, int direction) => _motion.turnPage(t, direction);

  bool _turned(int direction) {
    if (!mounted || !_canTurn(direction)) return false;
    setState(() {
      _previousMonth = _month;
      _month = DateTime(_month.year, _month.month + direction);
    });
    return true;
  }

  void _toggleYearPicker(double t) {
    setState(() {});
    _motion.showYearPicker(t, show: !_motion.showsYearPicker);
  }

  void _pick(DateTime day) {
    final onChanged = widget.onChanged;
    if (onChanged == null || !_inRange(day)) return;
    final v = widget.value;
    onChanged(DateTime(day.year, day.month, day.day, v.hour, v.minute));
  }

  void _pickMonth(int year, int month) {
    final v = _shown;
    var next = DateTime(
      year,
      month,
      math.min(v.day, _daysIn(DateTime(year, month))),
      v.hour,
      v.minute,
    );
    final first = widget._minimum;
    final last = widget._maximum;
    if (first != null && next.isBefore(_dateOnly(first))) {
      next = DateTime(first.year, first.month, first.day, v.hour, v.minute);
    }
    if (last != null && _dateOnly(next).isAfter(_dateOnly(last))) {
      next = DateTime(last.year, last.month, last.day, v.hour, v.minute);
    }
    setState(() {
      _previousMonth = null;
      _month = DateTime(next.year, next.month);
    });
    if (next != v) widget.onChanged?.call(next);
  }

  // An arrow key that finds no day in its direction on screen moves a day
  // or a week from the focused one, as Flutter's CalendarDatePicker does,
  // and turns the month when that day lies in another.
  bool _edge(DateTime from, TraversalDirection direction) {
    final step = switch (direction) {
      TraversalDirection.up => -DateTime.daysPerWeek,
      TraversalDirection.down => DateTime.daysPerWeek,
      TraversalDirection.left => _rtl ? 1 : -1,
      TraversalDirection.right => _rtl ? -1 : 1,
    };
    final next = DateTime(from.year, from.month, from.day + step);
    if (!_inRange(next)) return true;
    if (next.year == _month.year && next.month == _month.month) {
      _zones.requestFocus(next);
      return true;
    }
    final turn = next.isBefore(_month) ? -1 : 1;
    if (!_canTurn(turn)) return true;
    _focusAfterTurn = next;
    _motion.turnPage(_motion.clock.now, turn);
    return true;
  }

  void _focusPicked(bool focused) {
    if (!focused || !(widget.focusNode?.hasPrimaryFocus ?? false)) return;
    _zones.requestFocus(_entry());
  }

  // The day Tab enters the grid at: the picked day when it is shown, else
  // today, else the first day of the month.
  DateTime _entry() {
    final value = _dateOnly(_shown);
    if (value.year == _month.year && value.month == _month.month) {
      return value;
    }
    final today = _today;
    if (today.year == _month.year && today.month == _month.month) {
      return today;
    }
    return _month;
  }

  DateTime get _today => _dateOnly(widget.today ?? DateTime.now());

  List<Interaction> _pressOf(DateTime day) => _presses.putIfAbsent(
    day,
    () => [
      PressInteraction(
        role: InteractionRole.content,
        onTap: (_) => _pick(day),
      ),
    ],
  );

  _DayStates _statesOf(DateTime day) =>
      _dayStates.putIfAbsent(day, () => _DayStates(_zones, day));

  // Only the shown month keeps its days' interactions and states.
  void _forgetOtherMonths() {
    bool other(DateTime day) =>
        day.year != _month.year || day.month != _month.month;
    _presses.removeWhere((day, _) => other(day));
    _dayStates.removeWhere((day, states) {
      if (!other(day)) return false;
      states.dispose();
      return true;
    });
  }

  int _weeksOf(DateTime month) {
    final lead =
        (DateTime(month.year, month.month).weekday - widget.firstDayOfWeek) % 7;
    return ((lead + _daysIn(month)) / 7).ceil();
  }

  double _rowOf(DateTime month) => _weeksOf(month) > 5
      ? DatePickerCalendarMotion.sixWeekRowHeight
      : _Metrics.row;

  InputZoneFrame? _dayFrame(DateTime day) {
    if (day.year != _month.year || day.month != _month.month) return null;
    final lead =
        (DateTime(day.year, day.month).weekday - widget.firstDayOfWeek) % 7;
    final index = lead + day.day - 1;
    final column = index % 7;
    final row = _rowOf(day);
    final left = _rtl
        ? _Metrics.grid - (column + 1) * _Metrics.cell
        : column * _Metrics.cell;
    return InputZoneFrame(
      Rect.fromLTWH(left, (index ~/ 7) * row, _Metrics.cell, row),
    );
  }

  Widget _monthGrid(
    BuildContext context,
    DateTime month, {
    required bool live,
  }) {
    final first = DateTime(month.year, month.month);
    final lead = (first.weekday - widget.firstDayOfWeek) % 7;
    final days = _daysIn(month);
    final weeks = _weeksOf(month);
    final row = _rowOf(month);
    final value = _shown;
    final today = _today;
    // Its own layer: a page turn moves the recorded grid instead of
    // painting every day again on each frame.
    return RepaintBoundary(
      child: Column(
        children: [
          for (var w = 0; w < weeks; w++)
            SizedBox(
              height: row,
              child: Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    if (w * 7 + d - lead + 1 case final day
                        when day >= 1 && day <= days)
                      widget.dayBuilder(
                        context,
                        GlassDatePickerDay(
                          date: DateTime(month.year, month.month, day),
                          size: Size(_Metrics.cell, row),
                          selected: _sameDay(
                            DateTime(month.year, month.month, day),
                            value,
                          ),
                          today: _sameDay(
                            DateTime(month.year, month.month, day),
                            today,
                          ),
                          enabled:
                              _enabled &&
                              _inRange(DateTime(month.year, month.month, day)),
                          states: live
                              ? _statesOf(
                                  DateTime(month.year, month.month, day),
                                )
                              : const _NoStates(),
                        ),
                      )
                    else
                      const SizedBox(width: _Metrics.cell),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _days(BuildContext context, DateTime month) {
    _forgetOtherMonths();
    final value = _dateOnly(_shown);
    final today = _today;
    final focus = _focusAfterTurn;
    if (focus != null &&
        focus.year == month.year &&
        focus.month == month.month) {
      _focusAfterTurn = null;
      // The focus scope hands the focus back to its last holder when the
      // old month's days leave, so autofocus on the new day would not
      // apply; the new day takes it once its zone is mounted.
      _cancelFocus?.call();
      _cancelFocus = _motion.clock.schedulePublish(() {
        _cancelFocus = null;
        if (mounted) _zones.requestFocus(focus);
      });
    }
    final days = [
      for (var d = 1; d <= _daysIn(month); d++)
        DateTime(month.year, month.month, d),
    ];
    for (final day in days) {
      final selected = _sameDay(day, value);
      if (_zones.statesOf(day).contains(WidgetState.selected) != selected) {
        _zones.update(day, WidgetState.selected, add: selected);
      }
    }
    final loc = GlassLocalizations.of(context);
    Widget grid = InputZones<DateTime>(
      zones: [
        for (final day in days)
          InputZone<DateTime>(
            id: day,
            interactions: _pressOf(day),
            enabled: _enabled && _inRange(day),
            minimumHitSize: _target,
            semantics: SemanticsProperties(
              label: loc.dayLabel(day, today: _sameDay(day, today)),
              button: true,
              selected: _sameDay(day, value),
            ),
          ),
      ],
      frameOf: _dayFrame,
      frames: const _Still(),
      controller: _zones,
      axis: null,
      stops: InputZoneStops.one,
      current: _entry(),
      onEdge: _edge,
      child: _monthGrid(context, month, live: true),
    );
    if (widget.focusNode case final node?) {
      grid = Focus(
        focusNode: node,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: _focusPicked,
        child: grid,
      );
    }
    return grid;
  }

  Widget _part({
    required WidgetStatesController states,
    required List<Interaction> interactions,
    required bool enabled,
    required String label,
    required Widget child,
    String? value,
    bool liveRegion = false,
  }) => InputRegion(
    interactions: interactions,
    enabled: enabled,
    statesController: states,
    semantics: SemanticsProperties(label: label),
    minimumHitSize: _target,
    child: Semantics(
      button: true,
      value: value,
      liveRegion: liveRegion,
      excludeSemantics: true,
      child: child,
    ),
  );

  Widget _faded(MotionSelection<double> opacity, Widget child) =>
      MotionTransition(opacity: opacity, child: child);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl != _rtl) {
      _rtl = rtl;
      _chevronAngle = _angle(rtl: rtl);
    }
    final loc = GlassLocalizations.of(context);
    final years = _motion.showsYearPicker;
    final month = _month;
    final titleText = loc.monthYear(month);
    final canPrevious = _enabled && _canTurn(-1);
    final canNext = _enabled && _canTurn(1);
    Widget arrow({required bool next}) {
      final enabled = next ? canNext : canPrevious;
      final states = next ? _next : _previous;
      return _part(
        states: states,
        interactions: next ? _nextPress : _previousPress,
        enabled: enabled,
        label: next ? loc.nextMonthLabel : loc.previousMonthLabel,
        child: SizedBox(
          width: _Metrics.chevronButton,
          height: _Metrics.headerHeight,
          child: widget.arrowBuilder(
            context,
            GlassDatePickerArrow(
              next: next,
              pointsRight: next != rtl,
              enabled: enabled,
              states: states,
            ),
          ),
        ),
      );
    }

    final previous = _previousMonth;
    final previousGrid = previous == null
        ? null
        : ExcludeSemantics(
            child: IgnorePointer(
              child: _monthGrid(context, previous, live: false),
            ),
          );
    final monthGrid = _days(context, month);
    final calendar = Padding(
      padding: const EdgeInsets.only(top: _Metrics.top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _Metrics.headerHeight,
            child: Row(
              children: [
                const SizedBox(width: _Metrics.titleButtonStart),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: _part(
                          states: _title,
                          interactions: _titlePress,
                          enabled: _enabled,
                          label: years
                              ? loc.hideYearPickerLabel
                              : loc.showYearPickerLabel,
                          value: titleText,
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start:
                                  _Metrics.titleInset -
                                  _Metrics.titleButtonStart,
                              end: _Metrics.titleButtonEnd,
                            ),
                            child: SizedBox(
                              height: _Metrics.headerHeight,
                              child: widget.titleBuilder(
                                context,
                                GlassDatePickerTitle(
                                  text: titleText,
                                  showsYearPicker: years,
                                  chevronAngle: _chevronAngle,
                                  states: _title,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _faded(
                  _gridOpacity,
                  IgnorePointer(
                    ignoring: years,
                    child: ExcludeSemantics(
                      excluding: years,
                      child: ExcludeFocus(
                        excluding: years,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [arrow(next: false), arrow(next: true)],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _Metrics.chevronEnd),
              ],
            ),
          ),
          Expanded(
            child: _faded(
              _gridOpacity,
              IgnorePointer(
                ignoring: years,
                child: ExcludeSemantics(
                  excluding: years,
                  child: ExcludeFocus(
                    excluding: years,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: _Metrics.weekdayTop),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _Metrics.gridInset,
                          ),
                          child: SizedBox(
                            height: _Metrics.weekdayHeight,
                            child: ExcludeSemantics(
                              child: Row(
                                children: [
                                  for (var i = 0; i < 7; i++)
                                    SizedBox(
                                      width: _Metrics.cell,
                                      child: widget.weekdayBuilder(
                                        context,
                                        loc.weekdayAbbreviation(
                                          (widget.firstDayOfWeek + i - 1) % 7 +
                                              1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _Metrics.gridInset - _Metrics.reach,
                              _Metrics.gridTop,
                              _Metrics.gridInset - _Metrics.reach,
                              0,
                            ),
                            child: _PageClip(
                              inset: _Metrics.reach,
                              // A page turn repaints the moving grids'
                              // offsets only, not the weekday row above;
                              // mounting or swapping a grid lays out only
                              // this area.
                              child: _ScopedRepaintBoundary(
                                builder: (context, _) => ListenableBuilder(
                                  listenable: _pageTurning,
                                  builder: (context, _) => _daysReady
                                      ? _turning(
                                          rtl: rtl,
                                          previous: previous,
                                          previousGrid: previousGrid,
                                          month: month,
                                          monthGrid: monthGrid,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final wheels = widget.monthYearBuilder(
      context,
      GlassDatePickerMonthYear(
        month: month,
        firstDate: widget._minimum,
        lastDate: widget._maximum,
        onChanged: _pickMonth,
      ),
    );
    return MotionScope(
      motion: _motion,
      child: SizedBox.fromSize(
        size: RawGlassDatePicker.size,
        child: Stack(
          children: [
            Positioned.fill(child: calendar),
            PositionedDirectional(
              start: _Metrics.wheelsStart,
              top: _Metrics.wheelsTop,
              width: _Metrics.wheelsWidth,
              height: _Metrics.wheelsHeight,
              child: ListenableBuilder(
                listenable: _yearsVisible,
                builder: (context, child) {
                  if (!years && !_yearsVisible.value) {
                    return const SizedBox.shrink();
                  }
                  return IgnorePointer(
                    ignoring: !years,
                    child: ExcludeSemantics(
                      excluding: !years,
                      child: _faded(_wheelsOpacity, child!),
                    ),
                  );
                },
                child: wheels,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _turning({
    required bool rtl,
    required DateTime? previous,
    required Widget? previousGrid,
    required DateTime month,
    required Widget monthGrid,
  }) {
    final turning = _pageTurning.value;
    double dir(DatePickerCalendarMotion m) =>
        m.pageDirection * (rtl ? -1.0 : 1.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (previousGrid != null && previous != null && turning)
          Positioned(
            key: ValueKey<DateTime>(previous),
            left: _Metrics.reach,
            top: 0,
            width: _Metrics.grid,
            child: MotionTransition(
              offset: _motion.select(
                (m) => Offset(-dir(m) * _Metrics.grid * m.page, 0),
              ),
              child: previousGrid,
            ),
          ),
        Positioned(
          key: ValueKey<DateTime>(month),
          left: 0,
          top: 0,
          width: _Metrics.grid + 2 * _Metrics.reach,
          child: MotionTransition(
            offset: _motion.select((m) {
              final q = m.page;
              return Offset(
                previousGrid != null && q < 1
                    ? dir(m) * _Metrics.grid * (1 - q)
                    : 0,
                0,
              );
            }),
            // The outer days' targets reach past the grid.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _Metrics.reach),
              child: monthGrid,
            ),
          ),
        ),
      ],
    );
  }
}

/// The states of one day's zone as they change.
final class _DayStates extends ChangeNotifier
    implements ValueListenable<Set<WidgetState>> {
  _DayStates(this._zones, this._day) {
    _zones.addListener(_changed);
    _value = _zones.statesOf(_day).toSet();
  }

  final InputZonesController<DateTime> _zones;
  final DateTime _day;
  late Set<WidgetState> _value;

  @override
  Set<WidgetState> get value => _value;

  void _changed() {
    final now = _zones.statesOf(_day);
    if (setEquals(now, _value)) return;
    _value = now.toSet();
    notifyListeners();
  }

  @override
  void dispose() {
    _zones.removeListener(_changed);
    super.dispose();
  }
}

/// The states of a day that takes no input: the month a page turn leaves.
final class _NoStates implements ValueListenable<Set<WidgetState>> {
  const _NoStates();

  @override
  Set<WidgetState> get value => const {};

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// A repaint boundary that is also a build scope of its own, as a
/// [LayoutBuilder] is: a rebuild of its subtree lays out and repaints
/// from here down, where the overlay's [LayoutBuilder] above would lay
/// itself out and repaint the overlay's box around it.
class _ScopedRepaintBoundary extends ConstrainedLayoutBuilder<BoxConstraints> {
  const _ScopedRepaintBoundary({required super.builder});

  @override
  RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox>
  createRenderObject(BuildContext context) => _RenderScopedRepaintBoundary();
}

class _RenderScopedRepaintBoundary extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox> {
  @override
  bool get isRepaintBoundary => true;

  // A layout marks its render object for paint; this one paints nothing
  // but its child at its origin, so a layout that keeps its size and its
  // child leaves the paint to whatever below it changed (a change below
  // marks this boundary on its own).
  bool _keepsPaint = false;

  @override
  void markNeedsPaint() {
    if (_keepsPaint) {
      _keepsPaint = false;
      return;
    }
    super.markNeedsPaint();
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final before = hasSize ? size : null;
    final childBefore = this.child;
    runLayoutCallback();
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child.size);
    } else {
      size = constraints.biggest;
    }
    _keepsPaint = size == before && identical(child, childBefore);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;

  @override
  void paint(PaintingContext context, Offset offset) {
    _keepsPaint = false;
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }
}

/// Paints its child clipped [inset] inside its left and right edges, but
/// takes hits and bounds semantics in its whole box: the outer days'
/// targets reach past the grid that the paging months must not paint
/// beyond.
class _PageClip extends SingleChildRenderObjectWidget {
  const _PageClip({required this.inset, super.child});

  final double inset;

  @override
  _RenderPageClip createRenderObject(BuildContext context) =>
      _RenderPageClip(inset);
}

class _RenderPageClip extends RenderProxyBox {
  _RenderPageClip(this._inset);

  final double _inset;

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      _clip.layer = null;
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(_inset, 0, size.width - _inset, size.height),
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
