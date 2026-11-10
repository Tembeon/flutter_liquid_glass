// Which way the fragment at [fragment] mirrors its taps along each axis.
vec2 frostMirror(vec2 fragment) {
    return step(0.5, fract(fragment * 0.5)) * 2.0 - 1.0;
}

// A Gaussian frost of [copy] around [uv] by [sigma] texels: 12 bilinear taps
// importance-sampled from the Gaussian on a golden-angle spiral, equal
// weights, each clamped to [lo, hi] in uv. It stands in for a copy's blur
// passes, over a copy taken unblurred. [invSize] is one texel in uv.
//
// Each pixel of a 2 x 2 cell at [fragment] starts the spiral a quarter turn on
// from the last, so a hard edge shows as a faint dither in place of faint
// copies; a constant [fragment] gives up the dither for the registers it holds.
//
// [sigma] must be positive. The loop runs to a bound read from it, 12 for
// any positive [sigma]: unrolled, the reads are all kept in flight and double
// a shader's registers on the Mali-G78, halving its occupancy. In the loop
// each read waits for the last, so the count is what it costs: 12 against 24
// takes 0.34 to 0.47 ms of GPU time per frame from a Pixel 6a's chrome.
vec4 frostTaps(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi,
    vec2 fragment
) {
    vec4 frost = vec4(0.0);
    vec2 cell = frostMirror(fragment);
    vec2 direction = 0.5 * cell.x * vec2(1.0 + cell.y, 1.0 - cell.y);
    int taps = 12 - int(min(sigma, 0.0));
    for (int i = 0; i < taps; i++) {
        float u = (float(i) + 0.5) / 12.0;
        float r = sigma * sqrt(-2.0 * log(1.0 - u));
        frost += texture(copy, clamp(uv + direction * r * invSize, lo, hi));
        // Turns by the golden angle, 2.39996323 rad.
        direction = vec2(
            -0.73736888 * direction.x - 0.67549029 * direction.y,
            0.67549029 * direction.x - 0.73736888 * direction.y
        );
    }
    return frost / 12.0;
}

// Whether [frostLattice] frosts by [sigma] texels: up to eight pairs of
// texels an axis hold a Gaussian up to 3.47 texels wide, which is what a
// copy picked for its frost spans (CopyNeed, composer/geometry.dart). A
// copy finer than was asked, such as one that holds glass, leaves a wider
// frost to the sparse taps.
bool frostFitsLattice(float sigma) {
    return sigma * sigma <= 11.87;
}

// One of the bilinear reads an axis of [frostLattice]: the read of the two
// texels [first] and [first] + 1 texels from the texel center the point
// lies [f] of a texel past. x where the read lies, in texels from that
// center; y its weight. [k] is the factor in the Gaussian's exponent and
// [cut] what is taken from every weight.
vec2 frostLatticeRead(float f, float first, float k, float cut) {
    vec2 away = vec2(f - first, f - first - 1.0);
    vec2 weights = max(exp(k * away * away) - cut, 0.0);
    float both = weights.x + weights.y;
    return vec2(first + weights.y / max(both, 1e-6), both);
}

// The body of [frostLattice] for a square of N pairs of texels a side, N a
// constant, so the reads are written out and run side by side: read in a
// loop whose length the frost sets, each waits for the last, and the same
// 36 took 2.1 ms more of GPU time per frame from a Pixel 6a's tab bar. The
// weights and the places are found once an axis, 2 N of them for N * N
// reads.
#define FROST_LATTICE(N) { \
    float ratio2 = min(wide2 * 9.0 / float(N * N), 1.69) / 1.7956; \
    float k = -0.5 * (1.0 - ratio2 * ratio2 * ratio2 * sqrt(ratio2)) / wide2; \
    float cut = exp(float(N * N) * k); \
    highp float xs[N]; \
    highp float ys[N]; \
    float xw[N]; \
    float yw[N]; \
    vec2 total = vec2(0.0); \
    for (int i = 0; i < N; i++) { \
        float first = float(2 * i - (N - 1)); \
        vec2 x = frostLatticeRead(f.x, first, k, cut); \
        vec2 y = frostLatticeRead(f.y, first, k, cut); \
        xs[i] = clamp(origin.x + x.x * invSize.x, lo.x, hi.x); \
        ys[i] = clamp(origin.y + y.x * invSize.y, lo.y, hi.y); \
        xw[i] = x.y; \
        yw[i] = y.y; \
        total += vec2(x.y, y.y); \
    } \
    for (int i = 0; i < N; i++) { \
        vec4 row = vec4(0.0); \
        for (int j = 0; j < N; j++) { \
            row += yw[j] * texture(copy, vec2(xs[i], ys[j])); \
        } \
        frost += xw[i] * row; \
    } \
    frost /= total.x * total.y; \
}

// A Gaussian frost of [copy] around [uv] by [sigma] texels, at most what
// [frostFitsLattice] allows, each read clamped to [lo, hi] in uv. [invSize]
// is one texel in uv.
//
// A sparse frost reads a few points of a wide Gaussian, so a bright point
// under it comes out as that many points, a thin line as three and an edge
// as steps: on the iPhone stars under clear glass were small flowers and a
// crescent had stairs. Here every texel the Gaussian reaches is weighted,
// two to a bilinear read: 3, 4, 6 or 8 reads an axis, by the frost's
// width, over a square of 6 to 16 texels. The copy is a fraction of the
// screen's pixels, so the reads are few against the screen's: nine a copy
// pixel for a frost up to 1.3 texels wide, 64 for the widest, over a
// sixteenth of the pixels the glass covers.
//
// Each weight is cut by the Gaussian's value at the square's edge, where a
// texel enters or leaves it, so nothing steps as the point moves. The cut
// narrows the Gaussian, so the one weighed is wider by what the cut takes
// (fitted: within 1 % of the width asked). On a test picture of text,
// points and a crescent the result lies 1 to 2 levels of 255 (rms) from
// the true Gaussian, where eight sparse taps lie 6.
//
// [sigma] is the frost left for the taps by a copy read bilinearly, as the
// sparse taps take it; a sixth of a texel squared more is the Gaussian over
// the texels themselves.
vec4 frostLattice(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi
) {
    float wide2 = sigma * sigma + 0.16667;
    // A square of n pairs a side holds a Gaussian up to 1.3 / 3 of n wide.
    float pairs = sqrt(wide2) * 2.3077;
    highp vec2 at = uv / invSize - 0.5;
    highp vec2 base = floor(at);
    vec2 f = at - base;
    highp vec2 origin = (base + 0.5) * invSize;
    vec4 frost = vec4(0.0);
    if (pairs <= 3.0) FROST_LATTICE(3)
    else if (pairs <= 4.0) FROST_LATTICE(4)
    else if (pairs <= 6.0) FROST_LATTICE(6)
    else FROST_LATTICE(8)
    return frost;
}

// A sparse frost for a shader with registers to spare, its offsets written
// out, centered and scaled to a variance of sigma^2: the scroll edge a
// glass's own shader draws, and a copy too fine for [frostLattice]. The reads run in parallel, as
// [frostTaps]'s cannot: the same 24 taps took 1.9 ms less of GPU time per frame
// from a Pixel 6a's scroll edges written out than in the loop.
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
