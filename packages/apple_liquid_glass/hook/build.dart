import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _assetName = 'apple_liquid_glass.dylib';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final platform = switch (code.targetOS) {
      OS.iOS => _iOS(code),
      OS.macOS => _macOS(code),
      _ => null,
    };
    if (platform == null) return;
    final architecture = switch (code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      final other => throw UnsupportedError('No build for $other'),
    };
    final sdk = await _firstLine('xcrun', [
      '--show-sdk-path',
      '--sdk',
      platform.sdk,
    ]);
    final compiler = code.cCompiler?.compiler.toFilePath() ?? 'clang';
    final flags = [
      '-isysroot',
      sdk,
      '-target',
      '$architecture-apple-${platform.target}',
    ];

    final shared = input.packageRoot.resolve('src/');
    final own = shared.resolve('${platform.directory}/');
    final sources = [
      for (final directory in [shared, own])
        for (final entity in Directory.fromUri(directory).listSync())
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
        '-I',
        shared.toFilePath(),
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
      if (code.targetOS == OS.iOS) '-Wl,-encryptable',
      for (final framework in platform.frameworks) ...['-framework', framework],
      '-weak_framework',
      'Accessibility',
      ...built,
      '-o',
      library.toFilePath(),
    ]);

    output.dependencies
      ..add(shared)
      ..add(own)
      ..add(shared.resolve('glass_platform.h'))
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

typedef _Platform = ({
  String sdk,
  String target,
  String directory,
  List<String> frameworks,
});

_Platform _iOS(CodeConfig code) {
  final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
  final version = code.iOS.deploymentVersion;
  return (
    sdk: simulator ? 'iphonesimulator' : 'iphoneos',
    target:
        'ios${version.major}.${version.minor}${simulator ? '-simulator' : ''}',
    directory: 'ios',
    frameworks: const ['Foundation', 'UIKit'],
  );
}

_Platform _macOS(CodeConfig code) {
  final version = code.macOS.deploymentVersion;
  return (
    sdk: 'macosx',
    target: 'macos${version.major}.${version.minor}',
    directory: 'macos',
    frameworks: const ['Foundation', 'AppKit'],
  );
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
