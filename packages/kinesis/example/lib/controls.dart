import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/theme.dart';

class KinesisButton extends StatefulWidget {
  const KinesisButton({
    required this.label,
    required this.onPressed,
    this.glyph,
    this.accent,
    this.filled = false,
    this.compact = false,
    this.haptic = MotionHaptic.lightImpact,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final StudioGlyph? glyph;
  final Color? accent;
  final bool filled;
  final bool compact;
  final MotionHaptic? haptic;

  @override
  State<KinesisButton> createState() => _KinesisButtonState();
}

class _KinesisButtonState extends State<KinesisButton> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _scale = MotionValue<double>(
    1,
    clock: _clock,
  );
  late final MotionValue<double> _opacity = MotionValue<double>(
    1,
    restDistance: MotionRest.opacity,
    clock: _clock,
  );
  final WidgetStatesController _states = WidgetStatesController();

  late final PressInteraction _press = PressInteraction(
    onHighlightChanged: (t, {required highlighted}) {
      withSpring(Spring.snappy, () {
        _scale.retarget(t, highlighted ? 0.94 : 1);
        _opacity.retarget(t, highlighted ? 0.84 : 1);
      });
    },
    onTap: (_) => widget.onPressed?.call(),
  );

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = widget.accent ?? palette.blue;
    final enabled = widget.onPressed != null;

    return InputRegion(
      enabled: enabled,
      statesController: _states,
      interactions: [_press],
      feedback: (event) => event is ActivationEvent ? widget.haptic : null,
      semantics: SemanticsProperties(button: true, label: widget.label),
      child: MotionTransition(
        scale: _scale,
        opacity: _opacity,
        child: ValueListenableBuilder<Set<WidgetState>>(
          valueListenable: _states,
          builder: (context, states, _) {
            final hovered = states.contains(WidgetState.hovered);
            final focused = states.contains(WidgetState.focused);
            final bg = widget.filled
                ? (hovered ? accent.withValues(alpha: 0.88) : accent)
                : (hovered
                      ? palette.surfaceAlt
                      : palette.surfaceAlt.withValues(alpha: 0.62));
            final fg = widget.filled
                ? const Color(0xFFFFFFFF)
                : (widget.accent ?? palette.textPrimary);
            final padH = widget.compact ? 12.0 : 16.0;
            final padV = widget.compact ? 8.0 : 10.0;

            return DecoratedBox(
              decoration: BoxDecoration(
                color: enabled ? bg : bg.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
                border: Border.all(
                  color: focused
                      ? accent
                      : (widget.filled
                            ? const Color(0x00000000)
                            : palette.hairline),
                  width: focused ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.glyph case final glyph?) ...[
                      StudioIcon(
                        glyph,
                        color: enabled ? fg : fg.withValues(alpha: 0.45),
                        size: widget.compact ? 14 : 15,
                      ),
                      if (widget.label.isNotEmpty) const SizedBox(width: 7),
                    ],
                    if (widget.label.isNotEmpty)
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: widget.compact ? 12.5 : 13.5,
                          fontWeight: FontWeight.w600,
                          color: enabled ? fg : fg.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class KinesisChip extends StatefulWidget {
  const KinesisChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
    this.glyph,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;
  final StudioGlyph? glyph;

  @override
  State<KinesisChip> createState() => _KinesisChipState();
}

class _KinesisChipState extends State<KinesisChip> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _scale = MotionValue<double>(
    1,
    clock: _clock,
  );
  late final PressInteraction _press = PressInteraction(
    onHighlightChanged: (t, {required highlighted}) {
      withSpring(
        Spring.snappy,
        () => _scale.retarget(t, highlighted ? 0.94 : 1),
      );
    },
    onTap: (_) => widget.onTap(),
  );

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = widget.accent ?? palette.blue;
    final bg = widget.selected
        ? accent.withValues(alpha: palette.isDark ? 0.26 : 0.13)
        : palette.surfaceAlt.withValues(alpha: 0.55);
    final fg = widget.selected ? accent : palette.textSecondary;

    return InputRegion(
      interactions: [_press],
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.selection : null,
      semantics: SemanticsProperties(
        button: true,
        selected: widget.selected,
        label: widget.label,
      ),
      child: MotionTransition(
        scale: _scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected
                  ? accent.withValues(alpha: 0.45)
                  : palette.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.glyph case final glyph?) ...[
                  StudioIcon(glyph, color: fg, size: 13),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KinesisSwitch extends StatefulWidget {
  const KinesisSwitch({
    required this.value,
    required this.onChanged,
    this.label,
    this.accent,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final Color? accent;

  @override
  State<KinesisSwitch> createState() => _KinesisSwitchState();
}

class _KinesisSwitchState extends State<KinesisSwitch> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _pos = MotionValue<double>(
    widget.value ? 1 : 0,
    clock: _clock,
  );
  late final MotionValue<double> _stretch = MotionValue<double>(
    0,
    clock: _clock,
  );

  late final PressInteraction _press = PressInteraction(
    onHighlightChanged: (t, {required highlighted}) {
      withSpring(
        Spring.snappy,
        () => _stretch.retarget(t, highlighted ? 1 : 0),
      );
    },
    onTap: (_) => widget.onChanged(!widget.value),
  );

  @override
  void didUpdateWidget(KinesisSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      withSpring(
        Spring.snappy,
        () => _pos.retarget(_clock.now, widget.value ? 1 : 0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = widget.accent ?? palette.green;
    final offTrack = palette.isDark
        ? const Color(0xFF3A3A44)
        : const Color(0xFFD5D5DC);

    return InputRegion(
      interactions: [_press],
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.lightImpact : null,
      semantics: SemanticsProperties(
        toggled: widget.value,
        label: widget.label ?? 'Toggle',
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label case final text?) ...[
            Text(text, style: palette.label),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 42,
            height: 24,
            child: CustomPaint(
              painter: _SwitchPainter(
                pos: _pos,
                stretch: _stretch,
                onColor: accent,
                offColor: offTrack,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SwitchPainter extends CustomPainter {
  _SwitchPainter({
    required this.pos,
    required this.stretch,
    required this.onColor,
    required this.offColor,
  }) : super(repaint: Listenable.merge([pos, stretch]));

  final MotionValue<double> pos;
  final MotionValue<double> stretch;
  final Color onColor;
  final Color offColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pos.value.clamp(0.0, 1.0);
    final s = stretch.value.clamp(0.0, 1.0);
    final trackColor = Color.lerp(offColor, onColor, p)!;
    final trackRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    const pad = 2.0;
    final thumbH = size.height - pad * 2;
    final thumbW = thumbH + 5 * s;
    final travel = size.width - pad * 2 - thumbW;
    final x = pad + travel * p;
    final thumbRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, pad, thumbW, thumbH),
      Radius.circular(thumbH / 2),
    );
    canvas.drawRRect(
      thumbRRect.shift(const Offset(0, 1)),
      Paint()..color = const Color(0x28000000),
    );
    canvas.drawRRect(thumbRRect, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_SwitchPainter oldDelegate) =>
      onColor != oldDelegate.onColor || offColor != oldDelegate.offColor;
}

class KinesisSlider extends StatefulWidget {
  const KinesisSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.valueLabel,
    this.accent,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? valueLabel;
  final Color? accent;

  @override
  State<KinesisSlider> createState() => _KinesisSliderState();
}

class _KinesisSliderState extends State<KinesisSlider> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _thumbScale = MotionValue<double>(
    1,
    clock: _clock,
  );
  late final MotionValue<double> _overshoot = MotionValue<double>(
    0,
    clock: _clock,
  );
  double _trackWidth = 200;
  double _startFraction = 0;

  double get _fraction =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  late final DragInteraction _drag = DragInteraction(
    axis: Axis.horizontal,
    slop: 0,
    onStart: (details) {
      _startFraction = _fraction;
      withSpring(Spring.snappy, () => _thumbScale.retarget(details.time, 1.25));
    },
    onUpdate: (details) {
      final raw = _startFraction + details.translation.dx / _trackWidth;
      final clamped = raw.clamp(0.0, 1.0);
      const band = RubberBand(0, 1, dimension: 0.45);
      final over = band.apply(raw) - clamped;
      _overshoot.snap(details.time, over);
      widget.onChanged(widget.min + clamped * (widget.max - widget.min));
    },
    onEnd: (details) {
      withSpring(Spring.snappy, () {
        _thumbScale.retarget(details.time, 1);
        _overshoot.retarget(details.time, 0);
      });
    },
    onCancel: (t) {
      withSpring(Spring.snappy, () {
        _thumbScale.retarget(t, 1);
        _overshoot.retarget(t, 0);
      });
    },
  );

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = widget.accent ?? palette.blue;
    final readout = widget.valueLabel ?? widget.value.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.label, style: palette.label),
              Text(readout, style: palette.mono),
            ],
          ),
          const SizedBox(height: 6),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            _trackWidth = math.max<double>(80, constraints.maxWidth - 20);
            return InputRegion(
              interactions: [_drag],
              semantics: SemanticsProperties(
                slider: true,
                label: widget.label.isEmpty ? 'Slider' : widget.label,
                value: readout,
              ),
              child: SizedBox(
                height: 30,
                child: CustomPaint(
                  painter: _SliderPainter(
                    fraction: _fraction,
                    thumbScale: _thumbScale,
                    overshoot: _overshoot,
                    accent: accent,
                    trackColor: palette.surfaceAlt,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

final class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.fraction,
    required this.thumbScale,
    required this.overshoot,
    required this.accent,
    required this.trackColor,
  }) : super(repaint: Listenable.merge([thumbScale, overshoot]));

  final double fraction;
  final MotionValue<double> thumbScale;
  final MotionValue<double> overshoot;
  final Color accent;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final overPx = overshoot.value * 24;
    final left = 10.0 + math.min<double>(0, overPx);
    final right = size.width - 10.0 + math.max<double>(0, overPx);
    final trackHeight = 6.0 - overshoot.value.abs().clamp(0.0, 0.25) * 6;
    final radius = Radius.circular(trackHeight / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, cy - trackHeight / 2, right, cy + trackHeight / 2),
        radius,
      ),
      Paint()..color = trackColor,
    );

    final thumbX = left + (right - left) * fraction;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, cy - trackHeight / 2, thumbX, cy + trackHeight / 2),
        radius,
      ),
      Paint()..color = accent,
    );

    final r = 9.5 * thumbScale.value;
    canvas.drawCircle(
      Offset(thumbX, cy + 1.5),
      r,
      Paint()..color = const Color(0x30000000),
    );
    canvas.drawCircle(
      Offset(thumbX, cy),
      r,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      Offset(thumbX, cy),
      r,
      Paint()
        ..color = const Color(0x22000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      accent != oldDelegate.accent ||
      trackColor != oldDelegate.trackColor;
}

class StudioPageHeader extends StatelessWidget {
  const StudioPageHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final info = StudioPageInfo.maybeOf(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info != null) ...[
          Text(
            info.eyebrow.toUpperCase(),
            style: palette.eyebrow(info.accent),
          ),
          const SizedBox(height: 8),
        ],
        Text(title, style: palette.pageTitle),
        const SizedBox(height: 8),
        Text(subtitle, style: palette.pageSubtitle),
      ],
    );
    final extra = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (extra == null) return text;
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 16), extra],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: text),
              const SizedBox(width: 16),
              extra,
            ],
          );
        },
      ),
    );
  }
}

class StudioSurface extends StatelessWidget {
  const StudioSurface({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.hairline),
        boxShadow: palette.cardShadow,
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: palette.title),
                        if (subtitle case final sub?) ...[
                          const SizedBox(height: 4),
                          Text(sub, style: palette.subtitle),
                        ],
                      ],
                    ),
                  ),
                  if (trailing case final extra?) ...[
                    const SizedBox(width: 12),
                    extra,
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class InspectorDrawer extends StatelessWidget {
  const InspectorDrawer({
    required this.apis,
    required this.child,
    this.builds,
    super.key,
  });

  final List<String> apis;
  final Widget child;
  final int? builds;

  @override
  Widget build(BuildContext context) {
    if (!StudioTheme.inspectorOf(context)) {
      return const SizedBox.shrink();
    }
    final palette = StudioTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.well,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final api in apis)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              child: Text(
                                api,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: palette.blue,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (builds case final count?) ...[
                    const SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.green.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          'rebuilds: $count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: palette.green,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
