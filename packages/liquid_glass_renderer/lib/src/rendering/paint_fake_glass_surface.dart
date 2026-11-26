import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe.dart';
import 'package:liquid_glass_renderer/src/painting/glass_recipe_groups.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// How far past its shape fake glass wearing [model] draws, in logical
/// pixels: a pixel past the direct model's contour, or as far for an iOS 27
/// recipe, whose dark specular is narrower, and for any model.
double fakeGlassSurfaceOutset([WornColorModel? model]) =>
    (model == null || model.recipe != null
        ? GlassRim.contourWidth
        : model.rim.contourWidth) +
    1;

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
  if (glow.drawsWash) {
    final wash = (glow.wash * fade).clamp(0.0, 1.0);
    canvas.drawPaint(
      Paint()
        ..color = Color.from(alpha: 1, red: wash, green: wash, blue: wash)
        ..blendMode = BlendMode.plus,
    );
  }
  if (glow.drawsSpot) {
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

/// The surface shaders a painter draws one recording with, one per draw,
/// made from the program once it has loaded and kept.
///
/// CanvasKit on the web keeps a pointer to a shader's uniforms, not a copy,
/// so draws of one picture that share a shader all take the uniforms it was
/// given last.
final class FakeGlassSurfaceShaders {
  /// Shaders of a shape's surface (fake_glass_surface.frag); `onLoaded` runs
  /// when the program lands after [ready] said it had not.
  FakeGlassSurfaceShaders({this._onLoaded})
    : _program = ShaderKeys.fakeGlassSurface;

  /// Shaders of a field body's surface (fake_glass_field_surface.frag).
  FakeGlassSurfaceShaders.field({this._onLoaded})
    : _program = ShaderKeys.fakeGlassFieldSurface;

  final String _program;
  final VoidCallback? _onLoaded;
  final List<ui.FragmentShader> _shaders = [];
  int _drawn = 0;
  bool _waiting = false;
  bool _disposed = false;

  /// Whether the program has loaded; starts loading it if not. Until it has,
  /// the surface draws a plain tint.
  bool ready() {
    if (GlassShaderPrograms.cached(_program) != null) return true;
    if (!_waiting) {
      _waiting = true;
      GlassShaderPrograms.precacheShader(_program).then((_) {
        _waiting = false;
        if (!_disposed && GlassShaderPrograms.cached(_program) != null) {
          _onLoaded?.call();
        }
      });
    }
    return false;
  }

  /// Starts a recording.
  void begin() => _drawn = 0;

  /// The shader of the recording's next draw.
  ui.FragmentShader next() {
    final drawn = _drawn++;
    if (drawn < _shaders.length) return _shaders[drawn];
    final shader = GlassShaderPrograms.cached(_program)!.fragmentShader();
    _shaders.add(shader);
    return shader;
  }

  /// The shader of a recording's first draw, once one was drawn.
  ui.FragmentShader? get debugFirst => _shaders.firstOrNull;

  /// Releases the shaders it made.
  void dispose() {
    _disposed = true;
    for (final shader in _shaders) {
      shader.dispose();
    }
    _shaders.clear();
  }
}

/// Paints a FakeGlass surface and, when the glass has any glint, its
/// glint pass on top, each with the next of [shaders].
void paintFakeGlassSurfaceWithGlint(
  Canvas canvas, {
  required FakeGlassSurfaceShaders shaders,
  required Size size,
  required LiquidShape shape,
  required FakeGlassLook look,
  required WornAppearance appearance,
  required double devicePixelRatio,
}) {
  paintFakeGlassSurface(
    canvas,
    shader: shaders.next(),
    size: size,
    shape: shape,
    look: look,
    appearance: appearance,
    devicePixelRatio: devicePixelRatio,
  );
  if (_drawsLight(look, appearance)) {
    paintFakeGlassSurface(
      canvas,
      shader: shaders.next(),
      size: size,
      shape: shape,
      look: look,
      appearance: appearance,
      devicePixelRatio: devicePixelRatio,
      glintOnly: true,
    );
  }
}

/// Paints the contour ring of a FakeGlass of [shape] at [size]: its
/// surface only outside the silhouette, where the contour reaches past it.
void paintFakeGlassContourRing(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required FakeGlassLook look,
  required WornAppearance appearance,
  required double devicePixelRatio,
}) {
  final bounds = Offset.zero & size;
  canvas
    ..save()
    ..clipPath(
      Path.from(shape.getOuterPath(bounds))
        ..addRect(bounds.inflate(fakeGlassSurfaceOutset(appearance.colorModel)))
        ..fillType = PathFillType.evenOdd,
    );
  paintFakeGlassSurface(
    canvas,
    shader: shader,
    size: size,
    shape: shape,
    look: look,
    appearance: appearance,
    devicePixelRatio: devicePixelRatio,
    exteriorOnly: true,
  );
  canvas.restore();
}

