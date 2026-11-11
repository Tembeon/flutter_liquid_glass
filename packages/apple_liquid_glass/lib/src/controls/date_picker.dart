import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/widgets.dart';

/// The look of a [GlassDatePicker], a [GlassTimePicker] and of the compact
/// picker's labels and wheels; a null field leaves it to the theme's style,
/// then the default, which follows the brightness and Increase Contrast.
@immutable
class GlassDatePickerStyle extends GlassStyle<GlassDatePickerStyle> {
  /// Creates a style.
  const GlassDatePickerStyle({
    this.accentColor,
    this.labelColor,
    this.labelFillColor,
    this.weekdayColor,
    this.todayFillColor,
    this.selectedDayTextColor,
    this.wheelBandColor,
    this.focusColor,
    this.hoverColor,
    this.titleTextStyle,
    this.weekdayTextStyle,
    this.dayTextStyle,
    this.selectedDayTextStyle,
    this.labelTextStyle,
    this.wheelTextStyle,
  });

  /// [style] over the theme's style over the measured defaults at
  /// [context], with every color but [focusColor] and [hoverColor] and
  /// every text style set.
  ///
  /// The defaults follow the ambient brightness and Increase Contrast; an
  /// accent without a [todayFillColor] of its own lends the today fill its
  /// color at the default's opacity. Dynamic colors resolve at [context],
  /// and the text styles take the theme's font and the typography of
  /// [resolveGlassText].
  factory GlassDatePickerStyle.resolve(
    BuildContext context,
    GlassDatePickerStyle? style,
  ) {
    final traits = GlassTraits.of(context);
    final night = traits.brightness == Brightness.dark;
    final table = traits.highContrast
        ? (night ? _darkHighContrast : _lightHighContrast)
        : (night ? _dark : _light);
    final look = (style ?? const GlassDatePickerStyle()).merge(
      maybeOf(context),
    );
    Color? resolved(Color? color) =>
        color == null ? null : GlassDynamicColor.resolve(color, context);
    final accent = resolved(
      look.accentColor ?? GlassTheme.primaryColorOf(context),
    );
    final labelColor = resolved(look.labelColor) ?? table.labelColor!;
    final weekdayColor = resolved(look.weekdayColor) ?? table.weekdayColor!;
    TextStyle text(TextStyle base, TextStyle? over) =>
        resolveGlassText(base.merge(over), context);
    return GlassDatePickerStyle(
      labelFillColor: resolved(look.labelFillColor) ?? table.labelFillColor,
      labelColor: labelColor,
      accentColor: accent ?? table.accentColor,
      weekdayColor: weekdayColor,
      todayFillColor:
          resolved(look.todayFillColor) ??
          accent?.withValues(alpha: table.todayFillColor!.a) ??
          table.todayFillColor,
      selectedDayTextColor:
          resolved(look.selectedDayTextColor) ?? table.selectedDayTextColor,
      wheelBandColor: resolved(look.wheelBandColor) ?? table.wheelBandColor,
      focusColor: resolved(look.focusColor),
      hoverColor: resolved(look.hoverColor),
      titleTextStyle: text(_title, look.titleTextStyle),
      weekdayTextStyle: text(
        _weekday.copyWith(color: weekdayColor),
        look.weekdayTextStyle,
      ),
      dayTextStyle: text(_day, look.dayTextStyle),
      selectedDayTextStyle: text(_daySelected, look.selectedDayTextStyle),
      labelTextStyle: text(_compact, look.labelTextStyle),
      wheelTextStyle: text(
        TextStyle(fontSize: _WheelGeometry.fontSize, color: labelColor),
        look.wheelTextStyle,
      ),
    );
  }

  /// The theme's [GlassDatePickerStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassDatePickerStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassDatePickerStyle>(context);

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

  /// The keyboard focus ring of a part; by default the ring Flutter's
  /// Cupertino controls derive from the accent.
  final Color? focusColor;

  /// What a part adds under the pointer; by default the wash of a glass
  /// body.
  final Color? hoverColor;

  /// The month title, over the default 17 points, semibold.
  final TextStyle? titleTextStyle;

