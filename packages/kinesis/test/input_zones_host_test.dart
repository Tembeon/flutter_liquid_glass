import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// Follows one finger over a menu's rows, as a menu does that stretches
/// after a finger beyond its edge: which row is under it now, where it is
/// in the host, and the stamp.
class _Finger extends Interaction {
  _Finger(this.zones);

  final InputZonesController<int> zones;
  final List<(String, int?, Offset)> heard = [];
  final List<double> times = [];

  void _hear(String phase, InteractionInput input, Offset position) {
    heard.add((phase, zones.zoneAt(position), position));
    times.add(input.time);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput(:final position):
        _hear('down', input, position);
        return const InteractionUpdate(claims: true);
      case PointerMoveInput(:final position):
        _hear('move', input, position);
      case PointerUpInput(:final position):
        _hear('up', input, position);
      case PointerCancelInput():
        heard.add(('cancel', null, Offset.zero));
      default:
    }
    return InteractionUpdate.none;
  }
}

/// Three rows of 40 points, one under the other, in a 100 point wide menu
/// at (50, 50).
class _Menu extends StatelessWidget {
  const _Menu({
    required this.zones,
    required this.finger,
    required this.frames,
    this.port,
    this.rowTaps,
  });

  final InputZonesController<int> zones;
  final _Finger finger;
  final Listenable frames;
  final InputPort? port;
  final List<int>? rowTaps;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 50,
    top: 50,
    child: InputZones<int>(
      zones: [
        for (var i = 0; i < 3; i++)
          InputZone(
            id: i,
            interactions: [PressInteraction(onTap: (t) => rowTaps?.add(i))],
          ),
      ],
      frameOf: (id) => InputZoneFrame(Rect.fromLTWH(0, id * 40.0, 100, 40)),
      frames: frames,
      controller: zones,
      interactions: [finger],
      port: port,
      child: const SizedBox(width: 100, height: 120),
    ),
  );
}

Widget _screen(List<Widget> children) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(children: children),
);

void main() {
  setUp(MotionClock.debugReset);

  late InputZonesController<int> zones;
  late ValueNotifier<int> frames;

  setUp(() {
    zones = InputZonesController<int>();
    frames = ValueNotifier(0);
  });

  tearDown(() {
    zones.dispose();
    frames.dispose();
  });

  testWidgets('a host interaction follows one finger from a row across two '
      'more, beyond the host and back, to its release', (tester) async {
    final finger = _Finger(zones);
    await tester.pumpWidget(
      _screen([_Menu(zones: zones, finger: finger, frames: frames)]),
    );
    final gesture = await tester.startGesture(const Offset(100, 70));
    for (final to in const [
      Offset(100, 110),
      Offset(100, 150),
      Offset(100, 230),
      Offset(170, 230),
      Offset(100, 155),
    ]) {
      await gesture.moveTo(to);
      await tester.pump();
    }
    await gesture.up();
    expect(finger.heard, [
      ('down', 0, const Offset(50, 20)),
      ('move', 1, const Offset(50, 60)),
      ('move', 2, const Offset(50, 100)),
      ('move', null, const Offset(50, 180)),
      ('move', null, const Offset(120, 180)),
      ('move', 2, const Offset(50, 105)),
      ('up', 2, const Offset(50, 105)),
    ]);
    for (var i = 1; i < finger.times.length; i++) {
      expect(finger.times[i], greaterThanOrEqualTo(finger.times[i - 1]));
    }
  });

  testWidgets('a touch between the zones and outside them reaches the host, '
      'and a zone under the finger still presses beside it', (tester) async {
    final finger = _Finger(zones);
    final taps = <int>[];
    await tester.pumpWidget(
      _screen([
        _Menu(zones: zones, finger: finger, frames: frames, rowTaps: taps),
      ]),
    );
    await tester.tapAt(const Offset(100, 115));
    expect(taps, [1]);
    expect(finger.heard.first, ('down', 1, const Offset(50, 65)));
    expect(finger.heard.last.$1, 'up');
  });

  testWidgets('the finger that opened the menu arrives through the port on no '
      'zone and slides onto the rows', (tester) async {
    final finger = _Finger(zones);
    final port = InputPort();
    await tester.pumpWidget(
      _screen([
        Positioned(
          left: 0,
          top: 0,
          child: InputRegion(
            interactions: [port.forward],
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
        _Menu(zones: zones, finger: finger, frames: frames, port: port),
      ]),
    );
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(20, 20));
    await gesture.moveTo(const Offset(100, 60));
    await gesture.moveTo(const Offset(100, 100));
    await gesture.up();
    expect(finger.heard, [
      ('down', null, const Offset(-30, -30)),
      ('move', 0, const Offset(50, 10)),
      ('move', 1, const Offset(50, 50)),
      ('up', 1, const Offset(50, 50)),
    ]);
  });

  testWidgets('zoneAt answers no zone for a disabled row or without a host', (
    tester,
  ) async {
    expect(zones.zoneAt(const Offset(10, 10)), isNull);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: InputZones<int>(
            zones: const [
              InputZone(id: 0),
              InputZone(id: 1, enabled: false),
            ],
            frameOf: (id) =>
                InputZoneFrame(Rect.fromLTWH(id * 50.0, 0, 50, 40)),
            frames: frames,
            controller: zones,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );
    expect(zones.zoneAt(const Offset(10, 10)), 0);
    expect(zones.zoneAt(const Offset(60, 10)), isNull);
    expect(zones.zoneAt(const Offset(10, 60)), isNull);
  });
}
