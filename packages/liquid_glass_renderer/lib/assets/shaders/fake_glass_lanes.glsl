// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FAKE_GLASS_LANES_GLSL
#define FAKE_GLASS_LANES_GLSL

uniform vec4 uFake[6];
#define uShapeType uFake[0].x
#define uCornerRadius uFake[0].y
#define uTint vec4(uFake[0].z, uFake[0].w, uFake[1].x, uFake[1].y)
#define uGlintStrength uFake[1].z
#define uGlintWidth uFake[1].w
#define uContourStrength uFake[2].x
#define uContourWidth uFake[2].y
#define uContourDirectionality uFake[2].z
#define uBevelStrength uFake[2].w
#define uBevelDepth uFake[3].x
#define uBevelOffset uFake[3].y
#define uPixelSize uFake[3].z
#define uExteriorOnly uFake[3].w
#define uGlintLuminance uFake[4].x
#define uFaceEmission uFake[4].yzw
#define uGlintFaceGain uFake[5].x
#define uGlintVibrancy uFake[5].y
#define uGlintOnly uFake[5].z
#define uBottomRadius uFake[5].w

#endif