  /// The weekday initials, over the default 13 points, semibold, in
  /// [weekdayColor].
  final TextStyle? weekdayTextStyle;

  /// A day's number, over the default 20 points. The calendar draws it in
  /// the color the day's state gives.
  final TextStyle? dayTextStyle;

  /// The chosen day's number, over the default 20 points, semibold.
  final TextStyle? selectedDayTextStyle;

  /// A compact label, over the default 17 points. The label draws it in
  /// [labelColor], or the accent while it is open.
  final TextStyle? labelTextStyle;

  /// A row of a wheel, over the default 21 points in [labelColor].
  final TextStyle? wheelTextStyle;

  /// This style over [other].
  @override
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
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      weekdayTextStyle:
          other.weekdayTextStyle?.merge(weekdayTextStyle) ?? weekdayTextStyle,
      dayTextStyle: other.dayTextStyle?.merge(dayTextStyle) ?? dayTextStyle,
      selectedDayTextStyle:
          other.selectedDayTextStyle?.merge(selectedDayTextStyle) ??
          selectedDayTextStyle,
      labelTextStyle:
          other.labelTextStyle?.merge(labelTextStyle) ?? labelTextStyle,
      wheelTextStyle:
          other.wheelTextStyle?.merge(wheelTextStyle) ?? wheelTextStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassDatePickerStyle lerp(GlassDatePickerStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    final text = GlassStyle.lerpNullable(TextStyle.lerp);
    return GlassDatePickerStyle(
      accentColor: color(accentColor, other.accentColor, t),
      labelColor: color(labelColor, other.labelColor, t),
      labelFillColor: color(labelFillColor, other.labelFillColor, t),
      weekdayColor: color(weekdayColor, other.weekdayColor, t),
      todayFillColor: color(todayFillColor, other.todayFillColor, t),
      selectedDayTextColor: color(
        selectedDayTextColor,
        other.selectedDayTextColor,
        t,
      ),
      wheelBandColor: color(wheelBandColor, other.wheelBandColor, t),
      focusColor: color(focusColor, other.focusColor, t),
      hoverColor: color(hoverColor, other.hoverColor, t),
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      weekdayTextStyle: text(weekdayTextStyle, other.weekdayTextStyle, t),
      dayTextStyle: text(dayTextStyle, other.dayTextStyle, t),
      selectedDayTextStyle: text(
        selectedDayTextStyle,
        other.selectedDayTextStyle,
        t,
      ),
      labelTextStyle: text(labelTextStyle, other.labelTextStyle, t),
      wheelTextStyle: text(wheelTextStyle, other.wheelTextStyle, t),
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
      other.wheelBandColor == wheelBandColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.titleTextStyle == titleTextStyle &&
      other.weekdayTextStyle == weekdayTextStyle &&
      other.dayTextStyle == dayTextStyle &&
      other.selectedDayTextStyle == selectedDayTextStyle &&
      other.labelTextStyle == labelTextStyle &&
      other.wheelTextStyle == wheelTextStyle;

  @override
  int get hashCode => Object.hash(
    accentColor,
    labelColor,
    labelFillColor,
    weekdayColor,
    todayFillColor,
    selectedDayTextColor,
    wheelBandColor,
    focusColor,
    hoverColor,
    titleTextStyle,
    weekdayTextStyle,
    dayTextStyle,
    selectedDayTextStyle,
    labelTextStyle,
    wheelTextStyle,
  );

  // UIKit's fonts for the date picker.
  static const _title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const _weekday = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: _weekdayHeight / 13,
  );
  static const _day = TextStyle(fontSize: 20, height: 1.2);
  static const _daySelected = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const _compact = TextStyle(fontSize: 17, height: 20.33 / 17);

  static const _light = GlassDatePickerStyle(
    labelFillColor: Color(0x1F767680),
    labelColor: Color(0xFF000000),
    accentColor: Color(0xFF0088FF),
    weekdayColor: Color(0x993C3C43),
    todayFillColor: Color(0x1F0088FF),
    selectedDayTextColor: Color(0xFFFFFFFF),
    wheelBandColor: Color(0x1F767680),
  );

  static const _dark = GlassDatePickerStyle(
    labelFillColor: Color(0x3D767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF0091FF),
    weekdayColor: Color(0x99EBEBF5),
    todayFillColor: Color(0x330091FF),
    selectedDayTextColor: Color(0xFF000000),
    wheelBandColor: Color(0x3D767680),
  );

  // Increase Contrast: the label fill and the wheel band (tertiarySystemFill)
  // turn from 12 to 20 percent and the accent takes systemBlue's
  // increased-contrast variant, the today fill following it at its own
  // opacity (read from UIKit's color tables, notes private; the weekday
  // color keeps its standard secondaryLabel value, not measured under
  // Increase Contrast).
  static const _lightHighContrast = GlassDatePickerStyle(
    labelFillColor: Color(0x33767680),
    labelColor: Color(0xFF000000),
    accentColor: Color(0xFF1E6EF4),
    weekdayColor: Color(0x993C3C43),
    todayFillColor: Color(0x1F1E6EF4),
    selectedDayTextColor: Color(0xFFFFFFFF),
    wheelBandColor: Color(0x33767680),
  );

  // Increase Contrast, dark: the fills turn from 24 to 32 percent and the
  // accent takes its increased-contrast variant (read from UIKit's color
  // tables, notes private).
  static const _darkHighContrast = GlassDatePickerStyle(
    labelFillColor: Color(0x52767680),
    labelColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF5CB8FF),
    weekdayColor: Color(0x99EBEBF5),
    todayFillColor: Color(0x335CB8FF),
    selectedDayTextColor: Color(0xFF000000),
    wheelBandColor: Color(0x52767680),
  );
}

