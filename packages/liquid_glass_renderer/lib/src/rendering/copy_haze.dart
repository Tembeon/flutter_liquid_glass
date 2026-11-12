import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:meta/meta.dart';

// The hazes' filters, held across frames: dart:ui converts each new filter
// to a native one again. A filter is bound to the size of its copy, which
// holds while glass moves, so the held ones are dropped all at once when
// they grow past a handful.
final _filters = <(double, double, ui.Size), ui.ImageFilter>{};

/// Whether glass draws its haze into the copies it reads: false frosts it
/// by the one blur that stands in for the haze, as where it reads the
/// backdrop live. For comparing the two; null and true draw the haze.
bool? debugGlassHaze;

/// How many haze filters were made, for tests that count what a frame
/// creates.
@visibleForTesting
int debugHazeFiltersMade = 0;

// The wide blur of what lies inside [size] alone, drawn with [alpha].
//
// The blur is bounded: it weighs only what lies inside the copy and divides
// by the weight it found, so the empty layer around a copy neither darkens
// its edge nor shows through.
ui.ImageFilter _filter(double sigma, double alpha, ui.Size size) {
  final key = (sigma, alpha, size);
  if (_filters[key] case final held?) return held;
  if (_filters.length >= 16) _filters.clear();
  debugHazeFiltersMade++;
  final blur = ui.ImageFilter.blur(
    sigmaX: sigma,
    sigmaY: sigma,
    tileMode: ui.TileMode.clamp,
    bounds: ui.Offset.zero & size,
  );
  return _filters[key] = alpha >= 1
      ? blur
      : ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(<double>[
            1, 0, 0, 0, 0, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 0, //
            0, 0, 0, alpha, 0, //
          ]),
          inner: blur,
        );
}

/// Mixes [haze] into what the layer [builder] is building holds inside
/// [rect], a copy of [pixels] of its own pixels a logical pixel.
///
/// Each mix is a backdrop filter of the layer: it reads the copy drawn so
/// far, blurs it wide and blends the blur back over it. A blur drawn at an
/// alpha with [ui.BlendMode.lighten] moves every channel that far to the
/// blur where the blur is lighter and leaves it where it is darker, which is
/// the mix itself; [ui.BlendMode.darken] is its mirror. The cover goes
/// first: the lighter or darker of a covered copy and its blur is the cover
/// of the lighter or darker of the two.
///
/// NEAR: the second mix blurs the covered copy, which already holds a share
/// of the blur, where iOS blurs the backdrop once. A blur of a blur by the
/// same sigma is 1.4 times as wide, and the cover's share of it is small
/// where the two differ most (the slider near `0`).
@internal
void addHaze(
  ui.SceneBuilder builder,
  LiquidGlassHaze haze,
  ui.Rect rect,
  double pixels,
) {
  if (haze.isNone || rect.isEmpty) return;
  final sigma = haze.sigma * pixels;
  final cover = haze.cover.clamp(0.0, 1.0);
  builder
    ..pushOffset(rect.left, rect.top)
    ..pushClipRect(ui.Offset.zero & rect.size, clipBehavior: ui.Clip.hardEdge);
  void mix(double alpha, ui.BlendMode mode) {
    if (alpha <= 0) return;
    builder
      ..pushBackdropFilter(
        _filter(sigma, alpha.clamp(0.0, 1.0), rect.size),
        blendMode: mode,
      )
      ..pop();
  }

  mix(cover, ui.BlendMode.srcOver);
  if (cover < 1) {
    mix(haze.lighten, ui.BlendMode.lighten);
    mix(haze.darken, ui.BlendMode.darken);
  }
  builder
    ..pop()
    ..pop();
}
