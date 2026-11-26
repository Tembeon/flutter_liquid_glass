// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FINAL_LANES_GLSL
#define FINAL_LANES_GLSL

uniform highp vec4 uGeometry[2];
#define uGeometryOffset uGeometry[0].xy
#define uGeometrySize uGeometry[0].zw
#define uMaterialCenter uGeometry[1].xy
float uRefractionHeight = uGeometry[1].z;
float uRefractionFits = uGeometry[1].w;

uniform vec4 uFace[6];
#define uTint uFace[0]
float uRefractionAmount = uFace[1].x;
float uDispersion = uFace[1].y;
float uGlintStrength = uFace[1].z;
float uBackdropScale = uFace[1].w;
float uSaturation = uFace[2].x;
#define uContourAlpha uFace[2].y
float uRimReach = uFace[2].z;
float uGlintWidth = uFace[2].w;
float uEdgeWidth = uFace[3].x;
float uContourDirectionality = uFace[3].y;
float uVibrancy = uFace[3].z;
float uBevelShadowStrength = uFace[3].w;
float uBevelShadowDepth = uFace[4].x;
float uBevelShadowOffset = uFace[4].y;
#define uColorModelCode uFace[4].z
#define uVisibility uFace[4].w
float uBlurFade = uFace[5].x;
float uTransmissionGamma = uFace[5].y;
float uReadDepth = uFace[5].z;

uniform highp vec4 uMapping[3];
#define uFilterToMatteBasis uMapping[0]
#define uBackdropBounds uMapping[1]
#define uFilterToMatteOffset uMapping[2].xy
#define uBackdropOrigin uMapping[2].zw

uniform vec4 uRecipes[27];
#define recipeFace(slot) uRecipes[(slot) * 9].xyz
#define recipeFaceRollOff(slot) uRecipes[(slot) * 9].w
#define recipeFaceFill(slot) uRecipes[(slot) * 9 + 1]
#define recipeBleed(slot) uRecipes[(slot) * 9 + 2].xyz
#define recipeBleedOpacity(slot) uRecipes[(slot) * 9 + 2].w
#define recipeTintRamp(slot) uRecipes[(slot) * 9 + 3]
#define recipeBrighten(slot) uRecipes[(slot) * 9 + 4].xyz
#define recipeHighlightOpacity(slot) uRecipes[(slot) * 9 + 4].w
#define recipeHighlightWidth(slot) uRecipes[(slot) * 9 + 5].x
#define recipeHighlightDiffuseWidth(slot) uRecipes[(slot) * 9 + 5].y
#define recipeHighlightCurvature(slot) uRecipes[(slot) * 9 + 5].z
#define recipeTintLumaWeight(slot) uRecipes[(slot) * 9 + 5].w
#define recipeHighlightSpread(slot) uRecipes[(slot) * 9 + 6].xy
#define recipeHighlightDiffuseBias(slot) uRecipes[(slot) * 9 + 6].z
#define recipeTintFloor(slot) uRecipes[(slot) * 9 + 6].w
#define recipeSpecularBias(slot) uRecipes[(slot) * 9 + 7].x
#define recipeSpecularWidth(slot) uRecipes[(slot) * 9 + 7].y
#define recipeSpecularColorBias(slot) uRecipes[(slot) * 9 + 7].z
#define recipeSpecularSpread(slot) uRecipes[(slot) * 9 + 7].w
#define recipeRingOpacity(slot) uRecipes[(slot) * 9 + 8].x
#define recipeRingOffset(slot) uRecipes[(slot) * 9 + 8].y
#define recipeRingStroke(slot) uRecipes[(slot) * 9 + 8].z
#define recipeRingInverseRadius(slot) uRecipes[(slot) * 9 + 8].w

uniform highp vec4 uEffects[5];
#define uSolidBackdrop uEffects[0]
#define uGlowSpot uEffects[1]
#define uGlowBox uEffects[2]
#define uBackdropPull uEffects[3]
#define uBackdropAberration uEffects[4].xy
#define uGlowWash uEffects[4].z
#define uBackdropReduced uEffects[4].w

uniform highp vec4 uCopy[6];
#define uLevelTexels uCopy[0].x
#define uLevelGrid uCopy[0].yz
#define uLevelCopyAt vec2(uCopy[0].w, uCopy[1].x)
#define uLevelRow uCopy[1].y
#define uLevelBlurAt uCopy[1].z
#define uLevelWidth uCopy[1].w
#define uLevelShare uCopy[2].x
#define uLevelFinest uCopy[2].y
#define uLevelCoarsest uCopy[2].z
#define uBlurSigmas vec4(uCopy[2].w, uCopy[3].x, uCopy[3].y, uCopy[3].z)
#define uBlurDepths vec3(uCopy[3].w, uCopy[4].x, uCopy[4].y)
#define uFillInverseStride uCopy[4].z
#define uFillMix vec3(uCopy[4].w, uCopy[5].x, uCopy[5].y)
#define uFillOffset uCopy[5].zw

#if FROST_BAND
uniform highp vec4 uBand[5];
#define uBandRect uBand[0]
#define uBandFrost uBand[1].x
#define uBandFadeWhole uBand[1].y
#define uBandFadeGone uBand[1].z
#define uBandLighten uBand[1].w
#define uBandFade uBand[2]
#define uBandHairlineRows uBand[3].xy
#define uBandHairlineAlpha uBand[3].z
#define uBandPresence uBand[3].w
#define uBandSaturation uBand[4].x
#define uBandHairlineColor uBand[4].yzw
#endif

#if !COMPUTED_SHAPE
uniform highp vec4 uAtlasPlace;
#define uAtlasTableOrigin uAtlasPlace.xy
#define uAtlasTextureSize uAtlasPlace.zw
#endif

#endif
