import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// A scene a read of what lies under glass adds itself to.
///
/// What only moves the coordinates waits for what needs them: a picture takes a
/// translation as its offset, and a layer pushed costs both threads.
@internal
final class SceneOut {
  /// Adds to [builder], the coordinates there taken by [matrix] if any.
  SceneOut(this.builder, this.matrix);

  /// The scene.
  final ui.SceneBuilder builder;

  /// The transform no layer holds yet, then the translation [at] after it.
  Matrix4? matrix;

  /// The translation no layer holds yet.
  Offset at = Offset.zero;

  /// Layers pushed and not popped.
  int pushes = 0;

  final _marks = <(Matrix4?, Offset, int)>[];

  /// Takes the coordinates by [by].
  void transform(Matrix4 by) {
    if (MatrixUtils.getAsTranslation(by) case final shift?) {
      at += shift;
      return;
    }
    final next = (matrix ?? Matrix4.identity()).clone()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..multiply(by);
    matrix = next;
    at = Offset.zero;
  }

  /// Pushes the waiting transform with its translation.
  void settleMatrix() {
    final held = matrix;
    if (held == null) return;
    if (at != Offset.zero) {
      final next = held.clone()..translateByDouble(at.dx, at.dy, 0, 1);
      builder.pushTransform(next.storage);
    } else {
      builder.pushTransform(held.storage);
    }
    matrix = null;
    at = Offset.zero;
    pushes++;
  }

  /// Leaves the coordinates of what comes next to the layers pushed.
  void settle() {
    settleMatrix();
    if (at == Offset.zero) return;
    builder.pushOffset(at.dx, at.dy);
    at = Offset.zero;
    pushes++;
  }

  /// Adds [picture] at the coordinates' origin.
  void picture(ui.Picture picture) {
    settleMatrix();
    builder.addPicture(at, picture);
  }

  /// Adds [texture] where it lies in the coordinates.
  void texture(TextureLayer texture) {
    settleMatrix();
    final rect = texture.rect;
    builder.addTexture(
      texture.textureId,
      offset: at + rect.topLeft,
      width: rect.width,
      height: rect.height,
      freeze: texture.freeze,
      filterQuality: texture.filterQuality,
    );
  }

  /// Remembers where the coordinates stand, for [leave].
  void mark() => _marks.add((matrix, at, pushes));

  /// Takes the coordinates back to the last [mark].
  void leave() {
    final (heldMatrix, heldAt, pushed) = _marks.removeLast();
    while (pushes > pushed) {
      builder.pop();
      pushes--;
    }
    matrix = heldMatrix;
    at = heldAt;
  }

  /// Pops everything pushed.
  void finish() {
    _marks.clear();
    while (pushes > 0) {
      builder.pop();
      pushes--;
    }
  }
}
