import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

/// A curve over the Liquid Glass slider position.
///
/// The endpoints sit at Clear (`0`) and Tinted (`1`). A curve of two values
/// is the line between them; one [GlassColorCurve.through] more values bends
/// at each of them.
@internal
@immutable
class GlassColorCurve {
  /// The line through [clear] and [tinted].
  const GlassColorCurve(this.clear, this.tinted) : _values = null;

  /// A curve that holds [value] at every slider position.
  const GlassColorCurve.constant(double value)
    : clear = value,
      tinted = value,
      _values = null;

  /// A curve through [values], spaced evenly over the slider from Clear to
  /// Tinted and linear between neighbours.
  GlassColorCurve.through(List<double> values)
    : assert(values.length >= 2, 'A curve has both of its ends.'),
      clear = values.first,
      tinted = values.last,
      _values = List.unmodifiable(values);

  /// A curve through [value] at every slider position iOS stops at, which
  /// are the multiples of 0.05.
  factory GlassColorCurve.sampled(
    double Function(double sliderPosition) value,
  ) => GlassColorCurve.through([for (var i = 0; i <= 20; i++) value(i / 20)]);

  /// Value at the Clear slider position (`0`).
  final double clear;

  /// Value at the Tinted slider position (`1`).
  final double tinted;

  final List<double>? _values;

  /// The value at [sliderPosition].
  double evaluate(double sliderPosition) {
    final amount = sliderPosition.clamp(0.0, 1.0);
    final values = _values;
    if (values == null) return clear + (tinted - clear) * amount;
    final at = amount * (values.length - 1);
    final below = math.min(at.floor(), values.length - 2);
    return values[below] + (values[below + 1] - values[below]) * (at - below);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassColorCurve &&
          other.clear == clear &&
          other.tinted == tinted &&
          listEquals(other._values, _values);

  @override
  int get hashCode => Object.hash(
    clear,
    tinted,
    _values == null ? null : Object.hashAll(_values),
  );

  @override
  String toString() =>
      'GlassColorCurve(${(_values ?? [clear, tinted]).join(', ')})';
}

/// The veil iOS 27 lays over the face of glass larger than a control: the
/// face is pulled toward a wash of what lies behind it.
///
/// With `Y` the luminance of the backdrop, the wash is `black + (white -
/// black) * Y + saturation * (backdrop - Y)`. The face mixes toward it by
/// `opacity * w^4`, where `w` is the luminance of the face when the bleed
/// is [onBright] and one minus it otherwise: light glass veils its bright
/// parts with a near-white wash, dark glass its dark parts with a dim one.
///
/// Approximation: iOS washes with a blur of the backdrop as wide as a third
/// of the glass, the renderer with the backdrop the face itself shows. Over
/// a plain backdrop the two are the same.
@internal
@immutable
class GlassColorBleed {
  /// A bleed of [opacity] toward a wash from [black] to [white].
  const GlassColorBleed({
    required this.opacity,
    required this.black,
    required this.white,
    this.saturation = 1,
    this.onBright = false,
  });

  /// No bleed.
  const GlassColorBleed.none()
    : opacity = 0,
      black = 0,
      white = 1,
      saturation = 1,
      onBright = false;

  /// How far the face goes toward the wash where the bleed is strongest.
  final double opacity;

  /// The wash over a black backdrop.
  final double black;

  /// The wash over a white backdrop.
  final double white;

  /// The gain of the backdrop's chroma in the wash.
  final double saturation;

  /// Whether the bleed takes the bright parts of the face, not the dark
  /// ones.
  final bool onBright;

  /// How far a face of luminance [face] goes toward the wash.
  double weightAt(double face) {
    final weight = (onBright ? face : 1 - face).clamp(0.0, 1.0);
    return opacity * weight * weight * weight * weight;
  }

  /// A grey face of luminance [face] over a grey backdrop of luminance
  /// [backdrop], after the bleed.
  double apply(double face, double backdrop) =>
      face + (black + (white - black) * backdrop - face) * weightAt(face);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassColorBleed &&
          other.opacity == opacity &&
          other.black == black &&
          other.white == white &&
          other.saturation == saturation &&
          other.onBright == onBright;

  @override
  int get hashCode => Object.hash(opacity, black, white, saturation, onBright);

