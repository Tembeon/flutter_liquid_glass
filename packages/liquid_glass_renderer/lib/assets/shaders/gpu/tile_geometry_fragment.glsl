// Evaluates the shapes for the texels of a geometry atlas's ring strips, one
// texel per buffer pixel, in the format of matte_encoding.glsl, and with
// LOOKS their look beside it (look_targets.glsl). The quad carries the
// buffer pixel of its first texel minus that texel's coordinate, so a
// texel's pixel center is gl_FragCoord plus that offset.

precision highp float;

#ifndef LOOKS
#define LOOKS 0
#endif
#define SCENE_LOOKS LOOKS

#include "sdf.glsl"
#include "matte_encoding.glsl"

flat in vec4 vValue;

layout(location = 0) out vec4 fragColor;
#if LOOKS
#include "look_targets.glsl"
#endif

void main() {
    vec2 position = gl_FragCoord.xy + vValue.xy;

    // A texel farther from every shape's box than the reach, the blend
    // budget and two pixels is past anything a read blends in.
    vec2 outsideBounds = sceneBoundsOutsideSquared(position, int(uNumShapes));
    float reach = uReachOutward + 2.0 + outsideBounds.y;
    if (outsideBounds.x > reach * reach) {
        fragColor = vec4(kFarInward, 0.0, 0.0, 0.0);
#if LOOKS
        writeLook(Look(vec4(0.0), vec4(0.0), vec4(0.0)));
#endif
        return;
    }

    SceneSample scene = sceneSample(position, int(uNumShapes));
    fragColor = encodeMatte(
        scene.distance,
        scene.opticalNormal,
        scene.halfMinor
    );
#if LOOKS
    writeLook(scene.look);
#endif
}
