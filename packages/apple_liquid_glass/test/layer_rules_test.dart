import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

const _material = 'package:material_ui/material_ui.dart';
const _cupertino = 'package:cupertino_ui/cupertino_ui.dart';
const _widgets = 'package:flutter/widgets.dart';
const _rendering = 'package:flutter/rendering.dart';

/// The glass renderer's values: its shapes, fields and looks, which draw
/// nothing.
const _glassValues = 'package:liquid_glass_renderer/painting.dart';

/// The glass renderer past its values.
const _glassDrawing = [
  'package:liquid_glass_renderer/liquid_glass_renderer.dart',
  'package:liquid_glass_renderer/composer.dart',
  'package:liquid_glass_renderer/rendering.dart',
  'package:liquid_glass_renderer/widgets.dart',
  'package:liquid_glass_renderer/src/',
];
const _kinesis = 'package:kinesis/kinesis.dart';
const _kinesisWidgets = 'package:kinesis/widgets.dart';
const _kinesisPresentation = 'package:kinesis/presentation.dart';
const _kinesisTesting = 'package:kinesis/testing.dart';
const _kinesisSrc = 'package:kinesis/src/';

/// Below widgets, a library reaches kinesis no higher than its widgets: the
/// umbrella of kinesis brings its presentations too.
const _belowPresentation = [_kinesis, _kinesisPresentation];

/// foundation < motions < surfaces < liquid < raw < widgets, each importing
/// only what its row names. The measured laws stay below widgets and
/// rendering so they replay a recording without a screen; only liquid draws
/// with the glass renderer, and nothing but the umbrella imports liquid, so
/// no other library picks a renderer for the app; a core knows no surface.
/// Every library takes the renderer's values ([_glassValues]): a body's
/// shape and field are the renderer's, and foundation lays a body out as
/// live glass does.
const _rules = LayerRules(
  package: 'apple_liquid_glass',
  libraries: {
    'foundation': {},
    'motions': {'foundation'},
    'surfaces': {'foundation', 'motions'},
    'liquid': {'foundation', 'surfaces'},
    'raw': {'foundation', 'motions'},
    'widgets': {'foundation', 'motions', 'surfaces', 'raw'},
  },
  umbrella: 'apple_liquid_glass',
  umbrellaReexports: {_kinesis, _glassValues},
  unchecked: {'testing'},
  packages: {'flutter', 'meta', 'kinesis', 'liquid_glass_renderer'},
  forbidden: {
    everyLibrary: [_material, _cupertino, _kinesisSrc],
    'foundation': [..._belowPresentation, _kinesisTesting, ..._glassDrawing],
    'motions': [
      _widgets,
      _rendering,
      _kinesisWidgets,
      ..._belowPresentation,
      _kinesisTesting,
      ..._glassDrawing,
    ],
    'surfaces': [..._belowPresentation, _kinesisTesting, ..._glassDrawing],
    'liquid': [..._belowPresentation, _kinesisTesting],
    'raw': [..._belowPresentation, _kinesisTesting, ..._glassDrawing],
    'widgets': [_kinesisTesting, ..._glassDrawing],
  },
  bans: [
    // Input goes through kinesis's InputRegion.
    Ban('GestureDetector', r'\b(?:Raw)?GestureDetector\b'),
    Ban('Listener', r'\bListener\s*\('),
    Ban('CallbackShortcuts', r'\bCallbackShortcuts\b'),
    // A touch with no region under it comes through kinesis's InputCapture.
    Ban('pointer-route', r'\bGestureBinding\b|\bpointerRouter\b'),
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
    // Apple reads the pixel ratio of the view it draws into in one place
    // (GlassTraits.viewPixelRatio); how far a blur reaches, and when a band
    // blurs at half resolution, is the renderer's.
    Ban(
      'pixel-ratio',
      r'[dD]evicePixelRatioOf\b|'
          r'\bView\.(?:maybeOf|of)\([^)]*\)\??\.devicePixelRatio\b|'
          r'\bImpellerBlur\b',
      allowedIn: {'lib/src/foundation/traits.dart'},
    ),
    // A scroll edge band says hard or soft (FrostBandPaint.hard, .soft);
    // the renderer keeps what no dissolve is.
    Ban('frost-sentinel', r'1e5\b'),
    // Whether full glass draws is the renderer's to know: liquid builds one
    // tree in every state and reads `LiquidGlass.support` where it must.
    Ban(
      'shader-filters',
      r'\bisShaderFilterSupported\b|\bkIsWeb\b',
      bannedIn: {'lib/src/liquid/'},
    ),
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
      allowedIn: {'lib/src/motions/', 'lib/src/liquid/scope.dart'},
    ),
    // A law lives in motions, where it replays a recording without a
    // screen; a host tells it what happened and reads its values.
    Ban(
      'law-outside-motions',
      r'\bextends\s+Motion(?:Loop)?\b',
      allowedIn: {'lib/src/motions/'},
    ),
    Ban('SingleChildScrollView', r'\bSingleChildScrollView\b'),
    // A corner radius is drawn as Flutter scales it (glassCornerRadii); one
    // clamped to half the short side on its own draws a pair's corners wrong.
    Ban(
      'radius-clamp',
      r'\bmin\([^;]*?\bshortestSide\s*/\s*2\b',
      allowedIn: {'lib/src/motions/'},
    ),
    // Glass casts its shadows as the renderer does (LiquidGlassShadow.paint);
    // only a page, which is no glass, blurs a shadow of its own.
    Ban(
      'shadow-blur',
      r'\bBlurStyle\.|\bMaskFilter\.blur\(',
      allowedIn: {
        'lib/src/widgets/navigation/page_route_card.dart',
        'lib/src/widgets/navigation/page_route_zoom.dart',
      },
    ),
    // A body fills through its shape (LiquidShape.paintInterior), and its
    // corners are fitted as Flutter fits them in glassCornerRadii alone.
    Ban(
      'superellipse-draw',
      r'\b(?:drawRSuperellipse|toRSuperellipse)\b',
      allowedIn: {'lib/src/foundation/body.dart'},
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
