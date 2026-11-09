// The shapes of one atlas draw and their looks, as
// FlutterGpuGeometryRenderer writes them.

#ifndef GEOMETRY_UNIFORMS_GLSL
#define GEOMETRY_UNIFORMS_GLSL

#define MAX_SHAPES 16

layout(std140) uniform GeometryUniforms {
    vec4 uShapeData[MAX_SHAPES * 3];
    vec4 uRseData[MAX_SHAPES * 6];
    vec4 uShapeBounds[MAX_SHAPES];
    // Entry i: the look of shape i (looks.glsl), or of look i in the fill
    // pass.
    vec4 uLookTints[MAX_SHAPES];
    vec4 uLookResponses[MAX_SHAPES];
} geometryUniforms;

#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData
#define uShapeBounds geometryUniforms.uShapeBounds
#define uLookTints geometryUniforms.uLookTints
#define uLookResponses geometryUniforms.uLookResponses

#endif
