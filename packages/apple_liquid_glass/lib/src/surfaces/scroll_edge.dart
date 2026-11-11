import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The numbers of UIKit's scroll edge effect on iOS 27: `PocketSettings`
/// and the layers of `UIKit.ScrollEdgeEffectView` (read from UIKit, notes
/// private; the hard band replayed against an iPhone 16 Pro capture that
/// is not among this package's fixtures). Radii are taken as Gaussian
/// sigmas.
@internal
abstract final class ScrollEdgeTuning {
  /// How far the soft band reaches past the bar.
  static const double softOverhang = 40;

  /// Where along the soft band, from the screen's edge, the fade starts to
  /// dissolve.
  static const double softFadeStart = 0.3407;

  /// The blur of the soft band.
  static const double softBlur = 1.5;

  /// The blur of the hard band, a navigation bar's.
  static const double hardBlur = 2;

  /// The saturation of the content under the hard band.
  static const double hardSaturation = 1.25;

  /// The brightness added under the hard band, as a share of full
  /// intensity.
  static const double hardBrightness = 0.03;

  /// How far the content fades toward the background: UIKit's replay
  /// alpha, 0.5 in light and 0.6 in dark.
  static double fade(Brightness brightness) =>
      brightness == Brightness.dark ? 0.6 : 0.5;

  /// The hairline of the hard band: black or white at 10 percent.
  static Color hairline(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0x1AFFFFFF)
      : const Color(0x1A000000);

  /// UIKit's saturation matrix (Rec. 709 luminance) plus the brightness
  /// offset, with [presence] as the alpha.
  static List<double> hardMatrix(double presence) {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    const s = hardSaturation;
    const o = hardBrightness * 255;
    return [
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, o, //
      0, 0, 0, presence, 0,
    ];
  }
}

/// The band of a scroll edge effect as [details] describe it, laid out at
/// its edge of the scroll view: the bar's extent, and for the soft effect
/// [ScrollEdgeTuning.softOverhang] past it. [paint] draws the band.
@internal
class ScrollEdgeBand extends StatelessWidget {
  /// Lays [paint] out where the band of [details] lies.
  const ScrollEdgeBand({required this.details, required this.paint, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  /// The render object widget that draws the band.
  final Widget paint;

  @override
  Widget build(BuildContext context) {
    final top = details.edge == AxisDirection.up;
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          height: details.hard
              ? details.extent
              : details.extent + ScrollEdgeTuning.softOverhang,
          width: double.infinity,
          child: paint,
        ),
      ),
    );
  }
}

