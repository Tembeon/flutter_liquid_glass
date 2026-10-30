import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);
const _contentKey = Key('content');

Widget _app({
  required void Function(BuildContext context) onPresent,
  Brightness brightness = Brightness.light,
  VoidCallback? onPageTap,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => GlassTheme(
    data: GlassThemeData(
      renderer: const GlassRenderer.flat(),
      brightness: brightness,
    ),
    child: child!,
  ),
  home: Builder(
    builder: (context) => ColoredBox(
      color: const Color(0xFFF2F2F7),
      child: Column(
        children: [
          const SizedBox(height: 80),
          GestureDetector(
            onTap: () => onPresent(context),
            child: const Text('present'),
          ),
          const SizedBox(height: 20),
          GestureDetector(onTap: onPageTap, child: const Text('page')),
        ],
      ),
    ),
  ),
);

Widget _content(BuildContext context) =>
    const SizedBox.expand(key: _contentKey, child: Text('sheet'));

Widget _list(BuildContext context) => ListView.builder(
  key: _contentKey,
  controller: GlassSheet.scrollControllerOf(context),
  itemCount: 50,
  itemBuilder: (context, i) => SizedBox(height: 50, child: Text('row $i')),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

Rect _sheet(WidgetTester tester) => tester.getRect(find.byKey(_contentKey));

GlassSheet _of(WidgetTester tester) =>
    GlassSheet.of(tester.element(find.byKey(_contentKey)));

Future<void> _present(
  WidgetTester tester,
  WidgetBuilder builder, {
  List<GlassSheetDetent> detents = const [
    GlassSheetDetent.medium,
    GlassSheetDetent.large,
  ],
  GlassSheetDetent? largestUndimmedDetent,
  bool showDragHandle = false,
  bool isDismissible = true,
  ValueChanged<GlassSheetDetent>? onDetentChanged,
  VoidCallback? onDismissAttempt,
  ValueChanged<Object?>? onResult,
  VoidCallback? onPageTap,
  Brightness brightness = Brightness.light,
  String? semanticLabel,
}) async {
  await tester.pumpWidget(
    _app(
      brightness: brightness,
      onPageTap: onPageTap,
      onPresent: (context) => unawaited(
        showGlassSheet<String>(
          context,
          builder: builder,
          detents: detents,
          largestUndimmedDetent: largestUndimmedDetent,
          showDragHandle: showDragHandle,
          isDismissible: isDismissible,
          semanticLabel: semanticLabel,
          onDetentChanged: onDetentChanged,
          onDismissAttempt: onDismissAttempt,
        ).then((value) => onResult?.call(value)),
      ),
    ),
  );
  await tester.tap(find.text('present'));
  await _settle(tester);
}

bool _docked(WidgetTester tester, Color color) => tester
    .widgetList<ColoredBox>(find.byType(ColoredBox))
    .any((b) => b.color.toARGB32() == color.toARGB32());

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('presents at the medium detent, floating, and docks at large', (
    tester,
  ) async {
    _phone(tester);
    await _present(tester, _content, showDragHandle: true);
    final medium = _sheet(tester);
    expect(medium.left, moreOrLessEquals(8, epsilon: 0.05));
    expect(medium.right, moreOrLessEquals(394, epsilon: 0.05));
    expect(medium.bottom, moreOrLessEquals(866, epsilon: 0.05));
    expect(medium.height, moreOrLessEquals(469.68 * 386 / 402, epsilon: 0.1));
    final sheet = _of(tester);
    expect(sheet.detent, GlassSheetDetent.medium);
    sheet.animateTo(GlassSheetDetent.large);
    await _settle(tester);
    final large = _sheet(tester);
    expect(large.top, moreOrLessEquals(62, epsilon: 0.05));
    expect(large.width, moreOrLessEquals(402, epsilon: 0.05));
    expect(sheet.detent, GlassSheetDetent.large);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the sheet tells the glass renderer the clip around its body, '
      'which places the backdrop pass of a resting sheet', (tester) async {
    _phone(tester);
    await _present(tester, _content);
    Rect? clip;
    var child = tester.renderObject(find.byKey(_contentKey));
    var parent = child.parent;
    while (parent != null && clip == null) {
      final local = parent.describeApproximatePaintClip(child);
      if (local != null) {
        clip = MatrixUtils.transformRect(parent.getTransformTo(null), local);
      }
      child = parent;
      parent = parent.parent;
    }
    final sheet = _sheet(tester);
    expect(clip, isNotNull);
    expect(clip!.left, moreOrLessEquals(sheet.left, epsilon: 0.01));
    expect(clip.top, moreOrLessEquals(sheet.top, epsilon: 0.01));
    expect(clip.right, moreOrLessEquals(sheet.right, epsilon: 0.01));
  });

  testWidgets('a tap at the top cycles the detent; a secondary click '
      'neither swells the sheet nor cycles it', (tester) async {
    _phone(tester);
    final changes = <GlassSheetDetent>[];
    await _present(
      tester,
      _content,
      showDragHandle: true,
      onDetentChanged: changes.add,
    );
    final rest = _sheet(tester);
    final click = await tester.startGesture(
      rest.topCenter + const Offset(0, 4),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(_frame);
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'a secondary button does not press the sheet',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await click.up();
    await _settle(tester);
    expect(_of(tester).detent, GlassSheetDetent.medium);
    expect(_sheet(tester), rectMoreOrLessEquals(rest, epsilon: 0.01));
    await tester.tapAt(rest.topCenter + const Offset(0, 4));
    await _settle(tester);
    expect(_of(tester).detent, GlassSheetDetent.large);
    expect(changes, [GlassSheetDetent.large]);
  });

  testWidgets('a drag up docks it, a drag down dismisses it with no result', (
    tester,
  ) async {
    _phone(tester);
    Object? result = 'pending';
    await _present(tester, _content, onResult: (value) => result = value);
    final before = _sheet(tester).top;
    await tester.drag(find.text('sheet'), const Offset(0, -300));
    await _settle(tester);
    final docked = _sheet(tester);
    expect(docked.top, lessThan(before - 100));
    expect(docked.width, moreOrLessEquals(402, epsilon: 0.05));
    await tester.fling(find.text('sheet'), const Offset(0, 500), 3000);
    await _settle(tester);
    await _settle(tester);
    expect(find.byKey(_contentKey), findsNothing);
    expect(result, isNull);
  });

  testWidgets('the sheet follows a finger 12 points after the touch, the '
      'device slop', (tester) async {
    _phone(tester);
    await _present(tester, _content);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('sheet')),
    );
    await _settle(tester);
    final held = _sheet(tester).top;
    for (var dy = 1; dy <= 11; dy++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    expect(_sheet(tester).top, held);
    for (var dy = 12; dy <= 16; dy++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    expect(_sheet(tester).top, lessThan(held - 2));
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a tap on the dimming dismisses; Navigator.pop returns', (
    tester,
  ) async {
    _phone(tester);
    Object? result = 'pending';
    await _present(
      tester,
      _content,
      detents: const [GlassSheetDetent.medium],
      onResult: (value) => result = value,
    );
    await tester.tapAt(const Offset(200, 40));
    await _settle(tester);
    expect(find.byKey(_contentKey), findsNothing);
    expect(result, isNull);
    await tester.tap(find.text('present'));
    await _settle(tester);
    Navigator.of(tester.element(find.byKey(_contentKey))).pop('done');
    await _settle(tester);
    expect(result, 'done');
    expect(find.byKey(_contentKey), findsNothing);
  });

  testWidgets('Escape closes a dismissible sheet only', (tester) async {
    _phone(tester);
    for (final dismissible in [true, false]) {
      await _present(
        tester,
        _content,
        detents: const [GlassSheetDetent.medium],
        isDismissible: dismissible,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(
        find.byKey(_contentKey),
        dismissible ? findsNothing : findsOneWidget,
      );
    }
  });

  testWidgets('an undimmed detent leaves the page behind interactive, and a '
      'drag up from it follows and docks', (tester) async {
    _phone(tester);
    var taps = 0;
    await _present(
      tester,
      _content,
      largestUndimmedDetent: GlassSheetDetent.medium,
      onPageTap: () => taps++,
    );
    await tester.tap(find.text('page'));
    expect(taps, 1);
    expect(find.byKey(_contentKey), findsOneWidget);
    final before = _sheet(tester).top;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('sheet')),
    );
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(_frame);
    }
    expect(_sheet(tester).top, lessThan(before - 100));
    await gesture.up();
    await _settle(tester);
    expect(_of(tester).detent, GlassSheetDetent.large);
    await tester.tap(find.text('page'), warnIfMissed: false);
    expect(taps, 1, reason: 'the large detent dims and takes the page');
  });

  testWidgets('a floating sheet stretches along a drag, takes touches on '
      'its stretched body only, and springs back', (tester) async {
    _phone(tester);
    await _present(tester, _content);
    final medium = _sheet(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('sheet')),
    );
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(_frame);
    }
    for (var i = 0; i < 120; i++) {
      await tester.pump(_frame);
    }
    final held = _sheet(tester);
    final ratio = (held.height / medium.height) / (held.width / medium.width);
    expect(ratio, greaterThan(1.012));
    expect(ratio, lessThan(1.018));
    final content = tester.renderObject(find.byKey(_contentKey));
    bool hits(Offset at) => tester
        .hitTestOnBinding(at)
        .path
        .any((entry) => identical(entry.target, content));
    for (final (inside, outside) in [
      (
        held.centerLeft + const Offset(0.5, 0),
        held.centerLeft - const Offset(0.5, 0),
      ),
      (
        held.centerRight - const Offset(0.5, 0),
        held.centerRight + const Offset(0.5, 0),
      ),
    ]) {
      expect(hits(inside), isTrue, reason: 'the content takes $inside');
      expect(hits(outside), isFalse, reason: '$outside is off the content');
    }
    await gesture.up();
    await _settle(tester);
    final back = _sheet(tester);
    expect(back.width, moreOrLessEquals(medium.width, epsilon: 0.01));
    expect(back.height, moreOrLessEquals(medium.height, epsilon: 0.01));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a finger moving on a resting sheet schedules no frames', (
    tester,
  ) async {
    _phone(tester);
    await _present(
      tester,
      (context) => GestureDetector(
        onHorizontalDragUpdate: (details) {},
        child: _content(context),
      ),
    );
    final rest = _sheet(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('sheet')),
    );
    await _settle(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(4, 0));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    await gesture.moveBy(const Offset(20, 0));
    await _settle(tester);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(4, 0));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    await gesture.up();
    await _settle(tester);
    expect(_sheet(tester).top, moreOrLessEquals(rest.top, epsilon: 0.05));
  });

  testWidgets('a sheet that may not leave stays and reports each attempt, '
      'but not a short refused pull', (tester) async {
    _phone(tester);
    var attempts = 0;
    await _present(
      tester,
      _content,
      detents: const [GlassSheetDetent.medium],
      isDismissible: false,
      onDismissAttempt: () => attempts++,
    );
    final rest = _sheet(tester);
    await tester.timedDrag(
      find.text('sheet'),
      const Offset(0, 12),
      const Duration(milliseconds: 600),
    );
    await _settle(tester);
    expect(attempts, 0);
    await tester.fling(find.text('sheet'), const Offset(0, 400), 3000);
    await _settle(tester);
    expect(_sheet(tester).top, moreOrLessEquals(rest.top, epsilon: 0.05));
    expect(attempts, 1);
    await tester.tapAt(const Offset(200, 40));
    await _settle(tester);
    expect(attempts, 2);
    expect(find.byKey(_contentKey), findsOneWidget);
  });

  testWidgets('a pop scope that cannot pop also holds the drag', (
    tester,
  ) async {
    _phone(tester);
    var attempts = 0;
    var invoked = 0;
    await _present(
      tester,
      (context) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) invoked++;
        },
        child: _content(context),
      ),
      detents: const [GlassSheetDetent.medium],
      onDismissAttempt: () => attempts++,
    );
    final rest = _sheet(tester);
    await tester.fling(find.text('sheet'), const Offset(0, 400), 3000);
    await _settle(tester);
    expect(find.byKey(_contentKey), findsOneWidget);
    expect(_sheet(tester).top, moreOrLessEquals(rest.top, epsilon: 0.05));
    expect(attempts, 1);
    expect(invoked, 1);
  });

  testWidgets('a detent set from code is not reported; one the user picks '
      'is', (tester) async {
    _phone(tester);
    final changes = <GlassSheetDetent>[];
    await _present(tester, _content, onDetentChanged: changes.add);
    _of(tester).animateTo(GlassSheetDetent.large);
    await _settle(tester);
    expect(changes, isEmpty);
    expect(_of(tester).detent, GlassSheetDetent.large);
    await tester.drag(find.text('sheet'), const Offset(0, 250));
    await _settle(tester);
    expect(changes, [GlassSheetDetent.medium]);
  });

  testWidgets('a scrollable hands its drags to the sheet, and one drag up '
      'expands the sheet, then scrolls the list', (tester) async {
    _phone(tester);
    await _present(tester, _list);
    final medium = _sheet(tester).top;
    await tester.drag(find.text('row 2'), const Offset(0, -250));
    await _settle(tester);
    final expanded = _sheet(tester).top;
    expect(expanded, lessThan(medium - 100));
    expect(find.text('row 0'), findsOneWidget);
    await tester.drag(find.text('row 2'), const Offset(0, -200));
    await _settle(tester);
    expect(_sheet(tester).top, expanded);
    expect(find.text('row 0'), findsNothing);

    Navigator.of(tester.element(find.byKey(_contentKey))).pop();
    await _settle(tester);
    await tester.tap(find.text('present'));
    await _settle(tester);
    await tester.timedDrag(
      find.text('row 2'),
      const Offset(0, -600),
      const Duration(milliseconds: 900),
    );
    await _settle(tester);
    expect(_sheet(tester).top, moreOrLessEquals(62, epsilon: 0.1));
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('the sheet is a named route for screen readers', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await _present(tester, _content, semanticLabel: 'Options');
    expect(find.bySemanticsLabel('Options'), findsOneWidget);
    expect(
      tester.semantics
          .find(find.bySemanticsLabel('Options'))
          .getSemanticsData()
          .flagsCollection
          .scopesRoute,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('docked, the sheet is opaque white, or dark gray in the dark', (
    tester,
  ) async {
    _phone(tester);
    await _present(
      tester,
      _content,
      detents: const [GlassSheetDetent.large],
      brightness: Brightness.dark,
    );
    expect(_docked(tester, const Color(0xFF1C1C1E)), isTrue);
    expect(_sheet(tester).width, 402);
  });

  testWidgets('a drag past the docking midpoint turns the fill opaque', (
    tester,
  ) async {
    _phone(tester);
    await _present(tester, _content);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('sheet')),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(_frame);
    }
    await _settle(tester);
    expect(_docked(tester, const Color(0xFFFFFFFF)), isFalse);
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(_frame);
    }
    await _settle(tester);
    expect(_docked(tester, const Color(0xFFFFFFFF)), isTrue);
    expect(
      find.byWidgetPredicate(
        (w) => w is GlassSurface && w.role == GlassRole.sheet,
      ),
      findsNothing,
    );
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('the sheet clips with continuous corners, the bottom ones '
      'concentric with the display', (tester) async {
    _phone(tester);
    await _present(tester, _content, detents: const [GlassSheetDetent.medium]);
    final clips = tester.layers.whereType<ClipRSuperellipseLayer>().where(
      (l) => l.clipRSuperellipse!.tlRadiusX == 38,
    );
    expect(clips, hasLength(1));
    expect(clips.single.clipRSuperellipse!.blRadiusX, 54);
  });

  testWidgets('the keyboard raises a medium sheet by its height without '
      'rebuilding content that ignores it, and pads the content above it', (
    tester,
  ) async {
    _phone(tester);
    var builds = 0;
    late EdgeInsets padding;
    await _present(tester, (context) {
      builds++;
      return Builder(
        builder: (context) {
          padding = MediaQuery.paddingOf(context);
          return _content(context);
        },
      );
    }, detents: const [GlassSheetDetent.medium]);
    final settled = builds;
    expect(_sheet(tester).top, closeTo(415.0, 0.5));
    tester.view.viewInsets = const FakeViewPadding(bottom: 328 * 3);
    await _settle(tester);
    // UIKit: value 435.68 + 328, still floating: top 100.1.
    expect(_sheet(tester).top, closeTo(100.1, 0.5));
    expect(builds, settled);
    expect(padding.bottom, 328);
    expect(padding.top, 0);
    expect(
      MediaQuery.viewInsetsOf(tester.element(find.byKey(_contentKey))),
      EdgeInsets.zero,
    );
    tester.view.resetViewInsets();
    await _settle(tester);
    expect(_sheet(tester).top, closeTo(415.0, 0.5));
  });

  testWidgets('custom and fitted detents', (tester) async {
    _phone(tester);
    await _present(
      tester,
      _content,
      detents: [
        GlassSheetDetent.custom(
          (maximum) => maximum * 0.25,
          identifier: 'quarter',
        ),
      ],
    );
    final quarter = _sheet(tester).height;
    expect(quarter, greaterThan(0));
    Navigator.of(tester.element(find.byKey(_contentKey))).pop();
    await _settle(tester);
    await _present(
      tester,
      (context) =>
          const SizedBox(key: _contentKey, height: 200, child: Text('fitted')),
      detents: const [GlassSheetDetent.fitted],
    );
    expect(_sheet(tester).height, moreOrLessEquals(200 * 386 / 402));
    expect(_sheet(tester).bottom, lessThan(874 - 34));
  });
}
