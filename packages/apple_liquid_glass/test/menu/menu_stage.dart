import 'dart:convert';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/menu_layer_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/testing.dart';

import '../support/fixtures.dart';

/// The rows of the recording [name] of the menu family on the device.
List<Map<String, Object?>> menuRecording(String name) => [
  for (final line in Fixtures.lines(
    'test/fixtures/ios27-device/menu_api/'
    '$name.jsonl',
  ))
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

/// The number [key] of a recorded [row].
double recorded(Map<String, Object?> row, String key) =>
    (row[key]! as num).toDouble();

/// A phone (an iPhone 16 Pro unless told otherwise) whose motions all run on
/// one manual clock: a test steps the clock and puts touches down at their
/// stamps, as a device recording has them, and reads what the user sees:
/// the menu open or not, the rows shown, the actions run and the haptics
/// played, each with its time.
class MenuStage {
  /// Puts every motion of [tester]'s tree on [clock].
  MenuStage(this.tester) {
    MotionClock.instance = clock;
  }

  /// The tester.
  final WidgetTester tester;

  /// The clock every motion runs on.
  final clock = ManualMotionClock();

  /// The menu's controller, for a source given it.
  final controller = GlassMenuController();

  /// The titles of the rows chosen, in order.
  final chosen = <String>[];

  /// The time each of [chosen] ran.
  final chosenAt = <double>[];

  /// The haptics played, with their times.
  final haptics = <(double, String)>[];

  /// The longest frame [runTo] steps.
  double step = 1 / 120;

  /// A row titled [title] whose action [chosen] records.
  GlassMenuItem item(String title, {Widget? icon, bool destructive = false}) =>
      GlassMenuItem(
        title: title,
        icon: icon,
        destructive: destructive,
        onPressed: () {
          chosen.add(title);
          chosenAt.add(clock.now);
        },
      );

  /// Shows [home] in a glass app on a phone of [size] whose bars take
  /// [padding], recording the haptics.
  Future<void> show(
    Widget home, {
    Size size = const Size(402, 874),
    EdgeInsets padding = const EdgeInsets.only(top: 62, bottom: 34),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding(
      top: padding.top * 3,
      bottom: padding.bottom * 3,
    );
    addTearDown(tester.view.reset);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add((clock.now, call.arguments! as String));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      WidgetsApp(
        key: ObjectKey(this),
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        builder: (context, child) =>
            GlassScope(renderer: const FlatGlassRenderer(), child: child!),
        home: home,
      ),
    );
  }

  /// Steps the clock to [t], [step] at a time, building and drawing a frame
  /// at each.
  Future<void> runTo(double t) async {
    while (clock.now + step < t) {
      await _frame(clock.now + step);
    }
    if (t > clock.now) await _frame(t);
  }

  Future<void> _frame(double t) async {
    final dt = t - clock.now;
    clock.advanceTo(t);
    await tester.pump(Duration(microseconds: (dt * 1e6).round()));
  }

  /// Puts a finger down at [at] at [t].
  Future<TestGesture> down(double t, Offset at) async {
    await runTo(t);
    return tester.startGesture(at);
  }

  /// Moves [finger] to [at] at [t].
  Future<void> move(TestGesture finger, double t, Offset at) async {
    await runTo(t);
    await finger.moveTo(at);
  }

  /// Lifts [finger] at [t], where it is.
  Future<void> up(TestGesture finger, double t) async {
    await runTo(t);
    await finger.up();
  }

  /// A finger down at [at] at [t] and lifted there [hold] later.
  Future<void> tap(double t, Offset at, {double hold = 0.05}) async {
    final finger = await down(t, at);
    await up(finger, t + hold);
  }

  /// Replays the touches of [recording] from [from] (in its seconds) on,
  /// shifted by [shift], the first at [start] on the clock; [frame] runs
  /// after each.
  Future<void> replay(
    List<Map<String, Object?>> recording, {
    required double start,
    double from = double.negativeInfinity,
    Offset shift = Offset.zero,
    void Function()? frame,
  }) async {
    final touches = [
      for (final row in recording)
        if (row['k'] == 'touch' && recorded(row, 't') >= from) row,
    ];
    if (touches.isEmpty) return;
    final t0 = recorded(touches.first, 't');
    TestGesture? finger;
    for (final row in touches) {
      final t = start + recorded(row, 't') - t0;
      final at = Offset(recorded(row, 'x'), recorded(row, 'y')) + shift;
      switch (row['phase']) {
        case 0:
          finger = await down(t, at);
        case 1:
          await move(finger!, t, at);
        case 3:
          await move(finger!, t, at);
          await finger.up();
      }
      frame?.call();
    }
  }

  /// Whether the menu shows or is on its way to showing.
  bool get isOpen => controller.isOpen;

  /// Whether a row titled [title] is in the tree.
  bool shows(String title) => find.text(title).evaluate().isNotEmpty;

  /// The centre of the row titled [title].
  Offset centerOf(String title) => tester.getCenter(find.text(title));

  /// The open menu's motion. What the user sees comes first; this is for
  /// where the test puts a finger and for the highlight, which no widget
  /// reports.
  MenuMotion get motion => (tester.state(_layer) as MenuLayerScope).motion;

  static final _layer = find.byElementPredicate(
    (element) => element is StatefulElement && element.state is MenuLayerScope,
    skipOffstage: false,
  );

  /// The row of card [card] the highlight shows on, or null for none.
  int? highlightOn(int card) {
    if (_layer.evaluate().isEmpty) return null;
    final motion = this.motion;
    return motion.highlightedCard == card ? motion.highlighted : null;
  }
}
