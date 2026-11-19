import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/animation.dart';
import 'package:kinesis/src/motion/motion.dart';
import 'package:kinesis/src/motion/rest.dart';
import 'package:kinesis/src/motion/value.dart';

/// One glyph of a [NumericTextMotion] at one moment: what it shows, where
/// it is, and how far it has come in or gone out.
@immutable
final class NumericGlyph {
  /// Creates a glyph snapshot.
  const NumericGlyph({
    required this.character,
    required this.box,
    this.arrival,
    this.departure,
    this.arrivalDirection = 0,
    this.departureDirection = 0,
  });

  /// The character the glyph shows.
  final String character;

  /// Where the glyph is, in the text's own coordinates: its box in the
  /// layout it belongs to, moved by the slide still running.
  final Rect box;

  /// How far the glyph has come in, from 0 to 1 (a bouncy spring swings
  /// past 1), or null when no change that brought it is still running.
  final double? arrival;

  /// How far the glyph has gone out, from 0 to 1, or null while it stays.
  final double? departure;

  /// The way [arrival] rolls: 1 counting up (in from below), -1 counting
  /// down (in from above), 0 in place.
  final int arrivalDirection;

  /// The way [departure] rolls: 1 counting up (out upward), -1 counting
  /// down (out downward), 0 in place.
  final int departureDirection;

  @override
  bool operator ==(Object other) =>
      other is NumericGlyph &&
      other.character == character &&
      other.box == box &&
      other.arrival == arrival &&
      other.departure == departure &&
      other.arrivalDirection == arrivalDirection &&
      other.departureDirection == departureDirection;

  @override
  int get hashCode => Object.hash(
    character,
    box,
    arrival,
    departure,
    arrivalDirection,
    departureDirection,
  );

  @override
  String toString() =>
      'NumericGlyph("$character", $box, arrival: $arrival, '
      'departure: $departure)';
}

/// What a [NumericTextMotion] shows at one moment.
@immutable
final class NumericTextFrame {
  /// Creates a frame snapshot.
  const NumericTextFrame({
    required this.glyphs,
    required this.width,
    required this.settled,
  });

  /// Every glyph on screen: the ones leaving first, then the text's own in
  /// order.
  final List<NumericGlyph> glyphs;

  /// The width the text takes now, sliding from one layout's to the next.
  final double width;

  /// Whether no change runs: the text shows exactly as laid out.
  final bool settled;

  @override
  bool operator ==(Object other) =>
      other is NumericTextFrame &&
      other.width == width &&
      other.settled == settled &&
      listEquals(other.glyphs, glyphs);

  @override
  int get hashCode => Object.hash(width, settled, Object.hashAll(glyphs));
}

/// The law of SwiftUI's rolling numeric text
/// (`.contentTransition(.numericText(countsDown:))`), glyph by glyph.
///
/// The law knows no fonts: whoever lays the text out hands each text its
/// glyph boxes, one per character, and its width. A change keeps the
/// unchanged prefix and suffix and right-aligns the changing middle, so
/// place values (`9 -> 10`, `$1,239 -> $1,240`) roll column by column:
/// a character that stays slides from its old box to its new one, a
/// changed or removed one leaves and a new one arrives, and the width
/// slides with them. Under `traits.reduceMotion` glyphs come and go in
/// place (direction 0).
///
/// A change never snaps what is on screen: each change has a progress of
/// its own, a glyph still arriving when the next change replaces it keeps
/// arriving while it leaves, and slides add up. At most [maxChanges]
/// changes run at once; a further one finishes the oldest at once.
///
/// `[approx]` SwiftUI's own spring for `.numericText` is unmeasured;
/// [defaultAnimation] is a crisp, nearly critical spring.
final class NumericTextMotion extends Motion {
  /// Creates the motion showing [text], laid out in [boxes] (one per
  /// character) and `width`.
  NumericTextMotion(
    String text, {
    required List<Rect> boxes,
    required this._width,
    this.animation = defaultAnimation,
    super.clock,
  }) : _text = text {
    _glyphs.addAll(_laidOut(text, boxes));
  }

