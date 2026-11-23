import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/motion/changes.dart';
import 'package:kinesis/src/motion/numeric_text.dart';
import 'package:kinesis/src/widgets/follow.dart';
import 'package:kinesis/src/widgets/scope.dart';

/// How a glyph of a [MotionNumericText] looks while it comes in or goes
/// out.
///
/// Subclass it for a look of your own: [poseAt] answers a [MotionPose] for
/// any progress, and the glyph wears it about its own box. Glyphs whose
/// poses share an opacity and a blur are drawn through one offscreen layer.
@immutable
abstract class NumericTextTransition {
  /// Allows subclasses to have const constructors.
  const NumericTextTransition();

  /// SwiftUI's `.numericText` roll: a glyph slides [travel] of its line
  /// height toward the count (up when counting up), fading, blurring up to
  /// [blur] sigma and scaling to [scale] where it is out of place.
  ///
  /// The travel and blur are measured by eye, not from UIKit.
  const factory NumericTextTransition.roll({
    double travel,
    double blur,
    double scale,
  }) = _RollTransition;

  /// Glyphs fade in place.
  const factory NumericTextTransition.fade() = _RollTransition.fade;

  /// The pose of a glyph [progress] of the way in when [incoming], or of
  /// the way out otherwise, rolling [direction].
  ///
  /// Its `offsetFraction` is of the glyph's box, its advance by its line
  /// height, and its pivot is the box's center. The pose at progress 1
  /// coming in and at progress 0 going out should be identity, which is
  /// how the glyph shows at rest.
  MotionPose poseAt(
    double progress, {
    required bool incoming,
    required NumericRollDirection direction,
  });
}

final class _RollTransition extends NumericTextTransition {
  const _RollTransition({this.travel = 0.85, this.blur = 2.5, this.scale = 1})
    : assert(blur >= 0, 'blur is a sigma and cannot be negative');

  const _RollTransition.fade() : travel = 0, blur = 0, scale = 1;

  final double travel;
  final double blur;
  final double scale;

