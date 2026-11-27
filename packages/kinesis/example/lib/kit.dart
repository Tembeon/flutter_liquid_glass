import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

EdgeInsets pageInsets(BuildContext context, {required double top}) {
  final side = max<double>(20, (MediaQuery.sizeOf(context).width - 720) / 2);
  return EdgeInsets.fromLTRB(
    side,
    top,
    side,
    40 + MediaQuery.paddingOf(context).bottom,
  );
}

@immutable
final class Palette {
  const Palette({
    required this.background,
    required this.surface,
    required this.label,
    required this.secondaryLabel,
    required this.separator,
    required this.fill,
    required this.accent,
    required this.onAccent,
    required this.swatches,
  });

  static const light = Palette(
    background: Color(0xFFF4F3EF),
    surface: Color(0xFFFFFFFF),
    label: Color(0xFF1C1B19),
    secondaryLabel: Color(0xFF6F6C66),
    separator: Color(0xFFE6E3DC),
    fill: Color(0xFFEDEBE5),
    accent: Color(0xFF3B5BDB),
    onAccent: Color(0xFFFFFFFF),
    swatches: [
      Color(0xFF3B5BDB),
      Color(0xFFF08C00),
      Color(0xFF2F9E44),
      Color(0xFFE03131),
      Color(0xFF9C36B5),
      Color(0xFF1098AD),
    ],
  );

  static const dark = Palette(
    background: Color(0xFF131312),
    surface: Color(0xFF1F1F1D),
    label: Color(0xFFF1F0EC),
    secondaryLabel: Color(0xFF9D9A93),
    separator: Color(0xFF30302D),
    fill: Color(0xFF2B2B28),
    accent: Color(0xFF748FFC),
    onAccent: Color(0xFF0F0F14),
    swatches: [
      Color(0xFF748FFC),
      Color(0xFFFFA94D),
      Color(0xFF69DB7C),
      Color(0xFFFF8787),
      Color(0xFFDA77F2),
      Color(0xFF66D9E8),
    ],
  );

  final Color background;
  final Color surface;
  final Color label;
  final Color secondaryLabel;
  final Color separator;
  final Color fill;
  final Color accent;
  final Color onAccent;
  final List<Color> swatches;

  static Palette of(BuildContext context) =>
      MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark
      ? dark
      : light;
}

abstract final class TextStyles {
  static const title = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.15,
  );
  static const headline = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
  );
  static const body = TextStyle(fontSize: 16, height: 1.4);
  static const caption = TextStyle(fontSize: 14, height: 1.4);
  static const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['monospace'],
    fontSize: 13,
    height: 1.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class DemoTitle extends InheritedWidget {
  const DemoTitle({required this.title, required super.child, super.key});

  final String title;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoTitle>()!.title;

  @override
  bool updateShouldNotify(DemoTitle oldWidget) => title != oldWidget.title;
}

class DemoPage extends StatelessWidget {
  const DemoPage({required this.summary, required this.children, super.key});

  final String summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BackBar(),
            Expanded(
              child: ListView(
                padding: pageInsets(context, top: 4),
                children: [
                  Text(DemoTitle.of(context), style: TextStyles.title),
                  const SizedBox(height: 8),
                  Text(
                    summary,
                    style: TextStyles.body.copyWith(
                      color: palette.secondaryLabel,
                    ),
                  ),
                  for (final child in children) ...[
                    const SizedBox(height: 32),
                    child,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Tappable(
          onTap: () => Navigator.of(context).maybePop(),
          semantics: const SemanticsProperties(button: true, label: 'Back'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chevron(color: palette.accent, back: true),
                const SizedBox(width: 6),
                Text(
                  'Catalog',
                  style: TextStyles.body.copyWith(color: palette.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.caption,
    this.stage,
    this.controls = const [],
    super.key,
  });

  final String title;
  final String caption;
  final Widget? stage;
  final List<Widget> controls;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: TextStyles.headline),
        const SizedBox(height: 4),
        Text(
          caption,
          style: TextStyles.caption.copyWith(color: palette.secondaryLabel),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?stage,
              if (stage != null && controls.isNotEmpty)
                const SizedBox(height: 16),
              if (controls.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 8, children: controls),
            ],
          ),
        ),
      ],
    );
  }
}

class Card extends StatelessWidget {
  const Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.of(context).surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class Tappable extends StatefulWidget {
  const Tappable({
    required this.onTap,
    required this.child,
    this.semantics = const SemanticsProperties(button: true),
    super.key,
  });

  final VoidCallback onTap;
  final Widget child;
  final SemanticsProperties semantics;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  final _pressed = MotionValue<double>(0);
  late final _opacity = MotionSelection(() => 1 - 0.4 * _pressed.value);
  late final _scale = MotionSelection(() => 1 - 0.04 * _pressed.value);

  late final _press = PressInteraction(
    onHighlightChanged: (_, {required highlighted}) => withSpring(
      highlighted ? Spring.interactive : Spring.smooth,
      () => _pressed.target = highlighted ? 1 : 0,
    ),
    onTap: (_) => widget.onTap(),
  );

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: [_press],
    mouseCursor: SystemMouseCursors.click,
    semantics: widget.semantics,
    child: MotionTransition(
      opacity: _opacity,
      scale: _scale,
      child: widget.child,
    ),
  );
}

class PushButton extends StatelessWidget {
  const PushButton(
    this.label, {
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Tappable(
      onTap: onPressed,
      semantics: SemanticsProperties(button: true, selected: selected),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.fill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyles.label.copyWith(
              color: selected ? palette.onAccent : palette.label,
            ),
          ),
        ),
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({required this.color, this.size = 36, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class Tile extends StatelessWidget {
  const Tile({
    required this.color,
    this.label,
    this.size = 56,
    this.radius = 14,
    super.key,
  });

  final Color color;
  final String? label;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: label == null
          ? null
          : Center(
              child: Text(
                label!,
                style: TextStyles.label.copyWith(
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
    ),
  );
}

class Rail extends StatelessWidget {
  const Rail({required this.child, this.height = 36, super.key});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        Positioned.fill(
          child: Center(
            child: SizedBox(
              height: 4,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.of(context).fill,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class Chevron extends StatelessWidget {
  const Chevron({required this.color, this.back = false, super.key});

  final Color color;
  final bool back;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(9, 16),
    painter: _ChevronPainter(
      color: color,
      back: back != (Directionality.of(context) == TextDirection.rtl),
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.back});

  final Color color;
  final bool back;

  @override
  void paint(Canvas canvas, Size size) {
    final near = back ? size.width - 1 : 1.0;
    final far = back ? 1.0 : size.width - 1;
    canvas.drawPath(
      Path()
        ..moveTo(near, 1)
        ..lineTo(far, size.height / 2)
        ..lineTo(near, size.height - 1),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) =>
      old.color != color || old.back != back;
}

class Travel extends StatelessWidget {
  const Travel({
    required this.progress,
    required this.extent,
    required this.child,
    super.key,
  });

  final MotionValue<double> progress;
  final double extent;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final direction = Directionality.of(context) == TextDirection.rtl
          ? -1
          : 1;
      final travel = (constraints.maxWidth - extent) * direction;
      return MotionTransition(
        translateX: MotionSelection(() => progress.value * travel),
        child: child,
      );
    },
  );
}

class RailDot extends StatelessWidget {
  const RailDot({
    required this.progress,
    required this.color,
    this.size = 28,
    super.key,
  });

  final MotionValue<double> progress;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Rail(
    height: size,
    child: Travel(
      progress: progress,
      extent: size,
      child: Dot(color: color, size: size),
    ),
  );
}