  /// `[approx]` The default animation of a change.
  static const MotionAnimation defaultAnimation = Spring.response(
    0.34,
    dampingRatio: 0.88,
  );

  /// How many changes may run at once.
  static const int maxChanges = 3;

  /// The [Spring] or [TimingCurve] a change runs on.
  MotionAnimation animation;

  String _text;
  double _width;
  final List<_Glyph> _glyphs = [];
  final List<_Move> _widthMoves = [];
  final List<_Change> _changes = [];

  /// The text shown once the running changes finish.
  String get text => _text;

  /// What shows at [now].
  NumericTextFrame get frame => frameAt(now);

  /// What shows at [t].
  NumericTextFrame frameAt(double t) => NumericTextFrame(
    glyphs: [for (final glyph in _glyphs) glyph.at(t)],
    width: _width - _owed(_widthMoves, t),
    settled: _changes.isEmpty,
  );

  /// Shows [next], laid out in [boxes] and [width], from time [t].
  ///
  /// [countsDown] picks the roll; when null it compares the first signed
  /// number of the old and new text (`next < old` rolls down). Unanimated,
  /// [next] shows at once and running changes end.
  void setText(
    double t,
    String next, {
    required List<Rect> boxes,
    required double width,
    bool? countsDown,
    bool animated = true,
  }) {
    advance(t);
    if (next == _text) {
      relayout(boxes: boxes, width: width);
      return;
    }
    final previous = _text;
    _text = next;
    if (!animated) {
      _endChanges();
      _glyphs
        ..clear()
        ..addAll(_laidOut(next, boxes));
      _width = width;
      changed();
      return;
    }
    if (_changes.length >= maxChanges) _finish(_changes.first, t);

    final down = countsDown ?? _inferCountsDown(previous, next);
    final direction = traits.reduceMotion ? 0 : (down ? -1 : 1);
    final change = _Change(
      own(
        MotionValue<double>(0, restDistance: MotionRest.opacity),
        rest: () => MotionRest.opacity,
      ),
    );
    _changes.add(change);

    final staying = [
      for (final glyph in _glyphs)
        if (glyph.departure == null) glyph,
    ];
    final characters = _characters(next);
    assert(
      boxes.length == characters.length,
      'A text is laid out in one box per character.',
    );
    final matches = _match(
      [for (final glyph in staying) glyph.character],
      characters,
    );
    final kept = <_Glyph>{};
    final shown = <_Glyph>[];
    for (var i = 0; i < characters.length; i++) {
      final match = matches[i];
      if (match != null) {
        final glyph = staying[match];
        final shift = boxes[i].left - glyph.box.left;
        if (shift != 0) glyph.moves.add(_Move(change, shift));
        glyph.box = boxes[i];
        kept.add(glyph);
        shown.add(glyph);
      } else {
        shown.add(
          _Glyph(characters[i], boxes[i])
            ..arrival = change
            ..arrivalDirection = direction,
        );
      }
    }
    final leaving = [
      for (final glyph in _glyphs)
        if (glyph.departure != null) glyph,
      for (final glyph in staying)
        if (!kept.contains(glyph))
          glyph
            ..departure = change
            ..departureDirection = direction,
    ];
    _glyphs
      ..clear()
      ..addAll(leaving)
      ..addAll(shown);

    if (width != _width) _widthMoves.add(_Move(change, width - _width));
    _width = width;

    change.progress.animate(
      t,
      1,
      animation: animation.resolve(reduceMotion: traits.reduceMotion),
    );
  }

  /// Moves the text's own glyphs to [boxes] and its width to [width] at
  /// once, slides and arrivals still running: a new font size or text
  /// scale, not a change.
  void relayout({required List<Rect> boxes, required double width}) {
    var i = 0;
    for (final glyph in _glyphs) {
      if (glyph.departure != null) continue;
      glyph.box = boxes[i++];
    }
    assert(i == boxes.length, 'A text is laid out in one box per character.');
    _width = width;
    changed();
  }