/// The flat scroll edge effect: the content under the band dissolves
/// toward the background, and the hard effect draws its hairline, with no
/// blur. Every renderer draws it unless it draws its own.
@internal
class FlatScrollEdge extends StatelessWidget {
  /// Creates the effect [details] describe.
  const FlatScrollEdge({required this.details, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  @override
  Widget build(BuildContext context) => ScrollEdgeBand(
    details: details,
    paint: _FlatEdgePaint(
      details: details,
      brightness: GlassTraits.of(context).brightness,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
    ),
  );
}

class _FlatEdgePaint extends LeafRenderObjectWidget {
  const _FlatEdgePaint({
    required this.details,
    required this.brightness,
    required this.devicePixelRatio,
  });

  final GlassScrollEdgeDetails details;
  final Brightness brightness;
  final double devicePixelRatio;

  @override
  RenderScrollEdge createRenderObject(BuildContext context) => RenderScrollEdge(
    details: details,
    brightness: brightness,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderScrollEdge renderObject) {
    renderObject.details = details;
    renderObject.brightness = brightness;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

/// The fade toward the background and the hairline of a scroll edge
/// effect, faded as one by its presence through an opacity layer. A
/// renderer that blurs the band extends it, drawing the fade inside its
/// blur ([paintBand]) and updating its own layers in place
/// ([updateBand]).
@internal
class RenderScrollEdge extends RenderBox {
  /// Creates the band.
  RenderScrollEdge({
    required this._details,
    required this._brightness,
    required this._devicePixelRatio,
  });

  final _fade = LayerHandle<OpacityLayer>();
  double? _painted;

  /// What to draw.
  GlassScrollEdgeDetails get details => _details;
  GlassScrollEdgeDetails _details;
  set details(GlassScrollEdgeDetails value) {
    if (value == _details) return;
    if (attached) _details.presence.removeListener(_presenceChanged);
    _details = value;
    if (attached) _details.presence.addListener(_presenceChanged);
    markNeedsPaint();
  }

  /// The brightness the fade and hairline follow.
  Brightness get brightness => _brightness;
  Brightness _brightness;
  set brightness(Brightness value) {
    if (value == _brightness) return;
    _brightness = value;
    markNeedsPaint();
  }

  /// The device pixels per logical pixel.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// How present the effect is now, 0 to 1.
  double get presence => _details.presence.value.clamp(0.0, 1.0);

  // A presence change between two visible values updates the layers it
  // already has, without painting; appearing or vanishing paints.
  void _presenceChanged() {
    final presence = this.presence;
    final painted = _painted;
    if (presence == painted) return;
    final fade = _fade.layer;
    if (painted == null ||
        painted <= 0.001 ||
        presence <= 0.001 ||
        fade == null ||
        !updateBand(presence)) {
      markNeedsPaint();
      return;
    }
    _painted = presence;
    fade.alpha = Color.getAlphaFromOpacity(presence);
    markNeedsCompositedLayerUpdate();
  }

  /// Updates the layers a subclass drew around the fade to [presence], and
  /// says whether it could without painting.
  @protected
  bool updateBand(double presence) => true;

  /// Drops the layers a subclass drew around the fade.
  @protected
  void dropBand() {}

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _details.presence.addListener(_presenceChanged);
  }

  @override
  void detach() {
    _details.presence.removeListener(_presenceChanged);
    super.detach();
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    dropBand();
    _fade.layer = null;
  }

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final presence = this.presence;
    _painted = presence;
    if (presence <= 0.001) {
      _drop();
      return;
    }
    paintBand(context, offset, presence, paintFade);
  }

  /// Paints the band at [presence]: by default only [fade], the fade and
  /// hairline.
  @protected
  void paintBand(
    PaintingContext context,
    Offset offset,
    double presence,
    PaintingContextCallback fade,
  ) {
    dropBand();
    fade(context, offset);
  }

  /// Paints the fade and the hairline in an opacity layer of the effect's
  /// presence.
  @protected
  void paintFade(PaintingContext context, Offset offset) {
    final box = offset & size;
    _fade.layer = context.pushOpacity(
      offset,
      Color.getAlphaFromOpacity(presence),
      (context, _) => _paintFade(context.canvas, box),
      oldLayer: _fade.layer,
    );
  }

  void _paintFade(Canvas canvas, Rect box) {
    final background = _details.background;
    final fade = background.withValues(
      alpha: background.a * ScrollEdgeTuning.fade(_brightness),
    );
    final top = _details.edge == AxisDirection.up;
    final paint = Paint();
    if (!_details.hard) {
      paint.shader = LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [fade, fade, fade.withValues(alpha: 0)],
        stops: const [0, ScrollEdgeTuning.softFadeStart, 1],
      ).createShader(box);
      canvas.drawRect(box, paint);
      return;
    }
    // The hairline takes its own strip, already blended over the fade, so
    // the two draws do not overlap: the opacity layer above them then hands
    // its alpha to each draw instead of drawing them in a layer of its own.
    final hairline = 1 / _devicePixelRatio;
    final edge = top ? box.bottom - hairline : box.top + hairline;
    final near = Rect.fromLTRB(box.left, box.top, box.right, edge);
    final far = Rect.fromLTRB(box.left, edge, box.right, box.bottom);
    final (band, line) = top ? (near, far) : (far, near);
    paint.color = fade;
    canvas.drawRect(band, paint);
    paint.color = Color.alphaBlend(
      ScrollEdgeTuning.hairline(_brightness),
      fade,
    );
    canvas.drawRect(line, paint);
  }
}
