import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

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
/// copy whose levels [strip] lays out from [at] of a texture of [texels] to
/// a pixel of the shader's size, each copy pixel [share] device pixels along
/// each side; with no [strip], a read of no levels. Where the levels blur,
/// every stop of [blur] takes the [frost], in device pixels, the copy leaves
/// to it ([blurAdding]).
@internal
List<double> copyLanes({
  required LevelStrip? strip,
  required GlassBlur blur,
  double frost = 0,
  Offset at = Offset.zero,
  double texels = 1,
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
  final stride = strip.fillStride.toDouble();
  final fill = at + strip.fillCellsAt;
  final fillOffset = stride > 0
      ? Offset(
          fill.dx + (grid.dx - at.dx) / stride - (grid.dx / stride).floor(),
          fill.dy + (grid.dy - at.dy) / stride - (grid.dy / stride).floor(),
        )
      : Offset.zero;
  return laneBlock(CopyLane.values, {
    CopyLane.levelTexels: [texels],
    CopyLane.levelGrid: [grid.dx, grid.dy],
    CopyLane.levelCopyAt: [at.dx, at.dy],
    CopyLane.levelRow: [at.dy + strip.cellsTop],
    CopyLane.levelBlurAt: [at.dx + strip.columnOf(strip.first)],
    CopyLane.levelWidth: [strip.width.toDouble()],
    CopyLane.levelShare: [share.toDouble()],
    CopyLane.levelFinest: [strip.first.toDouble()],
    CopyLane.levelCoarsest: [if (strip.blurs) strip.last.toDouble() else 0],
    CopyLane.blurSigmas: strip.blurs
        ? [for (final sigma in blur.sigmas) blurAdding(sigma, frost)]
        : GlassBlur.none.sigmas,
    CopyLane.blurDepths: blur.depths,
    CopyLane.fillInverseStride: [if (stride > 0) 1 / stride else 0],
    CopyLane.fillMix: stride > 0 ? blur.fillMix : GlassBlur.none.fillMix,
    CopyLane.fillOffset: [fillOffset.dx, fillOffset.dy],
  });
}

final _noLevels = <int, List<double>>{};

/// The levels a copy carries beside it ([LevelStrip]), drawn by one or two
/// layers the copy is drawn in. The inner one averages the copy into the
/// levels up to [coarseSourceLevel]; the outer one averages that level into
/// the coarser levels and the fill level.
///
/// NEAR: a cell at the copy's edge weighs the edge's own pixels again for
/// what lies past it. A layer that a clip cuts short of the strip carries no
/// levels (`CornerPlace.levels`).
@internal
final class CopyLevelPasses extends PinnedPasses {
  const CopyLevelPasses._(super.filters);

  /// Whether the levels' program is loaded; where it is not, starts loading
  /// it.
  static bool get ready =>
      GlassShaderPrograms.load(ShaderProgram.copyLevels.key) != null;

  /// What draws [strip] under a copy whose top left lies at [at] of the
  /// layers, or null where the program is not loaded yet.
  static CopyLevelPasses? of(LevelStrip strip, Offset at) =>
      _of(strip.withGrid(_phaseOf(strip)), at);

  // Where [strip]'s copy lies on the screen's grid up to whole periods of
  // the passes: a cell of level k starts on the grid every 2^k pixels and a
  // fill cell every fillStride, so the passes draw the same strip for any
  // grid that many pixels on, as glass moving across the screen passes it.
  static Offset _phaseOf(LevelStrip strip) {
    final cell = 1 << strip.last;
    final stride = strip.fillStride;
    final period = stride > 0 ? cell * stride ~/ _gcd(cell, stride) : cell;
    return Offset(strip.grid.dx % period, strip.grid.dy % period);
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// What draws [strip] at its own grid, which [of] takes up to its period.
  @visibleForTesting
  static CopyLevelPasses? debugAtGrid(LevelStrip strip, Offset at) =>
      _of(strip, at);

  static CopyLevelPasses? _of(LevelStrip strip, Offset at) {
    final key = (strip, at);
    if (_cached[key] case final held?) return held;
    final shader = GlassShaderPrograms.sharedShader(
      ShaderProgram.copyLevels.key,
    );
    if (shader == null) return null;
    if (_cached.length >= _mostHeld) _cached.clear();

    final top = at.dy + strip.top;
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
      // The shader holds other uniforms by the time a scene takes its
      // filter.
      return inputShaderFilterNow(shader);
    }

    final fine = pass(
      from: strip.first.toDouble(),
      to: coarseSourceLevel.toDouble(),
      fill: false,
      source: grid - at,
      stride: 1,
      bounds: copy.deflate(0.5),
    );
    if (strip.passes == 1) return _cached[key] = CopyLevelPasses._([fine]);
    const source = coarseSourceLevel;
    const stride = 1 << source;
    final base = at + Offset(strip.columnOf(source).toDouble(), strip.cellsTop);
    final coarse = pass(
      from: (source + 1).toDouble(),
      to: strip.last.toDouble(),
      fill: strip.fillStride > 0,
      source: Offset(
        stride * ((grid.dx / stride).floor() - base.dx),
        stride * ((grid.dy / stride).floor() - base.dy),
      ),
      stride: stride.toDouble(),
      bounds: (base & strip.cellsOf(source)).inflate(0.5),
    );
    return _cached[key] = CopyLevelPasses._([coarse, fine]);
  }
}

// Chrome over a scroll keeps a copy's place, so its levels too; glass in the
// scroll comes back to its phases of the grid.
final _cached = <Object, CopyLevelPasses>{};

// A few reads in motion, each through the phases of its period.
const _mostHeld = 512;
