import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = Key('page');

Widget _app({Widget? home, List<String>? log}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => GlassScope(
    renderer: const FlatGlassRenderer(),
    child: GlassToaster(child: child!),
  ),
  home:
      home ??
      GestureDetector(
        key: _page,
        behavior: HitTestBehavior.opaque,
        onTap: () => log?.add('page'),
        child: const SizedBox.expand(),
      ),
);

void _screen(WidgetTester tester) {
  MotionClock.debugEngineNow = () =>
      Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
  addTearDown(() => MotionClock.debugEngineNow = null);
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 50);
  addTearDown(tester.view.reset);
}

GlassToastEntry _toast(
  BuildContext context,
  String title, {
  Duration? duration = GlassToaster.duration,
  Widget Function(GlassToastEntry toast)? action,
}) => showGlassToast(
  context: context,
  duration: duration,
  builder: (context, toast) =>
      GlassToast(title: Text(title), action: action?.call(toast)),
);

BuildContext _context(WidgetTester tester) => tester.element(find.byKey(_page));

Rect _rect(WidgetTester tester, String title) => tester.getRect(
  find.ancestor(of: find.text(title), matching: find.byType(GlassToast)),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a toast stands at the top center under the safe area and '
      'leaves after its duration', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final toast = _toast(_context(tester), 'Copied');
    await _settle(tester);
    final rect = _rect(tester, 'Copied');
    expect(rect.top, 50 + GlassToaster.margin);
    expect(rect.center.dx, 200);
    expect(rect.height, GlassToast.radius * 2);
    await tester.pump(GlassToaster.duration);
    expect(toast.isShown, isFalse);
    await _settle(tester);
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('a toast with no duration stays until it is dismissed, and '
      'a second dismissal does nothing', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final toast = _toast(_context(tester), 'Offline', duration: null);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(toast.isShown, isTrue);
    expect(find.text('Offline'), findsOneWidget);
    toast
      ..dismiss()
      ..dismiss();
    expect(toast.isShown, isFalse);
    await _settle(tester);
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets('toasts stack down from the top, newest first, and a fourth '
      'dismisses the oldest', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final context = _context(tester);
    final first = _toast(context, 'One');
    final second = _toast(context, 'Two');
    final third = _toast(context, 'Three');
    await _settle(tester);
    expect(_rect(tester, 'Three').top, 50 + GlassToaster.margin);
    expect(
      _rect(tester, 'Two').top,
      _rect(tester, 'Three').bottom + GlassToaster.gap,
    );
    expect(
      _rect(tester, 'One').top,
      _rect(tester, 'Two').bottom + GlassToaster.gap,
    );
    _toast(context, 'Four');
    expect(first.isShown, isFalse);
    expect([second.isShown, third.isShown], [isTrue, isTrue]);
    await _settle(tester);
    expect(find.text('One'), findsNothing);
    expect(_rect(tester, 'Four').top, 50 + GlassToaster.margin);
    expect(
      _rect(tester, 'Two').top,
      _rect(tester, 'Three').bottom + GlassToaster.gap,
    );
  });

  testWidgets('a newer toast dismisses the oldest timed one before one '
      'that stays', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final context = _context(tester);
    final retry = _toast(context, 'Retry', duration: null);
    final first = _toast(context, 'One');
    final second = _toast(context, 'Two');
    _toast(context, 'Three');
    expect(retry.isShown, isTrue);
    expect(first.isShown, isFalse);
    expect(second.isShown, isTrue);
  });

  testWidgets('an action runs and dismisses its toast', (tester) async {
    _screen(tester);
    final log = <String>[];
    await tester.pumpWidget(_app());
    final toast = _toast(
      _context(tester),
      'Moved to Archive',
      action: (toast) => GlassButton.plain(
        onPressed: () {
          toast.dismiss();
          log.add('undo');
        },
        child: const Text('Undo'),
      ),
    );
    await _settle(tester);
    expect(_rect(tester, 'Moved to Archive').height, GlassToast.radius * 2);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(log, ['undo']);
    expect(toast.isShown, isFalse);
  });

  testWidgets('a toast shown from a page outlives the page, and the '
      "navigator's context shows one too", (tester) async {
    _screen(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        navigatorKey: navigator,
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) => GlassScope(
          renderer: const FlatGlassRenderer(),
          child: GlassToaster(child: child!),
        ),
        home: const SizedBox.expand(),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (context) => const SizedBox.expand(key: _page),
        ),
      ),
    );
    await _settle(tester);
    _toast(_context(tester), 'Sent');
    navigator.currentState!.pop();
    await _settle(tester);
    expect(find.byKey(_page), findsNothing);
    expect(find.text('Sent'), findsOneWidget);
    _toast(navigator.currentContext!, 'Saved');
    await _settle(tester);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a mouse on a toast holds it, and it leaves its duration '
      'after the mouse does', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final toast = _toast(_context(tester), 'Copied');
    await _settle(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 600));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(_rect(tester, 'Copied').center);
    await tester.pump(const Duration(seconds: 8));
    expect(toast.isShown, isTrue);
    await mouse.moveTo(const Offset(200, 600));
    await tester.pump(GlassToaster.duration - const Duration(seconds: 1));
    expect(toast.isShown, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(toast.isShown, isFalse);
  });

  testWidgets('touches beside a toast reach the app, and the toast takes '
      'no focus', (tester) async {
    _screen(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log: log));
    final focused = FocusManager.instance.primaryFocus;
    _toast(_context(tester), 'Copied');
    await _settle(tester);
    expect(FocusManager.instance.primaryFocus, focused);
    await tester.tapAt(const Offset(20, 400));
    await tester.tapAt(Offset(10, _rect(tester, 'Copied').center.dy));
    expect(log, ['page', 'page']);
  });

  testWidgets('a swipe up dismisses a toast, and a short drag puts it '
      'back', (tester) async {
    _screen(tester);
    await tester.pumpWidget(_app());
    final toast = _toast(_context(tester), 'Copied');
    await _settle(tester);
    final rest = _rect(tester, 'Copied');
    await tester.timedDragFrom(
      rest.center,
      const Offset(0, -20),
      const Duration(seconds: 1),
    );
    await _settle(tester);
    expect(toast.isShown, isTrue);
    expect(_rect(tester, 'Copied'), rest);
    await tester.flingFrom(rest.center, const Offset(0, -60), 800);
    await tester.pump();
    expect(toast.isShown, isFalse);
  });

  testWidgets('a toast with an action stays while a screen reader '
      'navigates; one without leaves', (tester) async {
    _screen(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_app());
    final context = _context(tester);
    final undo = _toast(
      context,
      'Moved to Archive',
      action: (toast) =>
          GlassButton.plain(onPressed: () {}, child: const Text('Undo')),
    );
    final notice = _toast(context, 'Copied');
    await _settle(tester);
    await tester.pump(GlassToaster.duration * 2);
    expect(undo.isShown, isTrue);
    expect(notice.isShown, isFalse);
  });

  testWidgets('screen readers hear a toast as it shows and can dismiss it', (
    tester,
  ) async {
    _screen(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    final toast = _toast(_context(tester), 'Copied');
    await _settle(tester);
    final node = find.semantics.byPredicate(
      (node) =>
          node.label == 'Copied' &&
          node.flagsCollection.isLiveRegion &&
          node.getSemanticsData().hasAction(SemanticsAction.dismiss),
    );
    expect(node, findsOne);
    tester.semantics.performAction(node, SemanticsAction.dismiss);
    expect(toast.isShown, isFalse);
    semantics.dispose();
  });

  testWidgets('showGlassToast without a toaster throws', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.expand(key: _page),
      ),
    );
    expect(
      () => _toast(_context(tester), 'Copied'),
      throwsA(isA<FlutterError>()),
    );
  });
}
