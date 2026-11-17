#ifndef FAKE_GLASS_LIGHTING_GLSL
#define FAKE_GLASS_LIGHTING_GLSL

#include "contour.glsl"
#include "fake_glass_lanes.glsl"
#include "shader_constants.glsl"

// The reference rim's peak is lower than a source-over mix of the same glint
// target. The additive pass only adds light, so scale it to the measured
// profile instead of replacing the face.
const float kAdditiveHighlightScale = 0.75;

vec4 fakeGlassLit(float distance, vec2 normal, float coverage) {
  float inward = max(-distance, 0.0);
  vec2 lightDirection = vec2(0.0, 1.0);
  float facing = dot(normal, -lightDirection);

  float tangency = abs(dot(normal, vec2(-lightDirection.y, lightDirection.x)));

  float glintWidth = max(
    uHighlightWidth > 0.0 ? uHighlightWidth : uContourWidth,
    0.001
  );
  float glintProfile =
      clamp(1.0 - inward / glintWidth, 0.0, 1.0) +
      kGlintBleed * clamp(1.0 - inward / (glintWidth * kGlintBleedReach), 0.0, 1.0);
  float wrapExponent = exp2(2.0 - 4.0 * clamp(uHighlightWrap, 0.0, 1.0));
  float lobe = pow(max(1.0 - tangency, 0.0), wrapExponent);
  float returnWeight = facing >= 0.0
      ? 1.0
      : clamp(uOppositeHighlight, 0.0, 1.0);
  float glint = clamp(
    max(uHighlight, 0.0) * kGlintPeak * lobe * returnWeight * glintProfile,
    0.0,
    1.0
  );

  float tintAlpha = uTint.a;
  vec3 faceProxy = uTint.rgb * tintAlpha + uFaceEmission;
  vec3 glintTarget = vec3(uGlintLuminance) +
      uGlintFaceGain * faceProxy +
      uGlintVibrancy * (faceProxy - vec3(dot(faceProxy, LUMA_WEIGHTS)));
  float materialCoverage = uExteriorOnly > 0.5 ? 0.0 : coverage;
  if (uHighlightsOnly > 0.5) {
    return vec4(
      max(glintTarget, vec3(0.0)) * glint * materialCoverage *
          kAdditiveHighlightScale,
      0.0
    );
  }
  float outwardPixels = distance / uPixelSize;
  float contourWidthPixels = uContourWidth / uPixelSize;
  float contourBand = 0.0;
  if (uContourWidth > 0.0) {
    contourBand =
        contourIntegral(max(outwardPixels + 0.5, 0.0), contourWidthPixels) -
        contourIntegral(max(outwardPixels - 0.5, 0.0), contourWidthPixels);
  }
  float contourStrength = clamp(uContourStrength, 0.0, 1.0) *
      mix(1.0, tangency, clamp(uContourDirectionality, 0.0, 1.0));

  float bevelDepth = max(uBevelDepth, 0.001);
  float bevelShift = max(uBevelOffset, 0.0) * facing;
  float bevelPenumbra = 2.0 * bevelShift;
  float bevelLeading = bevelPenumbra > 0.001
      ? smoothstep(0.0, bevelPenumbra, inward)
      : 1.0;
  float bevelFalloff = 1.0 - smoothstep(0.0, bevelDepth, inward - bevelShift);
  float wrappedFacing = smoothstep(0.0, 1.0, facing * 0.5 + 0.5);
  float directionalShadow = mix(
    1.0,
    wrappedFacing,
    clamp(uBevelDirectionality, 0.0, 1.0)
  );
  float bevelShadow = clamp(
    bevelLeading * bevelFalloff * directionalShadow *
        uBevelStrength,
    0.0,
    1.0
  );
  float materialAlpha = 1.0 - (1.0 - tintAlpha) * (1.0 - bevelShadow);
  float exteriorContourAlpha = clamp(contourBand * contourStrength, 0.0, 1.0);
  vec3 emissionUnshadowed = uFaceEmission * bevelShadow * (1.0 - tintAlpha);
  vec3 litPremultiplied = uTint.rgb * tintAlpha + emissionUnshadowed;
  float litAlpha = materialAlpha;
  if (litAlpha < 0.999) {
    litPremultiplied = min(litPremultiplied, vec3(1.0));
    float alphaCoveringColor =
        max(max(litPremultiplied.r, litPremultiplied.g), litPremultiplied.b);
    litAlpha = max(litAlpha, alphaCoveringColor);
  }
  float alpha = litAlpha * materialCoverage + exteriorContourAlpha;
  return vec4(
    max(litPremultiplied * materialCoverage, vec3(0.0)),
    clamp(alpha, 0.0, 1.0)
  );
}

#endif
