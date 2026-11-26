// Copyright 2025, Tim Lehmann for whynotmake.it

// Refraction is evaluated in global filter coordinates: the affine mapping and
// everything that holds a position stay highp, as mediump turns the coordinate
// subtraction into visible shimmer on large layers. The rest is mediump, which
// fits the shader in the 32 registers a Mali GPU runs at full occupancy.
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "shader_constants.glsl"
#include "contour.glsl"
#include "rim_light.glsl"
#include "render.glsl"
#include "glass_glow.glsl"
#if FROST_BAND
#include "frost.glsl"
#endif

uniform highp vec2 uSize;

// The floats Dart writes, four to a vec4: impellerc gives every uniform
// declaration its own Metal buffer, bound per draw, where Vulkan binds one
// struct.
#include "final_lanes.glsl"
#include "copy_levels.glsl"
#define uRefractionFitsShape (uRefractionFits > 0.5)

// The scroll edge's fade over what the glass reads, premultiplied: none
// without a band.
#if FROST_BAND
#define backdropFade uBandFade
#else
const vec4 backdropFade = vec4(0.0);
#endif

#if COMPUTED_SHAPE
#include "shape_geometry.glsl"
#endif

// The fitted/default CA range is below the pixel response of the backdrop
// sampler: the pinned three-scene scan found no score or decoded-image gain
// through |CA| = .01. Bound the fast path by the maximum displacement,
// rather than by CA alone, so a large-refraction surface does not silently lose
// visible dispersion. The threshold is a conservative quarter-pixel total
// red-to-blue spread (an eighth pixel on either side of green).
const float kDispersionSubpixelThreshold = 0.25;

uniform sampler2D uBackgroundTexture;
#if !COMPUTED_SHAPE
uniform sampler2D uAtlas;
uniform sampler2D uAtlasTable;
#endif
#if KIND != KIND_SINGLE
uniform sampler2D uLookTint;
#endif
#if KIND == KIND_MATERIAL
uniform sampler2D uLookResponse;
uniform sampler2D uLookWeights;
#endif

layout(location = 0) out vec4 fragColor;

#if FROST_BAND
vec4 bandColor(highp vec2 fragment) {
    vec2 inside = clamp(
        min(fragment + 0.5, uBandRect.zw) - max(fragment - 0.5, uBandRect.xy),
        0.0,
        1.0
    );
    float coverage = inside.x * inside.y;
    if (coverage <= 0.0) return vec4(0.0);
    highp vec2 invSize = 1.0 / uSize;
    highp float copyScale = 1.0 / max(uBackdropReduced, 1.0);
    highp vec2 halfTexel = invSize * 0.5;
    vec4 color = frostEight(
        uBackgroundTexture,
        fragment * invSize * copyScale,
        uBandFrost,
        invSize * copyScale * frostMirror(fragment),
        halfTexel * copyScale,
        (vec2(1.0) - halfTexel) * copyScale
    );
    vec3 rgb = color.rgb;
    float luminance = dot(rgb, LUMA_WEIGHTS);
    rgb = clamp(mix(vec3(luminance), rgb, uBandSaturation) + uBandBrightness * color.a, 0.0, 1.0);
    float whole = clamp(
        (fragment.y - uBandFadeGone) / (uBandFadeWhole - uBandFadeGone),
        0.0,
        1.0
    );
    // The frost dissolves into what lies under it where the fade does, with
    // no slope at either end.
    vec4 filtered = vec4(rgb, color.a) * uBandPresence * frostEase(whole);
    vec4 fade = uBandFade * whole;
    if (fragment.y >= uBandHairlineRows.x && fragment.y < uBandHairlineRows.y) {
        vec4 line = vec4(uBandHairlineColor * uBandHairlineAlpha, uBandHairlineAlpha) * uBandPresence;
        fade = line + fade * (1.0 - line.a);
    }
    return (fade + filtered * (1.0 - fade.a)) * coverage;
}

vec4 bandRim(highp vec2 fragment) {
    highp vec2 uv = fragment / uSize / max(uBackdropReduced, 1.0);
    vec4 color = texture(uBackgroundTexture, uv);
    vec4 fade = uBandFade;
    return fade + color * (1.0 - fade.a);
}
#define EMPTY_FRAGMENT bandColor(FlutterFragCoord().xy - uBackdropOrigin)
#else
#define EMPTY_FRAGMENT vec4(0.0)
#endif

// The face under a bleed (see BleedRecipe): pulled toward levels of the
// backdrop by the fourth power of its own luminance, or of what it lacks to
// white, or of a blend of the two where recipes of both kinds merge
// (onBright is the part of bleed.w that takes the bright parts). The veil
// is the backdrop the face shows, where iOS reads a wide blur of what lies
// outside the glass.
vec3 applyBleed(
    vec3 face,
    vec3 backdrop,
    float backdropLuminance,
    vec4 bleed,
    float onBright
) {
    if (bleed.w < 1e-4) {
        return face;
    }
    vec3 matrix = bleed.xyz / bleed.w;
    float weight = clamp(dot(face, LUMA_WEIGHTS), 0.0, 1.0);
    weight = mix(1.0 - weight, weight, onBright / bleed.w);
    weight *= weight;
    return mix(
        face,
        vec3(mix(matrix.x, matrix.y, backdropLuminance)) +
            (backdrop - backdropLuminance) * matrix.z,
        weight * weight * bleed.w
    );
}

