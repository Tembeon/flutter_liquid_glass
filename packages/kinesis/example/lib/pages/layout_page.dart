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
      StudioPageHeader(
        title: 'Fluid Layout & Overlays',
        subtitle:
            'Widgets glide smoothly when rearranged, toolbars track sliding '
            'fingers, and sheets or popovers animate with native physics.',
      ),
      _WidgetBoardCard(),
      SizedBox(height: 18),
      _DockAndOverlaysCard(),
    ],
  );
}

final class _BentoSpec {
  const _BentoSpec({
    required this.id,
    required this.title,
    required this.value,
    required this.glyph,
    required this.colorIndex,
  });

  final int id;
  final String title;
  final String value;
  final StudioGlyph glyph;
  final int colorIndex;
}

class _WidgetBoardCard extends StatefulWidget {
  const _WidgetBoardCard();

  @override
  State<_WidgetBoardCard> createState() => _WidgetBoardCardState();
}

class _WidgetBoardCardState extends State<_WidgetBoardCard> {
  final math.Random _rng = math.Random(9);
  int _nextId = 7;
  int _columns = 3;
  final List<_BentoSpec> _items = [
    const _BentoSpec(
      id: 1,
      title: 'Weather',
      value: '22 C',
      glyph: StudioGlyph.sun,
      colorIndex: 0,
    ),
    const _BentoSpec(
      id: 2,
      title: 'Battery',
      value: '94%',
      glyph: StudioGlyph.bolt,
      colorIndex: 1,
    ),
    const _BentoSpec(
      id: 3,
      title: 'Music',
      value: 'Playing',
      glyph: StudioGlyph.music,
      colorIndex: 2,
    ),
    const _BentoSpec(
      id: 4,
      title: 'Alerts',
      value: '3 New',
      glyph: StudioGlyph.bell,
      colorIndex: 3,
    ),
    const _BentoSpec(
      id: 5,
      title: 'Network',
      value: 'Wi-Fi 6E',
      glyph: StudioGlyph.wifi,
      colorIndex: 4,
    ),
    const _BentoSpec(
      id: 6,
      title: 'Favorites',
      value: '18 Saved',
      glyph: StudioGlyph.heart,
      colorIndex: 5,
    ),
  ];

  void _shuffle() => setState(() => _items.shuffle(_rng));

  void _add() {
    final id = _nextId++;
    setState(() {
      _items.insert(
        0,
        _BentoSpec(
          id: id,
          title: 'Widget #$id',
          value: 'Active',
          glyph: StudioGlyph.star,
          colorIndex: id,
        ),
      );
    });
  }

