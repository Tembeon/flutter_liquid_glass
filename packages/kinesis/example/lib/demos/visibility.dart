import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class VisibilityDemo extends StatefulWidget {
  const VisibilityDemo({super.key});

  @override
  State<VisibilityDemo> createState() => _VisibilityDemoState();
}

class _VisibilityDemoState extends State<VisibilityDemo> {
  static const _panes = ['Circle', 'Square', 'Ring'];

  final _pane = MotionValue<double>(0);
  late final _visible = [
    for (var i = 0; i < _panes.length; i++)
      MotionSelection(() => _pane.value.round() == i),
  ];
  int _selected = 0;

  final _caret = CaretBlinkMotion();
  String _text = '';
  bool _focused = false;

  void _show(int pane) {
    _pane.target = pane.toDouble();
    setState(() => _selected = pane);
  }

  void _focus() {
    _focused = !_focused;
    final now = _caret.clock.now;
    if (_focused) {
      _caret.show(now);
    } else {
      _caret.hide(now);
    }
    setState(() {});
  }

  void _type(String key) {
    if (!_focused) return;
    _caret.reset(_caret.clock.now);
    setState(
      () => _text = key == 'Delete'
          ? _text.substring(0, _text.isEmpty ? 0 : _text.length - 1)
          : _text + key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'Showing and hiding without building: MotionVisibility switches '
          'what paints from a listenable, and CaretBlinkMotion is the text '
          "cursor's blink as UIKit draws it.",
      children: [
        Section(
          title: 'MotionVisibility',
          caption:
              'Three panes stay built in a Stack; each shows while a '
              'selection of one value says so. A switch costs a paint, not '
              'a build or a layout.',
          stage: SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MotionVisibility(
                  visible: _visible[0],
                  child: Dot(color: palette.swatches[0], size: 96),
                ),
                MotionVisibility(
                  visible: _visible[1],
                  child: Tile(color: palette.swatches[2], size: 96, radius: 8),
                ),
                MotionVisibility(
                  visible: _visible[2],
                  child: SizedBox.square(
                    dimension: 96,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.swatches[4],
                          width: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          controls: [
            for (final (index, name) in _panes.indexed)
              PushButton(
                name,
                selected: index == _selected,
                onPressed: () => _show(index),
              ),
          ],
        ),
        Section(
          title: 'CaretBlinkMotion',
          caption:
              'Focus the field and type. The caret holds solid after every '
              'key, then blinks in steps; unfocused, it hides and the clock '
              'sleeps.',
          stage: MotionScope(
            motion: _caret,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focused ? palette.accent : palette.fill,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _text.isEmpty && !_focused ? 'Tap Focus' : _text,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyles.body.copyWith(
                          color: _text.isEmpty
                              ? palette.secondaryLabel
                              : palette.label,
                        ),
                      ),
                    ),
                    MotionTransition(
                      opacity: _caret.opacityListenable,
                      child: SizedBox(
                        width: 2,
                        height: 22,
                        child: ColoredBox(color: palette.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          controls: [
            PushButton('Focus', selected: _focused, onPressed: _focus),
            for (final key in ['k', 'i', 'n', 'e', 's', 'Delete'])
              PushButton(key, onPressed: () => _type(key)),
          ],
        ),
      ],
    );
  }
}
