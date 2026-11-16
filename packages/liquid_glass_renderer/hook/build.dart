import 'dart:io';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:hooks/hooks.dart';
import 'package:liquid_glass_renderer/src/composer/shader_constants.dart';

/// The prefixes of the runtime-effect shaders compiled to `.iplr` by this
/// hook instead of being listed under `flutter.shaders` in the pubspec: every
/// `liquid_glass_final_render*.frag`, one per final shader variant
/// (`FinalShaderVariant`), the `backdrop_frost*.frag` and the
/// `backdrop_haze*.frag`.
///
/// `flutter.shaders` are compiled for every backend a target platform
/// supports, including SkSL. These shaders use sampling that SkSL cannot
/// express, which makes Impeller-capable builds print a warning and Skia-only
/// builds (such as `flutter build web`) fail outright. Compiling here bundles
/// the same `.iplr` output that `FragmentProgram.fromAsset` decodes on
/// Impeller, while Skia builds never attempt a SkSL compile.
const _runtimeEffectPrefixes = [
  'liquid_glass_final_render',
  'backdrop_frost',
  'backdrop_haze',
];

void main(List<String> args) async {
  await build(args, (input, output) async {
    final constantsDirectory = _writeShaderConstants(input);
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'liquid_glass_renderer.shaderbundle.json',
      includeDirectories: [
        input.packageRoot.resolve('lib/assets/shaders/gpu/'),
        input.packageRoot.resolve('lib/assets/shaders/'),
        constantsDirectory,
      ],
      glesLanguageVersion: 300,
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
    );
    await _buildRuntimeEffects(input, output, constantsDirectory);
  });
}

Uri _writeShaderConstants(BuildInput input) {
  final directory = input.outputDirectory.resolve('shader_include/');
  final file = File.fromUri(directory.resolve(shaderConstantsFile));
  if (!file.existsSync() || file.readAsStringSync() != shaderConstantsGlsl) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(shaderConstantsGlsl)
      // The shaders name the file as a dependency, and the runner takes a
      // dependency newer than the build's start for an edit made during
      // the build: it is as new as the file it is written from.
      ..setLastModifiedSync(
        File.fromUri(
          input.packageRoot.resolve('lib/src/composer/shader_constants.dart'),
        ).lastModifiedSync(),
      );
  }
  return directory;
}

/// Compiles each shader named after one of [_runtimeEffectPrefixes] to
/// `build/shaderbundles/<name>.iplr`, an Impeller runtime-effect library
/// covering every backend except SkSL.
Future<void> _buildRuntimeEffects(
  BuildInput input,
  BuildOutputBuilder output,
  Uri constantsDirectory,
) async {
  final packageRoot = input.packageRoot;
  final shadersDirectory = packageRoot.resolve('lib/assets/shaders/');
  final outputDirectory = Directory.fromUri(
    packageRoot.resolve('build/shaderbundles/'),
  );
  await outputDirectory.create(recursive: true);

  final impellercExec = await findImpellerC();
  final help = Process.runSync(impellercExec.toFilePath(), ['--help']);
  final supportsDepfile =
      help.exitCode == 0 && impellerCHelpSupportsDepfile(help.stdout as String);
  final shaderLibDirectory = impellercExec.resolve('./shader_lib');

  final names = [
    for (final file in Directory.fromUri(shadersDirectory).listSync())
      if (file.uri.pathSegments.last case final name
          when _runtimeEffectPrefixes.any(name.startsWith) &&
              name.endsWith('.frag'))
        name.substring(0, name.length - '.frag'.length),
  ]..sort();
  // A shader added or removed changes the listing.
  output.dependencies.add(shadersDirectory);
  // A file the shaders include: impellerc names the ones a shader read only
  // where it writes a depfile, and the bundle's shaders name none. An edit
  // to one compiles everything again.
  for (final file in Directory.fromUri(
    shadersDirectory,
  ).listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.glsl')) {
      output.dependencies.add(file.uri);
    }
  }
  for (final name in names) {
    final source = shadersDirectory.resolve('$name.frag');
    final outFile = outputDirectory.uri.resolve('$name.iplr');
    final spirv = File('${outFile.toFilePath()}.spirv');
    final depfile = File('${outFile.toFilePath()}.d');

    final result = Process.runSync(impellercExec.toFilePath(), [
      '--runtime-stage-metal',
      '--runtime-stage-gles',
      '--runtime-stage-gles3',
      '--runtime-stage-vulkan',
      '--iplr',
      '--input=${source.toFilePath()}',
      '--input-type=frag',
      '--sl=${outFile.toFilePath()}',
      '--spirv=${spirv.path}',
      '--include=${shadersDirectory.toFilePath()}',
      '--include=${constantsDirectory.toFilePath()}',
      '--include=${shaderLibDirectory.toFilePath()}',
      if (supportsDepfile) '--depfile=${depfile.path}',
    ], workingDirectory: packageRoot.toFilePath());
    if (result.exitCode != 0) {
      throw Exception(
        'Failed to compile runtime-effect shader "$name": '
        '${result.stderr}\n${result.stdout}',
      );
    }

    output.dependencies.add(source);
    if (depfile.existsSync()) {
      output.dependencies.addAll(
        parseImpellerCDepfileDependencies(
          depfile.readAsStringSync(),
          relativeTo: packageRoot,
        ),
      );
      depfile.deleteSync();
    }
    spirv.deleteSync();
  }

  // `impellerc` ships in lockstep with the engine, so the produced files are
  // only valid for the SDK that compiled them. Declaring the compiler (and a
  // stamp of it) as a dependency reruns this hook when a different SDK rewrote
  // the shared `build/` output.
  output.dependencies.add(impellercExec);
  final stampUri = outputDirectory.uri.resolve(
    'runtime_effects.engine_stamp.json',
  );
  await writeEngineStampIfChanged(
    stampUri: stampUri,
    impellercExec: impellercExec,
  );
  output.dependencies.add(stampUri);
}
