// One quad of a geometry atlas (geometry_tiling.dart), its corners in clip
// space. Every vertex of a quad carries the same value and ramp: what the
// fill pass writes, or where the geometry and field passes find the buffer
// pixel under a texel.

in vec2 position;
in vec4 value;
in vec4 ramp;

flat out vec4 vValue;
flat out vec4 vRamp;

void main() {
  gl_Position = vec4(position, 0.0, 1.0);
  vValue = value;
  vRamp = ramp;
}
