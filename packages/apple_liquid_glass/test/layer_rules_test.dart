import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

const _material = 'package:flutter/material.dart';
const _cupertino = 'package:flutter/cupertino.dart';
const _widgets = 'package:flutter/widgets.dart';
const _rendering = 'package:flutter/rendering.dart';
const _glass = 'package:liquid_glass_renderer/';
const _kinesis = 'package:kinesis/kinesis.dart';
const _kinesisWidgets = 'package:kinesis/widgets.dart';
const _kinesisPresentation = 'package:kinesis/presentation.dart';
const _kinesisTesting = 'package:kinesis/testing.dart';
const _kinesisSrc = 'package:kinesis/src/';

/// Below presentations, a library reaches kinesis no higher than its
/// widgets: the umbrella of kinesis brings its presentations too.
const _belowPresentation = [_kinesis, _kinesisPresentation];

/// foundation < motions < surfaces < liquid < raw < controls <
/// presentations < navigation < app, each importing only what its row
/// names. The measured laws stay below widgets and rendering so they replay
/// a recording without a screen; only liquid knows the glass renderer, and
/// nothing but app and the umbrella imports liquid; nothing but the
/// umbrella imports app; a core knows no surface.
const _rules = LayerRules(
  package: 'apple_liquid_glass',
  libraries: {
    'foundation': {},
    'motions': {'foundation'},
    'surfaces': {'foundation', 'motions'},
    'liquid': {'foundation', 'surfaces'},
    'raw': {'foundation', 'motions'},
    'controls': {'foundation', 'motions', 'surfaces', 'raw'},
    'presentations': {'foundation', 'motions', 'surfaces', 'raw', 'controls'},
    'navigation': {
      'foundation',
      'motions',
      'surfaces',
      'raw',
      'controls',
      'presentations',
    },
    'app': {
      'foundation',
      'motions',
      'surfaces',
      'liquid',
      'raw',
      'controls',
      'presentations',
      'navigation',
    },
  },
  umbrella: 'apple_liquid_glass',
  umbrellaReexports: {_kinesis},
  unchecked: {'testing'},
  packages: {'flutter', 'meta', 'kinesis', 'liquid_glass_renderer'},
  forbidden: {
    everyLibrary: [_material, _cupertino, _kinesisSrc],
    'foundation': [..._belowPresentation, _kinesisTesting, _glass],
    'motions': [
      _widgets,
      _rendering,
      _kinesisWidgets,
      ..._belowPresentation,
      _kinesisTesting,
      _glass,
    ],
    'surfaces': [..._belowPresentation, _kinesisTesting, _glass],
    'liquid': [..._belowPresentation, _kinesisTesting],
    'raw': [..._belowPresentation, _kinesisTesting, _glass],
    'controls': [..._belowPresentation, _kinesisTesting, _glass],
    'presentations': [_kinesisTesting, _glass],
    'navigation': [_kinesisTesting, _glass],
    'app': [_kinesisTesting, _glass],
  },
  bans: [
    // Input goes through kinesis's InputRegion.
    Ban('GestureDetector', r'\b(?:Raw)?GestureDetector\b'),
    Ban('Listener', r'\bListener\s*\('),
    Ban('CallbackShortcuts', r'\bCallbackShortcuts\b'),
    Ban(
      'key-handler',
      r'\bonKey(?:Event)?\s*:|\bHardwareKeyboard\b|\bKeyboardListener\b|'
          r'\bShortcuts\s*\(',
    ),
    // Motion runs on kinesis's clock and reaches the screen without a
    // rebuild.
    Ban('AnimationController', r'\bAnimationController\b'),
    Ban('Ticker', r'\bTicker\b|\bcreateTicker\b'),
    Ban(
      'addPostFrameCallback',
      r'\baddPostFrameCallback\b',
      allowedWith: 'After the frame:',
    ),
    Ban('MotionClock.instance', r'\bMotionClock\.instance\b'),
    Ban('ValueListenableBuilder', r'\bValueListenableBuilder\b'),
    // Reduce Motion reaches a motion through Motion.traits.
    Ban('reducedMotion', r'\breducedMotion\b'),
    // A layer the frame composer does not know is drawn past it; the
    // renderer's own layers are its business.
    Ban(
      'engine-layer',
      r'\b(?:ImageFilter|BackdropFilter|ColorFilter|ShaderMask)Layer\b|'
          r'\bpush(?:ImageFilter|BackdropFilter|ColorFilter|ShaderMask)\b',
      // The selector blurs the items that dissolve as its bar collapses in
      // its own paint, with either renderer.
      allowedIn: {'lib/src/liquid/', 'lib/src/raw/selector_render.dart'},
    ),
    // A haptic plays with the input that causes it, through InputRegion.
    Ban('haptic-play', r'\.play\(\)'),
    Ban('HapticFeedback', r'\bHapticFeedback\.'),
    Ban('ignore', r'//\s*ignore:', code: false),
    Ban('ignore_for_file', r'//\s*ignore_for_file:', code: false),
    Ban('dynamic', r'\bdynamic\b'),
    // A measured spring lives with its law; the app's own choice of a
    // spring is a parameter of its scope.
    Ban(
      'spring',
      r'\bSpring(?:\.\w+|\()',
      allowedIn: {'lib/src/motions/', 'lib/src/app/'},
    ),
    Ban('SingleChildScrollView', r'\bSingleChildScrollView\b'),
  ],
);

void main() {
  final report = checkLayers(Directory.current, _rules);

  test('every lib/src folder is one library behind one library file', () {
    expect(report.structure, isEmpty);
  });

  test('imports and bans break the rules only as test/rules/debt.txt '
      'lists', () {
    final failure = holdDebt(
      File('test/rules/debt.txt'),
      report.violations,
      update: updateDebtRequested,
    );
    if (failure != null) fail(failure);
  });
}
