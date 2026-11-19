import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class SpringsPage extends StatelessWidget {
  const SpringsPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _MagneticArenaCard(),
      SizedBox(height: 16),
      _SpringLabCard(),
    ],
  );
}

class _MagneticArenaCard extends StatefulWidget {
  const _MagneticArenaCard();

  @override
  State<_MagneticArenaCard> createState() => _MagneticArenaCardState();
}

class _MagneticArenaCardState extends State<_MagneticArenaCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<Offset> _puck = MotionValue<Offset>(
    Offset.zero,
    clock: _clock,
  );
  late final MotionValue<double> _puckScale = MotionValue<double>(
    1,
    clock: _clock,
  );
  final ValueNotifier<Offset?> _predictedLanding = ValueNotifier<Offset?>(null);
  final ValueNotifier<int> _activeDock = ValueNotifier<int>(4);

  Size _arenaSize = const Size(320, 220);
  Offset _dragStartPuck = Offset.zero;
  bool _showVector = true;

  List<Offset> _dockPositions(Size size) {
    final hx = math.max<double>(40, size.width / 2 - 48);
    final hy = math.max<double>(36, size.height / 2 - 42);
    return [
      Offset(-hx, -hy),
      Offset(hx, -hy),
      Offset(-hx, hy),
      Offset(hx, hy),
      Offset.zero,
    ];
  }

  late final DragInteraction _drag = DragInteraction(
    slop: 0,
    onStart: (details) {
      _dragStartPuck = _puck.valueAt(details.time);
      _predictedLanding.value = null;
      withSpring(Spring.snappy, () => _puckScale.retarget(details.time, 1.16));
    },
    onUpdate: (details) {
      final raw = _dragStartPuck + details.translation;
      final hx = math.max<double>(40, _arenaSize.width / 2 - 34);
      final hy = math.max<double>(36, _arenaSize.height / 2 - 34);
      final bx = RubberBand(-hx, hx, dimension: hx * 0.9);
      final by = RubberBand(-hy, hy, dimension: hy * 0.9);
      _puck.snap(details.time, Offset(bx.apply(raw.dx), by.apply(raw.dy)));
      final proj = Projection.of(Spring.bouncy);
      _predictedLanding.value = Offset(
        proj.landing(_puck.valueAt(details.time).dx, details.velocity.dx),
        proj.landing(_puck.valueAt(details.time).dy, details.velocity.dy),
      );
    },
    onEnd: (details) {
      final t = details.time;
      final pos = _puck.valueAt(t);
      final vel = details.velocity;
      final proj = Projection.of(Spring.bouncy);
      final land = Offset(
        proj.landing(pos.dx, vel.dx),
        proj.landing(pos.dy, vel.dy),
      );
      _predictedLanding.value = land;
      final docks = _dockPositions(_arenaSize);
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < docks.length; i++) {
        final d = (docks[i] - land).distance;
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      _activeDock.value = best;
      MotionHaptic.selection.play(context);
      _puck.setVelocity(t, vel);
      withSpring(Spring.bouncy, () {
        _puck.retarget(t, docks[best]);
        _puckScale.retarget(t, 1);
      });
    },
    onCancel: (t) {
      withSpring(Spring.bouncy, () {
        _puck.retarget(t, Offset.zero);
        _puckScale.retarget(t, 1);
      });
    },
  );

  void _sendToDock(int index) {
    final docks = _dockPositions(_arenaSize);
    _activeDock.value = index;
    _predictedLanding.value = docks[index];
    withSpring(Spring.bouncy, () => _puck.retarget(_clock.now, docks[index]));
  }

  @override
  void dispose() {
    _predictedLanding.dispose();
    _activeDock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'Magnetic Dock Arena',
      subtitle:
          'Drag and fling the puck toward any corner. Projection predicts the '
          'landing dock from release velocity, RubberBand resists the edges, '
          'and grabbing mid-flight interrupts smoothly.',
      apis: const [
        'MotionValue<Offset>',
        'DragInteraction',
        'Projection.of',
        'RubberBand',
      ],
      trailing: KinesisSwitch(
        label: 'Vector',
        value: _showVector,
        accent: palette.orange,
        onChanged: (v) => setState(() => _showVector = v),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              _arenaSize = Size(constraints.maxWidth, 230);
              final docks = _dockPositions(_arenaSize);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.well,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.hairline),
                ),
                child: SizedBox(
                  height: _arenaSize.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ArenaPainter(
                              puck: _puck,
                              predicted: _predictedLanding,
                              activeDock: _activeDock,
                              docks: docks,
                              showVector: _showVector,
                              palette: palette,
                            ),
                          ),
                        ),
                        InputRegion(
                          interactions: [_drag],
                          semantics: const SemanticsProperties(
                            label: 'Magnetic puck',
                            hint: 'Drag and fling toward any dock',
                          ),
                          child: MotionTransition(
                            offset: _puck,
                            scale: _puckScale,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [palette.orange, palette.red],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.orange.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const SizedBox.square(
                                dimension: 54,
                                child: Center(
                                  child: StudioIcon(
                                    StudioGlyph.spring,
                                    color: Color(0xFFFFFFFF),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, name) in const [
                (0, 'Top Left'),
                (1, 'Top Right'),
                (2, 'Bottom Left'),
                (3, 'Bottom Right'),
                (4, 'Center'),
              ])
                KinesisButton(
                  label: name,
                  compact: true,
                  accent: palette.orange,
                  onPressed: () => _sendToDock(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ArenaPainter extends CustomPainter {
  _ArenaPainter({
    required this.puck,
    required this.predicted,
    required this.activeDock,
    required this.docks,
    required this.showVector,
    required this.palette,
  }) : super(repaint: Listenable.merge([puck, predicted, activeDock]));

  final MotionValue<Offset> puck;
  final ValueNotifier<Offset?> predicted;
  final ValueNotifier<int> activeDock;
  final List<Offset> docks;
  final bool showVector;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final gridPaint = Paint()
      ..color = palette.hairline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, 14),
      Offset(center.dx, size.height - 14),
      gridPaint,
    );
    canvas.drawLine(
      Offset(14, center.dy),
      Offset(size.width - 14, center.dy),
      gridPaint,
    );

    for (var i = 0; i < docks.length; i++) {
      final pos = center + docks[i];
      final active = activeDock.value == i;
      canvas.drawCircle(
        pos,
        active ? 18 : 13,
        Paint()
          ..color = active
              ? palette.orange.withValues(alpha: 0.16)
              : palette.hairline,
      );
      canvas.drawCircle(
        pos,
        active ? 18 : 13,
        Paint()
          ..color = active ? palette.orange : palette.textTertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2 : 1.2,
      );
    }

    if (showVector) {
      final current = center + puck.value;
      final landOffset = predicted.value;
      if (landOffset != null) {
        final target = Offset(
          (center.dx + landOffset.dx).clamp(12.0, size.width - 12),
          (center.dy + landOffset.dy).clamp(12.0, size.height - 12),
        );
        canvas.drawLine(
          current,
          target,
          Paint()
            ..color = palette.blue.withValues(alpha: 0.65)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(target, 5, Paint()..color = palette.blue);
      }
    }
  }

  @override
  bool shouldRepaint(_ArenaPainter oldDelegate) =>
      showVector != oldDelegate.showVector || palette != oldDelegate.palette;
}

enum _CurvePreset { snappy, bouncy, smooth, keyboard, easeInOut, additive }

class _SpringLabCard extends StatefulWidget {
  const _SpringLabCard();

  @override
  State<_SpringLabCard> createState() => _SpringLabCardState();
}

class _SpringLabCardState extends State<_SpringLabCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _trackX = MotionValue<double>(
    0,
    clock: _clock,
  );
  late final MotionValue<double> _cardTilt = MotionValue<double>(
    0,
    clock: _clock,
  );

  _CurvePreset _preset = _CurvePreset.bouncy;
  double _response = Spring.bouncy.response;
  double _dampingRatio = Spring.bouncy.dampingRatio;
  bool _atRight = false;
  int _stageBuilds = 0;

  MotionAnimation get _animation => switch (_preset) {
    _CurvePreset.easeInOut => const TimingCurve.easeInOut(duration: 0.45),
    _CurvePreset.additive => const TimingCurve.easeInOut(
      duration: 0.55,
      additive: true,
    ),
    _ => Spring.response(_response, dampingRatio: _dampingRatio),
  };

  void _selectPreset(_CurvePreset preset) {
    setState(() {
      _preset = preset;
      switch (preset) {
        case _CurvePreset.snappy:
          _response = Spring.snappy.response;
          _dampingRatio = Spring.snappy.dampingRatio;
        case _CurvePreset.bouncy:
          _response = Spring.bouncy.response;
          _dampingRatio = Spring.bouncy.dampingRatio;
        case _CurvePreset.smooth:
          _response = Spring.smooth.response;
          _dampingRatio = Spring.smooth.dampingRatio;
        case _CurvePreset.keyboard:
          _response = Spring.keyboard.response;
          _dampingRatio = Spring.keyboard.dampingRatio;
        case _CurvePreset.easeInOut || _CurvePreset.additive:
          break;
      }
    });
  }

  void _retarget() {
    _atRight = !_atRight;
    final t = _clock.now;
    _trackX.animate(t, _atRight ? 1 : 0, animation: _animation);
    _cardTilt.animate(t, _atRight ? 0.14 : -0.14, animation: _animation);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final anim = _animation;
    final isSpring = anim is Spring;

    return StudioCard(
      title: 'Spring & TimingCurve Tuner',
      subtitle:
          'Tune response and dampingRatio live, compare UIKit Spring vs '
          'TimingCurve (including additive curve stacking), and retarget '
          'rapidly mid-flight with zero widget rebuilds.',
      apis: const [
        'Spring',
        'Spring.settlingDuration',
        'TimingCurve',
        'withAnimation',
      ],
      trailing: ZeroRebuildBadge(builds: _stageBuilds + 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (p, name) in const [
                (_CurvePreset.snappy, 'snappy'),
                (_CurvePreset.bouncy, 'bouncy'),
                (_CurvePreset.smooth, 'smooth'),
                (_CurvePreset.keyboard, 'keyboard'),
                (_CurvePreset.easeInOut, 'easeInOut'),
                (_CurvePreset.additive, 'additive'),
              ])
                KinesisChip(
                  label: name,
                  selected: _preset == p,
                  onTap: () => _selectPreset(p),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (isSpring) ...[
            KinesisSlider(
              label: 'response',
              value: _response,
              min: 0.15,
              max: 1.2,
              valueLabel: '${_response.toStringAsFixed(2)} s',
              onChanged: (v) => setState(() => _response = v),
            ),
            const SizedBox(height: 10),
            KinesisSlider(
              label: 'dampingRatio',
              value: _dampingRatio,
              min: 0.2,
              max: 1.2,
              valueLabel: _dampingRatio.toStringAsFixed(2),
              accent: palette.purple,
              onChanged: (v) => setState(() => _dampingRatio = v),
            ),
            const SizedBox(height: 12),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 105,
                    child: CustomPaint(
                      painter: _CurvePlotPainter(
                        animation: anim,
                        palette: palette,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSpring
                        ? 'settling: '
                              '${anim.settlingDuration.toStringAsFixed(2)}s'
                              '  |  k=${anim.stiffness.toStringAsFixed(0)}'
                              '  |  c=${anim.damping.toStringAsFixed(1)}'
                        : 'TimingCurve  |  duration: '
                              '${(anim as TimingCurve).duration}s'
                              '  |  additive: ${anim.additive}',
                    style: palette.mono,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              _stageBuilds++;
              return InputRegion(
                interactions: [TapInteraction(onTap: (_) => _retarget())],
                feedback: (event) =>
                    event is ActivationEvent ? MotionHaptic.lightImpact : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.well,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.hairline),
                  ),
                  child: SizedBox(
                    height: 76,
                    child: CustomPaint(
                      painter: _RunwayPainter(
                        progress: _trackX,
                        tilt: _cardTilt,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              KinesisButton(
                label: 'Retarget Mid-Flight',
                filled: true,
                glyph: StudioGlyph.spring,
                onPressed: _retarget,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tap rapidly to interrupt and watch velocity carry through.',
                  style: palette.subtitle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _CurvePlotPainter extends CustomPainter {
  const _CurvePlotPainter({
    required this.animation,
    required this.palette,
  });

  final MotionAnimation animation;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const padV = 16.0;
    final y0 = size.height - padV;
    const y1 = padV + 18;

    final targetPaint = Paint()
      ..color = palette.green.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, y1), Offset(size.width, y1), targetPaint);
    canvas.drawLine(
      Offset(0, y0),
      Offset(size.width, y0),
      Paint()
        ..color = palette.hairline
        ..strokeWidth = 1,
    );

    final totalT = switch (animation) {
      final Spring s => math.max(0.6, s.settlingDuration),
      final TimingCurve c => math.max(0.6, c.duration),
    };
    final sim = switch (animation) {
      final Spring s => SpringSimulation(s.description, 0, 1, 0),
      TimingCurve() => null,
    };

    final path = Path();
    const samples = 120;
    for (var i = 0; i <= samples; i++) {
      final frac = i / samples;
      final t = frac * totalT;
      final val = switch (animation) {
        Spring() => sim!.x(t),
        final TimingCurve c => c.progressAt(t),
      };
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
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePlotPainter oldDelegate) =>
      animation != oldDelegate.animation || palette != oldDelegate.palette;
}

final class _RunwayPainter extends CustomPainter {
  _RunwayPainter({
    required this.progress,
    required this.tilt,
    required this.palette,
  }) : super(repaint: Listenable.merge([progress, tilt]));

  final MotionValue<double> progress;
  final MotionValue<double> tilt;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const boxW = 54.0;
    const boxH = 44.0;
    const pad = 22.0;
    const minX = pad + boxW / 2;
    final maxX = size.width - pad - boxW / 2;
    final cy = size.height / 2;

    canvas.drawLine(
      Offset(minX, cy),
      Offset(maxX, cy),
      Paint()
        ..color = palette.hairline
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(minX, cy),
      4,
      Paint()..color = palette.textTertiary,
    );
    canvas.drawCircle(
      Offset(maxX, cy),
      4,
      Paint()..color = palette.textTertiary,
    );

    final cx = minX + (maxX - minX) * progress.value;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt.value);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: boxW, height: boxH),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 3)),
      Paint()..color = palette.blue.withValues(alpha: 0.25),
    );
    canvas.drawRRect(rrect, Paint()..color = palette.blue);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RunwayPainter oldDelegate) =>
      palette != oldDelegate.palette;
}
