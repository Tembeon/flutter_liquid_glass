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
  // The sheet reads the finger in screen coordinates while it moves under
  // it, which a region inside the moving sheet cannot.
  'a release velocity comes from InputRegion': (
    RegExp(r'\bVelocityTracker\b'),
    {'lib/src/presentations/sheet.dart'},
  ),
  'a host steps no driver; it selects from its Motion': (
    RegExp(r'(implements|extends|with)[^{]*\bMotionDriver\b|addDriver\('),
    {},
  ),
  // A motion keeps its time on its Motion's cursor and asks its parts
  // whether they rest.
  'a motion keeps no clock of its own': (RegExp(r'\bdouble _now\b'), {}),
  'rest is asked of the part (restsAt)': (RegExp(r'\.isWithin\('), {}),
  'rest tolerances are MotionRest': (RegExp(r'\bGlassRest\b'), {}),
  // A renderer reads a body's field when it draws one (GlassOutline).
  'no widget asks which renderer draws it': (
    RegExp(r'(?<!other )\bis!? (?:Flat|Liquid|Adaptive)GlassRenderer\b'),
    {},
  ),
  'a press is a GlassPress': (RegExp(r'\bFlexInteraction\('), {}),
  // Every const Object() is one object, so two such slots of a motion
  // would replace each other's reactions.
  'a reaction slot is a symbol': (
    RegExp(r'static const _\w+ = Object\(\);'),
    {},
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

  group('public libraries', () {
    final export = RegExp(
      r'''export\s+'([^']+)'\s*(show\s+([^;]*))?;''',
      multiLine: true,
    );
    final libraries = Directory(
      'lib',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));

    test('export their own files by show lists only', () {
      final offenders = <String>[];
      for (final library in libraries) {
        for (final match in export.allMatches(library.readAsStringSync())) {
          final uri = match.group(1)!;
          if (uri.startsWith('package:kinesis/')) continue;
          if (uri.startsWith('package:') || match.group(2) == null) {
            offenders.add('${library.path}: $uri');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('show no internal name', () {
      final offenders = <String>[];
      for (final library in libraries) {
        for (final match in export.allMatches(library.readAsStringSync())) {
          final names = match.group(3);
          if (names == null) continue;
          final source = File('lib/${match.group(1)}').readAsStringSync();
          for (final name in names.split(',').map((name) => name.trim())) {
            final declared = RegExp(
              r'((?:^@\w+(?:\([^)]*\))?\n)*)^[^\n/]*?'
              '(?:class|enum|typedef|mixin|extension)\\s+$name\\b',
              multiLine: true,
            ).firstMatch(source);
            if (declared?.group(1)?.contains('@internal') ?? false) {
              offenders.add('${library.path}: $name');
            }
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('the renderer seam is only in glass_renderer.dart', () {
      final main = File('lib/apple_liquid_glass.dart').readAsStringSync();
      for (final name in [
        'package:liquid_glass_renderer',
        'GlassSurfaceDetails',
        'GlassGroupDetails',
        'GlassScrollEdgeDetails',
      ]) {
        expect(main.contains(name), isFalse, reason: name);
      }
    });
  });
}
