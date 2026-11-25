import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

const _pale = Color(0xFFE4E4E7);

const _normal = GlassTraits();
const _contrast = GlassTraits(highContrast: true);
const _darkContrast = GlassTraits(
  brightness: Brightness.dark,
  highContrast: true,
);

final _navigator = GlobalKey<NavigatorState>();

Widget _app(
  Widget child, {
  GlassThemeData theme = const GlassThemeData(),
  bool highContrast = false,
}) => WidgetsApp(
  navigatorKey: _navigator,
  color: _black,
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      size: const Size(402, 874),
      highContrast: highContrast,
    ),
    child: GlassScope(
      data: theme,
      renderer: const FlatGlassRenderer(),
      child: home!,
    ),
  ),
  home: Align(alignment: Alignment.topLeft, child: child),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

Color? _textColor(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text).last)
    .text
    .style
    ?.color;

Color? _iconColor(WidgetTester tester, Key key) =>
    IconTheme.of(tester.element(find.byKey(key))).color;

void main() {
  setUp(MotionClock.debugReset);

  group('the rule', () {
    // UIKit 27.2's prominent glass button title over each tint, read
    // through UIButton.Configuration under Mac Catalyst.
    final rows = <(String, Color, GlassTraits, Color)>[
      ('systemBlue', const Color(0xFF0088FF), _normal, _white),
      ('systemYellow', const Color(0xFFFFCC00), _normal, _black),
      ('systemGreen', const Color(0xFF34C759), _normal, _white),
      ('systemOrange', const Color(0xFFFF8D28), _normal, _white),
      ('light accent', _pale, _normal, _black),
      ('white', _white, _normal, _black),
      ('black', _black, _normal, _white),
      ('gray 194', const Color(0xFFC2C2C2), _normal, _white),
      ('gray 196', const Color(0xFFC4C4C4), _normal, _black),
      ('Rec. 709, not 601', const Color(0xFFFFC800), _normal, _black),
      ('Rec. 709 below', const Color(0xFFFFC300), _normal, _white),
      ('pure green', const Color(0xFF00FF00), _normal, _white),
      (
        'white at 0.76',
        const Color.from(alpha: 0.76, red: 1, green: 1, blue: 1),
        _normal,
        _white,
      ),
      (
        'white at 0.77',
        const Color.from(alpha: 0.77, red: 1, green: 1, blue: 1),
        _normal,
        _black,
      ),
      ('gray 119, contrast', const Color(0xFF777777), _contrast, _white),
      ('gray 121, contrast', const Color(0xFF797979), _contrast, _black),
      (
        'Rec. 709 magenta, contrast',
        const Color(0xFFFF3CFF),
        _contrast,
        _white,
      ),
      ('pure green, contrast', const Color(0xFF00FF00), _contrast, _black),
      (
        'white at 0.7, contrast',
        const Color.from(alpha: 0.7, red: 1, green: 1, blue: 1),
        _contrast,
        _black,
      ),
      ('systemBlue, contrast', GlassColors.systemBlue, _contrast, _white),
      (
        'systemBlue, dark contrast',
        GlassColors.systemBlue,
        _darkContrast,
        _black,
      ),
      (
        'systemRed, dark contrast',
        GlassColors.systemRed,
        _darkContrast,
        _black,
      ),
    ];
    for (final (name, fill, traits, expected) in rows) {
      test(name, () {
        expect(GlassColors.legibleOn(fill, traits), expected);
      });
    }
  });

  group('content on a fill the app chooses', () {
    Widget sidebar() => const SizedBox(
      width: 320,
      height: 400,
      child: GlassTabSidebar(
        destinations: [
          GlassTabDestination(
            icon: SizedBox.square(key: Key('home'), dimension: 24),
            label: Text('Home'),
          ),
          GlassTabDestination(
            icon: SizedBox.square(key: Key('library'), dimension: 24),
            label: Text('Library'),
          ),
        ],
        selectedIndex: 1,
        onDestinationSelected: _ignore,
      ),
    );

    testWidgets('the selected sidebar row', (tester) async {
      await tester.pumpWidget(_app(sidebar()));
      expect(_textColor(tester, 'Library'), _white);
      expect(_iconColor(tester, const Key('library')), _white);

      await tester.pumpWidget(
        _app(sidebar(), theme: const GlassThemeData(primaryColor: _pale)),
      );
      await _settle(tester);
      expect(_textColor(tester, 'Library'), _black);
      expect(_iconColor(tester, const Key('library')), _black);
      expect(_iconColor(tester, const Key('home')), _pale);

      await tester.pumpWidget(
        _app(
          sidebar(),
          theme: const GlassThemeData(brightness: Brightness.dark),
          highContrast: true,
        ),
      );
      await _settle(tester);
      expect(_textColor(tester, 'Library'), _black);
    });

    testWidgets('a prominent button follows whichever fill it is given', (
      tester,
    ) async {
      Future<Color?> label(
        GlassButton button, {
        GlassThemeData theme = const GlassThemeData(),
      }) async {
        await tester.pumpWidget(_app(button, theme: theme));
        await _settle(tester);
        return _textColor(tester, 'Go');
      }

      expect(
        await label(
          GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
        ),
        _white,
      );
      expect(
        await label(
          GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
          theme: const GlassThemeData(primaryColor: _pale),
        ),
        _black,
      );
      expect(
        await label(
          GlassButton.prominentClear(onPressed: () {}, child: const Text('Go')),
          theme: const GlassThemeData(primaryColor: _pale),
        ),
        _black,
      );
      expect(
        await label(
          GlassButton.prominent(
            onPressed: () {},
            style: GlassButton.styleFrom(backgroundColor: _pale),
            child: const Text('Go'),
          ),
        ),
        _black,
      );
      expect(
        await label(
          GlassButton.prominent(onPressed: () {}, child: const Text('Go')),
          theme: GlassThemeData(
            primaryColor: _pale,
            styles: [
              GlassProminentButtonStyle.from(
                GlassButton.styleFrom(backgroundColor: GlassColors.systemBlue),
              ),
            ],
          ),
        ),
        _white,
        reason: 'the theme style fill over the accent',
      );
      expect(
        await label(
          GlassButton.prominent(
            onPressed: () {},
            style: GlassButton.styleFrom(foregroundColor: _white),
            child: const Text('Go'),
          ),
          theme: const GlassThemeData(primaryColor: _pale),
        ),
        _white,
        reason: "the style's own label wins",
      );
      expect(
        (await label(
          const GlassButton.prominent(onPressed: null, child: Text('Go')),
          theme: const GlassThemeData(primaryColor: _pale),
        ))!.toARGB32(),
        GlassDynamicColor.resolveWith(
          GlassColors.tertiaryLabel,
          _normal,
        ).toARGB32(),
        reason: 'a disabled one keeps tertiaryLabel',
      );
      expect(
        (await label(
          GlassButton(onPressed: () {}, child: const Text('Go')),
          theme: const GlassThemeData(primaryColor: _pale),
        ))!.toARGB32(),
        _black.toARGB32(),
        reason: 'a regular button keeps label',
      );
      expect(
        (await label(
          GlassButton(
            onPressed: () {},
            style: GlassButton.styleFrom(
              backgroundColor: GlassColors.systemRed,
            ),
            child: const Text('Go'),
          ),
        ))!.toARGB32(),
        _black.toARGB32(),
        reason: 'a tinted regular button keeps label',
      );
      expect(
        (await label(
          GlassButton.clear(
            onPressed: () {},
            style: GlassButton.styleFrom(disabledBackgroundColor: _pale),
            child: const Text('Go'),
          ),
        ))!.toARGB32(),
        _black.toARGB32(),
        reason: 'a fill for the disabled state alone leaves label',
      );
    });

    testWidgets('a prominent bar item', (tester) async {
      Widget page({required bool enabled}) => SizedBox(
        width: 402,
        height: 300,
        child: GlassPageScaffold(
          toolbar: GlassToolbar(
            items: [
              GlassBarItem.prominent(
                label: const Text('Done'),
                onPressed: enabled ? () {} : null,
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      );

      await tester.pumpWidget(_app(page(enabled: true)));
      await _settle(tester);
      expect(_textColor(tester, 'Done'), _white);

      await tester.pumpWidget(
        _app(
          page(enabled: true),
          theme: const GlassThemeData(primaryColor: _pale),
        ),
      );
      await _settle(tester);
      expect(_textColor(tester, 'Done'), _black);

      await tester.pumpWidget(
        _app(
          page(enabled: false),
          theme: const GlassThemeData(primaryColor: _pale),
        ),
      );
      await _settle(tester);
      expect(
        _textColor(tester, 'Done'),
        _white,
        reason: 'the gray capsule of an item without an action keeps white',
      );
    });

    testWidgets("an alert's default action", (tester) async {
      Future<Color?> save({
        GlassThemeData theme = const GlassThemeData(),
      }) async {
        await tester.pumpWidget(_app(const SizedBox(), theme: theme));
        unawaited(
          showGlassAlert(
            _navigator.currentContext!,
            title: const Text('Save changes?'),
            actions: const [
              GlassAlertAction.cancel(child: Text('Cancel')),
              GlassAlertAction(isDefaultAction: true, child: Text('Save')),
            ],
          ),
        );
        await _settle(tester);
        final color = _textColor(tester, 'Save');
        _navigator.currentState!.pop();
        await _settle(tester);
        return color;
      }

      expect(await save(), _white);
      expect(
        await save(theme: const GlassThemeData(primaryColor: _pale)),
        _black,
      );
    });

    testWidgets("the calendar's chosen day", (tester) async {
      Future<Color?> number({
        required DateTime value,
        GlassThemeData theme = const GlassThemeData(),
        GlassDatePickerStyle? style,
      }) async {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 402,
              child: GlassDatePicker(
                value: value,
                today: DateTime(2026, 10, 3),
                style: style,
                onChanged: (_) {},
              ),
            ),
            theme: theme,
          ),
        );
        await _settle(tester);
        return _textColor(tester, '${value.day}');
      }

      final today = DateTime(2026, 10, 3);
      final other = DateTime(2026, 10, 14);
      expect(await number(value: today), _white);
      expect(
        await number(
          value: today,
          theme: const GlassThemeData(primaryColor: _pale),
        ),
        _black,
      );
      expect(await number(value: other), _white, reason: 'on a black disc');
      expect(
        await number(
          value: other,
          theme: const GlassThemeData(brightness: Brightness.dark),
        ),
        _black,
        reason: 'on a white disc',
      );
      expect(
        await number(
          value: other,
          style: const GlassDatePickerStyle(labelColor: _pale),
        ),
        _black,
      );
    });

    testWidgets('a badge', (tester) async {
      await tester.pumpWidget(_app(const GlassBadge.count(3)));
      expect(_textColor(tester, '3'), _white);
      await tester.pumpWidget(
        _app(
          const GlassBadge.count(
            3,
            style: GlassBadgeStyle(backgroundColor: _pale),
          ),
        ),
      );
      expect(_textColor(tester, '3'), _black);
    });

    testWidgets('a swipe action', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 402,
            child: GlassSwipeActions(
              trailing: [
                GlassSwipeAction(
                  title: 'Delete',
                  destructive: true,
                  onPressed: () {},
                ),
                GlassSwipeAction(
                  title: 'Pin',
                  backgroundColor: _pale,
                  onPressed: () {},
                ),
              ],
              child: const GlassListRow(title: Text('Message')),
            ),
          ),
        ),
      );
      await tester.drag(
        find.text('Message'),
        const Offset(-300, 0),
        touchSlopX: 0,
      );
      await _settle(tester);
      expect(_textColor(tester, 'Delete'), _white);
      expect(_textColor(tester, 'Pin'), _black);
    });
  });
}

void _ignore(int _) {}
