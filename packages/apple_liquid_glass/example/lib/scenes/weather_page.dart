import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);
const _dim = Color(0xA6FFFFFF);
const _card = Glass.clear(tint: Color(0x2E0A1830));

/// A weather page over a sky that is painted live: its colors turn with
/// the hour, the sun and the moon cross it, stars come out, clouds drift
/// and rain falls. The cards are glass, so the whole day passes through
/// their rims, and the slider at the bottom scrubs it by hand.
class WeatherPage extends StatefulWidget {
  const WeatherPage({this.preview = false, super.key});

  /// Whether the scene plays itself, with no bars and no controls: what the
  /// showcase shows of it.
  final bool preview;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage>
    with SingleTickerProviderStateMixin {
  static const _days = ['Today', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // One turn is ten minutes of drifting clouds.
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(minutes: 10),
  );
  final _hour = ValueNotifier<double>(16.5);

  // The hour the cards show: a quarter at a time, so a sky that turns
  // every frame builds them four times an hour.
  final _shown = ValueNotifier<double>(16.5);
  var _rain = false;

  @override
  void initState() {
    super.initState();
    _drift.repeat();
    _hour.addListener(
      () => _shown.value = (_hour.value * 4).floorToDouble() / 4,
    );
    // Left to itself, the day passes: an hour every two seconds.
    if (widget.preview) {
      _drift.addListener(
        () => _hour.value = (16.5 + _drift.value * 300) % 24,
      );
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _hour.dispose();
    _shown.dispose();
    super.dispose();
  }

  // The day's curve: coolest before dawn, warmest in the afternoon.
  static int _degrees(double hour) =>
      (17 + 6 * math.sin((hour - 9.5) / 24 * 2 * math.pi)).round();

  static bool _night(double hour) => hour < 6 || hour >= 19.5;

  IconData _icon(double hour) {
    if (_rain) return CupertinoIcons.cloud_rain_fill;
    if (_night(hour % 24)) return CupertinoIcons.moon_stars_fill;
    return (hour % 24) < 11
        ? CupertinoIcons.cloud_sun_fill
        : CupertinoIcons.sun_max_fill;
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: GlassPageScaffold(
        backgroundColor: const Color(0xFF000000),
        navigationBar: widget.preview
            ? null
            : GlassNavigationBar(
                title: const Text('Weather'),
                previousPageTitle: 'Showcase',
                trailing: [
                  GlassBarItem(
                    icon: Icon(
                      _rain
                          ? CupertinoIcons.cloud_rain_fill
                          : CupertinoIcons.cloud,
                    ),
                    semanticLabel: _rain ? 'Stop the rain' : 'Let it rain',
                    onPressed: () => setState(() => _rain = !_rain),
                  ),
                ],
              ),
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _Sky(hour: _hour, drift: _drift, rain: _rain),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _shown,
                  builder: (context, hour, _) => GlassContentScroll(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        padding.top + 4,
                        16,
                        padding.bottom + (widget.preview ? 0 : 92),
                      ),
                      children: [
                        _now(hour),
                        const SizedBox(height: 18),
                        _hourly(hour),
                        // A preview has room for the day, not the week.
                        if (!widget.preview) ...[
                          const SizedBox(height: 12),
                          _week(),
                        ],
                        const SizedBox(height: 12),
                        _details(hour),
                      ],
                    ),
                  ),
                ),
                if (!widget.preview)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: padding.bottom + 12,
                    child: _scrubber(),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _now(double hour) => Column(
    children: [
      const PhotoText('Lisbon', size: 30, weight: FontWeight.w500),
      PhotoText('${_degrees(hour)}°', size: 88, weight: FontWeight.w200),
      PhotoText(
        _rain
            ? 'Rain'
            : _night(hour)
            ? 'Clear'
            : 'Sunny',
        size: 19,
        weight: FontWeight.w500,
      ),
      const PhotoText('H:23°  L:11°', size: 17),
    ],
  );

  Widget _titled(IconData icon, String title, Widget child) => GlassSurface(
    shape: const GlassShape.superellipse(22),
    glass: _card,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: _dim),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: _dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );

