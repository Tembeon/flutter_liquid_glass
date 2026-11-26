import 'package:meta/meta.dart';

/// Whether shaders load from the package's own folder, as in its tests,
/// rather than from the assets of an app that depends on it.
@visibleForTesting
bool isLocalTest = false;

final String _shadersRoot = isLocalTest
    ? ''
    : 'packages/liquid_glass_renderer/';

/// The folder of the package the shader programs' sources lie in, each a
/// `.frag` at its top.
const String shaderSources = 'lib/assets/shaders/';

/// The folder of the package the build hook writes its programs to.
const String shaderBundles = 'build/shaderbundles/';

/// What builds a shader program from its source.
enum ShaderCompiler {
  /// The Flutter tool, from `flutter.shaders` in the pubspec, for every
  /// backend including SkSL: drawn on any engine.
  flutterTool,

  /// The package's build hook, to `<stem>.iplr` in [shaderBundles], for
  /// Impeller's backends alone: drawn where the engine draws shader filters.
  /// It builds every program of [shaderSources] the Flutter tool does not.
  ///
  /// `flutter.shaders` are compiled to SkSL too, which these programs'
  /// sampling cannot be written in: Impeller builds would warn and Skia
  /// builds (such as `flutter build web`) fail.
  hook;

  /// The asset key of the program of [stem] this compiler builds.
  String keyOf(String stem) => switch (this) {
    flutterTool => '$_shadersRoot$shaderSources$stem.frag',
    hook => '$_shadersRoot$shaderBundles$stem.iplr',
  };
}

/// The shader programs glass draws with, but for the final shader's
/// variants (FinalShaderVariant), which the hook builds.
enum ShaderProgram {
  /// The surface of fake glass.
  fakeGlassSurface('fake_glass_surface', ShaderCompiler.flutterTool),

  /// The surface of a fake glass body a field describes.
  fakeGlassFieldSurface(
    'fake_glass_field_surface',
    ShaderCompiler.flutterTool,
  ),

  /// Content drawn over a shape with its colors parted.
  bentContent('bent_content', ShaderCompiler.flutterTool),

  /// A copy drawn through a LiquidGlassBackdropFrost.
  backdropFrost('backdrop_frost', ShaderCompiler.hook),

  /// A narrow frost drawn into a copy in one pass.
  backdropFrostSquare('backdrop_frost_square', ShaderCompiler.hook),

  /// One axis of a frost drawn into a copy.
  backdropFrostAxis('backdrop_frost_axis', ShaderCompiler.hook),

  /// The levels a copy carries beside it.
  copyLevels('copy_levels', ShaderCompiler.hook);

  const ShaderProgram(this.stem, this.compiler);

  /// The name of its source in [shaderSources], without `.frag`.
  final String stem;

  /// What builds it.
  final ShaderCompiler compiler;

  /// Its asset key.
  String get key => compiler.keyOf(stem);
}

/// The name of the Flutter GPU shader bundle of the geometry renderer,
/// which the hook builds into [shaderBundles] from
/// `<name>.shaderbundle.json` at the package's root.
const String geometryBundleName = 'liquid_glass_renderer';

/// The asset key of the Flutter GPU shader bundle of the geometry renderer.
String get geometryBundleKey =>
    '$_shadersRoot$shaderBundles$geometryBundleName.shaderbundle';
