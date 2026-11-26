import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// Whether glass that reads copies blurs them as its recipe says and mixes
/// in its fill: false blurs them all over by the sigma Impeller's blur
/// delivers where the glass reads the backdrop, and leaves the fill out, so
/// a test can hold a copy against a backdrop read. Null and true draw the
/// recipe.
bool? debugGlassFill;

/// How glass blurs a copy it reads by depth, and mixes the copy's fill into
/// what it shows.
///
/// The blur runs piecewise linearly through four stops from the middle of
/// each shape to past its edge, as `BlurRecipe` does. The fill moves every
/// channel to the fill by one amount where the fill is lighter and by another
/// where it is darker, then covers the result, as `BlurFillRecipe` does.
@internal
@immutable
final class GlassBlur {
  /// A blur of [sigmas] at its stops and a fill mixed in by [fillMix].
  const GlassBlur({
    required this.sigmas,
    required this.depths,
    required this.fillMix,
  });

  /// No blur and no fill.
  static const none = GlassBlur(
    sigmas: [0, 0, 0, 0],
    depths: [0, 0, 0],
    fillMix: [0, 0, 0],
  );

  /// The sigmas, in device pixels, at the ramp's four stops from the deepest.
  final List<double> sigmas;

  /// The depths, in the geometry's pixels, of the stops after the deepest,
  /// which lies at the middle of each shape.
  final List<double> depths;

  /// How far a channel moves to the fill where the fill is lighter and where
  /// it is darker, and how much of the result the fill covers.
  final List<double> fillMix;

  /// This blur with [frost] device pixels added at every stop, as Gaussians
  /// add, where it blurs at all.
  GlassBlur adding(double frost) => frost <= 0 || sigmas.every((s) => s <= 0)
      ? this
      : GlassBlur(
          sigmas: [for (final s in sigmas) sqrt(s * s + frost * frost)],
          depths: depths,
          fillMix: fillMix,
        );

  @override
  bool operator ==(Object other) =>
      other is GlassBlur &&
      listEquals(other.sigmas, sigmas) &&
      listEquals(other.depths, depths) &&
      listEquals(other.fillMix, fillMix);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(sigmas),
    Object.hashAll(depths),
    Object.hashAll(fillMix),
  );
}

/// The final shader's uCopy, by [CopyLane], for glass blurring by [blur] a
/// copy whose levels [strip] lays out from [at] of a texture of [texture]
/// pixels, each copy pixel [share] device pixels along each side; with no
/// [strip], a read of no levels.
@internal
List<double> copyLanes({
  required LevelStrip? strip,
  required GlassBlur blur,
  Offset at = Offset.zero,
  Size texture = Size.zero,
  int share = 1,
}) {
  if (strip == null) {
    return _noLevels[share] ??= laneBlock(CopyLane.values, {
      for (final lane in CopyLane.values)
        lane: lane == CopyLane.levelShare
            ? [share.toDouble()]
            : List<double>.filled(lane.width, 0),
    });
  }
  final grid = strip.grid;
  final row = at.dy + strip.copy.height + 1;
  final stride = strip.fillStride.toDouble();
  final fillOffset = stride > 0
      ? Offset(
          (at.dx +
                  1 +
                  (grid.dx - at.dx) / stride -
                  (grid.dx / stride).floor()) /
              texture.width,
          (row + (grid.dy - at.dy) / stride - (grid.dy / stride).floor()) /
              texture.height,
        )
      : Offset.zero;
  return laneBlock(CopyLane.values, {
    CopyLane.levelTexture: [texture.width, texture.height],
    CopyLane.levelGrid: [grid.dx, grid.dy],
    CopyLane.levelCopyAt: [at.dx, at.dy],
    CopyLane.levelRow: [row],
    CopyLane.levelBlurAt: [at.dx + strip.columnOf(strip.first)],
    CopyLane.levelWidth: [strip.width.toDouble()],
    CopyLane.levelShare: [share.toDouble()],
    CopyLane.levelFinest: [strip.first.toDouble()],
    CopyLane.levelCoarsest: [if (strip.blurs) strip.last.toDouble() else 0],
    CopyLane.blurSigmas: strip.blurs ? blur.sigmas : GlassBlur.none.sigmas,
    CopyLane.blurDepths: blur.depths,
    CopyLane.fillInverseStride: [if (stride > 0) 1 / stride else 0],
    CopyLane.fillMix: stride > 0 ? blur.fillMix : GlassBlur.none.fillMix,
    CopyLane.fillOffset: [fillOffset.dx, fillOffset.dy],
  });
}

