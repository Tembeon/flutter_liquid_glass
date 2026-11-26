import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';

// A plan is kept while its sites ask as they did, so an ask that differs in
// anything the plan reads must not equal the last.
SiteAsk _ask({
  Rect drawn = const Rect.fromLTWH(10, 20, 100, 40),
  Rect reads = const Rect.fromLTWH(0, 10, 120, 60),
  Object? key = 'glass',
  CopyNeed need = const CopyNeed(
    share: 2,
    levels: CopyLevels(least: 2, most: 6),
  ),
  bool drawsBand = true,
  Object? tint = const Color(0x40FF0000),
  ShapeCensus census = const ShapeCensus(shapes: 2),
  ImageReadFilter? imageRead = const BlurredImage(2, 2),
  bool anyGrid = true,
  NoJoin? noJoin = NoJoin.glow,
  bool groupsBackdrop = true,
  Object? paints = 'paints',
  Rect? clip = const Rect.fromLTWH(0, 0, 200, 200),
  bool backdropOnly = false,
}) => SiteAsk(
  drawn: drawn,
  reads: reads,
  look: FilterLook(
    key: key,
    need: need,
    drawsBand: drawsBand,
    tint: tint,
    census: census,
    imageRead: imageRead,
    anyGrid: anyGrid,
  ),
  noJoin: noJoin,
  groupsBackdrop: groupsBackdrop,
  paints: paints,
  clip: clip,
  backdropOnly: backdropOnly,
);

void main() {
  test('an ask that differs in any field is another ask', () {
    expect(_ask(), _ask());
    expect(_ask().hashCode, _ask().hashCode);
    final others = {
      'drawn': _ask(drawn: const Rect.fromLTWH(11, 20, 100, 40)),
      'reads': _ask(reads: const Rect.fromLTWH(0, 10, 121, 60)),
      'key': _ask(key: 'other'),
      'need': _ask(need: const CopyNeed(share: 4)),
      'drawsBand': _ask(drawsBand: false),
      'tint': _ask(tint: const Color(0x4000FF00)),
      'census': _ask(census: const ShapeCensus(shapes: 3)),
      'imageRead': _ask(imageRead: const BlurredImage(3, 3)),
      'anyGrid': _ask(anyGrid: false),
      'noJoin': _ask(noJoin: NoJoin.field),
      'groupsBackdrop': _ask(groupsBackdrop: false),
      'paints': _ask(paints: 'other'),
      'clip': _ask(clip: const Rect.fromLTWH(0, 0, 201, 200)),
      'backdropOnly': _ask(backdropOnly: true),
    };
    for (final MapEntry(key: field, value: other) in others.entries) {
      expect(other, isNot(_ask()), reason: field);
    }
  });
}
