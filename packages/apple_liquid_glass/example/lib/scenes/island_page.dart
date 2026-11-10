import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/motion.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);
const _dim = Color(0x99FFFFFF);
const _smoked = Glass.regular(tint: Color(0xB8000000));

enum _Activity {
  timer('Timer', CupertinoIcons.timer, Color(0xFFFF9F0A), Size(0, 132)),
  music('Music', CupertinoIcons.music_note_2, Color(0xFFFF375F), Size(0, 176)),
  call('Call', CupertinoIcons.phone_fill, Color(0xFF30D158), Size(0, 84));

  const _Activity(this.title, this.icon, this.color, this.open);

  final String title;
  final IconData icon;
  final Color color;

  /// Its expanded size; a width of 0 is the page's.
  final Size open;
}

/// An island of glass at the top of the screen. An activity stretches it;
/// a second one splits a bubble off it, the two joined by a neck of glass
/// until they part, and a tap opens it into a panel. Every size is a spring
/// of one motion, so a tap in the middle of a change turns it around from
/// where it is, at the speed it has.
class IslandPage extends StatefulWidget {
  const IslandPage({this.preview = false, super.key});

  /// Whether the scene plays itself, with no bars and no controls: what the
  /// showcase shows of it.
  final bool preview;

  @override
  State<IslandPage> createState() => _IslandPageState();
}

