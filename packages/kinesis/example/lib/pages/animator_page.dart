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
      StudioPageHeader(
        title: 'Now Playing',
        subtitle:
            'Scrub, pause, reverse mid-flight, or finish with a spring. '
            'One MotionAnimator choreographs position, size, corners, and '
            'color in lockstep.',
      ),
      _NowPlayingScrubCard(),
      SizedBox(height: 18),
      _AmbientOrbitCard(),
    ],
  );
}

class _NowPlayingScrubCard extends StatefulWidget {
  const _NowPlayingScrubCard();

  @override
  State<_NowPlayingScrubCard> createState() => _NowPlayingScrubCardState();
}

class _NowPlayingScrubCardState extends State<_NowPlayingScrubCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late MotionAnimator _animator;

  late final MotionValue<double> _expand = MotionValue<double>(
    0,
    clock: _clock,
  );
  late final MotionValue<double> _artScale = MotionValue<double>(
    1,
    clock: _clock,
  );
  late final MotionValue<double> _controlsOpacity = MotionValue<double>(
    0,
    restDistance: MotionRest.opacity,
    clock: _clock,
  );
  late final MotionValue<Color> _glow = MotionValue<Color>(
    const Color(0xFF3B82F6),
    clock: _clock,
  );
  late final MotionValue<BorderRadius> _artRadius = MotionValue<BorderRadius>(
    BorderRadius.circular(10),
    clock: _clock,
  );

  @override
  void initState() {
    super.initState();
    _setupAnimator();
  }

  void _setupAnimator() {
    final t = _clock.now;
    _expand.snap(t, 0);
    _artScale.snap(t, 1);
    _controlsOpacity.snap(t, 0);
    _glow.snap(t, const Color(0xFF3B82F6));
    _artRadius.snap(t, BorderRadius.circular(10));

    _animator = MotionAnimator(
      animation: const TimingCurve.easeInOut(duration: 0.9),
      clock: _clock,
      pausesOnCompletion: true,
    );
    _animator.addAnimation<double>(_expand, 1);
    _animator.addAnimation<double>(_artScale, 1.08, delayFactor: 0.12);
    _animator.addAnimation<double>(_controlsOpacity, 1, delayFactor: 0.35);
    _animator.addAnimation<Color>(
      _glow,
      const Color(0xFFEC4899),
      delayFactor: 0.1,
    );
    _animator.addAnimation<BorderRadius>(
      _artRadius,
      BorderRadius.circular(24),
      delayFactor: 0.15,
    );
  }

  void _toggleExpand() {
    if (_animator.state == MotionAnimatorState.inactive) {
      _animator.isReversed = false;
      _animator.start();
    } else if (_animator.state == MotionAnimatorState.active) {
      final atEnd = _animator.fractionComplete > 0.5;
      _animator.isReversed = atEnd;
      _animator.continueWith(animation: Spring.bouncy);
    }
    setState(() {});
  }

  void _pauseOrResume() {
    if (_animator.isRunning) {
      _animator.pause();
    } else {
      _animator.start();
    }
    setState(() {});
  }

  void _reverse() {
    _animator.isReversed = !_animator.isReversed;
    if (!_animator.isRunning) {
      _animator.start();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _animator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 276,
              child: CustomPaint(
                painter: _NowPlayingPainter(
                  expand: _expand,
                  artScale: _artScale,
                  controlsOpacity: _controlsOpacity,
                  glow: _glow,
                  artRadius: _artRadius,
                  palette: palette,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<double>(
            valueListenable: _animator.progressListenable,
            builder: (context, frac, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KinesisSlider(
                  label: 'Scrub Mini  <->  Full Player',
                  value: frac,
                  min: 0,
                  max: 1,
                  valueLabel: '${(frac * 100).round()}%',
                  accent: palette.pink,
                  onChanged: (v) {
                    _animator.scrub(v);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    KinesisButton(
                      label: frac > 0.5 ? 'Collapse' : 'Expand',
                      filled: true,
                      accent: palette.pink,
                      glyph: StudioGlyph.music,
                      onPressed: _toggleExpand,
                    ),
                    KinesisButton(
                      label: _animator.isRunning ? 'Pause' : 'Play',
                      glyph: _animator.isRunning
                          ? StudioGlyph.pause
                          : StudioGlyph.play,
                      onPressed: _pauseOrResume,
                    ),
                    KinesisButton(
                      label: 'Reverse',
                      glyph: StudioGlyph.reverse,
                      onPressed: _reverse,
                    ),
                  ],
                ),
                InspectorDrawer(
                  apis: const [
                    'MotionAnimator',
                    'delayFactor',
                    'scrub',
                    'continueWith',
                    'BorderRadius',
                  ],
                  child: Text(
                    'state: ${_animator.state.name}  |  '
                    'running: ${_animator.isRunning}  |  '
                    'reversed: ${_animator.isReversed}  |  '
                    'fraction: ${frac.toStringAsFixed(2)}',
                    style: palette.mono,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _NowPlayingPainter extends CustomPainter {
  _NowPlayingPainter({
    required this.expand,
    required this.artScale,
    required this.controlsOpacity,
    required this.glow,
    required this.artRadius,
    required this.palette,
  }) : super(
         repaint: Listenable.merge([
           expand,
           artScale,
           controlsOpacity,
           glow,
           artRadius,
         ]),
       );

  final MotionValue<double> expand;
  final MotionValue<double> artScale;
  final MotionValue<double> controlsOpacity;
  final MotionValue<Color> glow;
  final MotionValue<BorderRadius> artRadius;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final t = expand.value.clamp(0.0, 1.0);
    final accent = glow.value;

    // Soft ambient backdrop that deepens as the player expands.
    final bgTop = Color.lerp(
      palette.well,
      accent.withValues(alpha: palette.isDark ? 0.34 : 0.2),
      t,
    )!;
    final bgBottom = Color.lerp(
      palette.well,
      palette.isDark ? const Color(0xFF13131A) : const Color(0xFFFDF2F8),
      t,
    )!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bgBottom],
        ).createShader(Offset.zero & size),
    );

    // Floating mini-bar card that expands to fill the stage.
    final miniRect = Rect.fromLTWH(16, size.height - 84, size.width - 32, 68);
    final fullRect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    final cardRect = Rect.lerp(miniRect, fullRect, t)!;
    final cardRRect = RRect.fromRectAndRadius(
      cardRect,
      Radius.circular(18 + 6 * t),
    );
    canvas.drawRRect(
      cardRRect.shift(const Offset(0, 6)),
      Paint()..color = palette.shadow,
    );
    canvas.drawRRect(cardRRect, Paint()..color = palette.surface);
    canvas.drawRRect(
      cardRRect,
      Paint()
        ..color = palette.hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Album artwork morphs from 46x46 mini square to 122x122 centered cover.
    final artMini = Rect.fromLTWH(
      cardRect.left + 12,
      cardRect.top + 11,
      46,
      46,
    );
    final artSize = 114.0 * (0.95 + 0.05 * artScale.value);
    final artFull = Rect.fromCenter(
      center: Offset(cardRect.center.dx, cardRect.top + 76),
      width: artSize,
      height: artSize,
    );
    final artRect = Rect.lerp(artMini, artFull, t)!;
    final artRRect = artRadius.value.toRRect(artRect);

    canvas.drawRRect(
      artRRect.shift(Offset(0, 6 * t + 2)),
      Paint()..color = accent.withValues(alpha: 0.32),
    );
    canvas.drawRRect(
      artRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, const Color(0xFF6366F1)],
        ).createShader(artRect),
    );
    // Vinyl rings inside artwork.
    canvas.drawCircle(
      artRect.center,
      artRect.width * 0.3,
      Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      artRect.center,
      artRect.width * 0.1,
      Paint()..color = const Color(0xCCFFFFFF),
    );

    // Track title & artist glide from right of mini-art to below big cover.
    final titleTp = TextPainter(
      text: TextSpan(
        text: 'Midnight Velocity',
        style: TextStyle(
          fontSize: 14 + 4 * t,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final artistTp = TextPainter(
      text: TextSpan(
        text: 'Kinesis Ensemble',
        style: TextStyle(
          fontSize: 12 + 1 * t,
          color: palette.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final miniTitlePos = Offset(artMini.right + 12, cardRect.top + 16);
    final fullTitlePos = Offset(
      cardRect.center.dx - titleTp.width / 2,
      artFull.bottom + 14,
    );
    final titlePos = Offset.lerp(miniTitlePos, fullTitlePos, t)!;
    titleTp.paint(canvas, titlePos);

    final miniArtistPos = Offset(artMini.right + 12, cardRect.top + 36);
    final fullArtistPos = Offset(
      cardRect.center.dx - artistTp.width / 2,
      artFull.bottom + 38,
    );
    artistTp.paint(canvas, Offset.lerp(miniArtistPos, fullArtistPos, t)!);

    // Delayed playback scrubber bar fades in after delayFactor: 0.35.
    final cAlpha = controlsOpacity.value.clamp(0.0, 1.0);
    if (cAlpha > 0.01) {
      final barY = cardRect.bottom - 34;
      final barLeft = cardRect.left + 28;
      final barRight = cardRect.right - 28;
      canvas.drawLine(
        Offset(barLeft, barY),
        Offset(barRight, barY),
        Paint()
          ..color = palette.hairline.withValues(alpha: 0.25 * cAlpha)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(barLeft, barY),
        Offset(barLeft + (barRight - barLeft) * 0.62, barY),
        Paint()
          ..color = accent.withValues(alpha: cAlpha)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        Offset(barLeft + (barRight - barLeft) * 0.62, barY),
        6,
        Paint()..color = accent.withValues(alpha: cAlpha),
      );
    }

    // Mini play dot on right side fades out as player expands.
    final miniAlpha = (1 - t * 2).clamp(0.0, 1.0);
    if (miniAlpha > 0.01) {
      final btnCenter = Offset(cardRect.right - 30, cardRect.center.dy);
      canvas.drawCircle(
        btnCenter,
        16,
        Paint()..color = accent.withValues(alpha: 0.15 * miniAlpha),
      );
      final tri = Path()
        ..moveTo(btnCenter.dx - 4, btnCenter.dy - 6)
        ..lineTo(btnCenter.dx + 6, btnCenter.dy)
        ..lineTo(btnCenter.dx - 4, btnCenter.dy + 6)
        ..close();
      canvas.drawPath(
        tri,
        Paint()..color = accent.withValues(alpha: miniAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(_NowPlayingPainter oldDelegate) =>
      palette != oldDelegate.palette;
}

class _AmbientOrbitCard extends StatefulWidget {
  const _AmbientOrbitCard();

  @override
  State<_AmbientOrbitCard> createState() => _AmbientOrbitCardState();
}

class _AmbientOrbitCardState extends State<_AmbientOrbitCard> {
  late final MotionClock _clock = MotionClockScope.of(context);
  KeyframeMode _mode = KeyframeMode.cubic;

  static const _stops = [
    KeyframeStop<Offset>(0, Offset(-0.72, 0.36)),
    KeyframeStop<Offset>(0.25, Offset(-0.24, -0.56)),
    KeyframeStop<Offset>(0.5, Offset(0.32, 0.52)),
    KeyframeStop<Offset>(0.75, Offset(0.72, -0.38)),
    KeyframeStop<Offset>(1, Offset(-0.72, 0.36)),
  ];

  static const _colors = [
    KeyframeStop<Color>(0, Color(0xFF0A84FF)),
    KeyframeStop<Color>(0.33, Color(0xFF30D158)),
    KeyframeStop<Color>(0.66, Color(0xFFFF9F0A)),
    KeyframeStop<Color>(1, Color(0xFF0A84FF)),
  ];

  late final KeyframeValue<Offset> _pos = KeyframeValue<Offset>(
    _pathFor(_mode),
    clock: _clock,
  );
  late final KeyframeValue<Color> _hue = KeyframeValue<Color>(
    _colorFor(_mode),
    clock: _clock,
  );

  MotionKeyframes<Offset> _pathFor(KeyframeMode mode) =>
      MotionKeyframes<Offset>(
        duration: 2.8,
        mode: mode,
        repeatCount: double.infinity,
        stops: _stops,
      );

  MotionKeyframes<Color> _colorFor(KeyframeMode mode) => MotionKeyframes<Color>(
    duration: 2.8,
    mode: mode,
    repeatCount: double.infinity,
    stops: _colors,
  );

  void _setMode(KeyframeMode mode) {
    final t = _clock.now;
    _mode = mode;
    _pos.play(t, keyframes: _pathFor(mode));
    _hue.play(t, keyframes: _colorFor(mode));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioSurface(
      title: 'Keyframe Motion Paths',
      subtitle:
          'Switch between organic Catmull-Rom splines, crisp linear legs, '
          'and stepped discrete jumps.',
      trailing: Wrap(
        spacing: 6,
        children: [
          for (final (m, label) in const [
            (KeyframeMode.cubic, 'Smooth'),
            (KeyframeMode.linear, 'Linear'),
            (KeyframeMode.discrete, 'Stepped'),
          ])
            KinesisChip(
              label: label,
              selected: _mode == m,
              accent: palette.teal,
              onTap: () => _setMode(m),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(color: palette.well),
              child: SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: _OrbitPainter(
                    pos: _pos,
                    hue: _hue,
                    keyframes: _pos.keyframes,
                    palette: palette,
                  ),
                ),
              ),
            ),
          ),
          InspectorDrawer(
            apis: const ['MotionKeyframes', 'KeyframeMode', 'KeyframeValue'],
            child: Text(
              'mode: ${_mode.name}  |  duration: 2.8s  |  '
              'stops: ${_stops.length}  |  looping: true',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}

final class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.pos,
    required this.hue,
    required this.keyframes,
    required this.palette,
  }) : super(repaint: Listenable.merge([pos, hue]));

  final KeyframeValue<Offset> pos;
  final KeyframeValue<Color> hue;
  final MotionKeyframes<Offset> keyframes;
  final StudioPalette palette;

  Offset _map(Offset norm, Size size) => Offset(
    size.width * (0.5 + norm.dx * 0.45),
    size.height * (0.5 + norm.dy * 0.62),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final trail = Path();
    const n = 96;
    for (var i = 0; i <= n; i++) {
      final p = _map(keyframes.valueAt(keyframes.duration * i / n), size);
      if (i == 0) {
        trail.moveTo(p.dx, p.dy);
      } else {
        trail.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      trail,
      Paint()
        ..color = palette.textTertiary.withValues(alpha: 0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final stop in keyframes.stops) {
      final p = _map(stop.value, size);
      canvas.drawCircle(p, 4.5, Paint()..color = palette.surface);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = palette.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final current = _map(pos.value, size);
    canvas.drawCircle(
      current,
      20,
      Paint()..color = hue.value.withValues(alpha: 0.2),
    );
    canvas.drawCircle(current, 10, Paint()..color = hue.value);
    canvas.drawCircle(
      current - const Offset(3, 3),
      3,
      Paint()..color = const Color(0xAAFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      keyframes != oldDelegate.keyframes || palette != oldDelegate.palette;
}
