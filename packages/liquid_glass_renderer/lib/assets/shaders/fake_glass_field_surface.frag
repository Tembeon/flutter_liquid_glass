#version 460 core
// Positions are the layer's, up to thousands of logical pixels: at 16 bits a
// node would land a pixel off.
precision highp float;

#include <flutter/runtime_effect.glsl>

// The fake surface of a field body (LiquidGlassField): the lighting of
// fake_glass_surface.frag, its distance and normal read from the field's
// node image (FakeGlassFieldImage) instead of a shape's own.

// The node image's columns and rows, where fake_glass_surface.frag takes
// its size: the two programs share the floats Dart writes up to their
// lanes.
uniform vec2 uNodes;
#include "fake_glass_lanes.glsl"
#include "shader_constants.glsl"
// Where node (0, 0) lies in the layer and how far apart nodes lie, both in
// logical pixels, and nothing.
uniform vec4 uGrid;
// One texel per node: the distance mapped from [-kFakeFieldInside,
// kFakeFieldOutside] logical pixels in red, the unit normal mapped from
// [-1, 1] in green and blue.
uniform sampler2D uField;

layout(location = 0) out vec4 fragColor;

#include "fake_glass_lighting.glsl"

void main() {
  vec2 node = (FlutterFragCoord().xy - uGrid.xy) / uGrid.z;
  vec4 texel = texture(uField, (node + 0.5) / uNodes);
  float distance = mix(-kFakeFieldInside, kFakeFieldOutside, texel.r);
  vec2 normal = normalize(texel.gb * 2.0 - 1.0 + vec2(0.00001));
  // The layer clips the body to the field's edge, which covers its pixels.
  fragColor = fakeGlassLit(distance, normal, 1.0);
}
