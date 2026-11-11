import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/glass.dart';
import 'package:apple_liquid_glass/src/foundation/shape.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/motions/date_picker_motion.dart';
import 'package:apple_liquid_glass/src/surfaces/clip.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// What a [GlassDatePicker] picks.
enum GlassDatePickerMode {
  /// A day: one label that opens a month calendar.
  date,

  /// A time of day: one label that opens the hour and minute wheels.
  time,

  /// A day and a time: a date label and a time label side by side.
  dateAndTime,
}

/// How a [GlassDatePicker] shows itself, after UIKit's
/// `UIDatePickerStyle` (`preferredDatePickerStyle`).
enum GlassDatePickerVariant {
  /// Labels that open the calendar or the wheels in an overlay: the only
  /// style implemented.
  compact,

  /// The calendar in place, without a label. Reserved: not implemented
  /// yet.
  inline,

  /// The wheels in place. Reserved: not implemented yet.
  wheels,
}

/// The colors of a [GlassDatePicker] and its overlay; a null field leaves
/// it to the theme's style, then the default, which follows the
/// brightness and Increase Contrast.
@immutable
class GlassDatePickerStyle {
  /// Creates a style.
  const GlassDatePickerStyle({
    this.accentColor,
    this.labelColor,
    this.labelFillColor,
    this.weekdayColor,
    this.todayFillColor,
    this.selectedDayTextColor,
    this.wheelBandColor,
  });

  /// The accent: the text of an open label, the month title's chevron,
  /// today's number and, when today is the chosen day, its disc; the
  /// theme's primary color, then systemBlue, by default.
  final Color? accentColor;

  /// The text of a compact label, the month title, a day, the month
  /// chevrons, the wheels' rows and the disc behind the chosen day when it
  /// is not today; label by default.
  final Color? labelColor;

  /// The fill of a compact label; tertiarySystemFill by default.
  final Color? labelFillColor;

  /// The weekday initials; secondaryLabel by default.
  final Color? weekdayColor;

  /// The fill behind today when it is not selected; the accent at the
  /// default's opacity by default.
  final Color? todayFillColor;

  /// The chosen day's number on its [labelColor] disc; the opposite of
  /// label by default.
  final Color? selectedDayTextColor;

  /// The band behind the wheels' selected row; tertiarySystemFill by
  /// default.
  final Color? wheelBandColor;

