import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

Widget _widgetsApp(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Center(child: child),
);

Widget _list(Widget item) => _app(
  ListView(
    children: [
      const SizedBox(height: 100),
      SizedBox(height: 60, child: item),
      const SizedBox(height: 2000),
    ],
  ),
);

void main() {
  final haptics = <String>[];

  setUp(() {
    MotionClock.debugReset();
    haptics.clear();
  });

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  testWidgets('a press activates on release with its states and haptic', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    var presses = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: _Pressable(
            onPressed: () => presses++,
            haptic: MotionHaptic.lightImpact,
            statesController: states,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Pressable)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(states.value, contains(WidgetState.pressed));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(presses, 1);
    expect(states.value, isNot(contains(WidgetState.pressed)));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('in a scroll view a held press highlights after 0.15 s', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    await tester.pumpWidget(
      _list(
        _Pressable(
          onPressed: () {},
          statesController: states,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Pressable)),
    );
    // A test's frame clock and engine clock disagree, so the motion clock
    // starts counting at the first frame after the touch.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(states.value, isNot(contains(WidgetState.pressed)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(states.value, contains(WidgetState.pressed));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a quick swipe scrolls the list and never presses', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    var presses = 0;
    final pressed = <bool>[];
    states.addListener(
      () => pressed.add(states.value.contains(WidgetState.pressed)),
    );
    await tester.pumpWidget(
      _list(
        _Pressable(
          onPressed: () => presses++,
          statesController: states,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(find.byType(_Pressable), const Offset(0, -200));
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(list.position.pixels, greaterThan(0));
    expect(presses, 0);
    expect(pressed, isNot(contains(true)));
  });

  testWidgets('a region nothing in takes never blocks a scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      _list(const InputRegion(interactions: [], child: SizedBox.expand())),
    );
    final before = tester.getTopLeft(find.byType(InputRegion)).dy;
    await tester.drag(find.byType(InputRegion), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(InputRegion)).dy, lessThan(before));
  });

  testWidgets('a drag ends with the velocity of its own release sample', (
    tester,
  ) async {
    DragInteractionDetails? end;
    await tester.pumpWidget(
      _app(
        Center(
          child: InputRegion(
            interactions: [
              DragInteraction(
                axis: Axis.horizontal,
                onEnd: (details) => end = details,
              ),
            ],
            child: const SizedBox(width: 300, height: 100),
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.byType(InputRegion));
    final reference = VelocityTracker.withKind(PointerDeviceKind.touch);
    final gesture = await tester.createGesture();
    await gesture.down(start);
    reference.addPosition(.zero, const Offset(150, 50));
    for (var i = 1; i <= 6; i++) {
      final time = Duration(milliseconds: 8 * i);
      await gesture.moveTo(start + Offset(12.0 * i, 0), timeStamp: time);
      reference.addPosition(time, Offset(150 + 12.0 * i, 50));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 56));
    reference.addPosition(
      const Duration(milliseconds: 56),
      const Offset(222, 50),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(end, isNotNull);
    expect(
      end!.velocity.dx,
      closeTo(reference.getVelocity().pixelsPerSecond.dx, 1e-6),
    );
  });

  testWidgets('a long press does not press as well', (tester) async {
    final heard = <String>[];
    await tester.pumpWidget(
      _app(
        Center(
          child: _Pressable(
            onPressed: () => heard.add('press'),
            onLongPress: () => heard.add('long'),
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_Pressable)),
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(heard, ['long']);
  });

  testWidgets('a pressable without onPressed is disabled', (tester) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    await tester.pumpWidget(
      _app(
        _Pressable(
          onPressed: null,
          statesController: states,
          child: const SizedBox(width: 80, height: 40),
        ),
      ),
    );
    expect(states.value, contains(WidgetState.disabled));
  });

  group('activation by intent', () {
    Future<void> focusRegion(WidgetTester tester) async {
      Focus.of(tester.element(find.byType(SizedBox))).requestFocus();
      await tester.pump();
    }

    testWidgets('Space and Enter activate a focused press with no haptic', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _widgetsApp(
          _Pressable(
            onPressed: () => presses++,
            haptic: MotionHaptic.lightImpact,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      await focusRegion(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(presses, 2);
      expect(haptics, isEmpty);
    });

    testWidgets('an app remaps the keys with Shortcuts', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _widgetsApp(
          Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.space):
                  DoNothingAndStopPropagationIntent(),
              SingleActivator(LogicalKeyboardKey.keyX): ActivateIntent(),
            },
            child: _Pressable(
              onPressed: () => presses++,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      );
      await focusRegion(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(presses, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(presses, 1);
    });

    testWidgets('an app overrides activation with Actions', (tester) async {
      var presses = 0;
      var overridden = 0;
      await tester.pumpWidget(
        _widgetsApp(
          Actions(
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) => overridden++,
              ),
            },
            child: _Pressable(
              onPressed: () => presses++,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      );
      await focusRegion(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect((presses, overridden), (0, 1));
    });

    testWidgets('a region that does not activate leaves the key unhandled', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _widgetsApp(
          InputRegion(
            interactions: [DragInteraction()],
            focusNode: focus,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse);
    });
  });

  testWidgets('an interaction of its own reports pressed and dragged', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    final held = _Held();
    await tester.pumpWidget(
      _app(
        Center(
          child: InputRegion(
            interactions: [held],
            statesController: states,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InputRegion)),
    );
    await tester.pump();
    expect(
      states.value,
      containsAll([WidgetState.pressed, WidgetState.dragged]),
    );
    await gesture.up();
    await tester.pump();
    expect(states.value, isNot(contains(WidgetState.pressed)));
    expect(states.value, isNot(contains(WidgetState.dragged)));
  });

  group('cursor', () {
    MouseCursor? active() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

    Future<TestGesture> hoverAt(WidgetTester tester, Offset at) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await gesture.addPointer(location: at);
      addTearDown(gesture.removePointer);
      await tester.pump();
      return gesture;
    }

    testWidgets('a state cursor resolves against the region states', (
      tester,
    ) async {
      final cursor = WidgetStateMouseCursor.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? SystemMouseCursors.forbidden
            : states.contains(WidgetState.pressed)
            ? SystemMouseCursors.grabbing
            : states.contains(WidgetState.hovered)
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
      );
      Widget region({required bool enabled}) => _app(
        Center(
          child: InputRegion(
            interactions: [PressInteraction()],
            enabled: enabled,
            mouseCursor: cursor,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      await tester.pumpWidget(region(enabled: true));
      final center = tester.getCenter(find.byType(InputRegion));
      final gesture = await hoverAt(tester, center);
      expect(active(), SystemMouseCursors.click);
      await gesture.down(center);
      await tester.pump();
      expect(active(), SystemMouseCursors.grabbing);
      await gesture.up();
      await tester.pump();
      expect(active(), SystemMouseCursors.click);
      await tester.pumpWidget(region(enabled: false));
      expect(active(), SystemMouseCursors.forbidden);
    });

    testWidgets('the default is adaptive clickable for what activates and '
        'defers otherwise', (tester) async {
      Widget region(List<Interaction> interactions) => _app(
        MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Center(
            child: InputRegion(
              interactions: interactions,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpWidget(region([PressInteraction()]));
      await hoverAt(tester, tester.getCenter(find.byType(InputRegion)));
      expect(
        active(),
        WidgetStateMouseCursor.adaptiveClickable.resolve(const {}),
      );
      await tester.pumpWidget(region([DragInteraction()]));
      await tester.pump();
      expect(active(), SystemMouseCursors.text);
    });
  });

  group('minimum hit size', () {
    Widget small({Size? minimum, VoidCallback? onTap}) => _app(
      Center(
        child: InputRegion(
          interactions: [PressInteraction(onTap: (t) => onTap?.call())],
          semanticLabel: 'small',
          minimumHitSize: minimum,
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    );

    testWidgets('taps in the extension press and taps beyond it do not', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        small(minimum: const Size(44, 44), onTap: () => taps++),
      );
      final center = tester.getCenter(find.byType(InputRegion));
      expect(tester.getSize(find.byType(InputRegion)), const Size(20, 20));
      await tester.tapAt(center + const Offset(21, 0));
      await tester.tapAt(center + const Offset(0, -21));
      expect(taps, 2);
      await tester.tapAt(center + const Offset(23, 0));
      await tester.tapAt(center + const Offset(0, 23));
      expect(taps, 2);
    });

    testWidgets('the semantics rectangle grows and meets the iOS tap '
        'target guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(small(minimum: const Size(44, 44)));
      expect(
        tester.getSemantics(find.byType(InputRegion)),
        matchesSemantics(
          label: 'small',
          rect: const Rect.fromLTRB(-12, -12, 32, 32),
          textDirection: TextDirection.ltr,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await tester.pumpWidget(small());
      await expectLater(tester, doesNotMeetGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });
  });

  group('value commands', () {
    Widget value(
      _Value interaction, {
      TextDirection direction = TextDirection.ltr,
      bool enabled = true,
      MotionHaptic? haptic,
    }) => WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => Directionality(
        textDirection: direction,
        child: Center(
          child: InputRegion(
            interactions: [interaction],
            enabled: enabled,
            semanticLabel: 'level',
            autofocus: true,
            feedback: (_) => haptic,
            child: const SizedBox(width: 120, height: 30),
          ),
        ),
      ),
    );

    testWidgets('the default keys step a value, arrows mirrored in '
        'right-to-left', (tester) async {
      final ltr = _Value();
      await tester.pumpWidget(value(ltr));
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(ltr.heard, [
        (ValueCommand.increase, ActivationSource.keyboard),
        (ValueCommand.decrease, ActivationSource.keyboard),
        (ValueCommand.increase, ActivationSource.keyboard),
        (ValueCommand.decrease, ActivationSource.keyboard),
        (ValueCommand.toMinimum, ActivationSource.keyboard),
        (ValueCommand.toMaximum, ActivationSource.keyboard),
        (ValueCommand.increaseLarge, ActivationSource.keyboard),
        (ValueCommand.decreaseLarge, ActivationSource.keyboard),
      ]);
      final rtl = _Value();
      await tester.pumpWidget(value(rtl, direction: TextDirection.rtl));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(rtl.heard, [
        (ValueCommand.decrease, ActivationSource.keyboard),
        (ValueCommand.increase, ActivationSource.keyboard),
      ]);
      expect(haptics, isEmpty);
    });

    testWidgets('an app overrides a command with Actions', (tester) async {
      final heard = _Value();
      final overridden = <ValueCommand>[];
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => Actions(
            actions: {
              AdjustValueIntent: CallbackAction<AdjustValueIntent>(
                onInvoke: (intent) => overridden.add(intent.command),
              ),
            },
            child: Center(
              child: InputRegion(
                interactions: [heard],
                autofocus: true,
                child: const SizedBox(width: 120, height: 30),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(heard.heard, isEmpty);
      expect(overridden, [ValueCommand.toMaximum]);
    });

    testWidgets('accessibility increases and decreases with exact '
        'semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      final interaction = _Value();
      await tester.pumpWidget(value(interaction, haptic: .lightImpact));
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(InputRegion)),
        matchesSemantics(
          label: 'level',
          textDirection: TextDirection.ltr,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          isFocused: true,
          hasFocusAction: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      tester.semantics.increase(find.semantics.byLabel('level'));
      tester.semantics.decrease(find.semantics.byLabel('level'));
      expect(interaction.heard, [
        (ValueCommand.increase, ActivationSource.accessibility),
        (ValueCommand.decrease, ActivationSource.accessibility),
      ]);
      expect(haptics, isEmpty);
      await tester.pumpWidget(value(_Value(), enabled: false));
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(InputRegion)),
        matchesSemantics(
          label: 'level',
          textDirection: TextDirection.ltr,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('focus', () {
    String? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<InputRegion>()
        ?.semanticLabel;

    testWidgets('Tab skips a region that takes no key unless it was given '
        'a focus node', (tester) async {
      final given = FocusNode();
      addTearDown(given.dispose);
      Widget region(String label, Interaction interaction, [FocusNode? n]) =>
          InputRegion(
            interactions: [interaction],
            semanticLabel: label,
            focusNode: n,
            child: const SizedBox(width: 40, height: 40),
          );
      await tester.pumpWidget(
        _widgetsApp(
          FocusScope(
            autofocus: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                region('press', PressInteraction()),
                region('drag', DragInteraction()),
                region('value', _Value()),
                region('given', DragInteraction(), given),
              ],
            ),
          ),
        ),
      );
      final order = <String?>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        order.add(focused());
      }
      expect(order, ['press', 'value', 'given']);
    });

    testWidgets('the focused state shows only in keyboard mode', (
      tester,
    ) async {
      final states = WidgetStatesController();
      addTearDown(states.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _widgetsApp(
          InputRegion(
            interactions: [PressInteraction()],
            statesController: states,
            focusNode: focus,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      );
      await tester.tap(find.byType(InputRegion));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(states.value, isNot(contains(WidgetState.focused)));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      expect(states.value, contains(WidgetState.focused));
      await tester.tap(find.byType(InputRegion));
      expect(focus.hasPrimaryFocus, isTrue);
      expect(states.value, isNot(contains(WidgetState.focused)));
    });
  });
}

final class _Value extends Interaction {
  final List<(ValueCommand, ActivationSource)> heard = [];

  @override
  bool get adjusts => true;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) heard.add((input.command, input.source));
    return InteractionUpdate.none;
  }
}

final class _Held extends Interaction {
  _Held() : super(role: InteractionRole.control);

  int? _pointer;

  @override
  bool get pressed => _pointer != null;

  @override
  bool get dragged => _pointer != null;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        _pointer = input.pointer;
        return const InteractionUpdate(claims: true);
      case PointerUpInput() || PointerCancelInput():
        _pointer = null;
        return const InteractionUpdate(recognizes: true);
      default:
        return InteractionUpdate.none;
    }
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.haptic,
    this.statesController,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final MotionHaptic? haptic;
  final WidgetStatesController? statesController;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  late final List<Interaction> _interactions = [
    if (widget.onLongPress != null)
      LongPressInteraction(onStart: (t) => widget.onLongPress?.call()),
    PressInteraction(onTap: (t) => widget.onPressed?.call()),
  ];

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _interactions,
    enabled: widget.onPressed != null,
    statesController: widget.statesController,
    feedback: (event) => event is ActivationEvent ? widget.haptic : null,
    child: widget.child,
  );
}
