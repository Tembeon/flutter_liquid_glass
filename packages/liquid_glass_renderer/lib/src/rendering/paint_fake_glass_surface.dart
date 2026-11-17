import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// Extra logical pixels required for the portion of the contour that lies
/// outside the shape's nominal bounds.
double fakeGlassSurfaceOutset(LiquidGlassSettings settings) =>
    math.max<double>(settings.contourWidth + 1, 0);

final _noSuperellipse = List<double>.filled(SquircleLane.values.length, 0);

/// The tint fake glass in [appearance] lays over its backdrop, faded by
/// its visibility.
Color fakeGlassSurfaceTint(WornAppearance appearance) {
  final tint = appearance.colorModel.approximateSurfaceTint(appearance.tint);
  return tint.withValues(
    alpha: tint.a * appearance.visibility,
  );
}

/// Paints [glow] on fake glass inside the canvas's clip, which the caller
/// sets to the glass's silhouette: over what its backdrop filter drew and
/// under its surface, faded by the visibility of [appearance].
void paintFakeGlassGlow(
  Canvas canvas,
  DrawnGlow glow, {
  required WornAppearance appearance,
}) {
  final fade = appearance.visibility;
  if (fade == 0) return;
  final wash = (glow.wash * fade).clamp(0.0, 1.0);
  if (wash > 0) {
    canvas.drawPaint(
      Paint()
        ..color = Color.from(alpha: 1, red: wash, green: wash, blue: wash)
        ..blendMode = BlendMode.plus,
    );
  }
  if (glow.gain > 0 && glow.radius > 0) {
    final reach = glow.radius * _spotReach;
    Color white(double t) {
      final d = t * _spotReach;
      final level =
          fade * _colorDodgeLevelFor(1 + glow.gain * math.exp(-0.5 * d * d));
      return Color.from(alpha: 1, red: level, green: level, blue: level);
    }

    canvas.drawCircle(
      glow.center,
      reach,
      Paint()
        ..blendMode = BlendMode.colorDodge
        ..shader = ui.Gradient.radial(glow.center, reach, [
          for (final t in _spotStops)
            if (t < 1) white(t) else const Color(0xFF000000),
        ], _spotStops),
    );
  }
}

const double _spotReach = 3.5;
const List<double> _spotStops = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 1];

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
/// shaders of the loaded program, made once and kept.
final class FakeGlassSurfaceShaders {
  /// Shaders of a shape's surface (fake_glass_surface.frag).
  FakeGlassSurfaceShaders() : _program = ShaderKeys.fakeGlassSurface;

  /// Shaders of a field body's surface (fake_glass_field_surface.frag).
  FakeGlassSurfaceShaders.field() : _program = ShaderKeys.fakeGlassFieldSurface;

  final String _program;
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
    final program = GlassShaderPrograms.cached(_program);
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
  required WornAppearance appearance,
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
  if (settings.highlight > 0 && appearance.shows) {
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

/// Paints the exterior border of a FakeGlass of [shape] at [size]: its
/// surface only outside the silhouette, where the contour reaches past it.
void paintFakeGlassBorderRing(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required WornAppearance appearance,
  required double devicePixelRatio,
}) {
  final bounds = Offset.zero & size;
  canvas
    ..save()
    ..clipPath(
      Path.from(shape.getOuterPath(bounds))
        ..addRect(bounds.inflate(fakeGlassSurfaceOutset(settings)))
        ..fillType = PathFillType.evenOdd,
    );
  paintFakeGlassSurface(
    canvas,
    shader: shader,
    size: size,
    shape: shape,
    settings: settings,
    appearance: appearance,
    devicePixelRatio: devicePixelRatio,
    exteriorOnly: true,
  );
  canvas.restore();
}

/// Paints one analytic fake glass surface, its settings in logical pixels as
/// real glass takes them.
void paintFakeGlassSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required LiquidGlassSettings settings,
  required WornAppearance appearance,
  required double devicePixelRatio,
  bool exteriorOnly = false,
  bool highlightOnly = false,
}) {
  final pairBottom = shape.pairBottomRadius;
  final pair = pairBottom == null
      ? null
      : roundedSuperellipsePairParameters(
          size,
          shape.cornerRadius,
          pairBottom,
        );
  final cornerRadius = pair?.topRadius ?? shape.cornerRadius;
  var at = putFloats(shader, 0, [size.width, size.height]);
  at = putLanes(shader, at, FakeSurfaceLane.values, {
    ..._litLanes(
      settings,
      appearance,
      devicePixelRatio: devicePixelRatio,
      exteriorOnly: exteriorOnly,
      highlightOnly: highlightOnly,
    ),
    FakeSurfaceLane.shapeType: [shape.rawType.shaderIndex],
    FakeSurfaceLane.cornerRadius: [cornerRadius],
    FakeSurfaceLane.bottomRadius: [pair?.bottomRadius ?? -1],
  });
  putFloats(shader, at, [
    ...?pair?.top.floats,
    ...?pair?.bottom.floats,
    if (pair == null) ...[
      ...shape.rawType == RawShapeType.squircle
          ? roundedSuperellipseParameters(size, cornerRadius).floats
          : _noSuperellipse,
      ..._noSuperellipse,
    ],
  ]);
  final contourOutset = fakeGlassSurfaceOutset(settings);
  canvas.drawRect(
    fakeGlassSurfaceQuad(
      (Offset.zero & size).inflate(highlightOnly ? 0 : contourOutset),
      canvas.getTransform(),
    ),
    _surfacePaint(shader, highlightOnly: highlightOnly),
  );
}

