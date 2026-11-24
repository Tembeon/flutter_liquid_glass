import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _assetName = 'apple_liquid_glass.dylib';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    if (code.targetOS != OS.iOS) return;

    final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    final sdk = await _firstLine('xcrun', [
      '--show-sdk-path',
      '--sdk',
      if (simulator) 'iphonesimulator' else 'iphoneos',
    ]);
    final architecture = switch (code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      final other => throw UnsupportedError('No iOS build for $other'),
    };
    final version = code.iOS.deploymentVersion;
    final target =
        '$architecture-apple-ios${version.major}.${version.minor}'
        '${simulator ? '-simulator' : ''}';
    final compiler = code.cCompiler?.compiler.toFilePath() ?? 'clang';
    final flags = ['-isysroot', sdk, '-target', target];

    final sourceDirectory = input.packageRoot.resolve('src/ios/');
    final sources = [
      for (final entity in Directory.fromUri(sourceDirectory).listSync())
        if (entity is File && entity.path.endsWith('.m')) entity.path,
    ]..sort();
    final objects = input.outputDirectory.resolve('objects/');
    Directory.fromUri(objects).createSync(recursive: true);
    final built = <String>[];
    for (final source in sources) {
      final object = objects
          .resolve('${source.split('/').last}.o')
          .toFilePath();
      await _run(compiler, [
        ...flags,
        '-x',
        'objective-c',
        '-fobjc-arc',
        '-fpic',
        '-gline-tables-only',
        '-c',
        source,
        '-o',
        object,
      ]);
      built.add(object);
    }
    final library = input.outputDirectory.resolve(_assetName);
    await _run(compiler, [
      ...flags,
      '-shared',
      '-Wl,-encryptable',
      '-framework',
      'Foundation',
      '-framework',
      'UIKit',
      ...built,
      '-o',
      library.toFilePath(),
    ]);

    output.dependencies
      ..add(sourceDirectory)
      ..addAll(sources.map(Uri.file));
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        file: library,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

Future<String> _firstLine(String command, List<String> args) async {
  final result = await Process.run(command, args);
  return (result.stdout as String).trim().split('\n').first;
}

Future<void> _run(String command, List<String> args) async {
  final result = await Process.run(command, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      command,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
