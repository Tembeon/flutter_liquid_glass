import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

/// The shaders of one program a painter draws one recording with, one per
/// draw, made once the program has loaded and kept across recordings.
///
/// CanvasKit on the web keeps a pointer to a shader's uniforms, not a copy,
/// so draws of one picture that share a shader all take the uniforms it was
/// given last.
final class RecordingShaders {
  /// Shaders of [program]; `onLoaded` runs when the program lands after
  /// [ready] said it had not.
  RecordingShaders(ShaderProgram program, {this._onLoaded})
    : _program = program.key;

  final String _program;
  final VoidCallback? _onLoaded;
  final List<ui.FragmentShader> _shaders = [];
  int _drawn = 0;
  bool _waiting = false;
  bool _disposed = false;

  /// Whether the program has loaded; starts loading it if not.
  bool ready() {
    if (GlassShaderPrograms.cached(_program) != null) return true;
    if (!_waiting) {
      _waiting = true;
      GlassShaderPrograms.precacheShader(_program).then((_) {
        _waiting = false;
        if (!_disposed && GlassShaderPrograms.cached(_program) != null) {
          _onLoaded?.call();
        }
      });
    }
    return false;
  }

  /// Starts a recording.
  void begin() => _drawn = 0;

  /// The shader of the recording's next draw.
  ui.FragmentShader next() {
    final drawn = _drawn++;
    if (drawn < _shaders.length) return _shaders[drawn];
    final shader = GlassShaderPrograms.cached(_program)!.fragmentShader();
    _shaders.add(shader);
    return shader;
  }

  /// The shader of a recording's first draw, once one was drawn.
  ui.FragmentShader? get debugFirst => _shaders.firstOrNull;

  /// Releases the shaders it made.
  void dispose() {
    _disposed = true;
    for (final shader in _shaders) {
      shader.dispose();
    }
    _shaders.clear();
  }
}
