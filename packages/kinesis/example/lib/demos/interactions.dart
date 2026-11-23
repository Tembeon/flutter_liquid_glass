import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class InteractionsDemo extends StatefulWidget {
  const InteractionsDemo({super.key});

  @override
  State<InteractionsDemo> createState() => _InteractionsDemoState();
}

class _InteractionsDemoState extends State<InteractionsDemo> {
  final _log = ValueNotifier<List<String>>(const []);
  final _pressed = MotionValue<double>(0);
  late final _padScale = MotionSelection(() => 1 - 0.05 * _pressed.value);

  late final List<Interaction> _padInteractions = [
    PressInteraction(
      role: InteractionRole.observer,
      onHighlightChanged: (_, {required highlighted}) => withSpring(
        highlighted ? Spring.interactive : Spring.bouncy,
        () => _pressed.target = highlighted ? 1 : 0,
      ),
    ),
    TapInteraction(
      count: 2,
      onTap: (_) => _note('double tap'),
    ).exclusively(TapInteraction(onTap: (_) => _note('tap'))),
    LongPressInteraction(
      onStart: (_) => _note('long press'),
      onCommit: (_) => _note('long press released'),
    ),
    SecondaryClickInteraction(
      onClick: (_, position) => _note(
        'secondary click at '
        '${position.dx.round()}, ${position.dy.round()}',
      ),
    ),
    DwellInteraction(
      duration: 0.6,
      onDwell: (_) => _note('pointer rested'),
    ),
  ];

  final _puck = MotionValue(Offset.zero);
  late final _puckDrag = DragInteraction(
    onUpdate: (details) => _puck.target = details.translation,
    onEnd: (details) {
      _puck.velocity = details.velocity;
      withSpring(Spring.bouncy, () => _puck.target = Offset.zero);
    },
  );

  final _lift = MotionValue<double>(0);
  final _carry = MotionValue(Offset.zero);
  late final _liftScale = MotionSelection(() => 1 + 0.12 * _lift.value);
  late final _liftShadow = MotionSelection(() => 0.25 * _lift.value);
  bool _dragged = false;
  late final _holdThenDrag =
      LongPressInteraction(
        duration: 0.35,
        onStart: (_) {
          _dragged = false;
          withSpring(Spring.snappy, () => _lift.target = 1);
        },
        onCommit: (_) => _dropUnlessDragged(),
        onCancel: (_) => _dropUnlessDragged(),
      ).sequenced(
        DragInteraction(
          slop: 0,
          onStart: (_) => _dragged = true,
          onUpdate: (details) => _carry.target = details.translation,
          onEnd: (details) => _drop(details.velocity),
          onCancel: (_) => _drop(Offset.zero),
        ),
      );

  late final _spot = _Spot();

  void _dropUnlessDragged() {
    if (!_dragged) _drop(Offset.zero);
  }

  void _drop(Offset velocity) {
    _carry.velocity = velocity;
    withSpring(Spring.bouncy, () {
      _lift.target = 0;
      _carry.target = Offset.zero;
    });
  }

  void _note(String event) => _log.value = [event, ..._log.value.take(4)];

  final _level = MotionValue<double>(0.4);
  late final _levelRange = MotionSelection(
    () => AdjustRange.of(_level.target, min: 0, max: 1),
  );
  double _levelWidth = 1;
  double _levelFrom = 0;

  late final List<Interaction> _levelInteractions = [
    DragInteraction(
      axis: Axis.horizontal,
      onStart: (_) => _levelFrom = _level.value,
      onUpdate: (details) => _level.target =
          (_levelFrom + details.translation.dx / _levelWidth).clamp(0.0, 1.0),
      onEnd: (_) => setState(() {}),
    ),
    _Steps(_step),
  ];

  static String _percent(double level) =>
      '${(level.clamp(0.0, 1.0) * 100).round()}%';

  void _step(ValueCommand command) {
    final level = _level.target;
    final next = switch (command) {
      ValueCommand.increase => level + 0.1,
      ValueCommand.decrease => level - 0.1,
      ValueCommand.increaseLarge => level + 0.25,
      ValueCommand.decreaseLarge => level - 0.25,
      ValueCommand.toMinimum => 0.0,
      ValueCommand.toMaximum => 1.0,
    };
    withSpring(Spring.snappy, () => _level.target = next.clamp(0.0, 1.0));
    setState(() {});
  }

