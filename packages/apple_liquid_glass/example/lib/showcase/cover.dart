import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/motion.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:flutter/widgets.dart';

/// The showcase's first page: the package's name in large letters, and
/// drops of clear glass that wander over it, bending the letters they
/// cross and fusing where they meet.
class Cover extends StatefulWidget {
  const Cover({super.key});

  @override
  State<Cover> createState() => _CoverState();
}

class _CoverState extends State<Cover> {
  final _drops = _Wander();

  @override
  void initState() {
    super.initState();
    _drops.start(MotionClock.instance.now);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DriftingWallpaper(wallpaper: Wallpaper.aurora),
        Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            padding.top,
            24,
            padding.bottom,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _drops.area = constraints.biggest;
              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  const Align(
                    alignment: Alignment(-1, -0.15),
                    child: Text(
                      'Liquid\nGlass',
                      style: TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 92,
                        height: 0.95,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -3.5,
                      ),
                    ),
                  ),
                  MotionScope(
                    motion: _drops,
                    child: GlassGroup(
                      merge: const GlassMerge.spacing(26),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final frame in _drops.frames)
                            GlassSurface.live(
                              frame: frame,
                              glass: const Glass.clear(),
                              child: const SizedBox.expand(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Four drops, each on a slow path of its own over the name.
final class _Wander extends Motion {
  _Wander() {
    own(_loop);
  }

  late final _loop = _Always();
  Size area = Size.zero;

  // Radius, the two paces of its path and where on the path it starts.
  static const _paths = <(double, double, double, double)>[
    (84, 0.23, 0.31, 0.0),
    (62, 0.29, 0.19, 1.7),
    (48, 0.17, 0.37, 3.1),
    (38, 0.35, 0.27, 4.6),
  ];

  late final List<MotionSelection<GlassFrame>> frames = [
    for (final (radius, paceX, paceY, phase) in _paths)
      select((wander) {
        final t = wander.now;
        final area = wander.area;
        return GlassFrame(
          shape: const GlassShape.oval(),
          rect: Rect.fromCircle(
            center: Offset(
              area.width * (0.4 + 0.36 * math.sin(t * paceX + phase)),
              area.height * (0.43 + 0.13 * math.sin(t * paceY + phase * 2)),
            ),
            radius: radius,
          ),
        );
      }),
  ];

  void start(double t) {
    advance(t);
    _loop.wake(t);
  }
}

// Keeps the motion on the clock: the paths are a function of its time.
final class _Always extends MotionLoop {
  _Always() : super(rate: 60, maxFrames: 1);

  @override
  bool step(double t) => true;
}
