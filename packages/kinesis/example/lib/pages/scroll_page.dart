import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class ScrollPage extends StatelessWidget {
  const ScrollPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DecelerationReelCard(),
      SizedBox(height: 16),
      _PagingCarouselCard(),
    ],
  );
}

class _DecelerationReelCard extends StatefulWidget {
  const _DecelerationReelCard();

  @override
  State<_DecelerationReelCard> createState() => _DecelerationReelCardState();
}

class _DecelerationReelCardState extends State<_DecelerationReelCard> {
  static const int _itemCount = 24;
  static const double _itemHeight = 46;
  static const double _viewportHeight = 230;
  static const double _maxOffset = _itemCount * _itemHeight - _viewportHeight;

  late final MotionClock _clock = MotionClockScope.of(context);
  late final _ReelMotion _reel = _ReelMotion(
    maxOffset: _maxOffset,
    clock: _clock,
  );
  late final MotionValue<double> _scrollToTop = MotionValue<double>(
    0,
    clock: _clock,
  );

  bool _fastRate = false;
  double _dragStartOffset = 0;
  bool _animatingToTop = false;

  ScrollDeceleration get _decel =>
      _fastRate ? ScrollDeceleration.fast : ScrollDeceleration.normal;

  late final DragInteraction _drag = DragInteraction(
    axis: Axis.vertical,
    slop: 0,
    onStart: (details) {
      if (_animatingToTop) {
        _animatingToTop = false;
        _reel.setPosition(details.time, _scrollToTop.valueAt(details.time));
      }
      _reel.stop(details.time);
      _dragStartOffset = _reel.offset;
    },
    onUpdate: (details) {
      final raw = _dragStartOffset - details.translation.dy;
      const band = RubberBand(0, _maxOffset, dimension: _viewportHeight);
      _reel.setPosition(details.time, band.apply(raw));
    },
    onEnd: (details) {
      _reel.fling(details.time, -details.velocity.dy, _decel);
    },
    onCancel: (t) => _reel.fling(t, 0, _decel),
  );

  void _triggerScrollToTop() {
    final t = _clock.now;
    _reel.stop(t);
    _scrollToTop.snap(t, _reel.offset);
    _animatingToTop = true;
    _scrollToTop.animate(t, 0, animation: ScrollToTopCurve.timing);
  }

  @override
  void initState() {
    super.initState();
    _scrollToTop.addListener(_syncScrollToTop);
  }

  void _syncScrollToTop() {
    if (!_animatingToTop) return;
    final t = _clock.now;
    _reel.setPosition(t, _scrollToTop.value);
    if (_scrollToTop.restsAt(t)) {
      _animatingToTop = false;
    }
  }

