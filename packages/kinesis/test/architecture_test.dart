import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The core of kinesis stays below widgets and rendering so it can live
/// beside any widget set.
const _allowed = {
  'dart:async',
  'dart:developer',
  'dart:ffi',
  'dart:io',
  'dart:math',
  'dart:typed_data',
  'dart:ui',
  'package:flutter/foundation.dart',
  'package:flutter/physics.dart',
  'package:flutter/scheduler.dart',
  'package:meta/meta.dart',
};

// The screen bindings (lib/src/screen) and the presentations
// (lib/src/presentation) sit on rendering, widgets, gestures and services;
// the pure input model (lib/src/input) needs pointer and geometry types
// only. The core below them imports neither.
const _screen = {
  'package:flutter/gestures.dart',
  'package:flutter/painting.dart',
  'package:flutter/rendering.dart',
  'package:flutter/services.dart',
  'package:flutter/widgets.dart',
};

const _input = {
  'package:flutter/gestures.dart',
  'package:flutter/painting.dart',
};

void main() {
  test('lib imports only the Dart core, foundation, physics, scheduler and '
      'meta; the screen bindings add rendering and widgets', () {
    final directive = RegExp(r'''^(?:import|export)\s+'([^']+)'.*$''');
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      for (final line in file.readAsLinesSync()) {
        final uri = directive.firstMatch(line.trim())?.group(1);
        if (uri == null) continue;
        final screen =
            file.path.startsWith('lib/src/screen/') ||
            file.path.startsWith('lib/src/presentation/');
        final input = file.path.startsWith('lib/src/input/');
        if (!screen && !input && uri.startsWith('package:kinesis/src/input/')) {
          offenders.add('${file.path}: $uri');
        }
        if (!screen &&
            (uri.startsWith('package:kinesis/src/screen/') ||
                uri.startsWith('package:kinesis/src/presentation/'))) {
          offenders.add('${file.path}: $uri');
        }
        final own = uri.startsWith('package:kinesis/') || !uri.contains(':');
        final allowed =
            _allowed.contains(uri) ||
            (screen && _screen.contains(uri)) ||
            (input && _input.contains(uri));
        if (!own && !allowed) offenders.add('${file.path}: $uri');
      }
    }
    expect(offenders, isEmpty);
  });
}
