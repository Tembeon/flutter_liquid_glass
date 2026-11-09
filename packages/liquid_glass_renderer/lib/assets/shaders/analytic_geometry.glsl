// Analytic geometry for the final pass: the layer's one shape evaluated
// where the fragment is, with the geometry pass's own scene (gpu/sdf.glsl),
// instead of read from a Flutter GPU matte. It yields the matte's texel at
// the fragment itself - the distance, the normal times its strength and half
// the shorter side - so the rest of the final pass reads it as it reads the
// matte.
//
// The geometry pass shades a texel per block of matte pixels; this runs for
// every pixel, so it skips the pixels deeper inside than the pass reads.
//
// Included by liquid_glass_final_render_core.glsl after its float uniforms.
// impellerc gives every uniform declaration its own Metal buffer slot and
// Metal has 31; these two fit because the core packs its optional effects
// into uEffects.
//
// The shape is highp, as the matte pass shades it; the core's mediump
// returns after it. A whole highp shader holds 64 work registers on a
// Mali-G78, half its occupancy; the shape scoped this way holds 32.
precision highp float;

#define MAX_SHAPES 1

// The shape's primitive, inverse basis and placement, as gpu/sdf.glsl reads
// them.
uniform vec4 uShapeData[3];
// Its three rounded superellipse rows, then a pair's bottom-half rows.
uniform vec4 uRseData[6];
// gpu/sdf.glsl's scene functions read shape bounds; one shape never calls
// them.
vec4 uShapeBounds[1];

#include "gpu/sdf.glsl"

// A lower bound of how deep p lies inside the shape, device px, or 0.
// A rounded box is convex, and at twice its corner radius from each corner
// (or at the side's middle, if nearer) its outline lies on its box's side
// to within a thousandth of the radius; a rounded superellipse's sides are
// not quite straight. So the shape holds the octagon through those points
// shrunk by a hundredth of the radius
// (test/src/analytic_depth_bound_test.dart), and p's depth in that octagon
// bounds its depth. That needs the radius to be at most half the box's
// shorter side (a capsule at most) and, for a pair, four times its larger
// radius to fit in the shorter side; ellipses and the rest report 0.
float shapeDepthBound(vec2 p) {
    vec4 primitive = uShapeData[0];
    if (primitive.x == 0.0 || primitive.x == 2.0) {
        return 0.0;
    }
    vec4 inverseBasis = uShapeData[1];
    vec4 placement = uShapeData[2];
    vec2 halfSize = primitive.yz * 0.5;
    float radius = primitive.w;
    float shorter = min(halfSize.x, halfSize.y);
    if (primitive.x == 4.0) {
        radius = max(radius, uRseData[5].x);
        if (2.0 * radius > shorter) {
            return 0.0;
        }
    } else if (radius > shorter) {
        return 0.0;
    }
    vec2 delta = p - placement.xy;
    vec2 local = abs(vec2(
        inverseBasis.x * delta.x + inverseBasis.y * delta.y,
        inverseBasis.z * delta.x + inverseBasis.w * delta.y
    ));
    vec2 inside = halfSize - local;
    vec2 cut = min(vec2(2.0 * radius), halfSize);
    float depth = min(inside.x, inside.y);
    if (radius > 0.0) {
        // The cut edge from (halfSize.x - cut.x, halfSize.y) to
        // (halfSize.x, halfSize.y - cut.y), measured inward.
        depth = min(
            depth,
            (inside.x * cut.y + inside.y * cut.x - cut.x * cut.y) /
                length(cut)
        );
    }
    return max(depth - 0.01 * radius, 0.0) * placement.z;
}

// The texel of [scene]: as geometry_fragment.glsl encodes it.
vec4 sceneTexel(SceneSample scene) {
    float gradientLength = length(scene.opticalNormal);
    vec2 normal = gradientLength > 0.0001
        ? scene.opticalNormal / gradientLength
        : vec2(0.0);
    return vec4(
        clamp(-scene.distance, -16000.0, 16000.0),
        normal * sqrt(clamp(gradientLength, 0.0, 1.0)),
        scene.halfMinor
    );
}

// The geometry pass's texel at p (geometry_fragment.glsl); deeper inside than
// [readDepth], where the final pass only checks that the distance is past
// it, some depth past it with no normal. The glass is drawn over the shape's
// own box, so few pixels lie far outside it; a test for them would double
// the registers (64 on a Mali-G78).
vec4 analyticTexel(vec2 p, float readDepth) {
    float depth = shapeDepthBound(p);
    if (depth > readDepth) {
        return vec4(depth, 0.0, 0.0, 0.0);
    }
    return sceneTexel(getShapeSampleFromArray(0, p, false));
}

precision mediump float;