// The color of the chosen day's number when the chosen day is today, on an
// accent disc.
const _selectedDayColor = Color(0xFFFFFFFF);

// The opacity of the wheels' rows outside the band, drawn in the label
// color at the smaller size (21 points against the band's 23.5), before
// they darken toward the cylinder's edges. UIKit's labels report 0.447; 0.4
// matches the screen (the rows next to the band read 0.36 of black on an
// iPhone 16 Pro).
const double _wheelFadedOpacity = 0.4;

// The opacity of a day outside the picker's range (not measured on a
// device).
const double _unavailableDayOpacity = 0.35;

// The focus ring and hover response of a part of [shape] around [child],
// from [states].
Widget _highlight(
  BuildContext context,
  GlassDatePickerStyle look, {
  required ValueListenable<Set<WidgetState>> states,
  required Widget child,
  GlassShape shape = GlassShape.capsule,
}) => GlassHighlightPaint.of(
  context,
  states: states,
  focusColor: look.focusColor,
  hoverColor: look.hoverColor,
  base: look.accentColor,
  shape: shape,
  inside: true,
  wash: true,
  child: child,
);

/// The iOS 27 calendar date picker: a month calendar in place.
///
/// UIKit: `UIDatePicker` with `.inline` and `.date`. SwiftUI: `DatePicker`
/// with `.graphical`. Flutter: `CalendarDatePicker`.
///
/// Its behaviour, keys and accessibility are [RawGlassDatePicker]'s: the
/// arrows turn the month with a slide, a tap on the month title turns the
/// day grid into month and year wheels (the title takes the accent color
/// at once and its chevron turns to point down over 0.25 s, as UIKit
/// does), and a tap on a day picks it. The picked day sits on a disc in
/// the label color, or in the accent when it is today, and today's number
/// takes the accent on a tinted disc; days outside [minimumDate] and
/// [maximumDate] fade. Texts come from [GlassLocalizations]. The calendar
/// follows the text scale up to [maxTextScale], except the day numbers,
/// which keep their size. It works with any renderer.
///
/// Focused from the keyboard, the title, an arrow or a day draws Flutter's
/// Cupertino focus ring inside it, and a mouse over one washes it as a
/// glass body's hover does (the rule of the glass controls; an
/// approximation, not measured). Each month grid is a layer of its own, so
/// a page turn moves recorded grids instead of painting every day again
/// (IDENTICAL).
class GlassDatePicker extends StatelessWidget {
  /// Creates a calendar with [value] picked.
  const GlassDatePicker({
    required this.value,
    required this.onChanged,
    this.minimumDate,
    this.maximumDate,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.style,
    this.focusNode,
    this.autofocus = false,
    @internal this.defersDays = false,
    super.key,
  });

