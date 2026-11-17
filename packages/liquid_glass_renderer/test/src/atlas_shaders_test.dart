import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/atlas_shaders.dart';

const _update = bool.fromEnvironment('UPDATE_SHADER_CONSTANTS');

void main() {
  final files = {
    'liquid_glass_renderer.shaderbundle.json': AtlasShader.bundle,
    for (final shader in AtlasShader.all)
      if (shader.source case final source?) shader.file: source,
  };
  for (final MapEntry(key: path, value: text) in files.entries) {
    test('$path is written from AtlasShader', () {
      final file = File(path);
      if (_update) {
        file.writeAsStringSync(text);
        return;
      }
      expect(
        file.readAsStringSync(),
        text,
        reason:
            'Run with --dart-define=UPDATE_SHADER_CONSTANTS=true after '
            'changing atlas_shaders.dart.',
      );
    });
  }

  test('every atlas shader has its file', () {
    for (final shader in AtlasShader.all) {
      expect(File(shader.file).existsSync(), isTrue, reason: shader.name);
    }
  });
}
