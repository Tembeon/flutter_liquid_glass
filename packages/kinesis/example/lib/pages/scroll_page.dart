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
      StudioPageHeader(
        title: 'Carousel & Momentum',
        subtitle:
            'Swipe stories with a quick flick, or fling the feed below to '
            'feel authentic iOS deceleration and elastic edge bounce.',
      ),
      _StoriesCarouselCard(),
      SizedBox(height: 18),
      _MomentumFeedCard(),
    ],
  );
}

class _StoriesCarouselCard extends StatefulWidget {
  const _StoriesCarouselCard();

  @override
  State<_StoriesCarouselCard> createState() => _StoriesCarouselCardState();
}

class _StoriesCarouselCardState extends State<_StoriesCarouselCard> {
  static const int _pageCount = 4;
  static const PagingPhysics _physics = PagingPhysics();

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _offset = MotionValue<double>(
    0,
    clock: _clock,
  );
  int _page = 0;
  double _pageExtent = 420;
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
    const stories = [
      (
        'DESIGN',
        'Fluid Interfaces',
        'Fast flicks turn the page even from a 15% drag.',
        Color(0xFF2563EB),
        Color(0xFF7C3AED),
      ),
      (
        'PHYSICS',
        'Elastic Edges',
        'Pull past the first or last card to feel rubber-band resistance.',
        Color(0xFFEA580C),
        Color(0xFFDB2777),
      ),
      (
        'ENGINE',
        'Zero Rebuilds',
        'Every frame paints directly from MotionValue without setState.',
        Color(0xFF059669),
        Color(0xFF0284C7),
      ),
      (
        'FEEL',
        'iOS Settle Spring',
        'Tuned to native paging frequency with subtle detent haptics.',
        Color(0xFF4F46E5),
        Color(0xFF9333EA),
      ),
    ];

