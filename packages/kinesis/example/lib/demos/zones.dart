import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class ZonesDemo extends StatefulWidget {
  const ZonesDemo({super.key});

  @override
  State<ZonesDemo> createState() => _ZonesDemoState();
}

class _ZonesDemoState extends State<ZonesDemo> {
  static const _segments = ['Day', 'Week', 'Month', 'Year'];
  static const _height = 40.0;

  final _zones = InputZonesController<int>();
  final _width = MotionSignal<double>(0);
  final _selection = MotionValue<double>(0);
  int _selected = 0;

  static const _orbit = MotionKeyframes<double>(
    duration: 6,
    repeatCount: double.infinity,
    stops: [KeyframeStop(0, 0), KeyframeStop(1, 2 * pi)],
  );
  static const _bubbles = 3;
  static const _bubble = 56.0;
  final _turn = KeyframeValue(_orbit, playing: false);
  final _bubbleSize = MotionSignal(Size.zero);
  final _popped = [for (var i = 0; i < _bubbles; i++) MotionValue<double>(0)];
  int _hits = 0;

  late final Listenable _bubbleFrames = Listenable.merge([
    _turn,
    _bubbleSize,
    ..._popped,
  ]);

  double get _segment => _width.value / _segments.length;

  Rect _segmentRect(int index) =>
      Rect.fromLTWH(index * _segment, 0, _segment, _height);

  void _select(int index) {
    withSpring(Spring.snappy, () => _selection.target = index.toDouble());
    setState(() => _selected = index);
  }

  Offset _bubbleCenter(int index) {
    final size = _bubbleSize.value;
    final angle = _turn.value + index * 2 * pi / _bubbles;
    final radius = min(size.width, size.height) / 2 - _bubble / 2 - 8;
    return size.center(Offset.zero) +
        Offset(cos(angle), sin(angle)) * max(radius, 0);
  }

  void _pop(int index) {
    _hits++;
    final popped = _popped[index];
    popped.target = 1;
    withSpring(Spring.bouncy, () => popped.target = 0);
    setState(() {});
  }

