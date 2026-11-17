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

  String get _macro => 'SHAPE_${_screaming(name)}';
}

/// `LiquidGlassField.opticalCornerScale`.
@internal
const double opticalCornerRadiusScale = 1.5;

/// The edge of a tile of a geometry atlas, in buffer pixels.
@internal
const int atlasTileSize = 16;

/// What the ramp of a quad of a geometry atlas says (gpu/tile_fill.glsl,
/// gpu/tile_geometry_fragment.glsl), in its first float.
@internal
abstract final class AtlasRamp {
  /// A quad at or above this writes constants: a tile wholly outside or deep
  /// inside, or the atlas's table.
  static const double fill = 128;

  /// A strip at or above this, less it, names the first of a run of shape
  /// rows; below, its four floats list the rows it evaluates.
  static const double run = 64;

  /// Added to a listed row where it starts its blend group.
  static const double startsGroup = geometryMaxShapesPerDraw * 1.0;

  /// A listed row past the last.
  static const double none = geometryMaxShapesPerDraw * 2.0;
}

/// The floats of a shape's row of the geometry draw, as the GPU shaders read
/// them in three vec4s: its primitive, its inverse basis, its placement.
@internal
enum ShapeLane {
  type,
  width,
  height,
  radius,
  inverseXX,
  inverseXY,
  inverseYX,
  inverseYY,
  centerX,
  centerY,
  distanceScale,

  /// The blend group's radius, negative (less one) where the shape starts
  /// its group.
  blendMarker,
}

/// The floats of a row of [lanes], in their order, from [values], which
/// names each lane once.
@internal
List<double> laneRow<L extends Enum>(List<L> lanes, Map<L, double> values) {
  assert(values.length == lanes.length, 'every lane of the row, once');
  return [for (final lane in lanes) values[lane]!];
}

/// The floats of a rounded superellipse's row (`sdfSquircle`), in three
/// vec4s: degrees and `1 - cos(span)` of its two octants, their circle
/// centers, their semi-axes and circle radii. A pair's bottom half holds its
/// bottom radius in [topAxis].
@internal
enum SquircleLane {
  topDegree,
  rightDegree,
  topSpan,
  rightSpan,
  topCenterX,
  topCenterY,
  rightCenterX,
  rightCenterY,
  topAxis,
  rightAxis,
  topRadius,
  rightRadius,
}

/// The glint's profile, which the final shader and FakeGlass draw and the
/// reach of glass's geometry follows.
///
/// iOS 27 recolors the glint, measured on the pinned solid-palette probes in
/// both appearances: it mixes the lit face toward a bright target whose
/// luminance sits above SDR white and whose chroma is the face's amplified.
@internal
abstract final class GlassGlint {
  /// The weight of the faint bleed inward of the glint line: a fifth of the
  /// line's.
  static const double bleed = 0.21;

  /// How many glint widths deep the bleed reaches.
  static const double bleedReach = 4;

  /// The line's strength at a highlight of 1: the simulator captures give a
  /// mix weight of 0.14, and an iPhone renders the same glass 1.8 times
  /// stronger.
  static const double peak = 0.252;

  /// The luminance of the target the direct model's glint pulls toward.
  static const double directLuminance = 1.6;

  /// How strongly the direct model's glint amplifies the face's chroma.
  static const double directVibrancy = 2.85;
}

/// How far the final shader shifts the backdrop at a glass's edge, which the
/// reach of the copy it reads follows.
@internal
abstract final class GlassShift {
  /// How far clear glass may shift the backdrop at its edge, as a share of
  /// half its short side; glass whose refraction fits its shape shifts it at
  /// most that far.
  static const double clearShare = 1.3;

  /// The share of the dispersion the outer colors move apart by.
  static const double dispersionSpread = 0.5;
}

/// The widest frost, in pixels of the copy, eight taps serve
/// (`frostEight` in frost.glsl): past it they speckle, and sixteen take over.
@internal
const double frostEightMost = 2.8;

