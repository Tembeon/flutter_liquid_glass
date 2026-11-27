part of 'date_picker.dart';

class _TimeWheelsState extends State<GlassTimePicker> {
  late int _hour = _bounded(widget.value).hour;
  late int _minute = _rounded(_bounded(widget.value).minute);
  late (int, int) _emitted;
  bool? _twentyFourShown;
  int _hourLaps = 0;
  bool _meridiemSteps = false;

  bool get _twentyFour => use24HourFormatAt(context, widget.use24HourFormat);
  int get _hourCount => _twentyFour ? 24 : 12;
  int get _step => widget.minuteInterval;
  int get _minuteCount => 60 ~/ _step;
  bool get _enabled => widget.onChanged != null;
  bool get _pm => _hour >= 12;

  int _rounded(int minute) => minute - minute % _step;

  @override
  void initState() {
    super.initState();
    _emitted = (_hour, _minute);
  }

  @override
  void didUpdateWidget(GlassTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reformatted = _formatChanged();
    if (reformatted ||
        widget.value != oldWidget.value ||
        widget.minuteInterval != oldWidget.minuteInterval ||
        widget.minimumDate != oldWidget.minimumDate ||
        widget.maximumDate != oldWidget.maximumDate) {
      _sync(_bounded(widget.value));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_formatChanged()) _sync(_bounded(widget.value));
  }

  bool _formatChanged() {
    final was = _twentyFourShown;
    _twentyFourShown = _twentyFour;
    return was != null && was != _twentyFourShown;
  }

  DateTime _bounded(DateTime value) =>
      GlassDateBounds(widget.minimumDate, widget.maximumDate).clamp(value);

  void _sync(DateTime value) {
    // An hour the app sets jumps the day period; only the hour wheel's own
    // wrap turns it in a step.
    if (value.hour != _hour) _meridiemSteps = false;
    _hour = value.hour;
    _minute = _rounded(value.minute);
    _emitted = (_hour, _minute);
  }

  bool _settled(ScrollEndNotification notification) {
    if (_emitted != (_hour, _minute)) {
      _emitted = (_hour, _minute);
      final v = widget.value;
      widget.onChanged?.call(
        _bounded(DateTime(v.year, v.month, v.day, _hour, _minute)),
      );
    }
    return false;
  }

  String _hourText(int h) {
    if (_twentyFour) return _two(h);
    return '${h == 0 ? 12 : h}';
  }

  void _hourChanged(int row) {
    final laps = _hourLaps;
    _hourLaps = 0;
    final pm = laps.isOdd != _pm;
    setState(() {
      _meridiemSteps = pm != _pm;
      _hour = _twentyFour ? row : row + (pm ? 12 : 0);
    });
  }

  void _minuteChanged(int row) => setState(() => _minute = row * _step);

  void _meridiemChanged(int row) {
    final pm = row == 1;
    if (pm == _pm) return;
    setState(() => _hour = _hour % 12 + (pm ? 12 : 0));
  }

  Widget _column(_WheelColumn column, Widget wheel) => Positioned(
    left: column.left - _WheelMetrics.inset,
    width: column.width,
    top: 0,
    bottom: 0,
    child: wheel,
  );