  Widget _hourly(double hour) => _titled(
    CupertinoIcons.clock,
    'HOURLY FORECAST',
    SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 16,
        separatorBuilder: (context, index) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final at = hour.floor() + index;
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                index == 0 ? 'Now' : '${at % 24}',
                style: const TextStyle(
                  color: _white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(_icon(at.toDouble()), color: _white, size: 24),
              Text(
                '${_degrees(at.toDouble())}°',
                style: const TextStyle(
                  color: _white,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _week() => _titled(
    CupertinoIcons.calendar,
    '7-DAY FORECAST',
    Column(
      children: [
        for (final (index, day) in _days.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    day,
                    style: const TextStyle(
                      color: _white,
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  index.isOdd && !_rain
                      ? CupertinoIcons.cloud_sun_fill
                      : _icon(13),
                  color: _white,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Text(
                  '${9 + index % 3 * 2}°',
                  style: const TextStyle(color: _dim, fontSize: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 5,
                    child: CustomPaint(
                      painter: _Range(
                        from: 0.08 + index % 3 * 0.1,
                        to: 0.72 + index % 4 * 0.07,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${20 + index % 4}°',
                  style: const TextStyle(color: _white, fontSize: 19),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _details(double hour) {
    final daylight = ((hour - 6) / 13.5).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: _titled(
            CupertinoIcons.sunset_fill,
            'SUNSET',
            SizedBox(
              height: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '19:32',
                    style: TextStyle(color: _white, fontSize: 28),
                  ),
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _Arc(daylight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _titled(
            CupertinoIcons.wind,
            'WIND',
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '12',
                          style: TextStyle(color: _white, fontSize: 28),
                        ),
                        Text(
                          'km/h',
                          style: TextStyle(color: _dim, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  SizedBox.square(
                    dimension: 84,
                    child: AnimatedBuilder(
                      animation: _drift,
                      builder: (context, _) => CustomPaint(
                        painter: _Compass(
                          0.6 +
                              0.35 * math.sin(_drift.value * 2 * math.pi * 40),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scrubber() => GlassSurface(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          const Icon(CupertinoIcons.sunrise_fill, color: _white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _hour,
              builder: (context, hour, _) => GlassSlider(
                value: hour,
                max: 24,
                semanticLabel: 'Hour of the day',
                onChanged: (value) => _hour.value = value,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(CupertinoIcons.moon_fill, color: _white, size: 18),
        ],
      ),
    ),
  );
}

/// The sky at an hour: its colors, the sun or the moon on their arcs, the
/// stars, drifting clouds and the rain.
class _Sky extends CustomPainter {
  _Sky({required this.hour, required this.drift, required this.rain})
    : super(repaint: Listenable.merge([hour, drift]));

  final ValueNotifier<double> hour;
  final Animation<double> drift;
  final bool rain;

  // The hour, the zenith and the horizon.
  static const _keys = <(double, Color, Color)>[
    (0, Color(0xFF04060F), Color(0xFF0E1830)),
    (5, Color(0xFF0B1230), Color(0xFF2A2F5E)),
    (6.5, Color(0xFF2E4A8C), Color(0xFFFFA27A)),
    (9, Color(0xFF2F7DDC), Color(0xFFA9D6FF)),
    (15, Color(0xFF2468C9), Color(0xFF8FC4FF)),
    (18.5, Color(0xFF34408F), Color(0xFFFF8A5C)),
    (20, Color(0xFF151A45), Color(0xFF7A3E72)),
    (22, Color(0xFF070A1C), Color(0xFF141E3C)),
    (24, Color(0xFF04060F), Color(0xFF0E1830)),
  ];

  static (Color, Color) _colors(double hour) {
    for (var i = 1; i < _keys.length; i++) {
      final (to, zenith, horizon) = _keys[i];
      if (hour > to) continue;
      final (from, zenith0, horizon0) = _keys[i - 1];
      final t = (hour - from) / (to - from);
      return (
        Color.lerp(zenith0, zenith, t)!,
        Color.lerp(horizon0, horizon, t)!,
      );
    }
    return (_keys.last.$2, _keys.last.$3);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hour = this.hour.value.clamp(0.0, 24.0);
    final seconds = drift.value * 600;
    final bounds = Offset.zero & size;
    final (zenith, horizon) = _colors(hour);
    final gray = rain ? 0.55 : 0.0;
    const overcast = Color(0xFF4A5566);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(zenith, overcast, gray * 0.8)!,
            Color.lerp(horizon, overcast, gray)!,
          ],
        ).createShader(bounds),
    );
    // How far the sun is below the horizon, 0 by day and 1 at night.
    final dark = (1 - (math.sin((hour - 6) / 13.5 * math.pi) * 3 + 0.4)).clamp(
      0.0,
      1.0,
    );
    _stars(canvas, size, seconds, dark * (1 - gray));
    final day = (hour - 6) / 13.5;
    if (day > -0.05 && day < 1.05) {
      _disc(
        canvas,
        Offset(
          size.width * (0.05 + 0.9 * day),
          size.height * (0.62 - 0.5 * math.sin(day * math.pi)),
        ),
        Color.lerp(
          const Color(0xFFFFF4D6),
          const Color(0xFFFFB36B),
          (2 * day - 1).abs(),
        )!,
        34,
        1 - gray,
      );
    }
    final night = ((hour + 4.5) % 24) / 10.5;
    if (night < 1.05) {
      final at = Offset(
        size.width * (0.1 + 0.8 * night),
        size.height * (0.5 - 0.36 * math.sin(night * math.pi)),
      );
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: at, radius: 22)),
          Path()..addOval(
            Rect.fromCircle(center: at + const Offset(11, -7), radius: 20),
          ),
        ),
        Paint()
          ..color = const Color(0xFFF2F4FF)
              .withValues(alpha: dark * (1 - gray)),
      );
    }
    _clouds(canvas, size, seconds, dark, gray);
    if (rain) _rain(canvas, size, seconds);
  }

  void _stars(Canvas canvas, Size size, double seconds, double shown) {
    if (shown < 0.02) return;
    final star = Paint();
    for (var i = 0; i < 70; i++) {
      final twinkle = 0.55 + 0.45 * math.sin(seconds * (0.6 + i % 5 * 0.3) + i);
      canvas.drawCircle(
        Offset(
          (i * 0.618034 % 1) * size.width,
          (i * 0.754877 % 1) * size.height * 0.8,
        ),
        0.6 + i % 3 * 0.5,
        star..color = _white.withValues(alpha: shown * twinkle),
      );
    }
  }

  void _disc(
    Canvas canvas,
    Offset at,
    Color color,
    double radius,
    double shown,
  ) {
    final halo = Rect.fromCircle(center: at, radius: radius * 5);
    canvas
      ..drawCircle(
        at,
        radius * 5,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.55 * shown),
              color.withValues(alpha: 0),
            ],
          ).createShader(halo),
      )
      ..drawCircle(at, radius, Paint()..color = color.withValues(alpha: shown));
  }

  void _clouds(
    Canvas canvas,
    Size size,
    double seconds,
    double dark,
    double gray,
  ) {
    final tone = Color.lerp(
      Color.lerp(_white, const Color(0xFF2A3350), dark),
      const Color(0xFF8792A3),
      gray,
    )!;
    final puff = Paint();
    final count = rain ? 9 : 5;
    for (var i = 0; i < count; i++) {
      final speed = 5 + i % 3 * 4.0;
      final span = size.width + 320;
      final x = (i * 137.0 + seconds * speed) % span - 160;
      final y = size.height * (0.1 + (i * 0.37 % 1) * 0.5);
      final scale = 0.8 + i % 4 * 0.25;
      for (final (dx, dy, r) in const [
        (-46.0, 8.0, 30.0),
        (-14.0, -8.0, 40.0),
        (24.0, 0.0, 34.0),
        (54.0, 10.0, 24.0),
      ]) {
        final center = Offset(x + dx * scale, y + dy * scale);
        final radius = r * scale * 1.5;
        canvas.drawCircle(
          center,
          radius,
          puff
            ..shader = RadialGradient(
              colors: [
                tone.withValues(alpha: 0.5 + 0.3 * gray),
                tone.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        );
      }
    }
  }

  void _rain(Canvas canvas, Size size, double seconds) {
    final streak = Paint()
      ..color = const Color(0x66DCE8FF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 110; i++) {
      final pace = 1.1 + i % 5 * 0.16;
      final fall = (i * 0.754877 + seconds * pace) % 1;
      final x = (i * 0.618034 % 1) * (size.width + 80) - 20 * fall;
      final y = fall * (size.height + 40) - 20;
      canvas.drawLine(Offset(x, y), Offset(x - 5, y + 18), streak);
    }
  }

  @override
  bool shouldRepaint(_Sky old) => old.rain != rain;
}

/// A day's range of temperatures on the week's scale.
class _Range extends CustomPainter {
  const _Range({required this.from, required this.to});

  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final range = Rect.fromLTRB(
      size.width * from,
      0,
      size.width * to,
      size.height,
    );
    canvas
      ..drawRRect(track, Paint()..color = const Color(0x33000000))
      ..drawRRect(
        RRect.fromRectAndRadius(range, Radius.circular(size.height / 2)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF64D2FF), Color(0xFFFFD60A), Color(0xFFFF9F0A)],
          ).createShader(Offset.zero & size),
      );
  }

  @override
  bool shouldRepaint(_Range old) => old.from != from || old.to != to;
}

/// The sun's way over the horizon, the sun at [daylight] of it.
class _Arc extends CustomPainter {
  const _Arc(this.daylight);

  final double daylight;

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.78;
    final way = Path()..moveTo(0, horizon);
    for (var i = 1; i <= 40; i++) {
      final t = i / 40;
      way.lineTo(
        size.width * t,
        horizon - math.sin(t * math.pi) * horizon * 0.9,
      );
    }
    final sun = Offset(
      size.width * daylight,
      horizon - math.sin(daylight * math.pi) * horizon * 0.9,
    );
    canvas
      ..drawPath(
        way,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x66FFFFFF),
      )
      ..drawLine(
        Offset(0, horizon),
        Offset(size.width, horizon),
        Paint()..color = const Color(0x4DFFFFFF),
      )
      ..drawCircle(sun, 9, Paint()..color = const Color(0x55FFD60A))
      ..drawCircle(sun, 5, Paint()..color = const Color(0xFFFFD60A));
  }

  @override
  bool shouldRepaint(_Arc old) => old.daylight != daylight;
}

/// A compass with its needle at [turn] radians.
class _Compass extends CustomPainter {
  const _Compass(this.turn);

  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final tick = Paint()
      ..color = const Color(0x80FFFFFF)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 36; i++) {
      final a = i / 36 * 2 * math.pi;
      final out = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + out * (radius - (i % 9 == 0 ? 9 : 5)),
        center + out * radius,
        tick,
      );
    }
    final way = Offset(math.cos(turn), math.sin(turn));
    final needle = Paint()
      ..color = _white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        center - way * (radius - 14),
        center + way * (radius - 14),
        needle,
      )
      ..drawCircle(center + way * (radius - 14), 5, Paint()..color = _white);
  }

  @override
  bool shouldRepaint(_Compass old) => old.turn != turn;
}
