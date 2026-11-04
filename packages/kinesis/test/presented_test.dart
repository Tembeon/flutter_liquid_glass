import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

final class _Card extends Motion with Presented, Sourced {
  late final Presence _show = own(Presence(openSpring: Spring.snappy));
  final List<DismissTrigger> left = [];
  final List<SourceGeometry?> sources = [];

  @override
  PresenceStatus get presence => _show.status;

  @override
  void open(double t) => _show.open(t);

  @override
  bool leave(double t, DismissTrigger trigger) {
    left.add(trigger);
    _show.hide(t);
    return true;
  }

  @override
  void sourceMoved(double t, SourceGeometry? geometry) => sources.add(geometry);
}

const _contentKey = ValueKey('content');

Presentation<String, _Card> _presentation(
  List<_Card> made, {
  DismissPolicy dismiss = const DismissPolicy(),
  MotionSource? source,
  bool modal = true,
  List<DismissTrigger>? vetoes,
  List<String?>? dismissed,
}) => Presentation<String, _Card>(
  motion: (_) {
    final card = _Card();
    made.add(card);
    return card;
  },
  builder: (context, motion) => Center(
    child: GestureDetector(
      key: _contentKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => PresentationHandle.of(
        context,
      ).dismiss(DismissTrigger.programmatic, 'tapped'),
      child: const SizedBox(width: 100, height: 100),
    ),
  ),
  source: source,
  dismiss: dismiss,
  modal: modal ? null : (_) => false,
  onVeto: vetoes?.add,
  onDismissed: dismissed?.add,
  semanticsLabel: 'Panel',
);

/// One way to show a [Presentation]: a popup route, a page route or a
/// portal.
abstract class _Shell {
  String get name;

  /// Pumps an app whose page shows [page], ready to [present].
  Future<void> pump(WidgetTester tester, Widget page);

  Future<void> present(
    WidgetTester tester,
    Presentation<String, _Card> presentation,
  );

  bool get isPresented;

  /// What the presentation completed with, for the routes.
  String? get result;
}

Widget _app(Widget home, {GlobalKey<NavigatorState>? key}) => WidgetsApp(
  navigatorKey: key,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (c, _, _) => builder(c),
  ),
  home: home,
);

final class _RouteShell extends _Shell {
  _RouteShell({required this.page});

  final bool page;
  final GlobalKey<NavigatorState> _nav = GlobalKey();
  PresentationRoute<String>? _route;
  PresentationPageRoute<String>? _page;
  @override
  String? result;

  @override
  String get name => page ? 'page route' : 'popup route';

  @override
  Future<void> pump(WidgetTester tester, Widget page) =>
      tester.pumpWidget(_app(page, key: _nav));

  @override
  Future<void> present(
    WidgetTester tester,
    Presentation<String, _Card> presentation,
  ) async {
    final Future<String?> done;
    if (page) {
      final route = _page = PresentationPageRoute(presentation: presentation);
      done = _nav.currentState!.push(route);
    } else {
      final route = _route = PresentationRoute(presentation: presentation);
      done = showPresentation(_nav.currentContext!, route);
    }
    unawaited(done.then((r) => result = r));
  }

  @override
  bool get isPresented =>
      (_page?.isCurrent ?? false) ||
      (_route?.isActive ?? false) ||
      (_page?.isActive ?? false);
}

final class _PortalShell extends _Shell {
  final PresentationPortalController controller =
      PresentationPortalController();
  final ValueNotifier<Presentation<String, _Card>?> _shown = ValueNotifier(
    null,
  );

  @override
  String get name => 'portal';

  @override
  String? get result => null;

  @override
  Future<void> pump(WidgetTester tester, Widget page) => tester.pumpWidget(
    _app(
      ValueListenableBuilder(
        valueListenable: _shown,
        builder: (context, presentation, child) => PresentationPortal(
          controller: controller,
          presentation: presentation ?? _presentation([]),
          child: child!,
        ),
        child: page,
      ),
    ),
  );

  @override
  Future<void> present(
    WidgetTester tester,
    Presentation<String, _Card> presentation,
  ) async {
    _shown.value = presentation;
    await tester.pump();
    controller.present();
  }

  @override
  bool get isPresented => controller.isPresented;
}

final List<_Shell Function()> _shells = [
  () => _RouteShell(page: false),
  () => _RouteShell(page: true),
  _PortalShell.new,
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

SemanticsNode? _node(WidgetTester tester, String label) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    if (node.label == label) found = node;
    node.visitChildren(visit);
    return found == null;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return found;
}