class _IslandPageState extends State<IslandPage>
    with SingleTickerProviderStateMixin {
  static const _room = 190.0;

  final _island = _Island();
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  Timer? _second;
  Timer? _script;
  _Activity? _main;
  _Activity? _aside;
  var _open = false;
  var _playing = true;
  var _left = 5 * 60;
  var _talked = 0;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _beat.repeat();
    if (widget.preview) {
      // Left to itself, the island goes through what it can do.
      var step = 0;
      final script = <VoidCallback>[
        () => _toggle(_Activity.timer),
        () => _toggle(_Activity.music),
        _tapped,
        _close,
        () => _toggle(_Activity.call),
        _tapped,
        _close,
        () => _toggle(_Activity.call),
        () => _toggle(_Activity.music),
        () => _toggle(_Activity.timer),
      ];
      _script = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => script[step++ % script.length](),
      );
    }
    _second = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_runs(_Activity.timer) && !_runs(_Activity.call)) return;
      setState(() {
        if (_runs(_Activity.timer)) _left = _left > 0 ? _left - 1 : 5 * 60;
        if (_runs(_Activity.call)) _talked++;
      });
    });
  }

  @override
  void dispose() {
    _second?.cancel();
    _script?.cancel();
    _beat.dispose();
    super.dispose();
  }

  bool _runs(_Activity activity) => _main == activity || _aside == activity;

  // The body's size in the state the page is in.
  Size get _size {
    final main = _main;
    if (main == null) return const Size(126, 37);
    if (_open) return Size(_width, main.open.height);
    return Size(main == _Activity.music ? 196 : 176, 37);
  }

  void _settle({bool opening = false}) => _island.shape(
    MotionClock.instance.now,
    _size,
    corner: _open ? 42 : 18.5,
    aside: _aside != null && !_open,
    spring: opening ? Spring.bouncy : Spring.snappy,
  );

  void _toggle(_Activity activity) {
    if (!widget.preview) unawaited(HapticFeedback.selectionClick());
    setState(() {
      _open = false;
      if (_main == activity) {
        _main = _aside;
        _aside = null;
      } else if (_aside == activity) {
        _aside = null;
      } else {
        _aside = _main;
        _main = activity;
        if (activity == _Activity.call) _talked = 0;
      }
    });
    _settle(opening: true);
  }

  void _tapped() {
    if (_main == null) return;
    if (!widget.preview) unawaited(HapticFeedback.selectionClick());
    setState(() => _open = !_open);
    _settle(opening: _open);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _settle();
  }

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: GlassTheme(
        data: const GlassThemeData(brightness: Brightness.dark),
        child: GlassPageScaffold(
          backgroundColor: const Color(0xFF000000),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DriftingWallpaper(wallpaper: Wallpaper.dunes),
                const ColoredBox(color: Color(0x33000000)),
                Positioned(
                  left: 12,
                  right: 12,
                  top: media.padding.top + 10,
                  height: _room,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (_width != constraints.maxWidth) {
                        _width = constraints.maxWidth;
                        _island.place(MotionClock.instance.now, _width, _size);
                      }
                      return _islandOf();
                    },
                  ),
                ),
                if (!widget.preview)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: media.padding.bottom + 16,
                    child: _launcher(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _islandOf() => MotionScope(
    motion: _island,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Closer than the gap they rest at, the two are one body.
        GlassGroup(
          merge: const GlassMerge.spacing(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GlassSurface.live(
                frame: _island.bubble,
                glass: _smoked,
                child: const SizedBox.expand(),
              ),
              GlassSurface.live(
                frame: _island.body,
                glass: _smoked,
                child: const SizedBox.expand(),
              ),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _island.bubble,
          builder: (context, frame, child) => Positioned.fromRect(
            rect: frame.rect!,
            child: Opacity(opacity: frame.opacity, child: child),
          ),
          child: Icon(
            (_aside ?? _Activity.timer).icon,
            size: 18,
            color: (_aside ?? _Activity.timer).color,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _island.body,
          builder: (context, frame, child) => Positioned.fromRect(
            rect: frame.rect!,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(_island.cornerNow),
              child: child,
            ),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tapped,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: OverflowBox(
                key: ValueKey((_main, _open)),
                minWidth: _size.width,
                maxWidth: _size.width,
                minHeight: _size.height,
                maxHeight: _size.height,
                child: _content(),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _content() => switch ((_main, _open)) {
    (null, _) => const SizedBox.expand(),
    (final main?, false) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(main.icon, size: 19, color: main.color),
          const Spacer(),
          switch (main) {
            _Activity.timer => _digits(_clock(_left), main.color, 15),
            _Activity.call => _digits(_clock(_talked), main.color, 15),
            _Activity.music => SizedBox(
              width: 26,
              height: 18,
              child: CustomPaint(
                painter: _Bars(_beat, main.color, moving: _playing),
              ),
            ),
          },
        ],
      ),
    ),
    (_Activity.timer, true) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          _round(CupertinoIcons.pause_fill, const Color(0x4DFF9F0A), () {}),
          const SizedBox(width: 12),
          _round(
            CupertinoIcons.xmark,
            const Color(0x33FFFFFF),
            () => _toggle(_Activity.timer),
          ),
          const Spacer(),
          const Text('Timer', style: TextStyle(color: _dim, fontSize: 17)),
          const SizedBox(width: 10),
          _digits(_clock(_left), _Activity.timer.color, 46),
        ],
      ),
    ),
    (_Activity.call, true) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: ShapeDecoration(
              color: Color(0xFF5E5CE6),
              shape: CircleBorder(),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Text(
                  'T',
                  style: TextStyle(color: _white, fontSize: 22),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _clock(_talked),
                  style: const TextStyle(color: _dim, fontSize: 14),
                ),
                const Text(
                  'Tim',
                  style: TextStyle(
                    color: _white,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _round(
            CupertinoIcons.phone_down_fill,
            const Color(0xFFFF453A),
            () => _toggle(_Activity.call),
          ),
          const SizedBox(width: 12),
          _round(CupertinoIcons.speaker_2_fill, const Color(0x33FFFFFF), () {}),
        ],
      ),
    ),
    (_Activity.music, true) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        children: [
          Row(
            children: [
              ClipRSuperellipse(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: Wallpaper.bloom.image,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liquid Dreams',
                      maxLines: 1,
                      style: TextStyle(
                        color: _white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Meniscus',
                      style: TextStyle(color: _dim, fontSize: 15),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 30,
                height: 22,
                child: CustomPaint(
                  painter: _Bars(
                    _beat,
                    _Activity.music.color,
                    moving: _playing,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SizedBox(
            height: 5,
            width: double.infinity,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: Color(0x40FFFFFF),
                shape: StadiumBorder(),
              ),
              child: FractionallySizedBox(
                widthFactor: 0.38,
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: _white,
                    shape: StadiumBorder(),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _glyph(CupertinoIcons.backward_fill, () {}),
              _glyph(
                _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                () => setState(() => _playing = !_playing),
                size: 34,
              ),
              _glyph(CupertinoIcons.forward_fill, () {}),
            ],
          ),
        ],
      ),
    ),
  };

  Widget _digits(String text, Color color, double size) => Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: size > 20 ? FontWeight.w300 : FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _round(IconData icon, Color color, VoidCallback onPressed) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: color,
            shape: const CircleBorder(),
          ),
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, color: _white, size: 22),
          ),
        ),
      );

  Widget _glyph(IconData icon, VoidCallback onPressed, {double size = 26}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: Icon(icon, color: _white, size: size),
        ),
      );

  Widget _launcher(BuildContext context) => Column(
    children: [
      const PhotoText('Start an activity, then a second one.'),
      const PhotoText('Tap the island to open it.'),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final activity in _Activity.values)
            _Launch(
              activity: activity,
              running: _runs(activity),
              onPressed: () => _toggle(activity),
            ),
          SizedBox.square(
            dimension: 62,
            child: GlassButton(
              onPressed: () => Navigator.of(context).maybePop(),
              semanticLabel: 'Done',
              child: const Icon(CupertinoIcons.xmark),
            ),
          ),
        ],
      ),
    ],
  );
}

