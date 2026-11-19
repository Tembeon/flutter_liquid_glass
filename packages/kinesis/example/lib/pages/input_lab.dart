import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis_example/controls.dart';
import 'package:kinesis_example/theme.dart';

class InputLabCard extends StatelessWidget {
  const InputLabCard({super.key});

  @override
  Widget build(BuildContext context) => StudioSurface(
    title: 'Hold, Hover, Right-Click, Adjust',
    subtitle:
        'Interactions share one region and settle who takes the touch. A '
        'hold beats the press under it, a hover dwell waits beside a tap, a '
        'right-click or Shift+F10 opens a menu where you asked, and an '
        'interaction of your own takes the arrow keys and VoiceOver.',
    child: LayoutBuilder(
      builder: (context, constraints) {
        const tiles = [_HoldTile(), _HoverTile(), _MenuTile(), _AdjustTile()];
        if (constraints.maxWidth >= 640) {
          return Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: tiles[row * 2]),
                  const SizedBox(width: 12),
                  Expanded(child: tiles[row * 2 + 1]),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _LabTile extends StatelessWidget {
  const _LabTile({
    required this.title,
    required this.hint,
    required this.child,
    this.focused = false,
  });

  final String title;
  final String hint;
  final Widget child;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.blue;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.well,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: focused ? accent : palette.hairline,
          width: focused ? 2 : 1,
        ),
      ),
      child: SizedBox(
        height: 176,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            children: [
              Expanded(child: Center(child: child)),
              const SizedBox(height: 8),
              Text(title, style: palette.label),
              const SizedBox(height: 2),
              Text(
                hint,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: palette.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldTile extends StatefulWidget {
  const _HoldTile();

  @override
  State<_HoldTile> createState() => _HoldTileState();
}

class _HoldTileState extends State<_HoldTile> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _fill = MotionValue<double>(0, clock: _clock);
  late final SymbolEffectMotion _pin = SymbolEffectMotion(clock: _clock);
  late final LongPressInteraction _long = LongPressInteraction(
    onStart: _recognized,
  );
  late final PressInteraction _press = PressInteraction(
    onHighlightChanged: (t, {required highlighted}) {
      if (highlighted) {
        _fill.animate(
          t,
          1,
          animation: TimingCurve.linear(duration: _long.duration),
        );
      } else {
        withSpring(Spring.snappy, () => _fill.retarget(t, 0));
      }
    },
  );
  bool _pinned = false;

  void _recognized(double t) {
    _pin.add(t, const BounceSymbolEffect());
    withSpring(Spring.snappy, () => _fill.retarget(t, 0));
    setState(() => _pinned = !_pinned);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.blue;
    return InputRegion(
      interactions: [_long, _press],
      feedback: (event) =>
          event is LongPressStartEvent ? MotionHaptic.success : null,
      semantics: SemanticsProperties(
        button: true,
        label: _pinned ? 'Pinned' : 'Hold to pin',
      ),
      child: _LabTile(
        title: _pinned ? 'Pinned' : 'Hold',
        hint: 'Press and hold to pin',
        child: CustomPaint(
          painter: _RingPainter(
            fill: _fill,
            color: accent,
            track: palette.hairline,
          ),
          child: SizedBox.square(
            dimension: 76,
            child: Center(
              child: MotionSymbol(
                motion: _pin,
                child: StudioIcon(
                  StudioGlyph.star,
                  size: 30,
                  color: _pinned ? accent : palette.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  _RingPainter({required this.fill, required this.color, required this.track})
    : super(repaint: fill);

  final MotionValue<double> fill;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, stroke..color = track);
    final sweep = fill.value.clamp(0.0, 1.0) * math.pi * 2;
    if (sweep > 0) {
      canvas.drawArc(rect, -math.pi / 2, sweep, false, stroke..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      color != oldDelegate.color || track != oldDelegate.track;
}

class _HoverTile extends StatefulWidget {
  const _HoverTile();

  @override
  State<_HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<_HoverTile> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late final Presence _peek = Presence(
    openSpring: Spring.bouncy,
    closeSpring: Spring.snappy,
    clock: _clock,
  );
  late final ValueListenable<MotionPose> _peekPose = _peek.select(
    (peek) => MotionPose(
      offset: Offset(0, 10 * (1 - peek.progress)),
      scale: 0.8 + 0.2 * peek.progress,
      opacity: peek.progress.clamp(0.0, 1.0),
    ),
  );
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
  }

  @override
  void dispose() {
    _states
      ..removeListener(_statesChanged)
      ..dispose();
    super.dispose();
  }

  void _statesChanged() {
    if (!_states.value.contains(WidgetState.hovered) && _peek.isShown) {
      _peek.hide(_clock.now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.blue;
    return InputRegion(
      statesController: _states,
      interactions: [
        HoverDwellInteraction(duration: 0.45, onDwell: _peek.open),
        PressInteraction(
          onTap: (t) => _peek.turn(t, shown: !_peek.isShown),
        ),
      ],
      semantics: const SemanticsProperties(
        button: true,
        label: 'Show the peek',
      ),
      child: _LabTile(
        title: 'Hover',
        hint: 'Rest a pointer here, or tap',
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            StudioIcon(StudioGlyph.sparkle, size: 30, color: accent),
            Positioned(
              bottom: 46,
              child: MotionTransition(
                pose: _peekPose,
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.textPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      'Held for 0.45 s',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.surface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MenuMotion extends PresentedProgress {
  _MenuMotion({super.clock})
    : super(
        openSpring: Spring.snappy,
        closeSpring: Spring.snappy,
        rest: MotionRest.opacity,
      );

  late final ValueListenable<double> scaleListenable = select(
    (menu) => 0.8 + 0.2 * menu.progress,
  );
  late final ValueListenable<double> opacityListenable = select(
    (menu) => menu.opacity,
  );
}

class _MenuTile extends StatefulWidget {
  const _MenuTile();

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  final PresentationPortalController _portal = PresentationPortalController();
  final GlobalKey _region = GlobalKey();
  Offset _at = Offset.zero;
  String _picked = 'Nothing picked yet';

  void _open(Offset local) {
    final box = _region.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _portal.isPresented) return;
    _at = box.localToGlobal(local);
    _portal.present();
  }

  void _pick(String choice) {
    _portal.dismiss(DismissTrigger.programmatic);
    setState(() => _picked = choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.blue;
    return PresentationPortal(
      controller: _portal,
      presentation: Presentation<void, _MenuMotion>(
        dismissesOnOutsideTap: true,
        motion: (env) => _MenuMotion(clock: env.clock),
        builder: (context, motion) => _PointMenu(
          at: _at,
          motion: motion,
          palette: palette,
          onPick: _pick,
        ),
      ),
      child: InputRegion(
        key: _region,
        interactions: [
          SecondaryClickInteraction(onClick: (t, at) => _open(at)),
          LongPressInteraction(
            onStart: (t) {
              final box = _region.currentContext?.findRenderObject();
              if (box is RenderBox) _open(box.size.center(Offset.zero));
            },
          ),
        ],
        feedback: (event) =>
            event is LongPressStartEvent ? MotionHaptic.mediumImpact : null,
        semantics: SemanticsProperties(
          button: true,
          label: 'Open the menu',
          value: _picked,
        ),
        child: _LabTile(
          title: 'Menu',
          hint: 'Right-click, Shift+F10 or hold',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudioIcon(StudioGlyph.menu, size: 30, color: accent),
              const SizedBox(height: 8),
              MotionContentTransition(
                child: Text(
                  _picked,
                  key: ValueKey<String>(_picked),
                  style: palette.caption.copyWith(color: accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointMenu extends StatelessWidget {
  const _PointMenu({
    required this.at,
    required this.motion,
    required this.palette,
    required this.onPick,
  });

  final Offset at;
  final _MenuMotion motion;
  final StudioPalette palette;
  final ValueChanged<String> onPick;

  static const _width = 180.0;
  static const _height = 150.0;

  @override
  Widget build(BuildContext context) => StudioTheme(
    palette: palette,
    inspector: false,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final left = at.dx.clamp(
          8.0,
          math.max<double>(8, constraints.maxWidth - _width - 8),
        );
        final top = at.dy.clamp(
          8.0,
          math.max<double>(8, constraints.maxHeight - _height - 8),
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: MotionTransition(
                scale: motion.scaleListenable,
                opacity: motion.opacityListenable,
                alignment: Alignment.topLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.hairline),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2E000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: SizedBox(
                      width: _width - 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (label, glyph, color) in [
                            ('Copy Style', StudioGlyph.plus, palette.blue),
                            ('Make Favorite', StudioGlyph.heart, palette.pink),
                            ('Share', StudioGlyph.share, palette.purple),
                          ])
                            _MenuRow(
                              label: label,
                              glyph: glyph,
                              color: color,
                              onTap: () => onPick(label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.label,
    required this.glyph,
    required this.color,
    required this.onTap,
  });

  final String label;
  final StudioGlyph glyph;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  final WidgetStatesController _states = WidgetStatesController();
  late final PressInteraction _press = PressInteraction(
    onTap: (_) => widget.onTap(),
  );

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    return InputRegion(
      interactions: [_press],
      statesController: _states,
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.selection : null,
      semantics: SemanticsProperties(button: true, label: widget.label),
      child: ValueListenableBuilder<Set<WidgetState>>(
        valueListenable: _states,
        builder: (context, states, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: states.contains(WidgetState.pressed)
                ? widget.color.withValues(alpha: 0.2)
                : states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                ? widget.color.withValues(alpha: 0.1)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              StudioIcon(widget.glyph, color: widget.color, size: 15),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _StepInteraction extends Interaction {
  _StepInteraction(this.onCommand);

  final void Function(ValueCommand command) onCommand;

  @override
  bool get adjusts => true;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) onCommand(input.command);
    return InteractionUpdate.none;
  }
}

class _AdjustTile extends StatefulWidget {
  const _AdjustTile();

  @override
  State<_AdjustTile> createState() => _AdjustTileState();
}

class _AdjustTileState extends State<_AdjustTile> {
  static const _max = 10;

  late final MotionClock _clock = MotionClockScope.of(context);
  late final MotionValue<double> _level = MotionValue<double>(
    _value / _max,
    clock: _clock,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'Adjust tile');
  final WidgetStatesController _states = WidgetStatesController();
  late final ValueNotifier<AdjustRange> _range = ValueNotifier(
    _rangeOf(_value),
  );
  int _value = 4;
  int _dragFrom = 4;

  static AdjustRange _rangeOf(int value) =>
      AdjustRange.of(value.toDouble(), min: 0, max: _max.toDouble());

  late final List<Interaction> _interactions = [
    _StepInteraction(_command),
    DragInteraction(
      axis: Axis.horizontal,
      onStart: (_) => _dragFrom = _value,
      onUpdate: (details) =>
          _set(_dragFrom + (details.translation.dx / 14).round()),
    ),
    PressInteraction(onTap: (_) => _focus.requestFocus()),
  ];

  void _command(ValueCommand command) => _set(switch (command) {
    ValueCommand.increase => _value + 1,
    ValueCommand.decrease => _value - 1,
    ValueCommand.increaseLarge => _value + 3,
    ValueCommand.decreaseLarge => _value - 3,
    ValueCommand.toMinimum => 0,
    ValueCommand.toMaximum => _max,
  });

  void _set(int next) {
    final value = next.clamp(0, _max);
    if (value == _value) return;
    final t = _clock.now;
    withSpring(Spring.snappy, () => _level.retarget(t, value / _max));
    _range.value = _rangeOf(value);
    setState(() => _value = value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _states.dispose();
    _range.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = StudioTheme.of(context);
    final accent = StudioPageInfo.maybeOf(context)?.accent ?? palette.blue;
    return InputRegion(
      interactions: _interactions,
      focusNode: _focus,
      statesController: _states,
      adjustRange: _range,
      feedback: (event) =>
          event is ActivationEvent ? MotionHaptic.selection : null,
      semantics: SemanticsProperties(
        slider: true,
        label: 'Level',
        value: '$_value of $_max',
        increasedValue: _value < _max ? '${_value + 1} of $_max' : null,
        decreasedValue: _value > 0 ? '${_value - 1} of $_max' : null,
      ),
      child: ValueListenableBuilder<Set<WidgetState>>(
        valueListenable: _states,
        builder: (context, states, child) => _LabTile(
          title: 'Adjust',
          hint: 'Drag, arrow keys or VoiceOver',
          focused: states.contains(WidgetState.focused),
          child: child!,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MotionNumericText(
              '$_value',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 110,
              height: 8,
              child: CustomPaint(
                painter: _LevelPainter(
                  level: _level,
                  color: accent,
                  track: palette.hairline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _LevelPainter extends CustomPainter {
  _LevelPainter({
    required this.level,
    required this.color,
    required this.track,
  }) : super(repaint: level);

  final MotionValue<double> level;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    final width = size.width * level.value.clamp(0.0, 1.0);
    if (width <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, math.max(width, size.height), size.height),
        radius,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) =>
      color != oldDelegate.color || track != oldDelegate.track;
}
