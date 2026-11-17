import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

Widget _app(Widget home, {GlobalKey<NavigatorState>? navigator}) => WidgetsApp(
  navigatorKey: navigator,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) =>
      GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  home: home,
);

void _phone(WidgetTester tester, {double textScale = 3}) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

/// Every text on screen whose optical size axis is set, checked against
/// the size its paragraph draws it at; returns the texts checked.
Set<String> _expectOpticalSizesDrawn(WidgetTester tester) {
  final checked = <String>{};
  void spans(InlineSpan root, TextScaler scaler) {
    void visit(InlineSpan span, TextStyle inherited) {
      if (span is! TextSpan) return;
      final style = inherited.merge(span.style);
      final text = span.text;
      final opsz = style.fontVariations?.where((v) => v.axis == 'opsz');
      if (text != null && text.trim().isNotEmpty && opsz != null) {
        final drawn = scaler.scale(style.fontSize ?? kDefaultFontSize);
        expect(
          opsz.single.value,
          closeTo(drawn, 0.01),
          reason: '"$text" draws at $drawn',
        );
        checked.add(text);
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }

    visit(root, const TextStyle());
  }

  void walk(RenderObject object) {
    if (object is RenderParagraph) spans(object.text, object.textScaler);
    if (object is RenderEditable) {
      final text = object.text;
      if (text != null) spans(text, object.textScaler);
    }
    object.visitChildren(walk);
  }

  tester.binding.renderViews.forEach(walk);
  return checked;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('an alert resolves and measures its text at its cap, so two '
      'labels that fit side by side at the cap share a row', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(const SizedBox.expand(), navigator: navigator),
    );
    unawaited(
      showGlassAlert(
        navigator.currentContext!,
        title: const Text('Title'),
        message: const Text('Message'),
        actions: [
          GlassAlertAction(onPressed: () {}, child: const Text('Yes')),
          GlassAlertAction(onPressed: () {}, child: const Text('Not')),
        ],
      ),
    );
    await _settle(tester);
    expect(
      tester.getCenter(find.text('Yes')).dy,
      tester.getCenter(find.text('Not')).dy,
    );
    expect(
      _expectOpticalSizesDrawn(tester),
      containsAll(['Title', 'Message', 'Yes', 'Not']),
    );
  }, variant: _ios);

  testWidgets('a date picker resolves its title and weekdays at its cap and '
      'its days unscaled', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        Center(
          child: GlassDatePicker(
            value: DateTime(2026, 11, 17),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(
      _expectOpticalSizesDrawn(tester),
      containsAll(['November 2026', 'SUN', '17']),
    );
  }, variant: _ios);

  testWidgets('a time picker resolves its rows unscaled', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        Center(
          child: GlassTimePicker(
            value: DateTime(2026, 11, 17, 9, 41),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(_expectOpticalSizesDrawn(tester), containsAll(['41']));
  }, variant: _ios);

  testWidgets('a compact date picker resolves its label and its overlay at '
      'their caps', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        Center(
          child: GlassCompactDatePicker(
            value: DateTime(2026, 11, 17),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await _settle(tester);
    final label = _expectOpticalSizesDrawn(tester);
    expect(label, isNotEmpty);
    await tester.tap(find.byType(GlassCompactDatePicker));
    await _settle(tester);
    expect(_expectOpticalSizesDrawn(tester), containsAll(['17']));
  }, variant: _ios);

  testWidgets('a search field resolves its placeholder and its text at its '
      'cap', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const Center(child: SizedBox(width: 360, child: GlassSearchField())),
      ),
    );
    await _settle(tester);
    expect(_expectOpticalSizesDrawn(tester), contains('Search'));
    await tester.enterText(find.byType(EditableText), 'glass');
    await _settle(tester);
    expect(_expectOpticalSizesDrawn(tester), contains('glass'));
  }, variant: _ios);

  testWidgets('a segmented control, a tab bar with a badge and a navigation '
      'bar resolve their labels at their caps', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        GlassPageScaffold(
          navigationBar: const GlassNavigationBar(
            title: Text('Inline'),
            largeTitle: Text('Large'),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: GlassSegmentedControl<String>(
                  segments: const [
                    GlassSegment(value: 'a', label: Text('One')),
                    GlassSegment(value: 'b', label: Text('Two')),
                  ],
                  groupValue: 'a',
                  onChanged: (_) {},
                ),
              ),
              GlassTabBar(
                destinations: const [
                  GlassTabDestination(
                    icon: SizedBox.square(dimension: 24),
                    label: Text('Home'),
                    badge: GlassBadge.count(3),
                  ),
                  GlassTabDestination(
                    icon: SizedBox.square(dimension: 24),
                    label: Text('More'),
                  ),
                ],
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(
      _expectOpticalSizesDrawn(tester),
      containsAll(['Inline', 'Large', 'One', 'Two', 'Home', 'More', '3']),
    );
  }, variant: _ios);

  testWidgets('an open menu measures and draws its rows at one scale', (
    tester,
  ) async {
    _phone(tester, textScale: 1.2);
    await tester.pumpWidget(
      _app(
        Center(
          child: GlassMenuAnchor(
            menuChildren: [
              for (final title in ['Copy', 'Share'])
                GlassMenuItem(title: title, onPressed: () {}),
            ],
            builder: (context, controller, child) =>
                GlassButton(onPressed: controller.open, child: child!),
            child: const Text('Menu'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Menu'));
    await _settle(tester);
    expect(
      _expectOpticalSizesDrawn(tester),
      containsAll(['Menu', 'Copy', 'Share']),
    );
  }, variant: _ios);
}
