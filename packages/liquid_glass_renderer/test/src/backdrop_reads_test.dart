import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// What reads a backdrop or takes a copy of the screen: a layer that filters
// the backdrop, the keys and groups that share one, an opacity pass's seed, an
// image taken of a scene. Surfaces read through the
// composer's own types, such as LiquidGlassBackdropFilterLayer and
// BackdropRig.
final _read = RegExp(
  r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
  r'BackdropFilter|BackdropKey|BackdropGroup|'
  r'OpacitySeedLayer|GlassCopies)\(',
);

// The only reads outside the composer, per file. The shader warm-up draws
// its own detached layer tree, never part of a frame; the glass layer's one
// image is the empty 1x1 placeholder bound to the matte sampler. Every other
// surface reads its backdrop through the view's composer.
const _outsideComposer = {
  'lib/src/internal/warm_up.dart': 3,
  'lib/src/rendering/consolidated_fake_glass_layer.dart': 1,
  'lib/src/rendering/liquid_glass_layer.dart': 1,
};

void main() {
  test('surfaces read their backdrop only through the composer', () {
    final found = <String, int>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.startsWith('lib/src/composer/'));
    for (final file in files) {
      var count = 0;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        count += _read.allMatches(line).length;
      }
      if (count > 0) found[file.path] = count;
    }
    expect(found, _outsideComposer);
  });
}
