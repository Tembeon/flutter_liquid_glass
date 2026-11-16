import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

/// painting < composer < rendering < widgets < effects. The values and the
/// plan stay pure, so a frame is planned and checked without a GPU; the
/// renderer depends on nothing but the Flutter SDK at run time, and the
/// effects are the only library that animates.
const _rules = LayerRules(
  package: 'liquid_glass_renderer',
  libraries: {
    'painting': {},
    'composer': {'painting'},
    'rendering': {'painting', 'composer'},
    'widgets': {'painting', 'composer', 'rendering'},
    'effects': {'painting', 'composer', 'rendering', 'widgets'},
  },
  umbrella: 'liquid_glass_renderer',
  umbrellaLibraries: {'painting', 'widgets'},
  otherLibrariesThroughSource: true,
  packages: {
    'flutter',
    'flutter_gpu',
    'vector_math',
    'meta',
  },
  forbidden: {
    everyLibrary: [
      'package:material_ui/material_ui.dart',
      'package:cupertino_ui/cupertino_ui.dart',
      'package:logging/',
    ],
  },
  bans: [
    Ban('ignore', r'//\s*ignore:', code: false),
    Ban('ignore_for_file', r'//\s*ignore_for_file:', code: false),
    // The end of a frame is for what a frame leaves behind: disposal, a
    // report, a flag reset. Glass that shows a value a frame late is a
    // defect, so each use says why it is not one on the line above it.
    Ban(
      'addPostFrameCallback',
      r'\baddPostFrameCallback\b',
      allowedWith: 'After the frame:',
    ),
    Ban(
      'AnimationController',
      r'\bAnimationController\b',
      allowedIn: {'lib/src/effects/'},
    ),
    Ban(
      'Ticker',
      r'\b(?:Single)?Ticker(?:Provider(?:StateMixin)?)?\b|\bcreateTicker\b',
      allowedIn: {'lib/src/effects/'},
    ),
    Ban('dynamic', r'\bdynamic\b'),
    Ban('SingleChildScrollView', r'\bSingleChildScrollView\b'),
    // Glass reads its backdrop, or takes a copy of the screen, only through
    // the frame's composer, which plans every read. The warm-up draws its
    // own detached layer tree that is never part of a frame, the shading's
    // one image is the empty pixel bound where a draw has no image of its
    // own, the consolidated fake glass layer shares one capture among its
    // own reads, and bent content draws a picture of what lies over a shape,
    // which the caller paints and which holds nothing of the screen.
    Ban(
      'backdrop-read',
      r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
          'BackdropFilter|BackdropKey|BackdropGroup|'
          r'OpacitySeedLayer|GlassCopies)\(',
      allowedIn: {
        'lib/src/composer/',
        'lib/src/rendering/backdrop_filter_layer.dart',
        'lib/src/rendering/backdrop_rig.dart',
        'lib/src/rendering/bent_content.dart',
        'lib/src/rendering/consolidated_fake_glass_layer.dart',
        'lib/src/rendering/copy_frost.dart',
        'lib/src/rendering/copy_read.dart',
        'lib/src/rendering/glass_form.dart',
        'lib/src/rendering/glass_form_open.dart',
        'lib/src/rendering/glass_composer.dart',
        'lib/src/rendering/glass_composition_probe.dart',
        'lib/src/rendering/read.dart',
        'lib/src/rendering/scene_out.dart',
        'lib/src/rendering/shading.dart',
        'lib/src/rendering/warm_up.dart',
      },
    ),
    // A copy's grid is its read's geometry's to decide and its place's to
    // lay out: readers take the boxes and texels they give, round nothing to
    // pixels of their own and carry no ratio between a copy's pixels and the
    // screen's.
    Ban(
      'copy-grid',
      r'\.cover\(|\.outTo\(|\.pixelsOn\(|'
          r'devicePixelRatio\s*/\s*share|/\s*share\b.*\bpixels\b',
      allowedIn: {
        'lib/src/composer/copy_place.dart',
        'lib/src/composer/impeller.dart',
        'lib/src/composer/read_geometry.dart',
        'lib/src/painting/view_pixels.dart',
      },
    ),
    // Rounding a length to device pixels is ViewPixels's: a rect rounded
    // twice, or by two rules, lands a pixel off the one beside it.
    Ban(
      'pixel-rounding',
      r'(?:devicePixelRatio|\bdpr\b)[^;\n]*\.(?:floor|ceil|round)(?:ToDouble)?\(|'
          r'\.(?:floor|ceil|round)(?:ToDouble)?\(\)[^;\n]*/\s*'
          r'(?:devicePixelRatio|dpr)\b',
      allowedIn: {
        'lib/src/composer/impeller.dart',
        'lib/src/painting/view_pixels.dart',
      },
    ),
    // A copy comes to hold a frost only where its layers are made: a read's
    // corner in the frame and a page in an image. Every reader takes what the
    // copy holds from there.
    Ban(
      'copy-frost',
      r'\bfrostInPlace\(',
      allowedIn: {
        'lib/src/rendering/copy_frost.dart',
        'lib/src/rendering/copy_read.dart',
        'lib/src/rendering/read.dart',
      },
    ),
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