  /// The picked day; its time of day is kept when another day is picked.
  final DateTime value;

  /// Called with the day the user picks; null disables the picker.
  final ValueChanged<DateTime>? onChanged;

  /// The earliest moment that can be picked; null for no limit. Later
  /// than [maximumDate], both are ignored, as UIKit ignores them.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit.
  final DateTime? maximumDate;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to tint as today; null for the current day.
  final DateTime? today;

  /// The colors, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  /// The focus node of the days, or null for the picker's own: focusing it
  /// focuses the picked day.
  final FocusNode? focusNode;

  /// Whether the days take focus when they first appear.
  final bool autofocus;

  /// Whether the days mount a frame after the rest.
  @internal
  final bool defersDays;

  /// The largest text scale the fixed-size calendar follows.
  static const double maxTextScale = 1.2;

  @override
  Widget build(BuildContext context) {
    final look = GlassDatePickerStyle.resolve(context, style);
    final title = look.titleTextStyle!;
    final weekday = look.weekdayTextStyle!;
    final day = look.dayTextStyle!;
    final selectedDay = look.selectedDayTextStyle!;
    final reduceMotion = GlassTraits.of(context).reduceMotion;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: DefaultTextStyle(
        style: resolveGlassText(
          TextStyle(fontSize: 17, color: look.labelColor),
          context,
        ),
        child: RawGlassDatePicker(
          value: value,
          onChanged: onChanged,
          minimumDate: minimumDate,
          maximumDate: maximumDate,
          firstDayOfWeek: firstDayOfWeek,
          today: today,
          focusNode: focusNode,
          autofocus: autofocus,
          defersDays: defersDays,
          dayBuilder: (context, details) => _day(
            details,
            look: look,
            style: details.selected ? selectedDay : day,
            reduceMotion: reduceMotion,
          ),
          titleBuilder: (context, details) => _highlight(
            context,
            look,
            states: details.states,
            child: _Title(details: details, look: look, style: title),
          ),
          arrowBuilder: (context, details) => _highlight(
            context,
            look,
            states: details.states,
            shape: const GlassShape.oval(),
            child: _Arrow(details: details, look: look),
          ),
          weekdayBuilder: (context, label) =>
              Text(label, textAlign: TextAlign.center, style: weekday),
          monthYearBuilder: (context, details) =>
              _MonthYearWheels(details: details, look: look),
        ),
      ),
    );
  }
}

const double _weekdayHeight = 15.67;

class _Title extends StatelessWidget {
  const _Title({
    required this.details,
    required this.look,
    required this.style,
  });

  final GlassDatePickerTitle details;
  final GlassDatePickerStyle look;
  final TextStyle style;

  static const double _chevronGap = 7.67;
  static const Size _chevron = Size(6.33, 11.67);
  static const double _chevronStroke = 2.1;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            details.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              color: details.showsYearPicker
                  ? look.accentColor!
                  : look.labelColor!,
            ),
          ),
        ),
        const SizedBox(width: _chevronGap),
        MotionTransition(
          rotation: details.chevronAngle,
          child: CustomPaint(
            size: _chevron,
            painter: _ChevronPainter(
              color: look.accentColor!,
              forward: !rtl,
              stroke: _chevronStroke,
            ),
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.details, required this.look});

  final GlassDatePickerArrow details;
  final GlassDatePickerStyle look;

  static const Size _chevron = Size(10, 17.33);
  static const double _stroke = 2.6;
  static const double _shiftRight = 1;
  static const double _shiftLeft = -1.33;

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.translate(
      offset: Offset(details.pointsRight ? _shiftRight : _shiftLeft, 0),
      child: Opacity(
        opacity: details.enabled ? 1 : _unavailableDayOpacity,
        child: CustomPaint(
          size: _chevron,
          painter: _ChevronPainter(
            color: look.labelColor!,
            forward: details.pointsRight,
            stroke: _stroke,
          ),
        ),
      ),
    ),
  );
}

