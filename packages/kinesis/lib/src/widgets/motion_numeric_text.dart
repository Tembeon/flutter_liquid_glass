import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// Displays numeric [text] with SwiftUI-style rolling digit transitions
/// (`.contentTransition(.numericText(countsDown:))`).
///
/// Unchanged prefixes, suffixes, and digits stay stationary while changed
/// digits roll vertically on [spring] with composited opacity and optional
/// Gaussian [blur] — performing zero widget rebuilds per animation frame.
/// Under Reduce Motion (`MotionTraits.reduceMotion`), digits cross-fade in
/// place instead of sliding.
class MotionNumericText extends StatefulWidget {
  /// Creates a rolling numeric text display.
  const MotionNumericText(
    this.text, {
    this.style,
    this.countsDown,
    this.spring = NumericTextMotion.defaultSpring,
    this.blur = true,
    this.semanticsLabel,
    super.key,
  });

  /// The formatted text to display (e.g. `'$1,240'`, `'09:59'`, `'42%'`).
  final String text;

  /// Optional text style; merged with the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Explicit roll direction (`true` rolls down, `false` rolls up); when null,
  /// inferred automatically by comparing the numeric values of the old and new
  /// strings.
  final bool? countsDown;

  /// The spring driving digit transitions.
  final Spring spring;

  /// Whether rolling digits apply a subtle mid-flight blur (`[approx]` max
  /// sigma 2.5 logical pixels, disabled under Reduce Motion).
  final bool blur;

  /// Optional override semantics label; defaults to [text].
  final String? semanticsLabel;

  @override
  State<MotionNumericText> createState() => _MotionNumericTextState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text))
      ..add(DiagnosticsProperty<TextStyle>('style', style, defaultValue: null))
      ..add(FlagProperty('countsDown', value: countsDown, ifTrue: 'down'))
      ..add(DiagnosticsProperty<Spring>('spring', spring))
      ..add(FlagProperty('blur', value: blur, ifTrue: 'blur'));
  }
}

class _MotionNumericTextState extends State<MotionNumericText> {
  late final MotionClock _clock = MotionClockScope.of(context);
  late NumericTextMotion _motion = NumericTextMotion(
    widget.text,
    spring: widget.spring,
    clock: _clock,
  );
  List<NumericSlot> _slots = const [];

  @override
  void initState() {
    super.initState();
    _slots = _motion.slots;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.traits = MotionTraitsOverride.of(context);
  }

  @override
  void didUpdateWidget(MotionNumericText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spring != oldWidget.spring) {
      _motion = NumericTextMotion(
        oldWidget.text,
        spring: widget.spring,
        clock: _clock,
      )..traits = MotionTraitsOverride.of(context);
    }
    if (widget.text != oldWidget.text) {
      _motion.setText(_clock.now, widget.text, countsDown: widget.countsDown);
      _slots = _motion.slotsAt(_clock.now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style
        .merge(widget.style);
    final fontSize = effectiveStyle.fontSize ?? 14;
    final lineHeight = fontSize * (effectiveStyle.height ?? 1.2);
    final reduceMotion = _motion.traits.reduceMotion;

    return Semantics(
      label: widget.semanticsLabel ?? widget.text,
      excludeSemantics: true,
      child: DefaultTextStyle(
        style: effectiveStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textBaseline: TextBaseline.alphabetic,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          children: [
            for (var i = 0; i < _slots.length; i++)
              _RollingSlot(
                key: ValueKey<String>(
                  '$i:${_slots[i].previous ?? ''}>${_slots[i].current}',
                ),
                slot: _slots[i],
                progress: _motion.progressListenable,
                clock: _clock,
                travel: lineHeight * 0.85,
                blur: widget.blur && !reduceMotion,
              ),
          ],
        ),
      ),
    );
  }
}

class _RollingSlot extends StatefulWidget {
  const _RollingSlot({
    required this.slot,
    required this.progress,
    required this.clock,
    required this.travel,
    required this.blur,
    super.key,
  });

  final NumericSlot slot;
  final ValueListenable<double> progress;
  final MotionClock clock;
  final double travel;
  final bool blur;

  @override
  State<_RollingSlot> createState() => _RollingSlotState();
}

class _RollingSlotState extends State<_RollingSlot> {
  late final MotionSelection<double> _inY = MotionSelection<double>(
    () => (1 - widget.progress.value) * widget.slot.direction * widget.travel,
    clock: widget.clock,
  );
  late final MotionSelection<double> _outY = MotionSelection<double>(
    () => -widget.progress.value * widget.slot.direction * widget.travel,
    clock: widget.clock,
  );
  late final MotionSelection<double> _inOpacity = MotionSelection<double>(
    () => widget.progress.value.clamp(0.0, 1.0),
    clock: widget.clock,
  );
  late final MotionSelection<double> _outOpacity = MotionSelection<double>(
    () => (1 - widget.progress.value).clamp(0.0, 1.0),
    clock: widget.clock,
  );
  late final MotionSelection<double> _inBlur = MotionSelection<double>(
    () => widget.blur ? (1 - widget.progress.value.clamp(0.0, 1.0)) * 2.5 : 0.0,
    clock: widget.clock,
  );
  late final MotionSelection<double> _outBlur = MotionSelection<double>(
    () => widget.blur ? widget.progress.value.clamp(0.0, 1.0) * 2.5 : 0.0,
    clock: widget.clock,
  );

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final staticSlot = slot.previous == null && !slot.entering && !slot.leaving;
    if (staticSlot) {
      return Text(slot.current, softWrap: false);
    }

    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (slot.previous case final prev?)
            MotionTransition(
              translateY: _outY,
              opacity: _outOpacity,
              blur: widget.blur ? _outBlur : null,
              child: Text(prev, softWrap: false),
            ),
          if (!slot.leaving)
            MotionTransition(
              translateY: _inY,
              opacity: _inOpacity,
              blur: widget.blur ? _inBlur : null,
              child: Text(slot.current, softWrap: false),
            ),
        ],
      ),
    );
  }
}
