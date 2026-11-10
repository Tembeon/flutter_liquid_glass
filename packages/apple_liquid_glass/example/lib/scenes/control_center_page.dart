import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _white = Color(0xFFFFFFFF);
const _dim = Color(0x99FFFFFF);
const _well = Color(0x24FFFFFF);

/// Control Center, built from the package's surfaces alone: a platter of
/// round toggles, what is playing, a Focus capsule that fills with its
/// color, two tall sliders that fill under the finger and stretch past
/// their ends, and a row of round buttons. The modules rise into place one
/// after another when the page opens.
class ControlCenterPage extends StatefulWidget {
  const ControlCenterPage({this.preview = false, super.key});

  /// Whether the scene plays itself, with no bars and no controls: what the
  /// showcase shows of it.
  final bool preview;

  @override
  State<ControlCenterPage> createState() => _ControlCenterPageState();
}

class _ControlCenterPageState extends State<ControlCenterPage>
    with SingleTickerProviderStateMixin {
  static const _margin = 24.0;
  static const _gap = 14.0;

  late final _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  final _on = <String>{'Wi-Fi', 'Bluetooth'};
  var _playing = true;
  var _brightness = 0.62;
  var _volume = 0.38;

  @override
  void initState() {
    super.initState();
    _rise.forward();
    if (widget.preview) {
      // Left to itself, a module turns on or off now and then.
      var step = 0;
      const names = ['Focus', 'Flashlight', 'Cellular', 'Timer', 'Low Power'];
      _script = Timer.periodic(
        const Duration(milliseconds: 1400),
        (_) => _toggle(names[step++ % names.length]),
      );
    }
  }

  Timer? _script;

  @override
  void dispose() {
    _script?.cancel();
    _rise.dispose();
    super.dispose();
  }

  void _toggle(String name) => setState(() {
    if (!_on.remove(name)) _on.add(name);
  });

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: GlassPageScaffold(
        backgroundColor: const Color(0xFF000000),
        navigationBar: widget.preview
            ? null
            : const GlassNavigationBar(
                title: Text('Control Center'),
                previousPageTitle: 'Showcase',
              ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DriftingWallpaper(wallpaper: Wallpaper.city),
            const ColoredBox(color: Color(0x66000000)),
            Builder(builder: _modules),
          ],
        ),
      ),
    ),
  );

  Widget _modules(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 2 * _margin - 3 * _gap) / 4;
        final top = media.padding.top + 20;
        var index = 0;
        Widget at(int column, int row, int columns, int rows, Widget child) {
          final order = index++;
          return Positioned(
            left: _margin + column * (cell + _gap),
            top: top + row * (cell + _gap),
            width: columns * cell + (columns - 1) * _gap,
            height: rows * cell + (rows - 1) * _gap,
            child: _Rise(animation: _rise, order: order, child: child),
          );
        }

        return Stack(
          children: [
            at(0, 0, 2, 2, _connectivity(cell)),
            at(2, 0, 2, 2, _nowPlaying()),
            at(
              0,
              2,
              2,
              1,
              _Module(
                label: 'Focus',
                detail: _on.contains('Focus') ? 'Do Not Disturb' : 'Off',
                icon: CupertinoIcons.moon_fill,
                color: const Color(0xFF5E5CE6),
                on: _on.contains('Focus'),
                onPressed: () => _toggle('Focus'),
              ),
            ),
            at(
              2,
              2,
              1,
              2,
              _TallSlider(
                value: _brightness,
                icon: CupertinoIcons.sun_max_fill,
                semanticLabel: 'Brightness',
                onChanged: (value) => setState(() => _brightness = value),
              ),
            ),
            at(
              3,
              2,
              1,
              2,
              _TallSlider(
                value: _volume,
                icon: _volume == 0
                    ? CupertinoIcons.speaker_slash_fill
                    : _volume < 0.5
                    ? CupertinoIcons.speaker_1_fill
                    : CupertinoIcons.speaker_3_fill,
                semanticLabel: 'Volume',
                onChanged: (value) => setState(() => _volume = value),
              ),
            ),
            at(
              0,
              3,
              1,
              1,
              _round(
                'Rotation Lock',
                CupertinoIcons.lock_rotation,
                const Color(0xFFFF453A),
              ),
            ),
            at(
              1,
              3,
              1,
              1,
              _round(
                'Screen Mirroring',
                CupertinoIcons.rectangle_on_rectangle,
                const Color(0xFF0A84FF),
              ),
            ),
            at(
              0,
              4,
              1,
              1,
              _round(
                'Flashlight',
                CupertinoIcons.lightbulb_fill,
                const Color(0xFFFFD60A),
              ),
            ),
            at(
              1,
              4,
              1,
              1,
              _round(
                'Timer',
                CupertinoIcons.timer,
                const Color(0xFFFF9F0A),
              ),
            ),
            at(
              2,
              4,
              1,
              1,
              _round(
                'Low Power',
                CupertinoIcons.battery_25,
                const Color(0xFF30D158),
              ),
            ),
            at(
              3,
              4,
              1,
              1,
              _round(
                'Camera',
                CupertinoIcons.camera_fill,
                const Color(0xFF64D2FF),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _round(String name, IconData icon, Color color) => _RoundToggle(
    icon: icon,
    color: color,
    on: _on.contains(name),
    semanticLabel: name,
    onPressed: () => _toggle(name),
  );

  // One platter holds the four toggles: they are painted wells, so the
  // platter reads what lies behind it once.
  Widget _connectivity(double cell) => GlassSurface(
    shape: const GlassShape.superellipse(34),
    glass: const Glass.clear(),
    child: Padding(
      padding: EdgeInsets.all(cell * 0.14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final row in const [
            [
              ('Airplane', CupertinoIcons.airplane, Color(0xFFFF9F0A)),
              (
                'Cellular',
                CupertinoIcons.antenna_radiowaves_left_right,
                Color(0xFF30D158),
              ),
            ],
            [
              ('Wi-Fi', CupertinoIcons.wifi, Color(0xFF0A84FF)),
              ('Bluetooth', CupertinoIcons.bluetooth, Color(0xFF0A84FF)),
            ],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (name, icon, color) in row)
                  _Well(
                    size: cell * 0.74,
                    icon: icon,
                    color: color,
                    on: _on.contains(name),
                    semanticLabel: name,
                    onPressed: () => _toggle(name),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _nowPlaying() => GlassSurface(
    shape: const GlassShape.superellipse(34),
    glass: const Glass.clear(),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRSuperellipse(
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  image: Wallpaper.bloom.image,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const Spacer(),
              const Icon(
                CupertinoIcons.dot_radiowaves_left_right,
                size: 20,
                color: _dim,
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Liquid Dreams',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            'Meniscus',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _dim, fontSize: 13),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(CupertinoIcons.backward_fill, color: _white),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _playing = !_playing),
                child: Semantics(
                  button: true,
                  label: _playing ? 'Pause' : 'Play',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        _playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        key: ValueKey(_playing),
                        color: _white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              const Icon(CupertinoIcons.forward_fill, color: _white),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A module on its way in: it grows and settles a little after the one
/// before it.
class _Rise extends StatelessWidget {
  const _Rise({
    required this.animation,
    required this.order,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (order * 0.05).clamp(0.0, 0.5);
    final rise = CurvedAnimation(
      parent: animation,
      curve: Interval(start, start + 0.5, curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: rise,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 36 * (1 - rise.value)),
        child: Transform.scale(scale: 0.86 + 0.14 * rise.value, child: child),
      ),
    );
  }
}

/// A round toggle painted inside a platter.
class _Well extends StatefulWidget {
  const _Well({
    required this.size,
    required this.icon,
    required this.color,
    required this.on,
    required this.semanticLabel,
    required this.onPressed,
  });

  final double size;
  final IconData icon;
  final Color color;
  final bool on;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  State<_Well> createState() => _WellState();
}

class _WellState extends State<_Well> {
  var _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: widget.on,
    label: widget.semanticLabel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.on ? widget.color : _well,
          ),
          child: Icon(widget.icon, color: _white, size: widget.size * 0.44),
        ),
      ),
    ),
  );
}

/// A round glass toggle with the measured press of a glass button, filled
/// with its color while it is on.
class _RoundToggle extends StatelessWidget {
  const _RoundToggle({
    required this.icon,
    required this.color,
    required this.on,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final bool on;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => GlassPressable(
    onPressed: onPressed,
    shape: const GlassShape.oval(),
    semanticLabel: semanticLabel,
    builder: (context, details) => GlassSurface.live(
      frame: details.body,
      glass: Glass.clear(tint: on ? color : null),
      child: Center(child: details.label),
    ),
    child: Icon(icon, color: _white, size: 28),
  );
}

/// A capsule with a title and a detail, filled with its color while on.
class _Module extends StatelessWidget {
  const _Module({
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
    required this.on,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => GlassPressable(
    onPressed: onPressed,
    semanticLabel: '$label, $detail',
    builder: (context, details) => GlassSurface.live(
      frame: details.body,
      glass: Glass.clear(tint: on ? color : null),
      child: details.label,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? _white : _well,
            ),
            child: SizedBox.square(
              dimension: 44,
              child: Icon(icon, color: on ? color : _white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _dim, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A tall glass slider: it fills from the bottom under the finger, and a
/// drag past either end stretches it a little before it springs back.
class _TallSlider extends StatefulWidget {
  const _TallSlider({
    required this.value,
    required this.icon,
    required this.semanticLabel,
    required this.onChanged,
  });

  final double value;
  final IconData icon;
  final String semanticLabel;
  final ValueChanged<double> onChanged;

  @override
  State<_TallSlider> createState() => _TallSliderState();
}

class _TallSliderState extends State<_TallSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(() => setState(() => _over = _from * (1 - _ease.value)));
  late final CurvedAnimation _ease = CurvedAnimation(
    parent: _settle,
    curve: Curves.elasticOut,
  );

  // How far past an end the finger pulls, in sliders: up is positive.
  var _over = 0.0;
  var _from = 0.0;
  var _raw = 0.0;

  @override
  void dispose() {
    _ease.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _start() {
    _settle.stop();
    _raw = widget.value;
  }

  void _drag(double delta, double height) {
    _raw -= delta / height;
    final value = _raw.clamp(0.0, 1.0);
    setState(() => _over = _raw - value);
    if (value != widget.value) widget.onChanged(value);
  }

  void _release() {
    _from = _over;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      // A pull stretches the body toward the finger, less the farther it
      // goes.
      final stretch = _over.abs() / (1 + 4 * _over.abs()) * 0.5;
      final filled = widget.value > 0.2;
      return Semantics(
        slider: true,
        label: widget.semanticLabel,
        value: '${(widget.value * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _start(),
          onVerticalDragUpdate: (details) => _drag(details.delta.dy, height),
          onVerticalDragEnd: (_) => _release(),
          onVerticalDragCancel: _release,
          child: Transform(
            alignment: _over >= 0
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            transform: Matrix4.diagonal3Values(
              1 - stretch * 0.5,
              1 + stretch,
              1,
            ),
            child: GlassSurface(
              shape: const GlassShape.superellipse(28),
              glass: const Glass.clear(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: widget.value,
                      widthFactor: 1,
                      child: const ColoredBox(color: Color(0xEBFFFFFF)),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.72),
                    child: Icon(
                      widget.icon,
                      size: 26,
                      color: filled ? const Color(0xFF3A3A3C) : _white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
