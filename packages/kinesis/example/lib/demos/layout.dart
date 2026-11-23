import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class LayoutDemo extends StatefulWidget {
  const LayoutDemo({super.key});

  @override
  State<LayoutDemo> createState() => _LayoutDemoState();
}

class _LayoutDemoState extends State<LayoutDemo> {
  static const _planner = LayoutPlanner.flip(
    insert: MotionPose(scale: 0.4, opacity: 0),
    remove: MotionPose(scale: 0.4, opacity: 0),
  );

  final _random = Random(3);
  final _tiles = [for (var i = 1; i <= 8; i++) i];
  var _nextTile = 9;

  final _rows = [for (var i = 1; i <= 5; i++) i];
  var _nextRow = 6;

  void _change(Spring spring, VoidCallback change) =>
      withSpring(spring, () => setState(change));

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'Change the children and let layout do its job: MotionLayout and '
          'SliverMotionList move every child from where it was drawn to '
          'where layout put it, under the spring of the change.',
      children: [
        Section(
          title: 'MotionLayout',
          caption:
              'Any layout, here a Wrap. A change inside withSpring slides '
              'the tiles that moved; new tiles grow in and removed ones '
              "shrink away in the planner's poses.",
          stage: SizedBox(
            height: 152,
            child: MotionLayout(
              planner: _planner,
              layoutBuilder: (context, children) =>
                  Wrap(spacing: 10, runSpacing: 10, children: children),
              children: [
                for (final id in _tiles)
                  Tile(
                    key: ValueKey(id),
                    color: palette.swatches[id % palette.swatches.length],
                    label: '$id',
                    size: 44,
                    radius: 12,
                  ),
              ],
            ),
          ),
          controls: [
            PushButton(
              'Shuffle',
              onPressed: () =>
                  _change(Spring.snappy, () => _tiles.shuffle(_random)),
            ),
            PushButton(
              'Sort',
              onPressed: () => _change(Spring.snappy, _tiles.sort),
            ),
            PushButton(
              'Add',
              onPressed: () => _change(Spring.bouncy, () {
                if (_tiles.length < 12) {
                  _tiles.insert(
                    _random.nextInt(_tiles.length + 1),
                    _nextTile++,
                  );
                }
              }),
            ),
            PushButton(
              'Remove',
              onPressed: () => _change(Spring.smooth, () {
                if (_tiles.isNotEmpty) {
                  _tiles.removeAt(_random.nextInt(_tiles.length));
                }
              }),
            ),
          ],
        ),
        Section(
          title: 'SliverMotionList',
          caption:
              'The same for a sliver list that builds its rows lazily, by '
              'id. Tap a row to remove it.',
          stage: SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomScrollView(
                slivers: [
                  SliverMotionList(
                    ids: _rows,
                    itemBuilder: (context, id) => _Row(
                      id: id as int,
                      color: palette.swatches[id % palette.swatches.length],
                      onTap: () =>
                          _change(Spring.smooth, () => _rows.remove(id)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          controls: [
            PushButton(
              'Add on top',
              onPressed: () =>
                  _change(Spring.smooth, () => _rows.insert(0, _nextRow++)),
            ),
            PushButton(
              'Shuffle',
              onPressed: () =>
                  _change(Spring.snappy, () => _rows.shuffle(_random)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.id, required this.color, required this.onTap});

  final int id;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.fill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Dot(color: color, size: 20),
                const SizedBox(width: 12),
                Text('Row $id', style: TextStyles.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
