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

void main() {
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
