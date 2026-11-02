import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// What reads a backdrop or takes a copy of the screen: a layer that filters
// the backdrop, the keys and groups that share one, a seeded pass, an image
// taken of a scene. The composer's own layers, such as
// LiquidGlassBackdropFilterLayer, are how a surface reads through it.
final _read = RegExp(
  r'toImageSync\(|pushBackdropFilter\(|(?<![\w.])(?:BackdropFilterLayer|'
  r'BackdropFilter|BackdropKey|BackdropGroup|SeededBackdropPassLayer)\(',
);

// Reads outside the composer, per file. Glass reads its backdrop through
// the view's composer; these files still build their own reads and leave
// this list as they move there. A count may only fall.
const _outsideComposer = {
  'lib/src/fake_glass.dart': 1,
  'lib/src/internal/backdrop_seed.dart': 2,
  'lib/src/internal/backdrop_underlay.dart': 12,
  'lib/src/internal/warm_up.dart': 5,
  'lib/src/rendering/consolidated_fake_glass_layer.dart': 4,
  'lib/src/rendering/liquid_glass_layer.dart': 3,
};

void main() {
  test('backdrop reads outside the composer only shrink', () {
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
