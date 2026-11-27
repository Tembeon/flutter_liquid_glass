import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(GlobalKey<NavigatorState> navigator) => WidgetsApp(
  navigatorKey: navigator,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) =>
      GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  home: const ColoredBox(
    color: Color(0xFFFFFFFF),
    child: Center(child: Text('Home')),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

BuildContext _context(GlobalKey<NavigatorState> navigator) =>
    navigator.currentContext!;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('at AX3 the text grows as UIKit grows it', (tester) async {
    await _phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 40 / 17;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Title'),
        actions: const [GlassAlertAction(child: Text('OK'))],
      ),
    );
    await _settle(tester);
    double drawn(String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      return paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
    }

    expect(drawn('Title'), closeTo(40, 0.01));
    expect(drawn('OK'), closeTo(40, 0.01));
  });

  testWidgets('a message that changes while the alert shows changes in '
      'place, as a widget that listens', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final left = ValueNotifier(3);
    addTearDown(left.dispose);
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Uploading'),
        message: ValueListenableBuilder<int>(
          valueListenable: left,
          builder: (context, count, _) => Text('$count photos left'),
        ),
        actions: const [GlassAlertAction(child: Text('Hide'))],
      ),
    );
    await _settle(tester);
    expect(find.text('3 photos left'), findsOneWidget);
    left.value = 1;
    await tester.pump();
    expect(find.text('1 photos left'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the message under a title is secondaryLabel, 0.8 under '
      'Increase Contrast', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Title'),
        message: const Text('Message'),
        actions: const [GlassAlertAction(child: Text('OK'))],
      ),
    );
    await _settle(tester);
    Color? message() => tester
        .renderObject<RenderParagraph>(find.text('Message'))
        .text
        .style!
        .color;
    expect(message(), isSameColorAs(const Color(0x993C3C43)));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(message(), isSameColorAs(const Color(0xCC3C3C43)));
  });

  testWidgets('text fields stand as one group under the message, 290 by 48 '
      'a row with no gap, the first focused, the buttons 20 under the last', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    final name = TextEditingController();
    addTearDown(name.dispose);
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    GlassAlertAction? result;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Sign in'),
        message: const Text('Enter your name and password.'),
        textFields: [
          GlassAlertTextField(
            controller: name,
            placeholder: 'Name',
            onChanged: (text) => ready.value = text.isNotEmpty,
          ),
          const GlassAlertTextField(placeholder: 'Password', obscureText: true),
        ],
        actions: [
          const GlassAlertAction.cancel(child: Text('Cancel')),
          GlassAlertAction(
            isDefaultAction: true,
            enabled: false,
            enabledListenable: ready,
            child: const Text('OK'),
          ),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    final fields = find.byType(RawGlassTextField);
    expect(fields, findsNWidgets(2));
    final first = tester.getRect(fields.at(0));
    final second = tester.getRect(fields.at(1));
    expect(first.size, const Size(290, 48));
    expect(second.top, first.bottom, reason: 'no gap between rows');
    final platter = tester.getRect(
      find.ancestor(of: fields.at(0), matching: find.byType(ListView)),
    );
    expect(first.left - platter.left, 15);
    final button = tester.getRect(find.text('OK'));
    expect(button.center.dy, greaterThan(second.bottom + 20));
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
      reason: 'the first field raises the keyboard',
    );

    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(result, isNull, reason: 'OK waits for a name');
    await tester.enterText(find.byType(EditableText).first, 'Ann');
    await tester.pump();
    expect(ready.value, isTrue);
    await tester.tap(find.text('OK'));
    await _settle(tester);
    expect(result?.isDefaultAction, isTrue);
    expect(name.text, 'Ann');
  });

  testWidgets('a tap chooses an action, whose handler runs once the alert '
      'has gone', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    final ran = <String>[];
    GlassAlertAction? result;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Delete draft?'),
        message: const Text('It cannot be undone.'),
        actions: [
          GlassAlertAction.cancel(
            child: const Text('Cancel'),
            onPressed: () => ran.add('cancel'),
          ),
          GlassAlertAction.destructive(
            isDefaultAction: true,
            onPressed: () => ran.add('delete'),
            child: const Text('Delete'),
          ),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    expect(find.text('Delete draft?'), findsOneWidget);
    final cancel = tester.getCenter(find.text('Cancel'));
    final delete = tester.getCenter(find.text('Delete'));
    expect(cancel.dy, delete.dy, reason: 'two short labels share a row');
    expect(cancel.dx, lessThan(delete.dx), reason: 'cancel goes first');
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(ran, isEmpty);
    await _settle(tester);
    expect(ran, ['delete']);
    expect(result?.isDestructive, isTrue);
    expect(find.text('Delete draft?'), findsNothing);
  });

  testWidgets('three actions stand in a column with cancel last; Escape '
      'cancels and Return chooses the default action', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    GlassAlertAction? result;
    final actions = [
      const GlassAlertAction.cancel(child: Text('Cancel')),
      const GlassAlertAction(child: Text('Keep')),
      const GlassAlertAction(isDefaultAction: true, child: Text('Save')),
    ];
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Save changes?'),
        actions: actions,
      ).then((value) => result = value),
    );
    await _settle(tester);
    final keep = tester.getCenter(find.text('Keep')).dy;
    final save = tester.getCenter(find.text('Save')).dy;
    final cancel = tester.getCenter(find.text('Cancel')).dy;
    expect(keep, lessThan(save));
    expect(save, lessThan(cancel));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(result, same(actions[0]));

    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Save changes?'),
        actions: actions,
      ).then((value) => result = value),
    );
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(result, same(actions[2]));
  });

  testWidgets('a finger that slides to another button chooses it', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    GlassAlertAction? result;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
          GlassAlertAction(child: Text('Three')),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(_frame);
    await gesture.moveTo(tester.getCenter(find.text('Three')));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect((result?.child as Text?)?.data, 'Three');
  });

  testWidgets('a slide onto another button clicks, the touch-down does not', (
    tester,
  ) async {
    await _phone(tester);
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
          GlassAlertAction(child: Text('Three')),
        ],
      ),
    );
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(_frame);
    expect(haptics, isEmpty);
    await gesture.moveTo(tester.getCenter(find.text('Two')));
    await tester.pump(_frame);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a finger lifted over no button chooses nothing', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var done = false;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
        ],
      ).then((_) => done = true),
    );
    await _settle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await tester.pump(_frame);
    await gesture.moveTo(tester.getCenter(find.text('Pick')));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect(done, isFalse);
    expect(find.text('Pick'), findsOneWidget);
  });

  testWidgets('a finger put down on the title slides onto no button; one '
      'that left a button over the title chooses the button it comes back '
      'onto', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    Future<String?> slide(List<String> path) async {
      String? chosen;
      var done = false;
      unawaited(
        showGlassAlert(
          _context(navigator),
          title: const Text('Pick'),
          actions: const [
            GlassAlertAction(child: Text('One')),
            GlassAlertAction(child: Text('Two')),
          ],
        ).then((value) {
          chosen = (value?.child as Text?)?.data;
          done = true;
        }),
      );
      await _settle(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(path.first)),
      );
      await tester.pump(_frame);
      for (final title in path.skip(1)) {
        await gesture.moveTo(tester.getCenter(find.text(title)));
        await tester.pump(_frame);
      }
      await gesture.up();
      await _settle(tester);
      if (!done) {
        Navigator.of(_context(navigator)).pop();
        await _settle(tester);
      }
      return chosen;
    }

    expect(await slide(['Pick', 'Two']), isNull);
    expect(await slide(['One', 'Pick', 'Two']), 'Two');
  });

  testWidgets('a finger that scrolls a long alert chooses nothing', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var done = false;
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Pick'),
        message: Text('A long message. ' * 120),
        actions: const [
          GlassAlertAction(child: Text('One')),
          GlassAlertAction(child: Text('Two')),
        ],
      ).then((_) => done = true),
    );
    await _settle(tester);
    final start = tester.getCenter(find.text('Pick'));
    final gesture = await tester.startGesture(start);
    await tester.pump(_frame);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(0, -12.0 * i));
      await tester.pump(_frame);
    }
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    await gesture.moveTo(tester.getCenter(find.text('One')));
    await tester.pump(_frame);
    await gesture.up();
    await _settle(tester);
    expect(done, isFalse);
  });

  testWidgets('a tap outside an alert does nothing; outside an action sheet '
      'it cancels', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Stay'),
        actions: const [GlassAlertAction(child: Text('OK'))],
      ),
    );
    await _settle(tester);
    await tester.tapAt(const Offset(20, 60));
    await _settle(tester);
    expect(find.text('Stay'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await _settle(tester);

    GlassAlertAction? result;
    const cancel = GlassAlertAction.cancel(child: Text('Cancel'));
    unawaited(
      showGlassActionSheet(
        _context(navigator),
        title: const Text('Share'),
        actions: const [
          cancel,
          GlassAlertAction(child: Text('Copy')),
          GlassAlertAction(child: Text('Mail')),
        ],
      ).then((value) => result = value),
    );
    await _settle(tester);
    expect(
      tester.getCenter(find.text('Cancel')).dy,
      greaterThan(tester.getCenter(find.text('Mail')).dy),
    );
    await tester.tapAt(const Offset(20, 60));
    await _settle(tester);
    expect(result, same(cancel));
    expect(find.text('Share'), findsNothing);
  });

  testWidgets('the alert is 320 points wide and dims the page while shown', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Wide'),
        actions: const [GlassAlertAction(child: Text('OK'))],
      ),
    );
    await _settle(tester);
    final glass = tester.widget<GlassSurface>(find.byType(GlassSurface).last);
    final card = tester.getRect(find.byType(GlassSurface).last);
    expect(card.width, 320);
    expect(card.center.dx, 201);
    expect(
      glass.frame!.value.shape,
      const LiquidRoundedSuperellipse(radius: 34),
      reason: 'the platter has the alert corners, not a capsule',
    );
  });

  testWidgets('a style colors the title, the actions and their capsules', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      showGlassAlert(
        _context(navigator),
        title: const Text('Title'),
        actions: const [
          GlassAlertAction.cancel(child: Text('Cancel')),
          GlassAlertAction(isDefaultAction: true, child: Text('OK')),
        ],
        style: const GlassAlertStyle(
          titleTextStyle: TextStyle(color: Color(0xFF00AA00)),
          actionColor: Color(0xFFAA0000),
          defaultActionFillColor: Color(0xFF0000AA),
        ),
      ),
    );
    await _settle(tester);
    Color? color(String text) => DefaultTextStyle.of(
      tester.element(find.text(text)),
    ).style.color;
    expect(color('Title'), const Color(0xFF00AA00));
    expect(color('Cancel'), const Color(0xFFAA0000));
    expect(
      find
          .ancestor(of: find.text('OK'), matching: find.byType(CustomPaint))
          .first,
      paints..rrect(color: const Color(0xFF0000AA)),
    );
  });
}
