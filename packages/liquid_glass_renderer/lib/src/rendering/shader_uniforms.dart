import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

/// Writes [floats] into [shader] from float [at] on, and returns the float
/// after them.
int putFloats(ui.FragmentShader shader, int at, List<double> floats) {
  for (var i = 0; i < floats.length; i++) {
    shader.setFloat(at + i, floats[i]);
  }
  return at + floats.length;
}

/// Writes every lane of [lanes] from [values] into [shader], a block of whole
/// vec4s from float [at] on, and returns the float after the block.
int putLanes<L extends UniformLane>(
  ui.FragmentShader shader,
  int at,
  List<L> lanes,
  Map<L, List<double>> values,
) {
  var offset = at;
  for (final lane in lanes) {
    final floats = values[lane]!;
    assert(floats.length == lane.width, '$lane takes ${lane.width} floats');
    offset = putFloats(shader, offset, floats);
  }
  return at + laneBlockFloats(lanes);
}
