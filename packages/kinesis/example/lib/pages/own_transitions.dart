import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

final class TumbleDigits extends NumericTextTransition {
  const TumbleDigits();

  @override
  MotionPose poseAt(
    double progress, {
    required bool incoming,
    required int direction,
  }) {
    final away = (incoming ? 1 - progress : progress).clamp(0.0, 1.0);
    final side = (incoming ? 1 : -1) * (direction == 0 ? 1 : direction);
    return MotionPose(
      offsetFraction: Offset(0, 0.7 * side * away),
      rotation: 0.9 * side * away,
      scale: 1 - 0.4 * away,
      opacity: 1 - away,
      blur: 2 * away,
    );
  }
}

final class PopDigits extends NumericTextTransition {
  const PopDigits();

  @override
  MotionPose poseAt(
    double progress, {
    required bool incoming,
    required int direction,
  }) {
    final away = (incoming ? 1 - progress : progress).clamp(0.0, 1.0);
    return MotionPose(
      scale: incoming ? 1 + 0.8 * away : 1 - 0.6 * away,
      opacity: 1 - away,
      blur: 3 * away,
    );
  }
}

final class SwingContent extends ContentTransition {
  const SwingContent();

  @override
  MotionPose poseAt(double progress, {required bool incoming}) {
    final away = (incoming ? 1 - progress : progress).clamp(0.0, 1.0);
    return MotionPose(
      rotation: (incoming ? -0.9 : 0.9) * away,
      opacity: 1 - away,
    );
  }

  @override
  AlignmentGeometry get alignment => AlignmentDirectional.centerStart;
}

final class DropContent extends ContentTransition {
  const DropContent();

  @override
  MotionPose poseAt(double progress, {required bool incoming}) {
    final away = (incoming ? 1 - progress : progress).clamp(0.0, 1.0);
    return MotionPose(
      offsetFraction: Offset(0, (incoming ? -1.3 : 1.3) * away),
      scale: 1 - 0.12 * away,
      opacity: 1 - away,
    );
  }
}

enum _Digits { roll, tumble, pop, fade }

enum _Label { blur, swing, drop, slide }

class OwnTransitionsCard extends StatefulWidget {
  const OwnTransitionsCard({super.key});

  @override
  State<OwnTransitionsCard> createState() => _OwnTransitionsCardState();
}

class _OwnTransitionsCardState extends State<OwnTransitionsCard> {
  int _score = 120;
  _Digits _digits = _Digits.tumble;
  _Label _label = _Label.swing;
  Timer? _burst;

  static const _ranks = [
    (0, 'Rookie'),
    (100, 'Contender'),
    (250, 'Champion'),
    (500, 'Hall of Famer'),
  ];

  String get _rank =>
      _ranks.lastWhere((rank) => _score >= rank.$1, orElse: () => _ranks[0]).$2;

  NumericTextTransition get _digitTransition => switch (_digits) {
    _Digits.roll => const NumericTextTransition.roll(),
    _Digits.tumble => const TumbleDigits(),
    _Digits.pop => const PopDigits(),
    _Digits.fade => const NumericTextTransition.fade(),
  };

  ContentTransition get _labelTransition => switch (_label) {
    _Label.blur => const ContentTransition.blurReplace(),
    _Label.swing => const SwingContent(),
    _Label.drop => const DropContent(),
    _Label.slide => const ContentTransition.slide(offset: Offset(0, 14)),
  };

  void _add(int delta) =>
      setState(() => _score = (_score + delta).clamp(0, 9999));

  void _startBurst() {
    _burst?.cancel();
    var left = 10;
    _burst = Timer.periodic(const Duration(milliseconds: 55), (timer) {
      _add(left.isEven ? 37 : -12);
      if (--left == 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _burst?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.purple;
    return StudioSurface(
      title: 'Transitions of Your Own',
      subtitle:
          'NumericTextTransition and ContentTransition are open: a subclass '
          'answers a MotionPose for any progress. Burst fires ten changes '
          'in half a second, and each carries on from what shows.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: palette.isDark
                    ? const [Color(0xFF241A36), Color(0xFF14202E)]
                    : const [Color(0xFFF7EEFF), Color(0xFFEAF6FF)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  MotionNumericText(
                    '$_score',
                    transition: _digitTransition,
                    style: TextStyle(
                      fontSize: 68,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StudioIcon(StudioGlyph.star, color: accent, size: 16),
                      const SizedBox(width: 8),
                      MotionContentTransition(
                        transition: _labelTransition,
                        child: _RankPill(
                          key: ValueKey<String>(_rank),
                          rank: _rank,
                          accent: accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StudioIcon(StudioGlyph.star, color: accent, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KinesisButton(
                label: '+1',
                filled: true,
                accent: accent,
                onPressed: () => _add(1),
              ),
              KinesisButton(
                label: '+150',
                accent: accent,
                onPressed: () => _add(150),
              ),
              KinesisButton(
                label: '-90',
                accent: palette.orange,
                onPressed: () => _add(-90),
              ),
              KinesisButton(
                label: 'Burst',
                glyph: StudioGlyph.bolt,
                accent: palette.pink,
                onPressed: _startBurst,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ChoiceRow(
            caption: 'Digits',
            children: [
              for (final (value, label) in const [
                (_Digits.roll, 'Roll'),
                (_Digits.tumble, 'Tumble'),
                (_Digits.pop, 'Pop'),
                (_Digits.fade, 'Fade'),
              ])
                KinesisChip(
                  label: label,
                  selected: _digits == value,
                  accent: accent,
                  onTap: () => setState(() => _digits = value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ChoiceRow(
            caption: 'Rank',
            children: [
              for (final (value, label) in const [
                (_Label.blur, 'Blur'),
                (_Label.swing, 'Swing'),
                (_Label.drop, 'Drop'),
                (_Label.slide, 'Slide'),
              ])
                KinesisChip(
                  label: label,
                  selected: _label == value,
                  accent: accent,
                  onTap: () => setState(() => _label = value),
                ),
            ],
          ),
          InspectorDrawer(
            apis: const [
              'NumericTextTransition',
              'ContentTransition',
              'MotionPose',
              'MotionNumericText',
              'MotionContentTransition',
            ],
            child: Text(
              'digits: ${_digits.name}  |  rank: ${_label.name}  |  '
              'at most ${MotionContentTransition.maxChanges} changes at once',
              style: palette.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank, required this.accent, super.key});

  final String rank;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        rank,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.caption, required this.children});

  final String caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(caption.toUpperCase(), style: palette.caption),
        ),
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 6, children: children),
        ),
      ],
    );
  }
}
