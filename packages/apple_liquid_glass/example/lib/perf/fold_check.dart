// Checks on a device that glass drawn into another glass's copy matches
// reading the backdrop: the copy of the upper of two glass, drawn in the
// frame the lower one's copy is drawn too, against the lower glass read live.
// Prints FOLD_CHECK with the largest channel difference.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

void main() => runApp(const _Check());

class _Check extends StatefulWidget {
  const _Check();

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> {
  final _key = GlobalKey();
  double _shift = 0;
  bool _second = false;
  double _frost = 0;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _frame() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _set(void Function() change) async {
    setState(change);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final (frost, seeds) in [(0.0, true), (6.0, true), (6.0, false)]) {
      SeededBackdropPassLayer.debugModeOverride = seeds
          ? null
          : BackdropSeed.none;
      final dpr = View.of(_key.currentContext!).devicePixelRatio;
      BackdropUnderlay.debugEnabledOverride = false;
      await _set(() {
        _frost = frost;
        _second = false;
        _shift = 0;
        _epoch++;
      });
      await _frame();
      final boundary =
          _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final shot = await boundary.toImage(pixelRatio: dpr);
      final reading = (await shot.toByteData())!.buffer.asUint8List();
      final width = shot.width;
      shot.dispose();

      BackdropUnderlay.debugEnabledOverride = true;
      await _set(() {
        _second = true;
        _shift = 0.3;
        _epoch++;
      });
      await _frame();
      final folded = BackdropUnderlay.debugFolds;
      await _set(() => _shift = 0);
      final folds = BackdropUnderlay.debugFolds - folded;
      final upper = [
        for (final g in _glass(_root)) g.debugUnderlay,
      ].reduce((a, b) => a.debugPlace.$1.top > b.debugPlace.$1.top ? a : b);
      final (rect, offset) = upper.debugPlace;
      final image = upper.debugImage;
      if (image == null) {
        final all = [
          for (final g in _glass(_root))
            '${g.debugDrewOverUnderlay} ${g.debugUnderlay.debugMiss}',
        ];
        debugPrint(
          'FOLD_CHECK frost=$frost folds=$folds no copy: $all '
          '${BackdropUnderlay.debugMisses}',
        );
        continue;
      }
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final scale = dpr;
      var largest = 0;
      var over4 = 0;
      final w = (rect.width * scale).round();
      final h = (rect.height * scale).round();
      // Inside the copy, away from its edge, where the copy's blur and the
      // lower glass's read past the copy reach.
      final inset = (frost * 3 * scale).ceil() + 2;
      for (var y = inset; y < h - inset; y++) {
        for (var x = inset; x < w - inset; x++) {
          final copied =
              ((offset.dy.round() + y) * image.width + offset.dx.round() + x) *
              4;
          final read =
              (((rect.top * scale).round() + y) * width +
                  (rect.left * scale).round() +
                  x) *
              4;
          for (var c = 0; c < 4; c++) {
            final d = (bytes[copied + c] - reading[read + c]).abs();
            if (d > largest) largest = d;
            if (d > 4) over4++;
          }
        }
      }
      debugPrint(
        'FOLD_CHECK frost=$frost seeds=$seeds folds=$folds max=$largest '
        'over4=$over4 rect=${rect.left},${rect.top},${rect.right},'
        '${rect.bottom} copy=${image.width}x${image.height} dpr=$dpr',
      );
    }
    debugPrint('FOLD_CHECK done');
  }

  RenderObject get _root => _key.currentContext!.findRenderObject()!;

  Iterable<RenderLiquidGlassLayer> _glass(RenderObject root) sync* {
    if (root is RenderLiquidGlassLayer) yield root;
    final children = <RenderObject>[];
    root.visitChildren(children.add);
    for (final child in children) {
      yield* _glass(child);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _key,
      child: Stack(
        key: ValueKey(_epoch),
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
                    begin: Alignment(-1 + _shift, -1),
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          // The upper glass is clear, so its copy is not blurred.
          for (final (rect, frost) in [
            (const Rect.fromLTWH(30, 200, 200, 90), _frost),
            if (_second) (const Rect.fromLTWH(30, 260, 200, 60), 0.0),
          ])
            Positioned.fill(
              child: RepaintBoundary(
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                    frost: frost,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: rect,
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(borderRadius: 28),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
