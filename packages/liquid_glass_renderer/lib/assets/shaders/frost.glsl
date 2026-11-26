#include "shader_constants.glsl"

// Which way the fragment at [fragment] mirrors its taps along each axis.
vec2 frostMirror(vec2 fragment) {
    return step(0.5, fract(fragment * 0.5)) * 2.0 - 1.0;
}

#define FROST_TAP(x, y) \
    frost += texture(copy, clamp(uv + vec2(x, y) * reach, lo, hi));

// [invSize] carries [frostMirror]'s sign per axis. Each pixel of a 2 x 2 cell
// reads the taps mirrored its own way, four times as many positions over the
// cell, so a hard edge shows as a faint dither in place of faint copies.
vec4 frostEight(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi
) {
    highp vec2 reach = sigma * invSize;
    vec4 frost = vec4(0.0);
    FROST_EIGHT_TAPS(FROST_TAP)
    return frost * 0.125;
}

vec4 frostSixteen(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi
) {
    highp vec2 reach = sigma * invSize;
    vec4 frost = vec4(0.0);
    FROST_SIXTEEN_TAPS(FROST_TAP)
    return frost * 0.0625;
}

// How much of a frost shows a share [t] of the way from where it is gone
// (0) to where it is whole (1): a smootherstep, so neither end shows as a
// line.
float frostEase(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// How much of a frost shows at [row], between the row where it is whole
// and the row where it is gone: every way a soft scroll edge is drawn
// dissolves its frost by this.
float frostDissolve(highp float row, highp float whole, highp float gone) {
    return frostEase(clamp((row - gone) / (whole - gone), 0.0, 1.0));
}
