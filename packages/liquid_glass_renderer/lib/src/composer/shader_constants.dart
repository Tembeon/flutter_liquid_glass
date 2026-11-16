import 'package:meta/meta.dart';

/// A layer draws this many glass shapes in one cluster, the shapes whose
/// edges reach the same 16-pixel tile of the layer, and any number of
/// clusters; a field whose shapes carry their own appearances is one draw, so
/// it holds this many in all. Shapes beyond it are not drawn and debug builds
/// print a warning. Split the glass across several layers to draw more.
const int geometryMaxShapesPerDraw = 16;

@internal
const double kFarOutside = -4096;

@internal
enum RawShapeType {
  // 0 is no shape, which the CPU never encodes.
  squircle(1),
  ellipse(2),
  roundedRectangle(3),

  /// A squircle whose two bottom corners have a different radius from its two
  /// top ones, drawn as two halves that meet on the split line (sdf.glsl's
  /// resolvePairHalf).
  squirclePair(4);

  const RawShapeType(this.shaderIndex);

  final double shaderIndex;

  String get _macro =>
      'SHAPE_${name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}')}'
          .toUpperCase();
}

@internal
const String shaderConstantsFile = 'shader_constants.glsl';

@internal
final String shaderConstantsGlsl =
    '''
#ifndef SHADER_CONSTANTS_GLSL
#define SHADER_CONSTANTS_GLSL

#define GEOMETRY_MAX_SHAPES $geometryMaxShapesPerDraw
const float kFarOutside = $kFarOutside;
${[for (final type in RawShapeType.values) '#define ${type._macro} ${type.shaderIndex}'].join('\n')}

#endif
''';
