part of 'date_picker.dart';

int _floorMinute(int minute, int interval) =>
    interval < 2 ? minute : minute - minute % interval;

DateTime _clampDate(DateTime value, DateTime? first, DateTime? last) {
  if (first != null && value.isBefore(first)) return first;
  if (last != null && value.isAfter(last)) return last;
  return value;
}

class _TimeWheelsState extends State<GlassTimePicker> {
  static const int _loops = _WheelGeometry.loops;
  int get _hourCount => _twentyFour ? 24 : 12;
  late int _hourIndex = _hourCount * (_loops ~/ 2) + _hour % _hourCount;
  late final FixedExtentScrollController _hours = FixedExtentScrollController(
    initialItem: _hourIndex,
  );
  int get _step => widget.minuteInterval;
  bool get _twentyFour =>
      widget.use24HourFormat ??
      MediaQuery.maybeAlwaysUse24HourFormatOf(context) ??
      false;
  bool get _enabled => widget.onChanged != null;
  int get _minuteCount => 60 ~/ _step;
  late final FixedExtentScrollController _minutes = FixedExtentScrollController(
    initialItem: _minuteCount * (_loops ~/ 2) + _minute ~/ _step,
  );
  late final FixedExtentScrollController _meridiem =
      FixedExtentScrollController(initialItem: _hour < 12 ? 0 : 1);
  late int _hour = _bounded(widget.value).hour;
  late int _minute = _rounded(_bounded(widget.value).minute);

  int _rounded(int minute) => _floorMinute(minute, widget.minuteInterval);

  bool get _pm => _hour >= 12;
  bool? _twentyFourShown;
  bool _syncing = false;
  final _WheelViews _views = _WheelViews();

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _meridiem.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _bounded(widget.value);
    _sync(value, formatChanged: _formatChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_formatChanged()) _sync(_bounded(widget.value), formatChanged: true);
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

  void _sync(DateTime value, {bool formatChanged = false}) {
    _syncing = true;
    final hourChanged = _hour != value.hour || formatChanged;
    final minute = _rounded(value.minute);
    final minuteChanged = _minute != minute;
    _hour = value.hour;
    _minute = minute;
    if (hourChanged && _hours.hasClients) {
      _hourIndex = _hourCount * (_loops ~/ 2) + _hour % _hourCount;
      _hours.jumpToItem(_hourIndex);
    }
    if (minuteChanged && _minutes.hasClients) {
      _minutes.jumpToItem(_minuteCount * (_loops ~/ 2) + _minute ~/ _step);
    }
    if (_meridiem.hasClients && _meridiem.selectedItem != (_pm ? 1 : 0)) {
      _meridiem.jumpToItem(_pm ? 1 : 0);
    }
    _syncing = false;
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

  void _hourChanged(int index) {
    if (_syncing) return;
    if (_twentyFour) {
      if (index % 24 == _hour) return;
      setState(() => _hour = index % 24);
      _emit();
      return;
    }
    if (index == _hourIndex) return;
    final crossed = index ~/ 12 - _hourIndex ~/ 12;
    _hourIndex = index;
    var pm = _pm;
    if (crossed.isOdd) {
      pm = !pm;
      if (_meridiem.hasClients) {
        _meridiem.animateToItem(
          pm ? 1 : 0,
          duration: _wheelStep,
          curve: _wheelStepCurve,
        );
      }
    }
    setState(() => _hour = index % 12 + (pm ? 12 : 0));
    _emit();
  }

  void _minuteChanged(int m) {
    final minute = (m % _minuteCount) * _step;
    if (_syncing || minute == _minute) return;
    setState(() => _minute = minute);
    _emit();
  }

  void _meridiemChanged(int index) {
    if (_syncing) return;
    final pm = index == 1;
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
                      controller: _hours,
                      count: _hourCount,
                      text: _hourText,
                      selected: _hour % _hourCount,
                      label: loc.hourLabel,
                      alignment: twelve
                          ? Alignment.centerRight
                          : Alignment.center,
                      padding: EdgeInsets.only(
                        right: twelve ? _WheelMetrics.hour12End : 0,
                      ),
                      onSelected: _hourChanged,
                      views: _views,
                      viewKey: _twentyFour,
                      context: context,
                      enabled: _enabled,
                    ),
                  ),
                  _column(
                    minute,
                    _wheel(
                      geometry: geometry,
                      look: look,
                      controller: _minutes,
                      count: _minuteCount,
                      text: (int i) => _two(i * _step),
                      selected: _minute ~/ _step,
                      label: loc.minuteLabel,
                      onSelected: _minuteChanged,
                      views: _views,
                      viewKey: _step,
                      context: context,
                      enabled: _enabled,
                    ),
                  ),
                  if (twelve)
                    _column(
                      _WheelMetrics.meridiem,
                      _wheel(
                        geometry: geometry,
                        look: look,
                        controller: _meridiem,
                        count: 2,
                        looping: false,
                        text: (int i) => i == 0
                            ? loc.anteMeridiemAbbreviation
                            : loc.postMeridiemAbbreviation,
                        selected: _pm ? 1 : 0,
                        label: loc.dayPeriodLabel,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(
                          left: _WheelMetrics.meridiemStart,
                        ),
                        onSelected: _meridiemChanged,
                        views: _views,
                        viewKey: loc,
                        context: context,
                        enabled: _enabled,
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
  static const int _loops = _WheelGeometry.loops;
  GlassDatePickerMonthYear get _details => widget.details;
  int get _firstYear => _details.firstDate?.year ?? 1;
  int get _lastYear => math.max(_firstYear, _details.lastDate?.year ?? 9999);
  late int _month = _details.month.month;
  late int _year = _details.month.year.clamp(_firstYear, _lastYear);
  late final FixedExtentScrollController _monthWheel =
      FixedExtentScrollController(initialItem: 12 * (_loops ~/ 2) + _month - 1);
  late final FixedExtentScrollController _yearWheel =
      FixedExtentScrollController(initialItem: _year - _firstYear);
  late (int, int) _emitted;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _emitted = (_year, _month);
  }

  @override
  void dispose() {
    _monthWheel.dispose();
    _yearWheel.dispose();
    super.dispose();
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
    _syncing = true;
    _month = _details.month.month;
    _year = _details.month.year.clamp(_firstYear, _lastYear);
    _emitted = (_year, _month);
    if (_monthWheel.hasClients && _monthWheel.selectedItem % 12 != _month - 1) {
      _monthWheel.jumpToItem(12 * (_loops ~/ 2) + _month - 1);
    }
    if (_yearWheel.hasClients &&
        _yearWheel.selectedItem != _year - _firstYear) {
      _yearWheel.jumpToItem(_year - _firstYear);
    }
    _syncing = false;
  }

  bool _settled(ScrollEndNotification notification) {
    if (_syncing) return false;
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
                      controller: _monthWheel,
                      count: 12,
                      text: (int i) => loc.monthName(i + 1),
                      selected: _month - 1,
                      label: loc.monthLabel,
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsetsDirectional.only(
                        start: _MonthYearMetrics.monthStart,
                      ),
                      onSelected: (int i) {
                        if (!_syncing) setState(() => _month = i % 12 + 1);
                      },
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
                      controller: _yearWheel,
                      count: _lastYear - _firstYear + 1,
                      looping: false,
                      text: (int i) => '${_firstYear + i}',
                      selected: _year - _firstYear,
                      label: loc.yearLabel,
                      onSelected: (int i) {
                        if (!_syncing) setState(() => _year = _firstYear + i);
                      },
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
