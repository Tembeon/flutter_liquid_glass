import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// Follows the touch on the host whole, claiming it at the down, as a
/// menu's stretch does.
class _Host extends Interaction {
  final List<String> heard = [];

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        heard.add('down');
        return const InteractionUpdate(claims: true);
      case PointerUpInput():
        heard.add('up');
      default:
    }
    return InteractionUpdate.none;
  }
}

/// Writes the downs a row hears: their stamp, their contact and the scroll
/// views around them.
class _Downs extends Interaction {
  _Downs() : super(role: InteractionRole.observer);

  final List<PointerDownInput> downs = [];

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput) downs.add(input);
    return InteractionUpdate.none;
  }
}

/// Three sliding rows of 100 x 40, [gap] apart at the top of each 40
/// point band, in a menu at (50, 50), whose host follows the touch.
class _Rows extends StatefulWidget {
  const _Rows({
    required this.zones,
    required this.taps,
    this.gap = 0,
    this.zoneAt,
    this.slidesFrom,
    this.extra = const {},
  });

  final InputZonesController<int> zones;
  final List<int> taps;
  final double gap;
  final int? Function(Offset position)? zoneAt;
  final bool Function(Offset position)? slidesFrom;
  final Map<int, List<Interaction>> extra;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  late final _rows = {
    for (var i = 0; i < 3; i++)
      i: [
        PressInteraction(onTap: (t) => widget.taps.add(i)),
        ...?widget.extra[i],
      ],
  };
  final _host = _Host();
  final _frames = ValueNotifier(0);

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: Stack(
      children: [
        Positioned(
          left: 50,
          top: 50,
          child: InputZones<int>(
            zones: [
              for (var i = 0; i < 3; i++)
                InputZone(id: i, interactions: _rows[i]!),
            ],
            frameOf: (id) => InputZoneFrame(
              Rect.fromLTWH(0, id * 40.0 + widget.gap, 100, 40 - widget.gap),
            ),
            frames: _frames,
            controller: widget.zones,
            slides: true,
            slidesFrom: widget.slidesFrom,
            zoneAt: widget.zoneAt,
            interactions: [_host],
            child: const SizedBox(width: 100, height: 120),
          ),
        ),
      ],
    ),
  );
}

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

/// The centre of row [row] in a menu at (50, 50).
Offset _row(int row) => Offset(100, 50 + row * 40.0 + 20);

