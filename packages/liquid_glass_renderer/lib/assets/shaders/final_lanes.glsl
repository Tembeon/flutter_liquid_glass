// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FINAL_LANES_GLSL
#define FINAL_LANES_GLSL

uniform vec4 uFace[7];
#define uTint uFace[0]
float uDisplacementScale = uFace[1].x;
float uDispersion = uFace[1].y;
#define uFaceSpare uFace[1].z
float uLightIntensity = uFace[1].w;
float uBackdropScale = uFace[2].x;
float uSaturation = uFace[2].y;
#define uLightDirection uFace[2].zw
#define uHighlightColor uFace[3]
#define uContourColor uFace[4]
float uBevelShadowDirectionality = uFace[5].x;
float uRimReach = uFace[5].y;
float uHighlightWidth = uFace[5].z;
float uHighlightOppositeStrength = uFace[5].w;
float uEdgeWidth = uFace[6].x;
float uContourTransmittance = uFace[6].y;
float uContourDirectionality = uFace[6].z;
float uContourOffset = uFace[6].w;

uniform highp vec4 uProfile;
#define uMaterialCenter uProfile.xy
float uSpecularWrap = uProfile.z;
float uTransmissionGamma = uProfile.w;

uniform vec4 uMaterial[2];
float uVibrancy = uMaterial[0].x;
#define uTintAmount uMaterial[0].y
float uBevelShadowStrength = uMaterial[0].z;
float uBevelShadowDepth = uMaterial[0].w;
float uBevelShadowOffset = uMaterial[1].x;
#define uColorModelCode uMaterial[1].y
#define uVisibility uMaterial[1].z

uniform highp vec4 uMapping[3];
#define uFilterToMatteBasis uMapping[0]
#define uFilterToMatteOffset uMapping[1].xy
float uBlurFade = uMapping[1].z;
#define uBackdropBounds vec4(uMapping[1].w, uMapping[2].x, uMapping[2].y, uMapping[2].z)
#define uBackdropOriginX uMapping[2].w
uniform highp float uMappingEnd;

uniform highp vec4 uEffects[8];
#define uSolidBackdrop uEffects[0]
#define uGlowSpot uEffects[1]
#define uGlowBox uEffects[2]
#define uGlowWash uEffects[3].x
#define uGlowSpare uEffects[3].yzw
#define uEffectsSpare uEffects[4].xy
#define uBackdropReduced uEffects[4].z
#define uBackdropFrost uEffects[4].w
#define uBackdropOverlay uEffects[5]
#define uBackdropPull uEffects[6]
#define uBackdropAberration uEffects[7].xy

#if FROST_BAND
uniform highp vec4 uBand[5];
#define uBandRect uBand[0]
#define uBandFrost uBand[1].x
#define uBandFadeWhole uBand[1].y
#define uBandFadeGone uBand[1].z
#define uBandBrightness uBand[1].w
#define uBandFade uBand[2]
#define uBandHairlineRows uBand[3].xy
#define uBandHairlineAlpha uBand[3].z
#define uBandPresence uBand[3].w
#define uBandSaturation uBand[4].x
#define uBandHairlineColor uBand[4].yzw
#endif

#endif
