part of 'date_picker.dart';

int _floorMinute(int minute, int interval) =>
    interval < 2 ? minute : minute - minute % interval;

DateTime _clampDate(DateTime value, DateTime? first, DateTime? last) {
  if (first != null && value.isBefore(first)) return first;
  if (last != null && value.isAfter(last)) return last;
  return value;
}

class _TimeWheelsState extends State<GlassTimePicker> {
  int get _hourCount => _twentyFour ? 24 : 12;
  int get _step => widget.minuteInterval;
  bool get _twentyFour =>
      widget.use24HourFormat ??
      MediaQuery.maybeAlwaysUse24HourFormatOf(context) ??
      false;
  bool get _enabled => widget.onChanged != null;
  int get _minuteCount => 60 ~/ _step;
  late int _hour = _bounded(widget.value).hour;
  late int _minute = _rounded(_bounded(widget.value).minute);

  int _rounded(int minute) => _floorMinute(minute, widget.minuteInterval);

  bool get _pm => _hour >= 12;
  bool? _twentyFourShown;
  int _hourLaps = 0;

  @override
  void didUpdateWidget(GlassTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _formatChanged();
    _sync(_bounded(widget.value));
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

  DateTime _bounded(DateTime value) {
    final first = widget.minimumDate;
    final last = widget.maximumDate;
    final holds = first == null || last == null || !last.isBefore(first);
    return holds ? _clampDate(value, first, last) : value;
  }

  void _sync(DateTime value) {
    _hour = value.hour;
    _minute = _rounded(value.minute);
  }

  void _emit() {
    final v = widget.value;
    widget.onChanged?.call(
      _bounded(DateTime(v.year, v.month, v.day, _hour, _minute)),
    );
  }

  String _hourText(int h) {
    if (_twentyFour) return _two(h);
    return '${h == 0 ? 12 : h}';
  }

  void _hourChanged(int row) {
    final laps = _hourLaps;
    _hourLaps = 0;
    final pm = laps.isOdd != _pm;
    setState(() => _hour = _twentyFour ? row : row + (pm ? 12 : 0));
    _emit();
  }

  void _minuteChanged(int row) {
    setState(() => _minute = row * _step);
    _emit();
  }

  void _meridiemChanged(int row) {
    final pm = row == 1;
    if (pm == _pm) return;
    setState(() => _hour = _hour % 12 + (pm ? 12 : 0));
    _emit();
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
                        animatesValue: true,
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
      style: resolveGlassText(
        TextStyle(fontSize: 17, color: look.labelColor),
        context,
      ),
      child: SizedBox.fromSize(
        size: DatePickerMotion.timeSize,
        child: _enabled ? wheels : AbsorbPointer(child: wheels),
      ),
    );
  }
}

/// The calendar's month and year wheels, shown in place of the day grid
/// after a tap on the month title.
///
/// The month wheel loops; the year wheel runs from the first allowed year
/// to the last. A wheel coming to rest on a new row reports the year and
/// month, as UIKit sends its value change when the wheel settles.
class _MonthYearWheels extends StatefulWidget {
  const _MonthYearWheels({required this.details, required this.look});

  final GlassDatePickerMonthYear details;
  final GlassDatePickerStyle look;

  @override
  State<_MonthYearWheels> createState() => _MonthYearWheelsState();
}

class _MonthYearWheelsState extends State<_MonthYearWheels> {
  GlassDatePickerMonthYear get _details => widget.details;
  int get _firstYear => _details.firstDate?.year ?? 1;
  int get _lastYear => math.max(_firstYear, _details.lastDate?.year ?? 9999);
  late int _month = _details.month.month;
  late int _year = _details.month.year.clamp(_firstYear, _lastYear);
  late (int, int) _emitted;

  @override
  void initState() {
    super.initState();
    _emitted = (_year, _month);
  }

  @override
  void didUpdateWidget(_MonthYearWheels oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.details;
    if (_details.month != old.month ||
        _details.firstDate != old.firstDate ||
        _details.lastDate != old.lastDate) {
      _sync();
    }
  }

  void _sync() {
    _month = _details.month.month;
    _year = _details.month.year.clamp(_firstYear, _lastYear);
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
                      text: (int i) => loc.monthName(i + 1),
                      value: _month - 1,
                      label: loc.monthLabel,
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsetsDirectional.only(
                        start: _MonthYearMetrics.monthStart,
                      ),
                      onChanged: (int row) => setState(() => _month = row + 1),
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
                      count: _lastYear - _firstYear + 1,
                      looping: false,
                      text: (int i) => '${_firstYear + i}',
                      value: _year - _firstYear,
                      label: loc.yearLabel,
                      onChanged: (int row) =>
                          setState(() => _year = _firstYear + row),
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
