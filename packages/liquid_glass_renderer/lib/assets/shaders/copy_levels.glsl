#ifndef COPY_LEVELS_GLSL
#define COPY_LEVELS_GLSL

// The levels a copy carries beside it (copy_levels.frag): blur level k
// averages 2^k x 2^k of the copy's pixels by a tent twice that wide, and the
// fill level a cell of its own stride the same way, each on a grid anchored
// at the screen. They lie in one row under the copy, the fill level first,
// then the blur levels from the finest, each inside a ring of one texel that
// repeats its edge, so a read anywhere over the copy needs no clamp.

// The uv of blur level [k] over the copy's uv [copyUV].
highp vec2 levelUV(highp vec2 copyUV, highp float k) {
    highp float stride = exp2(k);
    highp float column = uLevelBlurAt +
        uLevelWidth * (exp2(1.0 - uLevelFinest) - exp2(1.0 - k)) +
        3.0 * (k - uLevelFinest);
    return copyUV / stride + (
        vec2(column, uLevelRow) +
        (uLevelGrid - uLevelCopyAt) / stride -
        floor(uLevelGrid / stride)
    ) / uLevelTexture;
}

// The variance, in copy pixels squared, of a bilinear read of blur level
// [k]: the cell a copy pixel already averages, the tent the level averages
// by and the tent of the read; level 0 is the copy itself. Levels past 2
// average level 2, so they carry its tent too.
highp float levelVariance(highp float k) {
    highp float box = uLevelShare > 1.0 ? 1.0 / 12.0 : 0.0;
    highp float base = k > 2.5 ? 8.0 / 3.0 : 0.0;
    return k < 0.5 ? box + 1.0 / 6.0 : box + base + exp2(2.0 * k) / 3.0;
}

// [sharp], the copy read at [copyUV], blurred by [sigma] copy pixels: the
// two levels whose blur brackets it, mixed by variance, toward [sharp]
// below the finest.
vec4 levelBlur(
    sampler2D copy,
    vec4 sharp,
    highp vec2 copyUV,
    highp float sigma
) {
    highp float variance = sigma * sigma;
    highp float box = uLevelShare > 1.0 ? 1.0 / 12.0 : 0.0;
    highp float span = 3.0 * (variance - box);
    highp float k = floor(0.5 * log2(max(
        span >= 72.0 ? span - 8.0 : min(span, 63.0),
        1e-4
    )));
    k = clamp(k, uLevelFinest - 1.0, uLevelCoarsest - 1.0);
    highp float below = k < uLevelFinest ? 0.0 : k;
    vec4 low = sharp;
    if (below > 0.5) {
        low = texture(copy, levelUV(copyUV, below));
    }
    vec4 high = texture(copy, levelUV(copyUV, k + 1.0));
    highp float from = levelVariance(below);
    float toHigh = clamp(
        (variance - from) / (levelVariance(k + 1.0) - from),
        0.0,
        1.0
    );
    return mix(low, high, toHigh);
}

// The fill level over the copy's uv [copyUV].
vec4 levelFill(sampler2D copy, highp vec2 copyUV) {
    return texture(copy, copyUV * uFillInverseStride + uFillOffset);
}

// [c] moved to the fill [f] by one amount where [f] is lighter and by
// another where it is darker, channel by channel, then covered by [f]
// ([uFillMix]). One amount picked by the sign: a max and a min each scaled
// take twice the work registers on a Mali-G78.
vec3 fillMix(vec3 c, vec3 f) {
    vec3 toFill = f - c;
    vec3 moved = c + toFill * mix(
        vec3(uFillMix.y),
        vec3(uFillMix.x),
        step(0.0, toFill)
    );
    return mix(moved, f, uFillMix.z);
}

#endif
