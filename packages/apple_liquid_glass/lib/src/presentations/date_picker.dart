import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/controls/date_picker.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/presentation.dart';
import 'package:kinesis/widgets.dart';

/// What a [GlassCompactDatePicker] picks.
enum GlassDatePickerMode {
  /// A day: one label that opens a month calendar.
  date,

  /// A time of day: one label that opens the hour and minute wheels.
  time,

  /// A day and a time: a date label and a time label side by side.
  dateAndTime,
}

DateTime _clamp(DateTime value, DateTime? first, DateTime? last) {
  if (first != null && value.isBefore(first)) return first;
  if (last != null && value.isAfter(last)) return last;
  return value;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [value] floored to [interval] as [GlassCompactDatePicker.minuteInterval]
/// describes; unchanged for an interval of 1.
DateTime _floorToMinuteInterval(DateTime value, int interval) {
  if (interval < 2) return value;
  return value.copyWith(
    minute: floorMinute(value.minute, interval),
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
}

/// The iOS 27 compact date picker: a label that opens its picker in an
/// overlay.
///
/// UIKit: `UIDatePicker` with `.compact`. SwiftUI: `DatePicker` with
/// `.compact`. Flutter: `showDatePicker` and `showTimePicker`.
///
/// The label is a tinted capsule showing [value]; a touch dims its text,
/// and a tap opens the overlay out of it: a [GlassDatePicker] for a date,
/// the hour and minute wheels for a time. The overlay grows out of the
/// label's center on a spring while it fades in and reveals its content
/// from the label's side, hangs below the label (above it when there is no
/// room), and extends toward the leading side, on springs fitted to
/// UIKit's frames (replayed on an iPhone 16 Pro).
/// While it is open the label's text takes the accent color. Choosing a day
/// or turning a time wheel calls [onChanged] at once and the overlay stays
/// open; a tap outside or Escape closes it, turning an overlay that still
/// opens around. A tap on the label while the overlay closes opens a new
/// one after a shorter delay than a first open, as UIKit does, while the
/// old one finishes its close. With both labels, a tap on the other label
/// turns the open overlay into its picker.
///
/// In 12-hour time the wheels are the hour (1 to 12), the minute and AM/PM,
/// as UIKit lays them out; the hour wheel turning past 11 and 12 switches
/// AM and PM.
///
/// The texts come from [GlassLocalizations]. The label is a button and a
/// Tab stop; Space and Enter open it, and screen readers hear it expand. The
/// overlay is a dialog to screen readers, with a barrier that dismisses it;
/// it takes the focus at the picked day, and the focus returns to the label
/// when it closes. Focused from the keyboard, the label draws Flutter's
/// Cupertino focus ring, and a mouse over it washes it as a glass body's
/// hover does (an approximation, not measured). A disabled picker draws
/// its labels as text without their capsules and does not open.
///
/// The content fades inside the overlay's clip: NEAR (the clip's
/// anti-aliased edge row differs by up to 23 of 255 in the first frames
/// of the opening). The day grid (the time wheels) mounts on the frame
/// after the overlay's, while the overlay is still transparent, so the
/// open's layout spreads over two frames (IDENTICAL). A label dims under
/// the finger through the alpha of its text color instead of an opacity
/// layer: NEAR (one rounding instead of two, at most 1 of 255 per
/// channel, except where the anti-aliased edges of two glyphs share a
/// pixel, which a layer would cover once and the color covers twice).
class GlassCompactDatePicker extends StatefulWidget {
  /// Creates a picker.
  const GlassCompactDatePicker({
    required this.value,
    required this.onChanged,
    this.mode = GlassDatePickerMode.date,
    this.style,
    this.minuteInterval = 1,
    this.minimumDate,
    this.maximumDate,
    this.use24HourFormat,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.semanticLabel,
    super.key,
  }) : assert(
         minuteInterval >= 1 &&
             minuteInterval <= 30 &&
             60 % minuteInterval == 0,
         'minuteInterval must divide 60 and lie in 1 to 30.',
       );

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

  @override
  State<GlassCompactDatePicker> createState() => _GlassCompactDatePickerState();
}

extension on GlassCompactDatePicker {
  bool get _boundsHold {
    final first = minimumDate;
    final last = maximumDate;
    return first == null || last == null || !last.isBefore(first);
  }

  DateTime? get _minimum => _boundsHold ? minimumDate : null;

  DateTime? get _maximum => _boundsHold ? maximumDate : null;
}

enum _Part { date, time }

class _GlassCompactDatePickerState extends State<GlassCompactDatePicker> {
  _Part? _open;
  DatePickerMotion? _overlay;
  _OverlayViewState? _routeView;
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
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    setState(() => _open = part);
    final reopening = _overlay?.presence == PresenceStatus.leaving;
    final days = FocusNode(debugLabel: 'GlassCompactDatePicker days');
    final loc = GlassLocalizations.of(context);
    await showPresentation<void>(
      context,
      PresentationRoute(
        presentation: Presentation<void, DatePickerMotion>(
          motion: (_) => _overlay = DatePickerMotion(reopening: reopening),
          semanticsRole: SemanticsRole.dialog,
          barrierLabel: loc.datePickerDismissLabel,
          initialFocus: part == _Part.date ? days : null,
          builder: (context, motion) => _OverlayView(
            picker: this,
            motion: motion,
            part: part,
            label: rect,
            days: days,
          ),
        ),
      ),
    );
    days.dispose();
    if (mounted) setState(() => _open = null);
  }

  void _changed(DateTime value) => widget.onChanged?.call(value);

  @override
  void didUpdateWidget(GlassCompactDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _routeView?._hostChanged();
  }

  @override
  Widget build(BuildContext context) {
    final loc = GlassLocalizations.of(context);
    final value = _floorToMinuteInterval(widget.value, widget.minuteInterval);
    final date = loc.compactDate(value);
    final time = loc.compactTime(value, use24HourFormat: _twentyFour);
    final parts = switch (widget.mode) {
      GlassDatePickerMode.date => [(_Part.date, date)],
      GlassDatePickerMode.time => [(_Part.time, time)],
      GlassDatePickerMode.dateAndTime => [
        (_Part.date, date),
        (_Part.time, time),
      ],
    };
    final look = DatePickerLook.of(context, widget.style);
    // The labels keep their measured sizes; a box narrower than they are
    // scales them down instead of overflowing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(width: _DatePickerLook.labelGap),
            _CompactLabel(
              key: _labels[parts[i].$1],
              text: parts[i].$2,
              height: parts[i].$1 == _Part.date
                  ? _DatePickerLook.dateLabelHeight
                  : _DatePickerLook.timeLabelHeight,
              open: _open == parts[i].$1,
              enabled: _enabled,
              look: look,
              semanticLabel: widget.semanticLabel,
              onOpen: (BuildContext anchor) => _show(parts[i].$1, anchor),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactLabel extends StatefulWidget {
  const _CompactLabel({
    required this.text,
    required this.height,
    required this.open,
    required this.enabled,
    required this.look,
    required this.semanticLabel,
    required this.onOpen,
    super.key,
  });

  final String text;
  final double height;
  final bool open;
  final bool enabled;
  final DatePickerLook look;
  final String? semanticLabel;
  final void Function(BuildContext anchor) onOpen;

  @override
  State<_CompactLabel> createState() => _CompactLabelState();
}

class _CompactLabelState extends State<_CompactLabel> {
  final _motion = DatePickerLabelMotion();
  late final _dim = _motion.select((m) => m.highlight.clamp(0.0, 1.0));
  final _states = WidgetStatesController();
  late final List<Interaction> _press = [
    PressInteraction(
      onHighlightChanged: (double t, {required bool highlighted}) =>
          highlighted ? _motion.press(t) : _motion.release(t),
      onTap: (_) => widget.onOpen(context),
    ),
  ];

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final loc = GlassLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
    final label = widget.semanticLabel;
    final color = widget.open ? look.accentColor : look.labelColor;
    final dim = widget.enabled ? _motion.highlight.clamp(0.0, 1.0) : 1.0;
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _press,
        enabled: widget.enabled,
        statesController: _states,
        semantics: SemanticsProperties(
          label: label == null ? widget.text : '$label, ${widget.text}',
        ),
        child: Semantics(
          button: true,
          expanded: widget.open,
          hint: loc.compactDatePickerHint,
          excludeSemantics: true,
          child: look.highlight(
            context,
            states: _states,
            child: Container(
              constraints: BoxConstraints(minHeight: widget.height),
              padding: const EdgeInsets.symmetric(
                horizontal: _DatePickerLook.labelPadding,
              ),
              decoration: widget.enabled
                  ? ShapeDecoration(
                      color: look.labelFillColor,
                      shape: const StadiumBorder(),
                    )
                  : null,
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: _Dimmed(
                  opacity: widget.enabled ? _dim : null,
                  color: color,
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    textScaler: scaler,
                    style: DatePickerType.resolve(
                      DatePickerType.compact.copyWith(
                        height: 20.33 / 17,
                        color: dim >= 1
                            ? color
                            : color.withValues(alpha: color.a * dim),
                      ),
                      context: context,
                    ),
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

/// Sets the alpha of its paragraph's text color to [color]'s times
/// [opacity] as the opacity changes, without a rebuild or a layer.
class _Dimmed extends SingleChildRenderObjectWidget {
  const _Dimmed({
    required this.opacity,
    required this.color,
    required super.child,
  });

  final MotionSelection<double>? opacity;
  final Color color;

  @override
  _RenderDimmed createRenderObject(BuildContext context) =>
      _RenderDimmed(opacity: opacity, color: color);

  @override
  void updateRenderObject(BuildContext context, _RenderDimmed renderObject) {
    renderObject.opacity = opacity;
    renderObject.color = color;
  }
}

class _RenderDimmed extends RenderProxyBox {
  _RenderDimmed({required this._opacity, required this.color});

  Color color;

  MotionSelection<double>? _opacity;
  MotionSelection<double>? get opacity => _opacity;
  set opacity(MotionSelection<double>? value) {
    if (identical(value, _opacity)) return;
    if (attached) _opacity?.removeRenderListener(_changed);
    _opacity = value;
    if (attached) {
      value?.addRenderListener(_changed);
      _changed();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity?.addRenderListener(_changed);
  }

  @override
  void detach() {
    _opacity?.removeRenderListener(_changed);
    super.detach();
  }

  void _changed() {
    final paragraph = child;
    if (paragraph is! RenderParagraph) return;
    final text = paragraph.text;
    if (text is! TextSpan) return;
    final opacity = _opacity?.value ?? 1;
    final next = opacity >= 1
        ? color
        : color.withValues(alpha: color.a * opacity);
    if (text.style?.color == next) return;
    paragraph.text = TextSpan(
      text: text.text,
      children: text.children,
      style: (text.style ?? const TextStyle()).copyWith(color: next),
      recognizer: text.recognizer,
      semanticsLabel: text.semanticsLabel,
      locale: text.locale,
      spellOut: text.spellOut,
    );
  }
}

/// The largest text scale the overlay's fixed-size content follows.
const double _overlayMaxTextScale = 1.2;

class _OverlayView extends StatefulWidget {
  const _OverlayView({
    required this.picker,
    required this.motion,
    required this.part,
    required this.label,
    required this.days,
  });

  final _GlassCompactDatePickerState picker;
  final DatePickerMotion motion;
  final _Part part;
  final Rect label;
  final FocusNode days;

  @override
  State<_OverlayView> createState() => _OverlayViewState();
}

/// Hears where a touch outside the overlay's box lifts, in global
/// coordinates.
final class _OutsideTap extends Interaction {
  _OutsideTap(this.onTap);

  final void Function(Offset position) onTap;
  Offset Function(Offset local) _toGlobal = _same;
  int? _pointer;

  static Offset _same(Offset local) => local;

  @override
  bool accepts(PointerDownInput down) => true;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) =>
      _toGlobal = toGlobal;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        _pointer = input.pointer;
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        onTap(_toGlobal(input.position));
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
      default:
    }
    return InteractionUpdate.none;
  }
}

class _OverlayViewState extends State<_OverlayView> {
  late DateTime _value = _bounded(_picker.value);
  late _Part _part = widget.part;
  late Rect _label = widget.label;
  _Part? _fromPart;
  Rect? _fromLabel;
  late final List<Interaction> _outside = [_OutsideTap(_tappedOutside)];

  // The tree rebuilds only when this flips; every other frame reads the
  // motion through render objects.
  late final _switching = _motion.select((m) => m.switching);
  late final _swap = _motion.select((m) => m.swap.clamp(0.0, 1.0));
  late final _unswap = _motion.select((m) => 1 - m.swap.clamp(0.0, 1.0));
  late final _opacity = _motion.select((m) => m.opacity);
  late final _glass = _motion.select(
    (m) => GlassFrame(
      shape: const GlassShape.superellipse(_DatePickerLook.cornerRadius),
      opacity: m.opacity,
    ),
  );

  // Safe one frame late: the overlay stays transparent for at least the
  // reopen delay after the lift.
  bool _contentReady = false;
  VoidCallback? _cancelReady;
  VoidCallback? _cancelReconcile;
  GlassCompactDatePicker? _shown;
  bool? _shownTwentyFour;

  DatePickerMotion get _motion => widget.motion;

  _GlassCompactDatePickerState get _host => widget.picker;

  GlassCompactDatePicker get _picker => _host.widget;

  double get _now => _motion.clock.now;

  @override
  void initState() {
    super.initState();
    _host._routeView = this;
    _cancelReady = _motion.clock.schedulePublish(() {
      _cancelReady = null;
      if (mounted) setState(() => _contentReady = true);
    });
  }

  @override
  void dispose() {
    _cancelReady?.call();
    _cancelReconcile?.call();
    if (_host._routeView == this) _host._routeView = null;
    super.dispose();
  }

  // The host's build is not this route's, so its change reaches the
  // overlay in the next publish phase, before that frame's build.
  void _hostChanged() {
    _cancelReconcile ??= _motion.clock.schedulePublish(() {
      _cancelReconcile = null;
      _reconcile();
    });
  }

  _Part? _otherLabelAt(Offset position) {
    for (final part in _Part.values) {
      if (part == _part) continue;
      final rect = _host._labelRect(part);
      if (rect != null && rect.contains(position)) return part;
    }
    return null;
  }

  void _tappedOutside(Offset position) {
    final other = _otherLabelAt(position);
    if (other == null) {
      _close(DismissTrigger.outsideTap);
    } else {
      _switchTo(other);
    }
  }

  void _switchTo(_Part part) {
    final label = _host._labelRect(part);
    if (label == null || !_motion.isOpen) return;
    _motion.switchPicker(_now, back: _switching.value && part == _fromPart);
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
      _clamp(value, _picker._minimum, _picker._maximum);

  void _pick(DateTime value) {
    if (!_host.mounted || !_host._enabled) return;
    final next = _bounded(value);
    setState(() => _value = next);
    _host._changed(next);
  }

  void _reconcile() {
    if (!mounted || !_host.mounted) return;
    if (!_host._enabled) {
      _close(DismissTrigger.programmatic);
      return;
    }
    final value = _bounded(_picker.value);
    final shown = _shown;
    if (_value == value &&
        _host._twentyFour == _shownTwentyFour &&
        shown != null &&
        _showsAlike(shown, _picker)) {
      return;
    }
    setState(() => _value = value);
  }

  static bool _showsAlike(GlassCompactDatePicker a, GlassCompactDatePicker b) =>
      a.mode == b.mode &&
      a.style == b.style &&
      a.minuteInterval == b.minuteInterval &&
      a.minimumDate == b.minimumDate &&
      a.maximumDate == b.maximumDate &&
      a.firstDayOfWeek == b.firstDayOfWeek &&
      a.today == b.today;

  Size _sizeFor(_Part part) => part == _Part.time
      ? DatePickerMotion.timeSize
      : DatePickerCalendarMotion.calendarSize;

  Widget _content(_Part part, DatePickerLook look) => part == _Part.time
      ? DatePickerTimeWheels(
          value: _value,
          firstDate: _picker._minimum,
          lastDate: _picker._maximum,
          minuteInterval: _picker.minuteInterval,
          twentyFour: _host._twentyFour,
          look: look,
          onChanged: _pick,
        )
      : GlassDatePicker(
          value: _value,
          onChanged: _pick,
          minimumDate: _picker._minimum,
          maximumDate: _picker._maximum,
          firstDayOfWeek: _picker.firstDayOfWeek,
          today: _picker.today ?? _dateOnly(DateTime.now()),
          style: _picker.style,
          focusNode: widget.days,
          defersDays: !_contentReady,
        );

  @override
  Widget build(BuildContext context) {
    _shown = _picker;
    _shownTwentyFour = _host._twentyFour;
    final look = DatePickerLook.of(context, _picker.style);
    final media = MediaQuery.of(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final origin = _origin(context);
    final padding = EdgeInsets.only(
      top: media.padding.top,
      bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    final part = _part;
    final size = _sizeFor(part);
    final from = _fromPart;
    final fromSize = from == null ? size : _sizeFor(from);
    final to = SizedBox.fromSize(
      key: ValueKey<_Part>(part),
      size: size,
      child: part == _Part.time && !_contentReady
          ? const SizedBox.shrink()
          : _content(part, look),
    );
    Widget overlayFor({required bool below}) => MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(
          maxScaleFactor: _overlayMaxTextScale,
        ),
      ),
      child: DefaultTextStyle(
        style: DatePickerType.resolve(
          TextStyle(fontSize: 17, color: look.labelColor),
          context: context,
        ),
        child: ListenableBuilder(
          listenable: _switching,
          builder: (BuildContext context, Widget? child) =>
              from == null || !_switching.value
              ? child!
              : _Crossfade(
                  alignment: below
                      ? AlignmentDirectional.topStart
                      : AlignmentDirectional.bottomStart,
                  fadeIn: _swap,
                  fadeOut: _unswap,
                  from: ExcludeSemantics(
                    child: SizedBox.fromSize(
                      size: fromSize,
                      child: _content(from, look),
                    ),
                  ),
                  to: child!,
                ),
          child: to,
        ),
      ),
    );
    return LayoutBuilder(
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
              child: ExcludeSemantics(
                child: InputRegion(
                  interactions: _outside,
                  child: const SizedBox.expand(),
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
                _DatePickerLook.cornerRadius,
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
  final Widget from;
  final Widget to;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: alignment,
    clipBehavior: Clip.none,
    children: [
      IgnorePointer(
        child: MotionTransition(opacity: fadeOut, child: from),
      ),
      MotionTransition(opacity: fadeIn, child: to),
    ],
  );
}

abstract final class _DatePickerLook {
  /// The corner radius of the overlay.
  static const double cornerRadius = 28;

  /// The height of the compact date label.
  static const double dateLabelHeight = 34.33;

  /// The height of the compact time label.
  static const double timeLabelHeight = 36;

  /// The horizontal space inside a compact label.
  static const double labelPadding = 12;

  /// The space between the date label and the time label.
  static const double labelGap = 4;
}
