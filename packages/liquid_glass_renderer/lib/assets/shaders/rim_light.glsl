#ifndef RIM_LIGHT_GLSL
#define RIM_LIGHT_GLSL

#include "shader_constants.glsl"

// The rim light real glass and FakeGlass share: the glint along the light
// axis and the raised rim's shadow on the face. Distances are inward from
// the silhouette, in the caller's unit.

// The fraction of the normal perpendicular to the light axis. The glint
// lives where it is zero; the dark border concentrates where it is one.
float lightAxisTangency(vec2 normal) {
    return abs(dot(normal, vec2(-kLightDirection.y, kLightDirection.x)));
}

// How squarely the normal faces the light: 1 on the lit wall, -1 on the
// far one.
float lightFacing(vec2 normal) {
    return dot(normal, -kLightDirection);
}

// The share of the border's strength the normal keeps, where
// [directionality] of it follows the light axis.
float contourDirection(vec2 normal, float directionality) {
    return mix(
        1.0,
        lightAxisTangency(normal),
        clamp(directionality, 0.0, 1.0)
    );
}

// The glint across the rim: a thin line anchored at the silhouette with a
// faint inward bleed, [highlightWidth] wide, or as wide as the border where
// that is 0. Both are linear ramps in logical distance, so the line stays
// crisp at every size and scale factor.
float glintProfile(float inward, float highlightWidth, float contourWidth) {
    float width = max(highlightWidth > 0.0 ? highlightWidth : contourWidth, 0.001);
    return clamp(1.0 - inward / width, 0.0, 1.0) +
        kGlintBleed * clamp(1.0 - inward / (width * kGlintBleedReach), 0.0, 1.0);
}

// The glint of [intensity] at [profile]. Both walls along the light axis
// catch it; it fades with the normal's tangential component.
// highlightWrap = 0.5 is the linear falloff measured on iOS 27; lower values
// narrow the lobes and higher values carry them further around corners.
float rimGlint(float intensity, vec2 normal, float profile) {
    float lobe = pow(
        max(1.0 - lightAxisTangency(normal), 0.0),
        exp2(2.0 - 4.0 * kHighlightWrap)
    );
    float returnWeight = lightFacing(normal) >= 0.0
        ? 1.0
        : kHighlightOppositeStrength;
    return clamp(
        max(intensity, 0.0) * kGlintPeak * lobe * returnWeight * profile,
        0.0,
        1.0
    );
}

// The raised rim's shadow on the face, like a wall lit along the light
// axis: its band of [depth] is displaced by [offset] along the light. Below
// the lit wall it falls inside the face, along the sides it starts at the
// rim, and below the far wall it is pushed out past the rim. The penumbra
// is as wide as the displacement.
float bevelShadow(
    float inward,
    vec2 normal,
    float depth,
    float offset,
    float strength
) {
    float facing = lightFacing(normal);
    float shift = max(offset, 0.0) * facing;
    float penumbra = 2.0 * shift;
    float leadingEdge = penumbra > 0.001
        ? smoothstep(0.0, penumbra, inward)
        : 1.0;
    float falloff = 1.0 - smoothstep(0.0, max(depth, 0.001), inward - shift);
    // The facing is remapped across the whole contour before directionality
    // applies: clamping it at zero makes a half-plane seam whose endpoints
    // project as wedges into circles and blended shapes. The cubic ramp is
    // strongest on the lit wall, reaches zero only opposite it, and has zero
    // slope at both ends.
    float direction = mix(
        1.0,
        smoothstep(0.0, 1.0, facing * 0.5 + 0.5),
        kBevelShadowDirectionality
    );
    return clamp(leadingEdge * falloff * direction * strength, 0.0, 1.0);
}

#endif
