// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

@visibleForTesting
bool isLocalTest = false;

final String _shadersRoot = !kIsWeb && isLocalTest
    ? ''
    : 'packages/liquid_glass_renderer/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  /// The compiled final shader [name], a FinalShaderVariant's.
  static String finalRender(String name) =>
      '${_shadersRoot}build/shaderbundles/$name.iplr';

  /// The compiled shader a LiquidGlassBackdropFrost draws a copy with.
  static final String backdropFrost =
      '${_shadersRoot}build/shaderbundles/backdrop_frost.iplr';

  /// The compiled shader that draws a narrow frost into a copy in one pass.
  static final String backdropFrostSquare =
      '${_shadersRoot}build/shaderbundles/backdrop_frost_square.iplr';

  /// The compiled shader that draws one axis of a frost into a copy.
  static final String backdropFrostAxis =
      '${_shadersRoot}build/shaderbundles/backdrop_frost_axis.iplr';

  static final fakeGlassSurface =
      '${_shadersRoot}lib/assets/shaders/fake_glass_surface.frag';

  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/liquid_glass_renderer.shaderbundle';
}
