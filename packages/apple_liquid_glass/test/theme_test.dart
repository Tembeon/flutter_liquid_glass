import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child, {MediaQueryData media = const MediaQueryData()}) =>
    MediaQuery(
      data: media,
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  setUp(MotionClock.debugReset);

  group('colors', () {
    test('a dynamic color resolves to the value of its traits', () {
      const blue = GlassColors.systemBlue;
      expect(
        blue.resolvedWith(const GlassTraits()),
        isSameColorAs(const Color(0xFF0088FF)),
      );
      expect(
        blue.resolvedWith(const GlassTraits(brightness: .dark)),
        isSameColorAs(const Color(0xFF0091FF)),
      );
      expect(
        blue.resolvedWith(
          const GlassTraits(brightness: .dark, highContrast: true),
        ),
        isSameColorAs(const Color(0xFF5CB8FF)),
      );
      expect(
        GlassColors.systemBackground.resolvedWith(
          const GlassTraits(brightness: .dark, interfaceLevel: .elevated),
        ),
        isSameColorAs(const Color(0xFF1C1C1E)),
      );
    });

    test('a null end jumps at the middle; so does a scheme role on one '
        'side', () {
      const blue = GlassColors.systemBlue;
      expect(GlassDynamicColor.lerp(null, blue, 0.25), isNull);
      expect(GlassDynamicColor.lerp(null, blue, 0.75), blue);
      const none = GlassColorScheme();
      const some = GlassColorScheme(surfaces: {GlassRole.bar: blue});
      expect(GlassColorScheme.lerp(none, some, 0.25)!.surfaces, isEmpty);
      expect(GlassColorScheme.lerp(none, some, 0.75)!.surfaces, {
        GlassRole.bar: blue,
      });
    });

    test('reading an unresolved color asserts', () {
      expect(() => GlassColors.label.a, throwsAssertionError);
      expect(() => GlassColors.label.toARGB32(), throwsAssertionError);
      expect(GlassColors.label.toString(), contains('unresolved'));
    });

    test('a lerp of dynamic colors stays dynamic', () {
      final mid = GlassDynamicColor.lerp(
        GlassColors.label,
        GlassColors.systemBlue,
        0.5,
      )!;
      expect(mid, isA<GlassDynamicColor>());
      expect(
        (mid as GlassDynamicColor).resolvedWith(
          const GlassTraits(brightness: .dark),
        ),
        isSameColorAs(
          Color.lerp(const Color(0xFFFFFFFF), const Color(0xFF0091FF), 0.5)!,
        ),
      );
      expect(
        GlassDynamicColor.lerp(
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
          0.5,
        ),
        isNot(isA<GlassDynamicColor>()),
      );
    });
  });

  group('traits', () {
    testWidgets('the theme sets the brightness; overrides nest', (
      tester,
    ) async {
      late GlassTraits traits;
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(
            disableAnimations: true,
            highContrast: true,
          ),
          GlassTheme(
            data: const GlassThemeData(brightness: .dark),
            child: GlassTraitsOverride(
              reduceTransparency: true,
              child: GlassTraitsOverride(
                interfaceLevel: .elevated,
                child: Builder(
                  builder: (context) {
                    traits = GlassTraits.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        traits,
        const GlassTraits(
          brightness: .dark,
          interfaceLevel: .elevated,
          highContrast: true,
          reduceMotion: true,
          reduceTransparency: true,
        ),
      );
    });
  });

  group('theme', () {
    testWidgets('a nested theme merges into the enclosing one', (
      tester,
    ) async {
      late GlassThemeData data;
      await tester.pumpWidget(
        GlassTheme(
          data: GlassThemeData(
            renderer: const GlassRenderer.flat(),
            fontFamily: 'Outer',
            buttonStyle: GlassButton.styleFrom(
              foregroundColor: const Color(0xFF00FF00),
            ),
          ),
          child: GlassTheme(
            data: GlassThemeData(
              fontFamily: 'Inner',
              colorScheme: const GlassColorScheme(label: Color(0xFF111111)),
              buttonStyle: GlassButton.styleFrom(
                disabledForegroundColor: const Color(0xFFFF0000),
              ),
            ),
            child: Builder(
              builder: (context) {
                data = GlassTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(data.renderer, const GlassRenderer.flat());
      expect(data.fontFamily, 'Inner');
      expect(data.colorScheme!.label, const Color(0xFF111111));
      final foreground = data.buttonStyle!.foregroundColor!;
      expect(foreground.resolve({}), const Color(0xFF00FF00));
      expect(
        foreground.resolve({WidgetState.disabled}),
        const Color(0xFFFF0000),
      );
    });

    testWidgets('a part of the theme notifies only its readers', (
      tester,
    ) async {
      var brightnessReads = 0;
      final reader = Builder(
        builder: (context) {
          GlassTheme.brightnessOf(context);
          brightnessReads++;
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        GlassTheme(data: const GlassThemeData(), child: reader),
      );
      await tester.pumpWidget(
        GlassTheme(
          data: const GlassThemeData(primaryColor: Color(0xFF123456)),
          child: reader,
        ),
      );
      expect(brightnessReads, 1);
      await tester.pumpWidget(
        GlassTheme(
          data: const GlassThemeData(brightness: .dark),
          child: reader,
        ),
      );
      expect(brightnessReads, 2);
    });

    testWidgets('an animated theme moves colors on its spring, switches '
        'the renderer at once and rests on its data', (tester) async {
      final seen = <GlassThemeData>[];
      final reader = Builder(
        builder: (context) {
          seen.add(GlassTheme.of(context));
          return const SizedBox();
        },
      );
      final from = GlassThemeData(
        primaryColor: const Color(0xFF000000),
        renderer: const GlassRenderer.liquid(),
        buttonStyle: GlassButton.styleFrom(padding: const EdgeInsets.all(30)),
      );
      final to = GlassThemeData(
        primaryColor: const Color(0xFFFFFFFF),
        renderer: const GlassRenderer.flat(),
        buttonStyle: GlassButton.styleFrom(
          foregroundColor: const Color(0xFFFF0000),
        ),
      );
      Widget themed(GlassThemeData data) =>
          AnimatedGlassTheme(data: data, child: reader);
      await tester.pumpWidget(themed(from));
      await tester.pumpWidget(themed(to));
      seen.clear();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(seen.map((e) => e.renderer).toSet(), {
        const GlassRenderer.flat(),
      });
      final reds = [for (final data in seen) data.primaryColor!.r];
      for (var i = 1; i < reds.length; i++) {
        expect(reds[i], greaterThanOrEqualTo(reds[i - 1]));
        expect(reds[i] - reds[i - 1], lessThan(0.2));
      }
      await tester.pumpAndSettle();
      expect(seen.last, same(to));

      final builds = seen.length;
      await tester.pumpWidget(themed(to));
      expect(seen.length, builds);
    });

    testWidgets('under Reduce Motion an animated theme switches at once', (
      tester,
    ) async {
      final seen = <Color?>[];
      Widget themed(Color color) => _app(
        media: const MediaQueryData(disableAnimations: true),
        AnimatedGlassTheme(
          data: GlassThemeData(primaryColor: color),
          child: Builder(
            builder: (context) {
              seen.add(GlassTheme.of(context).primaryColor);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(themed(const Color(0xFF000000)));
      await tester.pumpWidget(themed(const Color(0xFFFFFFFF)));
      expect(seen.last, const Color(0xFFFFFFFF));
    });
  });

  group('typography', () {
    test('a role takes its own size at the setting body text reports', () {
      const large = TextScaler.noScaling;
      const xxxLarge = TextScaler.linear(23 / 17);
      const ax5 = TextScaler.linear(53 / 17);
      expect(GlassTextRole.caption2.sizeFor(large), 11);
      expect(GlassTextRole.caption1.sizeFor(xxxLarge), closeTo(18, 1e-9));
      expect(GlassTextRole.largeTitle.sizeFor(xxxLarge), closeTo(40, 1e-9));
      expect(GlassTextRole.largeTitle.sizeFor(ax5), closeTo(60, 1e-9));
      expect(
        GlassTextRole.footnote.sizeFor(const TextScaler.linear(20 / 17)),
        closeTo(16, 1e-9),
      );
    });

    testWidgets('text under a role scales on the role curve, nested roles '
        'do not compound', (tester) async {
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(textScaler: TextScaler.linear(23 / 17)),
          const GlassDefaultTextStyle(
            role: GlassTextRole.body,
            child: GlassDefaultTextStyle(
              role: GlassTextRole.caption1,
              child: Text('caption'),
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('caption'),
      );
      expect(paragraph.textScaler.scale(12), closeTo(18, 1e-9));
    });

    testWidgets('on iOS the system font gets its optical size and tracking '
        'at the painted size, and no weight axis under Bold Text', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      late TextStyle plain;
      late TextStyle bold;
      Widget probe(void Function(TextStyle) write) => Builder(
        builder: (context) {
          write(
            resolveGlassText(
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              context,
            ),
          );
          return const SizedBox();
        },
      );
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(textScaler: TextScaler.linear(28 / 17)),
          probe((style) => plain = style),
        ),
      );
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(boldText: true),
          probe((style) => bold = style),
        ),
      );
      expect(plain.letterSpacing, closeTo(glassTracking(28), 1e-9));
      expect(plain.fontVariations, const [
        FontVariation('opsz', 28),
        FontVariation('wght', 590),
      ]);
      expect(bold.fontVariations, const [FontVariation('opsz', 17)]);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
