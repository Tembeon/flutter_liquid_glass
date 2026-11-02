import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _banned = [
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
  'package:material_ui/',
  'package:cupertino_ui/',
  'package:morph/',
  'package:motor/',
];

// What reads a backdrop or takes a copy of the screen. The renderer reads
// the backdrop for every surface; these files still build a read of their
// own, and a count may only fall.
final _read = RegExp(
  r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
  'LiquidGlassBackdropFilterLayer|BackdropFilter|BackdropKey|BackdropGroup|'
  r'SeededBackdropPassLayer)\(',
);

const _ownReads = {'lib/src/renderer/scroll_edge.dart': 1};

void main() {
  test('backdrop reads outside the renderer only shrink', () {
    final found = <String, int>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      var count = 0;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        count += _read.allMatches(line).length;
      }
      if (count > 0) found[file.path] = count;
    }
    expect(found, _ownReads);
  });

  test('lib imports no Material, Cupertino, Morph or motor', () {
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
        if (_banned.any(uri.startsWith)) offenders.add('${file.path}: $uri');
      }
    }
    expect(offenders, isEmpty);
  });
}
