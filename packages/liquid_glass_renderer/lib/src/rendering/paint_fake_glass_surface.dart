import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// Extra logical pixels required for the portion of the contour that lies
/// outside the shape's nominal bounds.
double fakeGlassSurfaceOutset(LiquidGlassSettings settings) =>
    math.max<double>(settings.contourWidth + 1, 0);

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

/// The surface shaders a painter draws one recording with, one per draw.
///
/// CanvasKit on the web keeps a pointer to a shader's uniforms, not a copy,
/// so draws of one picture that share a shader all take the uniforms it was
/// given last. The first draw takes the painter's own shader, later ones
/// shaders of the loaded fake surface program, made once and kept.
final class FakeGlassSurfaceShaders {
  ui.FragmentShader? _first;
  final List<ui.FragmentShader> _more = [];
  int _drawn = 0;

  /// Starts a recording whose first draw takes [first].
  void begin(ui.FragmentShader first) {
    _first = first;
    _drawn = 0;
  }

  /// The shader of the recording's next draw.
  ui.FragmentShader next() {
    final first = _first!;
    final drawn = _drawn++;
    if (drawn == 0) return first;
    if (drawn <= _more.length) return _more[drawn - 1];
    // Without a cached program (the warm-up loads its own) the draws share
    // [first]: only the web reads uniforms late, and it warms nothing up.
    final program = GlassShaderPrograms.cached(ShaderKeys.fakeGlassSurface);
    if (program == null) return first;
    final shader = program.fragmentShader();
    _more.add(shader);
    return shader;
  }

  /// Releases the shaders it made.
  void dispose() {
    for (final shader in _more) {
      shader.dispose();
    }
    _more.clear();
    _first = null;
  }
}

/// Paints a FakeGlass surface and, when the glass has any highlight, its
/// highlight pass on top, each with the next of [shaders].
void paintFakeGlassSurfaceWithHighlight(
  Canvas canvas, {
  required FakeGlassSurfaceShaders shaders,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required LiquidGlassAppearance appearance,
  required double devicePixelRatio,
}) {
  paintFakeGlassSurface(
    canvas,
    shader: shaders.next(),
    size: size,
    shape: shape,
    settings: settings,
    appearance: appearance,
    devicePixelRatio: devicePixelRatio,
  );
  if (settings.highlight * appearance.visibility > 0) {
    paintFakeGlassSurface(
      canvas,
      shader: shaders.next(),
      size: size,
      shape: shape,
      settings: settings,
      appearance: appearance,
      devicePixelRatio: devicePixelRatio,
      highlightOnly: true,
    );
  }
}

/// Paints one analytic fake glass surface, its settings in logical pixels as
/// real glass takes them.
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
  final pairBottom = shape.pairBottomRadius;
  final fit = pairBottom == null
      ? 1.0
      : roundedSuperellipsePairFit(size, shape.cornerRadius, pairBottom);
  final cornerRadius = shape.cornerRadius * fit;
  final pair = pairBottom == null
      ? null
      : roundedSuperellipsePairParameters(
          size,
          shape.cornerRadius,
          pairBottom,
        );
  final colorModel = appearance.colorModel;
  var at = putFloats(shader, 0, [size.width, size.height]);
  at = putLanes(shader, at, FakeSurfaceLane.values, {
    FakeSurfaceLane.shapeType: [shape.rawType.shaderIndex],
    FakeSurfaceLane.cornerRadius: [cornerRadius],
    FakeSurfaceLane.tint: _color8(tint),
    FakeSurfaceLane.highlight: [settings.highlight * appearanceVisibility],
    FakeSurfaceLane.highlightWidth: [GlassRim.highlightWidth],
    FakeSurfaceLane.highlightWrap: [GlassRim.highlightWrap],
    FakeSurfaceLane.oppositeHighlight: [
      GlassRim.highlightOppositeStrength * appearanceVisibility,
    ],
    FakeSurfaceLane.contourStrength: [
      settings.contourStrength *
          (colorModel.parameters?.contourScale(settings.effectiveTintAmount) ??
              1) *
          appearanceVisibility,
    ],
    FakeSurfaceLane.contourWidth: [settings.contourWidth],
    FakeSurfaceLane.contourTransmittance: [0],
    FakeSurfaceLane.contourOffset: [0],
    FakeSurfaceLane.contourDirectionality: [settings.contourDirectionality],
    FakeSurfaceLane.bevelStrength: [
      settings.bevelShadowStrength * appearanceVisibility,
    ],
    FakeSurfaceLane.bevelDepth: [GlassRim.bevelShadowDepth],
    FakeSurfaceLane.bevelOffset: [GlassRim.bevelShadowOffset],
    FakeSurfaceLane.bevelDirectionality: [GlassRim.bevelShadowDirectionality],
    FakeSurfaceLane.lightDirection: [0, 1],
    FakeSurfaceLane.pixelSize: [1 / math.max(devicePixelRatio, 0.01)],
    FakeSurfaceLane.exteriorOnly: [if (exteriorOnly) 1 else 0],
    FakeSurfaceLane.glintLuminance: [colorModel.fakeGlintLuminance],
    FakeSurfaceLane.faceEmission: [
      faceEmission.r * appearanceVisibility,
      faceEmission.g * appearanceVisibility,
      faceEmission.b * appearanceVisibility,
    ],
    FakeSurfaceLane.glintFaceGain: [colorModel.fakeGlintFaceGain],
    FakeSurfaceLane.glintVibrancy: [colorModel.fakeGlintVibrancy],
    FakeSurfaceLane.highlightsOnly: [if (highlightOnly) 1 else 0],
    FakeSurfaceLane.bottomRadius: [pair?.bottomRadius ?? -1],
  });
  putFloats(shader, at, [
    ...?pair?.top.floats,
    ...?pair?.bottom.floats,
    if (pair == null) ...[
      ...shape is LiquidRoundedSuperellipse
          ? roundedSuperellipseParameters(size, cornerRadius).floats
          : _noSuperellipse,
      ..._noSuperellipse,
    ],
  ]);
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
