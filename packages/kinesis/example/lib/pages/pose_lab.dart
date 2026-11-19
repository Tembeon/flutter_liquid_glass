import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class PoseLabCard extends StatefulWidget {
  const PoseLabCard({super.key});

  @override
  State<PoseLabCard> createState() => _PoseLabCardState();
}

class _PoseLabCardState extends State<PoseLabCard> {
  static const _presets = [
    ('Rest', MotionPose.identity),
    ('Lift', MotionPose(offset: Offset(0, -22), scale: 1.12)),
    ('Tilt', MotionPose(offset: Offset(0, -8), rotation: -0.22)),
    ('Ghost', MotionPose(scale: 0.9, opacity: 0.35, blur: 7)),
    ('Sink', MotionPose(offset: Offset(0, 26), scale: 0.82, rotation: 0.12)),
  ];

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _blend = MotionValue<double>(
    1,
    clock: _clock,
  );
  late final SymbolEffectMotion _effects = SymbolEffectMotion(clock: _clock);
  final ValueNotifier<MotionPose> _worn = ValueNotifier(MotionPose.identity);
  MotionPose _from = MotionPose.identity;
  MotionPose _target = MotionPose.identity;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _blend.addListener(_blended);
  }

  @override
  void dispose() {
    _blend.removeListener(_blended);
    _worn.dispose();
    super.dispose();
  }

  void _blended() =>
      _worn.value = MotionPose.lerp(_from, _target, _blend.value);

  void _set(MotionPose pose) {
    _blend.snap(_clock.now, 1);
    setState(() => _from = _target = pose);
    _worn.value = pose;
  }

  void _goTo(MotionPose pose) {
    final t = _clock.now;
    setState(() {
      _from = _worn.value;
      _target = pose;
    });
    _blend
      ..snap(t, 0)
      ..animate(t, 1, animation: Spring.bouncy);
  }

  MotionPose _edit({
    double? y,
    double? scale,
    double? turn,
    double? opacity,
    double? blur,
  }) => MotionPose(
    offset: Offset(0, y ?? _target.offset.dy),
    scale: scale ?? _target.scale,
    rotation: turn ?? _target.rotation,
    opacity: opacity ?? _target.opacity,
    blur: blur ?? _target.blur,
  );

  void _effect(MotionSymbolEffect effect) => _effects.add(_clock.now, effect);

  void _toggleHidden() {
    final t = _clock.now;
    if (_hidden) {
      _effects
        ..remove<DisappearSymbolEffect>(t, animated: false)
        ..add(t, const AppearSymbolEffect());
    } else {
      _effects.add(t, const DisappearSymbolEffect());
    }
    setState(() => _hidden = !_hidden);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.indigo;
    return StudioSurface(
      title: 'Pose Lab',
      subtitle:
          'MotionPose is the one look value of kinesis: move, scale, turn, '
          'fade and blur. The tile wears the pose of the sliders through '
          'MotionTransition, presets spring there with MotionPose.lerp, and '
          'symbol effects compose on top.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 230,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CustomPaint(
                painter: _DotGridPainter(
                  background: palette.well,
                  dot: palette.textTertiary.withValues(alpha: 0.35),
                ),
                child: Center(
                  child: MotionSymbol(
                    motion: _effects,
                    child: MotionTransition(
                      pose: _worn,
                      child: _Tile(accent: accent, second: palette.pink),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, pose) in _presets)
                KinesisChip(
                  label: label,
                  selected: _target == pose,
                  accent: accent,
                  onTap: () => _goTo(pose),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final sliders = [
                KinesisSlider(
                  label: 'Offset',
                  value: _target.offset.dy,
                  min: -40,
                  max: 40,
                  valueLabel: '${_target.offset.dy.toStringAsFixed(0)} px',
                  accent: accent,
                  onChanged: (v) => _set(_edit(y: v)),
                ),
                KinesisSlider(
                  label: 'Scale',
                  value: _target.scale,
                  min: 0.5,
                  max: 1.5,
                  valueLabel: _target.scale.toStringAsFixed(2),
                  accent: accent,
                  onChanged: (v) => _set(_edit(scale: v)),
                ),
                KinesisSlider(
                  label: 'Turn',
                  value: _target.rotation,
                  min: -0.6,
                  max: 0.6,
                  valueLabel: '${_target.rotation.toStringAsFixed(2)} rad',
                  accent: accent,
                  onChanged: (v) => _set(_edit(turn: v)),
                ),
                KinesisSlider(
                  label: 'Opacity',
                  value: _target.opacity,
                  min: 0,
                  max: 1,
                  valueLabel: _target.opacity.toStringAsFixed(2),
                  accent: accent,
                  onChanged: (v) => _set(_edit(opacity: v)),
                ),
                KinesisSlider(
                  label: 'Blur',
                  value: _target.blur,
                  min: 0,
                  max: 12,
                  valueLabel: _target.blur.toStringAsFixed(1),
                  accent: accent,
                  onChanged: (v) => _set(_edit(blur: v)),
                ),
              ];
              final columns = constraints.maxWidth >= 560 ? 2 : 1;
              final width =
                  (constraints.maxWidth - 20 * (columns - 1)) / columns;
              return Wrap(
                spacing: 20,
                children: [
                  for (final slider in sliders)
                    SizedBox(width: width, child: slider),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisButton(
                label: 'Bounce',
                glyph: StudioGlyph.sparkle,
                accent: accent,
                onPressed: () => _effect(const BounceSymbolEffect()),
              ),
              KinesisButton(
                label: 'Wiggle',
                glyph: StudioGlyph.bolt,
                accent: palette.orange,
                onPressed: () => _effect(const WiggleSymbolEffect()),
              ),
              KinesisButton(
                label: _hidden ? 'Appear' : 'Disappear',
                glyph: _hidden ? StudioGlyph.plus : StudioGlyph.minus,
                accent: palette.pink,
                onPressed: _toggleHidden,
              ),
            ],
          ),
          InspectorDrawer(
            apis: const [
              'MotionPose',
              'MotionPose.lerp',
              'MotionTransition.pose',
              'MotionSymbol',
              'AppearSymbolEffect',
              'DisappearSymbolEffect',
            ],
            child: ValueListenableBuilder<MotionPose>(
              valueListenable: _worn,
              builder: (context, pose, _) => Text(
                'offset ${pose.offset.dy.toStringAsFixed(1)}  '
                'scale ${pose.scale.toStringAsFixed(2)}  '
                'turn ${pose.rotation.toStringAsFixed(2)}  '
                'opacity ${pose.opacity.toStringAsFixed(2)}  '
                'blur ${pose.blur.toStringAsFixed(1)}',
                style: palette.mono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.accent, required this.second});

  final Color accent;
  final Color second;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, second],
      ),
      borderRadius: BorderRadius.circular(28),
    ),
    child: const SizedBox.square(
      dimension: 108,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StudioIcon(
            StudioGlyph.sparkle,
            color: Color(0xFFFFFFFF),
            size: 38,
          ),
          SizedBox(height: 8),
          Text(
            'kinesis',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.background, required this.dot});

  final Color background;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()..color = dot;
    const step = 18.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      background != oldDelegate.background || dot != oldDelegate.dot;
}
