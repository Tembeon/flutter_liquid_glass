import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);
const _dim = Color(0xB3FFFFFF);

/// A Lock Screen: the time over a drifting wallpaper, three glass widgets,
/// a stack of notifications that fans out into a list when it is tapped,
/// and the two round buttons at the bottom. A swipe up from the bottom
/// unlocks it, back to the gallery.
class LockScreenPage extends StatefulWidget {
  const LockScreenPage({super.key});

  @override
  State<LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends State<LockScreenPage> {
  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _notes = [
    (
      CupertinoIcons.chat_bubble_fill,
      Color(0xFF30D158),
      'Tim',
      'The pages are in: one pass a frame.',
      'now',
    ),
    (
      CupertinoIcons.calendar,
      Color(0xFFFF453A),
      'Design review',
      'In 20 minutes, the glass room',
      '9m ago',
    ),
    (
      CupertinoIcons.cloud_sun_fill,
      Color(0xFF0A84FF),
      'Weather',
      'Clear until the evening, then light rain',
      '32m ago',
    ),
  ];

  late DateTime _now = DateTime.now();
  Timer? _tick;
  var _open = false;
  var _torch = false;
  var _pull = 0.0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (now.minute != _now.minute) setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _date =>
      '${_days[_now.weekday - 1]}, ${_months[_now.month - 1]} ${_now.day}';

  String get _time => '${_now.hour}:${_now.minute.toString().padLeft(2, '0')}';

  void _released(DragEndDetails details) {
    final unlock = _pull > 120 || (details.primaryVelocity ?? 0) < -900;
    setState(() => _pull = 0);
    if (unlock) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The screen follows the finger up, and falls back if it lets go early.
    final lift = _pull / (1 + _pull / 400);
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: GlassPageScaffold(
          backgroundColor: const Color(0xFF000000),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DriftingWallpaper(wallpaper: Wallpaper.alpine),
              AnimatedSlide(
                offset: Offset(0, -lift / media.size.height),
                duration: Duration(milliseconds: _pull == 0 ? 380 : 0),
                curve: Curves.easeOutBack,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: media.padding.top + 28,
                    bottom: media.padding.bottom + 10,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        CupertinoIcons.lock_fill,
                        color: _white,
                        size: 20,
                      ),
                      const SizedBox(height: 14),
                      PhotoText(_date, size: 20, weight: FontWeight.w600),
                      PhotoText(_time, size: 96, weight: FontWeight.w600),
                      const SizedBox(height: 6),
                      _widgets(),
                      const Spacer(),
                      _notifications(media.size.width - 32),
                      const SizedBox(height: 18),
                      _buttons(),
                      const SizedBox(height: 10),
                      _handle(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _widgets() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 28),
    child: Row(
      children: [
        _Gauge(
          progress: 0.64,
          color: Color(0xFF30D158),
          child: Icon(CupertinoIcons.flame_fill, color: _white, size: 22),
        ),
        SizedBox(width: 12),
        _Gauge(
          progress: 0.82,
          color: Color(0xFFFFD60A),
          child: PhotoText('21', size: 20, weight: FontWeight.w600),
        ),
        SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 64,
            child: GlassSurface(
              glass: Glass.clear(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.calendar, color: _white, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Design review',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '10:30, the glass room',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _dim, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  // Closed, the cards lie on one another, each a little smaller and lower
  // than the one above; open, they stand in a list. One group draws them,
  // so the stack reads what lies behind it once.
  Widget _notifications(double width) {
    const height = 74.0;
    const gap = 8.0;
    final count = _notes.length;
    final total = _open ? count * height + (count - 1) * gap : height + 20;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        width: width,
        height: total,
        child: GlassGroup(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = count - 1; i >= 0; i--)
                AnimatedPositioned(
                  duration: Duration(milliseconds: 380 + i * 50),
                  curve: Curves.easeOutBack,
                  left: _open ? 0 : i * 10.0,
                  right: _open ? 0 : i * 10.0,
                  top: _open ? i * (height + gap) : i * 10.0,
                  height: height,
                  child: _Notification(
                    note: _notes[i],
                    showsText: _open || i == 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buttons() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 44),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _round(
          'Flashlight',
          _torch ? CupertinoIcons.lightbulb_fill : CupertinoIcons.lightbulb,
          _torch ? const Color(0xFFFFD60A) : null,
          () => setState(() => _torch = !_torch),
        ),
        _round('Camera', CupertinoIcons.camera_fill, null, () {}),
      ],
    ),
  );

  Widget _round(
    String label,
    IconData icon,
    Color? tint,
    VoidCallback onPressed,
  ) => SizedBox.square(
    dimension: 54,
    child: GlassPressable(
      onPressed: onPressed,
      shape: const GlassShape.oval(),
      semanticLabel: label,
      builder: (context, details) => GlassSurface.live(
        frame: details.body,
        glass: Glass.clear(tint: tint),
        child: Center(child: details.label),
      ),
      child: Icon(icon, color: _white, size: 24),
    ),
  );

  Widget _handle() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragUpdate: (details) =>
        setState(() => _pull = math.max(0, _pull - details.delta.dy)),
    onVerticalDragEnd: _released,
    child: const SizedBox(
      height: 44,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          PhotoText('Swipe up to open', size: 13),
          SizedBox(height: 8),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: _white,
              shape: StadiumBorder(),
            ),
            child: SizedBox(width: 134, height: 5),
          ),
        ],
      ),
    ),
  );
}

/// A round glass widget with a ring that shows [progress].
class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.progress,
    required this.color,
    required this.child,
  });

  final double progress;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 64,
    child: GlassSurface(
      shape: const GlassShape.oval(),
      glass: const Glass.clear(),
      child: CustomPaint(
        painter: _Ring(progress, color),
        child: Center(child: child),
      ),
    ),
  );
}

class _Ring extends CustomPainter {
  const _Ring(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(7);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      stroke..color = const Color(0x33FFFFFF),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.progress != progress || old.color != color;
}

class _Notification extends StatelessWidget {
  const _Notification({required this.note, required this.showsText});

  final (IconData, Color, String, String, String) note;
  final bool showsText;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body, age) = note;
    return GlassSurface(
      shape: const GlassShape.superellipse(24),
      child: AnimatedOpacity(
        opacity: showsText ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SettingsIcon(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          age,
                          style: const TextStyle(color: _dim, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _dim, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
