import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class TextPage extends StatelessWidget {
  const TextPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _NumericRollCard(),
      SizedBox(height: 16),
      _MotionTextCard(),
      SizedBox(height: 16),
      _ContentTransitionCard(),
      SizedBox(height: 16),
      _CaretBlinkCard(),
    ],
  );
}

class _NumericRollCard extends StatefulWidget {
  const _NumericRollCard();

  @override
  State<_NumericRollCard> createState() => _NumericRollCardState();
}

class _NumericRollCardState extends State<_NumericRollCard> {
  final math.Random _rng = math.Random(42);
  int _value = 1042;
  bool _priceMode = false;
  bool _blur = true;
  bool? _countsDown;

  String get _display =>
      _priceMode ? '\$${(_value / 100).toStringAsFixed(2)}' : '$_value';

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'MotionNumericText Rolling Digits',
      subtitle:
          'SwiftUI .contentTransition(.numericText) parity: only changed '
          'digits roll in and out with optional gaussian blur and automatic '
          'or explicit roll direction.',
      apis: const ['MotionNumericText', 'NumericTextMotion'],
      trailing: KinesisSwitch(
        label: 'Blur',
        value: _blur,
        onChanged: (v) => setState(() => _blur = v),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
              child: Center(
                child: MotionNumericText(
                  _display,
                  blur: _blur,
                  countsDown: _countsDown,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisButton(
                label: '-100',
                compact: true,
                onPressed: () => setState(() => _value -= 100),
              ),
              KinesisButton(
                label: '-1',
                compact: true,
                glyph: StudioGlyph.minus,
                onPressed: () => setState(() => _value -= 1),
              ),
              KinesisButton(
                label: '+1',
                compact: true,
                filled: true,
                glyph: StudioGlyph.plus,
                onPressed: () => setState(() => _value += 1),
              ),
              KinesisButton(
                label: '+100',
                compact: true,
                onPressed: () => setState(() => _value += 100),
              ),
              KinesisButton(
                label: 'Random',
                compact: true,
                glyph: StudioGlyph.shuffle,
                accent: palette.purple,
                onPressed: () =>
                    setState(() => _value = 100 + _rng.nextInt(98900)),
              ),
              KinesisChip(
                label: _priceMode ? r'Price ($)' : 'Integer',
                selected: _priceMode,
                accent: palette.green,
                onTap: () => setState(() => _priceMode = !_priceMode),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              KinesisChip(
                label: 'Auto Dir',
                selected: _countsDown == null,
                onTap: () => setState(() => _countsDown = null),
              ),
              KinesisChip(
                label: 'Roll Up',
                selected: _countsDown == false,
                onTap: () => setState(() => _countsDown = false),
              ),
              KinesisChip(
                label: 'Roll Down',
                selected: _countsDown ?? false,
                onTap: () => setState(() => _countsDown = true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MotionTextCard extends StatefulWidget {
  const _MotionTextCard();

  @override
  State<_MotionTextCard> createState() => _MotionTextCardState();
}

class _MotionTextCardState extends State<_MotionTextCard> {
  static const _baseStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.2,
    color: Color(0xFF1C1C1E),
  );

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<TextStyle> _style = MotionValue<TextStyle>(
    _baseStyle,
    converter: const TextStyleMotionConverter(_baseStyle),
    clock: _clock,
  );
  int _preset = 0;
  int _textBuilds = 0;

  List<(String, TextStyle)> _presets(StudioPalette p) => [
    (
      'Body',
      TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.3,
        color: p.textPrimary,
      ),
    ),
    (
      'Display',
      TextStyle(
        fontSize: 38,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        height: 1.05,
        color: p.blue,
      ),
    ),
    (
      'Tracked Caps',
      TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 4.5,
        height: 1.4,
        color: p.purple,
      ),
    ),
    (
      'Warm Accent',
      TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.15,
        color: p.orange,
      ),
    ),
  ];

  void _applyPreset(int index, StudioPalette palette) {
    _preset = index;
    final (_, style) = _presets(palette)[index];
    withSpring(Spring.bouncy, () => _style.retarget(_clock.now, style));
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final palette = StudioTheme.of(context);
    final (_, style) = _presets(palette)[_preset];
    _style.snap(_clock.now, style);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final presets = _presets(palette);
    return StudioCard(
      title: 'Zero-Rebuild MotionText',
      subtitle:
          'Interpolates fontSize, weight, letterSpacing, height, and color '
          'directly inside RenderParagraph via TextStyleMotionConverter.',
      apis: const ['MotionText', 'TextStyleMotionConverter'],
      trailing: ZeroRebuildBadge(builds: _textBuilds + 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.hairline),
            ),
            child: SizedBox(
              height: 92,
              child: Center(
                child: Builder(
                  builder: (context) {
                    _textBuilds++;
                    return MotionText(
                      'Fluid Typography',
                      style: _style,
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < presets.length; i++)
                KinesisChip(
                  label: presets[i].$1,
                  selected: _preset == i,
                  onTap: () => _applyPreset(i, palette),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _TransitionKind { blurReplace, fade, scale, slide }

class _ContentTransitionCard extends StatefulWidget {
  const _ContentTransitionCard();

  @override
  State<_ContentTransitionCard> createState() => _ContentTransitionCardState();
}

class _ContentTransitionCardState extends State<_ContentTransitionCard> {
  _TransitionKind _kind = _TransitionKind.blurReplace;
  int _index = 0;

  ContentTransition get _transition => switch (_kind) {
    _TransitionKind.blurReplace => const ContentTransition.blurReplace(),
    _TransitionKind.fade => const ContentTransition.fade(),
    _TransitionKind.scale => const ContentTransition.scale(),
    _TransitionKind.slide => const ContentTransition.slide(
      offset: Offset(0, 26),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final states = [
      (
        StudioGlyph.sun,
        '22 C  Clear Sky',
        'San Francisco -- Humidity 48%',
        palette.orange,
      ),
      (
        StudioGlyph.bolt,
        '94%  Charging',
        '18 minutes until full charge',
        palette.green,
      ),
      (
        StudioGlyph.wifi,
        'Studio 6E',
        'Connected -- 1.4 Gbps link',
        palette.blue,
      ),
      (
        StudioGlyph.bell,
        'Focus Mode On',
        'Notifications silenced until 19:00',
        palette.purple,
      ),
    ];
    final (glyph, title, desc, color) = states[_index % states.length];

    return StudioCard(
      title: 'MotionContentTransition',
      subtitle:
          'Swap arbitrary keyed widgets with blurReplace, fade, scale, or '
          'slide. Respects Reduce Motion automatically.',
      apis: const ['MotionContentTransition', 'ContentTransition'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in _TransitionKind.values)
                KinesisChip(
                  label: kind.name,
                  selected: _kind == kind,
                  accent: palette.indigo,
                  onTap: () => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.hairline),
            ),
            child: SizedBox(
              height: 86,
              child: Center(
                child: MotionContentTransition(
                  transition: _transition,
                  child: Row(
                    key: ValueKey<int>(_index),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(11),
                          child: StudioIcon(glyph, color: color, size: 22),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: palette.title),
                          const SizedBox(height: 2),
                          Text(desc, style: palette.subtitle),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              KinesisButton(
                label: 'Cycle Content',
                filled: true,
                accent: palette.indigo,
                onPressed: () => setState(() => _index++),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaretBlinkCard extends StatefulWidget {
  const _CaretBlinkCard();

  @override
  State<_CaretBlinkCard> createState() => _CaretBlinkCardState();
}

class _CaretBlinkCardState extends State<_CaretBlinkCard> {
  static const _sample = 'Kinesis renders UIKit stepped caret blink.';

  late final MotionClock _clock = MotionClockScope.of(context);
  late final CaretBlinkMotion _caret = CaretBlinkMotion(
    visible: true,
    clock: _clock,
  );
  String _typed = 'Hello kinesis';

  void _typeNext() {
    final nextLen = _typed.length < _sample.length ? _typed.length + 1 : 1;
    setState(() => _typed = _sample.substring(0, nextLen));
    _caret.reset(_clock.now);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return StudioCard(
      title: 'UIKit CaretBlinkMotion',
      subtitle:
          'Exact 1.0 s stepped keyframe blink cycle (solid 0..0.55 s, '
          'fade-out, off, fade-in). Calling reset() holds the caret solid '
          'while typing.',
      apis: const ['CaretBlinkMotion', 'MotionTransition'],
      trailing: KinesisSwitch(
        label: 'Active',
        value: _caret.isVisible,
        onChanged: (v) {
          final t = _clock.now;
          if (v) {
            _caret.show(t);
          } else {
            _caret.hide(t);
          }
          setState(() {});
        },
      ),
      child: MotionScope(
        motion: _caret,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.well,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _caret.isVisible
                      ? palette.blue.withValues(alpha: 0.65)
                      : palette.hairline,
                  width: _caret.isVisible ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _typed,
                        style: TextStyle(
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    MotionTransition(
                      opacity: _caret.opacityListenable,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.blue,
                          borderRadius: BorderRadius.circular(1),
                        ),
                        child: const SizedBox(width: 2.2, height: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                KinesisButton(
                  label: 'Type Character (reset)',
                  filled: true,
                  compact: true,
                  onPressed: _typeNext,
                ),
                KinesisButton(
                  label: 'Clear',
                  compact: true,
                  onPressed: () {
                    setState(() => _typed = '');
                    _caret.reset(_clock.now);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
