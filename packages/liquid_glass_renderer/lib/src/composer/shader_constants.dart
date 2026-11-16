/// The numbers the renderer and its shaders share. They are written once,
/// here: `hook/build.dart` writes [shaderConstantsGlsl] for the shaders to
/// include, so this file imports nothing the hook cannot run.
library;

/// The most shapes one draw of the matte evaluates (`GEOMETRY_MAX_SHAPES`
/// in the geometry shaders).
///
/// A layer draws this many glass shapes in one cluster, the shapes whose
/// edges reach the same 16-pixel tile of the layer, and any number of
/// clusters; a field whose shapes carry their own appearances is one draw, so
/// it holds this many in all. Shapes beyond it are not drawn and debug builds
/// print a warning. Split the glass across several layers to draw more.
const int geometryMaxShapesPerDraw = 16;

/// The edge distance of a geometry atlas's outside tile and of its texels
/// far from every shape: far outside, and still within a 16-bit float.
const double kFarInward = -4096;

/// The name the shaders include [shaderConstantsGlsl] by.
const String shaderConstantsFile = 'shader_constants.glsl';

/// [geometryMaxShapesPerDraw] and [kFarInward] as GLSL.
const String shaderConstantsGlsl =
    '''
// Written by hook/build.dart from lib/src/composer/shader_constants.dart.
#ifndef SHADER_CONSTANTS_GLSL
#define SHADER_CONSTANTS_GLSL

#define GEOMETRY_MAX_SHAPES $geometryMaxShapesPerDraw
const float kFarInward = $kFarInward;

#endif
''';