final _noLevels = <int, List<double>>{};

/// The levels a copy carries beside it ([LevelStrip]), drawn by one or two
/// layers the copy is drawn in. The inner one averages the copy into levels
/// 1 and 2; the outer one averages level 2 into the coarser levels and the
/// fill level.
///
/// NEAR: a cell at the copy's edge weighs the edge's own pixels again for
/// what lies past it. A layer that a clip cuts short of the strip carries no
/// levels (`CornerPlace.levels`).
@internal
final class CopyLevelPasses {
  const CopyLevelPasses._(this._passes);

  // The filters, outermost first.
  final List<ui.ImageFilter> _passes;

  /// Whether the levels' program is loaded; where it is not, starts loading
  /// it.
  static bool get ready =>
      GlassShaderPrograms.load(ShaderKeys.copyLevels) != null;

  /// What draws [strip] under a copy whose top left lies at [at] of the
  /// layers, or null where the program is not loaded yet.
  static CopyLevelPasses? of(LevelStrip strip, Offset at) {
    final key = (strip, at);
    if (_held[key] case final held?) return held;
    final shader = GlassShaderPrograms.sharedShader(ShaderKeys.copyLevels);
    if (shader == null) return null;
    if (_held.length >= 32) _held.clear();

    final top = at.dy + strip.copy.height;
    final grid = strip.grid;
    final copy = at & strip.copy;
    ui.ImageFilter pass({
      required double from,
      required double to,
      required bool fill,
      required Offset source,
      required double stride,
      required Rect bounds,
    }) {
      putUniform(shader, 'uStrip', [
        at.dx,
        top,
        strip.fillColumns.toDouble(),
        strip.fillStride.toDouble(),
      ]);
      putUniform(shader, 'uLevels', [
        strip.width.toDouble(),
        strip.height.toDouble(),
        strip.first.toDouble(),
        strip.last.toDouble(),
      ]);
      putUniform(shader, 'uGrid', [grid.dx, grid.dy]);
      putUniform(shader, 'uPass', [from, to, if (fill) 1 else 0]);
      putUniform(shader, 'uSource', [source.dx, source.dy, stride]);
      putUniform(shader, 'uBounds', [
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom,
      ]);
      shader.setImageSampler(
        0,
        transparentPixel,
        filterQuality: FilterQuality.low,
      );
      // The shader holds other uniforms by the time a scene takes its
      // filter.
      return shaderFilterNow(shader);
    }

    final fine = pass(
      from: strip.first.toDouble(),
      to: 2,
      fill: false,
      source: grid - at,
      stride: 1,
      bounds: copy.deflate(0.5),
    );
    if (strip.passes == 1) return _held[key] = CopyLevelPasses._([fine]);
    // Level 2's cells, inside its ring.
    final base = Offset(at.dx + strip.columnOf(2), top + 1);
    final cells = Offset(strip.width / 4 + 1, strip.height / 4 + 1);
    final coarse = pass(
      from: 3,
      to: strip.last.toDouble(),
      fill: strip.fillStride > 0,
      source: Offset(
        4 * ((grid.dx / 4).floor() - base.dx),
        4 * ((grid.dy / 4).floor() - base.dy),
      ),
      stride: 4,
      bounds: Rect.fromLTRB(
        base.dx - 0.5,
        base.dy - 0.5,
        base.dx + cells.dx + 0.5,
        base.dy + cells.dy + 0.5,
      ),
    );
    return _held[key] = CopyLevelPasses._([coarse, fine]);
  }

  /// Pushes the levels' layers, each held to [size] from [origin]; what is
  /// drawn until [pop], inside the copy's part of them, comes out with its
  /// levels under it.
  void push(ui.SceneBuilder builder, Offset origin, Size size) {
    for (final pass in _passes) {
      PinnedLayers.push(builder, pass, origin, size);
    }
  }

  /// Ends what [push] began.
  void pop(ui.SceneBuilder builder) {
    for (var i = 0; i < _passes.length; i++) {
      builder.pop();
    }
  }
}

// Chrome over a scroll keeps a copy's place, so its levels too.
final _held = <Object, CopyLevelPasses>{};