  @override
  void dispose() {
    _scrollToTop.removeListener(_syncScrollToTop);
    _reel.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'iOS Scroll Deceleration & Edge Bounce',
      subtitle:
          'Momentum list driven directly by ScrollDeceleration.step on '
          'MotionClock (no Flutter ScrollView). Fling to see the predicted '
          'landing marker, pull past the ends for RubberBand + 0.5 pt snap, '
          'or jump back with ScrollToTopCurve (1.6 s).',
      apis: const [
        'ScrollDeceleration',
        'landingOffset',
        'ScrollToTopCurve',
        'RubberBand',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisChip(
                label: 'normal (0.998)',
                selected: !_fastRate,
                onTap: () => setState(() => _fastRate = false),
              ),
              KinesisChip(
                label: 'fast (0.99)',
                selected: _fastRate,
                accent: palette.orange,
                onTap: () => setState(() => _fastRate = true),
              ),
              KinesisButton(
                label: 'Scroll to Top (1.6s)',
                compact: true,
                filled: true,
                onPressed: _triggerScrollToTop,
              ),
            ],
          ),
          const SizedBox(height: 12),
          MotionScope(
            motion: _reel,
            child: InputRegion(
              interactions: [_drag],
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.well,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.hairline),
                ),
                child: SizedBox(
                  height: _viewportHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: CustomPaint(
                      painter: _ReelPainter(
                        reel: _reel,
                        itemCount: _itemCount,
                        itemHeight: _itemHeight,
                        maxOffset: _maxOffset,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReelMotion extends Motion {
  _ReelMotion({required this.maxOffset, super.clock}) {
    _loop = own(_ReelLoop(this));
  }

  final double maxOffset;
  late final _ReelLoop _loop;
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);
  double _velocity = 0;
  double? _predictedLanding;
  ScrollDeceleration _decel = ScrollDeceleration.normal;
  double _lastTime = 0;
  bool _coasting = false;

  ValueNotifier<double> get listenable => _offset;
  double get offset => _offset.value;
  double get velocity => _velocity;
  double? get predictedLanding => _predictedLanding;

  void setPosition(double t, double value) {
    _offset.value = value;
    _lastTime = t;
    changed();
  }

  void stop(double t) {
    _coasting = false;
    _velocity = 0;
    _predictedLanding = null;
    changed();
  }

  void fling(double t, double velocity, ScrollDeceleration decel) {
    _velocity = velocity;
    _decel = decel;
    _lastTime = t;
    _coasting = true;
    final rawLanding = decel.landingOffset(_offset.value, velocity);
    _predictedLanding = rawLanding.clamp(0.0, maxOffset);
    _loop.wake(t);
    changed();
  }

  bool _tick(double t) {
    if (!_coasting) return false;
    final dt = (t - _lastTime).clamp(0.0, 0.05);
    _lastTime = t;
    if (dt <= 0) return true;
    final step = _decel.step(
      offset: _offset.value,
      velocity: _velocity,
      dt: dt,
      min: 0,
      max: maxOffset,
    );
    _offset.value = step.offset;
    _velocity = step.velocity;
    if (step.settled) {
      _coasting = false;
    }
    changed();
    return _coasting;
  }

  void release() => _offset.dispose();
}

final class _ReelLoop extends MotionLoop {
  _ReelLoop(this._host);

  final _ReelMotion _host;

  @override
  bool step(double t) => _host._tick(t);
}

final class _ReelPainter extends CustomPainter {
  _ReelPainter({
    required this.reel,
    required this.itemCount,
    required this.itemHeight,
    required this.maxOffset,
    required this.palette,
  }) : super(repaint: reel.listenable);

  final _ReelMotion reel;
  final int itemCount;
  final double itemHeight;
  final double maxOffset;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = reel.offset;
    final colors = [
      palette.blue,
      palette.teal,
      palette.green,
      palette.orange,
      palette.purple,
      palette.indigo,
    ];

    for (var i = 0; i < itemCount; i++) {
      final top = i * itemHeight - offset + 8;
      if (top + itemHeight < 0 || top > size.height) continue;
      final rect = Rect.fromLTWH(12, top, size.width - 34, itemHeight - 8);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, Paint()..color = palette.surface);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = palette.hairline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(28, rect.center.dy),
        6,
        Paint()..color = colors[i % colors.length],
      );
      final tp = TextPainter(
        text: TextSpan(
          text: 'Row ${i + 1}  --  y=${(i * itemHeight).round()} pt',
          style: palette.label,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 42);
      tp.paint(canvas, Offset(44, rect.center.dy - tp.height / 2));
    }

    // Mini scroll track with predicted landing dot on the right edge.
    final trackRect = Rect.fromLTWH(size.width - 12, 12, 4, size.height - 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(2)),
      Paint()..color = palette.hairline,
    );
    final frac = (offset / maxOffset).clamp(0.0, 1.0);
    final thumbY = trackRect.top + (trackRect.height - 28) * frac;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackRect.left, thumbY, 4, 28),
        const Radius.circular(2),
      ),
      Paint()..color = palette.blue,
    );

    if (reel.predictedLanding case final landing?) {
      final landFrac = (landing / maxOffset).clamp(0.0, 1.0);
      final markerY = trackRect.top + (trackRect.height - 28) * landFrac + 14;
      canvas.drawCircle(
        Offset(trackRect.center.dx, markerY),
        4.5,
        Paint()..color = palette.orange,
      );
    }

    // Readout badge in top-right corner.
    final readout = TextPainter(
      text: TextSpan(
        text:
            'y=${offset.toStringAsFixed(0)}  '
            'v=${reel.velocity.toStringAsFixed(0)}',
        style: palette.mono,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badgeRect = Rect.fromLTWH(
      size.width - readout.width - 34,
      8,
      readout.width + 14,
      22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(8)),
      Paint()..color = palette.surface.withValues(alpha: 0.9),
    );
    readout.paint(canvas, Offset(badgeRect.left + 7, badgeRect.top + 4));
  }

  @override
  bool shouldRepaint(_ReelPainter oldDelegate) =>
      palette != oldDelegate.palette;
}

class _PagingCarouselCard extends StatefulWidget {
  const _PagingCarouselCard();

  @override
  State<_PagingCarouselCard> createState() => _PagingCarouselCardState();
}

class _PagingCarouselCardState extends State<_PagingCarouselCard> {
  static const int _pageCount = 5;
  static const PagingPhysics _physics = PagingPhysics();

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _offset = MotionValue<double>(
    0,
    clock: _clock,
  );
  int _page = 0;
  double _pageExtent = 280;
  double _dragStart = 0;

