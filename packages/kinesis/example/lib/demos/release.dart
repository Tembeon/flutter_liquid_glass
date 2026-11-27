import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class ReleaseDemo extends StatefulWidget {
  const ReleaseDemo({super.key});

  @override
  State<ReleaseDemo> createState() => _ReleaseDemoState();
}

class _ReleaseDemoState extends State<ReleaseDemo> {
  static const _knob = 36.0;
  static const _stops = [0.0, 0.5, 1.0];
  static const _band = RubberBand(0, 1, dimension: 1);
  static const _projection = Projection.normal;

  final _snap = MotionValue<double>(0);
  final _ghost = MotionValue<double>(0);
  final _ghostOpacity = MotionValue<double>(0);
  double _snapTravel = 1;
  double _snapFrom = 0;

  late final _snapDrag = DragInteraction(
    axis: Axis.horizontal,
    onStart: (_) => _snapFrom = _band.invert(_snap.value),
    onUpdate: (details) => _snap.target = _band.apply(
      _snapFrom + details.translation.dx / _snapTravel,
    ),
    onEnd: (details) {
      final position = _snap.value;
      final velocity = details.velocity.dx / _snapTravel;
      final stop = switch (_projection.choose(
        position,
        velocity,
        stops: _stops,
      )) {
        ProjectionStop(:final value) => value,
        ProjectionExited() => position,
      };
      _ghost.target = _projection.landing(position, velocity).clamp(-0.1, 1.1);
      _ghostOpacity.target = 1;
      withAnimation(
        const TimingCurve.easeOut(duration: 1.2),
        () => _ghostOpacity.target = 0,
      );
      _snap.velocity = velocity;
      withSpring(Spring.snappy, () => _snap.target = stop);
    },
  );

  static const _pages = 4;
  static const _paging = PagingPhysics();
  final _page = MotionValue<double>(0);
  double _pageWidth = 1;
  double _pageFrom = 0;

  RubberBand get _pageBand =>
      RubberBand(0, (_pages - 1) * _pageWidth, dimension: _pageWidth);

  late final _pageDrag = DragInteraction(
    axis: Axis.horizontal,
    onStart: (_) => _pageFrom = _pageBand.invert(_page.value),
    onUpdate: (details) =>
        _page.target = _pageBand.apply(_pageFrom - details.translation.dx),
    onEnd: (details) {
      final velocity = -details.velocity.dx;
      final target = _paging.targetOffset(
        offset: _page.value,
        pageExtent: _pageWidth,
        velocity: velocity,
        pageCount: _pages,
      );
      _page.velocity = velocity;
      withSpring(_paging.spring, () => _page.target = target);
    },
  );

  static const _rulerLength = 1600.0;
  final _glide = _Glide();
  double _rulerEnd = 0;
  double _glideFrom = 0;

  RubberBand get _glideBand =>
      RubberBand(0, _rulerEnd, dimension: _rulerLength - _rulerEnd);

