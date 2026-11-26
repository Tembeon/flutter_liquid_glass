// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FAKE_GLASS_LANES_GLSL
#define FAKE_GLASS_LANES_GLSL

uniform vec4 uFake[9];
#define uShapeType uFake[0].x
#define uCornerRadius uFake[0].y
#define uTint vec4(uFake[0].z, uFake[0].w, uFake[1].x, uFake[1].y)
#define uGlintStrength uFake[1].z
#define uContourStrength uFake[1].w
#define uContourWidth uFake[2].x
#define uContourDirectionality uFake[2].y
#define uBevelStrength uFake[2].z
#define uPixelSize uFake[2].w
#define uOuterBandOnly uFake[3].x
#define uFaceEmission uFake[3].yzw
#define uLightOnly uFake[4].x
#define uBottomRadius uFake[4].y
#define uHighlightOpacity uFake[4].z
#define uHighlightWidth uFake[4].w
#define uHighlightDiffuseWidth uFake[5].x
#define uHighlightSpread uFake[5].yz
#define uHighlightDiffuseBias uFake[5].w
#define uHighlightCurvature uFake[6].x
#define uHighlightLift uFake[6].y
#define uRingOpacity uFake[6].z
#define uRingOffset uFake[6].w
#define uRingStroke uFake[7].x
#define uRingInverseRadius uFake[7].y
#define uSpecularStrength uFake[7].z
#define uSpecularWidth uFake[7].w
#define uSpecularSpread uFake[8].x
#define uSpecularBias uFake[8].y

#endif