#if COLOR_MODELS != COLOR_MODELS_DIRECT
#include "recipe_edges.glsl"

// A lane of the glass's recipe: slot 0's, or the slots' blended by the
// weights of the recipes, which sum to one.
#if COLOR_MODELS == COLOR_MODELS_IOS27
#define RECIPE(lane) lane(0)
#else
vec3 gRecipeWeights = vec3(1.0, 0.0, 0.0);
#define RECIPE(lane) ( \
    gRecipeWeights.x * lane(0) + \
    gRecipeWeights.y * lane(1) + \
    gRecipeWeights.z * lane(2))
#endif

// Levels black..white of the luma and a gain on the chroma, on
// sRGB-encoded values.
vec3 levels(vec3 c, vec3 blackWhiteSaturation) {
    float luma = dot(c, LUMA_WEIGHTS);
    return vec3(mix(blackWhiteSaturation.x, blackWhiteSaturation.y, luma)) +
        (c - luma) * blackWhiteSaturation.z;
}

// The recipe's face over what the glass shows: the luma rolls off toward
// the brightest the face lets it get, with a lift of chroma where it does,
// then the face's levels, then its fill.
vec3 recipeFaceOf(vec3 c) {
    vec3 face = RECIPE(recipeFace);
    float luma = dot(c, LUMA_WEIGHTS);
    float kept = clamp(1.0 - luma * RECIPE(recipeFaceRollOff), 0.0, 1.0);
    vec3 shown = vec3(mix(face.x, face.y, kept * luma)) +
        (c - luma) * (kept * (1.0 + 0.3 * (1.0 - kept)) * face.z);
    vec4 fill = RECIPE(recipeFaceFill);
    return shown * (1.0 - fill.a) + fill.rgb;
}

// The recipe's bleed over [face], from the [backdrop] the face shows.
vec3 recipeBleedOf(vec3 face, vec3 backdrop, float backdropLuminance) {
    #if COLOR_MODELS == COLOR_MODELS_IOS27
    float opacity = recipeBleedOpacity(0);
    vec4 bleed = vec4(recipeBleed(0), 1.0) * abs(opacity);
    float onBright = max(-opacity, 0.0);
    #else
    vec4 bleed = vec4(0.0);
    float onBright = 0.0;
    for (int slot = 0; slot < COLOR_MODEL_SLOTS; slot++) {
        float opacity = recipeBleedOpacity(slot);
        bleed += gRecipeWeights[slot] * vec4(recipeBleed(slot), 1.0) *
            abs(opacity);
        onBright += gRecipeWeights[slot] * max(-opacity, 0.0);
    }
    #endif
    return applyBleed(face, backdrop, backdropLuminance, bleed, onBright);
}

// The recipe's tint over the face [c]: each channel runs between the
// tint's tones over black and over white as the face's luma (or the
// channel) does, its brightest channel at most 1.2, over the face by the
// tint's opacity.
vec3 recipeTintOf(vec3 c, vec4 tint) {
    vec4 ramp = RECIPE(recipeTintRamp);
    vec3 low = max(vec3(RECIPE(recipeTintFloor)), ramp.x * tint.rgb + ramp.y);
    vec3 high = ramp.z * tint.rgb + ramp.w;
    vec3 by = mix(c, vec3(dot(c, LUMA_WEIGHTS)), RECIPE(recipeTintLumaWeight));
    vec3 tinted = low + (high - low) * by;
    float most = max(max(tinted.r, tinted.g), tinted.b);
    return mix(c, tinted * (most > 1.2 ? 1.2 / most : 1.0), tint.a);
}

// The rim highlight over the face [c] at [depth] device pixels inside the
// edge, whose outward normal is [normal]: a line and a diffuse glow lit
// from above and below that brighten the face.
vec3 recipeHighlightOf(vec3 c, float depth, vec2 normal) {
    float mask = rimHighlight(
        depth,
        normal,
        1.0,
        RECIPE(recipeHighlightWidth),
        RECIPE(recipeHighlightDiffuseWidth),
        RECIPE(recipeHighlightSpread),
        RECIPE(recipeHighlightDiffuseBias),
        RECIPE(recipeHighlightCurvature)
    ) * RECIPE(recipeHighlightOpacity);
    if (mask <= 0.0) return c;
    vec3 lit = levels(c, RECIPE(recipeBrighten));
    float most = max(max(lit.r, lit.g), lit.b);
    return mix(c, lit * (most > 1.2 ? 1.2 / most : 1.0), mask);
}

