// Evaluates the shapes for the texels of a geometry atlas's ring strips, in
// the format of matte_encoding.glsl, and with LOOKS their look beside it
// (look_targets.glsl). A texel spans vValue.z buffer pixels a side; the
// quad's xy carries where gl_FragCoord (0, 0) would sit, so a texel's center
// is the buffer point gl_FragCoord * vValue.z + vValue.xy. The quad's ramp
// lists the shapes its texels evaluate (listedSceneSample), or is negative
// where they evaluate every shape.

precision highp float;

#ifndef LOOKS
#define LOOKS 0
#endif
#define SCENE_LOOKS LOOKS

#include "sdf.glsl"
#include "matte_encoding.glsl"

flat in vec4 vValue;
flat in vec4 vRamp;

layout(location = 0) out vec4 fragColor;
#if LOOKS
#include "look_targets.glsl"
#endif

void main() {
    vec2 position = gl_FragCoord.xy * vValue.z + vValue.xy;

    bool listed = vRamp.x >= 0.0;
    // A texel farther from every shape's box than the reach, the blend
    // budget and two texels is past anything a read blends in.
    float outsideSquared = listed
        ? listedBoundsOutsideSquared(position, vRamp)
        : sceneBoundsOutsideSquared(position, int(uNumShapes));
    float reach = uReachOutward + 2.0 * vValue.z + uSmoothingBudget;
    if (outsideSquared > reach * reach) {
        fragColor = vec4(kFarInward, 0.0, 0.0, 0.0);
#if LOOKS
        writeLook(Look(vec4(0.0), vec4(0.0), vec4(0.0)));
#endif
        return;
    }

    SceneSample scene;
    if (listed) {
        scene = listedSceneSample(position, vRamp);
    } else {
        scene = sceneSample(position, int(uNumShapes));
    }
    fragColor = encodeMatte(
        scene.distance,
        scene.opticalNormal,
        scene.halfMinor
    );
#if LOOKS
    writeLook(scene.look);
#endif
}
