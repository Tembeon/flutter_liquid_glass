import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class TextDemo extends StatefulWidget {
  const TextDemo({super.key});

  @override
  State<TextDemo> createState() => _TextDemoState();
}

class _TextDemoState extends State<TextDemo> {
  static const _numberStyle = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const _rolls = {
    'roll': NumericTextTransition.roll(),
    'fade': NumericTextTransition.fade(),
  };

  static const _transitions = {
    'blurReplace': ContentTransition.blurReplace(),
    'fade': ContentTransition.fade(),
    'scale': ContentTransition.scale(),
    'slide': ContentTransition.slide(),
  };

  static const _words = ['Hello', 'Bonjour', 'Hej', 'Buongiorno', 'Hola'];

  final _random = Random(7);
  int _count = 128;
  String _roll = 'roll';

  late final _calm = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: Palette.of(context).secondaryLabel,
  );
  late final _loud = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    color: Palette.of(context).accent,
  );
  late final _style = MotionValue<TextStyle>(
    _calm,
    converter: TextStyleMotionConverter(_calm),
  );
  bool _isLoud = false;

  String _transition = 'blurReplace';
  int _word = 0;

  void _shout() {
    _isLoud = !_isLoud;
    withSpring(Spring.bouncy, () => _style.target = _isLoud ? _loud : _calm);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          'Text that changes in place: digits that roll, a style that '
          'springs, and content that swaps while the space around it '
          'slides. None of it rebuilds per frame.',
      children: [
        Section(
          title: 'MotionNumericText',
          caption:
              'Only the digits that change move, up when the number grows '
              'and down when it shrinks; the width slides with them.',
          stage: SizedBox(
            height: 80,
            child: Center(
              child: MotionNumericText(
                '$_count',
                style: _numberStyle.copyWith(color: palette.label),
                transition: _rolls[_roll]!,
              ),
            ),
          ),
          controls: [
            PushButton('-1', onPressed: () => setState(() => _count--)),
            PushButton('+1', onPressed: () => setState(() => _count++)),
            PushButton(
              '+100',
              onPressed: () => setState(() => _count += 100),
            ),
            PushButton(
              'Random',
              onPressed: () => setState(() => _count = _random.nextInt(99999)),
            ),
            for (final name in _rolls.keys)
              PushButton(
                name,
                selected: name == _roll,
                onPressed: () => setState(() => _roll = name),
              ),
          ],
        ),
        Section(
          title: 'MotionText',
          caption:
              'A MotionValue<TextStyle> springs size, weight, spacing and '
              'color. MotionText lays the paragraph out again each frame '
              'without building a widget.',
          stage: SizedBox(
            height: 80,
            child: Center(child: MotionText('kinesis', style: _style)),
          ),
          controls: [PushButton('Shout', onPressed: _shout)],
        ),
        Section(
          title: 'MotionContentTransition',
          caption:
              'A child with a new key comes in through a ContentTransition '
              'while the old one leaves; the box slides from one size to '
              'the other.',
          stage: SizedBox(
            height: 80,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.fill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: MotionContentTransition(
                  transition: _transitions[_transition]!,
                  clipBehavior: Clip.hardEdge,
                  child: Padding(
                    key: ValueKey(_word),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Text(_words[_word], style: TextStyles.headline),
                  ),
                ),
              ),
            ),
          ),
          controls: [
            PushButton(
              'Next',
              onPressed: () =>
                  setState(() => _word = (_word + 1) % _words.length),
            ),
            for (final name in _transitions.keys)
              PushButton(
                name,
                selected: name == _transition,
                onPressed: () => setState(() => _transition = name),
              ),
          ],
        ),
      ],
    );
  }
}
