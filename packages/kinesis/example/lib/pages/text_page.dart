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
      StudioPageHeader(
        title: 'Live Typography',
        subtitle:
            'Rolling numeric digits, zero-rebuild font morphing, fluid '
            'content swaps, and UIKit stepped caret blinking.',
      ),
      _WalletBalanceCard(),
      SizedBox(height: 18),
      _TypographyAndCaretCard(),
    ],
  );
}

enum _SwapStyle { blurReplace, fade, scale, slide }

class _WalletBalanceCard extends StatefulWidget {
  const _WalletBalanceCard();

  @override
  State<_WalletBalanceCard> createState() => _WalletBalanceCardState();
}

class _WalletBalanceCardState extends State<_WalletBalanceCard> {
  final math.Random _rng = math.Random(17);
  int _cents = 124850;
  int _eventIndex = 0;
  String _statusText = 'Updated just now';
  Color? _statusAccent;
  bool _blurDigits = true;
  _SwapStyle _swapStyle = _SwapStyle.blurReplace;

  String get _formatted {
    final dollars = _cents ~/ 100;
    final rem = (_cents.abs() % 100).toString().padLeft(2, '0');
    final raw = dollars.abs().toString();
    final buf = StringBuffer();
    if (_cents < 0) buf.write('-');
    buf.write(r'$');
    for (var i = 0; i < raw.length; i++) {
      final fromRight = raw.length - i;
      if (i > 0 && fromRight % 3 == 0) buf.write(',');
      buf.write(raw[i]);
    }
    buf.write('.$rem');
    return buf.toString();
  }

  ContentTransition get _transition => switch (_swapStyle) {
    _SwapStyle.blurReplace => const ContentTransition.blurReplace(),
    _SwapStyle.fade => const ContentTransition.fade(),
    _SwapStyle.scale => const ContentTransition.scale(),
    _SwapStyle.slide => const ContentTransition.slide(offset: Offset(0, 18)),
  };

