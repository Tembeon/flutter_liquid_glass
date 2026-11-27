import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

void main() {
  test('every program of the shaders folder is in the table', () {
    final sources = {
      for (final file in Directory(shaderSources).listSync())
        if (file is File && file.path.endsWith('.frag'))
          file.uri.pathSegments.last,
    };
    expect(sources, {
      for (final program in ShaderProgram.values) '${program.stem}.frag',
      for (final variant in FinalShaderVariant.all) '${variant.name}.frag',
    });
  });

  test('the pubspec lists the programs the Flutter tool builds', () {
    const item = '    - ';
    final lines = File('pubspec.yaml').readAsLinesSync();
    final listed = {
      for (final line
          in lines
              .skip(lines.indexOf('  shaders:') + 1)
              .takeWhile((line) => line.startsWith(item)))
        line.substring(item.length),
    };
    expect(listed, {
      for (final program in ShaderProgram.values)
        if (program.compiler == ShaderCompiler.flutterTool)
          '$shaderSources${program.stem}.frag',
    });
  });
}