  @override
  MotionPose poseAt(
    double progress, {
    required bool incoming,
    required NumericRollDirection direction,
  }) {
    final away = incoming ? 1 - progress : progress;
    final rolls = direction == NumericRollDirection.up ? 1 : -1;
    final shown = progress.clamp(0.0, 1.0);
    final hidden = incoming ? 1 - shown : shown;
    return MotionPose(
      offsetFraction: Offset(
        0,
        (incoming ? 1 : -1) * rolls * travel * away,
      ),
      scale: 1 - (1 - scale) * hidden,
      opacity: 1 - hidden,
      blur: blur * hidden,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _RollTransition &&
      other.travel == travel &&
      other.blur == blur &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(travel, blur, scale);

  @override
  String toString() =>
      'NumericTextTransition.roll(travel: $travel, blur: $blur, '
      'scale: $scale)';
}

/// Shows numeric [text] that rolls digit by digit when it changes, as
/// SwiftUI's `.contentTransition(.numericText(countsDown:))` does.
///
/// One render object lays the text out as one paragraph, so kerning,
/// letter spacing and tabular figures come from a single layout. Unchanged
/// characters stay; changed ones come and go through [transition] while
/// the characters that stay slide to their new places and the width
/// slides with them, so nothing around the text jumps. A change during a
/// change carries on from what shows. At rest it paints one paragraph; a
/// frame of a change builds nothing, and only a moving width lays out.
///
/// Under Reduce Motion (`MotionTraits.reduceMotion`) glyphs wear only the
/// opacity of [transition], in place.
class MotionNumericText extends LeafRenderObjectWidget {
  /// Creates a rolling numeric text.
  const MotionNumericText(
    this.text, {
    this.style,
    this.roll,
    this.animation = defaultAnimation,
    this.transition = const NumericTextTransition.roll(),
    this.textDirection,
    this.textScaler,
    this.locale,
    this.semanticsLabel,
    super.key,
  });

  /// The formatted text (`'$1,240'`, `'09:59'`, `'42%'`).
  final String text;

  /// The text style, merged over the ambient [DefaultTextStyle].
  final TextStyle? style;

  /// Which way the glyphs roll, or null to compare the old and new numbers:
  /// down when the new one is smaller.
  final NumericRollDirection? roll;

  /// The [Spring] or [TimingCurve] a change runs on.
  final MotionAnimation animation;

  /// The animation a change runs on by default: a crisp, nearly critical
  /// spring.
  static const MotionAnimation defaultAnimation =
      NumericTextMotion.defaultAnimation;

  /// How glyphs come and go.
  final NumericTextTransition transition;

  /// The text direction; [Directionality.of] when null.
  final TextDirection? textDirection;

  /// The text scaling; [MediaQuery.textScalerOf] when null.
  final TextScaler? textScaler;

  /// The locale for font selection; [Localizations.maybeLocaleOf] when
  /// null.
  final Locale? locale;

  /// What screen readers read instead of [text].
  final String? semanticsLabel;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final ambient = _ambient(context);
    return RenderMotionNumericText(
      text: text,
      style: ambient.style,
      textDirection: ambient.direction,
      textScaler: ambient.scaler,
      locale: ambient.locale,
      animation: animation,
      transition: transition,
      traits: ambient.traits,
      semanticsLabel: semanticsLabel,
      following: ambient.following,
      clock: MotionClockScope.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final ambient = _ambient(context);
    (renderObject as RenderMotionNumericText).update(
      text: text,
      style: ambient.style,
      textDirection: ambient.direction,
      textScaler: ambient.scaler,
      locale: ambient.locale,
      roll: roll,
      animation: animation,
      transition: transition,
      traits: ambient.traits,
      semanticsLabel: semanticsLabel,
      following: ambient.following,
    );
  }

  _NumericAmbient _ambient(BuildContext context) => (
    style: DefaultTextStyle.of(context).style.merge(style),
    direction: textDirection ?? Directionality.of(context),
    scaler: textScaler ?? MediaQuery.textScalerOf(context),
    locale: locale ?? Localizations.maybeLocaleOf(context),
    traits: MotionTraitsOverride.of(context),
    following: followsMotion(context),
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text))
      ..add(DiagnosticsProperty<TextStyle>('style', style, defaultValue: null))
      ..add(
        EnumProperty<NumericRollDirection>('roll', roll, defaultValue: null),
      )
      ..add(DiagnosticsProperty<MotionAnimation>('animation', animation))
      ..add(
        DiagnosticsProperty<NumericTextTransition>('transition', transition),
      );
  }
}

typedef _NumericAmbient = ({
  TextStyle style,
  TextDirection direction,
  TextScaler scaler,
  Locale? locale,
  MotionTraits traits,
  bool following,
});

/// The render object of a [MotionNumericText].
@internal
class RenderMotionNumericText extends RenderBox {
  /// Lays [text] out and starts its motion on `clock`.
  RenderMotionNumericText({
    required String text,
    required this._style,
    required this._textDirection,
    required this._textScaler,
    required this._locale,
    required MotionAnimation animation,
    required this._transition,
    required MotionTraits traits,
    required this._semanticsLabel,
    required bool following,
    required this._clock,
  }) : _follow = MotionFollow.render(following: following) {
    _laidOut = _layOut(text);
    _motion = NumericTextMotion(
      text,
      boxes: _boxesOf(text, _laidOut),
      width: _laidOut.width,
      animation: animation,
      clock: _clock,
    )..traits = traits;
    _frame = _motion.select((motion) => motion.frame);
    _shown = _frame.value;
    _follow.hear([(_frame, _read)]);
  }