  late final DragInteraction _drag = DragInteraction(
    axis: Axis.horizontal,
    slop: 0,
    onStart: (details) => _dragStart = _offset.valueAt(details.time),
    onUpdate: (details) {
      final maxOff = (_pageCount - 1) * _pageExtent;
      final band = RubberBand(0, maxOff, dimension: _pageExtent);
      _offset.snap(
        details.time,
        band.apply(_dragStart - details.translation.dx),
      );
    },
    onEnd: (details) {
      final t = details.time;
      final current = _offset.valueAt(t);
      final next = _physics.targetPage(
        offset: current,
        pageExtent: _pageExtent,
        velocity: -details.velocity.dx,
        pageCount: _pageCount,
      );
      if (next != _page) {
        setState(() => _page = next);
        MotionHaptic.selection.play(context);
      }
      _offset.setVelocity(t, -details.velocity.dx);
      withSpring(
        _physics.spring,
        () => _offset.retarget(t, next * _pageExtent),
      );
    },
    onCancel: (t) {
      withSpring(
        _physics.spring,
        () => _offset.retarget(t, _page * _pageExtent),
      );
    },
  );

  void _goTo(int page) {
    final clamped = page.clamp(0, _pageCount - 1);
    setState(() => _page = clamped);
    withSpring(
      _physics.spring,
      () => _offset.retarget(_clock.now, clamped * _pageExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final titles = [
      ('Spring Physics', 'omega = 15.9, zeta = 0.88', palette.blue),
      ('Velocity Flip', '300 pt/s flick crosses a page', palette.purple),
      ('Rubber Band', 'Pull past edge for smooth tension', palette.orange),
      ('Zero Rebuild', 'Cards glide without setState frames', palette.green),
      ('Selection Haptics', '25 Hz throttled detent feedback', palette.teal),
    ];

    return StudioCard(
      title: 'PagingPhysics Card Deck',
      subtitle:
          'Flick at > 300 pt/s to advance a page even from 15% drag, or drag '
          'past the ends for RubberBand stretch. Settles on UIKit paging '
          'spring (omega 15.9, z 0.88).',
      apis: const [
        'PagingPhysics',
        'PagingPhysics.defaultSpring',
        'RubberBand',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final nextExtent = math.max<double>(180, constraints.maxWidth);
              if ((nextExtent - _pageExtent).abs() > 1) {
                _pageExtent = nextExtent;
                _offset.snap(_clock.now, _page * _pageExtent);
              }
              return InputRegion(
                interactions: [_drag],
                child: SizedBox(
                  height: 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CustomPaint(
                      painter: _CarouselPainter(
                        offset: _offset,
                        pageExtent: _pageExtent,
                        titles: titles,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              KinesisButton(
                label: 'Prev',
                compact: true,
                onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i == _page
                              ? palette.blue
                              : palette.textTertiary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SizedBox(width: i == _page ? 18 : 7, height: 7),
                      ),
                    ),
                ],
              ),
              KinesisButton(
                label: 'Next',
                compact: true,
                onPressed: _page < _pageCount - 1
                    ? () => _goTo(_page + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _CarouselPainter extends CustomPainter {
  _CarouselPainter({
    required this.offset,
    required this.pageExtent,
    required this.titles,
  }) : super(repaint: offset);

  final MotionValue<double> offset;
  final double pageExtent;
  final List<(String, String, Color)> titles;

  @override
  void paint(Canvas canvas, Size size) {
    final scroll = offset.value;
    for (var i = 0; i < titles.length; i++) {
      final x = i * pageExtent - scroll;
      if (x + pageExtent < -20 || x > size.width + 20) continue;
      final (title, subtitle, color) = titles[i];
      final rect = Rect.fromLTWH(x + 6, 4, pageExtent - 12, size.height - 8);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.72)],
          ).createShader(rect),
      );
      final numTp = TextPainter(
        text: TextSpan(
          text: '0${i + 1}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xBBFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numTp.paint(canvas, Offset(rect.left + 18, rect.top + 16));

      final titleTp = TextPainter(
        text: TextSpan(
          text: title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 36);
      titleTp.paint(canvas, Offset(rect.left + 18, rect.top + 42));

      final subTp = TextPainter(
        text: TextSpan(
          text: subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xDDFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 36);
      subTp.paint(canvas, Offset(rect.left + 18, rect.top + 74));
    }
  }

  @override
  bool shouldRepaint(_CarouselPainter oldDelegate) =>
      pageExtent != oldDelegate.pageExtent;
}
