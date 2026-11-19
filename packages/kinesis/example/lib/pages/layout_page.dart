import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class LayoutPage extends StatelessWidget {
  const LayoutPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _MotionLayoutGridCard(),
      SizedBox(height: 16),
      _InputZonesDockCard(),
      SizedBox(height: 16),
      _PresentationsCard(),
    ],
  );
}

class _MotionLayoutGridCard extends StatefulWidget {
  const _MotionLayoutGridCard();

  @override
  State<_MotionLayoutGridCard> createState() => _MotionLayoutGridCardState();
}

class _MotionLayoutGridCardState extends State<_MotionLayoutGridCard> {
  final math.Random _rng = math.Random(7);
  int _nextId = 7;
  int _columns = 3;
  final List<int> _items = [1, 2, 3, 4, 5, 6];

  void _shuffle() => setState(() => _items.shuffle(_rng));

  void _add() => setState(() => _items.insert(0, _nextId++));

  void _remove() {
    if (_items.length <= 1) return;
    setState(_items.removeLast);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final colors = [
      palette.blue,
      palette.orange,
      palette.green,
      palette.purple,
      palette.teal,
      palette.indigo,
      palette.red,
    ];

    return StudioCard(
      title: 'MotionLayout Spring Grid',
      subtitle:
          'Shuffle, add, remove, or change column count: MotionLayout '
          'captures each child rect after layout and springs every tile to '
          'its new slot before paint.',
      apis: const ['MotionLayout', 'LayoutMotion', 'LayoutPlanner'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              KinesisButton(
                label: 'Shuffle',
                compact: true,
                filled: true,
                glyph: StudioGlyph.shuffle,
                onPressed: _shuffle,
              ),
              KinesisButton(
                label: 'Add',
                compact: true,
                glyph: StudioGlyph.plus,
                accent: palette.green,
                onPressed: _add,
              ),
              KinesisButton(
                label: 'Remove',
                compact: true,
                glyph: StudioGlyph.minus,
                accent: palette.red,
                onPressed: _items.length > 1 ? _remove : null,
              ),
              for (final cols in const [1, 2, 3])
                KinesisChip(
                  label: '$cols col',
                  selected: _columns == cols,
                  onTap: () => setState(() => _columns = cols),
                ),
            ],
          ),
          const SizedBox(height: 14),
          MotionLayout(
            layoutBuilder: (context, children) => LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                final w =
                    (constraints.maxWidth - gap * (_columns - 1)) / _columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final child in children)
                      SizedBox(width: w, height: 54, child: child),
                  ],
                );
              },
            ),
            children: [
              for (final id in _items)
                _Tile(
                  key: ValueKey<int>(id),
                  id: id,
                  color: colors[id % colors.length],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.id, required this.color, super.key});

  final int id;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Center(
      child: Text(
        'Item #$id',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
}

class _InputZonesDockCard extends StatefulWidget {
  const _InputZonesDockCard();

  @override
  State<_InputZonesDockCard> createState() => _InputZonesDockCardState();
}

class _InputZonesDockCardState extends State<_InputZonesDockCard> {
  static const _labels = ['Draw', 'Erase', 'Measure', 'Export'];

  late final MotionClock _clock = MotionClockScope.of(context);
  late final InputZonesController<int> _controller =
      InputZonesController<int>();
  late final MotionValue<double> _activeX = MotionValue<double>(
    0,
    clock: _clock,
  );
  final ChangeNotifier _frames = ChangeNotifier();
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'InputZones Sliding Action Dock',
      subtitle:
          'Press and slide your finger across zones without lifting. One '
          'InputZones host handles hit testing, sliding handoff, focus, '
          'keyboard arrows, and per-zone WidgetStates.',
      apis: const ['InputZones', 'InputZonesController', 'InputZoneFrame'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final zoneW = constraints.maxWidth / _labels.length;
              return InputZones<int>(
                controller: _controller,
                activatesOnMove: true,
                frames: _frames,
                current: _selected,
                frameOf: (id) => InputZoneFrame(
                  Rect.fromLTWH(id * zoneW, 0, zoneW, 48),
                  radius: BorderRadius.circular(12),
                ),
                feedback: (id, event) =>
                    event is ActivationEvent ? MotionHaptic.selection : null,
                zones: [
                  for (var i = 0; i < _labels.length; i++)
                    InputZone<int>(
                      id: i,
                      interactions: [
                        TapInteraction(
                          onTap: (t) {
                            if (_selected != i) {
                              setState(() => _selected = i);
                              withSpring(
                                Spring.snappy,
                                () => _activeX.retarget(t, i.toDouble()),
                              );
                            }
                          },
                        ),
                      ],
                      semantics: SemanticsProperties(
                        button: true,
                        selected: _selected == i,
                        label: _labels[i],
                      ),
                    ),
                ],
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.well,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.hairline),
                  ),
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _DockPillPainter(
                              index: _activeX,
                              count: _labels.length,
                              color: palette.blue,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _labels.length; i++)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    _labels[i],
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _selected == i
                                          ? const Color(0xFFFFFFFF)
                                          : palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Active zone: ${_labels[_selected]} (try dragging or arrow keys)',
            style: palette.mono,
          ),
        ],
      ),
    );
  }
}

