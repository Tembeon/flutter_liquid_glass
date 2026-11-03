// A Gaussian frost of [copy] around [uv] by [sigma] texels: 24 bilinear taps
// importance-sampled from the Gaussian on a golden-angle spiral, equal
// weights, each clamped to [lo, hi] in uv. It stands in for a copy's blur
// passes, over a copy taken unblurred. [invSize] is one texel in uv.
//
// [sigma] must be positive. The loop runs to a bound read from it, 24 for
// any positive [sigma]: unrolled, the 24 reads are all kept in flight and
// double a shader's registers on the Mali-G78, halving its occupancy.
vec4 frostTaps(sampler2D copy, vec2 uv, float sigma, vec2 invSize, vec2 lo, vec2 hi) {
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
