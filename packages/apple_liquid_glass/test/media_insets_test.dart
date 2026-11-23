import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an overlay keeps the larger of the safe area and the keyboard clear',
    () {
      const safe = MediaQueryData(padding: EdgeInsets.fromLTRB(1, 2, 3, 34));
      expect(safe.bottomAboveKeyboard, 34);
      expect(safe.paddingAboveKeyboard, const EdgeInsets.fromLTRB(1, 2, 3, 34));

      final typing = safe.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 300),
      );
      expect(typing.bottomAboveKeyboard, 300);
      expect(
        typing.paddingAboveKeyboard,
        const EdgeInsets.fromLTRB(1, 2, 3, 300),
      );
    },
  );

  testWidgets('an overlay covers the window band at the top of the padding', (
    tester,
  ) async {
    final seen = <EdgeInsets>[];
    for (final band in [0.0, 28.0, 80.0]) {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.fromLTRB(1, 52, 3, 34),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: GlassWindowBand(
            height: band,
            child: Builder(
              builder: (context) {
                seen.add(GlassWindowBand.overlayPaddingOf(context));
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }
    expect(seen, const [
      EdgeInsets.fromLTRB(1, 52, 3, 300),
      EdgeInsets.fromLTRB(1, 24, 3, 300),
      EdgeInsets.fromLTRB(1, 0, 3, 300),
    ]);
  });
}
