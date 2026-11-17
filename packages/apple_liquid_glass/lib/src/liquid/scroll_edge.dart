import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/underlay_layers.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
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
  Widget build(BuildContext context) {
    final traits = GlassTraits.of(context);
    return ScrollEdgeBand(
      details: details,
      paint: _EdgePaint(
        details: details,
        brightness: traits.brightness,
        devicePixelRatio: traits.viewPixelRatio,
      ),
    );
  }
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
    blur.bandPaint = _bandPaint(presence, blur.clip);
    return true;
  }

  @override
  void dropBand() => _blur.layer = null;

  @override
  void paintBand(
    PaintingContext context,
    Offset offset,
    double presence,
    PaintingContextCallback fade,
  ) {
    final box = offset & size;
    final sigma = bandTuning.blurSigma;
    final paint = _bandPaint(presence, box);
    final blur = _blur.layer ??= LiquidGlassBackdropFilterLayer.band(
      sigma: sigma,
      paint: paint,
      clip: box,
    );
    blur
      ..sigma = sigma
      ..bandPaint = paint
      ..clip = box;
    context.pushLayer(blur, fade, offset);
  }

  // Presence rides in the frost's alpha: a fade changes only the frost's
  // matrix, which keeps the copy, and a filtered copy takes one color pass
  // instead of two.
  FrostBandPaint _bandPaint(double presence, Rect box) {
    final tuning = bandTuning;
    if (details.hard) {
      return FrostBandPaint.hard(
        edge: details.edge,
        fade: tuning.fadeColor,
        line: tuning.hairline,
        presence: presence,
        saturation: tuning.saturation,
        brightness: tuning.brightnessShift,
      );
    }
    final top = details.edge == AxisDirection.up;
    final start = box.height * tuning.softFadeStart;
    return FrostBandPaint.soft(
      fade: tuning.fadeColor,
      whole: top ? box.top + start : box.bottom - start,
      gone: top ? box.bottom : box.top,
      presence: presence,
    );
  }
}