/// The round button that starts or ends an activity, filled while it runs.
class _Launch extends StatelessWidget {
  const _Launch({
    required this.activity,
    required this.running,
    required this.onPressed,
  });

  final _Activity activity;
  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 62,
    child: GlassPressable(
      onPressed: onPressed,
      shape: const GlassShape.oval(),
      semanticLabel: activity.title,
      builder: (context, details) => GlassSurface.live(
        frame: details.body,
        glass: Glass.clear(tint: running ? activity.color : null),
        child: Center(child: details.label),
      ),
      child: Icon(activity.icon, color: _white, size: 26),
    ),
  );
}

/// The island's body and the bubble beside it: a width, a height, a corner
/// and how far the bubble stands out, each on a spring.
final class _Island extends Motion {
  static const _bubble = 37.0;
  static const _gap = 9.0;

  late final _width = own(MotionValue<double>(126));
  late final _height = own(MotionValue<double>(37));
  late final _corner = own(MotionValue<double>(18.5));
  late final _out = own(MotionValue<double>(0));
  double _page = 0;

  /// The body's corner radius now.
  double get cornerNow => _corner.valueAt(now);

  Rect _bodyAt(double t) {
    final width = _width.valueAt(t);
    // The pair stays centered as the bubble leaves.
    final shift = _out.valueAt(t).clamp(0.0, 1.0) * (_gap + _bubble) / 2;
    return Rect.fromLTWH(
      (_page - width) / 2 - shift,
      0,
      width,
      _height.valueAt(t),
    );
  }

  late final MotionSelection<GlassFrame> body = select((island) {
    final t = island.now;
    return GlassFrame(
      shape: GlassShape.superellipse(island._corner.valueAt(t)),
      rect: island._bodyAt(t),
    );
  });

  late final MotionSelection<GlassFrame> bubble = select((island) {
    final t = island.now;
    final out = island._out.valueAt(t);
    final body = island._bodyAt(t);
    return GlassFrame(
      shape: const GlassShape.oval(),
      rect: Rect.fromLTWH(
        body.right - _bubble + out * (_gap + _bubble),
        0,
        _bubble,
        _bubble,
      ),
      opacity: (out * 6).clamp(0.0, 1.0),
    );
  });

  /// Lays the island out in a page [width] wide, at rest.
  void place(double t, double width, Size size) {
    advance(t);
    _page = width;
    _width.snap(t, size.width);
    _height.snap(t, size.height);
  }

  /// Sends the island toward [size] and [corner], its bubble out or in.
  void shape(
    double t,
    Size size, {
    required double corner,
    required bool aside,
    required Spring spring,
  }) {
    advance(t);
    _width.retarget(t, size.width, spring: spring);
    _height.retarget(t, size.height, spring: spring);
    _corner.retarget(t, corner, spring: Spring.smooth);
    _out.retarget(t, aside ? 1 : 0, spring: spring);
  }
}

/// Five bars that dance while [moving].
class _Bars extends CustomPainter {
  _Bars(this.beat, this.color, {required this.moving}) : super(repaint: beat);

  final Animation<double> beat;
  final Color color;
  final bool moving;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 5;
    final width = size.width / (count * 2 - 1);
    final bar = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final wave = moving
          ? 0.5 + 0.5 * math.sin(beat.value * 2 * math.pi * (2 + i % 3) + i)
          : 0.15;
      final height = size.height * (0.25 + 0.75 * wave);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * 2 * width,
            (size.height - height) / 2,
            width,
            height,
          ),
          Radius.circular(width / 2),
        ),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(_Bars old) => old.color != color || old.moving != moving;
}