/// How deep inside and how far outside its edge fake glass reads the
/// distance of a field body, in logical pixels: the range its 8-bit node
/// image holds, an eighth of a point a level. The bevel reaches about 22
/// points in and the contour a point or two out.
@internal
const double fakeFieldInside = 24;

/// See [fakeFieldInside].
@internal
const double fakeFieldOutside = 8;

/// The reads along a side of a cell that backdrop_haze_strip.frag has room
/// for.
@internal
const int hazeMostReads = 32;

/// Rec.709's luminance weights, the material's luminance basis: a
/// color-card fit on the host's Metal shows less blue and cyan transfer error
/// with them than with Rec.601's.
@internal
const lumaWeights = (0.2126, 0.7152, 0.0722);

/// The mirror that turns an edge's outward normal into the way glass parts
/// colors along, as the rows (x, y) and (y, z): the reflection across the
/// line 52.5 degrees from the right to the bottom, cos 105 and sin 105.
@internal
const partingMirror = (-0.258819, 0.965926, 0.258819);

/// A lane of the floats a pubspec shader reads, in an enum whose order is
/// the order Dart writes them in. The generated file of the enum names each
/// lane in the shader.
@internal
abstract interface class UniformLane implements Enum {
  /// How many floats the lane takes.
  int get width;
}

/// Where [lane] starts among the floats of [lanes].
@internal
int laneOffset(List<UniformLane> lanes, UniformLane lane) {
  var offset = 0;
  for (var i = 0; i < lane.index; i++) {
    offset += lanes[i].width;
  }
  return offset;
}

/// The floats [lanes] take in whole vec4s.
@internal
int laneBlockFloats(List<UniformLane> lanes) =>
    (laneOffset(lanes, lanes.last) + lanes.last.width + 3) ~/ 4 * 4;

/// The floats fake_glass_surface.frag reads after its size.
@internal
enum FakeSurfaceLane implements UniformLane {
  shapeType,
  cornerRadius,
  tint(4),
  highlight,
  highlightWidth,
  highlightWrap,
  oppositeHighlight,
  contourStrength,
  contourWidth,
  contourDirectionality,
  bevelStrength,
  bevelDepth,
  bevelOffset,
  bevelDirectionality,

  /// The logical size of one device pixel.
  pixelSize,

  /// 1 draws only the border ring outside the shape's clip.
  exteriorOnly,

  /// The luminance of the neutral glint target.
  glintLuminance,

  /// The premultiplied emission of the face the backdrop filter produced.
  faceEmission(3),

  /// The face's share of the glint target, as the color model's
  /// glintFaceGain.
  glintFaceGain,
  glintVibrancy,

  /// 1 draws only the additive highlight pass.
  highlightsOnly,

  /// A pair's bottom corner radius, or -1 for one radius.
  bottomRadius;

  const FakeSurfaceLane([this.width = 1]);

  @override
  final int width;
}

/// The floats bent_content.frag reads.
@internal
enum BentContentLane implements UniformLane {
  size(2),
  radius,

  /// 0 draws what the content takes of what lies under it, 1 the content.
  pass,

  /// Where the picture of the content starts in the shape's coordinates.
  pictureOrigin(2),

  /// One over the picture's size.
  pictureScale(2),

  /// The amount and height of the first bend, then of the second.
  bends(4),

  /// How far the colors part and how deep from the rim the parting fades.
  parting(2),

  /// Logical pixels per device pixel.
  pixel;

  const BentContentLane([this.width = 1]);

  @override
  final int width;
}

