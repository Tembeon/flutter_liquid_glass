import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/underlay_layers.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/widgets.dart';
import 'package:meta/meta.dart';

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
      devicePixelRatio: glassDevicePixelRatioOf(context),
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
class _RenderEdge extends RenderScrollEdge with LiquidGlassBackdropFilterHost {
  _RenderEdge({
    required super.details,
    required super.brightness,
    required super.devicePixelRatio,
  });

  final _blur = LayerHandle<LiquidGlassBackdropFilterLayer>();

  @override
  Layer? get composedLayer => _blur.layer;

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

  double get _sigma =>
      ImpellerBlur.halfResolution(bandTuning.blurSigma, devicePixelRatio);

  // Presence rides in the matrix's alpha row: a fade changes only the
  // frost's matrix, which keeps the copy, and a filtered copy takes one
  // color pass instead of two.
  LiquidGlassBackdropFrost _frost(double presence) => LiquidGlassBackdropFrost(
    sigma: _sigma,
    colorMatrix: details.hard
        ? bandTuning.hardMatrix(presence)
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
    final reach = ImpellerBlur.reach(_sigma, devicePixelRatio);
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
      fade: bandTuning.fadeColor,
      whole: details.hard
          ? -1e5 + 1
          : top
          ? box.top + box.height * bandTuning.softFadeStart
          : box.bottom - box.height * bandTuning.softFadeStart,
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
      saturation: bandTuning.saturation,
      brightness: bandTuning.brightnessShift,
    );
  }
}