  @override
  Widget build(BuildContext context) {
    final look = GlassDatePickerStyle.resolve(context, widget.style);
    final loc = GlassLocalizations.of(context);
    final twelve = !_twentyFour;
    final hour = twelve ? _WheelMetrics.hour12 : _WheelMetrics.hour24;
    final minute = twelve ? _WheelMetrics.minute12 : _WheelMetrics.minute24;
    const geometry = _WheelMetrics.geometry;
    final wheels = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _WheelMetrics.inset,
        vertical: _WheelMetrics.top,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: _WheelMetrics.bandInset,
            right: _WheelMetrics.bandInset,
            height: _WheelMetrics.band,
            child: _wheelBand(look),
          ),
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: geometry.shade,
              child: Stack(
                children: [
                  _column(
                    hour,
                    _wheel(
                      geometry: geometry,
                      look: look,
                      count: _hourCount,
                      text: _hourText,
                      value: _hour % _hourCount,
                      label: loc.hourLabel,
                      alignment: twelve
                          ? Alignment.centerRight
                          : Alignment.center,
                      padding: EdgeInsets.only(
                        right: twelve ? _WheelMetrics.hour12End : 0,
                      ),
                      onChanged: _enabled ? _hourChanged : null,
                      onWrapped: (laps) => _hourLaps = laps,
                      rowsKey: _twentyFour,
                      context: context,
                    ),
                  ),
                  _column(
                    minute,
                    _wheel(
                      geometry: geometry,
                      look: look,
                      count: _minuteCount,
                      text: (int i) => _two(i * _step),
                      value: _minute ~/ _step,
                      label: loc.minuteLabel,
                      onChanged: _enabled ? _minuteChanged : null,
                      rowsKey: _step,
                      context: context,
                    ),
                  ),
                  if (twelve)
                    _column(
                      _WheelMetrics.meridiem,
                      _wheel(
                        geometry: geometry,
                        look: look,
                        count: 2,
                        looping: false,
                        animatesValue: _meridiemSteps,
                        text: (int i) => i == 0
                            ? loc.anteMeridiemAbbreviation
                            : loc.postMeridiemAbbreviation,
                        value: _pm ? 1 : 0,
                        label: loc.dayPeriodLabel,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(
                          left: _WheelMetrics.meridiemStart,
                        ),
                        onChanged: _enabled ? _meridiemChanged : null,
                        rowsKey: loc,
                        context: context,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return DefaultTextStyle(
      style: GlassTextScale.fixed(
        context,
      ).resolve(TextStyle(fontSize: 17, color: look.labelColor)),
      child: SizedBox.fromSize(
        size: DatePickerMotion.timeSize,
        child: _enabled
            ? NotificationListener<ScrollEndNotification>(
                onNotification: _settled,
                child: wheels,
              )
            : AbsorbPointer(child: wheels),
      ),
    );
  }
}

/// A duration in hours and minutes on two wheels, as a timer sets it.
///
/// UIKit: `UIDatePicker` with `datePickerMode = .countDownTimer` and
/// `countDownDuration`. Flutter: `CupertinoTimerPicker` in
/// `CupertinoTimerPickerMode.hm`.
///
/// The hour wheel runs from 0 to 23 and stops at its ends; the minute
/// wheel loops through the multiples of [minuteInterval]. Each number
/// stands right-aligned before its unit, "hour" or "hours" and "min" in 17
/// point semibold, which stay where they are while the wheels turn. A
/// wheel coming to rest on a new row calls [onChanged] once with the
/// duration; a count-down never rests at zero: wheels that stop on 0:00
/// report one [minuteInterval] and the minute wheel turns on to it. A
/// [value] between two multiples of the interval shows floored to the
/// earlier one, and one under an interval shows as one.
///
/// ```dart
/// GlassCountDownPicker(
///   value: timer,
///   onChanged: (picked) => setState(() => timer = picked),
/// )
/// ```
///
/// Fidelity. The size, the columns, the units and the rules for zero and
/// for values set from code are measured on the iOS 27.2 simulator (date
/// picker passport and a tree dump of the picker at 1 hour 30 minutes);
/// the wheels' rows and fade are the calendar's month and year wheels'.
class GlassCountDownPicker extends StatefulWidget {
  /// Creates wheels showing [value].
  const GlassCountDownPicker({
    required this.value,
    required this.onChanged,
    this.minuteInterval = 1,
    this.style,
    super.key,
  }) : assert(
         minuteInterval >= 1 &&
             minuteInterval <= 30 &&
             60 % minuteInterval == 0,
         'minuteInterval must divide 60 and lie in 1 to 30.',
       );

  /// The duration shown, as [shownFor] gives it.
  final Duration value;

  /// Called with the duration when a wheel comes to rest on a new row;
  /// null disables the wheels.
  final ValueChanged<Duration>? onChanged;

  /// The step of the minute wheel in minutes, a divisor of 60 from 1 to
  /// 30 (UIKit `minuteInterval`).
  final int minuteInterval;

  /// The look, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  /// The size of the wheels.
  static const Size size = Size(320, 216);

  /// The duration the wheels show for [value]: floored to [minuteInterval],
  /// at least one interval and at most 23 hours and the last multiple of
  /// the interval, as UIKit reads back `countDownDuration` (3725 seconds
  /// with an interval of 5 read 3600; 100 with 15 read 900).
  static Duration shownFor(Duration value, {int minuteInterval = 1}) {
    final minutes = value.inMinutes - value.inMinutes % minuteInterval;
    return Duration(
      minutes: minutes.clamp(minuteInterval, 24 * 60 - minuteInterval),
    );
  }

  @override
  State<GlassCountDownPicker> createState() => _CountDownState();
}

class _CountDownState extends State<GlassCountDownPicker> {
  late int _hours;
  late int _minutes;
  late (int, int) _emitted;

  int get _step => widget.minuteInterval;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GlassCountDownPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value ||
        widget.minuteInterval != oldWidget.minuteInterval) {
      _sync();
    }
  }

  void _sync() {
    final shown = GlassCountDownPicker.shownFor(
      widget.value,
      minuteInterval: _step,
    );
    _hours = shown.inHours;
    _minutes = shown.inMinutes % 60;
    _emitted = (_hours, _minutes);
  }

  bool _settled(ScrollEndNotification notification) {
    if (_hours == 0 && _minutes == 0) setState(() => _minutes = _step);
    if (_emitted != (_hours, _minutes)) {
      _emitted = (_hours, _minutes);
      widget.onChanged?.call(Duration(hours: _hours, minutes: _minutes));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final look = GlassDatePickerStyle.resolve(context, widget.style);
    final loc = GlassLocalizations.of(context);
    final enabled = widget.onChanged != null;
    const geometry = _MonthYearMetrics.geometry;
    final unit = GlassTextScale.fixed(context).resolve(
      TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: look.labelColor,
      ),
    );
    Widget column({
      required double start,
      required double end,
      required double digitsEnd,
      required int count,
      required int value,
      required bool looping,
      required String Function(int) text,
      required String label,
      required ValueChanged<int> onChanged,
    }) => PositionedDirectional(
      start: start,
      width: end - start,
      top: 0,
      bottom: 0,
      child: _wheel(
        geometry: geometry,
        look: look,
        count: count,
        looping: looping,
        animatesValue: true,
        text: text,
        value: value,
        label: label,
        alignment: AlignmentDirectional.centerEnd,
        padding: EdgeInsetsDirectional.only(end: end - digitsEnd),
        onChanged: enabled ? onChanged : null,
        context: context,
      ),
    );
    Widget units(double start, String text) => PositionedDirectional(
      start: start,
      top: _CountDownMetrics.unitTop,
      child: IgnorePointer(child: Text(text, style: unit, maxLines: 1)),
    );
    return DefaultTextStyle(
      style: GlassTextScale.fixed(
        context,
      ).resolve(TextStyle(fontSize: 17, color: look.labelColor)),
      child: SizedBox.fromSize(
        size: GlassCountDownPicker.size,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: _settled,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                height: _MonthYearMetrics.band,
                child: _wheelBand(look),
              ),
              Positioned.fill(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: geometry.shade,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      column(
                        start: 0,
                        end: _CountDownMetrics.minutesStart,
                        digitsEnd: _CountDownMetrics.hoursEnd,
                        count: 24,
                        looping: false,
                        value: _hours,
                        text: (int i) => '$i',
                        label: loc.hourLabel,
                        onChanged: (int row) => setState(() => _hours = row),
                      ),
                      column(
                        start: _CountDownMetrics.minutesStart,
                        end: _CountDownMetrics.minutesColumnEnd,
                        digitsEnd: _CountDownMetrics.minutesEnd,
                        count: 60 ~/ _step,
                        looping: true,
                        value: _minutes ~/ _step,
                        text: (int i) => '${i * _step}',
                        label: loc.minuteLabel,
                        onChanged: (int row) =>
                            setState(() => _minutes = row * _step),
                      ),
                    ],
                  ),
                ),
              ),
              units(
                _CountDownMetrics.hoursUnit,
                loc.countDownHoursUnit(_hours),
              ),
              units(_CountDownMetrics.minutesUnit, loc.countDownMinutesUnit),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a count-down's numbers and units stand in its 320 points (tree
/// dump of the iOS 27.2 simulator's picker): the numbers right-aligned to
/// 103.33 and 188.33 points in, the units at 112.67 and 197.67, their 21.33
/// point line 98.33 down. Each wheel takes the touches of its column,
/// UIKit's 78 to 158 and 163 to 243 (date picker passport): the hour wheel
/// from the start to 158, its unit included, and the minute wheel from 158
/// to 243. A wheel magnifies its band about its box's middle, where UIKit
/// grows the number from its leading edge: the band's hours stand within a
/// point of UIKit's, its minutes about 5 points before them (NEAR).
abstract final class _CountDownMetrics {
  static const double hoursEnd = 103.33;
  static const double minutesEnd = 188.33;
  static const double hoursUnit = 112.67;
  static const double minutesUnit = 197.67;
  static const double unitTop = 98.33;
  static const double minutesStart = 158;
  static const double minutesColumnEnd = 243;
}

/// A month and a year on two wheels in place.
///
/// UIKit: `UIDatePicker` with `datePickerMode = .yearAndMonth` and the
/// wheels style. Flutter: `CupertinoDatePicker` in
/// `CupertinoDatePickerMode.monthYear`.
///
/// The wheels are the calendar's own, those a tap on its month title
/// shows: the month wheel loops and the year wheel runs from 1 to 9999. A
/// wheel coming to rest on a new row calls [onChanged] once with the first
/// day of that month, at midnight, moved into [minimumDate] and
/// [maximumDate] by month; a new [value] turns the wheels to it, so an app
/// that sets the value it gets turns a wheel back from a month out of
/// bounds, as UIKit's roll back.
///
/// ```dart
/// GlassMonthYearPicker(
///   value: month,
///   onChanged: (picked) => setState(() => month = picked),
/// )
/// ```
///
/// Fidelity. The wheels, their rows and their fade are measured in the
/// calendar's overlay (date picker passport, month column 133 points, wheels
/// 288 by 216); standing alone they keep those places.
class GlassMonthYearPicker extends StatelessWidget {
  /// Creates wheels showing [value]'s month and year.
  const GlassMonthYearPicker({
    required this.value,
    required this.onChanged,
    this.minimumDate,
    this.maximumDate,
    this.style,
    super.key,
  });

