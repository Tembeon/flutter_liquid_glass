import 'dart:io';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:hooks/hooks.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

final _flutterTool = {
  for (final program in ShaderProgram.values)
    if (program.compiler == ShaderCompiler.flutterTool) '${program.stem}.frag',
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: '$geometryBundleName.shaderbundle.json',
      includeDirectories: [
        input.packageRoot.resolve('${shaderSources}gpu/'),
        input.packageRoot.resolve(shaderSources),
      ],
      glesLanguageVersion: 300,
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
    );
    await _buildRuntimeEffects(input, output);
  });
}

/// Compiles each program of [shaderSources] the Flutter tool does not build
/// to `<name>.iplr` in [shaderBundles], an Impeller runtime-effect library
/// covering every backend but SkSL ([ShaderCompiler.hook]).
Future<void> _buildRuntimeEffects(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  final packageRoot = input.packageRoot;
  final shadersDirectory = packageRoot.resolve(shaderSources);
  final outputDirectory = Directory.fromUri(
    packageRoot.resolve(shaderBundles),
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
          when file is File &&
              name.endsWith('.frag') &&
              !_flutterTool.contains(name))
        name.substring(0, name.length - '.frag'.length),
  ]..sort();
  // A shader added or removed changes the listing.
  output.dependencies.add(shadersDirectory);
  // The program of a source that went would stay among the assets.
  final built = {for (final name in names) '$name.iplr'};
  for (final file in outputDirectory.listSync()) {
    if (file is File &&
        file.path.endsWith('.iplr') &&
        !built.contains(file.uri.pathSegments.last)) {
      file.deleteSync();
    }
  }
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