    return StudioSurface(
      title: 'Featured Stories',
      subtitle:
          'Swipe left or right -- quick flicks snap straight to the next card.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final nextExtent = math.max<double>(220, constraints.maxWidth);
              if ((nextExtent - _pageExtent).abs() > 1) {
                _pageExtent = nextExtent;
                _offset.snap(_clock.now, _page * _pageExtent);
              }
              return InputRegion(
                interactions: [_drag],
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 178,
                    child: CustomPaint(
                      painter: _StoriesPainter(
                        offset: _offset,
                        pageExtent: _pageExtent,
                        stories: stories,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              KinesisButton(
                label: 'Previous',
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
                              : palette.textTertiary.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SizedBox(width: i == _page ? 20 : 7, height: 7),
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
          InspectorDrawer(
            apis: const [
              'PagingPhysics',
              'PagingPhysics.defaultSpring',
              'RubberBand',
            ],
            child: Text(
              'page: ${_page + 1}/$_pageCount  |  '
              'flip threshold: 300 pt/s  |  omega: 15.9, zeta: 0.88',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}

final class _StoriesPainter extends CustomPainter {
  _StoriesPainter({
    required this.offset,
    required this.pageExtent,
    required this.stories,
  }) : super(repaint: offset);

  final MotionValue<double> offset;
  final double pageExtent;
  final List<(String, String, String, Color, Color)> stories;

  @override
  void paint(Canvas canvas, Size size) {
    final scroll = offset.value;
    for (var i = 0; i < stories.length; i++) {
      final x = i * pageExtent - scroll;
      if (x + pageExtent < -20 || x > size.width + 20) continue;
      final (kicker, title, desc, c1, c2) = stories[i];
      final rect = Rect.fromLTWH(x + 4, 2, pageExtent - 8, size.height - 4);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2],
          ).createShader(rect),
      );

      // Decorative translucent orbs for visual depth.
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawCircle(
        Offset(rect.right - 32, rect.top + 34),
        68,
        Paint()..color = const Color(0x22FFFFFF),
      );
      canvas.drawCircle(
        Offset(rect.right - 84, rect.bottom + 10),
        52,
        Paint()..color = const Color(0x18FFFFFF),
      );
      canvas.restore();

      final kickerTp = TextPainter(
        text: TextSpan(
          text: kicker,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Color(0xCCFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      kickerTp.paint(canvas, Offset(rect.left + 22, rect.top + 24));

      final titleTp = TextPainter(
        text: TextSpan(
          text: title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Color(0xFFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 44);
      titleTp.paint(canvas, Offset(rect.left + 22, rect.top + 48));

      final descTp = TextPainter(
        text: TextSpan(
          text: desc,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: Color(0xE6FFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 44);
      descTp.paint(canvas, Offset(rect.left + 22, rect.top + 86));
    }
  }

  @override
  bool shouldRepaint(_StoriesPainter oldDelegate) =>
      pageExtent != oldDelegate.pageExtent;
}

class _MomentumFeedCard extends StatefulWidget {
  const _MomentumFeedCard();

  @override
  State<_MomentumFeedCard> createState() => _MomentumFeedCardState();
}

class _MomentumFeedCardState extends State<_MomentumFeedCard> {
  static const _messages = [
    ('AK', 'Alex Kim', 'Shipped the new spring physics kernel', '2m'),
    ('ML', 'Maya Lin', 'Rubber-band bounce feels super crisp now', '8m'),
    ('JR', 'Jordan Reed', 'Can we test 0.25x slow motion on iPad?', '19m'),
    ('SO', 'Sam Ortiz', 'Updated typography morph transitions', '34m'),
    ('EC', 'Elena Cruz', 'Symbol queue tests are all green', '1h'),
    ('DW', 'Devon Wu', 'Loved the scrubbable Now Playing card', '2h'),
    ('NP', 'Nora Park', 'Haptics throttle nicely at 25 Hz', '3h'),
    ('LT', 'Leo Tan', 'Paging flick threshold feels spot on', '4h'),
    ('HB', 'Hana Bell', 'Dark mode contrast looks great', '5h'),
    ('MC', 'Marco Conti', 'Zero rebuilds confirmed at 120 fps', '6h'),
    ('RS', 'Rina Sato', 'Ready for the Friday design review', '1d'),
    ('TG', 'Theo Grant', 'Added anchored popover presentation', '1d'),
    ('AV', 'Aria Vance', 'Reduced motion cross-fade verified', '2d'),
    ('KL', 'Kai Lind', 'Keyboard navigation works end to end', '2d'),
  ];
  static const double _itemHeight = 62;
  static const double _viewportHeight = 256;
  static final double _maxOffset =
      _messages.length * _itemHeight - _viewportHeight + 16;

  late final MotionClock _clock = MotionClockScope.of(context);
  late final _FeedMotion _feed = _FeedMotion(
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
        _feed.setPosition(details.time, _scrollToTop.valueAt(details.time));
      }
      _feed.stop(details.time);
      _dragStartOffset = _feed.offset;
    },
    onUpdate: (details) {
      final raw = _dragStartOffset - details.translation.dy;
      final band = RubberBand(0, _maxOffset, dimension: _viewportHeight);
      _feed.setPosition(details.time, band.apply(raw));
    },
    onEnd: (details) => _feed.fling(details.time, -details.velocity.dy, _decel),
    onCancel: (t) => _feed.fling(t, 0, _decel),
  );

  void _backToTop() {
    final t = _clock.now;
    _feed.stop(t);
    _scrollToTop.snap(t, _feed.offset);
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
    _feed.setPosition(t, _scrollToTop.value);
    if (_scrollToTop.restsAt(t)) {
      _animatingToTop = false;
    }
  }

  @override
  void dispose() {
    _scrollToTop.removeListener(_syncScrollToTop);
    _feed.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final inspect = StudioTheme.inspectorOf(context);

    return StudioSurface(
      title: 'Momentum Feed',
      subtitle:
          'Drag and fling vertically, pull past the top or bottom, or tap '
          'Back to Top for the smooth 1.6 s curve.',
      trailing: KinesisButton(
        label: 'Back to Top',
        compact: true,
        filled: true,
        glyph: StudioGlyph.arrowUp,
        onPressed: _backToTop,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisChip(
                label: 'iOS Normal Friction',
                selected: !_fastRate,
                onTap: () => setState(() => _fastRate = false),
              ),
              KinesisChip(
                label: 'Fast Deceleration',
                selected: _fastRate,
                accent: palette.orange,
                onTap: () => setState(() => _fastRate = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MotionScope(
            motion: _feed,
            child: InputRegion(
              interactions: [_drag],
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: palette.well),
                  child: SizedBox(
                    height: _viewportHeight,
                    child: CustomPaint(
                      painter: _FeedPainter(
                        feed: _feed,
                        messages: _messages,
                        itemHeight: _itemHeight,
                        maxOffset: _maxOffset,
                        showInspector: inspect,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          InspectorDrawer(
            apis: const [
              'ScrollDeceleration',
              'landingOffset',
              'ScrollToTopCurve',
              'MotionLoop',
            ],
            child: ValueListenableBuilder<double>(
              valueListenable: _feed.listenable,
              builder: (context, y, _) => Text(
                'rate: ${_decel.rate}  |  offset: ${y.toStringAsFixed(0)} pt'
                '  |  velocity: ${_feed.velocity.toStringAsFixed(0)} pt/s',
                style: palette.mono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _FeedMotion extends Motion {
  _FeedMotion({required this.maxOffset, super.clock}) {
    _loop = own(_FeedLoop(this));
  }

  final double maxOffset;
  late final _FeedLoop _loop;
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
    _predictedLanding = decel
        .landingOffset(_offset.value, velocity)
        .clamp(0.0, maxOffset);
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
    if (step.settled) _coasting = false;
    changed();
    return _coasting;
  }

  void release() => _offset.dispose();
}

final class _FeedLoop extends MotionLoop {
  _FeedLoop(this._host);

  final _FeedMotion _host;

  @override
  bool step(double t) => _host._tick(t);
}

final class _FeedPainter extends CustomPainter {
  _FeedPainter({
    required this.feed,
    required this.messages,
    required this.itemHeight,
    required this.maxOffset,
    required this.showInspector,
    required this.palette,
  }) : super(repaint: feed.listenable);

  final _FeedMotion feed;
  final List<(String, String, String, String)> messages;
  final double itemHeight;
  final double maxOffset;
  final bool showInspector;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = feed.offset;
    final avatarColors = [
      palette.blue,
      palette.purple,
      palette.orange,
      palette.green,
      palette.teal,
      palette.pink,
    ];

    for (var i = 0; i < messages.length; i++) {
      final top = i * itemHeight - offset + 8;
      if (top + itemHeight < 0 || top > size.height) continue;
      final (initials, author, body, time) = messages[i];
      final rect = Rect.fromLTWH(10, top, size.width - 28, itemHeight - 8);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(13));
      canvas.drawRRect(rrect, Paint()..color = palette.surface);

      final avatarCenter = Offset(rect.left + 26, rect.center.dy);
      final color = avatarColors[i % avatarColors.length];
      canvas.drawCircle(
        avatarCenter,
        16,
        Paint()..color = color.withValues(alpha: 0.16),
      );
      final initTp = TextPainter(
        text: TextSpan(
          text: initials,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      initTp.paint(
        canvas,
        avatarCenter - Offset(initTp.width / 2, initTp.height / 2),
      );

      final nameTp = TextPainter(
        text: TextSpan(
          text: author,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 104);
      nameTp.paint(canvas, Offset(rect.left + 52, rect.top + 10));

      final bodyTp = TextPainter(
        text: TextSpan(
          text: body,
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rect.width - 68);
      bodyTp.paint(canvas, Offset(rect.left + 52, rect.top + 29));

      final timeTp = TextPainter(
        text: TextSpan(text: time, style: palette.caption),
        textDirection: TextDirection.ltr,
      )..layout();
      timeTp.paint(
        canvas,
        Offset(rect.right - timeTp.width - 12, rect.top + 10),
      );
    }

    // Minimalist scroll indicator.
    final trackRect = Rect.fromLTWH(size.width - 10, 12, 4, size.height - 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(2)),
      Paint()..color = palette.hairline,
    );
    final frac = (offset / maxOffset).clamp(0.0, 1.0);
    final thumbY = trackRect.top + (trackRect.height - 32) * frac;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackRect.left, thumbY, 4, 32),
        const Radius.circular(2),
      ),
      Paint()..color = palette.textTertiary,
    );

    if (showInspector) {
      if (feed.predictedLanding case final landing?) {
        final landFrac = (landing / maxOffset).clamp(0.0, 1.0);
        final markerY = trackRect.top + (trackRect.height - 32) * landFrac + 16;
        canvas.drawCircle(
          Offset(trackRect.center.dx, markerY),
          4.5,
          Paint()..color = palette.orange,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FeedPainter oldDelegate) =>
      showInspector != oldDelegate.showInspector ||
      palette != oldDelegate.palette;
}
