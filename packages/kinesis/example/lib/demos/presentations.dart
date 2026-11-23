import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class PresentationsDemo extends StatefulWidget {
  const PresentationsDemo({super.key});

  @override
  State<PresentationsDemo> createState() => _PresentationsDemoState();
}

class _PresentationsDemoState extends State<PresentationsDemo> {
  static const _panelSize = Size(280, 220);
  static const _sheetHeight = 300.0;
  static final _radius = BorderRadius.circular(14);

  final _album = MotionSource(debugLabel: 'Album');
  final _portal = PresentationPortalController();
  String _answer = 'No answer yet.';

  late final _question = Presentation<bool, _Pop>(
    motion: (environment) => _Pop(clock: environment.clock),
    dim: (motion) => 0.3 * motion.opacity,
    semanticsLabel: 'Keep the change?',
    semanticsRole: SemanticsRole.alertDialog,
    builder: (context, motion) => Center(
      child: MotionTransition(
        opacity: motion.fade,
        scale: motion.scale,
        child: const _Question(),
      ),
    ),
  );

  late final _grown = Presentation<void, _Grow>(
    source: _album,
    motion: (environment) => _Grow(
      clock: environment.clock,
      target: Rect.fromCenter(
        center: environment.bounds.center(Offset.zero),
        width: _panelSize.width,
        height: _panelSize.height,
      ),
    ),
    dim: (motion) => 0.25 * motion.opacity,
    semanticsLabel: 'Album',
    builder: (context, motion) => Stack(
      children: [
        Positioned(
          left: motion.target.left,
          top: motion.target.top,
          child: MotionTransition(
            offset: motion.shift,
            width: motion.width,
            height: motion.height,
            borderRadius: _radius,
            child: OverflowBox(
              minWidth: _panelSize.width,
              maxWidth: _panelSize.width,
              minHeight: _panelSize.height,
              maxHeight: _panelSize.height,
              child: _Panel(contentOpacity: motion.contentOpacity),
            ),
          ),
        ),
      ],
    ),
  );

  late final _sheet = Presentation<void, _Sheet>(
    motion: (environment) =>
        _Sheet(clock: environment.clock, height: _sheetHeight),
    dim: (motion) => 0.3 * motion.opacity,
    semanticsLabel: 'Sheet',
    semanticsRole: SemanticsRole.dialog,
    builder: (context, motion) => Align(
      alignment: Alignment.bottomCenter,
      child: MotionTransition(
        translateY: motion.drop,
        child: _SheetBody(motion: motion),
      ),
    ),
  );

