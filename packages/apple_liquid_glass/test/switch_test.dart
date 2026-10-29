import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  Widget child, {
  GlassRenderer renderer = const GlassRenderer.flat(),
  GlassThemeData theme = const GlassThemeData(),
  TextDirection direction = TextDirection.ltr,
  bool disableAnimations = false,
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(
    textDirection: direction,
    child: GlassTheme(
      data: theme.merge(GlassThemeData(renderer: renderer)),
      child: Center(child: child),
    ),
  ),
);

class _Controlled extends StatefulWidget {
  const _Controlled({this.onChanged});

  final ValueChanged<bool>? onChanged;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  bool value = false;

  @override
  Widget build(BuildContext context) => GlassSwitch(
    value: value,
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => value = next);
    },
  );
}

class _Probe {
  int builds = 0;
  ValueListenable<GlassFrame>? thumb;
  ValueListenable<double>? progress;
  Set<WidgetState> states = {};

  Widget build(BuildContext context, GlassSwitchDetails details) {
    builds++;
    thumb = details.thumb;
    progress = details.progress;
    states = details.states;
    return const SizedBox.expand();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap toggles on release, and the track turns on', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: changes.add)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    await tester.pump(_frame);
    expect(changes, isEmpty);
    await gesture.up();
    await tester.pump(_frame);
    expect(changes, [true]);
    await _settle(tester);
    final track = tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .first
        .frame!
        .value
        .tint!;
    expect(track, isSameColorAs(const Color(0xFF34C759)));
  });

  testWidgets('a switch whose value does not follow returns to it', (
    tester,
  ) async {
    final probe = _Probe();
    var value = false;
    await tester.pumpWidget(
      _app(
        RawGlassSwitch(
          value: value,
          onChanged: (next) => value = next,
          builder: probe.build,
        ),
      ),
    );
    await tester.tap(find.byType(RawGlassSwitch));
    await _settle(tester);
    expect(value, isTrue);
    expect(probe.progress!.value, 0);
    expect(probe.thumb!.value.rect!.center.dx, lessThan(31.5));
  });

  testWidgets('a drag toward on flips it and the release keeps it', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(_app(_Controlled(onChanged: changes.add)));
    final start =
        tester.getTopLeft(find.byType(GlassSwitch)) + const Offset(20, 14);
    final gesture = await tester.startGesture(start);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(4.0 * i, 0));
      await tester.pump(_frame);
    }
    await gesture.up();
    await tester.pump(_frame);
    expect(changes, [true]);
    await _settle(tester);
  });

  testWidgets('without onChanged it is disabled, dim and ignores touches', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const GlassSwitch(value: false, onChanged: null)),
    );
    await tester.tap(find.byType(GlassSwitch));
    await _settle(tester);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      0.5,
    );
  });

  testWidgets('keys and the accessibility tap toggle; it reads as a '
      'toggle', (tester) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final changes = <bool>[];
    await tester.pumpWidget(
      _app(
        GlassSwitch(
          value: false,
          onChanged: changes.add,
          focusNode: focus,
          semanticLabel: 'Wi-Fi',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wi-Fi')),
      matchesSemantics(
        label: 'Wi-Fi',
        hasToggledState: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    tester.semantics.tap(find.semantics.byLabel('Wi-Fi'));
    expect(changes, [true, true]);
    semantics.dispose();
  });

  testWidgets('the builder runs on state edges only while the knob lifts '
      'and travels', (tester) async {
    final probe = _Probe();
    var value = false;
    late StateSetter set;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RawGlassSwitch(
              value: value,
              onChanged: (next) => set(() => value = next),
              builder: probe.build,
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
    final lifts = <double>[];
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
      lifts.add(probe.thumb!.value.lift);
    }
    final pressed = probe.builds;
    expect(lifts.last, greaterThan(0.9));
    await gesture.up();
    final xs = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(_frame);
      xs.add(probe.thumb!.value.rect!.center.dx);
    }
    expect(xs.last, greaterThan(xs.first));
    expect(probe.states, contains(WidgetState.selected));
    expect(probe.builds - pressed, lessThanOrEqualTo(2));
    await _settle(tester);
  });

  testWidgets('right to left, on is to the left', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassSwitch(value: true, onChanged: (_) {}, builder: probe.build),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump(_frame);
    expect(probe.thumb!.value.rect!.center.dx, lessThan(31.5));
  });

  testWidgets('on liquid glass the knob gets a glass layer only while '
      'lifted', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const GlassRenderer.liquid()),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(find.byType(LiquidGlassLayer), findsNothing);
  });

  testWidgets('the theme styles the track; Reduce Motion keeps the knob '
      'down', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        RawGlassSwitch(value: false, onChanged: (_) {}, builder: probe.build),
        disableAnimations: true,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
    }
    expect(probe.thumb!.value.lift, 0);
    await gesture.up();
    await _settle(tester);

    await tester.pumpWidget(
      _app(
        const GlassSwitch(value: true, onChanged: null),
        theme: GlassThemeData(
          switchStyle: GlassSwitch.styleFrom(
            activeTrackColor: const Color(0xFF123456),
          ),
        ),
      ),
    );
    await _settle(tester);
    final track = tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .first
        .frame!
        .value
        .tint!;
    expect(track, isSameColorAs(const Color(0xFF123456)));
  });

  testWidgets('disabling a switch under a finger ends the press quietly', (
    tester,
  ) async {
    Widget sw(ValueChanged<bool>? onChanged) =>
        _app(GlassSwitch(value: false, onChanged: onChanged));
    await tester.pumpWidget(sw((_) {}));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    await tester.pump(_frame);
    await tester.pumpWidget(sw(null));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('on liquid glass the lifted knob covers its platter instead '
      'of fading it', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const GlassRenderer.liquid()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    final flat = find.byElementPredicate(
      (element) =>
          element is RenderObjectElement &&
          element.renderObject is RenderFlatGlass,
    );
    expect(flat, findsNWidgets(2));
    expect(
      find.descendant(of: find.byType(LiquidGlass), matching: flat),
      findsNothing,
    );
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a held knob on fake glass does not rebuild its layer every '
      'frame', (tester) async {
    await tester.pumpWidget(
      _app(const _Controlled(), renderer: const GlassRenderer.fake()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassSwitch)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }
    var layerBuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is LiquidGlassLayer) layerBuilds++;
    };
    for (var i = 0; i < 30; i++) {
      await tester.pump(_frame);
    }
    debugOnRebuildDirtyWidget = null;
    expect(layerBuilds, 0);
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('a switch in a larger box keeps its size and its knob', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 120,
          height: 50,
          child: GlassSwitch(value: false, onChanged: null),
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassSwitch)), const Size(120, 50));
    final knob = find.byType(GlassSurface).last;
    expect(tester.getSize(knob), RawGlassSwitch.size);
    expect(
      tester.getCenter(knob),
      tester.getCenter(find.byType(RawGlassSwitch)),
    );
  });
}