  final MotionClock _clock;
  late final NumericTextMotion _motion;
  late final MotionSelection<NumericTextFrame> _frame;
  late NumericTextFrame _shown;
  late TextPainter _laidOut;
  final Map<String, _Glyph> _glyphs = {};
  TextStyle _style;
  TextDirection _textDirection;
  TextScaler _textScaler;
  Locale? _locale;
  NumericTextTransition _transition;
  String? _semanticsLabel;
  final MotionFollow _follow;
  int _debugLayers = 0;

  /// What the last paint showed.
  @visibleForTesting
  NumericTextFrame get debugFrame => _shown;

  /// How many offscreen layers the last paint opened, counted in debug
  /// builds only.
  @visibleForTesting
  int get debugLayers => _debugLayers;

  /// Takes the widget's configuration; a new [text] starts a change at the
  /// clock's time.
  void update({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
    required NumericRollDirection? roll,
    required MotionAnimation animation,
    required NumericTextTransition transition,
    required MotionTraits traits,
    required String? semanticsLabel,
    required bool following,
  }) {
    if (traits != _motion.traits) markNeedsPaint();
    _motion
      ..traits = traits
      ..animation = animation;
    if (transition != _transition) {
      _transition = transition;
      markNeedsPaint();
    }
    if (semanticsLabel != _semanticsLabel) {
      _semanticsLabel = semanticsLabel;
      markNeedsSemanticsUpdate();
    }
    if (style != _style ||
        textDirection != _textDirection ||
        textScaler != _textScaler ||
        locale != _locale) {
      _style = style;
      _textDirection = textDirection;
      _textScaler = textScaler;
      _locale = locale;
      _disposeGlyphs();
      _laidOut.dispose();
      _laidOut = _layOut(_motion.text);
      _motion.relayout(
        boxes: _boxesOf(_motion.text, _laidOut),
        width: _laidOut.width,
      );
      markNeedsLayout();
      _read();
    }
    if (text != _motion.text) {
      final laidOut = _layOut(text);
      _motion.setText(
        _clock.now,
        text,
        boxes: _boxesOf(text, laidOut),
        width: laidOut.width,
        roll: roll,
      );
      _laidOut.dispose();
      _laidOut = laidOut;
      markNeedsSemanticsUpdate();
      _read();
    }
    _follow.following = following;
  }

