import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

/// Whether shaders load from the package's own folder, as in its tests,
/// rather than from the assets of an app that depends on it.
@visibleForTesting
bool isLocalTest = false;

final String _shadersRoot = !kIsWeb && isLocalTest
    ? ''
    : 'packages/liquid_glass_renderer/';

/// The asset keys of the shaders glass draws with.
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

  /// The surface shader of fake glass.
  static final fakeGlassSurface =
      '${_shadersRoot}lib/assets/shaders/fake_glass_surface.frag';

  /// The Flutter GPU shader bundle of the geometry renderer.
  static final String gpuGeometryShaderBundle =
      '${_shadersRoot}build/shaderbundles/liquid_glass_renderer.shaderbundle';
}
