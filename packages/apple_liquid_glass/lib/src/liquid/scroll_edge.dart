import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/underlay_layers.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:meta/meta.dart';

/// The device-pixel sigma Impeller blurs with for [sigma] logical pixels
/// at [devicePixelRatio]: its sigma correction, then the canvas scale.
double _impellerSigma(double sigma, double devicePixelRatio) {
  final clamped = math.min(sigma, 500);
  return clamped *
      (1 - 3.4e-3 * clamped + 3.4e-6 * clamped * clamped) *
      devicePixelRatio;
}

/// The logical pixels around a region that Impeller's blur of [sigma]
/// logical pixels reads at [devicePixelRatio]: its kernel reaches 1.732 of
/// its device sigma, plus the texels its downsample and upsample add,
/// rounded up to whole device pixels.
double _blurReach(double sigma, double devicePixelRatio) {
  final scaled = _impellerSigma(sigma, devicePixelRatio);
  final scale = scaled <= 4
      ? 1.0
      : math
            .pow(
              2.0,
              math.max(-4.0, (math.log(4 / scaled) / math.ln2).roundToDouble()),
            )
            .toDouble();
  return (1.7320508 * scaled + 2 / scale + 2).ceilToDouble() / devicePixelRatio;
}

/// [sigma] raised to the smallest sigma Impeller blurs at half resolution
/// at [devicePixelRatio] (a device sigma of 4 sqrt 2), when that is at most
/// 1.12 times larger; else [sigma] itself. Just below that threshold
/// Impeller blurs every device pixel at about three times the cost on a
/// Mali GPU, where it blurs the band (a live read or a filtered copy).
/// NEAR: the band blurs up to 12 % wider than measured.
double _halfResolutionSigma(double sigma, double devicePixelRatio) {
  const threshold = 4 * math.sqrt2;
  if (sigma <= 0 || devicePixelRatio <= 0) return sigma;
  if (_impellerSigma(sigma, devicePixelRatio) >= threshold) return sigma;
  final target = threshold * 1.001 / devicePixelRatio;
  var raised = target;
  for (var i = 0; i < 4; i++) {
    raised = target / (1 - 3.4e-3 * raised + 3.4e-6 * raised * raised);
  }
  return raised <= sigma * 1.12 ? raised : sigma;
}

/// A scroll edge effect as [details] describe it, whose band blurs the
/// content under it before the content dissolves toward the background.
@internal
class ScrollEdge extends StatelessWidget {
  /// Creates the effect.
  const ScrollEdge({required this.details, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  @override
  Widget build(BuildContext context) => ScrollEdgeBand(
    details: details,
    paint: _EdgePaint(
      details: details,
      brightness: GlassTraits.of(context).brightness,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
    ),
  );
}

class _EdgePaint extends LeafRenderObjectWidget {
  const _EdgePaint({
    required this.details,
    required this.brightness,
    required this.devicePixelRatio,
  });

  final GlassScrollEdgeDetails details;
  final Brightness brightness;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    teachLiquidUnderlay();
    return _RenderEdge(
      details: details,
      brightness: brightness,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderEdge renderObject) {
    renderObject.details = details;
    renderObject.brightness = brightness;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

/// The blur of the band under the flat effect's fade and hairline: the
/// presence fades the blurred backdrop through its alpha, as an opacity
/// layer above a blur would read an empty backdrop. The blur reads a copy
/// of the backdrop only as far around the band as its kernel reaches.
class _RenderEdge extends RenderScrollEdge {
  _RenderEdge({
    required super.details,
    required super.brightness,
    required super.devicePixelRatio,
  });

  final _blur = LayerHandle<LiquidGlassBackdropFilterLayer>();

  @override
  bool updateBand(double presence) {
    final blur = _blur.layer;
    if (blur == null) return false;
    blur.frost = _frost(presence);
    blur.bandPaint = _bandPaint(presence, blur.clip);
    return true;
  }

  @override
  void dropBand() => _blur.layer = null;

  double get _sigma => _halfResolutionSigma(blurSigma, devicePixelRatio);

  // Presence rides in the matrix's alpha row: a fade changes only the
  // frost's matrix, which keeps the copy, and a filtered copy takes one
  // color pass instead of two.
  LiquidGlassBackdropFrost _frost(double presence) => LiquidGlassBackdropFrost(
    sigma: _sigma,
    colorMatrix: details.hard
        ? hardMatrix(presence)
        : presence == 1
        ? null
        : <double>[
            1, 0, 0, 0, 0, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 0, //
            0, 0, 0, presence, 0,
          ],
  );

  @override
  void paintBand(
    PaintingContext context,
    Offset offset,
    double presence,
    PaintingContextCallback fade,
  ) {
    final box = offset & size;
    final frost = _frost(presence);
    final reach = _blurReach(_sigma, devicePixelRatio);
    final blur = _blur.layer ??= LiquidGlassBackdropFilterLayer.frosted(
      frost: frost,
      clip: box,
      reach: reach,
      devicePixelRatio: devicePixelRatio,
    );
    blur.frost = frost;
    blur.bandPaint = _bandPaint(presence, box);
    blur.clip = box;
    blur.reach = reach;
    blur.devicePixelRatio = devicePixelRatio;
    context.pushLayer(blur, fade, offset);
  }

  FrostBandPaint _bandPaint(double presence, Rect box) {
    final top = details.edge == AxisDirection.up;
    final hairline = 1 / devicePixelRatio;
    return FrostBandPaint(
      fade: fadeColor,
      whole: details.hard
          ? -1e5 + 1
          : top
          ? box.top + box.height * softFadeStart
          : box.bottom - box.height * softFadeStart,
      gone: details.hard
          ? -1e5
          : top
          ? box.bottom
          : box.top,
      lineStart: !details.hard
          ? 0
          : top
          ? box.bottom - hairline
          : box.top,
      lineEnd: !details.hard
          ? 0
          : top
          ? box.bottom
          : box.top + hairline,
      lineGray: brightness == Brightness.dark ? 1 : 0,
      presence: presence,
      saturation: saturation,
      brightness: brightnessShift,
    );
  }
}
