import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class AnimatorPage extends StatelessWidget {
  const AnimatorPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _PropertyAnimatorCard(),
      SizedBox(height: 16),
      _KeyframesCard(),
    ],
  );
}

class _PropertyAnimatorCard extends StatefulWidget {
  const _PropertyAnimatorCard();

  @override
  State<_PropertyAnimatorCard> createState() => _PropertyAnimatorCardState();
}

class _PropertyAnimatorCardState extends State<_PropertyAnimatorCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late MotionAnimator _animator;
  late final MotionValue<double> _slide = MotionValue<double>(
    0,
    clock: _clock,
  );
  late final MotionValue<double> _scale = MotionValue<double>(
    1,
    clock: _clock,
  );
  late final MotionValue<double> _rotation = MotionValue<double>(
    0,
    clock: _clock,
  );
  late final MotionValue<Color> _color = MotionValue<Color>(
    const Color(0xFF007AFF),
    clock: _clock,
  );
  late final MotionValue<BorderRadius> _radius = MotionValue<BorderRadius>(
    BorderRadius.circular(14),
    clock: _clock,
  );

  String _lastEvent = 'inactive';

  @override
  void initState() {
    super.initState();
    _buildAnimator();
  }

  void _buildAnimator() {
    final t = _clock.now;
    _slide.snap(t, 0);
    _scale.snap(t, 1);
    _rotation.snap(t, 0);
    _color.snap(t, const Color(0xFF007AFF));
    _radius.snap(t, BorderRadius.circular(14));

    _animator = MotionAnimator(
      animation: const TimingCurve.easeInOut(duration: 1.2),
      clock: _clock,
      pausesOnCompletion: true,
    );
    _animator.addAnimation<double>(_slide, 1);
    _animator.addAnimation<double>(_scale, 1.32, delayFactor: 0.15);
    _animator.addAnimation<double>(_rotation, math.pi * 0.5, delayFactor: 0.25);
    _animator.addAnimation<Color>(
      _color,
      const Color(0xFFAF52DE),
      delayFactor: 0.1,
    );
    _animator.addAnimation<BorderRadius>(
      _radius,
      BorderRadius.circular(36),
      delayFactor: 0.2,
    );
    _animator.addCompletion((pos) {
      if (!mounted) return;
      setState(() => _lastEvent = 'completed at ${pos.name}');
    });
  }

  void _reset() {
    _animator.dispose();
    _buildAnimator();
    setState(() => _lastEvent = 'reset');
  }

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'MotionAnimator Scrub Deck',
      subtitle:
          'UIViewPropertyAnimator state machine with staggered delayFactor '
          'tracks (position, scale, rotation, color, BorderRadius). Scrub, '
          'pause, reverse mid-flight, or continue with a bouncy spring.',
      apis: const [
        'MotionAnimator',
        'delayFactor',
        'scrub',
        'continueWith',
        'BorderRadius',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.hairline),
            ),
            child: SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _AnimatorStagePainter(
                  slide: _slide,
                  scale: _scale,
                  rotation: _rotation,
                  color: _color,
                  radius: _radius,
                  palette: palette,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: _animator.progressListenable,
            builder: (context, frac, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KinesisSlider(
                  label: 'fractionComplete',
                  value: frac,
                  min: 0,
                  max: 1,
                  valueLabel: '${(frac * 100).round()}%',
                  accent: palette.purple,
                  onChanged: (v) {
                    if (_animator.state == MotionAnimatorState.stopped) {
                      _reset();
                    }
                    _animator.scrub(v);
                    setState(() => _lastEvent = 'scrubbed');
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'state: ${_animator.state.name}'
                  '  |  running: ${_animator.isRunning}'
                  '  |  reversed: ${_animator.isReversed}'
                  '  |  $_lastEvent',
                  style: palette.mono,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisButton(
                label: 'Play',
                filled: true,
                compact: true,
                glyph: StudioGlyph.play,
                onPressed: () {
                  if (_animator.state == MotionAnimatorState.stopped) {
                    _reset();
                  }
                  _animator.start();
                  setState(() => _lastEvent = 'started');
                },
              ),
              KinesisButton(
                label: 'Pause',
                compact: true,
                glyph: StudioGlyph.pause,
                onPressed: () {
                  _animator.pause();
                  setState(() => _lastEvent = 'paused');
                },
              ),
              KinesisButton(
                label: _animator.isReversed ? 'Forward' : 'Reverse',
                compact: true,
                glyph: StudioGlyph.reverse,
                accent: palette.purple,
                onPressed: () {
                  _animator.isReversed = !_animator.isReversed;
                  if (_animator.state == MotionAnimatorState.inactive) {
                    _animator.start();
                  }
                  setState(
                    () => _lastEvent = 'reversed=${_animator.isReversed}',
                  );
                },
              ),
              KinesisButton(
                label: 'Continue (Bouncy)',
                compact: true,
                accent: palette.orange,
                onPressed: () {
                  if (_animator.state == MotionAnimatorState.inactive) {
                    _animator.scrub(0.35);
                  }
                  if (_animator.state == MotionAnimatorState.active) {
                    _animator.continueWith(animation: Spring.bouncy);
                    setState(() => _lastEvent = 'continued with Spring.bouncy');
                  }
                },
              ),
              KinesisButton(
                label: 'Stop',
                compact: true,
                glyph: StudioGlyph.stop,
                accent: palette.red,
                onPressed: () {
                  if (_animator.state == MotionAnimatorState.active) {
                    _animator.stop(withoutFinishing: false);
                    setState(() => _lastEvent = 'stopped (awaiting finish)');
                  }
                },
              ),
              KinesisButton(
                label: 'Finish',
                compact: true,
                accent: palette.green,
                onPressed: _animator.state == MotionAnimatorState.stopped
                    ? () {
                        _animator.finish(AnimatorPosition.end);
                        setState(() {});
                      }
                    : null,
              ),
              KinesisButton(
                label: 'Reset',
                compact: true,
                onPressed: _reset,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _AnimatorStagePainter extends CustomPainter {
  _AnimatorStagePainter({
    required this.slide,
    required this.scale,
    required this.rotation,
    required this.color,
    required this.radius,
    required this.palette,
  }) : super(
         repaint: Listenable.merge([slide, scale, rotation, color, radius]),
       );

  final MotionValue<double> slide;
  final MotionValue<double> scale;
  final MotionValue<double> rotation;
  final MotionValue<Color> color;
  final MotionValue<BorderRadius> radius;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 54.0;
    const minX = pad;
    final maxX = size.width - pad;
    final cy = size.height / 2;

    canvas.drawLine(
      Offset(minX, cy),
      Offset(maxX, cy),
      Paint()
        ..color = palette.hairline
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final cx = minX + (maxX - minX) * slide.value;
    final box = 48.0 * scale.value;
    final rect = Rect.fromCenter(center: Offset.zero, width: box, height: box);
    final rrect = radius.value.toRRect(rect);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation.value);
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()..color = color.value.withValues(alpha: 0.28),
    );
    canvas.drawRRect(rrect, Paint()..color = color.value);
    canvas.drawLine(
      Offset(-box * 0.2, 0),
      Offset(box * 0.2, 0),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnimatorStagePainter oldDelegate) =>
      palette != oldDelegate.palette;
}

class _KeyframesCard extends StatefulWidget {
  const _KeyframesCard();

  @override
  State<_KeyframesCard> createState() => _KeyframesCardState();
}

class _KeyframesCardState extends State<_KeyframesCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  KeyframeMode _mode = KeyframeMode.cubic;
  bool _loop = true;

  static const _pathStops = [
    KeyframeStop<Offset>(0, Offset(-0.78, 0.35)),
    KeyframeStop<Offset>(0.25, Offset(-0.28, -0.58)),
    KeyframeStop<Offset>(0.5, Offset(0.32, 0.52)),
    KeyframeStop<Offset>(0.75, Offset(0.76, -0.42)),
    KeyframeStop<Offset>(1, Offset(-0.78, 0.35)),
  ];

  static const _colorStops = [
    KeyframeStop<Color>(0, Color(0xFF007AFF)),
    KeyframeStop<Color>(0.33, Color(0xFF34C759)),
    KeyframeStop<Color>(0.66, Color(0xFFFF9500)),
    KeyframeStop<Color>(1, Color(0xFF007AFF)),
  ];

  late final KeyframeValue<Offset> _pos = KeyframeValue<Offset>(
    _buildPath(),
    clock: _clock,
  );
  late final KeyframeValue<Color> _hue = KeyframeValue<Color>(
    _buildColor(),
    clock: _clock,
  );

  MotionKeyframes<Offset> _buildPath() => MotionKeyframes<Offset>(
    duration: 2.6,
    mode: _mode,
    repeatCount: _loop ? double.infinity : 1,
    stops: _pathStops,
  );

  MotionKeyframes<Color> _buildColor() => MotionKeyframes<Color>(
    duration: 2.6,
    mode: _mode,
    repeatCount: _loop ? double.infinity : 1,
    stops: _colorStops,
  );

  void _replay() {
    final t = _clock.now;
    _pos.play(t, keyframes: _buildPath());
    _hue.play(t, keyframes: _buildColor());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'MotionKeyframes Choreography',
      subtitle:
          'Compare Catmull-Rom cubic splines, linear segments, and discrete '
          'stepped stops driven by KeyframeValue.',
      apis: const ['MotionKeyframes', 'KeyframeMode', 'KeyframeValue'],
      trailing: KinesisSwitch(
        label: 'Loop',
        value: _loop,
        onChanged: (v) {
          _loop = v;
          _replay();
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in KeyframeMode.values)
                KinesisChip(
                  label: m.name,
                  selected: _mode == m,
                  accent: palette.teal,
                  onTap: () {
                    _mode = m;
                    _replay();
                  },
                ),
              KinesisButton(
                label: _pos.isPlaying ? 'Pause' : 'Resume',
                compact: true,
                glyph: _pos.isPlaying ? StudioGlyph.pause : StudioGlyph.play,
                onPressed: () {
                  final t = _clock.now;
                  if (_pos.isPlaying) {
                    _pos.pause(t);
                    _hue.pause(t);
                  } else {
                    _pos.resume(t);
                    _hue.resume(t);
                  }
                  setState(() {});
                },
              ),
              KinesisButton(
                label: 'Replay',
                compact: true,
                onPressed: _replay,
              ),
            ],
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.hairline),
            ),
            child: SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _KeyframeStagePainter(
                  pos: _pos,
                  hue: _hue,
                  keyframes: _pos.keyframes,
                  palette: palette,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _KeyframeStagePainter extends CustomPainter {
  _KeyframeStagePainter({
    required this.pos,
    required this.hue,
    required this.keyframes,
    required this.palette,
  }) : super(repaint: Listenable.merge([pos, hue]));

  final KeyframeValue<Offset> pos;
  final KeyframeValue<Color> hue;
  final MotionKeyframes<Offset> keyframes;
  final StudioPalette palette;

  Offset _toCanvas(Offset norm, Size size) => Offset(
    size.width * (0.5 + norm.dx * 0.46),
    size.height * (0.5 + norm.dy * 0.65),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final trail = Path();
    const steps = 100;
    for (var i = 0; i <= steps; i++) {
      final p = _toCanvas(
        keyframes.valueAt(keyframes.duration * i / steps),
        size,
      );
      if (i == 0) {
        trail.moveTo(p.dx, p.dy);
      } else {
        trail.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      trail,
      Paint()
        ..color = palette.textTertiary.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    for (final stop in keyframes.stops) {
      final p = _toCanvas(stop.value, size);
      canvas.drawCircle(p, 5, Paint()..color = palette.surface);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = palette.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final current = _toCanvas(pos.value, size);
    canvas.drawCircle(
      current,
      16,
      Paint()..color = hue.value.withValues(alpha: 0.24),
    );
    canvas.drawCircle(current, 10, Paint()..color = hue.value);
  }

  @override
  bool shouldRepaint(_KeyframeStagePainter oldDelegate) =>
      keyframes != oldDelegate.keyframes || palette != oldDelegate.palette;
}
