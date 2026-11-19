import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class SymbolsPage extends StatelessWidget {
  const SymbolsPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SymbolEffectLabCard(),
      SizedBox(height: 16),
      _HapticsLabCard(),
    ],
  );
}

class _SymbolEffectLabCard extends StatefulWidget {
  const _SymbolEffectLabCard();

  @override
  State<_SymbolEffectLabCard> createState() => _SymbolEffectLabCardState();
}

class _SymbolEffectLabCardState extends State<_SymbolEffectLabCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final SymbolEffectMotion _motion = SymbolEffectMotion(clock: _clock);

  StudioGlyph _glyph = StudioGlyph.bell;
  double _speed = 1;
  int _repeat = 1;
  final Set<String> _activeIndefinite = {};
  final List<String> _log = [];

  void _record(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, message);
      if (_log.length > 5) _log.removeLast();
    });
  }

  void _fireDiscrete(String name, MotionSymbolEffect effect) {
    _motion.add(
      _clock.now,
      effect,
      options: SymbolEffectOptions(speed: _speed, repeatCount: _repeat),
      onComplete: (finished) => _record('$name done (isFinished: $finished)'),
    );
    _record('queued $name (x$_repeat @ ${_speed}x)');
  }

  void _toggleIndefinite<E extends MotionSymbolEffect>(
    String key,
    E effect,
  ) {
    final t = _clock.now;
    if (_activeIndefinite.contains(key)) {
      _activeIndefinite.remove(key);
      _motion.remove<E>(
        t,
        onComplete: (finished) =>
            _record('remove $key (isFinished: $finished)'),
      );
      setState(() {});
    } else {
      _activeIndefinite.add(key);
      _motion.add(
        t,
        effect,
        options: SymbolEffectOptions(speed: _speed),
        onComplete: (finished) {
          _activeIndefinite.remove(key);
          _record('$key cycle end (isFinished: $finished)');
        },
      );
      _record('added $key');
    }
  }

  void _removeAll() {
    _activeIndefinite.clear();
    _motion.removeAll(_clock.now);
    _record('removeAll (indefinites unwind, discrete continues)');
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'SymbolEffectMotion & MotionSymbol',
      subtitle:
          'UIKit SF Symbol effect engine: tap discrete effects rapidly to '
          'queue them back-to-back, stack multiple indefinite effects '
          'concurrently, and watch exact removal completion semantics.',
      apis: const [
        'SymbolEffectMotion',
        'MotionSymbol',
        'MotionSymbolEffect',
        'SymbolEffectOptions',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (g, name) in const [
                (StudioGlyph.bell, 'Bell'),
                (StudioGlyph.heart, 'Heart'),
                (StudioGlyph.star, 'Star'),
                (StudioGlyph.bolt, 'Bolt'),
                (StudioGlyph.wifi, 'Wifi'),
                (StudioGlyph.check, 'Check'),
              ])
                KinesisChip(
                  label: name,
                  glyph: g,
                  selected: _glyph == g,
                  onTap: () => setState(() => _glyph = g),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.hairline),
            ),
            child: SizedBox(
              height: 136,
              child: Center(
                child: MotionSymbol(
                  motion: _motion,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.blue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: StudioIcon(_glyph, color: palette.blue, size: 46),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in const [0.5, 1.0, 2.0])
                KinesisChip(
                  label: '${s}x speed',
                  selected: _speed == s,
                  accent: palette.teal,
                  onTap: () => setState(() => _speed = s),
                ),
              for (final r in const [1, 2, 3])
                KinesisChip(
                  label: 'repeat $r',
                  selected: _repeat == r,
                  accent: palette.orange,
                  onTap: () => setState(() => _repeat = r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Discrete (queues when tapped rapidly)', style: palette.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              KinesisButton(
                label: 'Bounce Up',
                compact: true,
                filled: true,
                onPressed: () =>
                    _fireDiscrete('bounce.up', const BounceSymbolEffect()),
              ),
              KinesisButton(
                label: 'Bounce Down',
                compact: true,
                onPressed: () => _fireDiscrete(
                  'bounce.down',
                  const BounceSymbolEffect(
                    direction: SymbolEffectDirection.down,
                  ),
                ),
              ),
              KinesisButton(
                label: 'Wiggle H',
                compact: true,
                onPressed: () =>
                    _fireDiscrete('wiggle.h', const WiggleSymbolEffect()),
              ),
              KinesisButton(
                label: 'Wiggle V',
                compact: true,
                onPressed: () => _fireDiscrete(
                  'wiggle.v',
                  const WiggleSymbolEffect(horizontal: false),
                ),
              ),
              KinesisButton(
                label: 'Rotate CW',
                compact: true,
                onPressed: () =>
                    _fireDiscrete('rotate.cw', const RotateSymbolEffect()),
              ),
              KinesisButton(
                label: 'Rotate CCW',
                compact: true,
                onPressed: () => _fireDiscrete(
                  'rotate.ccw',
                  const RotateSymbolEffect(clockwise: false),
                ),
              ),
              KinesisButton(
                label: 'Appear',
                compact: true,
                accent: palette.green,
                onPressed: () {
                  _activeIndefinite.remove('disappear');
                  _fireDiscrete('appear', const AppearSymbolEffect());
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Indefinite & Stateful (stack concurrently)',
            style: palette.label,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              KinesisChip(
                label: 'Scale Up',
                selected: _activeIndefinite.contains('scale.up'),
                accent: palette.purple,
                onTap: () {
                  _activeIndefinite.remove('scale.down');
                  _toggleIndefinite<ScaleSymbolEffect>(
                    'scale.up',
                    const ScaleSymbolEffect(),
                  );
                },
              ),
              KinesisChip(
                label: 'Scale Down',
                selected: _activeIndefinite.contains('scale.down'),
                accent: palette.purple,
                onTap: () {
                  _activeIndefinite.remove('scale.up');
                  _toggleIndefinite<ScaleSymbolEffect>(
                    'scale.down',
                    const ScaleSymbolEffect(
                      direction: SymbolEffectDirection.down,
                    ),
                  );
                },
              ),
              KinesisChip(
                label: 'Breathe',
                selected: _activeIndefinite.contains('breathe'),
                accent: palette.green,
                onTap: () => _toggleIndefinite<BreatheSymbolEffect>(
                  'breathe',
                  const BreatheSymbolEffect(),
                ),
              ),
              KinesisChip(
                label: 'Pulse',
                selected: _activeIndefinite.contains('pulse'),
                accent: palette.orange,
                onTap: () => _toggleIndefinite<PulseSymbolEffect>(
                  'pulse',
                  const PulseSymbolEffect(),
                ),
              ),
              KinesisChip(
                label: 'Disappear',
                selected: _activeIndefinite.contains('disappear'),
                accent: palette.red,
                onTap: () => _toggleIndefinite<DisappearSymbolEffect>(
                  'disappear',
                  const DisappearSymbolEffect(),
                ),
              ),
              KinesisButton(
                label: 'Remove All',
                compact: true,
                accent: palette.red,
                onPressed: _removeAll,
              ),
            ],
          ),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.well,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in _log) Text(entry, style: palette.mono),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HapticsLabCard extends StatefulWidget {
  const _HapticsLabCard();

  @override
  State<_HapticsLabCard> createState() => _HapticsLabCardState();
}

class _HapticsLabCardState extends State<_HapticsLabCard> {
  static const int _ticks = 12;
  final ChangeNotifier _frames = ChangeNotifier();
  double _rulerWidth = 280;
  int _selectedTick = 0;
  int _requestedTicks = 0;
  int _firedTicks = 0;

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'MotionHaptic & 40 ms Selection Throttle',
      subtitle:
          'Fire any of the 9 semantic haptics, or drag slowly vs rapidly '
          'across the 12-tick ruler below to observe UIKit 25 Hz (40 ms) '
          'selection throttling in MotionHapticScope.',
      apis: const [
        'MotionHaptic',
        'MotionHapticScope',
        'selectionMinimumInterval',
        'InputZones',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final haptic in MotionHaptic.values)
                KinesisButton(
                  label: haptic.name,
                  compact: true,
                  haptic: haptic,
                  accent: switch (haptic) {
                    MotionHaptic.success => palette.green,
                    MotionHaptic.warning => palette.orange,
                    MotionHaptic.error => palette.red,
                    MotionHaptic.selection => palette.teal,
                    _ => palette.blue,
                  },
                  onPressed: () {},
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Drag across ruler', style: palette.label),
              Text(
                'crossings: $_requestedTicks  |  fired (<=25Hz): $_firedTicks',
                style: palette.mono,
              ),
            ],
          ),
          const SizedBox(height: 8),
          MotionHapticScope(
            enabled: MotionHapticScope.enabledOf(context),
            onFeedback: (h) {
              if (h == MotionHaptic.selection) {
                setState(() => _firedTicks++);
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                _rulerWidth = constraints.maxWidth;
                final cellW = _rulerWidth / _ticks;
                return InputZones<int>(
                  activatesOnMove: true,
                  frames: _frames,
                  current: _selectedTick,
                  frameOf: (id) => InputZoneFrame(
                    Rect.fromLTWH(id * cellW, 0, cellW, 48),
                  ),
                  feedback: (id, event) =>
                      event is ActivationEvent ? MotionHaptic.selection : null,
                  zones: [
                    for (var i = 0; i < _ticks; i++)
                      InputZone<int>(
                        id: i,
                        interactions: [
                          TapInteraction(
                            onTap: (_) {
                              if (_selectedTick != i) {
                                setState(() {
                                  _selectedTick = i;
                                  _requestedTicks++;
                                });
                              }
                            },
                          ),
                        ],
                        semantics: SemanticsProperties(
                          label: 'Tick ${i + 1}',
                          selected: _selectedTick == i,
                        ),
                      ),
                  ],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.well,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.hairline),
                    ),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          for (var i = 0; i < _ticks; i++)
                            Expanded(
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: i == _selectedTick
                                        ? palette.teal
                                        : palette.textTertiary.withValues(
                                            alpha: 0.4,
                                          ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: SizedBox(
                                    width: i == _selectedTick ? 5 : 2,
                                    height: i == _selectedTick ? 28 : 14,
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
          ),
        ],
      ),
    );
  }
}