// How dark the ring shadow is at [depth] device pixels inside the edge of
// glass [halfSide] device pixels from its middle.
float recipeRingOf(float depth, vec2 normal, float halfSide) {
    return ringShadowAcross(
        depth,
        normal,
        halfSide,
        RECIPE(recipeRingOpacity),
        RECIPE(recipeRingOffset),
        RECIPE(recipeRingStroke),
        RECIPE(recipeRingInverseRadius)
    );
}

// How strongly the dark specular darkens at [depth] device pixels inside
// the edge, negative outside.
float recipeSpecularOf(float depth, vec2 normal) {
    return darkSpecular(
        depth,
        normal,
        1.0,
        RECIPE(recipeSpecularWidth),
        RECIPE(recipeSpecularSpread),
        RECIPE(recipeSpecularBias)
    );
}

// How far outside the glass a recipe draws, in device pixels: its dark
// specular band and the half pixel past it.
float recipeOutset() {
    #if COLOR_MODELS == COLOR_MODELS_IOS27
    return recipeSpecularWidth(0) + 0.5;
    #else
    return max(
        max(recipeSpecularWidth(0), recipeSpecularWidth(1)),
        recipeSpecularWidth(2)
    ) + 0.5;
    #endif
}
#endif

float contourIntegral(float t) {
    return contourIntegral(t, uEdgeWidth);
}

// Border coverage of the pixel, split at the silhouette: x lies outside the
// material and is composited over the backdrop, y lies inside it.
vec2 contourCoverage(float signedEdgeDistance) {
    if (uEdgeWidth <= 0.0) {
        return vec2(0.0);
    }
    float outward = -signedEdgeDistance;
    float lower = outward - 0.5;
    float upper = outward + 0.5;
    return vec2(
        contourIntegral(max(upper, 0.0)) - contourIntegral(max(lower, 0.0)),
        contourIntegral(min(upper, 0.0)) - contourIntegral(min(lower, 0.0))
    );
}

highp vec2 mirrorBackgroundUV(highp vec2 uv, highp vec2 inverseTextureSize) {
    // Image-filter sampler edge behavior differs between Impeller backends.
    // Preserve every coordinate inside the input texture exactly, and mirror
    // only displaced samples that genuinely leave it. This avoids GLES decal
    // black without clamping Metal samples into stretched edge pixels.
    highp vec2 mirrored = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
    highp vec2 halfTexel = inverseTextureSize * 0.5;
    return clamp(mirrored, halfTexel, vec2(1.0) - halfTexel);
}

highp vec2 filterDeltaFromMatteDelta(highp vec2 matteDelta, highp vec4 basis) {
    highp float determinant = basis.x * basis.w - basis.y * basis.z;
    if (abs(determinant) < 1e-6) {
        return vec2(0.0);
    }
    return vec2(
        basis.w * matteDelta.x - basis.y * matteDelta.y,
        -basis.z * matteDelta.x + basis.x * matteDelta.y
    ) / determinant;
}

highp vec2 mirrorIntoBackdrop(highp vec2 sourceOffset, highp vec2 matteCoord) {
    highp vec2 sampleMatte = matteCoord + vec2(
        dot(uFilterToMatteBasis.xy, sourceOffset),
        dot(uFilterToMatteBasis.zw, sourceOffset)
    );
    // Keep bilinear footprints off the uncaptured side of the edge.
    float margin = 0.5;
    highp vec2 lo = uBackdropBounds.xy + margin;
    highp vec2 hi = uBackdropBounds.zw - margin;
    if (all(greaterThanEqual(sampleMatte, lo)) &&
        all(lessThanEqual(sampleMatte, hi))) {
        return sourceOffset;
    }
    highp vec2 extent = max(hi - lo, vec2(0.0));
    highp vec2 mirrored = lo + extent - abs(extent - abs(sampleMatte - lo));
    mirrored = clamp(mirrored, lo, max(hi, lo));
    return sourceOffset + filterDeltaFromMatteDelta(
        mirrored - sampleMatte,
        uFilterToMatteBasis
    );
}

// From the nearest point of the material's long center line to
// [fromCenter], a point given from the material's center, in the matte.
highp vec2 fromCenterLine(highp vec2 fromCenter) {
    highp vec2 line = uBackdropPull.z > 0.0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    return fromCenter - line * clamp(
        dot(fromCenter, line),
        -abs(uBackdropPull.z),
        abs(uBackdropPull.z)
    );
}