  void _applyDelta(int deltaCents, String label, Color color) {
    setState(() {
      _cents = math.max(0, _cents + deltaCents);
      _statusText = label;
      _statusAccent = color;
      _eventIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final statusColor = _statusAccent ?? palette.green;

    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: palette.isDark
                    ? const [Color(0xFF1A2238), Color(0xFF1A162D)]
                    : const [Color(0xFFEEF4FF), Color(0xFFF6F0FF)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
              child: Column(
                children: [
                  Text('TOTAL BALANCE', style: palette.caption),
                  const SizedBox(height: 10),
                  MotionNumericText(
                    _formatted,
                    transition: NumericTextTransition.roll(
                      blur: _blurDigits ? 2.5 : 0,
                    ),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.6,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  MotionContentTransition(
                    transition: _transition,
                    child: DecoratedBox(
                      key: ValueKey<int>(_eventIndex),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: Text(
                          _statusText,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KinesisButton(
                label: r'+$25',
                filled: true,
                accent: palette.green,
                onPressed: () =>
                    _applyDelta(2500, r'Deposit +$25.00', palette.green),
              ),
              KinesisButton(
                label: r'+$100',
                accent: palette.green,
                onPressed: () =>
                    _applyDelta(10000, r'Transfer +$100.00', palette.green),
              ),
              KinesisButton(
                label: r'-$15',
                accent: palette.orange,
                onPressed: () =>
                    _applyDelta(-1500, r'Coffee -$15.00', palette.orange),
              ),
              KinesisButton(
                label: 'Randomize',
                glyph: StudioGlyph.shuffle,
                accent: palette.purple,
                onPressed: () {
                  final next = 12000 + _rng.nextInt(980000);
                  final up = next >= _cents;
                  setState(() {
                    _cents = next;
                    _statusText = up
                        ? 'Portfolio jumped up'
                        : 'Portfolio rebalanced';
                    _statusAccent = up ? palette.green : palette.purple;
                    _eventIndex++;
                  });
                },
              ),
              KinesisSwitch(
                label: 'Digit Blur',
                value: _blurDigits,
                onChanged: (v) => setState(() => _blurDigits = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (style, label) in const [
                (_SwapStyle.blurReplace, 'Blur Replace'),
                (_SwapStyle.fade, 'Cross Fade'),
                (_SwapStyle.scale, 'Scale Pop'),
                (_SwapStyle.slide, 'Slide Up'),
              ])
                KinesisChip(
                  label: label,
                  selected: _swapStyle == style,
                  accent: palette.indigo,
                  onTap: () => setState(() => _swapStyle = style),
                ),
            ],
          ),
          InspectorDrawer(
            apis: const [
              'MotionNumericText',
              'NumericTextMotion',
              'MotionContentTransition',
              'ContentTransition',
            ],
            child: Text(
              'value: $_formatted  |  blur: $_blurDigits  |  '
              'status transition: ${_swapStyle.name}',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypographyAndCaretCard extends StatefulWidget {
  const _TypographyAndCaretCard();

  @override
  State<_TypographyAndCaretCard> createState() =>
      _TypographyAndCaretCardState();
}

class _TypographyAndCaretCardState extends State<_TypographyAndCaretCard> {
  static const _baseStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.2,
    color: Color(0xFF141416),
  );
  static const _noteSample = 'Smooth springs, zero rebuilds, pure motion.';

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<TextStyle> _style = MotionValue<TextStyle>(
    _baseStyle,
    converter: const TextStyleMotionConverter(_baseStyle),
    clock: _clock,
  );
  late final CaretBlinkMotion _caret = CaretBlinkMotion(
    visible: true,
    clock: _clock,
  );

  int _preset = 1;
  int _textBuilds = 0;
  String _typed = 'Smooth springs';

  List<(String, TextStyle)> _presets(StudioPalette p) => [
    (
      'Compact',
      TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.3,
        color: p.textSecondary,
      ),
    ),
    (
      'Headline',
      TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.1,
        color: p.textPrimary,
      ),
    ),
    (
      'Editorial',
      TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 4.2,
        height: 1.4,
        color: p.purple,
      ),
    ),
    (
      'Highlight',
      TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.15,
        color: p.blue,
      ),
    ),
  ];

  void _selectPreset(int index, StudioPalette palette) {
    _preset = index;
    final (_, target) = _presets(palette)[index];
    withSpring(Spring.bouncy, () => _style.retarget(_clock.now, target));
    setState(() {});
  }

  void _typeNext() {
    final nextLen = _typed.length < _noteSample.length ? _typed.length + 1 : 1;
    setState(() => _typed = _noteSample.substring(0, nextLen));
    _caret.reset(_clock.now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final palette = StudioTheme.of(context);
    _style.snap(_clock.now, _presets(palette)[_preset].$2);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final presets = _presets(palette);

    return StudioSurface(
      title: 'Fluid Headline & UIKit Caret',
      subtitle:
          'Morph font size, weight, tracking, and color smoothly on a single '
          'RenderParagraph, paired with an exact 1.0 s stepped cursor.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.well,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 88,
              child: Center(
                child: Builder(
                  builder: (context) {
                    _textBuilds++;
                    return MotionText(
                      'Hello, Kinesis',
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
                  onTap: () => _selectPreset(i, palette),
                ),
            ],
          ),
          const SizedBox(height: 18),
          MotionScope(
            motion: _caret,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.well,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.blue.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _typed,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
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
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                              child: const SizedBox(width: 2.2, height: 21),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    KinesisButton(
                      label: 'Type',
                      compact: true,
                      filled: true,
                      onPressed: _typeNext,
                    ),
                  ],
                ),
              ),
            ),
          ),
          InspectorDrawer(
            apis: const [
              'MotionText',
              'TextStyleMotionConverter',
              'CaretBlinkMotion',
            ],
            builds: _textBuilds,
            child: Text(
              'style preset: ${presets[_preset].$1}  |  '
              'caret cycle: 1.0 s stepped keyframes (reset on key)',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}
