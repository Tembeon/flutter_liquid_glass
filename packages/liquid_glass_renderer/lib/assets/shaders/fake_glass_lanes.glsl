// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FAKE_GLASS_LANES_GLSL
#define FAKE_GLASS_LANES_GLSL

uniform vec4 uFake[7];
#define uShapeType uFake[0].x
#define uCornerRadius uFake[0].y
#define uTint vec4(uFake[0].z, uFake[0].w, uFake[1].x, uFake[1].y)
#define uHighlight uFake[1].z
#define uHighlightWidth uFake[1].w
#define uHighlightWrap uFake[2].x
#define uOppositeHighlight uFake[2].y
#define uContourStrength uFake[2].z
#define uContourWidth uFake[2].w
#define uContourDirectionality uFake[3].x
#define uBevelStrength uFake[3].y
#define uBevelDepth uFake[3].z
#define uBevelOffset uFake[3].w
#define uBevelDirectionality uFake[4].x
#define uPixelSize uFake[4].y
#define uExteriorOnly uFake[4].z
#define uGlintLuminance uFake[4].w
#define uFaceEmission uFake[5].xyz
#define uGlintFaceGain uFake[5].w
#define uGlintVibrancy uFake[6].x
#define uHighlightsOnly uFake[6].y
#define uBottomRadius uFake[6].z

#endif
