import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The numbers of UIKit's scroll edge effect on iOS 27: `PocketSettings`
/// and the layers of `UIKit.ScrollEdgeEffectView` (read from UIKit, notes
/// private; the hard band replayed against the device in Morph's
/// scroll-edge fixture). Radii are taken as Gaussian sigmas.
abstract final class _Edge {
  /// How far the soft band reaches past the bar.
  static const double softOverhang = 40;

  /// Where along the soft band, from the screen's edge, the fade starts to
  /// dissolve.
  static const double softFadeStart = 0.3407;

  /// The blur of the soft band.
  static const double softBlur = 1.5;

  /// The blur of the hard band; UIKit uses 2 under a navigation bar.
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
/// Mali GPU, and the two blurs differ by a few channel steps: NEAR.
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

// An identity backdrop filter: under a clip it gives the blur inside it a
// pass of the clip's size to read instead of the whole pass behind it.
const ui.ImageFilter _seed = ui.ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// The height of the band the effect [details] describe covers.
@internal
double scrollEdgeBand(GlassScrollEdgeDetails details) =>
    details.hard ? details.extent : details.extent + _Edge.softOverhang;

/// A scroll edge effect as [details] describe it; it blurs the content
/// under it only when [blurs].
@internal
class ScrollEdge extends StatelessWidget {
  /// Creates the effect.
  const ScrollEdge({required this.details, required this.blurs, super.key});

  /// What to draw.
  final GlassScrollEdgeDetails details;

  /// Whether the band blurs the content under it; without, the content
  /// only dissolves toward the background.
  final bool blurs;

  @override
  Widget build(BuildContext context) {
    final top = details.edge == AxisDirection.up;
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          height: scrollEdgeBand(details),
          width: double.infinity,
          child: _EdgePaint(
            details: details,
            blurs: blurs,
            brightness: GlassTraits.of(context).brightness,
            devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          ),
        ),
      ),
    );
  }
}

class _EdgePaint extends LeafRenderObjectWidget {
  const _EdgePaint({
    required this.details,
    required this.blurs,
    required this.brightness,
    required this.devicePixelRatio,
  });

  final GlassScrollEdgeDetails details;
  final bool blurs;
  final Brightness brightness;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEdge(
    details: details,
    blurs: blurs,
    brightness: brightness,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderEdge renderObject) {
    renderObject.details = details;
    renderObject.blurs = blurs;
    renderObject.brightness = brightness;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

/// The blur, the fade toward the background and the hairline of the
/// effect, faded as one by its presence through the alpha of the blurred
/// backdrop and of the paint over it: an opacity layer above a blur would
/// read an empty backdrop. The blur reads a copy of the backdrop only as
/// far around the band as its kernel reaches.
class _RenderEdge extends RenderBox {
  _RenderEdge({
    required this._details,
    required this._blurs,
    required this._brightness,
    required this._devicePixelRatio,
  });

  final _seedClip = LayerHandle<ClipRectLayer>();
  final _seedLayer = LayerHandle<BackdropFilterLayer>();
  final _clip = LayerHandle<ClipRectLayer>();
  final _blur = LayerHandle<BackdropFilterLayer>();
  final _fade = LayerHandle<OpacityLayer>();
  double? _painted;

  GlassScrollEdgeDetails _details;
  GlassScrollEdgeDetails get details => _details;
  set details(GlassScrollEdgeDetails value) {
    if (value == _details) return;
    if (attached) _details.presence.removeListener(_presenceChanged);
    _details = value;
    if (attached) _details.presence.addListener(_presenceChanged);
    markNeedsPaint();
  }

  bool _blurs;
  bool get blurs => _blurs;
  set blurs(bool value) {
    if (value == _blurs) return;
    _blurs = value;
    markNeedsPaint();
  }

  Brightness _brightness;
  Brightness get brightness => _brightness;
  set brightness(Brightness value) {
    if (value == _brightness) return;
    _brightness = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  double get _presence => _details.presence.value.clamp(0.0, 1.0);

  // A presence change between two visible values updates the layers it
  // already has, without painting; appearing or vanishing paints.
  void _presenceChanged() {
    final presence = _presence;
    final painted = _painted;
    if (presence == painted) return;
    final blur = _blur.layer;
    final fade = _fade.layer;
    if (painted == null ||
        painted <= 0.001 ||
        presence <= 0.001 ||
        (_blurs && blur == null) ||
        fade == null) {
      markNeedsPaint();
      return;
    }
    _painted = presence;
    if (_blurs) blur!.filter = _filter(presence);
    fade.alpha = Color.getAlphaFromOpacity(presence);
    markNeedsCompositedLayerUpdate();
  }

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
    _seedClip.layer = null;
    _seedLayer.layer = null;
    _clip.layer = null;
    _blur.layer = null;
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

  double get _sigma => _halfResolutionSigma(
    _details.hard ? _Edge.hardBlur : _Edge.softBlur,
    _devicePixelRatio,
  );

  // The hard band folds its presence into the saturation matrix after its
  // blur: one color pass instead of two.
  ui.ImageFilter _filter(double presence) {
    final sigma = _sigma;
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    if (_details.hard) {
      return ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(_Edge.hardMatrix(presence)),
        inner: blur,
      );
    }
    if (presence == 1) return blur;
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, presence, 0,
      ]),
      inner: blur,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final presence = _presence;
    _painted = presence;
    if (presence <= 0.001) {
      _drop();
      return;
    }
    final box = offset & size;
    void fade(PaintingContext context, Offset offset) {
      _fade.layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(presence),
        (context, _) => _paintFade(context.canvas, box),
        oldLayer: _fade.layer,
      );
    }

    if (!_blurs) {
      _seedClip.layer = null;
      _seedLayer.layer = null;
      _clip.layer = null;
      _blur.layer = null;
      fade(context, offset);
      return;
    }
    void band(PaintingContext context, Offset offset) {
      _clip.layer = context.pushClipRect(
        true,
        offset,
        Offset.zero & size,
        (context, offset) {
          final blur = _blur.layer ??= BackdropFilterLayer();
          blur.filter = _filter(presence);
          context.pushLayer(blur, fade, offset);
        },
        oldLayer: _clip.layer,
      );
    }

    final seed = _seedLayer.layer ??= BackdropFilterLayer(
      filter: _seed,
      blendMode: BlendMode.src,
    );
    _seedClip.layer = context.pushClipRect(
      true,
      offset,
      (Offset.zero & size).inflate(_blurReach(_sigma, _devicePixelRatio)),
      (context, offset) => context.pushLayer(seed, band, offset),
      oldLayer: _seedClip.layer,
    );
  }

  void _paintFade(Canvas canvas, Rect box) {
    final background = _details.background;
    final fade = background.withValues(
      alpha: background.a * _Edge.fade(_brightness),
    );
    final top = _details.edge == AxisDirection.up;
    final paint = Paint();
    if (!_details.hard) {
      paint.shader = LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [fade, fade, fade.withValues(alpha: 0)],
        stops: const [0, _Edge.softFadeStart, 1],
      ).createShader(box);
      canvas.drawRect(box, paint);
      return;
    }
    paint.color = fade;
    canvas.drawRect(box, paint);
    final hairline = 1 / _devicePixelRatio;
    paint.color = _Edge.hairline(_brightness);
    canvas.drawRect(
      top
          ? Rect.fromLTRB(
              box.left,
              box.bottom - hairline,
              box.right,
              box.bottom,
            )
          : Rect.fromLTRB(box.left, box.top, box.right, box.top + hairline),
      paint,
    );
  }
}