/// Paints one analytic fake glass surface in [look], its widths logical
/// pixels as real glass takes them.
void paintFakeGlassSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required Size size,
  required LiquidShape shape,
  required FakeGlassLook look,
  required WornAppearance appearance,
  required double devicePixelRatio,
  bool exteriorOnly = false,
  bool glintOnly = false,
}) {
  final pair = shape.isPair
      ? roundedSuperellipsePairParameters(
          size,
          shape.cornerRadius,
          shape.bottomCornerRadius,
        )
      : null;
  final cornerRadius = pair?.topRadius ?? shape.cornerRadius;
  var at = putFloats(shader, 0, [size.width, size.height]);
  at = putLanes(shader, at, FakeSurfaceLane.values, {
    ..._litLanes(
      look,
      appearance,
      devicePixelRatio: devicePixelRatio,
      exteriorOnly: exteriorOnly,
      glintOnly: glintOnly,
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
  final contourOutset = fakeGlassSurfaceOutset(appearance.colorModel);
  canvas.drawRect(
    shaderQuad(
      (Offset.zero & size).inflate(glintOnly ? 0 : contourOutset),
      canvas,
    ),
    _surfacePaint(shader, glintOnly: glintOnly),
  );
}

/// Paints the fake glass body [field] describes, shaded from [nodes], its
/// FakeGlassFieldImage, in the field's coordinates: its surface and
/// glint inside the field's edge and its contour outside it,
/// each with the next of [shaders].
void paintFakeGlassFieldBody(
  Canvas canvas, {
  required FakeGlassSurfaceShaders shaders,
  required ui.Image nodes,
  required LiquidGlassField field,
  required FakeGlassLook look,
  required WornAppearance appearance,
  required double devicePixelRatio,
}) {
  void paint({bool exteriorOnly = false, bool glintOnly = false}) =>
      _paintFakeGlassFieldSurface(
        canvas,
        shader: shaders.next(),
        nodes: nodes,
        field: field,
        look: look,
        appearance: appearance,
        devicePixelRatio: devicePixelRatio,
        exteriorOnly: exteriorOnly,
        glintOnly: glintOnly,
      );

  final edge = field.edge;
  canvas
    ..save()
    ..clipPath(edge);
  paint();
  if (_drawsLight(look, appearance)) paint(glintOnly: true);
  canvas.restore();
  if (!fakeGlassDrawsContour(look, appearance)) return;
  canvas
    ..save()
    ..clipPath(
      LiquidGlassSilhouette.path(
        edge,
      ).outside(
        edge.getBounds().inflate(
          fakeGlassSurfaceOutset(appearance.colorModel) + 1,
        ),
      ),
    );
  paint(exteriorOnly: true);
  canvas.restore();
}

void _paintFakeGlassFieldSurface(
  Canvas canvas, {
  required ui.FragmentShader shader,
  required ui.Image nodes,
  required LiquidGlassField field,
  required FakeGlassLook look,
  required WornAppearance appearance,
  required double devicePixelRatio,
  required bool exteriorOnly,
  required bool glintOnly,
}) {
  var at = putFloats(shader, 0, [
    field.columns.toDouble(),
    field.rows.toDouble(),
  ]);
  at = putLanes(shader, at, FakeSurfaceLane.values, {
    ..._litLanes(
      look,
      appearance,
      devicePixelRatio: devicePixelRatio,
      exteriorOnly: exteriorOnly,
      glintOnly: glintOnly,
    ),
    FakeSurfaceLane.shapeType: [0],
    FakeSurfaceLane.cornerRadius: [0],
    FakeSurfaceLane.bottomRadius: [-1],
  });
  putFloats(shader, at, [field.origin.dx, field.origin.dy, field.step, 0]);
  shader.setImageSampler(0, nodes, filterQuality: FilterQuality.low);
  final paint = _surfacePaint(shader, glintOnly: glintOnly);
  if (exteriorOnly) {
    canvas.drawPath(
      field.edge,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * fakeGlassSurfaceOutset(appearance.colorModel),
    );
    return;
  }
  canvas.drawRect(field.edge.getBounds().inflate(1), paint);
}

Paint _surfacePaint(ui.FragmentShader shader, {required bool glintOnly}) {
  final paint = Paint()..shader = shader;
  if (glintOnly) {
    // Add light on top of the surface instead of replacing it. A translucent
    // FakeGlass surface can then exceed its premultiplied face (and SDR white
    // on an extended-range target) without raising the surface's alpha.
    paint.blendMode = BlendMode.plus;
  }
  return paint;
}

/// Whether fake glass in [look] and [appearance] draws a glint pass: the
/// glint of direct glass, the rim highlight of an iOS 27 recipe.
bool _drawsLight(FakeGlassLook look, WornAppearance appearance) {
  if (!appearance.shows) return false;
  return switch (appearance.colorModel.recipe) {
    final worn? => recipeOf(worn, look.sliderPosition).rimHighlight.opacity > 0,
    null => appearance.colorModel.rim.glintStrength > 0,
  };
}

/// Whether fake glass in [look] and [appearance] draws a band outside its
/// shape: the contour of direct glass, the dark specular of an iOS 27
/// recipe.
bool fakeGlassDrawsContour(FakeGlassLook look, WornAppearance appearance) =>
    switch (appearance.colorModel.recipe) {
      final worn? => _specularOf(recipeOf(worn, look.sliderPosition)) != null,
      null => appearance.colorModel.rim.contourWidth > 0,
    };

DarkSpecularRecipe? _specularOf(GlassRecipe recipe) {
  final specular = recipe.darkSpecular;
  return specular.amount > 0 && specular.width > 0 && specular.colorBias < 0
      ? specular
      : null;
}

Map<FakeSurfaceLane, List<double>> _litLanes(
  FakeGlassLook look,
  WornAppearance appearance, {
  required double devicePixelRatio,
  required bool exteriorOnly,
  required bool glintOnly,
}) {
  final visibility = appearance.visibility;
  final colorModel = appearance.colorModel;
  final rim = colorModel.rim;
  final worn = colorModel.recipe;
  final recipe = worn == null ? null : recipeOf(worn, look.sliderPosition);
  final faceEmission = recipe?.face.fill ?? const Color(0x00000000);
  final directVisibility = recipe == null ? visibility : 0.0;
  final specular = recipe == null ? null : _specularOf(recipe);
  final edges = worn == null
      ? null
      : recipeLanes(
          worn,
          sliderPosition: look.sliderPosition,
          devicePixelRatio: 1,
        );
  List<double> edge(RecipeLane lane, {double scale = 1}) {
    if (edges == null) return List.filled(lane.width, 0);
    final at = laneOffset(RecipeLane.values, lane);
    return [for (var i = 0; i < lane.width; i++) edges[at + i] * scale];
  }

  return {
    FakeSurfaceLane.tint: _color8(fakeGlassSurfaceTint(appearance)),
    FakeSurfaceLane.glintStrength: [rim.glintStrength * directVisibility],
    FakeSurfaceLane.contourStrength: [rim.contourStrength * directVisibility],
    FakeSurfaceLane.contourWidth: [rim.contourWidth],
    FakeSurfaceLane.contourDirectionality: [rim.contourDirectionality],
    FakeSurfaceLane.bevelStrength: [
      rim.bevelShadowStrength * directVisibility,
    ],
    FakeSurfaceLane.pixelSize: [1 / math.max(devicePixelRatio, 0.01)],
    FakeSurfaceLane.exteriorOnly: [if (exteriorOnly) 1 else 0],
    FakeSurfaceLane.faceEmission: [
      faceEmission.r * faceEmission.a * visibility,
      faceEmission.g * faceEmission.a * visibility,
      faceEmission.b * faceEmission.a * visibility,
    ],
    FakeSurfaceLane.glintOnly: [if (glintOnly) 1 else 0],
    FakeSurfaceLane.highlightOpacity: edge(
      RecipeLane.highlightOpacity,
      scale: visibility,
    ),
    FakeSurfaceLane.highlightWidth: edge(RecipeLane.highlightWidth),
    FakeSurfaceLane.highlightDiffuseWidth: edge(
      RecipeLane.highlightDiffuseWidth,
    ),
    FakeSurfaceLane.highlightSpread: edge(RecipeLane.highlightSpread),
    FakeSurfaceLane.highlightDiffuseBias: edge(RecipeLane.highlightDiffuseBias),
    FakeSurfaceLane.highlightCurvature: edge(RecipeLane.highlightCurvature),
    FakeSurfaceLane.highlightLift: [
      if (recipe == null) 0 else fakeGlassHighlightLift(recipe),
    ],
    FakeSurfaceLane.ringOpacity: edge(
      RecipeLane.ringOpacity,
      scale: visibility,
    ),
    FakeSurfaceLane.ringOffset: edge(RecipeLane.ringOffset),
    FakeSurfaceLane.ringStroke: edge(RecipeLane.ringStroke),
    FakeSurfaceLane.ringInverseRadius: edge(RecipeLane.ringInverseRadius),
    FakeSurfaceLane.specularStrength: [
      if (specular == null) 0 else -specular.colorBias * visibility,
    ],
    FakeSurfaceLane.specularWidth: edge(RecipeLane.specularWidth),
    FakeSurfaceLane.specularSpread: edge(RecipeLane.specularSpread),
    FakeSurfaceLane.specularBias: edge(RecipeLane.specularBias),
  };
}

double _colorDodgeLevelFor(double multiplier) => 1 - 1 / multiplier;