vec3 applyGlint(
    vec3 baseColor,
    vec3 transmittedColor,
    float signedEdgeDistance,
    vec2 surfaceNormal
) {
    if (
        uGlintStrength < 0.01 &&
        uContourAlpha < 0.01 &&
        uBevelShadowStrength < 0.001
    ) {
        return baseColor;
    }

    float inwardDistance = max(signedEdgeDistance, 0.0);
    float outlineCoverage = contourCoverage(signedEdgeDistance).y /
        max(clamp(signedEdgeDistance + 0.5, 0.0, 1.0), 0.001);
    float profile = glintProfile(inwardDistance, uGlintWidth);

    if (
        outlineCoverage < 0.01 &&
        profile < 0.001 &&
        uBevelShadowStrength < 0.001
    ) {
        return baseColor;
    }

    float glint = rimGlint(uGlintStrength, surfaceNormal, profile);
    float shadow = 0.0;
    if (uBevelShadowStrength >= 0.001) {
        shadow = bevelShadow(
            inwardDistance,
            surfaceNormal,
            uBevelShadowDepth,
            uBevelShadowOffset,
            uBevelShadowStrength
        );
    }
    float edgeAbsorption = clamp(
        outlineCoverage *
            uContourAlpha *
            contourDirection(surfaceNormal, uContourDirectionality),
        0.0,
        1.0
    );
    vec3 result = baseColor * (1.0 - edgeAbsorption);
    // The shadow absorbs only light that came through the glass: the wash
    // emits the same over any backdrop, so over black the face is unshaded.
    result = max(
        result - transmittedColor * (1.0 - edgeAbsorption) * shadow,
        vec3(0.0)
    );
    // The glint recolors the lit face rather than adding white: it pulls
    // luminance toward a target above SDR white and amplifies the face's own
    // chroma, so glass over color glints in that color.
    float resultLuminance = dot(result, LUMA_WEIGHTS);
    vec3 glintTarget = vec3(kGlintLuminance) +
        (result - vec3(resultLuminance)) * kGlintVibrancy;
    // Only the lower bound is clamped: amplified chroma must not produce
    // negative (out-of-gamut) channels, while the upper side keeps its
    // headroom above SDR white for extended-range surfaces.
    result = max(mix(result, glintTarget, glint), vec3(0.0));

    return result;
}


#if !COMPUTED_SHAPE
// Where the atlas holds matte pixel position [pixel], from the geometry
// buffer's corner: the table names the atlas texel of the tile's first pixel
// and how many texels a pixel spans (1, a fraction where the tile is coarse,
// 0 for a constant tile). A tile's strip carries a texel of apron on each
// side, so the filtered read never blends in another tile's texels.
highp vec2 atlasPoint(highp vec2 pixel) {
    highp vec2 tile = min(
        floor(pixel / ATLAS_TILE_SIZE),
        ceil(uGeometrySize / ATLAS_TILE_SIZE) - 1.0
    );
    highp vec3 entry = texture(
        uAtlasTable,
        (uAtlasTableOrigin + tile + 0.5) / uAtlasTextureSize
    ).xyz;
    return (entry.xy + (pixel - tile * ATLAS_TILE_SIZE) * entry.z) /
        uAtlasTextureSize;
}
#endif

// The surface direction (xy) and refraction strength (z) of a geometry
// texel, which stores the direction with its length set to the strength.
vec3 surfaceOf(vec4 geometry) {
    float strength = length(geometry.yz);
    return vec3(
        strength > 0.0001 ? geometry.yz / strength : vec2(0.0),
        strength
    );
}

// Whether a pixel [signedEdgeDistance] outside the glass draws: in the
// direct model's contour or a recipe's dark specular band.
bool drawsOutside(float signedEdgeDistance) {
    #if COLOR_MODELS != COLOR_MODELS_IOS27
    if (contourCoverage(signedEdgeDistance).x * uContourAlpha >= 0.01) {
        return true;
    }
    #endif
    #if COLOR_MODELS != COLOR_MODELS_DIRECT
    return -signedEdgeDistance < recipeOutset();
    #else
    return false;
    #endif
}

// The sigma, in device pixels, the glass blurs what it shows by at
// [depth] in a shape [halfSide] deep: the ramp from the deepest stop, at
// the shape's middle, through the others, linear between them.
highp float blurSigma(float depth, float halfSide) {
    vec3 deeper = vec3(halfSide, uBlurDepths.xy);
    vec3 shallower = uBlurDepths;
    vec3 along = clamp(
        (depth - shallower) / max(deeper - shallower, 1e-3),
        0.0,
        1.0
    );
    return uBlurSigmas.w + dot(uBlurSigmas.xyz - uBlurSigmas.yzw, along);
}

#if PLAIN_INTERIOR
// How deep a pixel needs no bevel and no rim light. Glass that carries
// anything else over its whole face never takes this path.
float plainInteriorDepth() {
    bool plain = abs(uBackdropScale - 1.0) <= 0.0001 &&
        uBackdropPull.x <= 0.0 &&
        max(uBlurSigmas.x, uBlurSigmas.y) <= 0.0 &&
        uTint.a < 0.001 &&
        uVisibility >= 1.0 &&
        uGlowSpot.w <= 0.0 &&
        uGlowWash <= 0.0 &&
        uSolidBackdrop.a <= 0.5 &&
        backdropFade.a <= 0.0;
    return plain ? uReadDepth : 32000.0;
}
#endif

