import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/value.dart';

/// A single character slot inside a [NumericTextMotion] transition.
@immutable
final class NumericSlot {
  /// Creates a character slot snapshot.
  const NumericSlot({
    required this.current,
    this.previous,
    this.progress = 1,
    this.direction = 0,
    this.entering = false,
    this.leaving = false,
  });

  /// The incoming or resting glyph in this slot (`''` when [leaving]).
  final String current;

  /// The outgoing glyph being replaced, or null when unchanged or [entering].
  final String? previous;

  /// Normalized transition progress `0..1` (may slightly overshoot on bouncy
  /// springs).
  final double progress;

  /// Roll direction: `+1` counting up (new digit enters from below), `-1`
  /// counting down (new digit enters from above), or `0` stationary / fade.
  final int direction;

  /// Whether this slot was newly inserted (e.g. `9 -> 10`).
  final bool entering;

  /// Whether this slot is being removed (e.g. `10 -> 9`).
  final bool leaving;

  @override
  bool operator ==(Object other) =>
      other is NumericSlot &&
      other.current == current &&
      other.previous == previous &&
      other.progress == progress &&
      other.direction == direction &&
      other.entering == entering &&
      other.leaving == leaving;

  @override
  int get hashCode =>
      Object.hash(current, previous, progress, direction, entering, leaving);

  @override
  String toString() {
    final prev = previous == null ? null : '"$previous"';
    return 'NumericSlot(current: "$current", previous: $prev, '
        'progress: $progress, direction: $direction)';
  }
}

/// Pure motion law for SwiftUI-style rolling numeric text transitions
/// (`.contentTransition(.numericText(countsDown:))`).
///
/// `[approx]` SwiftUI's exact internal spring for `.numericText` is unmeasured;
/// [defaultSpring] uses a crisp critical-to-light spring (`response: 0.34`,
/// `dampingRatio: 0.88`).
///
/// Keeps unchanged prefix and suffix characters stationary and right-aligns
/// changing character runs so place values (`9 -> 10`, `$1,239 -> $1,240`)
/// roll smoothly per column. Under `traits.reduceMotion`, slots cross-fade
/// (`direction == 0`) instead of rolling vertically.
final class NumericTextMotion extends Motion {
  /// Creates a numeric text motion starting at [initialText].
  NumericTextMotion(
    String initialText, {
    this.spring = defaultSpring,
    super.clock,
  }) : _text = initialText {
    _progress = own(
      MotionValue<double>(1, spring: spring, restDistance: MotionRest.opacity),
      rest: () => MotionRest.opacity,
    );
    _slots = _restingSlots(initialText);
  }

  /// `[approx]` Default spring for rolling numeric transitions.
  static const Spring defaultSpring = Spring.response(0.34, dampingRatio: 0.88);

  /// The spring driving each digit roll transition.
  final Spring spring;

  String _text;
  late final MotionValue<double> _progress;
  List<_SlotState> _slots = const [];

  /// The current target text.
  String get text => _text;

  /// Reactive transition progress `0..1` for render-level widgets.
  ValueListenable<double> get progressListenable => _progress;

  /// Current transition progress at [now].
  double get progress => _progress.valueAt(now);

  /// Current character slots evaluated at [now].
  List<NumericSlot> get slots => slotsAt(now);

  /// Character slots evaluated at explicit time [t].
  List<NumericSlot> slotsAt(double t) {
    final p = _progress.valueAt(t);
    final settled = _progress.restsAt(t, MotionRest.opacity);
    if (settled) {
      return [
        for (final slot in _slots)
          if (!slot.leaving) NumericSlot(current: slot.current),
      ];
    }
    return [
      for (final slot in _slots)
        NumericSlot(
          current: slot.current,
          previous: slot.previous,
          progress: slot.changed ? p : 1,
          direction: slot.changed ? slot.direction : 0,
          entering: slot.entering,
          leaving: slot.leaving,
        ),
    ];
  }

  /// Updates the displayed text to [next] at time [t].
  ///
  /// When [countsDown] is null, the roll direction is inferred by parsing the
  /// first signed numeric value in the old and new strings (`next < old` rolls
  /// down, otherwise up). When [animated] is false, jumps immediately.
  void setText(
    double t,
    String next, {
    bool? countsDown,
    bool animated = true,
  }) {
    advance(t);
    if (next == _text) return;
    final previous = _text;
    _text = next;
    if (!animated) {
      _slots = _restingSlots(next);
      _progress.snap(t, 1);
      changed();
      return;
    }

    final down = countsDown ?? _inferCountsDown(previous, next);
    final dir = traits.reduceMotion ? 0 : (down ? -1 : 1);
    _slots = _diffSlots(previous, next, dir);
    _progress.snap(t, 0);
    _progress.retarget(
      t,
      1,
      spring: spring.resolve(reduceMotion: traits.reduceMotion),
    );
    changed();
  }