  @override
  void dispose() {
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'An Interaction is a gesture as plain logic over stamped input; '
          'InputRegion feeds it touches, the mouse, keys and accessibility '
          'actions. A region runs several side by side.',
      children: [
        Section(
          title: 'One region, several gestures',
          caption:
              'The press observes every touch and scales the pad. A double '
              'tap goes first and a single tap waits for it to fail '
              '(exclusively); a long press cancels the rest. With a mouse, '
              'right-click or rest the pointer.',
          stage: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputRegion(
                interactions: _padInteractions,
                semantics: const SemanticsProperties(label: 'Pad'),
                child: MotionTransition(
                  scale: _padScale,
                  child: SizedBox(
                    height: 110,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          'Press me',
                          style: TextStyles.headline.copyWith(
                            color: palette.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 104,
                child: ValueListenableBuilder(
                  valueListenable: _log,
                  builder: (context, log, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (log.isEmpty)
                        Text(
                          'Events show here.',
                          style: TextStyles.mono.copyWith(
                            color: palette.secondaryLabel,
                          ),
                        ),
                      for (final (index, event) in log.indexed)
                        Text(
                          event,
                          style: TextStyles.mono.copyWith(
                            color: index == 0
                                ? palette.label
                                : palette.secondaryLabel,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Section(
          title: 'Drag',
          caption:
              'DragInteraction reports the travel past its slop and the '
              'release velocity. The puck follows the finger, then springs '
              'home at the speed it was thrown.',
          stage: SizedBox(
            height: 200,
            child: Center(
              child: InputRegion(
                interactions: [_puckDrag],
                child: MotionTransition(
                  offset: _puck,
                  child: Dot(color: palette.swatches[1], size: 64),
                ),
              ),
            ),
          ),
        ),
        Section(
          title: 'Hold, then drag',
          caption:
              'A long press sequenced with a drag: the drag hears the touch '
              'only once the hold is recognized, so the page still scrolls '
              'under a quick swipe.',
          stage: SizedBox(
            height: 200,
            child: Center(
              child: InputRegion(
                interactions: [_holdThenDrag],
                child: MotionTransition(
                  offset: _carry,
                  scale: _liftScale,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      MotionTransition(
                        opacity: _liftShadow,
                        blur: MotionSelection(() => 12 * _lift.value),
                        offset: MotionSelection(
                          () => Offset(0, 10 * _lift.value),
                        ),
                        child: const Tile(color: Color(0xFF000000), size: 72),
                      ),
                      Tile(color: palette.swatches[2], size: 72, label: 'Hold'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Section(
          title: 'Follow',
          caption:
              'FollowInteraction hands every position of the touch to a '
              'PointerFollower at once, with no slop and no decision: here a '
              'light that stays under the finger.',
          stage: InputRegion(
            interactions: [FollowInteraction(_spot)],
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: palette.fill,
                child: SizedBox(
                  height: 160,
                  child: Stack(
                    children: [
                      Positioned(
                        left: -40,
                        top: -40,
                        child: MotionTransition(
                          offset: _spot.position,
                          opacity: _spot.opacity,
                          child: Dot(
                            color: palette.swatches[5].withValues(alpha: 0.6),
                            size: 80,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          'Touch and move',
                          style: TextStyles.caption.copyWith(
                            color: palette.secondaryLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Section(
          title: 'An interaction of your own',
          caption:
              'Interaction is open to subclasses. This one only adjusts: '
              'with the level focused, the arrows, Page Up and Down, Home '
              "and End, and a screen reader's increase and decrease step "
              'it, and AdjustRange tells the region when it is at an end. A '
              'DragInteraction beside it moves the level by touch.',
          stage: InputRegion(
            interactions: _levelInteractions,
            adjustRange: _levelRange,
            semantics: SemanticsProperties(
              label: 'Level',
              value: _percent(_level.target),
              increasedValue: _percent(_level.target + 0.1),
              decreasedValue: _percent(_level.target - 0.1),
            ),
            child: MotionMeasure(
              onSize: (_, size) => _levelWidth = size.width,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: palette.fill,
                  child: SizedBox(
                    height: 44,
                    child: MotionTransition(
                      scaleX: _level,
                      alignment: AlignmentDirectional.centerStart,
                      child: ColoredBox(color: palette.accent),
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

final class _Steps extends Interaction {
  _Steps(this.onCommand);

  final ValueChanged<ValueCommand> onCommand;

  @override
  bool get takesPointers => false;

  @override
  bool get adjusts => true;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) onCommand(input.command);
    return InteractionUpdate.none;
  }
}

class _Spot extends PointerFollower {
  final position = MotionValue(Offset.zero);
  final opacity = MotionValue<double>(0);

  @override
  void down(PointerDownInput input) {
    position.target = input.position;
    withSpring(Spring.snappy, () => opacity.target = 1);
  }

  @override
  void move(PointerMoveInput input) => position.target = input.position;

  @override
  void up(PointerUpInput input) => _fade();

  @override
  void cancel(PointerCancelInput input) => _fade();

  void _fade() => withSpring(Spring.smooth, () => opacity.target = 0);
}