  @override
  String toString() =>
      'GlassColorBleed($opacity, $black, $white, $saturation, $onBright)';
}

/// One boundary of the tint-tone ramp, `base + amplitude *
/// (min(1, luminance / pivot))^exponent`.
///
/// `pivot` normalizes luminance into the ramp; setting it to `1` (with
/// luminance already clamped to `0..1`) leaves the power curve unclamped.
@internal
@immutable
class GlassToneRamp {
  /// A luminance response `base + amplitude * (min(1, Y / pivot))^exponent`.
  const GlassToneRamp({
    required this.base,
    required this.amplitude,
    required this.pivot,
    required this.exponent,
  });

  /// A ramp that holds [base] at every luminance.
  const GlassToneRamp.constant(double base)
    : this(base: base, amplitude: 0, pivot: 1, exponent: 1);

  /// Ramp value at zero luminance (and the offset everywhere when
  /// [amplitude] is zero).
  final double base;

  /// Scale of the luminance-dependent part.
  final double amplitude;

  /// Luminance at which the ramp saturates; must be positive.
  final double pivot;

  /// Curvature of the response.
  final double exponent;

  /// Evaluates the ramp at [luminance] (unclamped input is clamped here).
  double evaluate(double luminance) {
    final y = luminance.clamp(0.0, 1.0);
    return base +
        amplitude * math.pow(math.min(1.0, y / pivot), exponent).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassToneRamp &&
          other.base == base &&
          other.amplitude == amplitude &&
          other.pivot == pivot &&
          other.exponent == exponent;

  @override
  int get hashCode => Object.hash(base, amplitude, pivot, exponent);

  @override
  String toString() => 'GlassToneRamp($base, $amplitude, $pivot, $exponent)';
}

/// Every numeric constant of the adaptive (backdrop-conditioned) color
/// model, driven from Dart and consumed by the final render shader as a
/// uniform block.
///
/// The untinted face of a shape is
/// `emission + transmittance * lum(Y) + chromaGain * keep(k) *
/// (backdrop - Y)` with `lum(Y) = Y + lift * Y * (1 - Y)`,
/// `k = 1 - Y * lift / (1 + lift)` and `keep(k) = k * (1 + 0.3 * (1 - k))`; `emission` is premultiplied. This is
/// the face of iOS 27 in other terms: the lift is its cap on luminance, and
/// the chroma falls with that cap as iOS's does. [bleed] then veils the
/// face. A tint then covers the face by its opacity with a tone picked by
/// the luminance `F` of the face: each tint channel `c` becomes
/// `clamp(lo + (hi - lo) * c^gamma)` where `lo`/`hi` are [GlassToneRamp]s of
/// `F` and `gamma = 1 + toneGammaLuminance * (1 - F)`.
///
/// The iOS 27 parameter sets ship as [GlassColorParameters.ios27Regular],
/// which follows the size of the glass, and [GlassColorParameters.ios27Clear];
/// subclasses are not needed for custom materials; compose parameters
/// instead.
@internal
@immutable
class GlassColorParameters {
  /// Creates a fully specified adaptive color parameter set.
  const GlassColorParameters({
    required this.emissionColor,
    required this.emissionAlpha,
    required this.transmittance,
    required this.luminanceLift,
    required this.chromaGain,
    this.bleed = const GlassColorBleed.none(),
    this.toneLow = const GlassToneRamp.constant(0),
    this.toneHigh = const GlassToneRamp.constant(1),
    this.toneGammaLuminance = 0,
    this.glintLuminance = _defaultGlintLuminance,
    this.glintFaceGain = _defaultGlintFaceGain,
    this.glintVibrancy = _defaultGlintVibrancy,
    this.contourResponse = 0,
    this.fakeGlintLuminance = _defaultGlintLuminance,
  });