  /// The month shown; its day and time are not read.
  final DateTime value;

  /// Called with the first day of the month a wheel comes to rest on;
  /// null disables the wheels.
  final ValueChanged<DateTime>? onChanged;

  /// The earliest month that can be picked; null for no limit.
  final DateTime? minimumDate;

  /// The latest month that can be picked; null for no limit.
  final DateTime? maximumDate;

  /// The look, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  /// The size of the wheels.
  static const Size size = Size(288, 216);

  DateTime _bounded(int year, int month) {
    final picked = DateTime(year, month);
    if (minimumDate case final first?
        when picked.isBefore(DateTime(first.year, first.month))) {
      return DateTime(first.year, first.month);
    }
    if (maximumDate case final last?
        when picked.isAfter(DateTime(last.year, last.month))) {
      return DateTime(last.year, last.month);
    }
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    final look = GlassDatePickerStyle.resolve(context, style);
    final onChanged = this.onChanged;
    final wheels = _MonthYearWheels(
      look: look,
      enabled: onChanged != null,
      details: GlassDatePickerMonthYear(
        month: DateTime(value.year, value.month),
        firstDate: minimumDate,
        lastDate: maximumDate,
        onChanged: (year, month) => onChanged?.call(_bounded(year, month)),
      ),
    );
    return DefaultTextStyle(
      style: GlassTextScale.fixed(
        context,
      ).resolve(TextStyle(fontSize: 17, color: look.labelColor)),
      child: SizedBox.fromSize(
        size: size,
        child: wheels,
      ),
    );
  }
}

/// The calendar's month and year wheels, shown in place of the day grid
/// after a tap on the month title.
///
/// The month wheel loops and the year wheel runs from 1 to 9999 whatever
/// the bounds, as UIKit's do. A wheel coming to rest on a new row reports
/// the year and month, as UIKit sends its value change when the wheel
/// settles; a month outside the bounds comes back clamped, and the wheels
/// turn to it.
class _MonthYearWheels extends StatefulWidget {
  const _MonthYearWheels({
    required this.details,
    required this.look,
    this.enabled = true,
  });

