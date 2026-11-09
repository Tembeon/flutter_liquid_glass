// The quads of a geometry atlas that hold no geometry: its constant tiles and
// its table. Such a quad's ramp has 128 in x; it writes its value, the x
// channel stepping by 16 times the value's z every texel from texel ramp.y:
// the entries of a run of ring tiles lie a tile's texels apart, so one quad
// writes them all. With LOOKS a deep block writes the look of row ramp.z
// (looks.glsl) beside it, and a quad with a negative ramp.z none.
//
// Included after the including shader has declared vValue, vRamp, fragColor
// and, with LOOKS, the look targets.

bool isFill() {
    return vRamp.x >= 128.0;
}

void writeFill() {
    float column = floor(gl_FragCoord.x - vRamp.y);
    fragColor = vValue + vec4(16.0 * vValue.z * column, 0.0, 0.0, 0.0);
#if LOOKS
    writeLook(
        vRamp.z < 0.0
            ? Look(vec4(0.0), vec4(0.0), vec4(0.0))
            : lookAt(int(vRamp.z) & 15)
    );
#endif
}
