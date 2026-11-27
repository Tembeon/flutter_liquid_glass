import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';

/// [ui.ImageFilter.shader] over [shader], reading its input bilinearly.
///
/// Up to Flutter 3.47 the filter samples its input as the image bound to the
/// shader's first sampler says, and the glass binds one there with
/// [ui.FilterQuality.low]. From 3.50 the input ignores that image and takes
/// the filter's own `filterQuality`, nearest unless asked; this asks for
/// [ui.FilterQuality.low] wherever the parameter exists.
@internal
ui.ImageFilter bilinearShaderFilter(ui.FragmentShader shader) {
  if (!kReleaseMode) GlassWork.filters++;
  const Object create = ui.ImageFilter.shader;
  if (create
      is ui.ImageFilter Function(
        ui.FragmentShader shader, {
        ui.FilterQuality filterQuality,
      })) {
    return create(shader, filterQuality: ui.FilterQuality.low);
  }
  return ui.ImageFilter.shader(shader);
}

/// [bilinearShaderFilter] holding the uniforms [shader] has now, which a
/// filter otherwise takes when a paint or a scene first holds it.
@internal
ui.ImageFilter shaderFilterNow(ui.FragmentShader shader) {
  final filter = bilinearShaderFilter(shader);
  ui.Paint().imageFilter = filter;
  return filter;
}

/// One transparent pixel: what a sampler is bound to where a draw has no image
/// of its own for it.
@internal
final ui.Image transparentPixel = () {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  return recorder.endRecording().toImageSync(1, 1);
}();

/// [shaderFilterNow] of [shader], whose first sampler is what the filter
/// reads: bound to [transparentPixel] at [ui.FilterQuality.low], which up to
/// Flutter 3.47 is how the filter samples its input.
@internal
ui.ImageFilter inputShaderFilterNow(ui.FragmentShader shader) {
  shader.setImageSampler(0, transparentPixel, filterQuality: FilterQuality.low);
  return shaderFilterNow(shader);
}
