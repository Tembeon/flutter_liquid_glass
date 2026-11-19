import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/pages/pose_lab.dart';
import 'package:kinesis_example/theme.dart';

class SymbolsPage extends StatelessWidget {
  const SymbolsPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StudioPageHeader(
        title: 'Tactile Symbols & Haptics',
        subtitle:
            'Tap any control tile directly to feel SF Symbol-style motion. '
            'Rapid taps queue cleanly; active tiles breathe or pulse until '
            'toggled off.',
      ),
      _ControlCenterGridCard(),
      SizedBox(height: 18),
      PoseLabCard(),
      SizedBox(height: 18),
      _ZoomDialHapticsCard(),
    ],
  );
}

class _ControlCenterGridCard extends StatefulWidget {
  const _ControlCenterGridCard();

  @override
  State<_ControlCenterGridCard> createState() => _ControlCenterGridCardState();
}

class _ControlCenterGridCardState extends State<_ControlCenterGridCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final SymbolEffectMotion _bell = SymbolEffectMotion(clock: _clock);
  late final SymbolEffectMotion _heart = SymbolEffectMotion(clock: _clock);
  late final SymbolEffectMotion _bolt = SymbolEffectMotion(clock: _clock);
  late final SymbolEffectMotion _star = SymbolEffectMotion(clock: _clock);
  late final SymbolEffectMotion _wifi = SymbolEffectMotion(clock: _clock);
  late final SymbolEffectMotion _check = SymbolEffectMotion(clock: _clock);

  double _speed = 1;
  bool _favorited = false;
  bool _airDropOn = false;
  bool _livePulse = false;
  String _lastLog = 'Tap any tile to trigger its symbol effect';

  void _tapBell() {
    _bell.add(
      _clock.now,
      const BounceSymbolEffect(),
      options: SymbolEffectOptions(speed: _speed),
      onComplete: (done) {
        if (mounted) setState(() => _lastLog = 'Bounce completed ($done)');
      },
    );
    setState(() => _lastLog = 'Queued BounceSymbolEffect on Alerts');
  }

  void _tapHeart() {
    final t = _clock.now;
    _favorited = !_favorited;
    if (_favorited) {
      _heart.add(
        t,
        const ScaleSymbolEffect(),
        options: SymbolEffectOptions(speed: _speed),
      );
      _heart.add(
        t,
        const BounceSymbolEffect(),
        options: SymbolEffectOptions(speed: _speed),
      );
    } else {
      _heart.remove<ScaleSymbolEffect>(t);
    }
    setState(
      () => _lastLog = _favorited
          ? 'Stacked ScaleSymbolEffect + Bounce'
          : 'Unwound ScaleSymbolEffect',
    );
  }

  void _tapBolt() {
    _bolt.add(
      _clock.now,
      const WiggleSymbolEffect(),
      options: SymbolEffectOptions(speed: _speed),
    );
    setState(() => _lastLog = 'Queued WiggleSymbolEffect on Energy');
  }

  void _tapStar() {
    _star.add(
      _clock.now,
      const RotateSymbolEffect(),
      options: SymbolEffectOptions(speed: _speed),
    );
    setState(() => _lastLog = 'Queued RotateSymbolEffect on Sync');
  }

  void _tapWifi() {
    final t = _clock.now;
    _airDropOn = !_airDropOn;
    if (_airDropOn) {
      _wifi.add(
        t,
        const BreatheSymbolEffect(),
        options: SymbolEffectOptions(speed: _speed),
        onComplete: (done) {
          if (mounted) {
            setState(
              () => _lastLog = 'Breathe cycle ended (isFinished: $done)',
            );
          }
        },
      );
    } else {
      _wifi.remove<BreatheSymbolEffect>(
        t,
        onComplete: (done) {
          if (mounted) {
            setState(
              () => _lastLog =
                  'Breathe stop requested (isFinished: $done, finishing cycle)',
            );
          }
        },
      );
    }
    setState(() {});
  }

  void _tapCheck() {
    final t = _clock.now;
    _livePulse = !_livePulse;
    if (_livePulse) {
      _check.add(
        t,
        const PulseSymbolEffect(),
        options: SymbolEffectOptions(speed: _speed),
      );
      setState(() => _lastLog = 'Started repeating PulseSymbolEffect');
    } else {
      _check.remove<PulseSymbolEffect>(t);
      setState(() => _lastLog = 'Stopping PulseSymbolEffect at cycle end');
    }
  }

  void _stopAll() {
    final t = _clock.now;
    _favorited = false;
    _airDropOn = false;
    _livePulse = false;
    for (final m in [_bell, _heart, _bolt, _star, _wifi, _check]) {
      m.removeAll(t);
    }
    setState(
      () => _lastLog = 'removeAll() -- active loops unwind, bounces finish',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 520 ? 3 : 2;
              const gap = 12.0;
              final tileW = (constraints.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _SymbolTile(
                    width: tileW,
                    title: 'Alerts',
                    caption: 'Tap fast to queue',
                    glyph: StudioGlyph.bell,
                    accent: palette.orange,
                    active: false,
                    motion: _bell,
                    onTap: _tapBell,
                  ),
                  _SymbolTile(
                    width: tileW,
                    title: 'Favorite',
                    caption: _favorited ? 'Held scaled up' : 'Tap to favorite',
                    glyph: StudioGlyph.heart,
                    accent: palette.pink,
                    active: _favorited,
                    motion: _heart,
                    onTap: _tapHeart,
                  ),
                  _SymbolTile(
                    width: tileW,
                    title: 'Quick Charge',
                    caption: 'Wiggle shake',
                    glyph: StudioGlyph.bolt,
                    accent: palette.green,
                    active: false,
                    motion: _bolt,
                    onTap: _tapBolt,
                  ),
                  _SymbolTile(
                    width: tileW,
                    title: 'Featured',
                    caption: 'Full smooth turn',
                    glyph: StudioGlyph.star,
                    accent: palette.indigo,
                    active: false,
                    motion: _star,
                    onTap: _tapStar,
                  ),
                  _SymbolTile(
                    width: tileW,
                    title: 'AirDrop',
                    caption: _airDropOn ? 'Breathing...' : 'Tap to search',
                    glyph: StudioGlyph.wifi,
                    accent: palette.blue,
                    active: _airDropOn,
                    motion: _wifi,
                    onTap: _tapWifi,
                  ),
                  _SymbolTile(
                    width: tileW,
                    title: 'Live Sync',
                    caption: _livePulse ? 'Pulsing...' : 'Tap to pulse',
                    glyph: StudioGlyph.check,
                    accent: palette.teal,
                    active: _livePulse,
                    motion: _check,
                    onTap: _tapCheck,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in const [0.5, 1.0, 2.0])
                KinesisChip(
                  label: '${s}x Speed',
                  selected: _speed == s,
                  onTap: () => setState(() => _speed = s),
                ),
              KinesisButton(
                label: 'Stop Active',
                compact: true,
                accent: palette.red,
                onPressed: _stopAll,
              ),
            ],
          ),
          InspectorDrawer(
            apis: const [
              'SymbolEffectMotion',
              'MotionSymbol',
              'Bounce / Wiggle / Rotate / Scale / Breathe / Pulse',
            ],
            child: Text(_lastLog, style: palette.mono),
          ),
        ],
      ),
    );
  }
}

