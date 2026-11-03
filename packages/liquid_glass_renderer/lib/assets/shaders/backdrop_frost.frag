#version 460 core

// A LiquidGlassBackdropFrost drawn from an unblurred copy: the frost, then
// the color matrix on unpremultiplied color, as Impeller's blur and color
// filter compose. Drawn in the copy image's pixels, so the fragment
// coordinate is where the copy holds the fragment.

#include <flutter/runtime_effect.glsl>
#include "frost.glsl"

uniform vec2 uInvSize;
// The rect of the copy in the image, in its pixels, inset by half a pixel.
uniform vec4 uBounds;
// The frost, in the image's pixels.
uniform float uFrost;
// The color matrix's 4 x 4 part, column by column, and its offset as a
// share of full intensity.
uniform mat4 uMatrix;
uniform vec4 uOffset;

uniform sampler2D uCopy;

out vec4 fragColor;

void main() {
    vec4 color = frostTaps(
        uCopy,
        FlutterFragCoord().xy * uInvSize,
        uFrost,
        uInvSize,
        uBounds.xy * uInvSize,
        uBounds.zw * uInvSize
    );
    vec3 rgb = color.a > 0.0 ? color.rgb / color.a : vec3(0.0);
    vec4 filtered = clamp(uMatrix * vec4(rgb, color.a) + uOffset, 0.0, 1.0);
    fragColor = vec4(filtered.rgb * filtered.a, filtered.a);
}