  /// The iOS 27 regular material in [brightness] as glass whose shorter
  /// side is [shortSide] points wears it.
  ///
  /// iOS gives glass a material by its size. Up to 64 points on the shorter
  /// side it is a control's: light glass lifts black to 40 %, dark glass to
  /// 12.5 % and keeps 60 % of the backdrop's luminance. From 160 points it
  /// is a panel's: a veil ([bleed]) pulls the bright parts of light glass
  /// toward white and the dark parts of dark glass toward a dim grey, and
  /// dark glass keeps 45 % of the luminance. Between the two every part
  /// grows linearly; dark glass reaches its cap on luminance at 104 points.
  /// Along the Liquid Glass slider a fill covers more of the face: white on
  /// light glass, grey on dark glass.
  ///
  /// A tint runs from a darker tone of itself over a black face to itself
  /// over a white one on light glass, and between two tones close to itself
  /// on dark glass. iOS tints with a grey by another law than with a color:
  /// [greyTint] gives the parameters of glass tinted with a grey.
  ///
  /// The numbers are the inputs UIKit gives its glass on iOS 27, and the
  /// face they give agrees with captures of native glass over plain colors
  /// within a level out of 255. Approximation: the tones of a color are
  /// exact for fully saturated colors and up to 0.12 off the darker tone of
  /// a pale one.
  ///
  /// Without [shortSide] it is the material of a panel.
  factory GlassColorParameters.ios27Regular({
    required Brightness brightness,
    double shortSide = double.infinity,
    bool greyTint = false,
  }) {
    final dark = brightness == Brightness.dark;
    final (:control, :panel) = ios27SizeRamp;
    final parameters = shortSide <= control
        ? (dark ? _ios27DarkControl : _ios27LightControl)
        : shortSide >= panel
        ? (dark ? _ios27DarkPanel : _ios27LightPanel)
        : _ios27Regular(dark, shortSide);
    return greyTint ? parameters.greyTinted : parameters;
  }

  /// Unpremultiplied emission color of the face wash.
  final Color emissionColor;

  /// Premultiplied emission strength over the slider.
  final GlassColorCurve emissionAlpha;

  /// Transmittance of transmitted content over the slider.
  final GlassColorCurve transmittance;

  /// S-curve lift applied to transmitted luminance.
  final GlassColorCurve luminanceLift;

  /// Gain applied to the transmitted chroma.
  final GlassColorCurve chromaGain;

  /// The veil over the face of glass larger than a control.
  final GlassColorBleed bleed;

  /// Luminance ramp of the tint tone's lower bound.
  final GlassToneRamp toneLow;

  /// Luminance ramp of the tint tone's upper bound.
  final GlassToneRamp toneHigh;

  /// Change of the tint-channel exponent `1 + toneGammaLuminance * (1 - F)`
  /// with the luminance `F` of the face.
  final double toneGammaLuminance;

  /// Luminance of the glint's bright target (real glass: HDR-capable).
  final double glintLuminance;

  /// How much of the lit face is added to the glint target. Clear glass
  /// brightens its own face instead of pulling toward fixed white.
  final double glintFaceGain;

  /// How much the glint amplifies face chroma.
  final double glintVibrancy;

  /// How strongly the slider's added opacity strengthens the dark contour.
  /// `1 + contourResponse * (T(0) - T(sliderPosition))` scales the contour
  /// alpha.
  final double contourResponse;

  /// Luminance of the glint target FakeGlass composites, which cannot see
  /// the face.
  final double fakeGlintLuminance;

  static const double _defaultGlintLuminance = GlassGlint.directLuminance;
  static const double _defaultGlintFaceGain = 0;
  static const double _defaultGlintVibrancy = GlassGlint.directVibrancy;

  // The shorter side, in points, from which dark glass keeps its least
  // fraction of the backdrop's luminance.
  static const double _ios27DarkCapSide = 104;

  static GlassColorParameters _ios27Regular(bool dark, double shortSide) {
    final grown = ios27PanelProgress(shortSide);
    final control = ios27SizeRamp.control;
    final black = dark ? 0.125 : 0.4;
    final white = dark ? 1.125 : 1.03;
    final saturation = dark ? 1.3 : 1.2;
    // The fill over the face: its grey and how much of the face it covers.
    double fillGrey(double amount) => dark ? 0.125 * (1 - 2 * amount).abs() : 1;
    double fill(double amount) {
      final (:upTo, :past) = splitAtMiddleTick(amount);
      return dark ? past : 0.4 * upTo + 0.6 * past;
    }

    double whiteKeeps(double amount) => dark
        ? 0.6 +
              (0.45 - 0.2 * splitAtMiddleTick(amount).upTo - 0.6) *
                  ((shortSide - control) / (_ios27DarkCapSide - control)).clamp(
                    0.0,
                    1.0,
                  )
        : ios27LightLuminanceCap;
    final base = dark ? _ios27DarkTones : _ios27LightTones;
    return base.copyWith(
      emissionAlpha: GlassColorCurve.sampled(
        (a) => black * (1 - fill(a)) + fillGrey(a) * fill(a),
      ),
      transmittance: GlassColorCurve.sampled(
        (a) => (white - black) * (1 - fill(a)) * whiteKeeps(a),
      ),
      luminanceLift: GlassColorCurve.sampled(
        (a) => (1 - whiteKeeps(a)) / whiteKeeps(a),
      ),
      chromaGain: GlassColorCurve.sampled((a) => saturation * (1 - fill(a))),
      bleed: dark
          ? GlassColorBleed(opacity: 0.8 * grown, black: 0.125, white: 0.5)
          : GlassColorBleed(
              opacity: 0.5 * grown,
              black: 0.9,
              white: 1,
              saturation: 1.2,
              onBright: true,
            ),
    );
  }

