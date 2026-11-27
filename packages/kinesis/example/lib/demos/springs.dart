import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class SpringsDemo extends StatefulWidget {
  const SpringsDemo({super.key});

  @override
  State<SpringsDemo> createState() => _SpringsDemoState();
}

class _SpringsDemoState extends State<SpringsDemo> {
  static const _springs = {
    'smooth': Spring.smooth,
    'snappy': Spring.snappy,
    'bouncy': Spring.bouncy,
    'interactive': Spring.interactive,
  };

  static const _curves = {
    'linear': TimingCurve.linear(duration: 0.6),
    'easeIn': TimingCurve.easeIn(duration: 0.6),
    'easeOut': TimingCurve.easeOut(duration: 0.6),
    'easeInOut': TimingCurve.easeInOut(duration: 0.6),
  };

  final _springDots = [for (final _ in _springs.keys) MotionValue<double>(0)];
  final _curveDots = [for (final _ in _curves.keys) MotionValue<double>(0)];

  final _width = MotionValue<double>(120);
  final _height = MotionValue<double>(72);
  late final _color = MotionValue<Color>(Palette.of(context).swatches[0]);
  bool _grown = false;

  final _inset = MotionValue<double>(0);

  final _hop = _Hop();
  bool _reduceMotion = false;

  void _moveSprings() {
    for (final (index, spring) in _springs.values.indexed) {
      final dot = _springDots[index];
      withSpring(spring, () => dot.target = dot.target == 0 ? 1 : 0);
    }
  }

  void _moveCurves() {
    for (final (index, curve) in _curves.values.indexed) {
      final dot = _curveDots[index];
      withAnimation(curve, () => dot.target = dot.target == 0 ? 1 : 0);
    }
  }

  void _grow(Palette palette) {
    _grown = !_grown;
    withSpring(Spring.snappy, () {
      _width.target = _grown ? 220 : 120;
      _height.target = _grown ? 132 : 72;
      _color.target = palette.swatches[_grown ? 1 : 0];
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'A MotionValue holds the target you set and the value on screen. '
          'Assign the target inside withSpring or withAnimation and the value '
          'moves there; MotionTransition draws it without a rebuild.',
      children: [
        Section(
          title: 'Springs keep their speed',
          caption:
              'Tap Move again while the dots fly: each turns around from '
              'where it is, at the speed it has.',
          stage: _Lanes(
            labels: _springs.keys.toList(),
            dots: _springDots,
            color: palette.accent,
          ),
          controls: [PushButton('Move', onPressed: _moveSprings)],
        ),
        Section(
          title: 'Timing curves',
          caption:
              "withAnimation takes a TimingCurve with UIKit's curves. A "
              'retarget mid-flight starts the curve again from where the '
              'dot is.',
          stage: _Lanes(
            labels: _curves.keys.toList(),
            dots: _curveDots,
            color: palette.swatches[2],
          ),
          controls: [PushButton('Move', onPressed: _moveCurves)],
        ),
        Section(
          title: 'Values of any type',
          caption:
              'A MotionValue animates sizes, colors, offsets, rects, radii '
              'and text styles. A width or height in MotionTransition takes '
              'part in layout, so the text below follows it.',
          stage: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 180),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MotionTransition(
                  width: _width,
                  height: _height,
                  borderRadius: BorderRadius.circular(16),
                  child: ValueListenableBuilder(
                    valueListenable: _color,
                    builder: (context, color, _) => ColoredBox(color: color),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'I sit below the box.',
                  style: TextStyles.caption.copyWith(
                    color: palette.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          controls: [
            PushButton('Grow', onPressed: () => _grow(palette)),
          ],
        ),
        Section(
          title: 'Any property',
          caption:
              'MotionDriven drives a chain of render-object widgets from '
              'motion values, here a Padding and a ClipRRect: a frame costs '
              'a layout and a paint, never a build.',
          stage: MotionDriven(
            template: () => Padding(
              padding: EdgeInsets.symmetric(
                horizontal: max(0, 48 * _inset.value),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6 + 30 * _inset.value),
              ),
            ),
            child: ColoredBox(
              color: palette.swatches[5],
              child: SizedBox(
                height: 96,
                child: Center(
                  child: Text(
                    'Padding and corners',
                    style: TextStyles.label.copyWith(color: palette.onAccent),
                  ),
                ),
              ),
            ),
          ),
          controls: [
            PushButton(
              'Inset',
              onPressed: () => withSpring(
                Spring.bouncy,
                () => _inset.target = _inset.target == 0 ? 1 : 0,
              ),
            ),
          ],
        ),
        Section(
          title: 'Reduce Motion',
          caption:
              'A spring names its Reduce Motion alternative. A Motion held '
              'by a MotionScope reads the preference from '
              'MotionTraitsOverride or the platform: here the bounce turns '
              'into a plain glide.',
          stage: MotionTraitsOverride(
            traits: MotionTraits(reduceMotion: _reduceMotion),
            child: MotionScope(
              motion: _hop,
              child: _Lanes(
                labels: const ['bouncy'],
                dots: [_hop.x],
                color: palette.swatches[4],
              ),
            ),
          ),
          controls: [
            PushButton('Move', onPressed: _hop.toggle),
            PushButton(
              'Reduce Motion',
              selected: _reduceMotion,
              onPressed: () => setState(() => _reduceMotion = !_reduceMotion),
            ),
          ],
        ),
      ],
    );
  }
}

final class _Hop extends Motion {
  static const _spring = Spring(bounce: 0.5, reduced: Spring.smooth);

  late final MotionValue<double> x = own(MotionValue<double>(0));

  void toggle() => withSpring(_spring, () => x.target = x.target == 0 ? 1 : 0);
}

class _Lanes extends StatelessWidget {
  const _Lanes({required this.labels, required this.dots, required this.color});

  final List<String> labels;
  final List<MotionValue<double>> dots;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Column(
      children: [
        for (final (index, label) in labels.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyles.mono.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                ),
                Expanded(
                  child: RailDot(progress: dots[index], color: color),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
