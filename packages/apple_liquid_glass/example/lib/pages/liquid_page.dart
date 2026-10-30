import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/settings_sheet.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// Glass drops floating over a drifting wallpaper. A finger lifts a drop and
/// drags it; drops that come close fuse into one body, and a released drop
/// flies home on a bouncy spring with the finger's momentum.
///
/// The drops and the wallpaper move for a while after the page shows or a
/// finger touches it, then come to rest, so a page nobody touches draws no
/// frames.
class LiquidPage extends StatefulWidget {
  const LiquidPage({super.key});

  @override
  State<LiquidPage> createState() => _LiquidPageState();
}

class _LiquidPageState extends State<LiquidPage> {
  static const _float = Spring(duration: Duration(milliseconds: 3200));
  static const _awake = Duration(seconds: 12);

  final _random = math.Random(7);
  var _wallpaper = Wallpaper.aurora;
  var _clear = true;
  var _fusion = 28.0;
  late final List<_Drop> _drops = [
    _Drop(
      home: const Alignment(-0.45, -0.22),
      size: (w) => Size.square(w * 0.36),
      child: const Icon(
        CupertinoIcons.drop_fill,
        size: 44,
        color: Color(0xFFFFFFFF),
      ),
    ),
    _Drop(
      home: const Alignment(0.55, -0.3),
      size: (w) => Size.square(w * 0.22),
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: const Icon(
        CupertinoIcons.sparkles,
        size: 30,
        color: Color(0xFFFFFFFF),
      ),
    ),
    _Drop(
      home: const Alignment(0.3, 0.08),
      size: (w) => Size(w * 0.52, 68),
      child: const PhotoText('Liquid', size: 26, weight: FontWeight.w600),
    ),
    _Drop(
      home: const Alignment(-0.55, 0.4),
      size: (w) => Size.square(w * 0.2),
      child: const Icon(
        CupertinoIcons.heart_fill,
        size: 26,
        color: Color(0xFFFFFFFF),
      ),
    ),
    _Drop(
      home: const Alignment(0.35, 0.5),
      size: (w) => Size.square(w * 0.28),
      child: const Icon(
        CupertinoIcons.moon_stars_fill,
        size: 34,
        color: Color(0xFFFFFFFF),
      ),
    ),
  ];
  final _grabs = <int, _Grab>{};
  Size _size = Size.zero;
  Timer? _floating;
  Timer? _asleep;
  var _drifting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _wake();
    } else {
      _rest();
    }
  }

  @override
  void dispose() {
    _floating?.cancel();
    _asleep?.cancel();
    super.dispose();
  }

  void _wake() {
    _asleep?.cancel();
    _asleep = Timer(_awake, () => setState(_rest));
    if (_drifting) return;
    _drifting = true;
    _floating = Timer.periodic(
      const Duration(milliseconds: 2600),
      (_) => _drift(),
    );
    _drift();
  }

  void _rest() {
    _floating?.cancel();
    _asleep?.cancel();
    if (!_drifting) return;
    _drifting = false;
    withSpring(_float, () {
      for (final drop in _drops) {
        drop.drift.target = Offset.zero;
      }
    });
  }

  void _drift() => withSpring(_float, () {
    for (final drop in _drops) {
      drop.drift.target = Offset(
        _random.nextDouble() * 18 - 9,
        _random.nextDouble() * 18 - 9,
      );
    }
  });

  void _layout(Size size) {
    if (size == _size) return;
    _size = size;
    withoutAnimation(() {
      for (final drop in _drops) {
        drop.measure(size);
        drop.center.target = drop.homeIn(size);
      }
    });
  }

  void _down(PointerDownEvent event) {
    if (_drifting) {
      _wake();
    } else {
      setState(_wake);
    }
    for (final drop in _drops.reversed) {
      if (_grabs.values.any((grab) => grab.drop == drop)) continue;
      if (!drop.rect.inflate(10).contains(event.localPosition)) continue;
      final grab = _Grab(drop, event.localPosition - drop.center.value);
      grab.velocity.addPosition(event.timeStamp, event.localPosition);
      _grabs[event.pointer] = grab;
      withoutAnimation(() => drop.touch.target = event.localPosition);
      withSpring(Spring.snappy, () => drop.press.target = 1);
      unawaited(HapticFeedback.selectionClick());
      return;
    }
  }

  void _move(PointerMoveEvent event) {
    final grab = _grabs[event.pointer];
    if (grab == null) return;
    grab.velocity.addPosition(event.timeStamp, event.localPosition);
    withoutAnimation(() => grab.drop.touch.target = event.localPosition);
    withSpring(
      Spring.interactive,
      () => grab.drop.center.target = event.localPosition - grab.offset,
      tracking: true,
    );
  }

  void _up(PointerEvent event) {
    final grab = _grabs.remove(event.pointer);
    if (grab == null) return;
    final drop = grab.drop;
    drop.center.velocity = grab.velocity.getVelocity().pixelsPerSecond;
    withSpring(Spring.bouncy, () {
      drop.center.target = drop.homeIn(_size);
      drop.press.target = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final glass = _clear ? const Glass.clear() : const Glass.regular();
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DriftingWallpaper(wallpaper: _wallpaper, drifts: _drifting),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _layout(constraints.biggest);
                return GlassGroup(
                  merge: _fusion < 1
                      ? const GlassMerge.none()
                      : GlassMerge.spacing(_fusion),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final drop in _drops)
                        Positioned.fromRect(
                          rect: drop.origin & drop.size,
                          child: GlassSurface.live(
                            frame: drop.frame,
                            glass: glass,
                            child: Center(child: drop.child),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: media.padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                GlassButton(
                  onPressed: () => showGallerySettings(context),
                  semanticLabel: 'Settings',
                  child: const Icon(CupertinoIcons.gear),
                ),
                const Spacer(),
                GlassButton(
                  onPressed: null,
                  semanticLabel: 'Look',
                  menuChildren: _menu(context),
                  child: const Icon(CupertinoIcons.paintbrush),
                ),
              ],
            ),
          ),
          Positioned(
            top: media.padding.top + 64,
            left: 24,
            right: 24,
            child: const IgnorePointer(
              child: Column(
                children: [
                  PhotoText(
                    'Liquid Glass',
                    size: 34,
                    weight: FontWeight.w700,
                  ),
                  SizedBox(height: 4),
                  PhotoText('Grab a drop. Bring two together.'),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: media.padding.bottom + 16,
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.circle_grid_hex,
                  color: Color(0xFFFFFFFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassSlider(
                    value: _fusion,
                    max: 60,
                    semanticLabel: 'Fusion',
                    onChanged: (value) => setState(() => _fusion = value),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  CupertinoIcons.drop_fill,
                  color: Color(0xFFFFFFFF),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<GlassMenuEntry> _menu(BuildContext context) {
    final renderer = GallerySettingsScope.of(context).value.renderer;
    return [
      GlassMenuSection(
        title: 'Wallpaper',
        singleSelection: true,
        children: [
          for (final wallpaper in Wallpaper.values)
            GlassMenuItem(
              title: wallpaper.title,
              state: wallpaper == _wallpaper
                  ? GlassMenuItemState.on
                  : GlassMenuItemState.off,
              onPressed: () => setState(() => _wallpaper = wallpaper),
            ),
        ],
      ),
      GlassMenuSection(
        title: 'Glass',
        singleSelection: true,
        elementSize: GlassMenuElementSize.medium,
        children: [
          GlassMenuItem(
            title: 'Regular',
            icon: const Icon(CupertinoIcons.drop_fill),
            state: _clear ? GlassMenuItemState.off : GlassMenuItemState.on,
            onPressed: () => setState(() => _clear = false),
          ),
          GlassMenuItem(
            title: 'Clear',
            icon: const Icon(CupertinoIcons.drop),
            state: _clear ? GlassMenuItemState.on : GlassMenuItemState.off,
            onPressed: () => setState(() => _clear = true),
          ),
        ],
      ),
      GlassSubmenu(
        title: 'Renderer',
        subtitle: renderer.title,
        icon: const Icon(CupertinoIcons.cube),
        singleSelection: true,
        children: [
          for (final option in GalleryRenderer.values)
            GlassMenuItem(
              title: option.title,
              state: option == renderer
                  ? GlassMenuItemState.on
                  : GlassMenuItemState.off,
              onPressed: () => GallerySettingsScope.update(
                context,
                (s) => s.copyWith(renderer: option),
              ),
            ),
        ],
      ),
    ];
  }
}

class _Grab {
  _Grab(this.drop, this.offset);

  final _Drop drop;
  final Offset offset;
  final velocity = VelocityTracker.withKind(PointerDeviceKind.touch);
}

class _Drop {
  _Drop({
    required this.home,
    required Size Function(double width) size,
    required this.child,
    this.shape = GlassFrame.capsule,
  }) : _sizeFor = size;

  final Alignment home;
  final Size Function(double width) _sizeFor;
  final LiquidShape shape;
  final Widget child;
  Size size = Size.zero;

  final center = MotionValue(Offset.zero);
  final drift = MotionValue(Offset.zero);
  final press = MotionValue<double>(0);
  final touch = MotionValue(Offset.zero);

  /// The top left of the box the drop is laid out in, at home. The body
  /// moves inside a box of its own size, where every renderer moves the
  /// content with it the same way.
  Offset origin = Offset.zero;

  late final MotionComputed<GlassFrame> frame = MotionComputed(() {
    final pressed = press.value;
    final scale = 1 + 0.14 * pressed;
    final local = center.value + drift.value - origin;
    final middle = size.center(Offset.zero);
    return GlassFrame(
      shape: shape,
      rect: Rect.fromCenter(
        center: local,
        width: size.width,
        height: size.height,
      ),
      scaleX: scale,
      scaleY: scale,
      glow: pressed < 0.01
          ? null
          : GlassTouchGlow(
              wash: 0.03 * pressed,
              center: middle + (touch.value - origin - local) / scale,
              radius: 0.568 * size.shortestSide,
              spot: 0.22 * pressed,
            ),
    );
  });

  Rect get rect => Rect.fromCenter(
    center: center.value + drift.value,
    width: size.width,
    height: size.height,
  );

  void measure(Size area) {
    size = _sizeFor(area.width);
    origin = homeIn(area) - size.center(Offset.zero);
  }

  Offset homeIn(Size area) => home.alongSize(area);
}