  @override
  void didAdvance(double t) {
    for (final change in List<_Change>.of(_changes)) {
      if (change.progress.restsAt(t, MotionRest.opacity)) _retire(change);
    }
  }

  void _finish(_Change change, double t) {
    change.progress.snap(t, 1);
    _retire(change);
  }

  void _retire(_Change change) {
    _changes.remove(change);
    disown(change.progress);
    _widthMoves.removeWhere((move) => move.change == change);
    _glyphs.removeWhere((glyph) => glyph.departure == change);
    for (final glyph in _glyphs) {
      glyph.moves.removeWhere((move) => move.change == change);
      if (glyph.arrival == change) glyph.arrival = null;
    }
  }

  void _endChanges() {
    for (final change in List<_Change>.of(_changes)) {
      _retire(change);
    }
  }

  static List<_Glyph> _laidOut(String text, List<Rect> boxes) {
    final characters = _characters(text);
    assert(
      boxes.length == characters.length,
      'A text is laid out in one box per character.',
    );
    return [
      for (var i = 0; i < characters.length; i++)
        _Glyph(characters[i], boxes[i]),
    ];
  }

  static List<String> _characters(String text) => [
    for (final rune in text.runes) String.fromCharCode(rune),
  ];

  // For each character of [next], the index of the character of [old] it
  // keeps, or null where a new one arrives. Unchanged non-digit prefix and
  // suffix stay; the middle is right-aligned so place values line up.
  static List<int?> _match(List<String> old, List<String> next) {
    final shortest = math.min(old.length, next.length);
    var prefix = 0;
    while (prefix < shortest &&
        old[prefix] == next[prefix] &&
        !_isDigit(old[prefix])) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        old[old.length - 1 - suffix] == next[next.length - 1 - suffix] &&
        !_isDigit(old[old.length - 1 - suffix])) {
      suffix++;
    }
    final matches = List<int?>.filled(next.length, null);
    for (var i = 0; i < prefix; i++) {
      matches[i] = i;
    }
    for (var i = 0; i < suffix; i++) {
      matches[next.length - 1 - i] = old.length - 1 - i;
    }
    final oldMiddle = old.length - prefix - suffix;
    final nextMiddle = next.length - prefix - suffix;
    final shared = math.min(oldMiddle, nextMiddle);
    for (var i = 1; i <= shared; i++) {
      final o = prefix + oldMiddle - i;
      final n = prefix + nextMiddle - i;
      if (old[o] == next[n]) matches[n] = o;
    }
    return matches;
  }

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

  static bool _isDigit(String character) {
    if (character.length != 1) return false;
    final code = character.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }
}

double _owed(List<_Move> moves, double t) {
  var owed = 0.0;
  for (final move in moves) {
    owed += move.delta * (1 - move.change.progress.valueAt(t));
  }
  return owed;
}

final class _Change {
  _Change(this.progress);

  final MotionValue<double> progress;
}

// A slide of [delta] still owed by a glyph or the width: it shrinks to
// nothing as its change completes, so slides of changes that overlap add
// up without a jump.
final class _Move {
  _Move(this.change, this.delta);

  final _Change change;
  final double delta;
}

final class _Glyph {
  _Glyph(this.character, this.box);

  final String character;
  Rect box;
  final List<_Move> moves = [];
  _Change? arrival;
  int arrivalDirection = 0;
  _Change? departure;
  int departureDirection = 0;

  NumericGlyph at(double t) => NumericGlyph(
    character: character,
    box: box.translate(-_owed(moves, t), 0),
    arrival: arrival?.progress.valueAt(t),
    departure: departure?.progress.valueAt(t),
    arrivalDirection: arrivalDirection,
    departureDirection: departureDirection,
  );
}