  @override
  void didAdvance(double t) {
    if (_progress.restsAt(t, MotionRest.opacity) &&
        _slots.any((s) => s.changed || s.leaving)) {
      _slots = _restingSlots(_text);
    }
  }

  static List<_SlotState> _restingSlots(String text) => [
    for (final rune in text.runes)
      _SlotState(
        current: String.fromCharCode(rune),
        previous: null,
        direction: 0,
        changed: false,
        entering: false,
        leaving: false,
      ),
  ];

  static bool _inferCountsDown(String previous, String next) {
    final a = _parseNumber(previous);
    final b = _parseNumber(next);
    if (a != null && b != null) return b < a;
    return next.compareTo(previous) < 0;
  }

  static double? _parseNumber(String text) {
    final buffer = StringBuffer();
    var hasDigit = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        buffer.writeCharCode(code);
        hasDigit = true;
      } else if (code == 46 && hasDigit && !buffer.toString().contains('.')) {
        buffer.write('.');
      } else if (code == 45 && !hasDigit && buffer.isEmpty) {
        buffer.write('-');
      }
    }
    if (!hasDigit) return null;
    return double.tryParse(buffer.toString());
  }

  static List<_SlotState> _diffSlots(String oldText, String newText, int dir) {
    final oldChars = [for (final r in oldText.runes) String.fromCharCode(r)];
    final newChars = [for (final r in newText.runes) String.fromCharCode(r)];

    var prefix = 0;
    final minLen = math.min(oldChars.length, newChars.length);
    while (prefix < minLen &&
        oldChars[prefix] == newChars[prefix] &&
        !_isDigit(oldChars[prefix])) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < minLen - prefix &&
        oldChars[oldChars.length - 1 - suffix] ==
            newChars[newChars.length - 1 - suffix] &&
        !_isDigit(oldChars[oldChars.length - 1 - suffix])) {
      suffix++;
    }

    final oldMid = oldChars.sublist(prefix, oldChars.length - suffix);
    final newMid = newChars.sublist(prefix, newChars.length - suffix);
    final maxMid = math.max(oldMid.length, newMid.length);
    final oldPad = maxMid - oldMid.length;
    final newPad = maxMid - newMid.length;

    final result = <_SlotState>[];
    for (var i = 0; i < prefix; i++) {
      result.add(
        _SlotState(
          current: newChars[i],
          previous: null,
          direction: 0,
          changed: false,
          entering: false,
          leaving: false,
        ),
      );
    }

    // Right-align the numeric middle so units, tens, hundreds stay aligned.
    for (var i = 0; i < maxMid; i++) {
      final prev = i >= oldPad ? oldMid[i - oldPad] : null;
      final curr = i >= newPad ? newMid[i - newPad] : null;
      if (prev != null && curr != null) {
        final same = prev == curr;
        result.add(
          _SlotState(
            current: curr,
            previous: same ? null : prev,
            direction: same ? 0 : dir,
            changed: !same,
            entering: false,
            leaving: false,
          ),
        );
      } else if (curr != null) {
        result.add(
          _SlotState(
            current: curr,
            previous: null,
            direction: dir,
            changed: true,
            entering: true,
            leaving: false,
          ),
        );
      } else if (prev != null) {
        result.add(
          _SlotState(
            current: '',
            previous: prev,
            direction: dir,
            changed: true,
            entering: false,
            leaving: true,
          ),
        );
      }
    }

    for (var i = newChars.length - suffix; i < newChars.length; i++) {
      result.add(
        _SlotState(
          current: newChars[i],
          previous: null,
          direction: 0,
          changed: false,
          entering: false,
          leaving: false,
        ),
      );
    }
    return result;
  }

  static bool _isDigit(String char) {
    if (char.length != 1) return false;
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }
}

final class _SlotState {
  const _SlotState({
    required this.current,
    required this.previous,
    required this.direction,
    required this.changed,
    required this.entering,
    required this.leaving,
  });

  final String current;
  final String? previous;
  final int direction;
  final bool changed;
  final bool entering;
  final bool leaving;
}
