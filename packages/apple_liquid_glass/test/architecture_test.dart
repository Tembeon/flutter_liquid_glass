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
// the backdrop for every surface, through the view's composer
// (LiquidGlassBackdropFilterLayer for a filter of the widget layer's own).
final _read = RegExp(
  r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
  r'BackdropFilter|BackdropKey|BackdropGroup|SeededBackdropPassLayer)\(',
);

// Code the stack replaced, with the files that still hold it. A listed file
// that stops offending fails too, so the list only shrinks.
final _bans = <String, (RegExp, Set<String>)>{
  'haptics through MotionHaptic.play': (RegExp(r'\bHapticFeedback\.'), {}),
  'a host steps no driver; it selects from its Motion': (
    RegExp(r'(implements|extends|with)[^{]*\bMotionDriver\b|addDriver\('),
    {
      'lib/src/chrome/bar.dart',
      'lib/src/chrome/navigation_bar.dart',
      'lib/src/chrome/page_route.dart',
      'lib/src/chrome/toolbar.dart',
      'lib/src/controls/date_picker.dart',
      'lib/src/controls/tab_bar.dart',
      'lib/src/menu/anchor.dart',
    },
  ),
  // A4 (search) and A9 (menu) move these onto GlassPress.
  'a press is a GlassPress': (
    RegExp(r'\bFlexInteraction\('),
    {
      'lib/src/menu/motion.dart',
      'lib/src/motion/flex_interaction.dart',
      'lib/src/motion/search_motion.dart',
    },
  ),
};

void main() {
  for (final MapEntry(key: rule, value: (pattern, allowed)) in _bans.entries) {
    test('lib: $rule', () {
      final found = <String>{};
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        final code = file.readAsLinesSync().where(
          (line) => !line.trimLeft().startsWith('//'),
        );
        if (code.any(pattern.hasMatch)) found.add(file.path);
      }
      expect(found.difference(allowed), isEmpty, reason: 'new offenders');
      expect(allowed.difference(found), isEmpty, reason: 'drop from the list');
    });
  }

  test('no backdrop read outside the renderer', () {
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
    expect(found, isEmpty);
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
