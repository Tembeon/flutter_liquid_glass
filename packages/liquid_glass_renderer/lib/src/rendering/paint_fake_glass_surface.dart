import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';

/// Extra logical pixels required for the portion of the contour that lies
/// outside the shape's nominal bounds.
double fakeGlassSurfaceOutset(LiquidGlassSettings settings) {
  return math
      .max(
        settings.contourWidth + 1,
        0,
      )
      .toDouble();
}

const _noSuperellipse = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

/// The channels of [color] as the shader's vec4 takes them, each rounded to
/// 8 bits as the surface was tuned with.
List<double> _color8(Color color) => [
  for (final channel in [color.r, color.g, color.b, color.a])
    (channel * 255).round().clamp(0, 255) / 255,
];

/// Expands [localQuad] outward to whole device pixels under [transform]
/// (the draw's `canvas.getTransform()`); a transform that is not an
/// axis-aligned scale and translate returns [localQuad] unchanged.
///
/// Works around an Impeller/Metal coverage bug on macOS: a shader-filled draw
/// whose quad edge lands on a half-integer device pixel quantizes its alpha
/// ramp to whole pixels near that edge, so the analytic silhouette
/// stair-steps. The shader places the shape by `FlutterFragCoord`, so a
/// larger quad changes nothing visible. The snap is taken at paint;
/// compositor-only motion of a retained layer can move the quad back onto a
/// half pixel until the next repaint.
Rect fakeGlassSurfaceQuad(Rect localQuad, Float64List transform) {
  final s = transform;
  if (s[1] != 0 ||
      s[2] != 0 ||
      s[3] != 0 ||
      s[4] != 0 ||
      s[6] != 0 ||
      s[7] != 0 ||
      s[11] != 0 ||
      s[14] != 0 ||
      s[0] == 0 ||
      s[5] == 0) {
    return localQuad;
  }
  (double, double) axis(
    double localMin,
    double localMax,
    double scale,
    double shift,
  ) {
    final a = scale * localMin + shift;
    final b = scale * localMax + shift;
    return (
      (math.min(a, b).floor() - shift) / scale,
      (math.max(a, b).ceil() - shift) / scale,
    );
  }

  final (left, right) = axis(localQuad.left, localQuad.right, s[0], s[12]);
  final (top, bottom) = axis(localQuad.top, localQuad.bottom, s[5], s[13]);
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Paints a FakeGlass surface and, when the glass has any highlight, its
/// highlight pass on top.
void paintFakeGlassSurfaceWithHighlight(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required LiquidGlassAppearance appearance,
  required double devicePixelRatio,
}) {
  paintFakeGlassSurface(
    canvas,
    shader: shader,
    size: size,
    shape: shape,
    settings: settings,
    appearance: appearance,
    devicePixelRatio: devicePixelRatio,
  );
  if (settings.highlight * appearance.visibility > 0) {
    paintFakeGlassSurface(
      canvas,
      shader: shader,
      size: size,
      shape: shape,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: devicePixelRatio,
      highlightOnly: true,
    );
  }
}

/// Paints one analytic FakeGlass surface with the same logical-pixel setting
/// contract used by RealGlass.
void paintFakeGlassSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required LiquidGlassAppearance appearance,
  required double devicePixelRatio,
  bool exteriorOnly = false,
  bool highlightOnly = false,
}) {
  final appearanceVisibility = appearance.visibility.clamp(0.0, 1.0);
  final surfaceTint = appearance.colorModel.approximateSurfaceTint(
    appearance.tint,
  );
  final tint = surfaceTint.withValues(
    alpha: surfaceTint.a * appearanceVisibility,
  );
  final faceEmission =
      appearance.colorModel.parameters
          ?.faceTransfer(tintAmount: settings.effectiveTintAmount)
          .emission ??
      const Color(0x00000000);
  final shapeType = switch (shape) {
    LiquidOval() => 0.0,
    LiquidRoundedRectangle() => 1.0,
    LiquidRoundedSuperellipse() => 2.0,
  };
  final pairShape = shape is LiquidRoundedSuperellipse && !shape.isUniform
      ? shape
      : null;
  final fit = pairShape == null
      ? 1.0
      : roundedSuperellipsePairFit(
          size,
          pairShape.borderRadius,
          pairShape.effectiveBottomRadius,
        );
  final cornerRadius = shape.cornerRadius * fit;
  final bottomRadius = pairShape == null
      ? null
      : pairShape.effectiveBottomRadius * fit;
  // A pair's halves, the bottom one with its half width back in the slot its
  // radius takes for real glass.
  final pair = pairShape == null
      ? null
      : (roundedSuperellipsePairParameters(
          size,
          pairShape.borderRadius,
          pairShape.effectiveBottomRadius,
        )..[12 + 8] = size.width / 2);
  final opticalThickness = settings.effectiveEdgeDistanceRange;
  final uniforms = <double>[
    size.width,
    size.height,
    shapeType,
    cornerRadius,
    ..._color8(tint),
    settings.highlight * appearanceVisibility,
    GlassRim.highlightWidth,
    opticalThickness,
    GlassRim.highlightWrap,
    GlassRim.highlightOppositeStrength * appearanceVisibility,
    settings.contourStrength *
        (appearance.colorModel.parameters?.contourScale(
              settings.effectiveTintAmount,
            ) ??
            1) *
        appearanceVisibility,
    settings.contourWidth,
    0, // contour transmittance
    0, // contour offset
    settings.contourDirectionality,
    settings.bevelShadowStrength * appearanceVisibility,
    GlassRim.bevelShadowDepth,
    GlassRim.bevelShadowOffset,
    GlassRim.bevelShadowDirectionality,
    0, // bevel shadow size response
    0,
    1,
    1 / math.max(devicePixelRatio, 0.01),
    if (exteriorOnly) 1 else 0,
    appearance.colorModel.fakeGlintLuminance,
    faceEmission.r * appearanceVisibility,
    faceEmission.g * appearanceVisibility,
    faceEmission.b * appearanceVisibility,
    ...?pair,
    if (pair == null) ...[
      ...shape is LiquidRoundedSuperellipse
          ? roundedSuperellipseParameters(size, cornerRadius)
          : _noSuperellipse,
      ..._noSuperellipse,
    ],
    appearance.colorModel.fakeGlintFaceGain,
    appearance.colorModel.fakeGlintVibrancy,
    if (highlightOnly) 1 else 0,
    bottomRadius ?? -1,
  ];
  for (var i = 0; i < uniforms.length; i++) {
    shader.setFloat(i, uniforms[i]);
  }
  final contourOutset = fakeGlassSurfaceOutset(settings);
  final paint = Paint()..shader = shader;
  if (highlightOnly) {
    // Add light on top of the surface instead of replacing it. A translucent
    // FakeGlass surface can then exceed its premultiplied face (and SDR white
    // on an extended-range target) without raising the surface's alpha.
    paint.blendMode = BlendMode.plus;
  }
  canvas.drawRect(
    fakeGlassSurfaceQuad(
      (Offset.zero & size).inflate(highlightOnly ? 0 : contourOutset),
      canvas.getTransform(),
    ),
    paint,
  );
}
