import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  testWidgets('glass in a blend group under an Opacity is warned about', (
    tester,
  ) async {
    final printed = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = print);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: LiquidGlassLayer(
            child: LiquidGlassBlendGroup(
              child: Opacity(
                opacity: 0.5,
                child: LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(printed, contains(contains('only fades the')));
  });
}
