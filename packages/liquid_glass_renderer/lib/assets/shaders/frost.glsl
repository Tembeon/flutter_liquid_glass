// A Gaussian frost of [copy] around [uv] by [sigma] texels: 24 bilinear taps
// importance-sampled from the Gaussian on a golden-angle spiral, equal
// weights, each clamped to [lo, hi] in uv. It stands in for a copy's blur
// passes, over a copy taken unblurred. [invSize] is one texel in uv.
//
// [sigma] must be positive. The loop runs to a bound read from it, 24 for
// any positive [sigma]: unrolled, the 24 reads are all kept in flight and
// double a shader's registers on the Mali-G78, halving its occupancy.
vec4 frostTaps(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi
) {
    vec4 frost = vec4(0.0);
    vec2 direction = vec2(1.0, 0.0);
    int taps = 24 - int(min(sigma, 0.0));
    for (int i = 0; i < taps; i++) {
        float u = (float(i) + 0.5) / 24.0;
        float r = sigma * sqrt(-2.0 * log(1.0 - u));
        frost += texture(copy, clamp(uv + direction * r * invSize, lo, hi));
        // Turns by the golden angle, 2.39996323 rad.
        direction = vec2(
            -0.73736888 * direction.x - 0.67549029 * direction.y,
            0.67549029 * direction.x - 0.73736888 * direction.y
        );
    }
    return frost / 24.0;
}

// A frost for a shader with registers to spare: the offsets of the spiral
// written out, centered and scaled to a variance of sigma^2, which takes the
// log and the root per tap out of the frost, the most of [frostTaps]'s
// arithmetic, and in one launch 1.9 ms of GPU time per frame from the scroll
// edges of a Pixel 6a. Written out, all the reads are in flight at once, which
// [frostTaps] says a large shader has no registers for.
//
// [invSize] carries [frostMirror]'s sign per axis. Each pixel of a 2 x 2 cell
// reads the taps mirrored its own way, four times as many positions over the
// cell, so a hard edge shows as a faint dither in place of faint copies.
//
// 8 taps serve a frost up to 2.8 texels, 16 a wider one.
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
    frost += texture(copy, clamp(uv + vec2(0.48914, 0.12110) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.36984, 0.56920) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.19721, -0.76661) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.79118, 0.99744) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-1.18410, -0.10946) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(1.44405, -0.72160) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.36967, 1.94006) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.99796, -2.03012) * reach, lo, hi));
    return frost * 0.125;
}

// Which way the fragment at [fragment] mirrors its taps along each axis.
vec2 frostMirror(vec2 fragment) {
    return step(0.5, fract(fragment * 0.5)) * 2.0 - 1.0;
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
    frost += texture(copy, clamp(uv + vec2(0.29397, 0.08599) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.29282, 0.38966) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.09030, -0.50235) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.47182, 0.65096) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.77215, -0.05743) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.82330, -0.41313) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.22990, 1.08504) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.48656, -0.92531) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(1.21020, 0.51383) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-1.21835, 0.60487) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.66623, -1.25508) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(0.52164, 1.62580) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-1.48966, -0.79971) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(1.94532, -0.33318) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-1.22920, 1.88940) * reach, lo, hi));
    frost += texture(copy, clamp(uv + vec2(-0.30413, -2.55934) * reach, lo, hi));
    return frost * 0.0625;
}