String _screaming(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

String _float(double value) {
  final text = value.toString();
  return text.contains('.') || text.contains('e') ? text : '$text.0';
}

String _vec3((double, double, double) value) =>
    'vec3(${_float(value.$1)}, ${_float(value.$2)}, ${_float(value.$3)})';

// The defines of [lanes] as lanes of `uniform vec4 [block][n]`, n the vec4s
// they fill: a lane within one vec4 a swizzle of it, one across two a vector
// of its floats.
String _lanes(String block, List<UniformLane> lanes) {
  String float(int at) => '$block[${at ~/ 4}].${'xyzw'[at % 4]}';
  return [
    'uniform vec4 $block[${laneBlockFloats(lanes) ~/ 4}];',
    for (final lane in lanes)
      () {
        final offset = laneOffset(lanes, lane);
        final width = lane.width;
        final name = 'u${lane.name[0].toUpperCase()}${lane.name.substring(1)}';
        if (width == 1) return '#define $name ${float(offset)}';
        final last = offset + width - 1;
        if (width == 4 && offset % 4 == 0) {
          return '#define $name $block[${offset ~/ 4}]';
        }
        if (offset ~/ 4 == last ~/ 4) {
          return '#define $name $block[${offset ~/ 4}].'
              '${'xyzw'.substring(offset % 4, last % 4 + 1)}';
        }
        return '#define $name vec$width('
            '${[for (var i = offset; i <= last; i++) float(i)].join(', ')})';
      }(),
  ].join('\n');
}

String _rows(String prefix, List<Enum> lanes, List<String> vec4s) => [
  '#define ${prefix}_ROW_VEC4S ${lanes.length ~/ 4}',
  for (var i = 0; i < vec4s.length; i++) '#define ${prefix}_${vec4s[i]} $i',
].join('\n');

String _guarded(String name, String body) {
  final guard = _screaming(name.replaceAll('.', '_'));
  return '''
// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef $guard
#define $guard

$body

#endif
''';
}

/// The GLSL files written from this table, by name in lib/assets/shaders.
@internal
final Map<String, String> generatedShaderFiles = {
  'shader_constants.glsl': _guarded('shader_constants.glsl', '''
#define GEOMETRY_MAX_SHAPES $geometryMaxShapesPerDraw
#define SHAPE_INDEX_MASK ${geometryMaxShapesPerDraw - 1}
const float kFarOutside = ${_float(kFarOutside)};
${[for (final type in RawShapeType.values) '#define ${type._macro} ${_float(type.shaderIndex)}'].join('\n')}

#define ATLAS_TILE_SIZE ${_float(atlasTileSize.toDouble())}
#define RAMP_FILL ${_float(AtlasRamp.fill)}
#define RAMP_RUN ${_float(AtlasRamp.run)}
#define MEMBER_STARTS_GROUP ${_float(AtlasRamp.startsGroup)}
#define MEMBER_NONE ${_float(AtlasRamp.none)}

${_rows('SHAPE', ShapeLane.values, ['PRIMITIVE', 'INVERSE_BASIS', 'PLACEMENT'])}
${_rows('SQUIRCLE', SquircleLane.values, ['DEGREES_AND_SPANS', 'CIRCLE_CENTERS', 'AXES_AND_RADII'])}
const float kOpticalCornerRadiusScale = ${_float(opticalCornerRadiusScale)};

const float kGlintBleed = ${_float(GlassGlint.bleed)};
const float kGlintBleedReach = ${_float(GlassGlint.bleedReach)};
const float kGlintPeak = ${_float(GlassGlint.peak)};
const float kGlintLuminance = ${_float(GlassGlint.directLuminance)};
const float kGlintVibrancy = ${_float(GlassGlint.directVibrancy)};
const float kClearShiftShare = ${_float(GlassShift.clearShare)};
const float kDispersionSpread = ${_float(GlassShift.dispersionSpread)};
const float kFrostEightMost = ${_float(frostEightMost)};
const float kFakeFieldInside = ${_float(fakeFieldInside)};
const float kFakeFieldOutside = ${_float(fakeFieldOutside)};
#define HAZE_MOST_READS $hazeMostReads
const vec3 LUMA_WEIGHTS = ${_vec3(lumaWeights)};
const vec3 kPartingMirror = ${_vec3(partingMirror)};'''),
  'fake_glass_lanes.glsl': _guarded(
    'fake_glass_lanes.glsl',
    _lanes('uFake', FakeSurfaceLane.values),
  ),
  'bent_content_lanes.glsl': _guarded(
    'bent_content_lanes.glsl',
    _lanes('uBent', BentContentLane.values),
  ),
};
