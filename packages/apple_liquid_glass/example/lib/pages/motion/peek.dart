import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/motion.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Two presentations of the app's own, on kinesis's portal.
///
/// The peek grows out of its button (a `MotionSource`) on a `Presence` and
/// a `MotionRect`, follows a finger that drags it down and leaves when the
/// release projects past a third of it. A tap on the button while it
/// shrinks back takes it over where it is.
///
/// The reactions bar opens under a held finger, which keeps sliding over
/// its icons: the portal pushes no route, so the touch that opened it is
/// never cancelled. Lifting over an icon picks it.
///
/// Not measured: the springs and the sizes are chosen by eye.
class PeekSection extends StatefulWidget {
  const PeekSection({super.key});

  @override
  State<PeekSection> createState() => _PeekSectionState();
}

class _PeekSectionState extends State<PeekSection> {
  final _peekSource = MotionSource(debugLabel: 'peek');
  final _peek = PresentationPortalController();
  final _reactions = PresentationPortalController();
  final _reactionsKey = GlobalKey();
  late final List<Interaction> _hold = [
    _HoldSlide(
      onHold: (t) => _reactions.present(),
      onSlide: (t, position) => _reactionsMotion?.hover(t, _global(position)),
      onLift: (t, position) {
        final motion = _reactionsMotion;
        if (motion == null || !_reactions.isPresented) return;
        motion.hover(t, _global(position));
        final picked = motion.hovered;
        if (picked != null) _picked(picked);
      },
      onCancel: (t) => _reactionsMotion?.hover(t, null),
    ),
  ];
  _ReactionsMotion? _reactionsMotion;
  var _reaction = 'Hold the button, slide to a reaction';

  late final _peekPresentation = Presentation<Object?, _PeekMotion>(
    motion: (environment) => _PeekMotion(
      Rect.fromCenter(
        center: environment.bounds.center(Offset.zero),
        width: math.min(340, environment.bounds.width - 40),
        height: 380,
      ),
    ),
    source: _peekSource,
    dim: (motion) => 0.25 * motion.shown.progressAt(motion.now),
    modal: (motion) => motion.presence != PresenceStatus.leaving,
    builder: (context, motion) => _PeekPanel(motion: motion),
    semanticsLabel: 'Peek',
  );

  late final _reactionsPresentation = Presentation<Object?, _ReactionsMotion>(
    motion: (environment) => _reactionsMotion = _ReactionsMotion(
      _anchor(),
      bounds: environment.bounds,
    ),
    modal: (motion) => motion.presence != PresenceStatus.leaving,
    builder: (context, motion) => _ReactionsBar(motion: motion),
    semanticsLabel: 'Reactions',
  );