  void _remove() {
    if (_items.length <= 2) return;
    setState(_items.removeLast);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final colors = [
      palette.orange,
      palette.green,
      palette.pink,
      palette.purple,
      palette.blue,
      palette.teal,
    ];

    return StudioSurface(
      title: 'Home Widget Board',
      subtitle: 'Shuffle tiles, change columns, or add and remove widgets.',
      trailing: Wrap(
        spacing: 6,
        children: [
          for (final cols in const [1, 2, 3])
            KinesisChip(
              label: '$cols col',
              selected: _columns == cols,
              onTap: () => setState(() => _columns = cols),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MotionLayout(
            layoutBuilder: (context, children) => LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final w =
                    (constraints.maxWidth - gap * (_columns - 1)) / _columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final child in children)
                      SizedBox(width: w, height: 82, child: child),
                  ],
                );
              },
            ),
            children: [
              for (final spec in _items)
                _BentoTile(
                  key: ValueKey<int>(spec.id),
                  spec: spec,
                  accent: colors[spec.colorIndex % colors.length],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisButton(
                label: 'Shuffle',
                filled: true,
                glyph: StudioGlyph.shuffle,
                onPressed: _shuffle,
              ),
              KinesisButton(
                label: 'Add Widget',
                glyph: StudioGlyph.plus,
                accent: palette.green,
                onPressed: _add,
              ),
              KinesisButton(
                label: 'Remove',
                glyph: StudioGlyph.minus,
                accent: palette.red,
                onPressed: _items.length > 2 ? _remove : null,
              ),
            ],
          ),
          InspectorDrawer(
            apis: const ['MotionLayout', 'LayoutMotion', 'LayoutPlanner'],
            child: Text(
              'items: ${_items.length}  |  columns: $_columns  |  '
              'layout resolved after build, before paint',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({
    required this.spec,
    required this.accent,
    super.key,
  });

  final _BentoSpec spec;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: palette.isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: StudioIcon(spec.glyph, color: accent, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.title,
                    overflow: TextOverflow.ellipsis,
                    style: palette.caption,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spec.value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockAndOverlaysCard extends StatefulWidget {
  const _DockAndOverlaysCard();

  @override
  State<_DockAndOverlaysCard> createState() => _DockAndOverlaysCardState();
}

class _DockAndOverlaysCardState extends State<_DockAndOverlaysCard> {
  static const _tools = ['Select', 'Draw', 'Type', 'Export'];

  late final MotionClock _clock = MotionClockScope.of(context);
  late final InputZonesController<int> _zonesController =
      InputZonesController<int>();
  late final MotionValue<double> _activeX = MotionValue<double>(
    0,
    clock: _clock,
  );
  final ChangeNotifier _frames = ChangeNotifier();
  final MotionSource _popoverSource = MotionSource();
  final PresentationPortalController _portal = PresentationPortalController();

  int _selectedTool = 0;
  String? _lastAction;

  Future<void> _openSheet() async {
    final palette = StudioTheme.of(context);
    final result = await showPresentation<String>(
      context,
      PresentationRoute<String>(
        semanticsLabel: 'Share Sheet',
        presentation: Presentation<String, _SheetMotion>(
          motion: (env) => _SheetMotion(clock: env.clock),
          dismiss: DismissPolicy.modal,
          dim: (motion) => 0.34 * motion.opacity,
          barrierLabel: 'Dismiss sheet',
          builder: (context, motion) => _ShareSheetBody(
            motion: motion,
            palette: palette,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _lastAction = result ?? 'Dismissed sheet');
  }

  @override
  void dispose() {
    _zonesController.dispose();
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioSurface(
      title: 'Sliding Dock & Presentations',
      subtitle:
          'Press and glide across the toolbar without lifting, or launch a '
          'draggable bottom sheet and anchored quick menu.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final zoneW = constraints.maxWidth / _tools.length;
              return InputZones<int>(
                controller: _zonesController,
                activatesOnMove: true,
                frames: _frames,
                current: _selectedTool,
                frameOf: (id) => InputZoneFrame(
                  Rect.fromLTWH(id * zoneW, 0, zoneW, 48),
                  radius: BorderRadius.circular(12),
                ),
                feedback: (id, event) =>
                    event is ActivationEvent ? MotionHaptic.selection : null,
                zones: [
                  for (var i = 0; i < _tools.length; i++)
                    InputZone<int>(
                      id: i,
                      interactions: [
                        TapInteraction(
                          onTap: (t) {
                            if (_selectedTool != i) {
                              setState(() => _selectedTool = i);
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
                        selected: _selectedTool == i,
                        label: _tools[i],
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
                              count: _tools.length,
                              color: palette.blue,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _tools.length; i++)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    _tools[i],
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: _selectedTool == i
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
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KinesisButton(
                label: 'Open Share Sheet',
                filled: true,
                glyph: StudioGlyph.share,
                onPressed: _openSheet,
              ),
              PresentationPortal(
                controller: _portal,
                presentation: Presentation<void, _PopoverMotion>(
                  source: _popoverSource,
                  dismissesOnOutsideTap: true,
                  motion: (env) => _PopoverMotion(clock: env.clock),
                  builder: (context, motion) => _QuickMenuPopover(
                    motion: motion,
                    palette: palette,
                    onPick: (choice) {
                      _portal.dismiss(DismissTrigger.programmatic);
                      setState(() => _lastAction = choice);
                    },
                  ),
                ),
                child: MotionSourceBox(
                  source: _popoverSource,
                  radius: BorderRadius.circular(12),
                  child: KinesisButton(
                    label: 'Quick Actions Menu',
                    glyph: StudioGlyph.menu,
                    accent: palette.purple,
                    onPressed: _portal.present,
                  ),
                ),
              ),
              if (_lastAction case final text?)
                Text(text, style: palette.subtitle),
            ],
          ),
          InspectorDrawer(
            apis: const [
              'InputZones',
              'PresentationRoute',
              'PresentationPortal',
              'MotionSourceBox',
            ],
            child: Text(
              'active tool: ${_tools[_selectedTool]}  |  '
              'last overlay action: ${_lastAction ?? 'none'}',
              style: palette.mono,
            ),
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

class _ShareSheetBody extends StatefulWidget {
  const _ShareSheetBody({
    required this.motion,
    required this.palette,
  });

  final _SheetMotion motion;
  final StudioPalette palette;

  @override
  State<_ShareSheetBody> createState() => _ShareSheetBodyState();
}

class _ShareSheetBodyState extends State<_ShareSheetBody> {
  late final DragInteraction _drag = DragInteraction(
    axis: Axis.vertical,
    slop: 0,
    onUpdate: (d) => widget.motion.dragUpdate(d.time, d.translation.dy),
    onEnd: (d) => widget.motion.dragEnd(
      d.time,
      d.velocity.dy,
      () => Navigator.of(context).pop('Swiped sheet away'),
    ),
    onCancel: (t) => widget.motion.dragEnd(t, 0, () {}),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return StudioTheme(
      palette: p,
      inspector: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: MotionTransition(
              translateY: widget.motion.translateY,
              opacity: widget.motion.opacityListenable,
              child: InputRegion(
                interactions: [_drag],
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: p.hairline),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x38000000),
                        blurRadius: 32,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
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
                            child: const SizedBox(width: 42, height: 5),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('Share Project', style: p.title),
                        const SizedBox(height: 6),
                        Text(
                          'Drag down to dismiss, press Escape, or choose a '
                          'destination below.',
                          style: p.subtitle,
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            KinesisButton(
                              label: 'Send via AirDrop',
                              filled: true,
                              glyph: StudioGlyph.wifi,
                              onPressed: () =>
                                  Navigator.of(context).pop('Sent via AirDrop'),
                            ),
                            KinesisButton(
                              label: 'Copy Link',
                              accent: p.green,
                              onPressed: () =>
                                  Navigator.of(context).pop('Copied link'),
                            ),
                            KinesisButton(
                              label: 'Cancel',
                              accent: p.red,
                              onPressed: () =>
                                  Navigator.of(context).pop('Cancelled'),
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
    (m) => 0.78 + 0.22 * m.progress,
  );
  late final ValueListenable<double> opacityListenable = select(
    (m) => m.opacity,
  );
}

class _QuickMenuPopover extends StatelessWidget {
  const _QuickMenuPopover({
    required this.motion,
    required this.palette,
    required this.onPick,
  });

  final _PopoverMotion motion;
  final StudioPalette palette;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final anchor = motion.source?.rect;
    final left = anchor != null ? math.max<double>(16, anchor.left) : 24.0;
    final top = anchor != null ? math.max<double>(16, anchor.top - 154) : 120.0;

    return StudioTheme(
      palette: palette,
      inspector: false,
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
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.hairline),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: 210,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (label, glyph, color) in [
                          ('Duplicate', StudioGlyph.plus, palette.blue),
                          ('Favorite', StudioGlyph.heart, palette.pink),
                          ('Share...', StudioGlyph.share, palette.purple),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: KinesisButton(
                              label: label,
                              glyph: glyph,
                              accent: color,
                              compact: true,
                              onPressed: () => onPick('Picked: $label'),
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
    );
  }
}
