// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FINAL_LANES_GLSL
#define FINAL_LANES_GLSL

uniform highp vec4 uMatte[2];
#define uGeometryOffset uMatte[0].xy
#define uGeometrySize uMatte[0].zw
#define uMaterialCenter uMatte[1].xy
float uRefractionHeight = uMatte[1].z;
float uRefractionFits = uMatte[1].w;

uniform vec4 uFace[6];
#define uTint uFace[0]
float uDisplacementScale = uFace[1].x;
float uDispersion = uFace[1].y;
float uLightIntensity = uFace[1].z;
float uBackdropScale = uFace[1].w;
float uSaturation = uFace[2].x;
#define uContourAlpha uFace[2].y
float uRimReach = uFace[2].z;
float uHighlightWidth = uFace[2].w;
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

uniform vec4 uColorModelParams[18];
#define modelEmission(slot) uColorModelParams[(slot) * 6].xyz
#define modelTransmittance(slot) uColorModelParams[(slot) * 6].w
#define modelFaceTransfer(slot) uColorModelParams[(slot) * 6 + 1].xy
#define modelContourBoost(slot) uColorModelParams[(slot) * 6 + 1].z
#define modelBleedOpacity(slot) uColorModelParams[(slot) * 6 + 1].w
#define modelBleed(slot) uColorModelParams[(slot) * 6 + 2].xyz
#define modelToneGammaLuminance(slot) uColorModelParams[(slot) * 6 + 2].w
#define modelToneLow(slot) uColorModelParams[(slot) * 6 + 3]
#define modelToneHigh(slot) uColorModelParams[(slot) * 6 + 4]
#define modelGlint(slot) uColorModelParams[(slot) * 6 + 5].xyz

uniform highp vec4 uEffects[7];
#define uSolidBackdrop uEffects[0]
#define uGlowSpot uEffects[1]
#define uGlowBox uEffects[2]
#define uBackdropOverlay uEffects[3]
#define uBackdropPull uEffects[4]
#define uBackdropAberration uEffects[5].xy
#define uGlowWash uEffects[5].z
#define uBackdropReduced uEffects[5].w
#define uBackdropFrost uEffects[6].x

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