  late final _glideDrag = DragInteraction(
    axis: Axis.horizontal,
    onStart: (details) {
      _glideFrom = _glideBand.invert(_glide.offset.value);
      _glide.hold(details.time);
    },
    onUpdate: (details) => _glide.drag(
      details.time,
      _glideBand.apply(_glideFrom - details.translation.dx),
    ),
    onEnd: (details) =>
        _glide.release(details.time, -details.velocity.dx, end: _rulerEnd),
  );

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'What happens when a finger lets go: where the release lands, '
          'which stop it picks, how far it overshoots an edge, and how it '
          'glides to rest. Each law is a plain value you call.',
      children: [
        Section(
          title: 'Projection picks a stop',
          caption:
              'Drag the knob and flick it. Projection adds the release '
              'velocity to the position, marks where it lands and picks the '
              'nearest stop. Past the ends, RubberBand resists the finger.',
          stage: MotionMeasure(
            onSize: (_, size) => _snapTravel = max(size.width - _knob, 1),
            child: InputRegion(
              interactions: [_snapDrag],
              child: Column(
                children: [
                  Rail(
                    child: Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        Travel(
                          progress: _ghost,
                          extent: _knob,
                          child: MotionTransition(
                            opacity: _ghostOpacity,
                            child: _Ring(color: palette.accent, size: _knob),
                          ),
                        ),
                        Travel(
                          progress: _snap,
                          extent: _knob,
                          child: Dot(color: palette.accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _knob / 2 - 1,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final _ in _stops)
                          SizedBox(
                            width: 2,
                            height: 8,
                            child: ColoredBox(color: palette.separator),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Section(
          title: 'Pages',
          caption:
              "PagingPhysics turns a release into UIKit's page target: a "
              'slow drag past half a page turns it, a flick turns it from '
              'anywhere.',
          stage: Column(
            children: [
              MotionMeasure(
                onSize: (_, size) => _pageWidth = max(size.width, 1),
                child: InputRegion(
                  interactions: [_pageDrag],
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 120,
                      child: LayoutBuilder(
                        builder: (context, constraints) => MotionTransition(
                          translateX: MotionSelection(() => -_page.value),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (var i = 0; i < _pages; i++)
                                Positioned(
                                  left: i * constraints.maxWidth,
                                  top: 0,
                                  bottom: 0,
                                  width: constraints.maxWidth,
                                  child: _PageCard(
                                    index: i,
                                    color: palette.swatches[i + 1],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: MotionTransition(
                        opacity: MotionSelection(
                          () => (1 - (_page.value / _pageWidth - i).abs())
                              .clamp(0.25, 1.0),
                        ),
                        child: Dot(color: palette.label, size: 8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Section(
          title: 'Glide',
          caption:
              "Flick the ruler. ScrollDeceleration is UIScrollView's "
              'deceleration and edge bounce, stepped frame by frame by a '
              'MotionLoop inside a Motion of our own.',
          stage: MotionScope(
            motion: _glide,
            child: MotionMeasure(
              onSize: (_, size) =>
                  _rulerEnd = max(_rulerLength - size.width, 0),
              child: InputRegion(
                interactions: [_glideDrag],
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ColoredBox(
                    color: palette.fill,
                    child: SizedBox(
                      height: 72,
                      child: MotionTransition(
                        translateX: _glide.shift,
                        child: OverflowBox(
                          alignment: AlignmentDirectional.centerStart,
                          minWidth: _rulerLength,
                          maxWidth: _rulerLength,
                          child: CustomPaint(
                            size: const Size(_rulerLength, 72),
                            painter: _RulerPainter(
                              color: palette.secondaryLabel,
                              accent: palette.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _Glide extends Motion {
  late final _loop = own(_GlideLoop());

  late final MotionSelection<double> offset = select((m) => m._loop.offset);
  late final MotionSelection<double> shift = select((m) => -m._loop.offset);

  void hold(double t) {
    advance(t);
    _loop.held = true;
  }

  void drag(double t, double to) {
    advance(t);
    _loop.offset = to;
    changed();
  }

  void release(double t, double velocity, {required double end}) {
    advance(t);
    _loop
      ..held = false
      ..velocity = velocity
      ..end = end;
    _loop.wake(t);
  }
}

final class _GlideLoop extends MotionLoop {
  double offset = 0;
  double velocity = 0;
  double end = 0;
  bool held = false;

  @override
  bool step(double t) {
    if (held) return false;
    final next = ScrollDeceleration.normal.step(
      offset: offset,
      velocity: velocity,
      dt: 1 / rate,
      min: 0,
      max: end,
    );
    offset = next.offset;
    velocity = next.velocity;
    return !next.settled;
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    ),
  );
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.index, required this.color});

  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          'Page ${index + 1}',
          style: TextStyles.headline.copyWith(color: const Color(0xFFFFFFFF)),
        ),
      ),
    ),
  );
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = 10.0; x < size.width; x += 20) {
      final major = (x - 10) % 100 == 0;
      final length = major ? 28.0 : 14.0;
      canvas.drawLine(
        Offset(x, size.height / 2 - length / 2),
        Offset(x, size.height / 2 + length / 2),
        tick..color = major ? accent : color,
      );
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.color != color || old.accent != accent;
}
