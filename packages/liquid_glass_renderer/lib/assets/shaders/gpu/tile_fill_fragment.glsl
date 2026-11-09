// Writes a geometry atlas's constant tiles and its table: the quad's value,
// its x channel stepping by ramp.y every texel from texel ramp.x, so one quad
// writes the entries of a whole run of ring tiles. With LOOKS each deep block
// writes look ramp.z (looks.glsl) beside it; a quad with a negative ramp.z
// writes none.

precision highp float;

#ifndef LOOKS
#define LOOKS 0
#endif

#if LOOKS
#include "looks.glsl"
#endif

flat in vec4 vValue;
flat in vec4 vRamp;

layout(location = 0) out vec4 fragColor;
#if LOOKS
#include "look_targets.glsl"
#endif

void main() {
    float column = floor(gl_FragCoord.x - vRamp.x);
    fragColor = vValue + vec4(vRamp.y * column, 0.0, 0.0, 0.0);
#if LOOKS
    writeLook(
        vRamp.z < 0.0
            ? Look(vec4(0.0), vec4(0.0), vec4(0.0))
            : lookAt(int(vRamp.z))
    );
#endif
}