class _SymbolTile extends StatelessWidget {
  const _SymbolTile({
    required this.width,
    required this.title,
    required this.caption,
    required this.glyph,
    required this.accent,
    required this.active,
    required this.motion,
    required this.onTap,
  });

  final double width;
  final String title;
  final String caption;
  final StudioGlyph glyph;
  final Color accent;
  final bool active;
  final SymbolEffectMotion motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return InputRegion(
      interactions: [TapInteraction(onTap: (_) => onTap())],
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.lightImpact : null,
      semantics: SemanticsProperties(button: true, label: title),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: palette.isDark ? 0.24 : 0.12)
              : palette.well,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.5) : palette.hairline,
          ),
        ),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Column(
              children: [
                SizedBox(
                  height: 54,
                  child: Center(
                    child: MotionSymbol(
                      motion: motion,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: active ? 1 : 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: StudioIcon(
                            glyph,
                            color: active ? const Color(0xFFFFFFFF) : accent,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(caption, style: palette.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomDialHapticsCard extends StatefulWidget {
  const _ZoomDialHapticsCard();

  @override
  State<_ZoomDialHapticsCard> createState() => _ZoomDialHapticsCardState();
}

class _ZoomDialHapticsCardState extends State<_ZoomDialHapticsCard> {
  static const int _ticks = 15;
  final ChangeNotifier _frames = ChangeNotifier();
  int _selected = 3;
  int _crossings = 0;
  int _fired = 0;

  double get _zoom => 0.5 + _selected * 0.3;

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioSurface(
      title: 'Camera Zoom Dial & Haptics',
      subtitle:
          'Slide smoothly across the dial to feel detent ticks automatically '
          'throttled to 25 Hz (40 ms), just like iOS Camera.',
      trailing: MotionNumericText(
        '${_zoom.toStringAsFixed(1)}x',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: palette.orange,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MotionHapticScope(
            enabled: MotionHapticScope.enabledOf(context),
            onFeedback: (h) {
              if (h == MotionHaptic.selection) {
                setState(() => _fired++);
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellW = constraints.maxWidth / _ticks;
                return InputZones<int>(
                  activatesOnMove: true,
                  frames: _frames,
                  current: _selected,
                  frameOf: (id) => InputZoneFrame(
                    Rect.fromLTWH(id * cellW, 0, cellW, 56),
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
                              if (_selected != i) {
                                setState(() {
                                  _selected = i;
                                  _crossings++;
                                });
                              }
                            },
                          ),
                        ],
                        semantics: SemanticsProperties(
                          label: 'Zoom ${(0.5 + i * 0.3).toStringAsFixed(1)}x',
                          selected: _selected == i,
                        ),
                      ),
                  ],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.well,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.hairline),
                    ),
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          for (var i = 0; i < _ticks; i++)
                            Expanded(
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: i == _selected
                                        ? palette.orange
                                        : (i % 5 == 0
                                              ? palette.textSecondary
                                              : palette.textTertiary.withValues(
                                                  alpha: 0.4,
                                                )),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: SizedBox(
                                    width: i == _selected ? 4 : 2,
                                    height: i == _selected
                                        ? 32
                                        : (i % 5 == 0 ? 22 : 12),
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (haptic, label, color) in [
                (MotionHaptic.lightImpact, 'Light Tap', palette.blue),
                (MotionHaptic.mediumImpact, 'Medium Tap', palette.indigo),
                (MotionHaptic.success, 'Success', palette.green),
                (MotionHaptic.error, 'Error', palette.red),
              ])
                KinesisButton(
                  label: label,
                  compact: true,
                  haptic: haptic,
                  accent: color,
                  onPressed: () {},
                ),
            ],
          ),
          InspectorDrawer(
            apis: const [
              'MotionHaptic',
              'MotionHapticScope',
              'selectionMinimumInterval',
              'InputZones',
            ],
            child: Text(
              'dial crossings: $_crossings  |  '
              'haptics fired (<=25 Hz): $_fired',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}
