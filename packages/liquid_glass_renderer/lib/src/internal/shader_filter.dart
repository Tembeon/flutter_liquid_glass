import 'dart:ui' as ui;

import 'package:meta/meta.dart';

/// [ui.ImageFilter.shader] over [shader], reading its input bilinearly.
///
/// Up to Flutter 3.47 the filter samples its input as the image bound to the
/// shader's first sampler says, and the glass binds one there with
/// [ui.FilterQuality.low]. From 3.50 the input ignores that image and takes
/// the filter's own `filterQuality`, nearest unless asked; this asks for
/// [ui.FilterQuality.low] wherever the parameter exists.
@internal
ui.ImageFilter bilinearShaderFilter(ui.FragmentShader shader) {
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
