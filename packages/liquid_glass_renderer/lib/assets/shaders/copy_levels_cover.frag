#version 460 core

// The second pass of the levels a copy carries beside it, which weighs each
// pixel by how much of it lies inside the copy (copy_levels_pass.glsl).

#define LEVEL_COVER 1
#include "copy_levels_pass.glsl"
