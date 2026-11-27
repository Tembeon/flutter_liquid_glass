import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

final class _Card extends Motion with Presented {
  _Card({super.clock});

  late final Presence _show = own(Presence(openSpring: Spring.snappy));
  double? opened;
  bool? reducedAtOpen;
  double? left;

  @override
  PresenceStatus get presence => _show.status;

  @override
  void open(double t) {
    opened = t;
    reducedAtOpen = traits.reduceMotion;
    _show.open(t);
  }

  @override
  bool leave(double t) {
    left = t;
    _show.leave(t);
    return true;
  }
}

Future<PresentationPortalController> _pumpPortal(
  WidgetTester tester, {
  required MotionClock clock,
  required _Card Function(PresentationEnvironment environment) motion,
  MotionTraits traits = const MotionTraits(),
}) async {
  final controller = PresentationPortalController();
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: MotionClockScope(
        clock: clock,
        child: MotionTraitsOverride(
          traits: traits,
          child: PresentationPortal(
            controller: controller,
            presentation: Presentation<void, _Card>(
              motion: motion,
              builder: (context, motion) => const SizedBox.expand(),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a portal under a clock scope commits, opens and leaves on '
      'that clock', (tester) async {
    final clock = ManualMotionClock(start: 5);
    final cards = <_Card>[];
    final environments = <PresentationEnvironment>[];
    final controller = await _pumpPortal(
      tester,
      clock: clock,
      motion: (environment) {
        environments.add(environment);
        final card = _Card(clock: environment.clock);
        cards.add(card);
        return card;
      },
    );
    controller.present();
    await tester.pump();
    expect(environments.single.clock, same(clock));
    expect(environments.single.time, 5);
    expect(cards.single.opened, 5);

    clock.advanceTo(6);
    controller.dismiss(DismissTrigger.programmatic);
    expect(cards.single.left, 6);
    clock.advanceTo(8);
    await tester.pump();
    expect(controller.isPresented, isFalse);
  });

  testWidgets('the commit gives the motion the traits of the place before '
      'it opens', (tester) async {
    final cards = <_Card>[];
    final controller = await _pumpPortal(
      tester,
      clock: ManualMotionClock(),
      traits: const MotionTraits(reduceMotion: true),
      motion: (environment) {
        final card = _Card(clock: environment.clock);
        cards.add(card);
        return card;
      },
    );
    controller.present();
    expect(cards.single.reducedAtOpen, isTrue);
  });

  testWidgets('a motion off the clock of the place fails the commit', (
    tester,
  ) async {
    final controller = await _pumpPortal(
      tester,
      clock: ManualMotionClock(),
      motion: (_) => _Card(),
    );
    expect(controller.present, throwsAssertionError);
  });
}