// A day is a handful of elements: the open frame builds every day of the
// month at once, and on a slow phone each element of it counts.
Widget _day(
  GlassDatePickerDay details, {
  required GlassDatePickerStyle look,
  required TextStyle style,
  required bool reduceMotion,
}) {
  final selected = details.selected;
  final today = details.today;
  final color = switch ((selected, today)) {
    (true, true) => _selectedDayColor,
    (true, false) => look.selectedDayTextColor!,
    (false, true) => look.accentColor!,
    (false, false) => look.labelColor!,
  };
  final fill = switch ((selected, today)) {
    (true, true) => look.accentColor!,
    (true, false) => look.labelColor!,
    (false, true) => look.todayFillColor!,
    (false, false) => null,
  };
  final cell = _DayCell(
    width: details.size.width,
    disc: math.min(details.size.width, details.size.height),
    fill: fill,
    states: details.states,
    focusColor: GlassHighlights.ringColor(
      look.focusColor,
      look.accentColor!,
      highContrast: false,
    ),
    hoverColor: look.hoverColor ?? GlassHighlights.hoverColor,
    reduceMotion: reduceMotion,
    child: Text(
      '${details.date.day}',
      textScaler: TextScaler.noScaling,
      style: style.copyWith(color: color),
    ),
  );
  return details.enabled
      ? cell
      : Opacity(opacity: _unavailableDayOpacity, child: cell);
}

/// One day of the grid: [width] wide and as tall as its row, a [disc]
/// across filled with [fill] at its center and the number centered on the
/// disc, with the focus ring inside the disc's edge and the hover's wash
/// over it. It lays out and paints as the Center, Container and Align it
/// stands for, offset for offset.
class _DayCell extends SingleChildRenderObjectWidget {
  const _DayCell({
    required this.width,
    required this.disc,
    required this.fill,
    required this.states,
    required this.focusColor,
    required this.hoverColor,
    required this.reduceMotion,
    required super.child,
  });

  final double width;
  final double disc;
  final Color? fill;
  final ValueListenable<Set<WidgetState>> states;
  final Color focusColor;
  final Color hoverColor;
  final bool reduceMotion;