  /// This style over [other].
  GlassDatePickerStyle merge(GlassDatePickerStyle? other) {
    if (other == null) return this;
    return GlassDatePickerStyle(
      accentColor: accentColor ?? other.accentColor,
      labelColor: labelColor ?? other.labelColor,
      labelFillColor: labelFillColor ?? other.labelFillColor,
      weekdayColor: weekdayColor ?? other.weekdayColor,
      todayFillColor: todayFillColor ?? other.todayFillColor,
      selectedDayTextColor: selectedDayTextColor ?? other.selectedDayTextColor,
      wheelBandColor: wheelBandColor ?? other.wheelBandColor,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassDatePickerStyle? lerp(
    GlassDatePickerStyle? a,
    GlassDatePickerStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    final color = snapNull(GlassDynamicColor.lerp);
    return GlassDatePickerStyle(
      accentColor: color(a.accentColor, b.accentColor, t),
      labelColor: color(a.labelColor, b.labelColor, t),
      labelFillColor: color(a.labelFillColor, b.labelFillColor, t),
      weekdayColor: color(a.weekdayColor, b.weekdayColor, t),
      todayFillColor: color(a.todayFillColor, b.todayFillColor, t),
      selectedDayTextColor: color(
        a.selectedDayTextColor,
        b.selectedDayTextColor,
        t,
      ),
      wheelBandColor: color(a.wheelBandColor, b.wheelBandColor, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassDatePickerStyle &&
      other.accentColor == accentColor &&
      other.labelColor == labelColor &&
      other.labelFillColor == labelFillColor &&
      other.weekdayColor == weekdayColor &&
      other.todayFillColor == todayFillColor &&
      other.selectedDayTextColor == selectedDayTextColor &&
      other.wheelBandColor == wheelBandColor;

  @override
  int get hashCode => Object.hash(
    accentColor,
    labelColor,
    labelFillColor,
    weekdayColor,
    todayFillColor,
    selectedDayTextColor,
    wheelBandColor,
  );
}

/// The texts and formats of a [GlassDatePicker], in one place as UIKit's
/// `UIDatePicker.locale`: every field null keeps the measured en_US
/// labels.
@immutable
class GlassDatePickerLocalizations {
  /// Creates the localizations; null fields keep the English defaults.
  const GlassDatePickerLocalizations({
    this.dateFormatter,
    this.timeFormatter,
    this.localize,
    this.calendarTitleFormatter,
    this.daySemanticFormatter,
    this.numberFormatter,
  });

  /// Formats the date label; null for English, such as "Oct 3, 2026".
  final String Function(DateTime)? dateFormatter;

  /// Formats the time label; null for "09:41" or "9:41 AM".
  final String Function(DateTime)? timeFormatter;

  /// Translates fixed English text: full month names, uppercase weekday
  /// abbreviations, "Show year picker", "Hide year picker", "Previous
  /// month", "Next month", "Hour", "Minute", "AM/PM", "AM", "PM",
  /// "Month" and "Year". Null preserves the measured en_US labels.
  /// Use [dateFormatter] and [timeFormatter] for the compact labels.
  final String Function(String)? localize;

  /// Formats the calendar header from its displayed month.
  /// Null joins the translated month name and formatted year.
  final String Function(DateTime)? calendarTitleFormatter;

  /// Formats each calendar day's screen-reader label.
  /// Null joins its formatted day, translated month name and year.
  final String Function(DateTime)? daySemanticFormatter;

  /// Formats day numbers and wheel values, including years, hours and
  /// minutes. Null preserves the measured English digits and padding.
  final String Function(int)? numberFormatter;

  @override
  bool operator ==(Object other) =>
      other is GlassDatePickerLocalizations &&
      other.dateFormatter == dateFormatter &&
      other.timeFormatter == timeFormatter &&
      other.localize == localize &&
      other.calendarTitleFormatter == calendarTitleFormatter &&
      other.daySemanticFormatter == daySemanticFormatter &&
      other.numberFormatter == numberFormatter;

  @override
  int get hashCode => Object.hash(
    dateFormatter,
    timeFormatter,
    localize,
    calendarTitleFormatter,
    daySemanticFormatter,
    numberFormatter,
  );
}

/// The look of a [GlassDatePicker] and its overlay.
@immutable
class _Appearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const _Appearance({
    this.labelFillColor = const Color(0x1F767680),
    this.labelColor = const Color(0xFF000000),
    this.accentColor = const Color(0xFF0088FF),
    this.weekdayColor = const Color(0x993C3C43),
    this.todayFillColor = const Color(0x1F0088FF),
    this.selectedDayTextColor = const Color(0xFFFFFFFF),
    this.wheelBandColor = const Color(0x1F767680),
  });

  /// The table for the ambient brightness and contrast under [style] and
  /// the theme's style; an accent without a today fill of its own lends
  /// [todayFillColor] its color at the table's opacity.
  factory _Appearance.of(BuildContext context, GlassDatePickerStyle? style) {
    final traits = GlassTraits.of(context);
    final night = traits.brightness == Brightness.dark;
    final table = traits.highContrast
        ? (night ? darkHighContrast : lightHighContrast)
        : (night ? dark : light);
    final theme = GlassTheme.of(context);
    final look = (style ?? const GlassDatePickerStyle()).merge(
      theme.datePickerStyle,
    );
    Color? resolved(Color? color) =>
        color == null ? null : GlassDynamicColor.resolve(color, context);
    final accent = resolved(look.accentColor ?? theme.primaryColor);
    return _Appearance(
      labelFillColor: resolved(look.labelFillColor) ?? table.labelFillColor,
      labelColor: resolved(look.labelColor) ?? table.labelColor,
      accentColor: accent ?? table.accentColor,
      weekdayColor: resolved(look.weekdayColor) ?? table.weekdayColor,
      todayFillColor:
          resolved(look.todayFillColor) ??
          accent?.withValues(alpha: table.todayFillColor.a) ??
          table.todayFillColor,
      selectedDayTextColor:
          resolved(look.selectedDayTextColor) ?? table.selectedDayTextColor,
      wheelBandColor: resolved(look.wheelBandColor) ?? table.wheelBandColor,
    );
  }

  /// The fill of a compact label: tertiarySystemFill. A disabled picker's
  /// labels drop it and keep their text, as UIKit's do (iPhone 16 Pro, iOS
  /// 27.0.1, light and dark).
  final Color labelFillColor;

  /// The color of label text: a compact label, the month title, a day, the
  /// month chevrons, the wheels' rows and the disc behind the chosen day
  /// when it is not today.
  final Color labelColor;

  /// The accent: the text of an open label, the month title's chevron,
  /// today's number and, when today is the chosen day, its disc.
  final Color accentColor;

  /// The color of the weekday initials: secondaryLabel.
  final Color weekdayColor;

  /// The fill behind today when it is not selected.
  final Color todayFillColor;

  /// The color of the chosen day's number on its [labelColor] disc.
  final Color selectedDayTextColor;

  /// The band behind the wheels' selected row.
  final Color wheelBandColor;

  /// The color of the chosen day's number when the chosen day is today,
  /// on an [accentColor] disc.
  static const selectedDayColor = Color(0xFFFFFFFF);

  /// The opacity of the wheels' rows outside the band, drawn in
  /// [labelColor] at the smaller size (21 points against the band's 23.5),
  /// before they darken toward the cylinder's edges. UIKit's labels report
  /// 0.447; 0.4 matches the screen (the rows next to the band read 0.36 of
  /// black on an iPhone 16 Pro).
  static const double wheelFadedOpacity = 0.4;

  /// The opacity of a day outside the picker's range (not measured on a
  /// device).
  static const double unavailableDayOpacity = 0.35;

  /// The light appearance.
  static const light = _Appearance();

  /// The dark appearance.
  static const dark = _Appearance(
    labelFillColor: Color(0x3D767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF0091FF),
    weekdayColor: Color(0x99EBEBF5),
    todayFillColor: Color(0x330091FF),
    selectedDayTextColor: Color(0xFF000000),
    wheelBandColor: Color(0x3D767680),
  );

  /// The light appearance under Increase Contrast: the label fill and the
  /// wheel band (tertiarySystemFill) turn from 12 to 20 percent and the
  /// accent takes systemBlue's increased-contrast variant, the today fill
  /// following it at its own opacity (read from UIKit's color tables,
  /// notes private; the weekday color keeps its standard secondaryLabel
  /// value, not measured under Increase Contrast).
  static const lightHighContrast = _Appearance(
    labelFillColor: Color(0x33767680),
    accentColor: Color(0xFF1E6EF4),
    todayFillColor: Color(0x1F1E6EF4),
    wheelBandColor: Color(0x33767680),
  );

  /// The dark appearance under Increase Contrast: the fills turn from 24
  /// to 32 percent and the accent takes its increased-contrast variant
  /// (read from UIKit's color tables, notes private).
  static const darkHighContrast = _Appearance(
    labelFillColor: Color(0x52767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF5CB8FF),
    weekdayColor: Color(0x99EBEBF5),
    todayFillColor: Color(0x335CB8FF),
    selectedDayTextColor: Color(0xFF000000),
    wheelBandColor: Color(0x52767680),
  );

  @override
  bool operator ==(Object other) =>
      other is _Appearance &&
      other.labelFillColor == labelFillColor &&
      other.labelColor == labelColor &&
      other.accentColor == accentColor &&
      other.weekdayColor == weekdayColor &&
      other.todayFillColor == todayFillColor &&
      other.selectedDayTextColor == selectedDayTextColor &&
      other.wheelBandColor == wheelBandColor;

  @override
  int get hashCode => Object.hash(
    labelFillColor,
    labelColor,
    accentColor,
    weekdayColor,
    todayFillColor,
    selectedDayTextColor,
    wheelBandColor,
  );
}

DateTime _clampDate(DateTime value, DateTime? first, DateTime? last) {
  if (first != null && value.isBefore(first)) return first;
  if (last != null && value.isAfter(last)) return last;
  return value;
}

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdays = [
  'SUN',
  'MON',
  'TUE',
  'WED',
  'THU',
  'FRI',
  'SAT',
];

String _two(int v) => v.toString().padLeft(2, '0');

int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The English medium date UIKit shows in an en_US compact label, such as
/// "Oct 3, 2026".
String _defaultDate(DateTime d) =>
    '${_months[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';

/// [minute] rounded down to a multiple of [interval].
int _floorMinute(int minute, int interval) =>
    interval < 2 ? minute : minute - minute % interval;

/// [value] floored to [interval] as [GlassDatePicker.minuteInterval]
/// describes; unchanged for an interval of 1.
DateTime _floorToMinuteInterval(DateTime value, int interval) {
  if (interval < 2) return value;
  return value.copyWith(
    minute: _floorMinute(value.minute, interval),
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
}

String _defaultTime(DateTime d, {required bool twentyFour}) {
  if (twentyFour) return '${_two(d.hour)}:${_two(d.minute)}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// The iOS 27 compact date picker: a label that opens its picker in an
/// overlay.
///
/// The label is a tinted capsule showing [value]; a touch dims its text, and a
/// tap opens the overlay out of it: a month calendar for a date, the hour and
/// minute wheels for a time. The overlay grows out of the label's center on a
/// spring while it fades in and reveals its content from the label's side,
/// hangs below the label (above it when there is no room), and extends toward
/// the leading side, on springs fitted to UIKit's frames ([DatePickerTuning];
/// replayed on an iPhone 16 Pro). While it is open the label's text takes
/// the accent color. Choosing a day or turning a time wheel calls
/// [onChanged] at once and the overlay stays open; a tap outside or Escape
/// closes it, turning an overlay that still opens around. A tap on the
/// label while the overlay closes opens a new one after a shorter delay
/// than a first open, as UIKit does, while the old one finishes its close.
///
/// In 12-hour time the wheels are the hour (1 to 12), the minute and AM/PM,
/// as UIKit lays them out; the hour wheel turning past 11 and 12 switches
/// AM and PM.
///
/// The calendar shows one month with the chosen day filled and today
/// tinted; the chevrons turn the month with a slide. A tap on the month
/// title turns the day grid into month and year wheels in the same
/// overlay (the title takes the accent color at once and its chevron
/// turns to point down over 0.25 s, as UIKit does); a wheel coming
/// to rest moves the chosen day to that month and year, keeping its day
/// of the month where the month has it (the 31st turned to November is
/// the 30th), and another tap on the title returns to the grid. The
/// labels are formatted in English by default ([localizations] translates
/// them). The label is a focusable button; Space and Enter open it. A
/// disabled picker draws its labels as text without their capsules and
/// does not open.
///
/// The content fades inside the overlay's clip: NEAR (the clip's
/// anti-aliased edge row differs by up to 23 of 255 in the first frames
/// of the opening). Each month grid is a layer of its own, so a page turn
/// moves recorded grids instead of painting every day again (IDENTICAL).
/// The day grid (the time wheels) mounts on the frame after the
/// overlay's, while the overlay is still transparent, so the open's
/// layout spreads over two frames (IDENTICAL). A label dims under the
/// finger through the alpha of its text color instead of an opacity
/// layer: NEAR (one rounding instead of two, at most 1 of 255 per
/// channel, except where the anti-aliased edges of two glyphs share a
/// pixel, which a layer would cover once and the color covers twice).
class GlassDatePicker extends StatefulWidget {
  /// Creates a picker.
  const GlassDatePicker({
    required this.value,
    required this.onChanged,
    this.mode = GlassDatePickerMode.date,
    this.variant = GlassDatePickerVariant.compact,
    this.style,
    this.minuteInterval = 1,
    this.minimumDate,
    this.maximumDate,
    this.use24HourFormat,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.semanticLabel,
    this.localizations = const GlassDatePickerLocalizations(),
    super.key,
  }) : assert(
         variant == GlassDatePickerVariant.compact,
         'Only GlassDatePickerVariant.compact is implemented.',
       ),
       assert(
         minuteInterval >= 1 &&
             minuteInterval <= 30 &&
             60 % minuteInterval == 0,
         'minuteInterval must divide 60 and lie in 1 to 30.',
       );

  /// How the picker shows itself (UIKit `preferredDatePickerStyle`);
  /// only [GlassDatePickerVariant.compact] is implemented.
  final GlassDatePickerVariant variant;

  /// The colors, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  /// The step of the minute wheel in minutes, a divisor of 60 from 1 to
  /// 30 (UIKit `minuteInterval`). As UIKit's `roundsToMinuteInterval`
  /// does, a time between two multiples is rounded DOWN to the earlier one
  /// with its seconds dropped, in the label and on the wheel alike, and the
  /// picker reports only such times (read from UIKit, notes private).
  final int minuteInterval;

  /// The picked moment.
  final DateTime value;

  /// Called with the new moment when the user picks one; null disables
  /// the picker.
  final ValueChanged<DateTime>? onChanged;

  /// What the picker picks.
  final GlassDatePickerMode mode;

  /// The earliest moment that can be picked; null for no limit. The
  /// calendar disables earlier days and the time wheels honor the time
  /// on the boundary day. Later than [maximumDate], both are ignored, as
  /// UIKit ignores them.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit. The time
  /// wheels honor its time on the boundary day.
  final DateTime? maximumDate;

  /// Whether times use 24 hours; null follows the platform's
  /// [MediaQueryData.alwaysUse24HourFormat] (the device's 24-Hour Time
  /// setting on iOS), as UIKit follows the locale's.
  final bool? use24HourFormat;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to tint as today; null for the current day.
  final DateTime? today;

  /// The label screen readers announce before the value.
  final String? semanticLabel;

  /// The texts and formats of the picker; the default keeps the
  /// measured en_US labels.
  final GlassDatePickerLocalizations localizations;

  @override
  State<GlassDatePicker> createState() => _GlassDatePickerState();
}

enum _Part { date, time }

class _GlassDatePickerState extends State<GlassDatePicker> {
  _Part? _open;
  DatePickerMotion? _overlay;
  final Map<_Part, GlobalKey> _labels = {
    _Part.date: GlobalKey(debugLabel: 'date'),
    _Part.time: GlobalKey(debugLabel: 'time'),
  };

  Rect? _labelRect(_Part part) {
    final box = _labels[part]!.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _switched(_Part part) {
    if (mounted) setState(() => _open = part);
  }

  bool get _enabled => widget.onChanged != null;

  bool get _twentyFour =>
      widget.use24HourFormat ??
      MediaQuery.maybeAlwaysUse24HourFormatOf(context) ??
      false;

  Future<void> _show(_Part part, BuildContext anchor) async {
    if (!_enabled || _open != null) return;
    final box = anchor.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = part);
    final reopening = _overlay?.presence == PresenceStatus.leaving;
    await showPresentation<void>(
      context,
      PresentationRoute(
        presentation: Presentation<void, DatePickerMotion>(
          motion: (_) => _overlay = DatePickerMotion(reopening: reopening),
          builder: (context, motion) => _OverlayView(
            picker: this,
            motion: motion,
            part: part,
            label: rect,
          ),
        ),
      ),
    );
    if (mounted) setState(() => _open = null);
  }

  void _changed(DateTime value) => widget.onChanged?.call(value);

  @override
  void didUpdateWidget(GlassDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _routeView?._reconcile();
    });
  }

  _OverlayViewState? _routeView;

  @override
  Widget build(BuildContext context) {
    final value = _floorToMinuteInterval(
      widget.value,
      widget.minuteInterval,
    );
    final date =
        widget.localizations.dateFormatter?.call(value) ?? _defaultDate(value);
    final time =
        widget.localizations.timeFormatter?.call(value) ??
        _defaultTime(value, twentyFour: _twentyFour);
    final parts = switch (widget.mode) {
      GlassDatePickerMode.date => [(_Part.date, date)],
      GlassDatePickerMode.time => [(_Part.time, time)],
      GlassDatePickerMode.dateAndTime => [
        (_Part.date, date),
        (_Part.time, time),
      ],
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: DatePickerTuning.labelGap),
          _CompactLabel(
            key: _labels[parts[i].$1],
            text: parts[i].$2,
            height: parts[i].$1 == _Part.date
                ? DatePickerTuning.dateLabelHeight
                : DatePickerTuning.timeLabelHeight,
            open: _open == parts[i].$1,
            enabled: _enabled,
            style: widget.style,
            semanticLabel: widget.semanticLabel,
            onOpen: (BuildContext anchor) => _show(parts[i].$1, anchor),
          ),
        ],
      ],
    );
  }
}

class _CompactLabel extends StatefulWidget {
  const _CompactLabel({
    required this.text,
    required this.height,
    required this.open,
    required this.enabled,
    required this.style,
    required this.semanticLabel,
    required this.onOpen,
    super.key,
  });

