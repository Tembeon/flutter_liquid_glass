import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

enum _FeelPreset { snappy, bouncy, smooth, keyboard, custom }

class SpringsPage extends StatefulWidget {
  const SpringsPage({super.key});

  @override
  State<SpringsPage> createState() => _SpringsPageState();
}

class _SpringsPageState extends State<SpringsPage> {
  static const Size _pipSize = Size(168, 102);

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<Offset> _pipOffset = MotionValue<Offset>(
    const Offset(96, -86),
    clock: _clock,
  );
  late final MotionValue<double> _pipScale = MotionValue<double>(
    1,
    clock: _clock,
  );
  final ValueNotifier<Offset?> _predicted = ValueNotifier<Offset?>(null);
  final ValueNotifier<int> _activeCorner = ValueNotifier<int>(1);

  _FeelPreset _preset = _FeelPreset.bouncy;
  double _response = Spring.bouncy.response;
  double _dampingRatio = Spring.bouncy.dampingRatio;
  bool _playing = true;
  Size _stageSize = const Size(520, 340);
  Offset _dragStart = Offset.zero;
  int _pipBuilds = 0;

  Spring get _spring => switch (_preset) {
    _FeelPreset.snappy => Spring.snappy,
    _FeelPreset.bouncy => Spring.bouncy,
    _FeelPreset.smooth => Spring.smooth,
    _FeelPreset.keyboard => Spring.keyboard,
    _FeelPreset.custom => Spring.response(
      _response,
      dampingRatio: _dampingRatio,
    ),
  };

  List<Offset> _corners(Size size) {
    const margin = 20.0;
    final hx = math.max<double>(24, (size.width - _pipSize.width) / 2 - margin);
    final hy = math.max<double>(
      24,
      (size.height - _pipSize.height) / 2 - margin,
    );
    return [
      Offset(-hx, -hy),
      Offset(hx, -hy),
      Offset(-hx, hy),
      Offset(hx, hy),
    ];
  }

  late final DragInteraction _drag = DragInteraction(
    slop: 0,
    onStart: (details) {
      _dragStart = _pipOffset.valueAt(details.time);
      _predicted.value = null;
      withSpring(Spring.snappy, () => _pipScale.retarget(details.time, 1.07));
    },
    onUpdate: (details) {
      final raw = _dragStart + details.translation;
      const margin = 16.0;
      final hx = math.max<double>(
        24,
        (_stageSize.width - _pipSize.width) / 2 - margin,
      );
      final hy = math.max<double>(
        24,
        (_stageSize.height - _pipSize.height) / 2 - margin,
      );
      final bx = RubberBand(-hx, hx, dimension: hx);
      final by = RubberBand(-hy, hy, dimension: hy);
      final shown = Offset(bx.apply(raw.dx), by.apply(raw.dy));
      _pipOffset.snap(details.time, shown);
      final proj = Projection.of(_spring);
      _predicted.value = Offset(
        proj.landing(shown.dx, details.velocity.dx),
        proj.landing(shown.dy, details.velocity.dy),
      );
    },
    onEnd: (details) {
      final t = details.time;
      final pos = _pipOffset.valueAt(t);
      final vel = details.velocity;
      final proj = Projection.of(_spring);
      final land = Offset(
        proj.landing(pos.dx, vel.dx),
        proj.landing(pos.dy, vel.dy),
      );
      _predicted.value = land;
      final corners = _corners(_stageSize);
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < corners.length; i++) {
        final d = (corners[i] - land).distance;
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      _activeCorner.value = best;
      MotionHaptic.selection.play(context);
      _pipOffset.setVelocity(t, vel);
      withSpring(_spring, () {
        _pipOffset.retarget(t, corners[best]);
        _pipScale.retarget(t, 1);
      });
    },
    onCancel: (t) {
      final corners = _corners(_stageSize);
      withSpring(_spring, () {
        _pipOffset.retarget(t, corners[_activeCorner.value]);
        _pipScale.retarget(t, 1);
      });
    },
  );