  Rect _anchor() {
    final box = _reactionsKey.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Offset? _global(Offset position) =>
      _reactions.isPresented ? _anchor().topLeft + position : null;

  void _picked(int index) {
    setState(
      () => _reaction = 'You reacted with ${_ReactionsMotion.names[index]}',
    );
    _reactions.dismiss(DismissTrigger.programmatic);
  }

  @override
  Widget build(BuildContext context) => GlassListSection(
    header: const Text('Your own presentation'),
    footer: const Text(
      'Drag the peek down to close it, and tap its button again while it '
      'closes: it comes back from where it is.',
    ),
    children: [
      ClipRect(
        child: SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: Wallpaper.dunes.image, fit: BoxFit.cover),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    PresentationPortal(
                      controller: _peek,
                      presentation: _peekPresentation,
                      child: MotionSourceBox(
                        source: _peekSource,
                        radius: BorderRadius.circular(22),
                        child: GlassButton(
                          onPressed: _peek.present,
                          child: const Text('Peek'),
                        ),
                      ),
                    ),
                    PresentationPortal(
                      controller: _reactions,
                      presentation: _reactionsPresentation,
                      child: InputRegion(
                        key: _reactionsKey,
                        interactions: _hold,
                        semanticLabel: 'Reactions',
                        child: const GlassSurface(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.heart,
                                  color: Color(0xFFFFFFFF),
                                ),
                                SizedBox(width: 8),
                                PhotoText('Hold to react', size: 17),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    PhotoText(_reaction),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

final class _PeekMotion extends Motion with Presented, Sourced {
  _PeekMotion(this.panel);

  /// Where the open panel stands, in the overlay.
  final Rect panel;

  late final shown = own(
    Presence(openSpring: Spring.bouncy, closeSpring: Spring.smooth),
  );
  late final frame = own(
    MotionRect(Rect.zero, springs: const RectSprings.all(Spring.snappy)),
  );
  late final drag = own(MotionValue<double>(0));
  Rect? _source;

  @override
  PresenceStatus get presence => shown.status;

  @override
  void sourceMoved(double t, SourceGeometry? geometry) {
    if (geometry == null) return;
    if (_source == null) frame.snap(t, geometry.rect);
    _source = geometry.rect;
  }

  @override
  void open(double t) {
    advance(t);
    shown.open(t);
    frame.retarget(t, panel);
    drag.retarget(t, 0, spring: Spring.snappy);
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    advance(t);
    if (shown.isHidden) return false;
    shown.hide(t);
    frame.retarget(t, _source ?? panel);
    drag.retarget(t, 0, spring: Spring.smooth);
    return true;
  }

  void follow(double t, double offset) {
    advance(t);
    drag.snap(t, offset);
  }

  void release(double t, double velocity) {
    advance(t);
    drag.setVelocity(t, velocity);
    drag.retarget(t, 0, spring: Spring.snappy);
  }

  GlassFrame get body {
    final rect = frame.valueAt(now).shift(Offset(0, drag.valueAt(now)));
    final pull = (drag.valueAt(now) / panel.height).clamp(0.0, 1.0);
    return GlassFrame(
      shape: const GlassShape.superellipse(34),
      rect: rect.shift(-panel.topLeft),
      scaleX: 1 - 0.1 * pull,
      scaleY: 1 - 0.1 * pull,
    );
  }
}

class _PeekPanel extends StatefulWidget {
  const _PeekPanel({required this.motion});

  final _PeekMotion motion;

  @override
  State<_PeekPanel> createState() => _PeekPanelState();
}

class _PeekPanelState extends State<_PeekPanel> {
  late final _body = widget.motion.select((m) => m.body);
  late final _opacity = widget.motion.select(
    (m) => m.shown.progressAt(m.now).clamp(0.0, 1.0),
  );
  late final _drag = DragInteraction(
    axis: Axis.vertical,
    onUpdate: _update,
    onEnd: _end,
    onCancel: (t) => widget.motion.release(t, 0),
  );
  late final List<Interaction> _interactions = [_drag];

  Band get _band => Band(
    0,
    widget.motion.panel.height,
    dimension: widget.motion.panel.height,
  );

  void _update(DragInteractionDetails details) =>
      widget.motion.follow(details.time, _band.show(details.translation.dy));

  void _end(DragInteractionDetails details) {
    final motion = widget.motion;
    final choice = Projection.of(Spring.snappy).choose(
      motion.drag.valueAt(details.time),
      details.velocity.dy,
      stops: const [0],
      exits: [ProjectionExit(threshold: motion.panel.height / 3)],
    );
    motion.release(details.time, details.velocity.dy);
    if (choice is ProjectionExited) {
      PresentationHandle.of(context).dismiss(DismissTrigger.interaction);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fromRect(
        rect: widget.motion.panel,
        child: InputRegion(
          interactions: _interactions,
          child: GlassSurface.live(
            frame: _body,
            child: MotionTransition(
              opacity: _opacity,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRSuperellipse(
                        borderRadius: BorderRadius.circular(20),
                        child: Image(
                          image: Wallpaper.alpine.image,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const GlassDefaultTextStyle(
                      role: GlassTextRole.headline,
                      child: Text('Alpine'),
                    ),
                    const SizedBox(height: 4),
                    const Text('Drag me down to close.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

final class _ReactionsMotion extends Motion with Presented {
  _ReactionsMotion(this.anchor, {required Size bounds})
    : bar = _place(anchor, bounds);

  static const icons = [
    CupertinoIcons.heart_fill,
    CupertinoIcons.hand_thumbsup_fill,
    CupertinoIcons.hand_thumbsdown_fill,
    CupertinoIcons.star_fill,
    CupertinoIcons.flame_fill,
  ];
  static const names = [
    'a heart',
    'a thumbs up',
    'a thumbs down',
    'a star',
    'a flame',
  ];
  static const _item = 48.0;
  static const _inset = 6.0;

  /// The button the bar grows out of, in the overlay.
  final Rect anchor;

  /// Where the open bar stands, in the overlay.
  final Rect bar;

  late final shown = own(
    Presence(openSpring: Spring.bouncy, closeSpring: Spring.snappy),
  );
  late final List<MotionValue<double>> _scales = [
    for (final _ in icons) own(MotionValue<double>(1)),
  ];

  /// The icon under the finger, or null.
  int? hovered;

  static Rect _place(Rect anchor, Size bounds) {
    final width = icons.length * _item + 2 * _inset;
    final left = (anchor.center.dx - width / 2)
        .clamp(8.0, math.max(8.0, bounds.width - width - 8.0))
        .toDouble();
    return Rect.fromLTWH(
      left,
      anchor.top - _item - 2 * _inset - 12,
      width,
      _item + 2 * _inset,
    );
  }

  @override
  PresenceStatus get presence => shown.status;

  @override
  void open(double t) {
    advance(t);
    shown.open(t);
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    advance(t);
    hover(t, null);
    if (shown.isHidden) return false;
    shown.hide(t);
    return true;
  }

  /// The finger is at [position] in the overlay, or gone when null.
  void hover(double t, Offset? position) {
    advance(t);
    int? index;
    if (position != null && bar.inflate(24).contains(position)) {
      final i = ((position.dx - bar.left - _inset) / _item).floor();
      if (i >= 0 && i < icons.length) index = i;
    }
    if (index == hovered) return;
    hovered = index;
    for (final (i, scale) in _scales.indexed) {
      scale.retarget(t, i == index ? 1.4 : 1, spring: Spring.snappy);
    }
    if (index != null) MotionHaptic.selection.play();
  }

  double scaleOf(int index) => _scales[index].valueAt(now);

  GlassFrame get body {
    final progress = shown.progressAt(now);
    final from = anchor.shift(-bar.topLeft);
    final to = Offset.zero & bar.size;
    return GlassFrame(rect: Rect.lerp(from, to, progress));
  }
}

class _ReactionsBar extends StatefulWidget {
  const _ReactionsBar({required this.motion});

  final _ReactionsMotion motion;

  @override
  State<_ReactionsBar> createState() => _ReactionsBarState();
}

class _ReactionsBarState extends State<_ReactionsBar> {
  late final _body = widget.motion.select((m) => m.body);
  late final _opacity = widget.motion.select(
    (m) => m.shown.progressAt(m.now).clamp(0.0, 1.0),
  );
  late final _scales = [
    for (final (i, _) in _ReactionsMotion.icons.indexed)
      widget.motion.select((m) => m.scaleOf(i)),
  ];

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fromRect(
        rect: widget.motion.bar,
        child: GlassSurface.live(
          frame: _body,
          child: MotionTransition(
            opacity: _opacity,
            child: Padding(
              padding: const EdgeInsets.all(_ReactionsMotion._inset),
              child: Row(
                children: [
                  for (final (i, icon) in _ReactionsMotion.icons.indexed)
                    SizedBox.square(
                      dimension: _ReactionsMotion._item,
                      child: MotionTransition(
                        scale: _scales[i],
                        child: Icon(icon, size: 28),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// A press held still for half a second that then keeps following its
/// finger: [onSlide] hears every move after [onHold] and [onLift] the
/// release, in the region's coordinates. A long press of the package
/// would hand the touch to nothing after it is recognized.
final class _HoldSlide extends Interaction {
  _HoldSlide({
    required this.onHold,
    required this.onSlide,
    required this.onLift,
    required this.onCancel,
  });

  static const _duration = 0.5;
  static const _slop = 10.0;

  final void Function(double t) onHold;
  final void Function(double t, Offset position) onSlide;
  final void Function(double t, Offset position) onLift;
  final void Function(double t) onCancel;

  int? _pointer;
  Offset _start = Offset.zero;
  double? _due;
  bool _held = false;

  @override
  double? get nextDue => _held ? null : _due;

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    if (_held || due == null || time < due) return InteractionUpdate.none;
    _held = true;
    onHold(due);
    return const InteractionUpdate(recognizes: true);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when _pointer == null && accepts(input):
        _pointer = input.pointer;
        _start = input.position;
        _due = input.time + _duration;
        _held = false;
      case PointerMoveInput(:final pointer, :final position, :final time)
          when pointer == _pointer:
        if (_held) {
          onSlide(time, position);
        } else if ((position - _start).distance > _slop) {
          _reset();
          return const InteractionUpdate(fails: true);
        }
      case PointerUpInput(:final pointer, :final position, :final time)
          when pointer == _pointer:
        if (_held) onLift(time, position);
        _reset();
      case PointerCancelInput(:final pointer, :final time)
          when pointer == _pointer:
        if (_held) onCancel(time);
        _reset();
      default:
    }
    return InteractionUpdate.none;
  }

  void _reset() {
    _pointer = null;
    _due = null;
    _held = false;
  }
}
