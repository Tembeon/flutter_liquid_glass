part of 'date_picker.dart';

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
