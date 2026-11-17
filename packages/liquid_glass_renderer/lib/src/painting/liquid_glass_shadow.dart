import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_shape.dart';

/// The shadow iOS 27 casts under regular glass, which widens and deepens
/// with the glass's shorter side.
///
/// Glass up to 64 points on its shorter side casts a faint contact shadow:
/// black at 1.2 % under a blur of 4 points. From 160 points it casts the full
/// one: black at 12 % in light mode and 18 % in dark mode under a blur of 24
/// points. Between the two every part grows linearly. All of them fall 8
/// points below the glass. Clear glass casts no shadow on iOS.
///
/// The numbers are read from UIKit on iOS 27 and agree with captures of
/// native glass over white within half a level out of 255.
///
/// Near, not identical: iOS shades by the distance to the outline, Flutter
/// blurs the shape. The two agree along straight edges and differ by a
/// fraction of a level around a corner.
///
/// Among the shadows of a glass shape the renderer casts [at] the shape's
/// size in its place. Read as a plain [BoxShadow] it is the shadow of the
/// largest glass, so room reserved by its fields is always enough.
@immutable
final class LiquidGlassShadow extends BoxShadow {
  /// The shadow of iOS 27 regular glass in [brightness].
  const LiquidGlassShadow.ios27Regular({required this.brightness})
    : super(
        color: brightness == Brightness.dark
            ? const Color.from(alpha: _alpha * 0.6, red: 0, green: 0, blue: 0)
            : const Color.from(alpha: _alpha * 0.4, red: 0, green: 0, blue: 0),
        offset: _offset,
        blurRadius: (24 / math.sqrt2 - 0.5) / 0.57735,
      );

  /// The colour scheme of the glass, which sets how dark its shadow gets.
  final Brightness brightness;

  static const _offset = Offset(0, 8);

  // The shadow's own colour is black at 30 %; the opacity that grows with
  // the size multiplies it.
  static const _alpha = 0.3;

  /// The shadow of a shape of [size].
  BoxShadow at(Size size) {
    final grown = ios27PanelProgress(size.shortestSide);
    final opacity =
        0.04 + (brightness == Brightness.dark ? 0.56 : 0.36) * grown;
    // iOS fades the shadow as erfc(distance / radius), a Gaussian edge whose
    // sigma is the radius over sqrt 2; Flutter derives sigma from blurRadius
    // as 0.57735 r + 0.5.
    final sigma = (4 + 20 * grown) / math.sqrt2;
    return BoxShadow(
      color: Color.from(alpha: _alpha * opacity, red: 0, green: 0, blue: 0),
      offset: _offset,
      blurRadius: (sigma - 0.5) / 0.57735,
    );
  }

  /// [shadows] as a shape of [size] casts them: every [LiquidGlassShadow]
  /// among them replaced by its shadow [at] that size.
  ///
  /// Returns [shadows] itself when it holds none.
  static List<BoxShadow> resolve(List<BoxShadow> shadows, Size size) {
    if (!shadows.any((shadow) => shadow is LiquidGlassShadow)) return shadows;
    return [
      for (final shadow in shadows)
        if (shadow is LiquidGlassShadow) shadow.at(size) else shadow,
    ];
  }

  /// Paints [shadows] cast by a glass body of [silhouette] at [visibility],
  /// as a glass layer casts the shadows of a shape alone on it.
  ///
  /// The shadows keep off the body: they are cut outside it half a pixel
  /// into its edge, so no seam shows between them, and shadows with neither
  /// offset nor spread are blurred outside it alone ([BlurStyle.outer]).
  /// While the body fades their opacity and blur scale with its
  /// [visibility], and they show through it by the part it has yet to fade
  /// in. A [LiquidGlassShadow] among them is cast at the silhouette's size.
  /// [BoxShadow.blurStyle] is ignored, and a path casts without spread.
  static void paint(
    Canvas canvas,
    LiquidGlassSilhouette silhouette,
    List<BoxShadow> shadows, {
    double visibility = 1,
  }) => paintLoneGlassShadows(
    canvas,
    silhouette,
    resolve(shadows, silhouette.rect.size),
    visibility: visibility,
  );
}

/// The outline a glass body casts its shadows by: a [LiquidShape] filling a
/// rect, or a path, such as a field's edge (`LiquidGlassField.edge`).
@immutable
final class LiquidGlassSilhouette {
  /// The silhouette of [shape] filling [rect].
  const LiquidGlassSilhouette.shape(LiquidShape this.shape, this.rect)
    : path = null;

  /// The silhouette [path] fills.
  LiquidGlassSilhouette.path(Path this.path)
    : shape = null,
      rect = path.getBounds();

  /// The shape, or null for a [path].
  final LiquidShape? shape;

  /// The path, or null for a [shape].
  final Path? path;

  /// The bounds of the silhouette, the rect a [shape] fills.
  final Rect rect;

  /// Fills the silhouette with [paint], a shape with the canvas primitive
  /// that draws and blurs faster than its path ([LiquidShape.paintInterior]).
  void fill(Canvas canvas, Paint paint) => _fill(canvas, paint, Offset.zero, 0);

  void _fill(Canvas canvas, Paint paint, Offset offset, double spread) {
    if (shape case final shape?) {
      shape.paintInterior(canvas, rect.shift(offset).inflate(spread), paint);
    } else {
      canvas.drawPath(
        offset == Offset.zero ? path! : path!.shift(offset),
        paint,
      );
    }
  }

  /// Silhouettes are equal when they fill the same rect with the same shape,
  /// or are the same path.
  @override
  bool operator ==(Object other) =>
      other is LiquidGlassSilhouette &&
      other.shape == shape &&
      identical(other.path, path) &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(shape, identityHashCode(path), rect);
}