// How far the backdrop is shifted at this pixel, in px, toward the inside of
// the shape. The glass is flat in the middle with a rounded (quarter-circle)
// bevel at the edge, and the bevel gets narrower on smaller shapes
// (GlassShift's caps).
float displacementMagnitude(
    float inward,
    float halfMinor,
    float shortening
) {
    float refractionHeight = uRefractionHeight;
    float bevel;
    float amount;
    if (uRefractionFitsShape) {
        bevel = min(refractionHeight, kFittedBevel * halfMinor);
        amount = min(uRefractionAmount, kFittedShift * halfMinor);
    } else {
        bevel = min(refractionHeight, kClearBevel * halfMinor);
        amount = min(uRefractionAmount, kClearShift * halfMinor);
    }
    float bevelX = 1.0 - clamp(max(inward, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float magnitude = bevel > 0.001
        ? amount * (1.0 - sqrt(1.0 - bevelX * bevelX)) * shortening
        : 0.0;
    return clamp(magnitude, 0.0, uRefractionAmount);
}

// How far and which way the backdrop pull reads from [fromCenter], a point
// given from the material's center, in the matte: out of a capsule of the
// material, by a quarter circle as the bevel's.
highp vec2 pullOf(highp vec2 fromCenter) {
    highp vec2 fromLine = fromCenterLine(fromCenter);
    highp float reach = length(fromLine);
    if (uBackdropPull.x <= 0.0 || reach <= 0.001) {
        return vec2(0.0);
    }
    float pullX = clamp(
        1.0 - (uBackdropPull.w - reach) / uBackdropPull.y,
        0.0,
        1.0
    );
    return fromLine *
        (uBackdropPull.x * (1.0 - sqrt(1.0 - pullX * pullX)) / reach);
}

#if ABERRATION
// From [fromCenter] to what the glass shows there, in the matte, with the
// glass taken for a capsule of the material: its bevel, then the pull of
// the point the bevel reads, and nothing past the capsule's edge, where
// the backdrop shows as it is. What a read beside the fragment takes,
// which has the geometry of the fragment alone.
highp vec2 capsuleSourceOffset(highp vec2 fromCenter, float visibility) {
    highp vec2 fromLine = fromCenterLine(fromCenter);
    highp float reach = length(fromLine);
    highp float depth = uBackdropPull.w - reach;
    if (reach <= 0.001) {
        return vec2(0.0);
    }
    highp vec2 bevel = fromLine * (
        -displacementMagnitude(depth, uBackdropPull.w, 1.0) / reach
    );
    return (bevel + pullOf(fromCenter + bevel)) *
        (visibility * clamp(depth + 0.5, 0.0, 1.0));
}
#endif

void main() {
    highp vec2 fragCoord = FlutterFragCoord().xy - uBackdropOrigin;
    highp vec2 screenUV = fragCoord / uSize;

    highp vec2 matteCoord = vec2(
        dot(uFilterToMatteBasis.xy, fragCoord),
        dot(uFilterToMatteBasis.zw, fragCoord)
    ) + uFilterToMatteOffset;
    highp vec2 geometryUV = (matteCoord - uGeometryOffset) / uGeometrySize;

    if (
        any(lessThan(geometryUV, vec2(0.0))) ||
        any(greaterThan(geometryUV, vec2(1.0)))
    ) {
        fragColor = EMPTY_FRAGMENT;
        return;
    }

    #if COMPUTED_SHAPE
    vec4 geometryTexel = shapeTexel(matteCoord - uGeometryOffset, uReadDepth);
    #else
    highp vec2 atlasUV = atlasPoint(matteCoord - uGeometryOffset);
    vec4 geometryTexel = texture(uAtlas, atlasUV);
    #endif
    #if PLAIN_INTERIOR
    if (geometryTexel.x > plainInteriorDepth()) {
        vec3 backdrop;
        #ifndef IMPELLER_TARGET_OPENGLES
        if (uBackdropReduced == 0.0) {
            backdrop = texelFetch(
                uBackgroundTexture,
                ivec2(floor(fragCoord)),
                0
            ).rgb;
        } else
        #endif
        {
            highp vec2 halfTexel = 0.5 / uSize;
            backdrop = texture(
                uBackgroundTexture,
                clamp(screenUV, halfTexel, vec2(1.0) - halfTexel) /
                    max(uBackdropReduced, 1.0)
            ).rgb;
        }
        if (uFillInverseStride > 0.0) {
            backdrop = fillMix(
                backdrop,
                levelFill(
                    uBackgroundTexture,
                    screenUV / max(uBackdropReduced, 1.0)
                ).rgb
            );
        }
        fragColor = vec4(
            clamp(
                recipeBleedOf(
                    recipeFaceOf(backdrop),
                    backdrop,
                    dot(backdrop, LUMA_WEIGHTS)
                ),
                0.0,
                1.0
            ),
            1.0
        );
        return;
    }
    #endif
    vec4 materialTint = uTint;
    float appearanceVisibility = clamp(uVisibility, 0.0, 1.0);
    vec4 colorModelWeights = colorModelWeightsOf(uColorModelCode);
    #if KIND != KIND_SINGLE
    {
        vec4 tint = texture(uLookTint, atlasUV);
        materialTint = vec4(
            tint.a > 0.0001 ? tint.rgb / tint.a : vec3(0.0),
            tint.a
        );
    }
    #endif
    #if KIND == KIND_MATERIAL
    {
        vec4 response = texture(uLookResponse, atlasUV);
        uSaturation = response.x;
        uTransmissionGamma = response.y;
        uVibrancy = response.z;
        appearanceVisibility = clamp(response.w, 0.0, 1.0);
        colorModelWeights = texture(uLookWeights, atlasUV);
    }
    #endif
    // Weight of the material over the refracted backdrop. Frosted glass
    // renders the material in full and its alpha fades it with the frost;
    // opaque unfrosted glass fades it here. Either way it fades linearly,
    // never twice.
    float materialVisibility = mix(appearanceVisibility, 1.0, uBlurFade);

    // Positive inside. It is a smooth value rather than a rounded byte, so
    // the antialiased edge below stays one pixel wide.
    float signedEdgeDistance = geometryTexel.x;
    // Box-filtered coverage of one physical pixel, as Core Animation
    // rasterizes the silhouette: a pixel-aligned edge stays hard, so the
    // glint's first row is not diluted by a wider feather.
    float materialAlpha = clamp(signedEdgeDistance + 0.5, 0.0, 1.0);
    if (materialAlpha < 0.01 && !drawsOutside(signedEdgeDistance)) {
        fragColor = EMPTY_FRAGMENT;
        return;
    }
    // The surface direction is only computed where something uses it: the
    // bevel, for refraction, and the rim lighting near the edge.
    vec2 surfaceNormal = vec2(0.0);
    bool hasSurfaceNormal = false;
    vec2 displacement = vec2(0.0);
    // The bevel is never wider than the refraction height, so deeper pixels
    // have no refraction and skip this.
    if (signedEdgeDistance < uRefractionHeight) {
        vec3 surface = surfaceOf(geometryTexel);
        float magnitude = displacementMagnitude(
            signedEdgeDistance,
            geometryTexel.w,
            surface.z
        );
        if (magnitude > 0.0) {
            surfaceNormal = surface.xy;
            hasSurfaceNormal = true;
            displacement = surfaceNormal * (-magnitude) * appearanceVisibility;
        }
    }

    highp vec2 invUSize = 1.0 / uSize;
    // From the copy's uv to its texture's.
    highp float copyScale = 1.0 / max(uBackdropReduced, 1.0);
    highp vec2 backdropScaleOffset = vec2(0.0);
    if (abs(uBackdropScale - 1.0) > 0.0001) {
        // backdropShrink is one lens over the whole face, uniform up to the
        // silhouette, about the material center. The bevel displacement adds
        // on top of it. It never enlarges: magnifiers re-render their content
        // instead (see the example's loupe).
        highp vec2 filterDeltaFromAnchor = filterDeltaFromMatteDelta(
            matteCoord - uMaterialCenter,
            uFilterToMatteBasis
        );
        float magnification = uBackdropScale;
        backdropScaleOffset =
            filterDeltaFromAnchor *
            (1.0 / magnification - 1.0) *
            appearanceVisibility;
    }
    if (uBackdropPull.x > 0.0) {
        // The bevel lies over the pulled backdrop, so the pull is the one
        // of the point the bevel reads.
        backdropScaleOffset += filterDeltaFromMatteDelta(
            pullOf(
                matteCoord + vec2(
                    dot(uFilterToMatteBasis.xy, displacement),
                    dot(uFilterToMatteBasis.zw, displacement)
                ) - uMaterialCenter
            ),
            uFilterToMatteBasis
        ) * appearanceVisibility;
    }
    vec4 refractColor;
    highp vec2 copyUV = vec2(0.0);
    if (uSolidBackdrop.a > 0.5) {
        // Refracting, frosting or splitting a uniform color returns it.
        refractColor = vec4(uSolidBackdrop.rgb, 1.0);
    } else if (
        abs(uDispersion) * uRefractionAmount <=
        kDispersionSubpixelThreshold
    ) {
        // Skip two texture reads only when the maximum channel separation is
        // subpixel. The uniform predicate stays coherent across the layer and
        // the displacement bound keeps this optimization valid for either CA
        // sign.
        highp vec2 sourceOffset = backdropScaleOffset + displacement;
        highp vec2 refractedUV;
        if (
            sourceOffset.x == 0.0 &&
            sourceOffset.y == 0.0 &&
            uBackdropReduced == 0.0
        ) {
            // Undisplaced glass fetches its own texel, bypassing the sampler,
            // so it reproduces the backdrop exactly even when the sampler is
            // bilinear (whose fixed-point sub-texel weights are never exactly
            // zero at texel centres).
            refractedUV = (floor(fragCoord) + 0.5) * invUSize;
            #ifdef IMPELLER_TARGET_OPENGLES
            // The GLES runtime stages also emit GLSL ES 1.00, which has no
            // texelFetch. The texel centre is exact under nearest sampling;
            // bilinear can differ by a few LSB at hard edges.
            refractColor = texture(uBackgroundTexture, refractedUV);
            #else
            refractColor = texelFetch(
                uBackgroundTexture,
                ivec2(floor(fragCoord)),
                0
            );
            #endif
        } else {
            refractedUV = screenUV +
                mirrorIntoBackdrop(sourceOffset, matteCoord) * invUSize;
            refractColor = texture(
                uBackgroundTexture,
                mirrorBackgroundUV(refractedUV, invUSize) * copyScale
            );
        }
        copyUV = mirrorBackgroundUV(refractedUV, invUSize) * copyScale;
        #if BLUR
        highp float sigma = blurSigma(
            signedEdgeDistance,
            geometryTexel.w
        ) / uLevelShare;
        if (sigma > 0.0 && uLevelCoarsest > 0.0) {
            refractColor = levelBlur(
                uBackgroundTexture,
                refractColor,
                copyUV,
                sigma
            );
        }
        #endif
    } else {
        float dispersionStrength = uDispersion * kDispersionSpread;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        highp vec2 redUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + redOffset,
                matteCoord
            ) * invUSize,
            invUSize
        );
        highp vec2 greenUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + displacement,
                matteCoord
            ) * invUSize,
            invUSize
        );
        highp vec2 blueUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + blueOffset,
                matteCoord
            ) * invUSize,
            invUSize
        );
        
        float red = texture(uBackgroundTexture, redUV * copyScale).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV * copyScale);
        float blue = texture(uBackgroundTexture, blueUV * copyScale).b;
        
        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
        copyUV = greenUV * copyScale;
    }
    if (uFillInverseStride > 0.0 && uSolidBackdrop.a <= 0.5) {
        refractColor.rgb = fillMix(
            refractColor.rgb,
            levelFill(uBackgroundTexture, copyUV).rgb
        );
    }
    #if ABERRATION
    if (uBackdropAberration.x > 0.0 && uSolidBackdrop.a <= 0.5) {
        // Seven reads of the glass a third of the amount apart along the
        // parting's way: red takes the three ahead, blue the three behind
        // and green the five in the middle, each weighted toward its far
        // end, and the parted color lies over the glass by the depth.
        highp vec2 fromCenter = matteCoord - uMaterialCenter;
        highp vec2 fromLine = fromCenterLine(fromCenter);
        highp float reach = length(fromLine);
        float parted = clamp(
            1.0 - (uBackdropPull.w - reach) / uBackdropAberration.y,
            0.0,
            1.0
        ) * appearanceVisibility;
        if (parted > 0.0 && reach > 0.001) {
            // The way is the edge's outward normal mirrored: out of the
            // glass up left and down right, into it up right and down left,
            // and nearly along the edge at the top, bottom and sides.
            highp vec2 third = vec2(
                dot(fromLine, kPartingMirror.xy),
                dot(fromLine, kPartingMirror.yz)
            ) * (uBackdropAberration.x / (3.0 * reach));
            vec3 taps[6];
            for (int i = 0; i < 6; i++) {
                highp vec2 beside = third * float(i < 3 ? i - 3 : i - 2);
                highp vec2 source = capsuleSourceOffset(
                    fromCenter + beside,
                    appearanceVisibility
                );
                taps[i] = texture(
                    uBackgroundTexture,
                    mirrorBackgroundUV(
                        screenUV + mirrorIntoBackdrop(
                            filterDeltaFromMatteDelta(
                                beside + source,
                                uFilterToMatteBasis
                            ),
                            matteCoord
                        ) * invUSize,
                        invUSize
                    ) * copyScale
                ).rgb;
            }
            refractColor.rgb = mix(
                refractColor.rgb,
                vec3(
                    dot(vec3(taps[3].r, taps[4].r, taps[5].r), kPartingSide),
                    dot(
                        vec3(
                            refractColor.g,
                            taps[2].g + taps[3].g,
                            taps[1].g + taps[4].g
                        ),
                        kPartingMiddle
                    ),
                    dot(vec3(taps[2].b, taps[1].b, taps[0].b), kPartingSide)
                ),
                parted
            );
        }
    }
    #endif
    if (backdropFade.a > 0.0) {
        refractColor.rgb =
            refractColor.rgb * (1.0 - backdropFade.a) + backdropFade.rgb;
    }
    
    #if COLOR_MODELS == COLOR_MODELS_IOS27
    float directWeight = 0.0;
    #elif COLOR_MODELS == COLOR_MODELS_DIRECT
    float directWeight = 1.0;
    #else
    float directWeight = colorModelWeights.x;
    #endif
    bool nearEdge = signedEdgeDistance < uRimReach;
    if (nearEdge && !hasSurfaceNormal) {
        surfaceNormal = surfaceOf(geometryTexel).xy;
    }
    vec3 litColor = vec3(0.0);
    float externalContourAlpha = 0.0;
    #if COLOR_MODELS != COLOR_MODELS_IOS27
    if (directWeight > 0.0) {
        vec3 transmittedColor = pow(
            max(refractColor.rgb, vec3(0.0)),
            vec3(max(uTransmissionGamma, 0.01))
        ) * (1.0 - materialTint.a);
        vec3 baseColor = applySaturation(
            materialTint.rgb * materialTint.a + transmittedColor,
            uSaturation
        );
        if (uVibrancy > 0.0) {
            float chroma = max(max(baseColor.r, baseColor.g), baseColor.b) -
                min(min(baseColor.r, baseColor.g), baseColor.b);
            baseColor = clamp(
                baseColor + vec3(chroma * max(uVibrancy, 0.0)),
                0.0,
                1.0
            );
        }
        litColor = baseColor;
        if (nearEdge) {
            litColor = applyGlint(
                baseColor,
                transmittedColor,
                signedEdgeDistance,
                surfaceNormal
            );
            externalContourAlpha =
                contourCoverage(signedEdgeDistance).x *
                uContourAlpha *
                contourDirection(surfaceNormal, uContourDirectionality) *
                appearanceVisibility *
                directWeight;
        }
    }
    #endif
    float specular = 0.0;
    #if COLOR_MODELS != COLOR_MODELS_DIRECT
    if (directWeight < 1.0) {
        #if COLOR_MODELS == COLOR_MODELS_ALL
        gRecipeWeights = colorModelWeights.yzw / (1.0 - directWeight);
        #endif
        // The glass's face and its bleed, clamped, then its ring shadow,
        // the tint and the rim highlight over it, as iOS composites them.
        vec3 face = recipeBleedOf(
            recipeFaceOf(refractColor.rgb),
            refractColor.rgb,
            dot(refractColor.rgb, LUMA_WEIGHTS)
        );
        face = clamp(face, 0.0, 1.0);
        if (nearEdge) {
            face *= 1.0 - recipeRingOf(
                signedEdgeDistance,
                surfaceNormal,
                geometryTexel.w
            );
        }
        if (materialTint.a >= 0.001) {
            face = recipeTintOf(face, materialTint);
        }
        // The ring reaches deepest; the highlight lies within its widest
        // band and the half pixel outside, the dark specular outside.
        if (nearEdge && signedEdgeDistance > -0.5 &&
            signedEdgeDistance < max(
                RECIPE(recipeHighlightWidth),
                RECIPE(recipeHighlightDiffuseWidth)
            ) + 0.5) {
            face = recipeHighlightOf(face, signedEdgeDistance, surfaceNormal);
        }
        if (nearEdge && signedEdgeDistance < 0.5) {
            specular = recipeSpecularOf(signedEdgeDistance, surfaceNormal) *
                appearanceVisibility *
                (1.0 - directWeight);
        }
        litColor = mix(face, litColor, directWeight);
    }
    #endif
    // The lit material cross-fades to the refracted backdrop, whose
    // refraction scales with visibility. Fading the output rather than each
    // parameter keeps coupled factors linear and monotonic.
    vec3 finalColor = mix(refractColor.rgb, litColor, materialVisibility);
    // The direct model's contour outside the material lies outside the
    // alpha fade, so it always scales with visibility.
    float fadeAlpha = mix(1.0, appearanceVisibility, uBlurFade);
    float visibleMaterialAlpha = materialAlpha * fadeAlpha;
    float alpha = visibleMaterialAlpha + externalContourAlpha;