  TextPainter _layOut(String text) => TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: _textDirection,
    textScaler: _textScaler,
    locale: _locale,
    maxLines: 1,
  )..layout();

  static List<Rect> _boxesOf(String text, TextPainter laidOut) {
    final boxes = <Rect>[];
    final height = laidOut.height;
    var offset = 0;
    var right = 0.0;
    for (final rune in text.runes) {
      final length = rune > 0xFFFF ? 2 : 1;
      final parts = laidOut.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + length),
      );
      offset += length;
      if (parts.isEmpty) {
        boxes.add(Rect.fromLTWH(right, 0, 0, height));
        continue;
      }
      var left = parts.first.left;
      var end = parts.first.right;
      for (final part in parts.skip(1)) {
        left = math.min(left, part.left);
        end = math.max(end, part.right);
      }
      right = end;
      boxes.add(Rect.fromLTRB(left, 0, end, height));
    }
    return boxes;
  }

  _Glyph _glyph(String character) => _glyphs.putIfAbsent(character, () {
    final painter = _layOut(character);
    final boxes = _boxesOf(character, painter);
    return (painter: painter, left: boxes.isEmpty ? 0 : boxes.first.left);
  });

  void _disposeGlyphs() {
    for (final glyph in _glyphs.values) {
      glyph.painter.dispose();
    }
    _glyphs.clear();
  }

  void _read() {
    final frame = _frame.value;
    if (frame == _shown) return;
    if (frame.width != _shown.width) markNeedsLayout();
    _shown = frame;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _follow.attach();
  }

  @override
  void detach() {
    _follow.detach();
    super.detach();
  }

  @override
  void dispose() {
    _disposeGlyphs();
    _laidOut.dispose();
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTestSelf(Offset position) => true;

  Size get _natural => Size(_shown.width, _laidOut.height);

  @override
  double computeMinIntrinsicWidth(double height) => _shown.width;

  @override
  double computeMaxIntrinsicWidth(double height) => _shown.width;

  @override
  double computeMinIntrinsicHeight(double width) => _laidOut.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _laidOut.height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(_natural);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _laidOut.computeDistanceToActualBaseline(baseline);

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _laidOut.computeDistanceToActualBaseline(baseline);

  @override
  void performLayout() => size = constraints.constrain(_natural);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (kDebugMode) _debugLayers = 0;
    final frame = _shown;
    final canvas = context.canvas;
    if (frame.settled) {
      _laidOut.paint(canvas, offset);
      return;
    }
    final groups = <(double, double), List<(NumericGlyph, MotionPose)>>{};
    for (final glyph in frame.glyphs) {
      final pose = _poseOf(glyph);
      if (pose.opacity <= 0) continue;
      if (pose.opacity >= 1 && pose.blur == 0) {
        _paintGlyph(canvas, offset, glyph, pose);
        continue;
      }
      groups.putIfAbsent((pose.opacity, pose.blur), () => []).add((
        glyph,
        pose,
      ));
    }
    for (final MapEntry(key: (opacity, blur), value: members)
        in groups.entries) {
      if (kDebugMode) _debugLayers++;
      canvas.saveLayer(
        _boundsOf(members, offset, blur),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
          ..imageFilter = blur > 0
              ? ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                )
              : null,
      );
      for (final (glyph, pose) in members) {
        _paintGlyph(canvas, offset, glyph, pose);
      }
      canvas.restore();
    }
  }

  MotionPose _poseOf(NumericGlyph glyph) => wornDuringChange(
    arriving: switch (glyph.arrival) {
      final arrival? => _transition.poseAt(
        arrival.progress,
        incoming: true,
        direction: arrival.direction,
      ),
      null => null,
    },
    leaving: switch (glyph.departure) {
      final departure? => _transition.poseAt(
        departure.progress,
        incoming: false,
        direction: departure.direction,
      ),
      null => null,
    },
    traits: _motion.traits,
  );

  void _paintGlyph(
    Canvas canvas,
    Offset offset,
    NumericGlyph glyph,
    MotionPose pose,
  ) {
    final (:painter, :left) = _glyph(glyph.character);
    final box = glyph.box;
    final moved =
        offset + box.topLeft.translate(-left, 0) + pose.offsetFor(box.size);
    if (pose.scale == 1 && pose.rotation == 0) {
      painter.paint(canvas, moved);
      return;
    }
    final half = box.size.center(Offset.zero);
    canvas
      ..save()
      ..translate(moved.dx + left + half.dx, moved.dy + half.dy)
      ..rotate(pose.rotation)
      ..scale(pose.scale);
    painter.paint(canvas, -half.translate(left, 0));
    canvas.restore();
  }

  // The drawn glyphs' boxes, grown by what a glyph's ink may overhang its
  // box and by the reach of the blur, so the layer cuts neither.
  Rect _boundsOf(
    List<(NumericGlyph, MotionPose)> members,
    Offset offset,
    double blur,
  ) {
    Rect? bounds;
    for (final (glyph, pose) in members) {
      final box = glyph.box;
      final grown = (pose.scale - 1).abs() * box.longestSide;
      final drawn = box
          .shift(offset + pose.offsetFor(box.size))
          .inflate(grown + box.height * 0.25);
      bounds = bounds?.expandToInclude(drawn) ?? drawn;
    }
    return bounds!.inflate(blur * 3);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _semanticsLabel ?? _motion.text
      ..textDirection = _textDirection;
  }
}

// A character laid out alone: its painter and where its box starts in that
// layout. Letter spacing splits around a glyph, so a lone glyph's box can
// start left of zero just as it does inside the whole text.
typedef _Glyph = ({TextPainter painter, double left});