  final GlassDatePickerMonthYear details;
  final GlassDatePickerStyle look;
  final bool enabled;

  @override
  State<_MonthYearWheels> createState() => _MonthYearWheelsState();
}

class _MonthYearWheelsState extends State<_MonthYearWheels> {
  GlassDatePickerMonthYear get _details => widget.details;
  static const _years = 9999;
  late int _month;
  late int _year;
  late (int, int) _emitted;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_MonthYearWheels oldWidget) {
    super.didUpdateWidget(oldWidget);
    final month = _details.month;
    if ((month.year, month.month) != _emitted) _sync();
  }

  void _sync() {
    _month = _details.month.month;
    _year = _details.month.year.clamp(1, _years);
    _emitted = (_year, _month);
  }

  bool _settled(ScrollEndNotification notification) {
    if (_emitted != (_year, _month)) {
      _emitted = (_year, _month);
      _details.onChanged(_year, _month);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final loc = GlassLocalizations.of(context);
    const geometry = _MonthYearMetrics.geometry;
    return NotificationListener<ScrollEndNotification>(
      onNotification: _settled,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            height: _MonthYearMetrics.band,
            child: _wheelBand(look),
          ),
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: geometry.shade,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: _MonthYearMetrics.monthColumn.left,
                    width: _MonthYearMetrics.monthColumn.width,
                    top: 0,
                    bottom: 0,
                    child: _wheel(
                      geometry: geometry,
                      look: look,
                      count: 12,
                      animatesValue: true,
                      text: (int i) => loc.monthName(i + 1),
                      value: _month - 1,
                      label: loc.monthLabel,
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsetsDirectional.only(
                        start: _MonthYearMetrics.monthStart,
                      ),
                      onChanged: !widget.enabled
                          ? null
                          : (int row) => setState(() => _month = row + 1),
                      context: context,
                    ),
                  ),
                  PositionedDirectional(
                    start: _MonthYearMetrics.yearColumn.left,
                    width: _MonthYearMetrics.yearColumn.width,
                    top: 0,
                    bottom: 0,
                    child: _wheel(
                      geometry: geometry,
                      look: look,
                      count: _years,
                      looping: false,
                      animatesValue: true,
                      text: (int i) => '${i + 1}',
                      value: _year - 1,
                      label: loc.yearLabel,
                      onChanged: !widget.enabled
                          ? null
                          : (int row) => setState(() => _year = row + 1),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
