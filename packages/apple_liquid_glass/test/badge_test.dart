import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
  child: Directionality(
    textDirection: direction,
    child: GlassTheme(
      data: GlassThemeData(brightness: brightness),
      child: Center(child: child),
    ),
  ),
);

// Arabic for new.
const _arabic = '\u062C\u062F\u064A\u062F';

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

  testWidgets('a count reads in the locale: grouped in English, in the '
      "app's own digits through its localizations", (tester) async {
    await tester.pumpWidget(_app(const GlassBadge.count(1234)));
    expect(find.text('1,234'), findsOneWidget);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('ar'),
        delegates: const [
          DefaultWidgetsLocalizations.delegate,
          _ArabicDigits.delegate,
        ],
        child: _app(const GlassBadge.count(12)),
      ),
    );
    expect(find.text('١٢'), findsOneWidget);
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

  testWidgets('the theme colors badges and a badge style overrides it', (
    tester,
  ) async {
    Color fill() =>
        (tester.widget<Container>(find.byType(Container)).decoration!
                as ShapeDecoration)
            .color!;
    Widget themed(Widget badge) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GlassTheme(
          data: const GlassThemeData(
            brightness: Brightness.light,
            styles: [GlassBadgeStyle(backgroundColor: Color(0xFF00AA00))],
          ),
          child: Center(child: badge),
        ),
      ),
    );
    await tester.pumpWidget(themed(const GlassBadge.count(3)));
    expect(fill(), const Color(0xFF00AA00));
    final small = tester.getSize(find.byType(GlassBadge)).height;

    await tester.pumpWidget(
      themed(
        const GlassBadge.count(
          3,
          style: GlassBadgeStyle(
            backgroundColor: Color(0xFF0000AA),
            textStyle: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
    expect(fill(), const Color(0xFF0000AA));
    expect(tester.getSize(find.byType(GlassBadge)).height, greaterThan(small));
  });

  testWidgets('right to left, a text badge runs in that direction and fits '
      'its text', (tester) async {
    await tester.pumpWidget(
      _app(const GlassBadge.text(_arabic), direction: TextDirection.rtl),
    );
    final size = tester.getSize(find.byType(GlassBadge));
    final text = tester.getSize(find.text(_arabic));
    expect(size.width, math.max(size.height, text.width + 8));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(_arabic));
    expect(paragraph.textDirection, TextDirection.rtl);
    expect(paragraph.didExceedMaxLines, isFalse);
  });
}

class _ArabicDigits extends DefaultGlassLocalizations {
  const _ArabicDigits();

  static const delegate = _ArabicDigitsDelegate();

  @override
  String formatDecimal(int number) => number
      .toString()
      .split('')
      .map((digit) => String.fromCharCode(0x0660 + int.parse(digit)))
      .join();
}

class _ArabicDigitsDelegate extends LocalizationsDelegate<GlassLocalizations> {
  const _ArabicDigitsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GlassLocalizations> load(Locale locale) =>
      SynchronousFuture(const _ArabicDigits());

  @override
  bool shouldReload(_ArabicDigitsDelegate old) => false;
}