final class _DockPillPainter extends CustomPainter {
  _DockPillPainter({
    required this.index,
    required this.count,
    required this.color,
  }) : super(repaint: index);

  final MotionValue<double> index;
  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / count;
    final rect = Rect.fromLTWH(
      index.value * w + 4,
      4,
      w - 8,
      size.height - 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_DockPillPainter oldDelegate) =>
      count != oldDelegate.count || color != oldDelegate.color;
}

class _PresentationsCard extends StatefulWidget {
  const _PresentationsCard();

  @override
  State<_PresentationsCard> createState() => _PresentationsCardState();
}

class _PresentationsCardState extends State<_PresentationsCard> {
  final MotionSource _popoverSource = MotionSource();
  final PresentationPortalController _portal = PresentationPortalController();
  String _lastResult = 'none';

  Future<void> _openSheet() async {
    final palette = StudioTheme.of(context);
    final result = await showPresentation<String>(
      context,
      PresentationRoute<String>(
        semanticsLabel: 'Kinesis Sheet',
        presentation: Presentation<String, _SheetMotion>(
          motion: (env) => _SheetMotion(clock: env.clock),
          dismiss: DismissPolicy.modal,
          dim: (motion) => 0.32 * motion.opacity,
          barrierLabel: 'Dismiss sheet',
          builder: (context, motion) => _DemoSheetBody(
            motion: motion,
            palette: palette,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _lastResult = result ?? 'dismissed');
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'Presentations: Route Sheet & Source Portal',
      subtitle:
          'Presentation owns focus, Escape/barrier dismissal, dim, and '
          'inert-on-leave. Open a draggable PresentationRoute sheet or a '
          'PresentationPortal popover growing out of its MotionSourceBox.',
      apis: const [
        'Presentation',
        'PresentationRoute',
        'PresentationPortal',
        'MotionSourceBox',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KinesisButton(
                label: 'Open Draggable Sheet',
                filled: true,
                onPressed: _openSheet,
              ),
              PresentationPortal(
                controller: _portal,
                presentation: Presentation<void, _PopoverMotion>(
                  source: _popoverSource,
                  dismissesOnOutsideTap: true,
                  motion: (env) => _PopoverMotion(clock: env.clock),
                  builder: (context, motion) => _DemoPopover(
                    motion: motion,
                    palette: palette,
                    onClose: () => _portal.dismiss(DismissTrigger.programmatic),
                  ),
                ),
                child: MotionSourceBox(
                  source: _popoverSource,
                  radius: BorderRadius.circular(11),
                  child: KinesisButton(
                    label: 'Open Anchored Popover',
                    accent: palette.purple,
                    onPressed: _portal.present,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Last sheet result: $_lastResult', style: palette.mono),
        ],
      ),
    );
  }
}

final class _SheetMotion extends PresentedProgress {
  _SheetMotion({super.clock})
    : super(
        openSpring: Spring.bouncy,
        closeSpring: Spring.snappy,
        rest: MotionRest.opacity,
      ) {
    _dragOffset = own(MotionValue<double>(0));
  }

  late final MotionValue<double> _dragOffset;

  late final ValueListenable<double> translateY = select(
    (m) => (1 - m.progress) * 280 + m._dragOffset.value,
  );
  late final ValueListenable<double> opacityListenable = select(
    (m) => m.opacity,
  );

  void dragUpdate(double t, double dy) {
    const band = RubberBand(0, 260, dimension: 240);
    _dragOffset.snap(t, band.apply(dy));
  }

  void dragEnd(double t, double velocity, VoidCallback onDismiss) {
    final pos = _dragOffset.valueAt(t);
    if (pos > 90 || velocity > 450) {
      onDismiss();
      return;
    }
    _dragOffset.setVelocity(t, velocity);
    withSpring(Spring.snappy, () => _dragOffset.retarget(t, 0));
  }
}

class _DemoSheetBody extends StatefulWidget {
  const _DemoSheetBody({
    required this.motion,
    required this.palette,
  });

  final _SheetMotion motion;
  final StudioPalette palette;

  @override
  State<_DemoSheetBody> createState() => _DemoSheetBodyState();
}

class _DemoSheetBodyState extends State<_DemoSheetBody> {
  late final DragInteraction _drag = DragInteraction(
    axis: Axis.vertical,
    slop: 0,
    onUpdate: (d) => widget.motion.dragUpdate(d.time, d.translation.dy),
    onEnd: (d) => widget.motion.dragEnd(
      d.time,
      d.velocity.dy,
      () => Navigator.of(context).pop('dragged down'),
    ),
    onCancel: (t) => widget.motion.dragEnd(t, 0, () {}),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return StudioTheme(
      palette: p,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: MotionTransition(
              translateY: widget.motion.translateY,
              opacity: widget.motion.opacityListenable,
              child: InputRegion(
                interactions: [_drag],
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: p.hairline),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: p.textTertiary.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const SizedBox(width: 40, height: 5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('PresentationRoute Sheet', style: p.title),
                        const SizedBox(height: 6),
                        Text(
                          'Drag down to dismiss, press Escape, tap the '
                          'barrier, or choose a result below.',
                          style: p.subtitle,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            KinesisButton(
                              label: 'Confirm',
                              filled: true,
                              accent: p.green,
                              onPressed: () =>
                                  Navigator.of(context).pop('confirmed'),
                            ),
                            const SizedBox(width: 10),
                            KinesisButton(
                              label: 'Cancel',
                              accent: p.red,
                              onPressed: () =>
                                  Navigator.of(context).pop('cancelled'),
                            ),
                          ],
                        ),
                      ],
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

final class _PopoverMotion extends PresentedProgress with Sourced {
  _PopoverMotion({super.clock})
    : super(
        openSpring: Spring.snappy,
        closeSpring: Spring.snappy,
        rest: MotionRest.opacity,
      );

  SourceGeometry? _source;

  SourceGeometry? get source => _source;

  @override
  void sourceMoved(double t, SourceGeometry? geometry) {
    _source = geometry;
    changed();
  }

  late final ValueListenable<double> scaleListenable = select(
    (m) => 0.72 + 0.28 * m.progress,
  );
  late final ValueListenable<double> opacityListenable = select(
    (m) => m.opacity,
  );
}

class _DemoPopover extends StatelessWidget {
  const _DemoPopover({
    required this.motion,
    required this.palette,
    required this.onClose,
  });

  final _PopoverMotion motion;
  final StudioPalette palette;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final anchor = motion.source?.rect;
    final left = anchor != null ? math.max<double>(12, anchor.left) : 24.0;
    final top = anchor != null ? math.max<double>(12, anchor.top - 122) : 120.0;

    return StudioTheme(
      palette: palette,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: MotionTransition(
              scale: motion.scaleListenable,
              opacity: motion.opacityListenable,
              alignment: Alignment.bottomLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x28000000),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: 240,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Source-Anchored Portal', style: palette.label),
                        const SizedBox(height: 4),
                        Text(
                          'Positioned from MotionSourceBox geometry without '
                          'cancelling pointer state.',
                          style: palette.subtitle,
                        ),
                        const SizedBox(height: 10),
                        KinesisButton(
                          label: 'Close',
                          compact: true,
                          accent: palette.purple,
                          onPressed: onClose,
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
    );
  }
}
