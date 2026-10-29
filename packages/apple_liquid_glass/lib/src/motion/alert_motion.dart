import 'package:apple_liquid_glass/src/motion/rest.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:meta/meta.dart';

/// The measured tuning and geometry of an iOS 27 alert
/// (UIAlertController with the alert style).
@internal
abstract final class AlertTuning {
  /// The spring of every alert animation: the dimming, the alert's opacity
  /// and its scale, presenting and dismissing. UIKit runs a
  /// CASpringAnimation of stiffness 522.35 and damping 45.71, mass 1:
  /// response 0.275 s, critically damped.
  static const spring = Spring.response(0.2749);

  /// The scale an alert presents from: it shrinks from this size to its
  /// own while it fades in (fitted 1.199 on an iPhone 16 Pro, 0.02
  /// percent rms; 1.196 on the simulator). A dismissing alert only fades.
  static const double presentScale = 1.199;

  /// The opacity of the black dimming behind an alert.
  static const double dimmingOpacity = 0.2;

  /// The alert text size in points, from the UIKit layout captures.
  static const double textFontSize = 17;

  /// The 17-point text line height in the UIKit layout captures.
  static const double textLineHeight = 20.33;

  /// The line-height multiplier of 17-point alert text.
  static const double textHeight = textLineHeight / textFontSize;

  /// The message line-height multiplier from the UIKit layout captures.
  static const double messageHeight = 1.2;

  /// The preferred action's semibold weight from the UIKit layout captures.
  static const FontWeight preferredWeight = FontWeight.w600;

  /// The single header's regular weight from the UIKit layout captures.
  static const FontWeight singleHeaderWeight = FontWeight.w400;

  /// The button's horizontal text inset from the UIKit layout captures.
  static const double buttonTextInset = 12;

  /// The screen-side alert margin, an engineering layout default.
  static const double screenMargin = 20;

  /// The text scale cap, an engineering layout default.
  static const double maxTextScale = 2;

  /// The flat fallback shadow sigma, an engineering rendering default.
  static const double flatShadowSigma = 24;

  /// The flat fallback shadow offset, an engineering rendering default.
  static const double flatShadowOffset = 8;

  /// The width of an alert.
  static const double width = 320;

  /// The corner radius of an alert's platter.
  static const double cornerRadius = 34;

  /// The space between the top of an alert and its first text label.
  ///
  /// UIKit's view dumps of iOS 27 alerts on the device (scene x4disalert,
  /// tool/ios_reference/references/disabled/dumps): the title `UILabel`
  /// rests 22 points under the platter's top in a column alert (313 in a
  /// platter at 291) and in a row alert with a text field (218 in 196).
  static const double headerTop = 22;

  /// The horizontal space between an alert's edge and its text.
  static const double textInset = 30;

  /// The space between the title and the message labels.
  ///
  /// UIKit's view dumps (see [headerTop]): the message `UILabel` starts at
  /// 340.67 under a title label of 20.33 points ending at 333.33 (22
  /// pixels at 3x; 245.67 under 238.33 in the row alert). The labels are
  /// as tall as UIKit makes them (`MorphLabelHeight`).
  static const double titleGap = 22 / 3;

  /// The space below the header text when both a title and a message
  /// show.
  ///
  /// UIKit's view dumps (see [headerTop]): the header scroll view ends at
  /// 363 under a message label ending at 358.67 (13 pixels at 3x), so a
  /// title and a one-line message make a 72 point header, as the
  /// recorded platters (264 points with three actions) and the action
  /// sheet popover's header (floored to 72 in the device tree of scene
  /// w2alert) hold.
  static const double headerBottom = 13 / 3;

  /// The space below the header text when only one line of text shows.
  ///
  /// Carried from the first port (11 pixels at 3x): no committed capture
  /// holds an alert with a title or a message alone, so the 46 point
  /// header it gives under a 20.33 point label is not replayed.
  static const double singleHeaderBottom = 11 / 3;

  /// The space around the stack of buttons.
  static const double buttonInset = 16;

  /// The height of a button.
  static const double buttonHeight = 48;

  /// The space between two buttons.
  static const double buttonGap = 8;

  /// The space between the header and a text field.
  ///
  /// UIKit's view dumps (see [headerTop]): the row alert's text field
  /// cell starts at 280 under a message label ending at 263.67 (49 pixels
  /// at 3x).
  static const double fieldTop = 49 / 3;

