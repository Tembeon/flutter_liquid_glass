import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class TimelinesDemo extends StatefulWidget {
  const TimelinesDemo({super.key});

  @override
  State<TimelinesDemo> createState() => _TimelinesDemoState();
}

class _TimelinesDemoState extends State<TimelinesDemo> {
  static const _pop = MotionKeyframes<double>(
    duration: 0.45,
    mode: KeyframeMode.cubic,
    stops: [
      KeyframeStop(0, 1),
      KeyframeStop(0.3, 1.25),
      KeyframeStop(0.65, 0.92),
      KeyframeStop(1, 1),
    ],
  );

  static const _shake = MotionKeyframes<double>(
    duration: 0.5,
    stops: [
      KeyframeStop(0, 0),
      KeyframeStop(0.12, -14),
      KeyframeStop(0.3, 12),
      KeyframeStop(0.48, -9),
      KeyframeStop(0.66, 6),
      KeyframeStop(0.84, -3),
      KeyframeStop(1, 0),
    ],
  );

  static const _tick = MotionKeyframes<double>(
    duration: 0.8,
    mode: KeyframeMode.discrete,
    stops: [
      KeyframeStop(0, 0),
      KeyframeStop(0.25, pi / 2),
      KeyframeStop(0.5, pi),
      KeyframeStop(0.75, 3 * pi / 2),
      KeyframeStop(1, 2 * pi),
    ],
  );

  static const _breathe = MotionKeyframes<double>(
    duration: 1.2,
    curve: TimingCurve.uikitEaseInOut,
    repeatCount: double.infinity,
    autoreverses: true,
    stops: [KeyframeStop(0, 1), KeyframeStop(1, 1.18)],
  );

  final _popValue = KeyframeValue(_pop, playing: false);
  final _shakeValue = KeyframeValue(_shake, playing: false);
  final _tickValue = KeyframeValue(_tick, playing: false);
  final _breatheValue = KeyframeValue(_breathe, playing: false);

  final _x = MotionValue<double>(0);
  final _turn = MotionValue<double>(0);
  late MotionAnimator _animator = _newAnimator();
  double _scrubFrom = 0;
  double _barWidth = 1;

  late final _scrub = DragInteraction(
    axis: Axis.horizontal,
    onStart: (_) {
      if (_animator.isRunning) _animator.pause();
      _scrubFrom = _animator.fractionComplete;
    },
    onUpdate: (details) => _animator.fractionComplete =
        (_scrubFrom + details.translation.dx / _barWidth).clamp(0.0, 1.0),
  );

  MotionAnimator _newAnimator() {
    final animator = MotionAnimator(
      animation: const TimingCurve.easeInOut(duration: 1.6),
      pausesOnCompletion: true,
    );
    animator.addAnimation(_x, 1);
    animator.addAnimation(_turn, pi);
    return animator;
  }

  void _play(KeyframeValue<double> value) => value.play(value.clock.now);

  void _toggleBreathe() {
    final now = _breatheValue.clock.now;
    if (_breatheValue.isPlaying) {
      _breatheValue.pause(now);
    } else {
      _breatheValue.resume(now);
    }
    setState(() {});
  }

  void _reverse() {
    _animator.isReversed = !_animator.isReversed;
    if (!_animator.isRunning) _animator.start();
  }

  void _reset() {
    if (_animator.state == MotionAnimatorState.active) {
      _animator.stop(withoutFinishing: false);
      _animator.finish(AnimatorPosition.start);
    }
    _animator.dispose();
    setState(() => _animator = _newAnimator());
  }

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'MotionKeyframes describes a timeline of values; a KeyframeValue '
          'plays it as a listenable. MotionAnimator runs several values on '
          'one curve that you can pause, scrub and reverse.',
      children: [
        Section(
          title: 'Keyframes',
          caption:
              'Tap a tile. Cubic keyframes pass smoothly through their stops, '
              'linear ones go straight, discrete ones jump.',
          stage: SizedBox(
            height: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _KeyframeTile(
                  label: 'cubic',
                  onTap: () => _play(_popValue),
                  child: MotionTransition(
                    scale: _popValue,
                    child: Tile(color: palette.swatches[0]),
                  ),
                ),
                _KeyframeTile(
                  label: 'linear',
                  onTap: () => _play(_shakeValue),
                  child: MotionTransition(
                    translateX: _shakeValue,
                    child: Tile(color: palette.swatches[1]),
                  ),
                ),
                _KeyframeTile(
                  label: 'discrete',
                  onTap: () => _play(_tickValue),
                  child: MotionTransition(
                    rotation: _tickValue,
                    child: Tile(color: palette.swatches[2], label: 'K'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Section(
          title: 'Repeat and autoreverse',
          caption:
              'A timeline can repeat forever and play every other cycle '
              'backward. Pause holds it where it is; play goes on from there.',
          stage: SizedBox(
            height: 96,
            child: Center(
              child: MotionTransition(
                scale: _breatheValue,
                child: Dot(color: palette.swatches[5], size: 56),
              ),
            ),
          ),
          controls: [
            PushButton(
              _breatheValue.isPlaying ? 'Pause' : 'Play',
              onPressed: _toggleBreathe,
            ),
          ],
        ),
        Section(
          title: 'MotionAnimator',
          caption:
              "UIKit's UIViewPropertyAnimator: start, pause, reverse "
              'mid-flight, or drag the bar to scrub. The tile moves and turns '
              'on one curve.',
          stage: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Rail(
                height: 48,
                child: Travel(
                  progress: _x,
                  extent: 48,
                  child: MotionTransition(
                    rotation: _turn,
                    child: Tile(
                      color: palette.swatches[3],
                      size: 48,
                      label: 'A',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              InputRegion(
                interactions: [_scrub],
                child: MotionMeasure(
                  onSize: (_, size) => _barWidth = max(size.width, 1),
                  child: SizedBox(
                    height: 28,
                    child: Center(
                      child: _ProgressBar(
                        progress: _animator.progressListenable,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          controls: [
            PushButton('Start', onPressed: _animator.start),
            PushButton(
              'Pause',
              onPressed: () {
                if (_animator.isRunning) _animator.pause();
              },
            ),
            PushButton('Reverse', onPressed: _reverse),
            PushButton('Reset', onPressed: _reset),
          ],
        ),
      ],
    );
  }
}

class _KeyframeTile extends StatelessWidget {
  const _KeyframeTile({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tappable(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyles.mono.copyWith(
            color: Palette.of(context).secondaryLabel,
          ),
        ),
      ],
    ),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: palette.fill),
            MotionTransition(
              scaleX: progress,
              alignment: AlignmentDirectional.centerStart,
              child: ColoredBox(color: palette.accent),
            ),
          ],
        ),
      ),
    );
  }
}