void main() {
  setUp(MotionClock.debugReset);

  late InputZonesController<int> zones;
  late List<int> taps;

  setUp(() {
    zones = InputZonesController<int>();
    taps = [];
  });

  tearDown(() => zones.dispose());

  bool pressed(int row) =>
      zones.states(row).value.contains(WidgetState.pressed);

  testWidgets('a touch that lands between the rows slides onto none, and one '
      'that lands on a row slides across them', (tester) async {
    await tester.pumpWidget(
      _app(_Rows(zones: zones, taps: taps, gap: 8)),
    );
    final between = await tester.startGesture(const Offset(100, 54));
    await between.moveTo(_row(1));
    await tester.pump();
    expect(pressed(1), isFalse);
    await between.up();
    expect(taps, isEmpty);

    final on = await tester.startGesture(_row(0));
    await on.moveTo(_row(1));
    await tester.pump();
    expect(pressed(1), isTrue);
    await on.up();
    expect(taps, [1]);
  });

  testWidgets('a touch that lands between the rows where the control says '
      'slides onto them', (tester) async {
    await tester.pumpWidget(
      _app(
        _Rows(
          zones: zones,
          taps: taps,
          gap: 8,
          slidesFrom: (position) => position.dy < 8,
        ),
      ),
    );
    final finger = await tester.startGesture(const Offset(100, 54));
    await finger.moveTo(_row(1));
    await tester.pump();
    expect(pressed(1), isTrue);
    await finger.up();
    expect(taps, [1]);
  });

  testWidgets('a row whose interactions change under the finger ends its '
      'touch, and the next move comes onto it afresh', (tester) async {
    final first = _Downs();
    final second = _Downs();
    var row = <Interaction>[first];
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SizedBox(
              height: 300,
              child: Stack(
                children: [
                  Positioned(
                    left: 50,
                    top: 50,
                    child: InputZones<int>(
                      zones: [InputZone(id: 0, interactions: row)],
                      frameOf: (id) =>
                          const InputZoneFrame(Rect.fromLTWH(0, 0, 100, 40)),
                      frames: const AlwaysStoppedAnimation(0),
                      controller: zones,
                      slides: true,
                      child: const SizedBox(width: 100, height: 40),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    final finger = await tester.startGesture(_row(0));
    await tester.pump();
    expect(first.downs, hasLength(1));
    rebuild(() => row = [second]);
    await tester.pump();
    expect(second.downs, isEmpty);
    await finger.moveTo(_row(0).translate(2, 0));
    await tester.pump();
    expect(second.downs, hasLength(1));
    await finger.up();
  });

  testWidgets('a scroll view that takes the finger ends the wait of a dwell '
      'on the row it started on', (tester) async {
    var dwelt = 0;
    final dwell = DwellInteraction(
      duration: 0.5,
      hovers: false,
      onDwell: (t) => dwelt++,
    );
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 200,
          height: 300,
          child: InputZones<int>(
            zones: [
              InputZone(
                id: 0,
                interactions: [
                  PressInteraction(role: InteractionRole.content),
                  dwell,
                ],
              ),
            ],
            frameOf: (id) =>
                const InputZoneFrame(Rect.fromLTWH(0, 0, 200, 300)),
            frames: const AlwaysStoppedAnimation(0),
            controller: zones,
            slides: true,
            child: ListView(
              children: const [SizedBox(height: 1000)],
            ),
          ),
        ),
      ),
    );
    final still = await tester.startGesture(const Offset(100, 100));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(dwelt, 1);
    await still.up();

    final drag = await tester.startGesture(const Offset(100, 200));
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset(100, 200 - 8.0 * i));
      await tester.pump(const Duration(milliseconds: 10));
    }
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(dwelt, 1);
    await drag.up();
  });

  testWidgets('a finger over no row leaves the row it was on and comes back '
      'onto another', (tester) async {
    await tester.pumpWidget(
      _app(_Rows(zones: zones, taps: taps, gap: 8)),
    );
    final finger = await tester.startGesture(_row(0));
    await tester.pump();
    expect(pressed(0), isTrue);
    await finger.moveTo(const Offset(100, 94));
    await tester.pump();
    expect(pressed(0), isFalse);
    await finger.moveTo(const Offset(100, 250));
    await finger.moveTo(_row(2));
    await tester.pump();
    expect(pressed(2), isTrue);
    await finger.up();
    expect(taps, [2]);
  });

  testWidgets('a row the finger slides onto hears a fresh contact there, '
      'held back by no scroll view', (tester) async {
    final downs = _Downs();
    var held = 0;
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 400,
          child: ListView(
            children: [
              _Rows(
                zones: zones,
                taps: taps,
                extra: {
                  1: [
                    downs,
                    LongPressInteraction(onStart: (t) => held++),
                  ],
                },
              ),
            ],
          ),
        ),
      ),
    );
    final finger = await tester.startGesture(_row(0));
    await tester.pump(const Duration(seconds: 1));
    await finger.moveTo(_row(1));
    await tester.pump();
    expect(pressed(1), isTrue);
    final down = downs.downs.single;
    expect(down.contactTime, down.time);
    expect(down.scrollAxes, isEmpty);
    expect(held, 0);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(held, 1);
    await finger.up();
  });

  testWidgets('one touch at a time slides: a second finger reaches no row', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Rows(zones: zones, taps: taps)));
    final first = await tester.startGesture(_row(0), pointer: 1);
    final second = await tester.startGesture(_row(2), pointer: 2);
    await tester.pump();
    expect(pressed(2), isFalse);
    await first.moveTo(_row(1));
    await tester.pump();
    expect(pressed(1), isTrue);
    await second.up();
    await first.up();
    expect(taps, [1]);
  });

  testWidgets("the control's hit answer decides the row under the finger, "
      'and the row holds the finger wherever the answer names it', (
    tester,
  ) async {
    int? answer(Offset position) => switch (position.dy) {
      >= 0 && < 60 => 0,
      >= 60 && < 120 => 2,
      _ => null,
    };
    await tester.pumpWidget(
      _app(_Rows(zones: zones, taps: taps, zoneAt: answer)),
    );
    expect(zones.zoneAt(const Offset(50, 70)), 2);
    final finger = await tester.startGesture(_row(1));
    await tester.pump();
    expect(pressed(2), isTrue);
    expect(pressed(1), isFalse);
    await finger.moveTo(const Offset(100, 105));
    await tester.pump();
    expect(pressed(0), isTrue);
    await finger.up();
    expect(taps, [0]);
  });
}