  final String text;
  final double height;
  final bool open;
  final bool enabled;
  final GlassDatePickerStyle? style;
  final String? semanticLabel;
  final void Function(BuildContext anchor) onOpen;

  @override
  State<_CompactLabel> createState() => _CompactLabelState();
}

class _CompactLabelState extends State<_CompactLabel> {
  final _motion = DatePickerLabelMotion();
  late final _highlight = _motion.select((m) => m.highlight);
  bool _focused = false;
  int? _pointer;

  void _down(PointerDownEvent event) {
    if (!widget.enabled ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    _motion.reducedMotion = GlassTraits.of(context).reduceMotion;
    _motion.press(MotionClock.instance.stamp(event.timeStamp));
  }

  @override
  void didUpdateWidget(_CompactLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) {
      _pointer = null;
      _motion.release(MotionClock.instance.now);
    }
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _motion.release(MotionClock.instance.stamp(event.timeStamp));
    final box = context.findRenderObject();
    if (event is PointerUpEvent && box is RenderBox && box.hasSize) {
      final local = box.globalToLocal(event.position);
      if ((Offset.zero & box.size).contains(local)) widget.onOpen(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _Appearance.of(context, widget.style);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
    final label = widget.semanticLabel;
    return MotionScope(
      motion: _motion,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onOpen(context);
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          expanded: widget.open,
          label: label == null ? widget.text : '$label, ${widget.text}',
          onTap: widget.enabled ? () => widget.onOpen(context) : null,
          child: ExcludeSemantics(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: Container(
                constraints: BoxConstraints(minHeight: widget.height),
                padding: const EdgeInsets.symmetric(
                  horizontal: DatePickerTuning.labelPadding,
                ),
                decoration: widget.enabled
                    ? ShapeDecoration(
                        color: style.labelFillColor,
                        shape: StadiumBorder(
                          side: _focused
                              ? BorderSide(color: style.accentColor, width: 2)
                              : BorderSide.none,
                        ),
                      )
                    : null,
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _highlight,
                    builder: (context, highlight, _) {
                      final color = widget.open
                          ? style.accentColor
                          : style.labelColor;
                      final opacity = widget.enabled
                          ? highlight.clamp(0.0, 1.0)
                          : 1.0;
                      return Text(
                        widget.text,
                        maxLines: 1,
                        textScaler: scaler,
                        style: _Type.resolve(
                          _Type.datePickerCompact.copyWith(
                            height: 20.33 / 17,
                            color: opacity >= 1
                                ? color
                                : color.withValues(alpha: color.a * opacity),
                          ),
                          context: context,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The largest text scale the overlay's fixed-size calendar follows.
const double _overlayMaxTextScale = 1.2;

class _OverlayView extends StatefulWidget {
  const _OverlayView({
    required this.picker,
    required this.motion,
    required this.part,
    required this.label,
  });

  final _GlassDatePickerState picker;
  final DatePickerMotion motion;
  final _Part part;
  final Rect label;

  @override
  State<_OverlayView> createState() => _OverlayViewState();
}

extension on GlassDatePicker {
  bool get _boundsHold {
    final first = minimumDate;
    final last = maximumDate;
    return first == null || last == null || !last.isBefore(first);
  }

  DateTime? get _minimum => _boundsHold ? minimumDate : null;

  DateTime? get _maximum => _boundsHold ? maximumDate : null;
}

class _OverlayViewState extends State<_OverlayView> {
  late DateTime _value = _bounded(_picker.value);
  late DateTime _month = DateTime(_value.year, _value.month);
  DateTime? _previousMonth;
  int? _outside;
  late _Part _part = widget.part;
  late Rect _label = widget.label;
  _Part? _fromPart;
  Rect? _fromLabel;

  // The tree rebuilds only when one of these flips; every other frame
  // reads the motion through render objects.
  late final _leaving = _motion.select((m) => !m.isOpen);
  late final _switching = _motion.select((m) => m.switching);
  late final _pageTurning = _motion.select((m) => m.page < 1);
  late final _yearsVisible = _motion.select(
    (m) => m.yearPicker.clamp(0.0, 1.0) > 0,
  );
  late final _swap = _motion.select((m) => m.swap.clamp(0.0, 1.0));
  late final _unswap = _motion.select((m) => 1 - m.swap.clamp(0.0, 1.0));
  late final _opacity = _motion.select((m) => m.opacity);
  late final _glass = _motion.select(
    (m) => GlassFrame(
      shape: const GlassShape.superellipse(DatePickerTuning.cornerRadius),
      opacity: m.opacity,
    ),
  );

  // Safe one frame late: the overlay stays transparent for at least the
  // reopen delay after the lift.
  final ValueNotifier<bool> _contentReady = ValueNotifier(false);

  DatePickerMotion get _motion => widget.motion;

  _GlassDatePickerState get _host => widget.picker;

  GlassDatePicker get _picker => _host.widget;

  double get _now => MotionClock.instance.now;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.reducedMotion = GlassTraits.of(context).reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    _host._routeView = this;
    _motion.onTurn = _turned;
    _leaving.addListener(_rebuild);
    _switching.addListener(_switched);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentReady.value = true;
    });
  }

  @override
  void dispose() {
    _leaving.removeListener(_rebuild);
    _switching.removeListener(_switched);
    _contentReady.dispose();
    if (_host._routeView == this) _host._routeView = null;
    if (_motion.onTurn == _turned) _motion.onTurn = null;
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _switched() {
    if (!_switching.value && _fromPart != null) {
      setState(() => _fromPart = null);
    }
  }

  _Part? _otherLabelAt(Offset position) {
    for (final part in _Part.values) {
      if (part == _part) continue;
      final rect = _host._labelRect(part);
      if (rect != null && rect.contains(position)) return part;
    }
    return null;
  }

  void _switchTo(_Part part) {
    final label = _host._labelRect(part);
    if (label == null || !_motion.isOpen) return;
    _motion.switchPicker(_now, back: part == _fromPart);
    setState(() {
      _fromPart = _part;
      _fromLabel = _label;
      _part = part;
      _label = label;
    });
    _host._switched(part);
  }

  void _close(DismissTrigger trigger) {
    if (!_motion.isOpen) return;
    PresentationHandle.of(context).dismiss(trigger);
  }

  DateTime _bounded(DateTime value) =>
      _clampDate(value, _picker._minimum, _picker._maximum);

  void _pick(DateTime value) {
    if (!_host.mounted || !_host._enabled) return;
    final next = _bounded(value);
    setState(() => _value = next);
    _host._changed(next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
  }

  void _reconcile() {
    if (!mounted || !_host.mounted) return;
    if (!_host._enabled) {
      _close(DismissTrigger.programmatic);
      return;
    }
    final value = _bounded(_picker.value);
    final shown = _shown;
    final twentyFour = _host._twentyFour;
    if (_value == value &&
        twentyFour == _shownTwentyFour &&
        shown != null &&
        _showsAlike(shown, _picker)) {
      return;
    }
    setState(() {
      if (_value != value) {
        _month = DateTime(value.year, value.month);
        _previousMonth = null;
      }
      _value = value;
    });
  }

  GlassDatePicker? _shown;
  bool? _shownTwentyFour;

  static bool _showsAlike(GlassDatePicker a, GlassDatePicker b) =>
      a.mode == b.mode &&
      a.minimumDate == b.minimumDate &&
      a.maximumDate == b.maximumDate &&
      a.firstDayOfWeek == b.firstDayOfWeek &&
      a.today == b.today &&
      a.localizations.localize == b.localizations.localize &&
      a.localizations.numberFormatter == b.localizations.numberFormatter &&
      a.localizations.calendarTitleFormatter ==
          b.localizations.calendarTitleFormatter &&
      a.localizations.daySemanticFormatter ==
          b.localizations.daySemanticFormatter;

  void _turn(int direction) => _motion.turnPage(_now, direction);

  bool _turned(int direction) {
    if (!mounted ||
        !_canTurnMonth(_month, direction, _picker._minimum, _picker._maximum)) {
      return false;
    }
    setState(() {
      _previousMonth = _month;
      _month = DateTime(_month.year, _month.month + direction);
    });
    return true;
  }

  void _toggleYearPicker() {
    if (!_motion.isOpen) return;
    setState(() {});
    _motion.showYearPicker(_now, show: !_motion.showsYearPicker);
  }

  void _pickMonth(int year, int month) {
    final v = _value;
    var next = DateTime(
      year,
      month,
      math.min(v.day, _daysIn(DateTime(year, month))),
      v.hour,
      v.minute,
    );
    final first = _picker._minimum;
    final last = _picker._maximum;
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
    if (next != v) _pick(next);
  }

  Size _sizeFor(_Part part) => part == _Part.time
      ? DatePickerTuning.timeSize
      : DatePickerTuning.calendarSize;

  @override
  Widget build(BuildContext context) {
    _shown = _picker;
    _shownTwentyFour = _host._twentyFour;
    final style = _Appearance.of(context, _picker.style);
    final media = MediaQuery.of(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final origin = _origin(context);
    final padding = EdgeInsets.only(
      top: media.padding.top,
      bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    Widget contentFor(_Part part) => part == _Part.time
        ? _TimeWheels(
            value: _value,
            firstDate: _picker._minimum,
            lastDate: _picker._maximum,
            localize: _picker.localizations.localize,
            numberFormatter: _picker.localizations.numberFormatter,
            minuteInterval: _picker.minuteInterval,
            twentyFour: _host._twentyFour,
            style: style,
            onChanged: _pick,
          )
        : _Calendar(
            value: _value,
            month: _month,
            previousMonth: _previousMonth,
            motion: _motion,
            pageTurning: _pageTurning,
            gridReady: _contentReady,
            yearsVisible: _yearsVisible,
            firstDayOfWeek: _picker.firstDayOfWeek,
            localize: _picker.localizations.localize,
            numberFormatter: _picker.localizations.numberFormatter,
            titleFormatter: _picker.localizations.calendarTitleFormatter,
            dayFormatter: _picker.localizations.daySemanticFormatter,
            firstDate: _picker._minimum,
            lastDate: _picker._maximum,
            today: _picker.today ?? _dateOnly(DateTime.now()),
            style: style,
            onPick: _pick,
            onTurn: _turn,
            onTitle: _toggleYearPicker,
            onPickMonth: _pickMonth,
          );
    final size = _sizeFor(_part);
    final from = _fromPart;
    final fromSize = from == null ? size : _sizeFor(from);
    Widget overlayFor({required bool below}) => Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: MediaQuery(
        data: media.copyWith(
          textScaler: media.textScaler.clamp(
            maxScaleFactor: _overlayMaxTextScale,
          ),
        ),
        child: DefaultTextStyle(
          style: _Type.resolve(
            TextStyle(fontSize: 17, color: style.labelColor),
            context: context,
          ),
          child: _Crossfade(
            alignment: below
                ? AlignmentDirectional.topStart
                : AlignmentDirectional.bottomStart,
            fadeIn: _swap,
            fadeOut: _unswap,
            from: from == null
                ? null
                : ExcludeSemantics(
                    child: SizedBox.fromSize(
                      size: fromSize,
                      child: contentFor(from),
                    ),
                  ),
            to: SizedBox.fromSize(
              key: ValueKey<_Part>(_part),
              size: size,
              child: _part == _Part.time
                  ? ValueListenableBuilder<bool>(
                      valueListenable: _contentReady,
                      child: contentFor(_part),
                      builder: (
                        BuildContext context,
                        bool ready,
                        Widget? child,
                      ) => ready ? child! : const SizedBox.shrink(),
                    )
                  : contentFor(_part),
            ),
          ),
        ),
      ),
    );
    return FocusScope(
      autofocus: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          DatePickerPlacement place(Size size, Rect label) => placeDatePicker(
            size: size,
            label: label.shift(-origin),
            screen: constraints.biggest,
            padding: padding,
            textDirection: direction,
          );
          final target = place(size, _label);
          final fromLabel = _fromLabel;
          final source = from == null || fromLabel == null
              ? null
              : place(fromSize, fromLabel);
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _leaving.value,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (PointerDownEvent e) => _outside = e.pointer,
                    onPointerUp: (PointerUpEvent e) {
                      if (e.pointer == _outside) {
                        final other = _otherLabelAt(e.position);
                        if (other == null) {
                          _close(DismissTrigger.outsideTap);
                        } else {
                          _switchTo(other);
                        }
                      }
                      _outside = null;
                    },
                    onPointerCancel: (PointerCancelEvent e) => _outside = null,
                  ),
                ),
              ),
              _box(
                target: target,
                source: source,
                screen: constraints.biggest,
                child: overlayFor(below: target.below),
              ),
            ],
          );
        },
      ),
    );
  }

  // The overlay's box: placed, scaled, faded and clipped per frame from the
  // motion, around content built once.
  Widget _box({
    required DatePickerPlacement target,
    required DatePickerPlacement? source,
    required Size screen,
    required Widget child,
  }) {
    final below = target.below;
    final frame = _motion.select((m) {
      final q = m.swap;
      final placement = source == null
          ? target
          : DatePickerPlacement(
              rect: Rect.lerp(source.rect, target.rect, q)!,
              anchor: Offset.lerp(source.anchor, target.anchor, q)!,
            );
      return _BoxFrame.of(m, placement, below: below);
    });
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _leaving.value,
        child: MotionDriven(
          template: () {
            final f = frame.value;
            return Transform(
              transform: f.transform,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  f.box.left,
                  f.box.top,
                  screen.width - f.box.right,
                  screen.height - f.box.bottom,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The menu's material: over black the native overlay reads
              // 32 gray on an iPhone 16 Pro film, as the native menu does.
              GlassSurface.live(
                role: GlassRole.panel,
                frame: _glass,
                child: const SizedBox.expand(),
              ),
              GlassClip(
                shape: const GlassShape.superellipse(
                  DatePickerTuning.cornerRadius,
                ),
                child: OverflowBox(
                  alignment: below
                      ? AlignmentDirectional.topStart
                      : AlignmentDirectional.bottomStart,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  // The content keeps its size while the scale, clip and
                  // opacity above it change every frame; its own layer,
                  // below the clip, keeps its raster through a reclip.
                  child: MotionTransition(
                    opacity: _opacity,
                    child: RepaintBoundary(child: child),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero);
    return Offset.zero;
  }
}

/// The overlay's box at one time: where it sits, how it scales about its
/// anchor and how far it shows.
@immutable
class _BoxFrame {
  const _BoxFrame({
    required this.box,
    required this.transform,
    required this.opacity,
  });

  factory _BoxFrame.of(
    DatePickerMotion motion,
    DatePickerPlacement placement, {
    required bool below,
  }) {
    final rect = placement.rect;
    final anchor = placement.anchor;
    final s = motion.scale;
    final h = math.min(rect.height, motion.height(rect.height));
    final box = Rect.fromLTWH(
      rect.left,
      below ? rect.top : rect.bottom - h,
      rect.width,
      math.max(0, h),
    );
    final transform = Matrix4.diagonal3Values(s, s, 1);
    transform.setTranslationRaw(
      anchor.dx - s * anchor.dx,
      anchor.dy - s * anchor.dy,
      0,
    );
    return _BoxFrame(
      box: box,
      transform: transform,
      opacity: motion.opacity,
    );
  }

  /// The box before the scale, in the overlay's coordinates.
  final Rect box;

  /// The scale about the anchor, in the overlay's coordinates.
  final Matrix4 transform;

  /// The platter's and the content's opacity.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is _BoxFrame &&
      other.box == box &&
      other.transform == transform &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(box, transform, opacity);
}

class _Crossfade extends StatelessWidget {
  const _Crossfade({
    required this.fadeIn,
    required this.fadeOut,
    required this.from,
    required this.to,
    required this.alignment,
  });

  final AlignmentDirectional alignment;
  final ValueListenable<double> fadeIn;
  final ValueListenable<double> fadeOut;
  final Widget? from;
  final Widget to;

  @override
  Widget build(BuildContext context) {
    final old = from;
    if (old == null) return to;
    return Stack(
      alignment: alignment,
      clipBehavior: Clip.none,
      children: [
        IgnorePointer(
          child: MotionTransition(opacity: fadeOut, child: old),
        ),
        MotionTransition(opacity: fadeIn, child: to),
      ],
    );
  }
}

/// The layout of the calendar, read from UIKit's views at 320 points wide.
abstract final class _CalendarMetrics {
  static const double top = 16;
  static const double headerHeight = 37.67;
  static const double titleInset = 20.33;
  static const double titleButtonStart = 16;
  static const double titleButtonEnd = 4;
  static const double titleChevronGap = 7.67;
  static const Size titleChevron = Size(6.33, 11.67);
  static const double titleChevronStroke = 2.1;
  static const Size chevron = Size(10, 17.33);
  static const double chevronStroke = 2.6;
  static const double chevronShiftForward = 1;
  static const double chevronShiftBack = -1.33;
  static const double weekdayTop = 16;
  static const double weekdayHeight = 15.67;
  static const double gridInset = 10.33;
  static const double cell = 42.67;
  static const double row = 45.67;
  static const double gridTop = 1;
  static const double chevronButton = 43.33;
  static const double chevronEnd = 2;
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.value,
    required this.month,
    required this.previousMonth,
    required this.motion,
    required this.pageTurning,
    required this.gridReady,
    required this.yearsVisible,
    required this.firstDayOfWeek,
    required this.firstDate,
    required this.lastDate,
    required this.today,
    required this.style,
    required this.onPick,
    required this.onTurn,
    required this.onTitle,
    required this.onPickMonth,
    required this.localize,
    required this.numberFormatter,
    required this.titleFormatter,
    required this.dayFormatter,
  });

  final DateTime value;
  final DateTime month;
  final DateTime? previousMonth;
  final DatePickerMotion motion;

  /// Whether a page turn runs: the old month is on screen.
  final ValueListenable<bool> pageTurning;

  /// Whether the day grid has mounted.
  final ValueListenable<bool> gridReady;

  /// Whether the month and year wheels show at all.
  final ValueListenable<bool> yearsVisible;

  final int firstDayOfWeek;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime today;
  final _Appearance style;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<int> onTurn;
  final VoidCallback onTitle;
  final void Function(int year, int month) onPickMonth;
  final String Function(String)? localize;
  final String Function(int)? numberFormatter;
  final String Function(DateTime)? titleFormatter;
  final String Function(DateTime)? dayFormatter;

  String _text(String value) => localize?.call(value) ?? value;
  String _number(int value) => numberFormatter?.call(value) ?? '$value';

  bool _canTurn(int direction) =>
      _canTurnMonth(month, direction, firstDate, lastDate);

  Widget _fading(Widget child, {required bool out}) => MotionTransition(
    opacity: motion.select((m) {
      final q = m.yearPicker.clamp(0.0, 1.0);
      return out ? 1 - q : q;
    }),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final years = motion.showsYearPicker;
    const grid = 7 * _CalendarMetrics.cell;
    final title = _Type.resolve(
      _Type.datePickerTitle.copyWith(
        height: 1.2,
        color: years ? style.accentColor : style.labelColor,
      ),
      context: context,
    );
    final weekday = _Type.resolve(
      _Type.datePickerWeekday.copyWith(
        height: _CalendarMetrics.weekdayHeight / 13,
        color: style.weekdayColor,
      ),
      context: context,
    );
    final titleText =
        titleFormatter?.call(month) ??
        '${_text(_months[month.month - 1])} ${_number(month.year)}';
    // Built once per calendar build: the frame builders below only move
    // them, so a tick of any overlay motion leaves the days untouched.
    // Both grids share one shape, so a page turn's start and end keep the
    // element (and the recorded layer) of the month that stays.
    final monthGrid = ExcludeSemantics(
      excluding: false,
      child: _month(context, month),
    );
    final previous = previousMonth;
    final previousGrid = previous == null
        ? null
        : ExcludeSemantics(child: _month(context, previous));
    final calendar = Padding(
      padding: const EdgeInsets.only(top: _CalendarMetrics.top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _CalendarMetrics.headerHeight,
            child: Row(
              children: [
                const SizedBox(width: _CalendarMetrics.titleButtonStart),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Semantics(
                          button: true,
                          liveRegion: true,
                          label: years
                              ? _text('Hide year picker')
                              : _text('Show year picker'),
                          value: titleText,
                          onTap: onTitle,
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTitle,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start:
                                    _CalendarMetrics.titleInset -
                                    _CalendarMetrics.titleButtonStart,
                                end: _CalendarMetrics.titleButtonEnd,
                              ),
                              child: SizedBox(
                                height: _CalendarMetrics.headerHeight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        titleText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: title,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: _CalendarMetrics.titleChevronGap,
                                    ),
                                    MotionTransition(
                                      rotation: motion.select(
                                        (m) =>
                                            (rtl ? -1 : 1) *
                                            m.yearPickerTurn *
                                            math.pi /
                                            2,
                                      ),
                                      child: CustomPaint(
                                        size: _CalendarMetrics.titleChevron,
                                        painter: _ChevronPainter(
                                          color: style.accentColor,
                                          forward: !rtl,
                                          stroke: _CalendarMetrics
                                              .titleChevronStroke,
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
                ),
                _fading(
                  out: true,
                  IgnorePointer(
                    ignoring: years,
                    child: ExcludeSemantics(
                      excluding: years,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ChevronButton(
                            label: _text('Previous month'),
                            forward: false,
                            color: style.labelColor,
                            onTap: _canTurn(-1) ? () => onTurn(-1) : null,
                          ),
                          _ChevronButton(
                            label: _text('Next month'),
                            forward: true,
                            color: style.labelColor,
                            onTap: _canTurn(1) ? () => onTurn(1) : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _CalendarMetrics.chevronEnd),
              ],
            ),
          ),
          Expanded(
            child: _fading(
              out: true,
              IgnorePointer(
                ignoring: years,
                child: ExcludeSemantics(
                  excluding: years,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: _CalendarMetrics.weekdayTop),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _CalendarMetrics.gridInset,
                        ),
                        child: SizedBox(
                          height: _CalendarMetrics.weekdayHeight,
                          child: ExcludeSemantics(
                            child: Row(
                              children: [
                                for (var i = 0; i < 7; i++)
                                  SizedBox(
                                    width: _CalendarMetrics.cell,
                                    child: Text(
                                      _text(
                                        _weekdays[(firstDayOfWeek + i) % 7],
                                      ),
                                      textAlign: TextAlign.center,
                                      style: weekday,
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
                            _CalendarMetrics.gridInset,
                            _CalendarMetrics.gridTop,
                            _CalendarMetrics.gridInset,
                            0,
                          ),
                          child: ClipRect(
                            // A page turn repaints the moving grids' offsets
                            // only, not the weekday row above; mounting or
                            // swapping a grid lays out only this area.
                            child: _ScopedRepaintBoundary(
                              builder:
                                  (
                                    BuildContext context,
                                    BoxConstraints _,
                                  ) => ListenableBuilder(
                                    listenable: Listenable.merge([
                                      pageTurning,
                                      gridReady,
                                    ]),
                                    builder: (BuildContext context, Widget? _) {
                                      if (!gridReady.value) {
                                        return const SizedBox.shrink();
                                      }
                                      final turning = pageTurning.value;
                                      double dir(DatePickerMotion m) =>
                                          m.pageDirection * (rtl ? -1.0 : 1.0);
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          if (previousGrid != null && turning)
                                            Positioned(
                                              key: ValueKey<DateTime>(
                                                previous!,
                                              ),
                                              left: 0,
                                              top: 0,
                                              width: grid,
                                              child: MotionTransition(
                                                offset: motion.select(
                                                  (m) => Offset(
                                                    -dir(m) * grid * m.page,
                                                    0,
                                                  ),
                                                ),
                                                child: previousGrid,
                                              ),
                                            ),
                                          Positioned(
                                            key: ValueKey<DateTime>(month),
                                            left: 0,
                                            top: 0,
                                            width: grid,
                                            child: MotionTransition(
                                              offset: motion.select((m) {
                                                final q = m.page;
                                                return Offset(
                                                  previousGrid != null && q < 1
                                                      ? dir(m) * grid * (1 - q)
                                                      : 0,
                                                  0,
                                                );
                                              }),
                                              child: monthGrid,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
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
        ],
      ),
    );
    final wheels = _MonthYearWheels(
      month: month,
      firstDate: firstDate,
      lastDate: lastDate,
      style: style,
      onChanged: onPickMonth,
      localize: localize,
      numberFormatter: numberFormatter,
    );
    return Stack(
      children: [
        Positioned.fill(child: calendar),
        PositionedDirectional(
          start: _MonthYearMetrics.start,
          top: _MonthYearMetrics.top,
          width: _MonthYearMetrics.width,
          height: _MonthYearMetrics.height,
          child: ValueListenableBuilder<bool>(
            valueListenable: yearsVisible,
            child: wheels,
            builder: (BuildContext context, bool visible, Widget? child) {
              if (!years && !visible) return const SizedBox.shrink();
              return IgnorePointer(
                ignoring: !years,
                child: ExcludeSemantics(
                  excluding: !years,
                  child: MotionTransition(
                    opacity: motion.select(
                      (m) => m.yearPicker.clamp(0.0, 1.0),
                    ),
                    child: child,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _month(BuildContext context, DateTime month) {
    final first = DateTime(month.year, month.month);
    final lead = (first.weekday - firstDayOfWeek) % 7;
    final days = _daysIn(month);
    final weeks = ((lead + days) / 7).ceil();
    final row = weeks > 5
        ? DatePickerTuning.sixWeekRowHeight
        : _CalendarMetrics.row;
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
                    () {
                      final day = w * 7 + d - lead + 1;
                      if (day < 1 || day > days) {
                        return const SizedBox(width: _CalendarMetrics.cell);
                      }
                      final date = DateTime(month.year, month.month, day);
                      return _day(
                        date: date,
                        semanticLabel:
                            dayFormatter?.call(date) ??
                            '${_number(date.day)} '
                                '${_text(_months[date.month - 1])} '
                                '${_number(date.year)}',
                        text: _number(date.day),
                        disc: math.min(_CalendarMetrics.cell, row),
                        selected: _sameDay(date, value),
                        today: _sameDay(date, today),
                        enabled:
                            !(firstDate != null &&
                                date.isBefore(_dateOnly(firstDate!))) &&
                            !(lastDate != null &&
                                date.isAfter(_dateOnly(lastDate!))),
                        style: style,
                        onTap: () => onPick(
                          DateTime(
                            date.year,
                            date.month,
                            date.day,
                            value.hour,
                            value.minute,
                          ),
                        ),
                        context: context,
                      );
                    }(),
                ],
              ),
            ),
        ],
      ),
    );
  }
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

// A day is a handful of elements: the open frame builds every day of the
// month at once, and on a slow phone each element of it counts.
Widget _day({
  required DateTime date,
  required String semanticLabel,
  required String text,
  required double disc,
  required bool selected,
  required bool today,
  required bool enabled,
  required _Appearance style,
  required VoidCallback onTap,
  BuildContext? context,
}) {
  final color = switch ((selected, today)) {
    (true, true) => _Appearance.selectedDayColor,
    (true, false) => style.selectedDayTextColor,
    (false, true) => style.accentColor,
    (false, false) => style.labelColor,
  };
  final fill = switch ((selected, today)) {
    (true, true) => style.accentColor,
    (true, false) => style.labelColor,
    (false, true) => style.todayFillColor,
    (false, false) => null,
  };
  final cell = _DayCell(
    width: _CalendarMetrics.cell,
    disc: disc,
    fill: fill,
    onTap: enabled ? onTap : null,
    child: Text(
      text,
      textScaler: TextScaler.noScaling,
      style: _Type.resolve(
        (selected ? _Type.datePickerDaySelected : _Type.datePickerDay).copyWith(
          height: 1.2,
          color: color,
        ),
        context: context,
      ),
    ),
  );
  return Semantics(
    button: true,
    selected: selected,
    enabled: enabled,
    label: semanticLabel,
    onTap: enabled ? onTap : null,
    excludeSemantics: true,
    child: enabled
        ? cell
        : Opacity(opacity: _Appearance.unavailableDayOpacity, child: cell),
  );
}

/// One day of the grid: [width] wide and as tall as its row, a [disc]
/// across filled with [fill] at its center and the number centered on
/// the disc, taking every touch in its box. It lays out and paints as the
/// Center, Container and Align it stands for, offset for offset, and
/// recognizes a tap as a GestureDetector would.
class _DayCell extends SingleChildRenderObjectWidget {
  const _DayCell({
    required this.width,
    required this.disc,
    required this.fill,
    required this.onTap,
    required super.child,
  });

  final double width;
  final double disc;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  _RenderDayCell createRenderObject(BuildContext context) => _RenderDayCell(
    width: width,
    disc: disc,
    fill: fill,
    onTap: onTap,
    gestureSettings: MediaQuery.maybeGestureSettingsOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderDayCell renderObject) {
    if (renderObject.width != width || renderObject.disc != disc) {
      renderObject.width = width;
      renderObject.disc = disc;
      renderObject.markNeedsLayout();
    }
    if (renderObject.fill != fill) {
      renderObject.fill = fill;
      renderObject.markNeedsPaint();
    }
    renderObject.onTap = onTap;
    renderObject.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('disc', disc));
    properties.add(ColorProperty('fill', fill, defaultValue: null));
  }
}

class _RenderDayCell extends RenderProxyBox {
  _RenderDayCell({
    required this.width,
    required this.disc,
    required this.fill,
    required VoidCallback? onTap,
    required DeviceGestureSettings? gestureSettings,
  }) {
    _tap.onTap = onTap;
    _tap.gestureSettings = gestureSettings;
  }

  final TapGestureRecognizer _tap = TapGestureRecognizer();

  double width;
  double disc;

  Color? fill;

  VoidCallback? get onTap => _tap.onTap;
  set onTap(VoidCallback? value) => _tap.onTap = value;

  DeviceGestureSettings? get gestureSettings => _tap.gestureSettings;
  set gestureSettings(DeviceGestureSettings? value) =>
      _tap.gestureSettings = value;

  Offset _discOffset = Offset.zero;
  Offset _childOffset = Offset.zero;

  @override
  void performLayout() {
    size = BoxConstraints.tightFor(
      width: width,
    ).enforce(constraints).constrain(Size.infinite);
    final discBox = BoxConstraints.tight(
      Size(disc, disc),
    ).enforce(BoxConstraints.loose(size));
    final discSize = discBox.constrain(Size.infinite);
    _discSize = discSize;
    _discOffset = Alignment.center.alongOffset(size - discSize as Offset);
    final child = this.child;
    if (child == null) return;
    child.layout(discBox.loosen(), parentUsesSize: true);
    _childOffset = Alignment.center.alongOffset(
      discSize - child.size as Offset,
    );
  }

  Size _discSize = Size.zero;

  @override
  Size computeDryLayout(BoxConstraints constraints) => BoxConstraints.tightFor(
    width: width,
  ).enforce(constraints).constrain(Size.infinite);

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + _discOffset;
    final fill = this.fill;
    if (fill != null) {
      final rect = origin & _discSize;
      final paint = Paint();
      paint.color = fill;
      context.canvas.drawCircle(rect.center, rect.shortestSide / 2.0, paint);
    }
    final child = this.child;
    if (child != null) context.paintChild(child, origin + _childOffset);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_discOffset.dx, _discOffset.dy, 0, 1);
    transform.translateByDouble(_childOffset.dx, _childOffset.dy, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _discOffset + _childOffset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent && _tap.onTap != null) _tap.addPointer(event);
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }
}

class _ChevronButton extends StatelessWidget {
  const _ChevronButton({
    required this.label,
    required this.forward,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool forward;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _CalendarMetrics.chevronButton,
          height: _CalendarMetrics.headerHeight,
          child: Center(
            child: Transform.translate(
              offset: Offset(
                forward != rtl
                    ? _CalendarMetrics.chevronShiftForward
                    : _CalendarMetrics.chevronShiftBack,
                0,
              ),
              child: Opacity(
                opacity: onTap == null ? _Appearance.unavailableDayOpacity : 1,
                child: CustomPaint(
                  size: _CalendarMetrics.chevron,
                  painter: _ChevronPainter(
                    color: color,
                    forward: forward != rtl,
                    stroke: _CalendarMetrics.chevronStroke,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({
    required this.color,
    required this.forward,
    required this.stroke,
  });

  final Color color;
  final bool forward;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final inset = stroke / 2;
    final path = Path();
    if (forward) {
      path.moveTo(inset, inset);
      path.lineTo(size.width - inset, size.height / 2);
      path.lineTo(inset, size.height - inset);
    } else {
      path.moveTo(size.width - inset, inset);
      path.lineTo(inset, size.height / 2);
      path.lineTo(size.width - inset, size.height - inset);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.forward != forward ||
      oldDelegate.stroke != stroke;
}

const Duration _wheelStep = Duration(milliseconds: 200);
const Curve _wheelStepCurve = Cubic(0.25, 0.1, 0.25, 1);

/// One of UIKit's picker wheels: a column of rows on a cylinder behind a
/// band that shows the selected row larger and in full, every other row
/// smaller, at [_Appearance.wheelFadedOpacity] and darkened toward the
/// cylinder's edges.
Widget _wheel({
  required _WheelGeometry geometry,
  required _Appearance style,
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) text,
  required int selected,
  required ValueChanged<int> onSelected,
  required String label,
  BuildContext? context,
  bool looping = true,
  AlignmentGeometry alignment = Alignment.center,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  _WheelViews? views,
  Object? viewKey,
}) {
  Widget view() => _wheelView(
    geometry: geometry,
    style: style,
    controller: controller,
    count: count,
    text: text,
    onSelected: onSelected,
    looping: looping,
    alignment: alignment,
    padding: padding,
    context: context,
  );
  final up = looping || selected + 1 < count;
  final down = looping || selected > 0;
  return Semantics(
    label: label,
    value: text(selected),
    increasedValue: up ? text((selected + 1) % count) : null,
    decreasedValue: down ? text((selected - 1) % count) : null,
    onIncrease: up
        ? () => controller.animateToItem(
            controller.selectedItem + 1,
            duration: _wheelStep,
            curve: _wheelStepCurve,
          )
        : null,
    onDecrease: down
        ? () => controller.animateToItem(
            controller.selectedItem - 1,
            duration: _wheelStep,
            curve: _wheelStepCurve,
          )
        : null,
    child: ExcludeSemantics(
      child: views == null
          ? view()
          : views.keep(controller, (
              viewKey,
              count,
              looping,
              style,
              context == null
                  ? null
                  : resolveGlassText(const TextStyle(), context).fontFamily,
            ), view),
    ),
  );
}

/// The wheel views a picker built before, handed back while what they
/// draw is unchanged: a value the parent sets back while a wheel turns
/// rebuilds no row.
class _WheelViews {
  final Map<Object, (Object?, Widget)> _kept = {};

  Widget keep(Object slot, Object? key, Widget Function() build) {
    final kept = _kept[slot];
    if (kept != null && kept.$1 == key) return kept.$2;
    final view = build();
    _kept[slot] = (key, view);
    return view;
  }
}

Widget _wheelView({
  required _WheelGeometry geometry,
  required _Appearance style,
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) text,
  required ValueChanged<int> onSelected,
  required bool looping,
  required AlignmentGeometry alignment,
  required EdgeInsetsGeometry padding,
  BuildContext? context,
}) {
  final row = _Type.resolve(
    TextStyle(fontSize: _WheelGeometry.fontSize, color: style.labelColor),
    context: context,
  );
  return ListWheelScrollView.useDelegate(
    controller: controller,
    itemExtent: geometry.row,
    diameterRatio: geometry.diameterRatio,
    perspective: _WheelGeometry.perspective,
    squeeze: geometry.squeeze,
    useMagnifier: true,
    magnification: _WheelGeometry.magnification,
    overAndUnderCenterOpacity: _Appearance.wheelFadedOpacity,
    physics: const FixedExtentScrollPhysics(
      parent: BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      ),
    ),
    onSelectedItemChanged: (int index) {
      MotionHaptic.selection.play();
      onSelected(index);
    },
    childDelegate: ListWheelChildBuilderDelegate(
      childCount: looping ? count * _WheelGeometry.loops : count,
      builder: (BuildContext context, int i) => Padding(
        padding: padding,
        child: Align(
          alignment: alignment,
          child: Text(
            text(i % count),
            textScaler: TextScaler.noScaling,
            style: row,
          ),
        ),
      ),
    ),
  );
}

/// The band behind a picker's selected row: a capsule across the wheels.
Widget _wheelBand(_Appearance style) => DecoratedBox(
  decoration: ShapeDecoration(
    color: style.wheelBandColor,
    shape: const StadiumBorder(),
  ),
);

class _TimeWheels extends StatefulWidget {
  const _TimeWheels({
    required this.value,
    required this.twentyFour,
    required this.firstDate,
    required this.lastDate,
    required this.style,
    required this.onChanged,
    required this.localize,
    required this.numberFormatter,
    required this.minuteInterval,
  });

  final DateTime value;
  final bool twentyFour;
  final int minuteInterval;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String Function(String)? localize;
  final String Function(int)? numberFormatter;
  final _Appearance style;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_TimeWheels> createState() => _TimeWheelsState();
}

class _TimeWheelsState extends State<_TimeWheels> {
  static const int _loops = _WheelGeometry.loops;
  int get _hourCount => widget.twentyFour ? 24 : 12;
  late int _hourIndex = _hourCount * (_loops ~/ 2) + _hour % _hourCount;
  late final FixedExtentScrollController _hours = FixedExtentScrollController(
    initialItem: _hourIndex,
  );
  int get _step => widget.minuteInterval;
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
  void didUpdateWidget(_TimeWheels oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _bounded(widget.value);
    _sync(value, formatChanged: oldWidget.twentyFour != widget.twentyFour);
  }

  DateTime _bounded(DateTime value) =>
      _clampDate(value, widget.firstDate, widget.lastDate);

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
    final next = _bounded(DateTime(v.year, v.month, v.day, _hour, _minute));
    widget.onChanged(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _sync(_bounded(widget.value)));
    });
  }

  String _hourText(int h) {
    final hour = widget.twentyFour
        ? h
        : h == 0
        ? 12
        : h;
    return widget.numberFormatter?.call(hour) ??
        (widget.twentyFour ? _two(hour) : '$hour');
  }

  void _hourChanged(int index) {
    if (_syncing) return;
    if (widget.twentyFour) {
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
    final style = widget.style;
    final twelve = !widget.twentyFour;
    final hour = twelve ? _WheelMetrics.hour12 : _WheelMetrics.hour24;
    final minute = twelve ? _WheelMetrics.minute12 : _WheelMetrics.minute24;
    const geometry = _WheelMetrics.geometry;
    return Padding(
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
            child: _wheelBand(style),
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
                      style: style,
                      controller: _hours,
                      count: _hourCount,
                      text: _hourText,
                      selected: _hour % _hourCount,
                      label: widget.localize?.call('Hour') ?? 'Hour',
                      alignment: twelve
                          ? Alignment.centerRight
                          : Alignment.center,
                      padding: EdgeInsets.only(
                        right: twelve ? _WheelMetrics.hour12End : 0,
                      ),
                      onSelected: _hourChanged,
                      views: _views,
                      viewKey: (widget.twentyFour, widget.numberFormatter),
                      context: context,
                    ),
                  ),
                  _column(
                    minute,
                    _wheel(
                      geometry: geometry,
                      style: style,
                      controller: _minutes,
                      count: _minuteCount,
                      text: (int i) =>
                          widget.numberFormatter?.call(i * _step) ??
                          _two(i * _step),
                      selected: _minute ~/ _step,
                      label: widget.localize?.call('Minute') ?? 'Minute',
                      onSelected: _minuteChanged,
                      views: _views,
                      viewKey: (_step, widget.numberFormatter),
                      context: context,
                    ),
                  ),
                  if (twelve)
                    _column(
                      _WheelMetrics.meridiem,
                      _wheel(
                        geometry: geometry,
                        style: style,
                        controller: _meridiem,
                        count: 2,
                        looping: false,
                        text: (int i) =>
                            widget.localize?.call(i == 0 ? 'AM' : 'PM') ??
                            (i == 0 ? 'AM' : 'PM'),
                        selected: _pm ? 1 : 0,
                        label: widget.localize?.call('AM/PM') ?? 'AM/PM',
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(
                          left: _WheelMetrics.meridiemStart,
                        ),
                        onSelected: _meridiemChanged,
                        views: _views,
                        viewKey: widget.localize,
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

/// The calendar's month and year wheels, shown in place of the day grid
/// after a tap on the month title.
///
/// The month wheel loops; the year wheel runs from the first allowed year
/// to the last. A wheel coming to rest on a new row calls [onChanged] with
/// the year and month, as UIKit sends its value change when the wheel
/// settles.
class _MonthYearWheels extends StatefulWidget {
  const _MonthYearWheels({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.style,
    required this.onChanged,
    required this.localize,
    required this.numberFormatter,
  });

  final DateTime month;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String Function(String)? localize;
  final String Function(int)? numberFormatter;
  final _Appearance style;
  final void Function(int year, int month) onChanged;

  @override
  State<_MonthYearWheels> createState() => _MonthYearWheelsState();
}

class _MonthYearWheelsState extends State<_MonthYearWheels> {
  static const int _loops = _WheelGeometry.loops;
  int get _firstYear => widget.firstDate?.year ?? 1;
  int get _lastYear => math.max(_firstYear, widget.lastDate?.year ?? 9999);
  late int _month = widget.month.month;
  late int _year = widget.month.year.clamp(_firstYear, _lastYear);
  late final FixedExtentScrollController _monthWheel =
      FixedExtentScrollController(initialItem: 12 * (_loops ~/ 2) + _month - 1);
  late final FixedExtentScrollController _yearWheel =
      FixedExtentScrollController(initialItem: _year - _firstYear);
  late (int, int) _emitted;

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

  bool _syncing = false;

  @override
  void didUpdateWidget(_MonthYearWheels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.month != oldWidget.month ||
        widget.firstDate != oldWidget.firstDate ||
        widget.lastDate != oldWidget.lastDate) {
      _sync();
    }
  }

  void _sync() {
    _syncing = true;
    _month = widget.month.month;
    _year = widget.month.year.clamp(_firstYear, _lastYear);
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
      widget.onChanged(_year, _month);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_sync);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
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
            child: _wheelBand(style),
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
                      style: style,
                      controller: _monthWheel,
                      count: 12,
                      text: (int i) =>
                          widget.localize?.call(_months[i]) ?? _months[i],
                      selected: _month - 1,
                      label: widget.localize?.call('Month') ?? 'Month',
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
                      style: style,
                      controller: _yearWheel,
                      count: _lastYear - _firstYear + 1,
                      looping: false,
                      text: (int i) =>
                          widget.numberFormatter?.call(_firstYear + i) ??
                          '${_firstYear + i}',
                      selected: _year - _firstYear,
                      label: widget.localize?.call('Year') ?? 'Year',
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

/// A wheel's box across the platter, from its leading edge.
typedef _WheelColumn = ({double left, double width});

/// The cylinder and the edge darkening of one of UIKit's picker wheels.
@immutable
class _WheelGeometry {
  const _WheelGeometry({
    required this.row,
    required this.diameterRatio,
    required this.squeeze,
    required this.fade,
  });

  /// The distance between two rows along the cylinder.
  final double row;

  /// The cylinder's diameter over the wheel's height.
  final double diameterRatio;

  /// The squeeze that turns [row] into the angle between two rows on the
  /// cylinder.
  final double squeeze;

  /// How much of the rows outside the band shows, by distance from the
  /// band's center: (distance, alpha) pairs, linear between them, on top
  /// of the wheels' faded opacity.
  final List<(double, double)> fade;

  static const int loops = 100;
  static const double perspective = 0.0001;
  static const double fontSize = 21;
  static const double magnification = 23.5 / 21;

  double _fadeAt(double y) {
    final d = y.abs();
    if (d <= fade.first.$1) return 1;
    for (var i = 1; i < fade.length; i++) {
      final (x1, a1) = fade[i];
      if (d <= x1) {
        final (x0, a0) = fade[i - 1];
        return a0 + (a1 - a0) * (d - x0) / (x1 - x0);
      }
    }
    return fade.last.$2;
  }

  static final Map<_WheelGeometry, (Rect, Shader)> _shades = {};

  /// The mask that darkens the rows toward the cylinder's edges, over the
  /// wheels' box: opaque inside the band.
  Shader shade(Rect rect) {
    final cached = _shades[this];
    if (cached != null && cached.$1 == rect) return cached.$2;
    final shader = _shadeFor(rect);
    _shades[this] = (rect, shader);
    return shader;
  }

  Shader _shadeFor(Rect rect) {
    final half = rect.height / 2;
    final steps = half.ceil();
    final stops = <double>[];
    final colors = <Color>[];
    for (var i = 0; i <= steps; i++) {
      final f = i / steps;
      stops.add(f);
      colors.add(Color.fromRGBO(0, 0, 0, _fadeAt((f * 2 - 1) * half)));
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(rect);
  }
}

/// The layout of the time wheels, read from UIKit's views on an iPhone 16
/// Pro (232 x 204 platter): the column view 218 x 172 inside, the band 200
/// x 32 centered, the hour and minute labels centered 73.5 and 148.5 points
/// from the platter's leading edge, the rows on a cylinder of radius 73.5
/// whose neighbours sit 31.3, 56.7 and 71.9 points from the center.
abstract final class _WheelMetrics {
  static const double inset = 7;
  static const double top = 16;
  static const double row = 32.4;
  static const double band = 32;
  static const double bandInset = 9;
  static const double column = 72;

  /// The 24-hour hour wheel, labels centered 73.5 points in.
  static const _WheelColumn hour24 = (left: 73.5 - column / 2, width: column);

  /// The 24-hour minute wheel, labels centered 148.5 points in.
  static const _WheelColumn minute24 = (
    left: 148.5 - column / 2,
    width: column,
  );

  /// The 12-hour hour wheel: its numbers end 51.33 points in (55 at the
  /// band's size), so one and two digits share their trailing edge; the
  /// box reaches past them so the band's magnified numbers are not cut.
  static const _WheelColumn hour12 = (left: 0, width: 60);

  /// The space after the 12-hour hour numbers in [hour12].
  static const double hour12End = 60 - 51.33;

  /// The 12-hour minute wheel, labels centered 110.67 points in.
  static const _WheelColumn minute12 = (left: 110.67 - 30, width: 60);

  /// The AM/PM wheel: its labels start 158 points in (156 at the band's
  /// size), [meridiemStart] into a box wide enough for the band's
  /// magnified labels.
  static const _WheelColumn meridiem = (left: 150, width: 56);

  /// The space before the AM/PM labels in [meridiem].
  static const double meridiemStart = 158 - 150;

  /// The cylinder: 172 points of wheel, radius 73.5, rows [row] apart.
  ///
  /// The fade is read from lossless screenshots of the wheels on an iPhone
  /// 16 Pro (dark, 07:41): the contrast of each pixel row of the digits
  /// against the platter, native over ours, times the mask that drew ours;
  /// the rows then show 0.33, 0.22 and 0.05 of the band's contrast at 31,
  /// 57 and 72 points out.
  static const geometry = _WheelGeometry(
    row: row,
    diameterRatio: 2 * 73.5 / 172,
    squeeze: row * math.pi / (172 * 0.4405),
    fade: [
      (16, 1),
      (22, 0.86),
      (26, 0.855),
      (30, 0.83),
      (34, 0.815),
      (38, 0.81),
      (52, 0.62),
      (55, 0.55),
      (58, 0.455),
      (61, 0.39),
      (70, 0.15),
      (72, 0.1),
      (86, 0),
    ],
  );
}

/// The layout of the calendar's month and year wheels, read from UIKit's
/// views on an iPhone 16 Pro (`_UICalendarMonthYearSelector` in the 320 x
/// 332 calendar, fixture ios27-device/date_picker/month-year.json): the
/// picker 288 x 216 at 16 x 76.84 in the platter, the band 288 x 34 across
/// its middle, the month names left-aligned at 54 points from the
/// platter's leading edge in the band (57.95 outside it), the years
/// centered 230 points in.
abstract final class _MonthYearMetrics {
  static const double start = 16;
  static const double top = 76.84;
  static const double width = 288;
  static const double height = 216;
  static const double band = 34;

  /// The center of the month wheel's box, from the wheels' leading edge:
  /// the wheel magnifies its band about its box's center, and the band's
  /// month names start at 38 points while the others start at 41.95, so
  /// the center sits where 1 + 2.5 / 21 of that offset lands: 75.13.
  static const double _monthCenter = 75.13;

  /// The month wheel's box, wide enough for the band's "September".
  static const _WheelColumn monthColumn = (left: _monthCenter - 76, width: 152);

  /// The space before the month names in [monthColumn].
  static const double monthStart = 41.95 - (_monthCenter - 76);

  /// The year wheel's box, centered on the years (213.9 points in).
  static const _WheelColumn yearColumn = (left: 213.9 - 40, width: 80);

  /// The cylinder: radius 87.7 and rows 31.87 apart, fitted to the rows'
  /// centers 31.3, 58.3, 77.6 and 87.1 points from the band's (0.14 points
  /// rms).
  ///
  /// The fade is read from lossless screenshots on an iPhone 16 Pro (light
  /// and dark agree within 0.01): the darkest pixel of each row against
  /// the platter over the band's, 0.36, 0.324, 0.19 and 0.092 at those
  /// distances, over the wheels' faded opacity of 0.4.
  static const geometry = _WheelGeometry(
    row: 31.87,
    diameterRatio: 2 * 87.7 / height,
    squeeze: math.pi * 87.7 / height,
    fade: [
      (17, 1),
      (31.3, 0.9),
      (58.3, 0.81),
      (77.6, 0.475),
      (87.1, 0.23),
      (96, 0),
    ],
  );
}

/// The text styles of the date picker (UIKit's fonts for it).
abstract final class _Type {
  static const datePickerTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  static const datePickerWeekday = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
  static const datePickerDay = TextStyle(fontSize: 20);
  static const datePickerDaySelected = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );
  static const datePickerCompact = TextStyle(fontSize: 17);

  static TextStyle resolve(TextStyle style, {BuildContext? context}) =>
      context == null ? style : resolveGlassText(style, context);
}