  void _toggleOrbit() {
    final now = _turn.clock.now;
    if (_turn.isPlaying) {
      _turn.pause(now);
    } else {
      _turn.resume(now);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _zones.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'InputZones gives the parts one widget paints what InputRegion '
          'gives a box: touch, mouse, focus, keys and semantics, for parts '
          'that may move every frame without a rebuild.',
      children: [
        Section(
          title: 'Slide across',
          caption:
              'Four zones over one painted control. With slides, a finger '
              'that moves onto another segment takes the touch there, and '
              'the segment it lifts on is chosen. With a keyboard, Tab in '
              'and use the arrows.',
          stage: MotionMeasure(
            onSize: (t, size) => _width.write(t, size.width),
            child: InputZones<int>(
              controller: _zones,
              stops: InputZoneStops.one,
              current: _selected,
              activatesOnMove: true,
              slides: true,
              feedback: (_, event) =>
                  event is ScrubChangeEvent ? MotionHaptic.selection : null,
              zones: [
                for (final (index, label) in _segments.indexed)
                  InputZone(
                    id: index,
                    interactions: [
                      PressInteraction(onTap: (_) => _select(index)),
                    ],
                    semantics: SemanticsProperties(
                      label: label,
                      button: true,
                      selected: index == _selected,
                    ),
                  ),
              ],
              frameOf: (index) => _width.value == 0
                  ? null
                  : InputZoneFrame(
                      _segmentRect(index),
                      radius: BorderRadius.circular(_height / 2),
                    ),
              frames: _width,
              child: _Segments(
                labels: _segments,
                selection: _selection,
                zones: _zones,
                height: _height,
              ),
            ),
          ),
        ),
        const Section(
          title: 'Hold, then slide',
          caption:
              'A long press hands its touch to the menu through an '
              'InputPort (sequenced): without lifting, the finger slides '
              'onto the rows and the one it lifts on is chosen. A finger '
              'that rests on More for half a second opens the rest '
              '(DwellInteraction). The menu answers its own hit test '
              '(zoneAt), and a quick tap on the button closes it.',
          stage: _PointMenu(),
        ),
        Section(
          title: 'Moving targets',
          caption:
              'Each bubble is a zone whose frame follows the orbit. Tap them '
              'as they go round: the hit test reads where they are painted '
              'in this frame, and nothing rebuilds while they move.',
          stage: MotionMeasure(
            onSize: _bubbleSize.write,
            child: SizedBox(
              height: 220,
              child: InputZones<int>(
                zones: [
                  for (var i = 0; i < _bubbles; i++)
                    InputZone(
                      id: i,
                      interactions: [PressInteraction(onTap: (_) => _pop(i))],
                      semantics: SemanticsProperties(
                        label: 'Bubble ${i + 1}',
                        button: true,
                      ),
                    ),
                ],
                frameOf: (i) => _bubbleSize.value.isEmpty
                    ? null
                    : InputZoneFrame(
                        Rect.fromCenter(
                          center: _bubbleCenter(i),
                          width: _bubble,
                          height: _bubble,
                        ),
                        radius: BorderRadius.circular(_bubble / 2),
                      ),
                frames: _bubbleFrames,
                child: Stack(
                  children: [
                    for (var i = 0; i < _bubbles; i++)
                      MotionTransition(
                        offset: MotionSelection(
                          () => _bubbleCenter(i) - const Offset(28, 28),
                        ),
                        scale: MotionSelection(
                          () => 1 + 0.35 * _popped[i].value,
                        ),
                        child: Dot(
                          color: palette.swatches[i + 1],
                          size: _bubble,
                        ),
                      ),
                    Center(
                      child: Text(
                        '$_hits',
                        style: TextStyles.title.copyWith(
                          color: palette.secondaryLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          controls: [
            PushButton(
              _turn.isPlaying ? 'Pause' : 'Orbit',
              onPressed: _toggleOrbit,
            ),
          ],
        ),
      ],
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({
    required this.labels,
    required this.selection,
    required this.zones,
    required this.height,
  });

  final List<String> labels;
  final MotionValue<double> selection;
  final InputZonesController<int> zones;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.fill,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segment = constraints.maxWidth / labels.length;
            return Stack(
              children: [
                MotionTransition(
                  translateX: MotionSelection(
                    () => selection.value * segment,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: SizedBox(
                      width: segment - 6,
                      height: height - 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(height / 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (index, label) in labels.indexed)
                      Expanded(
                        child: zones.withStates(
                          index,
                          (context, states) => Opacity(
                            opacity: states.contains(WidgetState.pressed)
                                ? 0.45
                                : 1,
                            child: Center(
                              child: Text(label, style: TextStyles.label),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A menu a long press on its button opens beside it, chosen by sliding.
class _PointMenu extends StatefulWidget {
  const _PointMenu();

  @override
  State<_PointMenu> createState() => _PointMenuState();
}

class _PointMenuState extends State<_PointMenu> {
  static const _rows = ['Copy', 'Share', 'More', 'Rename', 'Delete'];
  static const _more = 2;
  static const _rowHeight = 44.0;
  static const _width = 160.0;

  final _port = InputPort();
  final _zones = InputZonesController<int>();
  final _layout = ValueNotifier(0);
  final _shown = MotionValue<double>(0);
  bool _open = false;
  bool _expanded = false;
  String _chosen = 'Hold the button.';

  int get _visible => _expanded ? _rows.length : _more + 1;

  late final _button = [
    LongPressInteraction(
      duration: 0.3,
      allowableMovement: null,
      contends: true,
      onStart: (_) => _show(),
    ).sequenced(_port.forward),
    PressInteraction(onTap: (_) => _hide()),
  ];

  late final _lift = _Lift(onLift: _lifted);

  late final Map<int, List<Interaction>> _rowInputs = {
    for (var i = 0; i < _rows.length; i++)
      i: [
        PressInteraction(onTap: (_) => _choose(i)),
        if (i == _more)
          DwellInteraction(
            duration: 0.5,
            hovers: false,
            onDwell: (_) => _expand(),
          ),
      ],
  };

  void _show() {
    _expanded = false;
    _setOpen(true);
  }

  void _hide() => _setOpen(false);

  void _setOpen(bool open) {
    if (open == _open) return;
    setState(() => _open = open);
    _layout.value++;
    withSpring(Spring.snappy, () => _shown.target = open ? 1 : 0);
  }

  void _expand() {
    if (_expanded || !_open) return;
    setState(() => _expanded = true);
    _layout.value++;
  }

  void _choose(int row) {
    if (row == _more) return _expand();
    setState(() => _chosen = 'Chose ${_rows[row]}.');
    _hide();
  }

  void _lifted(Offset position) {
    if (_zones.zoneAt(position) == null) _hide();
  }

  int? _rowAt(Offset position) {
    if (!_open || position.dx < 0 || position.dx >= _width) return null;
    final row = (position.dy / _rowHeight).floor();
    return row >= 0 && row < _visible ? row : null;
  }

  InputZoneFrame? _frameOf(int row) => _open && row < _visible
      ? InputZoneFrame(Rect.fromLTWH(0, row * _rowHeight, _width, _rowHeight))
      : null;

  @override
  void dispose() {
    _zones.dispose();
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _rowHeight * _rows.length,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputRegion(
                interactions: _button,
                semantics: const SemanticsProperties(
                  label: 'Menu',
                  button: true,
                ),
                child: Tile(color: palette.accent, size: 72, label: 'Hold'),
              ),
              const SizedBox(width: 16),
              InputZones<int>(
                zones: [
                  for (var i = 0; i < _rows.length; i++)
                    InputZone(
                      id: i,
                      interactions: _rowInputs[i]!,
                      semantics: SemanticsProperties(
                        label: _rows[i],
                        button: true,
                      ),
                    ),
                ],
                frameOf: _frameOf,
                frames: _layout,
                zoneAt: _rowAt,
                controller: _zones,
                slides: true,
                port: _port,
                interactions: [_lift],
                feedback: (_, event) =>
                    event is ScrubChangeEvent ? MotionHaptic.selection : null,
                child: IgnorePointer(
                  ignoring: !_open,
                  child: MotionTransition(
                    opacity: _shown,
                    scale: MotionSelection(() => 0.9 + 0.1 * _shown.value),
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: _width,
                      height: _rowHeight * _visible,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.fill,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < _visible; i++)
                              _MenuRow(
                                label: i == _more && !_expanded
                                    ? '${_rows[i]}...'
                                    : _rows[i],
                                states: _zones.states(i),
                                height: _rowHeight,
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
        const SizedBox(height: 12),
        Text(_chosen, style: TextStyles.mono.copyWith(color: palette.label)),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.states,
    required this.height,
  });

  final String label;
  final ValueListenable<Set<WidgetState>> states;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return ValueListenableBuilder(
      valueListenable: states,
      builder: (context, states, _) => SizedBox(
        height: height,
        child: ColoredBox(
          color: states.contains(WidgetState.pressed)
              ? palette.accent.withValues(alpha: 0.25)
              : const Color(0x00000000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(label, style: TextStyles.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hears the finger lift anywhere on the menu, in the menu's coordinates.
final class _Lift extends Interaction {
  _Lift({required this.onLift}) : super(role: InteractionRole.observer);

  final ValueChanged<Offset> onLift;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input case PointerUpInput(:final position)) onLift(position);
    return InteractionUpdate.none;
  }
}
