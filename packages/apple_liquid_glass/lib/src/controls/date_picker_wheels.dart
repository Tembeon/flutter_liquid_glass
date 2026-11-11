part of 'date_picker.dart';

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
