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
