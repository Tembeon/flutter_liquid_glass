// Writes a geometry atlas's constant tiles and its table: the quad's value,
// its x channel stepping by ramp.y every texel from texel ramp.x, so one quad
// writes the entries of a whole run of ring tiles.

precision highp float;

flat in vec4 vValue;
flat in vec4 vRamp;

out vec4 fragColor;

void main() {
  float column = floor(gl_FragCoord.x - vRamp.x);
  fragColor = vValue + vec4(vRamp.y * column, 0.0, 0.0, 0.0);
}
