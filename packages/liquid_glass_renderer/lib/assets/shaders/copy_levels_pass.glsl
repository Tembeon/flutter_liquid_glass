#ifndef COPY_LEVELS_PASS_GLSL
#define COPY_LEVELS_PASS_GLSL

// A pass of the levels a copy carries beside it (LevelStrip in
// read_layout.dart, read by copy_levels.glsl): the image filter of a layer
// that holds the copy and the row of cells under it. A cell of blur level k
// averages 2^k x 2^k of the copy's pixels by a tent twice that wide, a cell
// of the fill level a cell of its own stride the same way, on a grid
// anchored at the screen. The first pass averages the copy into the levels
// up to kCoarseSourceLevel, the second that level into the coarser levels
// and the fill level; every other pixel passes through.
//
// Each cell is the tent read in bilinear pairs: two neighbours weighed w0
// and w1 are one read between them, w1 / (w0 + w1) of the way.
//
// With LEVEL_COVER (copy_levels_cover.frag: the second pass of a copy that
// holds less than its blur reaches, LevelStrip.covers) a source pixel
// weighs as much as it lies inside the copy, so a cell the copy's edge cuts
// averages what the copy holds and changes smoothly as the copy moves, and
// the ring around each level holds the cells beside it, not a repeat of the
// edge, so the strip moving a cell along the screen's grid changes nothing
// a read sees. The first pass (copy_levels.frag) goes without: glass reads
// its levels only far inside the copy, the second pass weighs the cells it
// averages by their coverage, and in the first pass, which draws nearly all
// the levels' pixels, the coverage cost a tab bar drag 4 % more GPU time on
// the Pixel 6a; in the second pass of every copy, 2.7 %.

precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "shader_constants.glsl"

// The layer's texture size in pixels; an image filter's engine sets it.
uniform highp vec2 uSize;
// The strip's top left in the layer, the columns of the fill level with its
// ring (0 for none) and its stride.
uniform highp vec4 uStrip;
// The copy's width and height rounded up to whole cells of the coarsest
// level, and the finest and the coarsest level the strip holds.
uniform highp vec4 uLevels;
// The copy's top left on the screen's grid of its pixels.
uniform highp vec2 uGrid;
// The levels this pass writes, from x to y, and z: 1 where it writes the
// fill level.
uniform highp vec3 uPass;
// Where the pixels this pass reads lie: the screen's grid point, in copy
// pixels, of their pixel zero, and how many copy pixels one of them spans.
uniform highp vec3 uSource;
// The rect the pass reads inside, in the layer's pixels.
uniform highp vec4 uBounds;
#if LEVEL_COVER
// The copy's size in its pixels.
uniform highp vec2 uCopySize;
#endif

uniform sampler2D uCopy;

out vec4 fragColor;

// The weight of source pixel [t] in a tent reaching [h] around [c].
highp float tent(highp float t, highp float c, highp float h) {
    return max(1.0 - abs(t + 0.5 - c) / h, 0.0);
}

void main() {
    highp vec2 invSize = 1.0 / uSize;
    highp vec2 at = FlutterFragCoord().xy;
    highp vec2 local = floor(at - uStrip.xy);
    highp float k = 0.0;
    highp float start = 0.0;
    highp float columns = uStrip.z;
    highp float stride = uStrip.w;
    bool fill = local.x < uStrip.z;
    if (!fill) {
        k = uLevels.z;
        start = uStrip.z;
        for (int i = 0; i < LEVEL_MOST_DEEP; i++) {
            stride = exp2(k);
            columns = uLevels.x / stride + 1.0 + 2.0 * kLevelRing;
            if (local.x < start + columns || k >= uLevels.w) break;
            start += columns;
            k += 1.0;
        }
    }
    // Cells along each side, their ring aside.
    highp vec2 cells = fill
        ? vec2(uStrip.z - 2.0 * kLevelRing, ceil(uLevels.y / stride) + 1.0)
        : uLevels.xy / stride + 1.0;
    bool writes = local.y >= 0.0 && local.x >= 0.0 &&
        local.x < start + columns && local.y < cells.y + 2.0 * kLevelRing &&
        (fill ? uPass.z > 0.5 : k >= uPass.x && k <= uPass.y);
    if (!writes) {
        fragColor = texture(uCopy, at * invSize);
        return;
    }
#if LEVEL_COVER
    highp vec2 cell = vec2(local.x - start, local.y) - kLevelRing;
#else
    highp vec2 cell = clamp(
        vec2(local.x - start, local.y) - kLevelRing,
        vec2(0.0),
        cells - 1.0
    );
#endif
    // The cell's middle among the source's pixels, and how far the tent
    // reaches in them.
    highp vec2 middle =
        ((floor(uGrid / stride) + cell + 0.5) * stride - uSource.xy) /
        uSource.z;
    highp float spread = stride / uSource.z;
    highp vec2 first = floor(middle - spread - 0.5) + 1.0;
#if LEVEL_COVER
    // The copy among the source's pixels.
    highp vec2 copyFrom = (uGrid - uSource.xy) / uSource.z;
    highp vec2 copyTo = copyFrom + uCopySize / uSource.z;
#endif
    highp vec2 pairs = ceil((ceil(middle + spread - 0.5) - first) / 2.0);
    highp vec4 sum = vec4(0.0);
    highp float total = 0.0;
    float column = 0.0;
    float row = 0.0;
    // One loop over the pairs, row after row: a loop inside a loop takes
    // twice the work registers on a Mali-G78, which the fragments that only
    // pass the copy on would pay for too.
    for (int n = 0; n < LEVEL_MOST_PAIRS * LEVEL_MOST_PAIRS; n++) {
        highp vec2 t = first + 2.0 * vec2(column, row);
        highp vec2 w0 = vec2(
            tent(t.x, middle.x, spread),
            tent(t.y, middle.y, spread)
        );
        highp vec2 w1 = vec2(
            tent(t.x + 1.0, middle.x, spread),
            tent(t.y + 1.0, middle.y, spread)
        );
#if LEVEL_COVER
        w0 *= clamp(min(t + 1.0, copyTo) - max(t, copyFrom), 0.0, 1.0);
        w1 *= clamp(min(t + 2.0, copyTo) - max(t + 1.0, copyFrom), 0.0, 1.0);
#endif
        highp vec2 weight = w0 + w1;
        highp vec2 read = t + 0.5 + w1 / max(weight, vec2(1e-6));
        highp float w = weight.x * weight.y;
        sum += texture(uCopy, clamp(read, uBounds.xy, uBounds.zw) * invSize) * w;
        total += w;
        column += 1.0;
        if (column >= pairs.x) {
            row += 1.0;
            if (row >= pairs.y) break;
            column = 0.0;
        }
    }
#if LEVEL_COVER
    fragColor = total > 1e-6
        ? sum / total
        : texture(uCopy, clamp(middle, uBounds.xy, uBounds.zw) * invSize);
#else
    fragColor = sum / max(total, 1e-6);
#endif
}

#endif