  @override
  _RenderDayCell createRenderObject(BuildContext context) => _RenderDayCell(
    width: width,
    disc: disc,
    fill: fill,
    highlight: GlassHighlight(states: states, reduceMotion: reduceMotion),
    focusColor: focusColor,
    hoverColor: hoverColor,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderDayCell renderObject) {
    if (renderObject.width != width || renderObject.disc != disc) {
      renderObject.width = width;
      renderObject.disc = disc;
      renderObject.markNeedsLayout();
    }
    if (renderObject.fill != fill ||
        renderObject.focusColor != focusColor ||
        renderObject.hoverColor != hoverColor) {
      renderObject.fill = fill;
      renderObject.focusColor = focusColor;
      renderObject.hoverColor = hoverColor;
      renderObject.markNeedsPaint();
    }
    renderObject.highlight.states = states;
    renderObject.highlight.reduceMotion = reduceMotion;
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
    required this.highlight,
    required this.focusColor,
    required this.hoverColor,
  });

  double width;
  double disc;
  Color? fill;
  final GlassHighlight highlight;
  Color focusColor;
  Color hoverColor;

  Offset _discOffset = Offset.zero;
  Offset _childOffset = Offset.zero;
  Size _discSize = Size.zero;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    highlight.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    highlight.removeListener(markNeedsPaint);
    super.detach();
  }

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

  @override
  Size computeDryLayout(BoxConstraints constraints) => BoxConstraints.tightFor(
    width: width,
  ).enforce(constraints).constrain(Size.infinite);

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + _discOffset;
    final rect = origin & _discSize;
    final fill = this.fill;
    final canvas = context.canvas;
    if (fill != null) {
      final paint = Paint();
      paint.color = fill;
      canvas.drawCircle(rect.center, rect.shortestSide / 2.0, paint);
    }
    final child = this.child;
    if (child != null) context.paintChild(child, origin + _childOffset);
    const shape = GlassShape.oval();
    final hovered = highlight.hovered;
    if (hovered > 0) {
      GlassHighlights.paintHover(
        context.canvas,
        shape.pathIn(rect),
        hoverColor,
        hovered,
      );
    }
    if (highlight.focused) {
      GlassHighlights.paintRing(
        context.canvas,
        focusColor,
        shape: shape,
        body: rect,
        inside: true,
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_discOffset.dx, _discOffset.dy, 0, 1);
    transform.translateByDouble(_childOffset.dx, _childOffset.dy, 0, 1);
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

String _two(int v) => v.toString().padLeft(2, '0');

/// One of UIKit's picker wheels: a column of rows on a cylinder behind a
/// band that shows the selected row larger and in full, every other row
/// smaller, at [_wheelFadedOpacity] and darkened toward the
/// cylinder's edges.
Widget _wheel({
  required _WheelGeometry geometry,
  required GlassDatePickerStyle look,
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) text,
  required int selected,
  required ValueChanged<int> onSelected,
  required String label,
  BuildContext? context,
  bool enabled = true,
  bool looping = true,
  AlignmentGeometry alignment = Alignment.center,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  _WheelViews? views,
  Object? viewKey,
}) {
  Widget view() => _wheelView(
    geometry: geometry,
    look: look,
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
  return _WheelRegion(
    controller: controller,
    count: count,
    looping: looping,
    row: geometry.row,
    look: look,
    enabled: enabled,
    canIncrease: up,
    canDecrease: down,
    semantics: SemanticsProperties(
      label: label,
      value: text(selected),
      increasedValue: up ? text((selected + 1) % count) : null,
      decreasedValue: down ? text((selected - 1) % count) : null,
    ),
    child: ExcludeSemantics(
      child: views == null
          ? view()
          : views.keep(controller, (
              viewKey,
              count,
              looping,
              look,
              context == null
                  ? null
                  : resolveGlassText(const TextStyle(), context).fontFamily,
            ), view),
    ),
  );
}

/// One wheel as a keyboard and accessibility target: a Tab stop that steps
/// the wheel with the arrows, Page Up and Page Down, Home and End, and
/// that draws the focus ring and the hover wash around its selected row.
/// Touches stay with the wheel's own scrolling.
class _WheelRegion extends StatefulWidget {
  const _WheelRegion({
    required this.controller,
    required this.count,
    required this.looping,
    required this.row,
    required this.look,
    required this.enabled,
    required this.canIncrease,
    required this.canDecrease,
    required this.semantics,
    required this.child,
  });

  final FixedExtentScrollController controller;
  final int count;
  final bool looping;
  final double row;
  final GlassDatePickerStyle look;
  final bool enabled;
  final bool canIncrease;
  final bool canDecrease;
  final SemanticsProperties semantics;
  final Widget child;

  @override
  State<_WheelRegion> createState() => _WheelRegionState();
}

class _WheelRegionState extends State<_WheelRegion> {
  final _states = WidgetStatesController();
  late final _range = ValueNotifier(_rangeOf(widget));
  late final List<Interaction> _interactions = [_WheelInput(_command)];

  static AdjustRange _rangeOf(_WheelRegion widget) => AdjustRange(
    canIncrease: widget.canIncrease,
    canDecrease: widget.canDecrease,
  );

  @override
  void didUpdateWidget(_WheelRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _range.value = _rangeOf(widget);
  }

  @override
  void dispose() {
    _states.dispose();
    _range.dispose();
    super.dispose();
  }

  void _command(ValueCommand command) {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final item = controller.selectedItem;
    final count = widget.count;
    final first = widget.looping ? item - item % count : 0;
    final large = math.max(2, count ~/ 4);
    final target = switch (command) {
      ValueCommand.increase => item + 1,
      ValueCommand.decrease => item - 1,
      ValueCommand.increaseLarge => item + large,
      ValueCommand.decreaseLarge => item - large,
      ValueCommand.toMinimum => first,
      ValueCommand.toMaximum => first + count - 1,
    };
    final last = widget.looping ? count * _WheelGeometry.loops - 1 : count - 1;
    final to = target.clamp(0, last);
    if (to == item) return;
    controller.animateToItem(
      to,
      duration: _wheelStep,
      curve: _wheelStepCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    return InputRegion(
      interactions: _interactions,
      statesController: _states,
      enabled: widget.enabled,
      adjustRange: _range,
      semantics: widget.semantics,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Center(
            child: SizedBox(
              height: widget.row,
              child: IgnorePointer(
                child: _highlight(
                  context,
                  look,
                  states: _states,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A wheel's value commands, for the keyboard and accessibility; touches
/// are the wheel's own scrolling.
final class _WheelInput extends Interaction {
  _WheelInput(this.onCommand) : super(role: InteractionRole.control);

  final ValueChanged<ValueCommand> onCommand;

  @override
  bool get adjusts => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) onCommand(input.command);
    return InteractionUpdate.none;
  }
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
  required GlassDatePickerStyle look,
  required FixedExtentScrollController controller,
  required int count,
  required String Function(int) text,
  required ValueChanged<int> onSelected,
  required bool looping,
  required AlignmentGeometry alignment,
  required EdgeInsetsGeometry padding,
  BuildContext? context,
}) {
  final row = look.wheelTextStyle!;
  return ListWheelScrollView.useDelegate(
    controller: controller,
    itemExtent: geometry.row,
    diameterRatio: geometry.diameterRatio,
    perspective: _WheelGeometry.perspective,
    squeeze: geometry.squeeze,
    useMagnifier: true,
    magnification: _WheelGeometry.magnification,
    overAndUnderCenterOpacity: _wheelFadedOpacity,
    physics: const FixedExtentScrollPhysics(
      parent: BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      ),
    ),
    onSelectedItemChanged: (int index) {
      if (context != null) MotionHaptic.selection.play(context);
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
Widget _wheelBand(GlassDatePickerStyle look) => DecoratedBox(
  decoration: ShapeDecoration(
    color: look.wheelBandColor,
    shape: const StadiumBorder(),
  ),
);

/// The iOS 27 time picker: the hour and minute wheels, with an AM/PM wheel
/// in 12-hour time.
///
/// UIKit: `UIDatePicker` with `.wheels` and `.time`. SwiftUI: `DatePicker`
/// with `.wheel` and `.hourAndMinute`. Flutter: `CupertinoTimerPicker` or
/// `CupertinoDatePicker` in time mode.
///
/// A wheel coming to a new row calls [onChanged] with [value]'s day at
/// the new time, bounded by [minimumDate] and [maximumDate]; a new [value]
/// turns the wheels to it. In 12-hour time the hour wheel turning past 11
/// and 12 switches AM and PM, as UIKit's does. A time between two multiples
/// of [minuteInterval] is shown, and reported, rounded down to the earlier
/// one. It is 232 by 204 points and works with any renderer.
///
/// ```dart
/// GlassTimePicker(
///   value: time,
///   minuteInterval: 5,
///   onChanged: (picked) => setState(() => time = picked),
/// )
/// ```
class GlassTimePicker extends StatefulWidget {
  /// Creates wheels showing [value]'s time.
  const GlassTimePicker({
    required this.value,
    required this.onChanged,
    this.minuteInterval = 1,
    this.use24HourFormat,
    this.minimumDate,
    this.maximumDate,
    this.style,
    super.key,
  }) : assert(
         minuteInterval >= 1 &&
             minuteInterval <= 30 &&
             60 % minuteInterval == 0,
         'minuteInterval must divide 60 and lie in 1 to 30.',
       );

  /// The time shown; its day is kept when a wheel turns.
  final DateTime value;

  /// Called with the new time when a wheel comes to a new row; null
  /// disables the wheels.
  final ValueChanged<DateTime>? onChanged;

  /// The step of the minute wheel in minutes, a divisor of 60 from 1 to 30
  /// (UIKit `minuteInterval`).
  final int minuteInterval;

  /// Whether times use 24 hours; null follows the platform's
  /// [MediaQueryData.alwaysUse24HourFormat] (the device's 24-Hour Time
  /// setting on iOS), as UIKit follows the locale's.
  final bool? use24HourFormat;

  /// The earliest moment that can be picked; null for no limit. The wheels
  /// honor its time on its day.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit. The wheels
  /// honor its time on its day.
  final DateTime? maximumDate;

  /// The look, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  @override
  State<GlassTimePicker> createState() => _TimeWheelsState();
}

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