  /// The horizontal space between an alert's edge and a text field.
  static const double fieldInset = 15;

  /// The space between two text fields.
  ///
  /// Carried from the first port as [buttonGap]: no committed capture
  /// holds an alert with more than one text field, so the gap is not
  /// replayed.
  static const double fieldGap = 8;

  /// The space below the last text field, above the buttons' own
  /// [buttonInset].
  ///
  /// UIKit's view dumps (see [headerTop]): the row alert's text field
  /// collection view runs from 280 to 332 around a 48 point cell ending
  /// at 328, and the actions view starting at 332 holds its first button
  /// at 348, so the buttons rest 20 points under the field in a 216 point
  /// platter. Only one text field was captured; with several, the space
  /// is assumed to follow the last one.
  static const double fieldBottom = 4;

  /// The opacity of a pressed button's fill, relative to its normal fill.
  static const double pressedFillOpacity = 0.4;

  /// The width of an action sheet's content when it presents as a popover
  /// from its source.
  static const double popoverWidth = 240;
}

/// The motion of an iOS 27 alert: the dimming, the alert's opacity and its
/// scale.
///
/// Presenting, the alert fades in with the dimming while it shrinks from
/// [AlertTuning.presentScale] to its size; dismissing, it fades out
/// with the dimming at its size. Both run on [AlertTuning.spring],
/// and a dismissal in the middle of the presentation reverses from where
/// the alert stands, velocity included.
///
/// For Reduce Motion ([reducedMotion]) the alert does not shrink: it
/// fades in at its size on the same spring. Read from UIKit, notes
/// private: UIAlertController starts the presentation at scale 1 instead
/// of 1.2 under Reduce Motion and keeps the timing.
///
/// Times are seconds on the caller's clock.
@internal
class AlertMotion {
  /// Creates the motion of an alert that is not shown yet.
  AlertMotion({
    this.spring = AlertTuning.spring,
    this.presentScale = AlertTuning.presentScale,
  }) : _progress = MotionValue<double>(0, spring: spring),
       _scale = MotionValue<double>(presentScale, spring: spring);

  /// The spring of the progress and the scale.
  final Spring spring;

  /// The scale the alert presents from.
  final double presentScale;

  final MotionValue<double> _progress;
  final MotionValue<double> _scale;
  double _now = 0;
  bool _dismissing = false;

  /// Whether the alert presents for Reduce Motion, at its size.
  bool reducedMotion = false;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether the alert is on its way out.
  bool get isDismissing => _dismissing;

  /// Whether the alert has left and nothing moves any more.
  bool get isDismissed =>
      _dismissing && _progress.isWithin(_now, GlassRest.opacity);

  /// Whether nothing moves visibly any more: the fade and the dimming
  /// swing less than [GlassRest.opacity] and the scale less than
  /// [GlassRest.scale] of the alert's width ([settle] lands them).
  bool get isSettled =>
      _progress.isWithin(_now, GlassRest.opacity) &&
      _scale.isWithin(_now, GlassRest.scale(AlertTuning.width));

  /// Lands every spring on its target at the motion's time: at a visible
  /// rest ([isSettled]) nothing that shows moves (NEAR, invisible).
  void settle() {
    _progress.settle(_now);
    _scale.settle(_now);
  }

  /// Starts presenting the alert at time [t].
  void present(double t) {
    advance(t);
    _dismissing = false;
    if (_progress.valueAt(t) <= 0 && _progress.velocityAt(t) == 0) {
      _scale.snap(t, presentScale);
    }
    _progress.retarget(t, 1);
    _scale.retarget(t, 1);
  }

  /// Starts dismissing the alert at time [t].
  void dismiss(double t) {
    advance(t);
    _dismissing = true;
    _progress.retarget(t, 0);
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t > _now) _now = t;
  }

  /// The presentation progress: 0 hidden, 1 shown.
  double get progress => _progress.valueAt(_now);

  /// The opacity of the alert.
  double get opacity => progress.clamp(0.0, 1.0);

  /// The opacity of the dimming, as a fraction of
  /// [AlertTuning.dimmingOpacity].
  double get dimming => progress.clamp(0.0, 1.0);

  /// The scale of the alert.
  double get scale => reducedMotion ? 1 : _scale.valueAt(_now);
}