  void _selectPreset(_FeelPreset preset) {
    setState(() {
      _preset = preset;
      final s = _spring;
      _response = s.response;
      _dampingRatio = s.dampingRatio;
    });
    _hopToNextCorner();
  }

  void _hopToNextCorner() {
    final next = (_activeCorner.value + 1) % 4;
    final corners = _corners(_stageSize);
    _activeCorner.value = next;
    _predicted.value = corners[next];
    withSpring(_spring, () => _pipOffset.retarget(_clock.now, corners[next]));
  }

  @override
  void dispose() {
    _predicted.dispose();
    _activeCorner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final inspect = StudioTheme.inspectorOf(context);
    final spring = _spring;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioPageHeader(
          title: 'Picture-in-Picture',
          subtitle:
              'Drag and toss the floating video player toward any corner. '
              'Catch it mid-flight to feel velocity-preserving interruption.',
          trailing: KinesisButton(
            label: 'Toss Corner',
            filled: true,
            glyph: StudioGlyph.pip,
            onPressed: _hopToNextCorner,
          ),
        ),
        StudioSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final nextSize = Size(constraints.maxWidth, 340);
                  final firstLayout = _stageSize.width != nextSize.width;
                  _stageSize = nextSize;
                  final corners = _corners(_stageSize);
                  if (firstLayout) {
                    _pipOffset.snap(_clock.now, corners[_activeCorner.value]);
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: _stageSize.height,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: palette.isDark
                                      ? const [
                                          Color(0xFF15192B),
                                          Color(0xFF1D152C),
                                          Color(0xFF121822),
                                        ]
                                      : const [
                                          Color(0xFFE6EEFF),
                                          Color(0xFFF3E8FF),
                                          Color(0xFFE8F6F8),
                                        ],
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PipBackdropPainter(
                                offset: _pipOffset,
                                predicted: _predicted,
                                activeCorner: _activeCorner,
                                corners: corners,
                                pipSize: _pipSize,
                                showVector: inspect,
                                palette: palette,
                              ),
                            ),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.surface.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: palette.hairline),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              child: Text(
                                'Toss the player into any corner',
                                style: palette.caption,
                              ),
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              _pipBuilds++;
                              return InputRegion(
                                interactions: [_drag],
                                semantics: const SemanticsProperties(
                                  label: 'Floating video player',
                                  hint: 'Drag and release toward a corner',
                                ),
                                child: MotionTransition(
                                  offset: _pipOffset,
                                  scale: _pipScale,
                                  child: _PipPlayerWindow(
                                    size: _pipSize,
                                    playing: _playing,
                                    onTogglePlay: () =>
                                        setState(() => _playing = !_playing),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (p, label) in const [
                    (_FeelPreset.snappy, 'Snappy'),
                    (_FeelPreset.bouncy, 'Bouncy'),
                    (_FeelPreset.smooth, 'Smooth'),
                    (_FeelPreset.keyboard, 'Keyboard'),
                  ])
                    KinesisChip(
                      label: label,
                      selected: _preset == p,
                      onTap: () => _selectPreset(p),
                    ),
                ],
              ),
              InspectorDrawer(
                apis: const [
                  'Spring',
                  'MotionValue<Offset>',
                  'Projection.of',
                  'RubberBand',
                  'DragInteraction',
                ],
                builds: _pipBuilds,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 88,
                      child: CustomPaint(
                        painter: _SpringPlotPainter(
                          spring: spring,
                          palette: palette,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    KinesisSlider(
                      label: 'Response',
                      value: _response,
                      min: 0.16,
                      max: 1.1,
                      valueLabel: '${_response.toStringAsFixed(2)} s',
                      onChanged: (v) => setState(() {
                        _preset = _FeelPreset.custom;
                        _response = v;
                      }),
                    ),
                    const SizedBox(height: 8),
                    KinesisSlider(
                      label: 'Damping Ratio',
                      value: _dampingRatio,
                      min: 0.25,
                      max: 1.15,
                      valueLabel: _dampingRatio.toStringAsFixed(2),
                      accent: palette.purple,
                      onChanged: (v) => setState(() {
                        _preset = _FeelPreset.custom;
                        _dampingRatio = v;
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'settlingDuration: '
                      '${spring.settlingDuration.toStringAsFixed(2)}s  |  '
                      'stiffness: ${spring.stiffness.toStringAsFixed(0)}  |  '
                      'damping: ${spring.damping.toStringAsFixed(1)}',
                      style: palette.mono,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PipPlayerWindow extends StatelessWidget {
  const _PipPlayerWindow({
    required this.size,
    required this.playing,
    required this.onTogglePlay,
  });

  final Size size;
  final bool playing;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED), Color(0xFFEC4899)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x44FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44000000),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x44000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFFF453A),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(dimension: 6),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Text(
                  '02:14',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Color(0xDDFFFFFF),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keynote',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                      Text(
                        'Fluid Motion',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InputRegion(
                  interactions: [TapInteraction(onTap: (_) => onTogglePlay())],
                  semantics: SemanticsProperties(
                    button: true,
                    label: playing ? 'Pause video' : 'Play video',
                  ),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0x38FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: StudioIcon(
                        playing ? StudioGlyph.pause : StudioGlyph.play,
                        color: const Color(0xFFFFFFFF),
                        size: 13,
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
}

final class _PipBackdropPainter extends CustomPainter {
  _PipBackdropPainter({
    required this.offset,
    required this.predicted,
    required this.activeCorner,
    required this.corners,
    required this.pipSize,
    required this.showVector,
    required this.palette,
  }) : super(repaint: Listenable.merge([offset, predicted, activeCorner]));

  final MotionValue<Offset> offset;
  final ValueNotifier<Offset?> predicted;
  final ValueNotifier<int> activeCorner;
  final List<Offset> corners;
  final Size pipSize;
  final bool showVector;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (var i = 0; i < corners.length; i++) {
      final active = activeCorner.value == i;
      final rect = Rect.fromCenter(
        center: center + corners[i],
        width: pipSize.width,
        height: pipSize.height,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = active
              ? palette.blue.withValues(alpha: palette.isDark ? 0.14 : 0.08)
              : palette.hairline.withValues(alpha: 0.04),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = active
              ? palette.blue.withValues(alpha: 0.35)
              : palette.hairline
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 1.5 : 1,
      );
    }

    if (showVector) {
      final current = center + offset.value;
      if (predicted.value case final land?) {
        final clamped = Offset(
          (center.dx + land.dx).clamp(16.0, size.width - 16),
          (center.dy + land.dy).clamp(16.0, size.height - 16),
        );
        canvas.drawLine(
          current,
          clamped,
          Paint()
            ..color = palette.orange
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(clamped, 5.5, Paint()..color = palette.orange);
      }
    }
  }

  @override
  bool shouldRepaint(_PipBackdropPainter oldDelegate) =>
      showVector != oldDelegate.showVector || palette != oldDelegate.palette;
}

final class _SpringPlotPainter extends CustomPainter {
  const _SpringPlotPainter({required this.spring, required this.palette});

  final Spring spring;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const padV = 12.0;
    final y0 = size.height - padV;
    const y1 = padV + 16;

    canvas.drawLine(
      const Offset(0, y1),
      Offset(size.width, y1),
      Paint()
        ..color = palette.green.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, y0),
      Offset(size.width, y0),
      Paint()
        ..color = palette.hairline
        ..strokeWidth = 1,
    );

    final totalT = math.max(0.6, spring.settlingDuration);
    final sim = SpringSimulation(spring.description, 0, 1, 0);
    final path = Path();
    const samples = 100;
    for (var i = 0; i <= samples; i++) {
      final frac = i / samples;
      final val = sim.x(frac * totalT);
      final x = frac * size.width;
      final y = y0 - (y0 - y1) * val;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = palette.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpringPlotPainter oldDelegate) =>
      spring != oldDelegate.spring || palette != oldDelegate.palette;
}
