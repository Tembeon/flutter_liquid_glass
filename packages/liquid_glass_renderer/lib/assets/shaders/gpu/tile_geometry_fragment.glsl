// Evaluates the shapes for the texels of a geometry atlas's ring strips, one
// texel per buffer pixel, in the format of matte_encoding.glsl. The quad
// carries the buffer pixel of its first texel minus that texel's coordinate,
// so a texel's pixel center is gl_FragCoord plus that offset.

precision highp float;

#define MAX_SHAPES 16

// The prefix of material_gradient_fragment.glsl's block, so one buffer
// serves both.
layout(std140) uniform GeometryUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    vec4 uShapeData[MAX_SHAPES * 3];
    vec4 uRseData[MAX_SHAPES * 6];
    vec4 uShapeTints[MAX_SHAPES];
    vec4 uShapeResponses[MAX_SHAPES];
    vec4 uShapeBounds[MAX_SHAPES];
} geometryUniforms;

#define uContourProps geometryUniforms.uContourProps
#define uNumShapes (geometryUniforms.uOpticalProps.w)
#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData
#define uShapeBounds geometryUniforms.uShapeBounds

#include "sdf.glsl"
#include "matte_encoding.glsl"

flat in vec4 vValue;

out vec4 fragColor;

void main() {
    vec2 position = gl_FragCoord.xy + vValue.xy;

    // A texel farther from every shape's box than the reach, the blend
    // budget and two pixels is past anything a read blends in.
    vec2 outsideBounds = sceneBoundsOutsideSquared(position, int(uNumShapes));
    float reach = uContourProps.x + 2.0 + outsideBounds.y;
    if (outsideBounds.x > reach * reach) {
        fragColor = vec4(kFarInward, 0.0, 0.0, 0.0);
        return;
    }

    SceneSample scene = sceneSample(position, int(uNumShapes));
    fragColor = encodeMatte(
        scene.distance,
        scene.opticalNormal,
        scene.halfMinor
    );
}
