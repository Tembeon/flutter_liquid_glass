import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The shorter sides, in points, where iOS 27 tells a control's glass from a
/// panel's: glass up to `control` wears a control's material, haze and
/// shadow, glass from `panel` a panel's, and between the two each part grows
/// linearly ([ios27PanelProgress]), but for two laws with ramps of their
/// own, [ios27DarkFaceRamp] and [ios27RimSpreadRamp].
@internal
const ios27SizeRamp = (control: 64.0, panel: 160.0);

/// How far glass whose shorter side is [shortSide] points has grown from a
/// control's toward a panel's ([ios27SizeRamp]): 0 up to a control, 1 from a
/// panel.
@internal
double ios27PanelProgress(double shortSide) {
  final (:control, :panel) = ios27SizeRamp;
  return ios27RampProgress((from: control, to: panel), shortSide);
}

/// The shorter sides, in points, over which dark regular glass lowers the
/// brightest luma its face lets through toward a panel's.
@internal
const ios27DarkFaceRamp = (from: 64.0, to: 104.0);

/// The shorter sides, in points, over which the rim highlight's spread
/// widens from 80 to 90 degrees: the one law of the size that still grows
/// past a panel's side.
@internal
const ios27RimSpreadRamp = (from: 96.0, to: 192.0);

/// How far glass whose shorter side is [shortSide] points has gone along
/// [ramp]: 0 up to its start, 1 from its end.
@internal
double ios27RampProgress(
  ({double from, double to}) ramp,
  double shortSide,
) => ((shortSide - ramp.from) / (ramp.to - ramp.from)).clamp(0.0, 1.0);

/// The Settings Liquid Glass slider's middle tick: iOS 27 glass follows the
/// slider at one rate up to it and at another past it
/// ([splitAtMiddleTick]).
@internal
const double sliderMiddleTick = 0.5;

/// How far the slider position [amount] runs up to [sliderMiddleTick], and
/// how far past it.
@internal
({double upTo, double past}) splitAtMiddleTick(double amount) => (
  upTo: math.min(amount, sliderMiddleTick),
  past: math.max(amount - sliderMiddleTick, 0),
);

/// The sigma, in logical pixels, a unit of iOS 27's blur radius comes to over
/// its pyramid of smaller copies.
@internal
const double ios27BlurUnit = 1.94;
