// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FAKE_GLASS_LANES_GLSL
#define FAKE_GLASS_LANES_GLSL

uniform vec4 uFake[8];
#define uShapeType uFake[0].x
#define uCornerRadius uFake[0].y
#define uTint vec4(uFake[0].z, uFake[0].w, uFake[1].x, uFake[1].y)
#define uHighlight uFake[1].z
#define uHighlightWidth uFake[1].w
#define uHighlightWrap uFake[2].x
#define uOppositeHighlight uFake[2].y
#define uContourStrength uFake[2].z
#define uContourWidth uFake[2].w
#define uContourTransmittance uFake[3].x
#define uContourOffset uFake[3].y
#define uContourDirectionality uFake[3].z
#define uBevelStrength uFake[3].w
#define uBevelDepth uFake[4].x
#define uBevelOffset uFake[4].y
#define uBevelDirectionality uFake[4].z
#define uLightDirection vec2(uFake[4].w, uFake[5].x)
#define uPixelSize uFake[5].y
#define uExteriorOnly uFake[5].z
#define uGlintLuminance uFake[5].w
#define uFaceEmission uFake[6].xyz
#define uGlintFaceGain uFake[6].w
#define uGlintVibrancy uFake[7].x
#define uHighlightsOnly uFake[7].y
#define uBottomRadius uFake[7].z

#endif