#if GLOW
    // The matte coordinate is derived again, so no register holds it across
    // the shading.
    if (uGlowSpot.w > 0.0 || uGlowWash > 0.0) {
        highp vec2 glowCoord = FlutterFragCoord().xy - uBackdropOrigin;
        finalColor = applyGlassGlow(
            finalColor,
            vec2(
                dot(uFilterToMatteBasis.xy, glowCoord),
                dot(uFilterToMatteBasis.zw, glowCoord)
            ) + uFilterToMatteOffset,
            uGlowSpot,
            uGlowBox,
            uGlowWash
        );
    }
#endif
    vec3 premultipliedColor = finalColor * visibleMaterialAlpha;
    #if COLOR_MODELS != COLOR_MODELS_DIRECT
    if (specular > 0.0) {
        // The dark specular darkens the band just outside the edge and the
        // glass's fringe, the mid tones of the glass most. Outside the
        // glass it darkens what lies there as iOS's darkens a light face
        // over it: what glass reads past its edge is not the backdrop.
        float bias = RECIPE(recipeSpecularColorBias);
        premultipliedColor *= 1.0 + bias * specular * (3.0 - 2.0 * finalColor);
        alpha += (1.0 - alpha) * specular * -bias;
    }
    #endif

    fragColor = vec4(premultipliedColor, alpha);
#if FROST_BAND
    if (alpha < 0.999) fragColor += bandRim(FlutterFragCoord().xy - uBackdropOrigin) * (1.0 - alpha);
#endif
}