  /// The fraction of a white backdrop's luminance light glass keeps before its
  /// own white point brightens it.
  ///
  /// iOS takes 1 on a display with headroom over white, which an iPhone
  /// has, and 0.94 on one without, such as the simulator's: there the
  /// brightest greys under light glass come out up to five levels darker.
  static const double ios27LightLuminanceCap = 1;

  // What the size and the slider do not set: the face's white emission and
  // the tones of a tint.
  static const _ios27LightTones = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(0),
    transmittance: GlassColorCurve.constant(1),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1),
    toneLow: _lightToneLow,
    toneHigh: _lightToneHigh,
  );

  // A channel c of a tint on light glass is 0.6706 c - 0.0706 over a black
  // face and c over a white one.
  static const _lightToneLow = GlassToneRamp(
    base: -.0706,
    amplitude: .0706,
    pivot: 1,
    exponent: 1,
  );
  static const _lightToneHigh = GlassToneRamp(
    base: .6,
    amplitude: .4,
    pivot: 1,
    exponent: 1,
  );

  // On dark glass it is 1.0362 c - 0.0306 over a black face and
  // 0.7946 c + 0.1735 over a white one.
  static const _ios27DarkTones = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(0),
    transmittance: GlassColorCurve.constant(1),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1),
    toneLow: GlassToneRamp(
      base: -.0306,
      amplitude: .2041,
      pivot: 1,
      exponent: 1,
    ),
    toneHigh: GlassToneRamp(
      base: 1.0056,
      amplitude: -.0375,
      pivot: 1,
      exponent: 1,
    ),
    contourResponse: .95,
  );

  /// These parameters under a grey tint: a grey g of a tint is
  /// 1.1875 g - 0.25 over a black face and 0.3125 more over a white one, in
  /// both appearances and on clear glass.
  GlassColorParameters get greyTinted => copyWith(
    toneLow: const GlassToneRamp(
      base: -.25,
      amplitude: .3125,
      pivot: 1,
      exponent: 1,
    ),
    toneHigh: const GlassToneRamp(
      base: .9375,
      amplitude: .3125,
      pivot: 1,
      exponent: 1,
    ),
    toneGammaLuminance: 0,
  );

  static final _ios27LightControl = _ios27Regular(
    false,
    ios27SizeRamp.control,
  );
  static final _ios27DarkControl = _ios27Regular(true, ios27SizeRamp.control);

  static final _ios27LightPanel = _ios27Regular(false, ios27SizeRamp.panel);
  static final _ios27DarkPanel = _ios27Regular(true, ios27SizeRamp.panel);

  /// The fitted iOS 27 `Glass.clear`, identical in light and dark.
  ///
  /// Clear glass lifts black to 12.5 %, takes white to 108 % and passes
  /// chroma through at 1.06, at every size and slider position: the inputs
  /// UIKit gives it on iOS 27. It takes the tint tones of light glass in
  /// both appearances, and its glint brightens its own face rather than
  /// pulling toward a fixed bright target.
  static const ios27Clear = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(.125),
    transmittance: GlassColorCurve.constant(.955),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1.06),
    toneLow: _lightToneLow,
    toneHigh: _lightToneHigh,
    glintLuminance: 2.34,
    glintFaceGain: 3.58,
    glintVibrancy: .78,
    fakeGlintLuminance: 3.26,
  );

  /// A copy with the given fields replaced.
  GlassColorParameters copyWith({
    Color? emissionColor,
    GlassColorCurve? emissionAlpha,
    GlassColorCurve? transmittance,
    GlassColorCurve? luminanceLift,
    GlassColorCurve? chromaGain,
    GlassColorBleed? bleed,
    GlassToneRamp? toneLow,
    GlassToneRamp? toneHigh,
    double? toneGammaLuminance,
    double? glintLuminance,
    double? glintFaceGain,
    double? glintVibrancy,
    double? contourResponse,
    double? fakeGlintLuminance,
  }) => GlassColorParameters(
    emissionColor: emissionColor ?? this.emissionColor,
    emissionAlpha: emissionAlpha ?? this.emissionAlpha,
    transmittance: transmittance ?? this.transmittance,
    luminanceLift: luminanceLift ?? this.luminanceLift,
    chromaGain: chromaGain ?? this.chromaGain,
    bleed: bleed ?? this.bleed,
    toneLow: toneLow ?? this.toneLow,
    toneHigh: toneHigh ?? this.toneHigh,
    toneGammaLuminance: toneGammaLuminance ?? this.toneGammaLuminance,
    glintLuminance: glintLuminance ?? this.glintLuminance,
    glintFaceGain: glintFaceGain ?? this.glintFaceGain,
    glintVibrancy: glintVibrancy ?? this.glintVibrancy,
    contourResponse: contourResponse ?? this.contourResponse,
    fakeGlintLuminance: fakeGlintLuminance ?? this.fakeGlintLuminance,
  );

  /// The untinted face under [bleed], as the class describes it, at
  /// [sliderPosition]; `emission` is premultiplied.
  ({Color emission, double transmittance, double lift, double chromaGain})
  faceTransfer({double sliderPosition = 0}) {
    final alpha = emissionAlpha.evaluate(sliderPosition);
    return (
      emission: Color.from(
        alpha: 1,
        red: emissionColor.r * alpha,
        green: emissionColor.g * alpha,
        blue: emissionColor.b * alpha,
      ),
      transmittance: transmittance.evaluate(sliderPosition),
      lift: luminanceLift.evaluate(sliderPosition),
      chromaGain: chromaGain.evaluate(sliderPosition),
    );
  }

  /// Factor applied to the border strength at slider [sliderPosition].
  double contourScale(double sliderPosition) =>
      1 +
      contourResponse *
          (transmittance.evaluate(0) - transmittance.evaluate(sliderPosition));

  /// Maps one opaque tint channel triple to the tone selected for a face of
  /// [luminance].
  Color tintTone(Color tint, double luminance) {
    final lo = toneLow.evaluate(luminance);
    final hi = toneHigh.evaluate(luminance);
    final gamma = 1 + toneGammaLuminance * (1 - luminance);
    double channel(double c) =>
        (lo + (hi - lo) * math.pow(math.max(c, 0.0), gamma)).clamp(0.0, 1.0);
    return Color.from(
      alpha: 1,
      red: channel(tint.r),
      green: channel(tint.g),
      blue: channel(tint.b),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassColorParameters &&
          other.emissionColor == emissionColor &&
          other.emissionAlpha == emissionAlpha &&
          other.transmittance == transmittance &&
          other.luminanceLift == luminanceLift &&
          other.chromaGain == chromaGain &&
          other.bleed == bleed &&
          other.toneLow == toneLow &&
          other.toneHigh == toneHigh &&
          other.toneGammaLuminance == toneGammaLuminance &&
          other.glintLuminance == glintLuminance &&
          other.glintFaceGain == glintFaceGain &&
          other.glintVibrancy == glintVibrancy &&
          other.contourResponse == contourResponse &&
          other.fakeGlintLuminance == fakeGlintLuminance;

  @override
  int get hashCode => Object.hash(
    emissionColor,
    emissionAlpha,
    transmittance,
    luminanceLift,
    chromaGain,
    bleed,
    toneLow,
    toneHigh,
    toneGammaLuminance,
    glintLuminance,
    glintFaceGain,
    glintVibrancy,
    contourResponse,
    fakeGlintLuminance,
  );

  @override
  String toString() =>
      'GlassColorParameters($emissionColor, $emissionAlpha, $transmittance, '
      '$luminanceLift, $chromaGain, $bleed, $toneLow, $toneHigh, '
      '$toneGammaLuminance, $glintLuminance, $glintFaceGain, $glintVibrancy, '
      '$contourResponse, $fakeGlintLuminance)';
}
