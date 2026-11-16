// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef SHADER_CONSTANTS_GLSL
#define SHADER_CONSTANTS_GLSL

#define GEOMETRY_MAX_SHAPES 16
#define SHAPE_INDEX_MASK 15
const float kFarOutside = -4096.0;
#define SHAPE_SQUIRCLE 1.0
#define SHAPE_ELLIPSE 2.0
#define SHAPE_ROUNDED_RECTANGLE 3.0
#define SHAPE_SQUIRCLE_PAIR 4.0

#define ATLAS_TILE_SIZE 16.0
#define RAMP_FILL 128.0
#define RAMP_RUN 64.0
#define MEMBER_STARTS_GROUP 16.0
#define MEMBER_NONE 32.0

#define SHAPE_ROW_VEC4S 3
#define SHAPE_PRIMITIVE 0
#define SHAPE_INVERSE_BASIS 1
#define SHAPE_PLACEMENT 2
#define SQUIRCLE_ROW_VEC4S 3
#define SQUIRCLE_DEGREES_AND_SPANS 0
#define SQUIRCLE_CIRCLE_CENTERS 1
#define SQUIRCLE_AXES_AND_RADII 2
const float kOpticalCornerRadiusScale = 1.5;

const float kGlintBleed = 0.21;
const float kGlintBleedReach = 4.0;
const float kGlintPeak = 0.252;
const float kGlintLuminance = 1.6;
const float kGlintVibrancy = 2.85;
const float kClearShiftShare = 1.3;
const float kDispersionSpread = 0.5;
const float kFrostEightMost = 2.8;
#define HAZE_MOST_READS 32
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
const vec3 kPartingMirror = vec3(-0.258819, 0.965926, 0.258819);

#endif