void main() {
  setUp(MotionClock.debugReset);

  for (final make in _shells) {
    final name = make().name;

    group(name, () {
      testWidgets('opens at the commit and goes once its leave ends', (
        tester,
      ) async {
        final shell = make();
        final made = <_Card>[];
        final dismissed = <String?>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation(made, dismissed: dismissed),
        );
        await tester.pump();
        await tester.pump();
        expect(made, hasLength(1));
        expect(made.single.presence, PresenceStatus.opening);
        expect(find.byKey(_contentKey), findsOneWidget);
        await _settle(tester);
        expect(made.single.presence, PresenceStatus.shown);
        await tester.tap(find.byKey(_contentKey));
        await tester.pump();
        expect(made.single.left, [DismissTrigger.programmatic]);
        expect(find.byKey(_contentKey), findsOneWidget);
        expect(dismissed, isEmpty);
        await _settle(tester);
        expect(dismissed, ['tapped']);
        expect(find.byKey(_contentKey), findsNothing);
        expect(shell.isPresented, isFalse);
        if (shell is _RouteShell) expect(shell.result, 'tapped');
      });

      testWidgets('Escape and Back dismiss only as the policy lets them', (
        tester,
      ) async {
        final shell = make();
        final made = <_Card>[];
        final vetoes = <DismissTrigger>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation(
            made,
            vetoes: vetoes,
            dismiss: const DismissPolicy({DismissTrigger.back}),
          ),
        );
        await tester.pump();
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(made.single.left, isEmpty);
        final handle = PresentationHandle.of(
          tester.element(find.byKey(_contentKey)),
        );
        expect(handle.canDismiss(DismissTrigger.escape), isFalse);
        expect(handle.canDismiss(DismissTrigger.back), isTrue);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(made.single.left, [DismissTrigger.back]);
        expect(handle.canDismiss(DismissTrigger.programmatic), isFalse);
        await _settle(tester);
        expect(shell.isPresented, isFalse);
      });

      testWidgets('the screen reader dismisses it by its name', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        final made = <_Card>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(tester, _presentation(made));
        await tester.pump();
        await _settle(tester);
        final node = _node(tester, 'Panel');
        expect(node, isNotNull);
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          node!.id,
          SemanticsAction.dismiss,
        );
        await tester.pump();
        expect(made.single.left, [DismissTrigger.accessibility]);
        semantics.dispose();
      });

      testWidgets('hides its source in the commit frame, follows it and '
          'shows it again once gone', (tester) async {
        final shell = make();
        final made = <_Card>[];
        final source = MotionSource();
        final scroll = ScrollController();
        final shown = ValueNotifier(true);
        var taps = 0;
        await shell.pump(
          tester,
          ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 40),
              ValueListenableBuilder(
                valueListenable: shown,
                builder: (context, show, _) => show
                    ? MotionSourceBox(
                        source: source,
                        child: GestureDetector(
                          onTap: () => taps++,
                          child: const ColoredBox(
                            color: Color(0xFF00FF00),
                            child: SizedBox(height: 50),
                          ),
                        ),
                      )
                    : const SizedBox(height: 50),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        );
        final box = find.byType(MotionSourceBox);
        expect(tester.renderObject(box), isNot(paintsNothing));
        await shell.present(
          tester,
          _presentation(made, source: source, modal: false),
        );
        await tester.pump();
        await tester.pump();
        expect(source.isHidden, isTrue);
        expect(tester.renderObject(box), paintsNothing);
        final card = made.single;
        expect(card.sources.first?.rect.top, 40);

        if (shell is! _RouteShell || !shell.page) {
          await tester.tapAt(const Offset(10, 60));
          expect(taps, 1);
        }

        scroll.jumpTo(30);
        await tester.pump();
        expect(card.sources.last?.rect.top, 10);

        shown.value = false;
        await tester.pump();
        expect(card.sources.last, isNull);

        shown.value = true;
        await tester.pump();
        PresentationHandle.of(
          tester.element(find.byKey(_contentKey)),
        ).dismiss(DismissTrigger.programmatic);
        await _settle(tester);
        expect(source.isHidden, isFalse);
        expect(tester.renderObject(box), isNot(paintsNothing));
      });
    });
  }

  group('portal', () {
    testWidgets('the touch that presents it is not cancelled', (tester) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      final events = <String>[];
      await shell.pump(
        tester,
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => events.add('down'),
          onPointerMove: (_) => events.add('move'),
          onPointerUp: (_) => events.add('up'),
          onPointerCancel: (_) => events.add('cancel'),
          child: const SizedBox.expand(),
        ),
      );
      final gesture = await tester.startGesture(const Offset(20, 20));
      await shell.present(tester, _presentation(made));
      await tester.pump();
      await tester.pump();
      expect(shell.isPresented, isTrue);
      await gesture.moveBy(const Offset(0, 10));
      await gesture.up();
      expect(events, ['down', 'move', 'up']);
    });

    testWidgets('takes the focus and gives it back', (tester) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      final field = FocusNode();
      await shell.pump(
        tester,
        Focus(focusNode: field, autofocus: true, child: const SizedBox()),
      );
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      await shell.present(tester, _presentation(made));
      await tester.pump();
      await tester.pump();
      expect(field.hasFocus, isFalse);
      shell.controller.dismiss(DismissTrigger.programmatic);
      await _settle(tester);
      expect(field.hasPrimaryFocus, isTrue);
      field.dispose();
    });
  });
}
