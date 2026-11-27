#ifndef RECIPE_EDGES_GLSL
#define RECIPE_EDGES_GLSL

// The edges an iOS 27 recipe draws, for the glass shader and FakeGlass
// alike: functions of the depth inside the edge (negative outside) and the
// edge's outward normal, y down, in units of which [pixel] is one device
// pixel.

// 1 - erf(x / sqrt 2) halved, the Gaussian's tail past x sigma, within 0.001.
float gaussianTail(float x) {
    float t = clamp(x * 0.7071, -2.0, 2.0);
    float t2 = t * t;
    return 0.5 +
        t * (-0.5605 + t2 * (0.16821 + t2 * (-0.03445 + 0.002954 * t2)));
}

// Two lights opposite each other along the axis [facing] is measured on,
// each reaching [spread] (a cosine) of the edge's direction, over a mask
// [value] that the bias shapes. A bias of -1 makes the mask a step; the
// floor of its divisor stays a normal 16-bit float.
float twoLights(float facing, float spread, float bias, float value) {
    float reach = 1.0 / max(1.0 - spread, 1e-4);
    float near = clamp((facing - spread) * reach, 0.0, 1.0) * value;
    float far = clamp((-facing - spread) * reach, 0.0, 1.0) * value;
    return near / max(bias * (1.0 - near) + 1.0, 1e-4) +
        far / max(bias * (1.0 - far) + 1.0, 1e-4);
}

// How strongly the rim highlight lights at [depth]: a line [line] deep
// whose profile bends by [curvature] (biased by kRimLineBias), and a
// diffuse glow [diffuse] deep biased by [diffuseBias], lit from above and
// below as far as the cosines [spread]. The line and the glow add up, past
// 1 near the edge.
float rimHighlight(
    float depth,
    vec2 normal,
    float pixel,
    float line,
    float diffuse,
    vec2 spread,
    float diffuseBias,
    float curvature
) {
    float inside = clamp(depth / pixel + 0.5, 0.0, 1.0);
    float x = clamp(depth / line, 0.0, 1.0);
    float lineMask = mix(x < 1.0 ? 1.0 : 0.0, 1.0 - x, curvature) * inside *
        clamp((line - depth) / pixel + 0.5, 0.0, 1.0);
    float glowMask = (1.0 - clamp(depth / diffuse, 0.0, 1.0)) * inside *
        clamp((diffuse - depth) / pixel + 0.5, 0.0, 1.0);
    return twoLights(-normal.y, spread.x, kRimLineBias, lineMask) +
        twoLights(-normal.y, spread.y, diffuseBias, glowMask);
}

// How dark the ring shadow is at [depth]: a band [stroke] wide inside the
// outline moved [offset] down, blurred by a sigma of 1 / [inverseRadius],
// black at [opacity]. The moved outline's distance is taken to first order
// from this pixel's own, which is exact along straight edges.
float ringShadow(
    float depth,
    vec2 normal,
    float opacity,
    float offset,
    float stroke,
    float inverseRadius
) {
    float moved = (-depth - offset * normal.y) * inverseRadius;
    return opacity * clamp(
        gaussianTail(moved) - gaussianTail(moved + stroke * inverseRadius),
        0.0,
        1.0
    );
}

// The ring shadow of glass whose shorter side is 2 [halfSide]: the band of
// the wall [depth] away and, where the glass is short enough for a band to
// reach past its middle, the band of the parallel wall across, which still
// darkens where this one lies nearer.
float ringShadowAcross(
    float depth,
    vec2 normal,
    float halfSide,
    float opacity,
    float offset,
    float stroke,
    float inverseRadius
) {
    float ring = ringShadow(depth, normal, opacity, offset, stroke, inverseRadius);
    float across = 2.0 * halfSide - depth;
    if ((across - offset - stroke) * inverseRadius < 3.0) {
        ring += ringShadow(
            across,
            -normal,
            opacity,
            offset,
            stroke,
            inverseRadius
        );
    }
    return min(ring, 1.0);
}

// The share of the dark specular's fall that ramps toward the band's outer
// end; the rest is a step at its inner end.
const float kDarkSpecularRamp = 0.75;

// How strongly the dark specular darkens at [depth] from the band's inner
// end, positive inward: a band [width] wide outward from there, strongest
// at its outer end, lit from the left and the right as far as the cosine
// [spread], its mask biased by [bias]. A band that starts inside the glass
// is drawn with its callers' depth moved by its inset.
float darkSpecular(
    float depth,
    vec2 normal,
    float pixel,
    float width,
    float spread,
    float bias
) {
    if (width <= 0.0) return 0.0;
    float from = width + depth;
    float x = 1.0 - clamp(from / width, 0.0, 1.0);
    float fall = mix(x > 0.0 ? 1.0 : 0.0, x, kDarkSpecularRamp) *
        clamp(0.5 - depth / pixel, 0.0, 1.0) *
        clamp(from / pixel + 0.5, 0.0, 1.0);
    return min(twoLights(normal.x, spread, bias, fall), 1.0);
}

#endif
