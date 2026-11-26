import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';

void main() {
  test('a program asked for again while it loads loads once and '
      'completes', () async {
    final reported = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = onError);

    const key = 'shaders/not_a_program.frag';
    final first = GlassShaderPrograms.precacheShader(key);
    final second = GlassShaderPrograms.precacheShader(key);
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]).timeout(const Duration(seconds: 5));
    expect(GlassShaderPrograms.cached(key), isNull);
    expect(reported, hasLength(1));
  });
}
