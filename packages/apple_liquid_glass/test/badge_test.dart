import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassTheme(
          data: GlassThemeData(brightness: brightness),
          child: Center(child: child),
        ),
      ),
    );

void main() {
  testWidgets('a count is a red capsule with white text that ignores the '
      'text size, at least as wide as it is tall', (tester) async {
    await tester.pumpWidget(_app(const GlassBadge.count(6)));
    final size = tester.getSize(find.byType(GlassBadge));
    final text = tester.getSize(find.text('6'));
    expect(text.height, lessThan(24));
    expect(size.height, text.height + 4);
    expect(size.width, math.max(size.height, text.width + 8));
    expect(
      find.byType(GlassBadge),
      paints..rrect(color: const Color(0xFFFF383C)),
    );
    expect(
      tester.widget<Text>(find.text('6')).style!.color,
      const Color(0xFFFFFFFF),
    );
    expect(find.bySemanticsLabel('6'), findsOneWidget);
  });

  testWidgets('a long text grows up to 64 points; zero and an empty text '
      'show nothing; the dot is an 18 point circle', (tester) async {
    await tester.pumpWidget(
      _app(const GlassBadge.text('New messages waiting for you')),
    );
    expect(tester.getSize(find.byType(GlassBadge)).width, 64);

    await tester.pumpWidget(_app(const GlassBadge.count(0)));
    expect(tester.getSize(find.byType(GlassBadge)), Size.zero);
    await tester.pumpWidget(_app(const GlassBadge.text('')));
    expect(tester.getSize(find.byType(GlassBadge)), Size.zero);

    await tester.pumpWidget(
      _app(const GlassBadge.indicator(), brightness: Brightness.dark),
    );
    expect(tester.getSize(find.byType(GlassBadge)), const Size.square(18));
    expect(
      find.byType(GlassBadge),
      paints..rrect(color: const Color(0xFFFF4245)),
    );
  });
}
