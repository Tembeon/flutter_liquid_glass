// The light fake glass draws at a point [distance] logical pixels outside
// its silhouette (negative inside) where its surface faces [normal], the
// silhouette covering [coverage] of the pixel: the shared lighting of
// fake_glass_surface.frag and fake_glass_field_surface.frag, which differ
// only in where the distance and the normal come from. It reads the lanes
// of fake_glass_lanes.glsl and the constants of shader_constants.glsl,
// which the including program declares first.

#ifndef FAKE_GLASS_LIGHTING_GLSL
#define FAKE_GLASS_LIGHTING_GLSL

// The reference rim's peak is lower than a source-over mix of the same glint
// target. The additive pass only adds light, so scale it to the measured
// profile instead of replacing the face.
const float kAdditiveHighlightScale = 0.75;

// Integral of the border ramp from the silhouette to outward distance t, all
// in physical pixels. See contourIntegral in the final render shader.
float contourIntegral(float t, float offset, float width) {
  float u = clamp(t - offset, 0.0, width);
  return u - u * u / (2.0 * width);
}

vec4 fakeGlassLit(float distance, vec2 normal, float coverage) {
  float inward = max(-distance, 0.0);
  vec2 lightDirection = normalize(uLightDirection + vec2(0.00001));
  float facing = dot(normal, -lightDirection);

  // Same SDF-space lighting contract as RealGlass (see
  // liquid_glass_final_render_core.glsl): a one-sided exterior border and a
  // glint line anchored at the silhouette.
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
  // The glint adds a bright target on top of the lit face. Without backdrop
  // access FakeGlass approximates the face with the surface tint plus
  // emission; only RealGlass amplifies the true backdrop chroma under the
  // glint and keeps the headroom above white.
  vec3 faceProxy = uTint.rgb * tintAlpha + uFaceEmission;
  vec3 glintTarget = vec3(uGlintLuminance) +
      uGlintFaceGain * faceProxy +
      uGlintVibrancy * (faceProxy - vec3(dot(faceProxy, LUMA_WEIGHTS)));
  float materialCoverage = uExteriorOnly > 0.5 ? 0.0 : coverage;
  if (uHighlightsOnly > 0.5) {
    // Additive pass: emit only the glint's light. Alpha stays zero so the
    // destination face keeps its own coverage; RGB is premultiplied by the
    // glint weight (not by alpha) and may exceed one on an extended-range
    // target.
    return vec4(
      max(glintTarget, vec3(0.0)) * glint * materialCoverage *
          kAdditiveHighlightScale,
      0.0
    );
  }
  // The border is box-filtered over one physical pixel, split at the
  // silhouette, so a sub-pixel border does not alias into a dotted line.
  float outwardPixels = distance / uPixelSize;
  float contourOffsetPixels = uContourOffset / uPixelSize;
  float contourWidthPixels = uContourWidth / uPixelSize;
  vec2 contourBand = vec2(0.0);
  if (uContourWidth > 0.0) {
    float lower = outwardPixels - 0.5;
    float upper = outwardPixels + 0.5;
    contourBand = vec2(
      contourIntegral(max(upper, 0.0), contourOffsetPixels, contourWidthPixels) -
          contourIntegral(max(lower, 0.0), contourOffsetPixels, contourWidthPixels),
      contourIntegral(min(upper, 0.0), contourOffsetPixels, contourWidthPixels) -
          contourIntegral(min(lower, 0.0), contourOffsetPixels, contourWidthPixels)
    );
  }
  float contourStrength = clamp(uContourStrength, 0.0, 1.0) *
      mix(1.0, tangency, clamp(uContourDirectionality, 0.0, 1.0));
  // In-material share of the border, relative to the material's coverage.
  float contourAbsorption = clamp(
    contourBand.y / max(coverage, 0.001) * contourStrength,
    0.0,
    1.0
  );
  float backdropContourAbsorption = contourAbsorption *
      (1.0 - clamp(uContourTransmittance, 0.0, 1.0));
  float bevelShadow = 0.0;

  float bevelDepth = max(uBevelDepth, 0.001);
  // The rim's band is displaced along the light, as in RealGlass.
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
  bevelShadow = clamp(
    bevelLeading * bevelFalloff * directionalShadow *
        uBevelStrength,
    0.0,
    1.0
  );
  float backdropAbsorption = 1.0 -
      (1.0 - backdropContourAbsorption) * (1.0 - bevelShadow);
  float materialAlpha = 1.0 - (1.0 - tintAlpha) *
      (1.0 - backdropAbsorption);
  float exteriorContourAlpha = clamp(contourBand.x * contourStrength, 0.0, 1.0);
  // The inner shadow absorbs the filtered face, which includes the face's
  // own emission; adding that share back leaves only the transmitted light
  // shaded, as in RealGlass.
  vec3 litPremultiplied =
      uTint.rgb * tintAlpha * (1.0 - contourAbsorption) +
      uFaceEmission * bevelShadow * (1.0 - tintAlpha) *
          (1.0 - backdropContourAbsorption);
  float litAlpha = materialAlpha;
  // Keep the surface's premultiplied color within alpha as Skia needs. The
  // separate additive highlight pass carries the glint, including headroom
  // above SDR white on an extended-range target.
  if (litAlpha < 0.999) {
    litPremultiplied = min(litPremultiplied, vec3(1.0));
    litAlpha = max(
      litAlpha,
      max(max(litPremultiplied.r, litPremultiplied.g), litPremultiplied.b)
    );
  }
  float alpha = litAlpha * materialCoverage + exteriorContourAlpha;
  return vec4(
    max(litPremultiplied * materialCoverage, vec3(0.0)),
    clamp(alpha, 0.0, 1.0)
  );
}

#endif
