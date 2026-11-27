import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

import 'package:kinesis_example/kit.dart';

class ScrollDemo extends StatefulWidget {
  const ScrollDemo({super.key});

  @override
  State<ScrollDemo> createState() => _ScrollDemoState();
}

class _ScrollDemoState extends State<ScrollDemo> {
  static const _titleRange = 48.0;

  final _scroll = MotionScroll();

  late final _pixels = _scroll.select((m) => m.metrics?.pixels ?? 0);
  late final _titleOpacity = MotionSelection(
    () => (1 - _pixels.value / _titleRange).clamp(0.0, 1.0),
  );
  late final _titleScale = MotionSelection(
    () => 1 + (-_pixels.value / 400).clamp(0.0, 0.15),
  );
  late final _barOpacity = MotionSelection(
    () => ((_pixels.value - _titleRange / 2) / _titleRange).clamp(0.0, 1.0),
  );
  late final _phase = _scroll.select((m) => m.phase);

  void _scrollToTop() => _scroll.position?.animateTo(
    0,
    duration: Duration(
      milliseconds: (ScrollToTopCurve.duration * 1000).round(),
    ),
    curve: const ScrollToTopCurve(),
  );

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return DemoPage(
      summary:
          "MotionScroll reads a scroll view as a motion: its offset and its "
          'phase become values a selection can follow, so a title fades and '
          'a bar appears without a listener or a rebuild of their own.',
      children: [
        Section(
          title: 'A title that follows the content',
          caption:
              'Scroll the list. The large title fades and the small one '
              'comes in; pull down and the title grows. Top scrolls back on '
              "UIKit's scroll-to-top curve.",
          stage: MotionScope(
            motion: _scroll,
            child: SizedBox(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: palette.background,
                  child: Stack(
                    children: [
                      NotificationListener<Notification>(
                        onNotification: _scroll.handle,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                          itemCount: 31,
                          itemBuilder: (context, index) => index == 0
                              ? MotionTransition(
                                  opacity: _titleOpacity,
                                  scale: _titleScale,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      'Journal',
                                      style: TextStyles.title,
                                    ),
                                  ),
                                )
                              : _Message(index: index),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: MotionTransition(
                          opacity: _barOpacity,
                          child: ColoredBox(
                            color: palette.surface,
                            child: const SizedBox(
                              height: 44,
                              child: Center(
                                child: Text(
                                  'Journal',
                                  style: TextStyles.label,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          controls: [
            PushButton('Top', onPressed: _scrollToTop),
            ValueListenableBuilder(
              valueListenable: _phase,
              builder: (context, phase, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'phase: ${phase.name}',
                  style: TextStyles.mono.copyWith(
                    color: palette.secondaryLabel,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Dot(
                color: palette.swatches[index % palette.swatches.length],
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Entry $index',
                  style: TextStyles.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