/// How the shadows of glass keep off the glass that casts them.
@internal
enum GlassShadowCut {
  /// Blurred outside the body alone ([BlurStyle.outer]), which is exact
  /// only for a lone whole body and shadows with neither offset nor spread.
  outer,

  /// Drawn in a layer of their own and cut by each body by its visibility.
  fraction,

  /// Clipped outside the whole bodies.
  clip,

  /// Drawn whole, for glass that covers them inside its bodies.
  none;

  /// The cut of [shadows] cast by one body ([lone]) or by several, while
  /// one of them is [fading] or none, drawn [under] glass that covers them
  /// or over it.
  static GlassShadowCut of({
    required bool lone,
    required Iterable<BoxShadow> shadows,
    required bool fading,
    bool under = false,
  }) {
    if (fading) return fraction;
    if (lone &&
        shadows.every(
          (shadow) => shadow.offset == Offset.zero && shadow.spreadRadius == 0,
        )) {
      return outer;
    }
    return under ? none : clip;
  }
}

/// A [LiquidGlassSilhouette] as glass casts its shadows by it.
@internal
extension CastSilhouette on LiquidGlassSilhouette {
  /// Fills [shadows] of the silhouette at [visibility].
  void cast(
    Canvas canvas,
    List<BoxShadow> shadows,
    double visibility, {
    required bool outer,
  }) {
    for (final shadow in shadows) {
      final paint = shadow
          .copyWith(
            color: shadow.color.withValues(alpha: shadow.color.a * visibility),
            blurRadius: shadow.blurRadius * visibility,
            blurStyle: outer ? BlurStyle.outer : BlurStyle.normal,
          )
          .toPaint();
      _fill(canvas, paint, shadow.offset, shadow.spreadRadius);
    }
  }

  /// The rect a shape's [cut] fills up to each side, so also its bounds.
  Rect get cutRect => rect.deflate(_antialiasedEdgeOverlap);

  static const _antialiasedEdgeOverlap = .5;

  /// The edge the silhouette cuts its shadows at: a shape's at [cutRect], a
  /// path's its own.
  Path get cut => path ?? shape!.getOuterPath(cutRect);

  /// Whether [cut] added to a box under the even-odd rule leaves the box
  /// less the silhouette ([pathOutside]).
  bool get cutsUnderEvenOdd => switch (path) {
    final path? => path.fillType == PathFillType.evenOdd,
    null => true,
  };

  /// What lies in [bounds] and outside the silhouette, to clip a shadow to.
  Path outside(Rect bounds) =>
      pathOutside(cut, bounds, cutsUnderEvenOdd: cutsUnderEvenOdd);

  /// Takes [visibility] of what lies under the silhouette's [cut] out of
  /// what is drawn.
  void cutOut(Canvas canvas, double visibility) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, visibility)
      ..blendMode = BlendMode.dstOut;
    if (shape case final shape?) {
      shape.paintInterior(canvas, cutRect, paint);
    } else {
      canvas.drawPath(path!, paint);
    }
  }
}

/// What lies in [bounds] and outside [cut] (a silhouette's
/// [CastSilhouette.cut], placed by [transform]), to clip a shadow to.
@internal
Path pathOutside(
  Path cut,
  Rect bounds, {
  required bool cutsUnderEvenOdd,
  Float64List? transform,
}) {
  final whole = Path()..addRect(bounds);
  if (!cutsUnderEvenOdd) {
    return Path.combine(
      PathOperation.difference,
      whole,
      transform == null ? cut : cut.transform(transform),
    );
  }
  return whole
    ..fillType = PathFillType.evenOdd
    ..addPath(cut, Offset.zero, matrix4: transform);
}

double _blurSupport(double blurRadius) =>
    Shadow.convertRadiusToSigma(blurRadius) * 3;

Rect _shadowRect(Rect body, BoxShadow shadow, double visibility) => body
    .shift(shadow.offset)
    .inflate(
      math.max(
        shadow.spreadRadius + _blurSupport(shadow.blurRadius * visibility),
        0,
      ),
    );

/// [body] grown to hold what each of [shadows] of it paints at
/// [visibility].
@internal
Rect glassShadowBounds(
  Rect body,
  List<BoxShadow> shadows,
  double visibility,
) => shadows.fold(
  body,
  (bounds, shadow) =>
      bounds.expandToInclude(_shadowRect(body, shadow, visibility)),
);

/// Paints [shadows], resolved for the body, of a lone body of [silhouette]
/// at [visibility], as [LiquidGlassShadow.paint] does.
@internal
void paintLoneGlassShadows(
  Canvas canvas,
  LiquidGlassSilhouette silhouette,
  List<BoxShadow> shadows, {
  required double visibility,
  Rect Function(Rect bounds)? layerBounds,
}) {
  final shown = drawnVisibility(visibility);
  if (shown <= 0 || shadows.isEmpty) return;
  final bounds = glassShadowBounds(silhouette.rect, shadows, shown);
  switch (GlassShadowCut.of(lone: true, shadows: shadows, fading: shown < 1)) {
    case GlassShadowCut.outer:
      silhouette.cast(canvas, shadows, shown, outer: true);
    case GlassShadowCut.none:
      silhouette.cast(canvas, shadows, shown, outer: false);
    case GlassShadowCut.clip:
      canvas
        ..save()
        ..clipPath(silhouette.outside(bounds));
      silhouette.cast(canvas, shadows, shown, outer: false);
      canvas.restore();
    case GlassShadowCut.fraction:
      canvas.saveLayer(layerBounds?.call(bounds) ?? bounds, Paint());
      silhouette
        ..cast(canvas, shadows, shown, outer: false)
        ..cutOut(canvas, shown);
      canvas.restore();
  }
}
