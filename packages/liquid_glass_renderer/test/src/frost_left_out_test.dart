import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_levels.dart';

void main() {
  test('glass left a frost blurs by the levels its copy lays out', () {
    const devicePixelRatio = 2.0;
    const deep = 9.0;
    const rim = 4.0;
    final layout = ReadLayout.resolve(
      devicePixelRatio: devicePixelRatio,
      askedShare: 2,
      atScreen: false,
      reads: const Rect.fromLTWH(40, 60, 120, 80),
      screen: const Rect.fromLTWH(0, 0, 300, 400),
      clip: null,
      holdsGlass: false,
      edgeFrost: 0,
      frostLeftOut: 3,
      filter: null,
      imageBlur: 0,
      levels: const CopyLevels(least: rim, most: deep),
    );
    final lanes = copyLanes(
      strip: CornerPlace.inFrame(layout).levels,
      blur: const GlassBlur(
        sigmas: [deep * devicePixelRatio, rim * devicePixelRatio, 2, 1],
        depths: [8, 2, 0],
        fillMix: [0, 0, 0],
      ),
      frost: layout.frostLeftOut * devicePixelRatio,
    );
    final at = laneOffset(CopyLane.values, CopyLane.blurSigmas);
    final levels = layout.levels!;
    expect(lanes[at] / devicePixelRatio, closeTo(levels.most, 1e-9));
    expect(lanes[at + 1] / devicePixelRatio, closeTo(levels.least, 1e-9));
    expect(levels.least, greaterThan(rim));
  });
}
