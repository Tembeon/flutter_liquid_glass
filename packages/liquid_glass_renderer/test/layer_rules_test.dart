import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:layer_rules/layer_rules.dart';

/// painting < composer < rendering < widgets. The values and the plan stay
/// pure, so a frame is planned and checked without a GPU; the renderer
/// depends on nothing but the Flutter SDK at run time, and animates nothing:
/// touch laws, springs and gestures belong to the widget libraries built on
/// it, which drive glass through its live frames.
const _rules = LayerRules(
  package: 'liquid_glass_renderer',
  libraries: {
    'painting': {},
    'composer': {'painting'},
    'rendering': {'painting', 'composer'},
    'widgets': {'painting', 'composer', 'rendering'},
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
    Ban('AnimationController', r'\bAnimationController\b'),
    Ban(
      'Ticker',
      r'\b(?:Single)?Ticker(?:Provider(?:StateMixin)?)?\b|\bcreateTicker\b',
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
    // Whether two rects reach each other is rects.dart's: an empty rect,
    // clipped away or drawing nothing, meets nothing wherever it lies.
    Ban(
      'overlaps',
      r'\.overlaps\(',
      allowedIn: {'lib/src/composer/rects.dart'},
    ),
    // Which member of a read is its band's painter, and which are glass, is
    // the read's to say (GlassRead.bandPainter, glassMembers).
    Ban(
      'read-member-index',
      r'\bmembers\[\d',
      allowedIn: {'lib/src/composer/plan_result.dart'},
    ),
    // Whether glass shows is one answer (DrawnAppearance.shows), and whether
    // a layer draws a shape another (FrameShapes.drawn).
    Ban(
      'visibility-threshold',
      r'\.visibility\s*(?:>|<=)\s*0\b',
      bannedIn: {'lib/src/'},
    ),
    // Where glass draws, beside its siblings or in a layer of its own under
    // another glass, is the nearest GlassHost's answer, not an ancestor walk.
    Ban(
      'ancestor-walk',
      r'\bvisitAncestorElements\b',
      bannedIn: {'lib/src/widgets/'},
    ),
    // A fragment shader's uniforms are found and written in one file, by name
    // or by a lane table.
    Ban(
      'uniform-write',
      r'\.(?:setFloat|getUniformFloat)\(',
      allowedIn: {'lib/src/rendering/shader_uniforms.dart'},
    ),
    // Geometry hears of settings only through what they ask of it, the
    // layer's MatteNeed: a frost or a tint redraws no matte, and a rising
    // bevel only each step of its reach.
    Ban(
      'geometry-settings',
      r'\bLiquidGlassSettings\b',
      bannedIn: {
        'lib/src/rendering/flutter_gpu_geometry_renderer.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native_pages.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native_quads.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_native_resources.dart',
        'lib/src/rendering/flutter_gpu_geometry_renderer_web.dart',
        'lib/src/rendering/geometry_render_link.dart',
        'lib/src/rendering/geometry_tiling.dart',
        'lib/src/rendering/geometry_tiling_atlas.dart',
        'lib/src/rendering/geometry_tiling_bounds.dart',
        'lib/src/rendering/geometry_tiling_groups.dart',
        'lib/src/rendering/geometry_tiling_values.dart',
        'lib/src/rendering/group_matte.dart',
        'lib/src/rendering/liquid_glass.dart',
        'lib/src/rendering/liquid_glass_blend_group.dart',
        'lib/src/rendering/render_liquid_glass_geometry.dart',
        'lib/src/rendering/shape_set.dart',
        'lib/src/rendering/tiling_drift.dart',
      },
    ),
    // A number Dart and the shaders share is written once, in the table the
    // shaders' constants are generated from.
    Ban(
      'shader-constant',
      r'(?<![\d.])(?:0\.2126|0\.7152|0\.0722|0\.258819|0\.965926)(?!\d)',
      allowedIn: {'lib/src/painting/shader_constants.dart'},
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
    // Glass casts its shadows by one law (LiquidGlassShadow.paint): one
    // fade, one reach, one cut. A blur anywhere else is a second law.
    Ban(
      'shadow-blur',
      r'\bBlurStyle\.|\bMaskFilter\.blur\(',
      allowedIn: {'lib/src/painting/liquid_glass_shadow.dart'},
    ),
    // What a shape is to the shaders is answered by its drawn values, and a
    // fill by LiquidShape.paintInterior; only the clip picks Flutter's clip
    // widget for each shape.
    Ban(
      'shape-switch',
      r'^\s*(?:case\s+)?(?:final\s+)?Liquid(?:RoundedSuperellipse|RoundedRectangle|Oval)\b[^;\n]*=>'
      r'|\b(?:is|case)\s+(?:final\s+)?Liquid(?:RoundedSuperellipse|RoundedRectangle|Oval)\b',
      allowedIn: {
        'lib/src/painting/liquid_shape.dart',
        'lib/src/rendering/drawn_values.dart',
        'lib/src/widgets/optimized_clip.dart',
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