/// Paints the fake glass body [field] describes, shaded from [nodes], its
/// FakeGlassFieldImage, in the field's coordinates: its surface and
/// highlight inside the field's edge and its exterior border outside it,
/// each with the next of [shaders].
void paintFakeGlassFieldBody(
  Canvas canvas, {
  required FakeGlassSurfaceShaders shaders,
  required ui.Image nodes,
  required LiquidGlassField field,
  required LiquidGlassSettings settings,
  required WornAppearance appearance,
  required double devicePixelRatio,
}) {
  void paint({bool exteriorOnly = false, bool highlightOnly = false}) =>
      _paintFakeGlassFieldSurface(
        canvas,
        shader: shaders.next(),
        nodes: nodes,
        field: field,
        settings: settings,
        appearance: appearance,
        devicePixelRatio: devicePixelRatio,
        exteriorOnly: exteriorOnly,
        highlightOnly: highlightOnly,
      );

  final edge = field.edge;
  canvas
    ..save()
    ..clipPath(edge);
  paint();
  if (settings.highlight > 0 && appearance.shows) paint(highlightOnly: true);
  canvas.restore();
  if (settings.contourWidth <= 0) return;
  canvas
    ..save()
    ..clipPath(
      LiquidGlassSilhouette.path(
        edge,
      ).outside(edge.getBounds().inflate(fakeGlassSurfaceOutset(settings) + 1)),
    );
  paint(exteriorOnly: true);
  canvas.restore();
}

void _paintFakeGlassFieldSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required ui.Image nodes,
  required LiquidGlassField field,
  required LiquidGlassSettings settings,
  required WornAppearance appearance,
  required double devicePixelRatio,
  required bool exteriorOnly,
  required bool highlightOnly,
}) {
  var at = putFloats(shader, 0, [
    field.cols.toDouble(),
    field.rows.toDouble(),
  ]);
  at = putLanes(shader, at, FakeSurfaceLane.values, {
    ..._litLanes(
      settings,
      appearance,
      devicePixelRatio: devicePixelRatio,
      exteriorOnly: exteriorOnly,
      highlightOnly: highlightOnly,
    ),
    FakeSurfaceLane.shapeType: [0],
    FakeSurfaceLane.cornerRadius: [0],
    FakeSurfaceLane.bottomRadius: [-1],
  });
  putFloats(shader, at, [field.origin.dx, field.origin.dy, field.step, 0]);
  shader.setImageSampler(0, nodes, filterQuality: FilterQuality.low);
  final paint = _surfacePaint(shader, highlightOnly: highlightOnly);
  if (exteriorOnly) {
    canvas.drawPath(
      field.edge,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * fakeGlassSurfaceOutset(settings),
    );
    return;
  }
  canvas.drawRect(field.edge.getBounds().inflate(1), paint);
}

Paint _surfacePaint(ui.FragmentShader shader, {required bool highlightOnly}) {
  final paint = Paint()..shader = shader;
  if (highlightOnly) {
    // Add light on top of the surface instead of replacing it. A translucent
    // FakeGlass surface can then exceed its premultiplied face (and SDR white
    // on an extended-range target) without raising the surface's alpha.
    paint.blendMode = BlendMode.plus;
  }
  return paint;
}

Map<FakeSurfaceLane, List<double>> _litLanes(
  LiquidGlassSettings settings,
  WornAppearance appearance, {
  required double devicePixelRatio,
  required bool exteriorOnly,
  required bool highlightOnly,
}) {
  final visibility = appearance.visibility;
  final colorModel = appearance.colorModel;
  final faceEmission =
      colorModel.parameters
          ?.faceTransfer(tintAmount: settings.effectiveTintAmount)
          .emission ??
      const Color(0x00000000);
  return {
    FakeSurfaceLane.tint: _color8(fakeGlassSurfaceTint(appearance)),
    FakeSurfaceLane.highlight: [settings.highlight * visibility],
    FakeSurfaceLane.highlightWidth: [GlassRim.highlightWidth],
    FakeSurfaceLane.contourStrength: [
      settings.contourStrength *
          (colorModel.parameters?.contourScale(settings.effectiveTintAmount) ??
              1) *
          visibility,
    ],
    FakeSurfaceLane.contourWidth: [settings.contourWidth],
    FakeSurfaceLane.contourDirectionality: [settings.contourDirectionality],
    FakeSurfaceLane.bevelStrength: [settings.bevelShadowStrength * visibility],
    FakeSurfaceLane.bevelDepth: [GlassRim.bevelShadowDepth],
    FakeSurfaceLane.bevelOffset: [GlassRim.bevelShadowOffset],
    FakeSurfaceLane.pixelSize: [1 / math.max(devicePixelRatio, 0.01)],
    FakeSurfaceLane.exteriorOnly: [if (exteriorOnly) 1 else 0],
    FakeSurfaceLane.glintLuminance: [colorModel.fakeGlintLuminance],
    FakeSurfaceLane.faceEmission: [
      faceEmission.r * visibility,
      faceEmission.g * visibility,
      faceEmission.b * visibility,
    ],
    FakeSurfaceLane.glintFaceGain: [colorModel.fakeGlintFaceGain],
    FakeSurfaceLane.glintVibrancy: [colorModel.fakeGlintVibrancy],
    FakeSurfaceLane.highlightsOnly: [if (highlightOnly) 1 else 0],
  };
}

double _colorDodgeLevelFor(double multiplier) => 1 - 1 / multiplier;