  Future<void> _ask() async {
    final keep = await showPresentation(
      context,
      PresentationRoute(presentation: _question),
    );
    if (!mounted) return;
    setState(
      () => _answer = switch (keep) {
        true => 'Kept.',
        false => 'Discarded.',
        null => 'Dismissed without an answer.',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'A Presentation is a motion plus the content drawn over it. A route '
          'or a portal shows it and brings focus, Escape, Back, the dim and '
          'screen readers; the motion decides how it comes and goes. This '
          'page came in on a PresentationPageRoute, so Back and the '
          "predictive back gesture of Android move it.",
      children: [
        Section(
          title: 'A popup',
          caption:
              'PresentationRoute and showPresentation, which completes with '
              'the answer. The motion is a PresentedProgress: one progress '
              'that springs open and closed. Tap outside or press Escape to '
              'dismiss it without one.',
          stage: Text(
            _answer,
            style: TextStyles.mono.copyWith(color: palette.secondaryLabel),
          ),
          controls: [PushButton('Ask', onPressed: _ask)],
        ),
        Section(
          title: 'Grow from a source',
          caption:
              'A PresentationPortal shows its presentation on the overlay '
              'with no route. The tile is a MotionSource: it hides while '
              'the panel shows, and the motion hears where it is in every '
              'frame, so the panel grows out of it and goes back into it.',
          stage: Center(
            child: PresentationPortal(
              controller: _portal,
              presentation: _grown,
              child: Tappable(
                onTap: _portal.present,
                semantics: const SemanticsProperties(
                  label: 'Open album',
                  button: true,
                ),
                child: MotionSourceBox(
                  source: _album,
                  radius: _radius,
                  child: Tile(
                    color: palette.swatches[3],
                    size: 72,
                    label: 'Open',
                  ),
                ),
              ),
            ),
          ),
        ),
        Section(
          title: 'A sheet the finger takes away',
          caption:
              'The content holds its presentation through '
              'PresentationHandle: a drag shows what is below, moves the '
              'sheet with the finger and, past half way or with a flick, '
              'dismisses it at the speed it was thrown.',
          controls: [
            PushButton(
              'Show sheet',
              onPressed: () => showPresentation(
                context,
                PresentationRoute(presentation: _sheet),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _Pop extends PresentedProgress {
  _Pop({super.clock}) : super(openSpring: Spring.bouncy, restDistance: 1e-3);

  late final MotionSelection<double> fade = select((m) => m.opacity);

  late final MotionSelection<double> scale = select(
    (m) => 0.8 + 0.2 * m.progress,
  );
}

class _Question extends StatelessWidget {
  const _Question();

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final handle = PresentationHandle.of(context);
    return SizedBox(
      width: 280,
      child: Card(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Keep the change?', style: TextStyles.headline),
            const SizedBox(height: 6),
            Text(
              'The answer comes back to the page that asked.',
              style: TextStyles.body.copyWith(color: palette.secondaryLabel),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PushButton(
                    'Discard',
                    onPressed: () =>
                        handle.dismiss(DismissTrigger.programmatic, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PushButton(
                    'Keep',
                    selected: true,
                    onPressed: () =>
                        handle.dismiss(DismissTrigger.programmatic, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _Grow extends Motion with Presented, Sourced {
  _Grow({required this.target, super.clock});

  final Rect target;

  late final Presence _shown = own(Presence(openSpring: Spring.snappy));
  SourceGeometry? _source;

  Rect get _from => _source?.rect ?? target;

  late final MotionSelection<Offset> shift = select(
    (m) => (m._from.topLeft - m.target.topLeft) * (1 - m._shown.progress),
  );

  late final MotionSelection<double> width = select(
    (m) =>
        max(0, lerpDouble(m._from.width, m.target.width, m._shown.progress)!),
  );

  late final MotionSelection<double> height = select(
    (m) =>
        max(0, lerpDouble(m._from.height, m.target.height, m._shown.progress)!),
  );

  late final MotionSelection<double> contentOpacity = select(
    (m) => ((m._shown.progress - 0.5) * 2).clamp(0.0, 1.0),
  );

  double get opacity => _shown.opacity;

  @override
  PresenceStatus get presence => _shown.status;

  @override
  void open(double t) => _shown.open(t);

  @override
  bool leave(double t) {
    _shown.hide(t);
    return true;
  }

  @override
  void sourceMoved(double t, SourceGeometry? geometry) {
    if (geometry == null || geometry == _source) return;
    advance(t);
    _source = geometry;
    changed();
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.contentOpacity});

  final ValueListenable<double> contentOpacity;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final handle = PresentationHandle.of(context);
    return ColoredBox(
      color: palette.swatches[3],
      child: MotionTransition(
        opacity: contentOpacity,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Album',
                style: TextStyles.headline.copyWith(color: palette.onAccent),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  'Grown out of the tile. Close it, or tap outside, and it '
                  'shrinks back into the tile wherever the tile is now.',
                  overflow: TextOverflow.fade,
                  style: TextStyles.body.copyWith(color: palette.onAccent),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PushButton(
                  'Close',
                  onPressed: () => handle.dismiss(DismissTrigger.programmatic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Sheet extends Motion with Presented {
  _Sheet({required this.height, super.clock});

  final double height;

  late final Presence _shown = own(Presence(openSpring: Spring.smooth));

  late final MotionSelection<double> drop = select(
    (m) => (1 - m._shown.progress) * m.height,
  );

  double get opacity => _shown.opacity;

  @override
  PresenceStatus get presence => _shown.status;

  @override
  void open(double t) => _shown.open(t);

  @override
  bool leave(double t) {
    _shown.hide(t);
    return true;
  }

  void follow(double t, double distance) {
    advance(t);
    _shown.hold(t, 1 - (distance / height).clamp(0.0, 1.0));
  }

  bool release(double t, double velocity) {
    advance(t);
    final progressVelocity = -velocity / height;
    _shown.setVelocity(t, progressVelocity);
    final dismisses = _shown.progress < 0.5 || progressVelocity < -1.5;
    if (!dismisses) _shown.open(t);
    return dismisses;
  }
}

class _SheetBody extends StatefulWidget {
  const _SheetBody({required this.motion});

  final _Sheet motion;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  late final _drag = DragInteraction(
    axis: Axis.vertical,
    onStart: _start,
    onUpdate: (details) =>
        widget.motion.follow(details.time, details.translation.dy),
    onEnd: (details) => _end(details.time, details.velocity.dy),
    onCancel: (t) => _end(t, 0),
  );

  bool _dragging = false;

  void _start(DragInteractionDetails details) {
    final handle = PresentationHandle.of(context);
    if (!handle.canDismiss(DismissTrigger.interaction)) return;
    _dragging = true;
    handle.beginInteraction();
    widget.motion.follow(details.time, details.translation.dy);
  }

  void _end(double t, double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final handle = PresentationHandle.of(context);
    handle.endInteraction();
    if (widget.motion.release(t, velocity)) {
      handle.dismiss(DismissTrigger.interaction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return InputRegion(
      interactions: [_drag],
      child: SizedBox(
        height: widget.motion.height + MediaQuery.paddingOf(context).bottom,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SizedBox(
                    width: 40,
                    height: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.separator,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Drag me down', style: TextStyles.headline),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    'Let go above half way and the sheet springs back. '
                    'Lower, or with a flick, it leaves at the speed of the '
                    'finger.',
                    overflow: TextOverflow.fade,
                    style: TextStyles.body.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                ),
                PushButton(
                  'Done',
                  onPressed: () => PresentationHandle.of(
                    context,
                  ).dismiss(DismissTrigger.programmatic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
