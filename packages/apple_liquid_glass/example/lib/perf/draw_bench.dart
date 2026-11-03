// Microbench: the UI-thread cost of putting leaf pictures into a copy, a
// recorder's drawPicture against a scene builder's addPicture.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  Timer(const Duration(seconds: 3), _run);
}

ui.Picture _leaf(int ops) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < ops; i++) {
    final x = (i % 20) * 50.0;
    final y = (i ~/ 20) * 50.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 40, 40),
        const Radius.circular(8),
      ),
      Paint()..color = Color(0xFF000000 + i * 7919),
    );
  }
  return recorder.endRecording();
}

double _time(int n, void Function() body) {
  for (var i = 0; i < 50; i++) {
    body();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    body();
  }
  return watch.elapsedMicroseconds / n;
}

void _run() {
  for (final ops in [2, 40, 400]) {
    final leaves = [for (var i = 0; i < 3; i++) _leaf(ops)];
    const tile = Rect.fromLTWH(100, 100, 160, 120);
    final recorder = _time(2000, () {
      final r = ui.PictureRecorder();
      final c = Canvas(r);
      c.clipRect(const Rect.fromLTWH(0, 0, 160, 120), doAntiAlias: false);
      c.translate(-100, -100);
      for (final leaf in leaves) {
        c.save();
        c.clipRect(const Rect.fromLTWH(0, 0, 1000, 1000), doAntiAlias: false);
        c.translate(0, 10);
        c.drawPicture(leaf);
        c.restore();
      }
      r.endRecording().dispose();
    });
    final empty = _time(2000, () {
      final r = ui.PictureRecorder();
      final c = Canvas(r);
      c.clipRect(const Rect.fromLTWH(0, 0, 160, 120), doAntiAlias: false);
      c.translate(-100, -100);
      for (final _ in leaves) {
        c.save();
        c.clipRect(const Rect.fromLTWH(0, 0, 1000, 1000), doAntiAlias: false);
        c.translate(0, 10);
        c.restore();
      }
      r.endRecording().dispose();
    });
    final scene = _time(2000, () {
      final b = ui.SceneBuilder();
      b.pushClipRect(tile);
      for (final leaf in leaves) {
        b.pushClipRect(const Rect.fromLTWH(0, 0, 1000, 1000));
        b.pushOffset(0, 10);
        b.addPicture(Offset.zero, leaf);
        b.pop();
        b.pop();
      }
      b.pop();
      b.build().dispose();
    });
    final sceneLean = _time(2000, () {
      final b = ui.SceneBuilder();
      b.pushClipRect(tile);
      for (final leaf in leaves) {
        b.addPicture(const Offset(0, 10), leaf);
      }
      b.pop();
      b.build().dispose();
    });
    debugPrint(
      'DRAWBENCH ops=$ops tile(3 leaves): '
      'recorder ${recorder.toStringAsFixed(1)} us, '
      'recorder without drawPicture ${empty.toStringAsFixed(1)} us, '
      'scene ${scene.toStringAsFixed(1)} us, '
      'scene lean ${sceneLean.toStringAsFixed(1)} us',
    );
  }
  debugPrint('DRAWBENCH done');
}
