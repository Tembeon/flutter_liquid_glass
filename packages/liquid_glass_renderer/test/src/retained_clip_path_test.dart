import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';

class _NotchClipper extends CustomClipper<Path> {
  _NotchClipper(this.inset) : super(reclip: inset);

  final ValueNotifier<double> inset;

  @override
  Path getClip(Size size) => const StadiumBorder().getOuterPath(
    Rect.fromLTRB(inset.value, 0, size.width, size.height),
  );

  @override
  bool shouldReclip(_NotchClipper oldClipper) => oldClipper.inset != inset;
}

void main() {
  testWidgets('a held clipper keeps its path across glass repaints', (
    tester,
  ) async {
    final inset = ValueNotifier<double>(0);
    addTearDown(inset.dispose);
    final clipper = _NotchClipper(inset);
    final tint = ValueNotifier<Color>(const Color(0xC00040FF));
    addTearDown(tint.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: ValueListenableBuilder(
              valueListenable: tint,
              builder: (context, color, _) => LiquidGlassLayer(
                fake: true,
                settings: const LiquidGlassSettings(frost: 0),
                defaultAppearance: LiquidGlassAppearance(tint: color),
                child: ClipPath(
                  clipper: clipper,
                  child: const LiquidGlass(
                    shape: LiquidRoundedRectangle(borderRadius: 20),
                    child: SizedBox(width: 260, height: 180),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Object? geometry() {
      final layers = tester.layers.whereType<NativeClipLayer>().toList();
      expect(layers, hasLength(1));
      return layers.single.geometry;
    }

    final first = geometry();
    expect(first, isA<Path>());

    tint.value = const Color(0xC0FF4000);
    await tester.pump();
    expect(identical(geometry(), first), isTrue);

    inset.value = 20;
    await tester.pump();
    final reclipped = geometry();
    expect(identical(reclipped, first), isFalse);
    expect((reclipped! as Path).getBounds().left, 20);
  });
}
