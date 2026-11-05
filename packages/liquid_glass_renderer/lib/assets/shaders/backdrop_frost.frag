#version 460 core

// A LiquidGlassBackdropFrost drawn from an unblurred copy: the frost, then
// the color matrix on unpremultiplied color, as Impeller's blur and color
// filter compose. Drawn in the copy image's pixels, or as the image filter
// of a layer whose top-left corner holds the copy, so the fragment
// coordinate times [uScale] is where the copy holds the fragment.

#include <flutter/runtime_effect.glsl>
#include "frost.glsl"

// The copy's texture size in pixels; an image filter's engine sets it.
uniform vec2 uSize;
// The rect of the copy in the image, in its pixels, inset by half a pixel.
uniform vec4 uBounds;
// The frost, in the image's pixels.
uniform float uFrost;
// The copy's pixels per fragment.
uniform float uScale;
// The rect the frost covers, in fragment coordinates: each pixel is
// covered as much as it lies inside.
uniform vec4 uShown;
// The color matrix's 4 x 4 part, column by column, and its offset as a
// share of full intensity.
uniform mat4 uMatrix;
uniform vec4 uOffset;

uniform sampler2D uCopy;

out vec4 fragColor;

void main() {
    vec2 fragment = FlutterFragCoord().xy;
    vec2 inside = clamp(
        min(fragment + 0.5, uShown.zw) - max(fragment - 0.5, uShown.xy),
        0.0,
        1.0
    );
    float coverage = inside.x * inside.y;
    if (coverage <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 invSize = 1.0 / uSize;
    vec2 uv = fragment * uScale * invSize;
    vec2 mirrored = invSize * frostMirror(fragment);
    vec2 lo = uBounds.xy * invSize;
    vec2 hi = uBounds.zw * invSize;
    vec4 color;
    if (uFrost > 2.8) {
        color = frostSixteen(uCopy, uv, uFrost, mirrored, lo, hi);
    } else {
        color = frostEight(uCopy, uv, uFrost, mirrored, lo, hi);
    }
    vec3 rgb = color.a > 0.0 ? color.rgb / color.a : vec3(0.0);
    vec4 filtered = clamp(uMatrix * vec4(rgb, color.a) + uOffset, 0.0, 1.0);
    fragColor = vec4(filtered.rgb * filtered.a, filtered.a) * coverage;
}
