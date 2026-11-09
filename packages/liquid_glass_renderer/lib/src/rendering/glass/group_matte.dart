import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/shape_set.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// One glass of a group: its `shapes`, where their origin lies on the
/// screen (`onScreen`, device pixels), the rect its shader paints (`drawn`,
/// the screen's logical pixels) and the `appearance` it draws with.
@internal
typedef GroupMember = ({
  ShapeSet shapes,
  Offset onScreen,
  Rect drawn,
  LiquidGlassAppearance appearance,
});

/// What the first glass of a group draws the group's matte with.
@internal
typedef GroupLead = ({
  LiquidGlassSettings settings,
  double devicePixelRatio,
  int matteScale,
  double contourOutset,
  LiquidGlassAppearance fallback,
});

/// One matte of a group's glass, its origin on the first's. Glass that moves
/// together lies where it lay in it, so a scroll under it renders nothing and
/// only moves the mapping.
@internal
final class GroupMatte {
  /// A group matte, drawn with Flutter GPU, which glass with a group has.
  GroupMatte()
    : _renderer = FlutterGpuGeometryRenderer.tryCreateCached(
        ShaderKeys.gpuGeometryShaderBundle,
      )!;

  /// How many times a group's matte was drawn.
  @visibleForTesting
  static int debugRenders = 0;

  final FlutterGpuGeometryRenderer _renderer;
  var _signature = const <Object?>[];

  /// The matte, once gathered.
  ui.Image? image;

  /// Where the matte lies, in logical pixels from [origin].
  Rect bounds = Rect.zero;

  /// The size of the texture the matte fills the top-left of.
  Size textureSize = Size.zero;

  /// The tint of each shape, where they differ; a low-resolution map, so
  /// glass reads it as the color of the nearest shape. NEAR: 8 bits a
  /// channel where a uniform holds the tint exactly.
  ui.Image? tints;

  /// The size of the texture [tints] fills the top-left of.
  Size tintsSize = const Size(1, 1);

  /// Where the matte's origin lies on the screen, in logical pixels.
  Offset origin = Offset.zero;

  /// Draws the matte of [glass] again, unless it lies as it lay.
  void gather(List<GroupMember> glass, GroupLead lead) {
    final dpr = lead.devicePixelRatio;
    final base = glass.first.onScreen;
    origin = base / dpr;
    // A 64th of a pixel keeps rounding in the layers' moves from drawing the
    // matte again; the glass lies that much off, unseen.
    double fixed(double value) => (value * 64).roundToDouble() / 64;
    final signature = <Object?>[lead.settings, dpr, lead.matteScale];
    for (final member in glass) {
      final at = member.onScreen - base;
      signature.addAll([
        member.shapes,
        member.appearance.tint,
        fixed(at.dx),
        fixed(at.dy),
      ]);
    }
    if (image != null && listEquals(signature, _signature)) return;
    _signature = signature;
    debugRenders++;
    final shapes = ShapeSet.join([
      for (final member in glass)
        (
          member.shapes,
          Offset(
            fixed(member.onScreen.dx - base.dx),
            fixed(member.onScreen.dy - base.dy),
          ),
        ),
    ]);
    Rect? rect;
    for (final member in glass) {
      final shown = member.drawn;
      final drawn = Rect.fromLTRB(
        shown.left * dpr - base.dx,
        shown.top * dpr - base.dy,
        shown.right * dpr - base.dx,
        shown.bottom * dpr - base.dy,
      );
      rect = rect?.expandToInclude(drawn) ?? drawn;
    }
    final all = rect!;
    final contour = matteRoom(dpr, lead.contourOutset) * dpr;
    final room = contour.ceilToDouble() + 2;
    final left = (all.left - room).floorToDouble();
    final top = (all.top - room).floorToDouble();
    final settings = lead.settings;
    final firstTint = glass.first.appearance.tint;
    final mixed = glass.any((member) => member.appearance.tint != firstTint);
    final result = _renderer.render(
      writeMaterials: mixed,
      writeTintOnly: mixed,
      appearanceData: mixed
          ? appearanceLookupData([
              for (final member in glass)
                for (var i = 0; i < member.shapes.count; i++) member.appearance,
            ], lead.fallback)
          : const <double>[],
      width: (all.right + room - left).ceil(),
      height: (all.bottom + room - top).ceil(),
      shapeData: shapes.shapes,
      rseData: shapes.superellipses,
      rseLowerData: shapes.superellipsesLower,
      boundsData: shapes.boxes,
      numShapes: shapes.count,
      refractionHeight: settings.effectiveRefractionHeight * dpr,
      refractionAmount: settings.effectiveRefractionAmount * dpr,
      edgeDistanceRange: settings.effectiveEdgeDistanceRange * dpr,
      refractionFitsShape: settings.refractionFitsShape,
      contourExtent: contour,
      offsetX: left,
      offsetY: top,
      matteScale: lead.matteScale,
    );
    image = result.image;
    bounds = Rect.fromLTWH(
      left / dpr,
      top / dpr,
      result.width / dpr,
      result.height / dpr,
    );
    textureSize = Size(
      result.textureWidth.toDouble(),
      result.textureHeight.toDouble(),
    );
    final map = mixed ? _renderer.materialImage : null;
    tints = map;
    tintsSize = map == null
        ? const Size(1, 1)
        : Size(map.width.toDouble(), map.height.toDouble());
  }

  /// Releases the renderer.
  void dispose() => _renderer.dispose();
}
