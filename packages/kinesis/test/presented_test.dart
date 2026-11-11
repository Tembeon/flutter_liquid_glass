import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

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

  /// Leaves without being dismissed, as a menu does once a row is chosen.
  void leaveOnOwn(double t) => _show.hide(t);

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
  VoidCallback? onContentPointer,
  String? barrierLabel,
  FocusNode? focus,
  FocusNode? initialFocus,
  bool named = false,
  String? label = 'Panel',
  SemanticsRole? role,
}) => Presentation<String, _Card>(
  motion: (_) {
    final card = _Card();
    made.add(card);
    return card;
  },
  builder: (context, motion) => Center(
    child: Listener(
      onPointerDown: (_) => onContentPointer?.call(),
      onPointerMove: (_) => onContentPointer?.call(),
      child: GestureDetector(
        key: _contentKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => PresentationHandle.of(
          context,
        ).dismiss(DismissTrigger.programmatic, 'tapped'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              focusNode: focus,
              child: const SizedBox(width: 100, height: 50),
            ),
            Focus(
              focusNode: initialFocus,
              child: const SizedBox(width: 100, height: 50),
            ),
          ],
        ),
      ),
    ),
  ),
  source: source,
  dismiss: dismiss,
  modal: modal ? null : (_) => false,
  onVeto: vetoes?.add,
  onDismissed: dismissed?.add,
  semanticsLabel: label,
  semanticsRole: role,
  barrierLabel: barrierLabel,
  initialFocus: named ? initialFocus : null,
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

/// The labels of the semantics tree in the order a screen reader visits
/// them.
List<String> _readingOrder(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
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

      testWidgets('a motion that leaves on its own takes the presentation '
          'with it', (tester) async {
        final shell = make();
        final made = <_Card>[];
        final dismissed = <String?>[];
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation(
            made,
            dismissed: dismissed,
            dismiss: const DismissPolicy({}),
          ),
        );
        await tester.pump();
        await _settle(tester);
        made.single.leaveOnOwn(MotionClock.instance.now);
        await tester.pump();
        expect(made.single.left, [DismissTrigger.programmatic]);
        await _settle(tester);
        expect(dismissed, [null]);
        expect(find.byKey(_contentKey), findsNothing);
        expect(shell.isPresented, isFalse);
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

      testWidgets('the barrier hides what is below in a route and, '
          'labelled, offers the dismissal after the content', (tester) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        final made = <_Card>[];
        await shell.pump(
          tester,
          Semantics(label: 'Page below', child: const SizedBox.expand()),
        );
        expect(_readingOrder(tester), contains('Page below'));
        await shell.present(
          tester,
          _presentation(made, barrierLabel: 'Dismiss panel'),
        );
        await tester.pump();
        await _settle(tester);
        // A portal's content reads after its anchor, the page below.
        expect(_readingOrder(tester), [
          if (shell is _PortalShell) 'Page below',
          'Panel',
          'Dismiss panel',
        ]);
        final barrier = _node(tester, 'Dismiss panel')!.getSemanticsData();
        expect(barrier.hasAction(SemanticsAction.tap), isTrue);
        expect(barrier.hasAction(SemanticsAction.dismiss), isTrue);
        tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
          _node(tester, 'Dismiss panel')!.id,
          SemanticsAction.tap,
        );
        await tester.pump();
        expect(made.single.left, [DismissTrigger.outsideTap]);
        semantics.dispose();
      });

      testWidgets('the barrier is silent without a label, when an outside '
          'tap may not dismiss and where the platform has no such dismissal', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        for (final (label, policy, platform) in [
          (null, const DismissPolicy(), TargetPlatform.android),
          ('Dismiss panel', DismissPolicy.modal, TargetPlatform.iOS),
          ('Dismiss panel', const DismissPolicy(), TargetPlatform.linux),
          ('Dismiss panel', const DismissPolicy(), TargetPlatform.windows),
        ]) {
          debugDefaultTargetPlatformOverride = platform;
          final shell = make();
          final made = <_Card>[];
          await shell.pump(
            tester,
            Semantics(label: 'Page below', child: const SizedBox.expand()),
          );
          await shell.present(
            tester,
            _presentation(made, barrierLabel: label, dismiss: policy),
          );
          await tester.pump();
          await _settle(tester);
          expect(_readingOrder(tester), [
            if (shell is _PortalShell) 'Page below',
            'Panel',
          ], reason: '$platform');
          await tester.pumpWidget(const SizedBox());
        }
        debugDefaultTargetPlatformOverride = null;
        semantics.dispose();
      });

      testWidgets('is inert from the start of its leave: no new touch, no '
          'focus, no semantics', (tester) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        final made = <_Card>[];
        final focus = FocusNode();
        var below = 0;
        var onIt = 0;
        await shell.pump(
          tester,
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => below++,
            child: const SizedBox.expand(),
          ),
        );
        await shell.present(
          tester,
          _presentation(
            made,
            focus: focus,
            onContentPointer: () => onIt++,
          ),
        );
        await tester.pump();
        await _settle(tester);
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(_node(tester, 'Panel'), isNotNull);
        final center = tester.getCenter(find.byKey(_contentKey));
        await tester.tapAt(center);
        expect(onIt, 1);
        expect(below, 0);

        PresentationHandle.of(
          tester.element(find.byKey(_contentKey)),
        ).dismiss(DismissTrigger.outsideTap);
        await tester.tapAt(center);
        expect(onIt, 1, reason: 'no touch in the frame the leave started');
        // A navigator absorbs every touch in the frame of a pop.
        expect(below, shell is _PortalShell ? 1 : 0);
        await tester.pump(const Duration(milliseconds: 16));
        expect(made.single.presence, PresenceStatus.leaving);
        expect(find.byKey(_contentKey), findsOneWidget);
        expect(focus.hasFocus, isFalse);
        expect(focus.canRequestFocus, isFalse);
        expect(_node(tester, 'Panel'), isNull);
        await tester.tapAt(center);
        expect(onIt, 1);
        expect(below, shell is _PortalShell ? 2 : 1);
        await _settle(tester);
        focus.dispose();
        semantics.dispose();
      });

      testWidgets('the focus moves in at the open: to the named node, to '
          'the first focusable one with the keyboard, to itself on touch', (
        tester,
      ) async {
        for (final keyboard in [false, true]) {
          for (final named in [false, true]) {
            FocusManager.instance.highlightStrategy = keyboard
                ? FocusHighlightStrategy.alwaysTraditional
                : FocusHighlightStrategy.alwaysTouch;
            final shell = make();
            final first = FocusNode();
            final second = FocusNode();
            await shell.pump(tester, const SizedBox.expand());
            await shell.present(
              tester,
              _presentation(
                [],
                focus: first,
                initialFocus: second,
                named: named,
              ),
            );
            await tester.pump();
            await tester.pump();
            final reason = 'keyboard $keyboard, named $named';
            if (named) {
              expect(second.hasPrimaryFocus, isTrue, reason: reason);
            } else if (keyboard) {
              expect(first.hasPrimaryFocus, isTrue, reason: reason);
            } else {
              expect(first.hasFocus || second.hasFocus, isFalse);
              expect(
                FocusManager.instance.primaryFocus?.debugLabel,
                'Presentation',
                reason: reason,
              );
            }
            await tester.pumpWidget(const SizedBox());
            first.dispose();
            second.dispose();
          }
        }
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
      });

      testWidgets('Tab cycles inside a modal presentation', (tester) async {
        final shell = make();
        final first = FocusNode();
        final second = FocusNode();
        final outside = FocusNode();
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        await shell.pump(
          tester,
          Focus(focusNode: outside, child: const SizedBox.expand()),
        );
        await shell.present(
          tester,
          _presentation([], focus: first, initialFocus: second),
        );
        await tester.pump();
        await tester.pump();
        expect(first.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(second.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        if (shell is _RouteShell && shell.page) {
          // A page keeps its navigator's edge behaviour, as page routes do.
          expect(outside.hasFocus, isFalse);
        } else {
          expect(first.hasPrimaryFocus, isTrue);
        }
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic;
        await tester.pumpWidget(const SizedBox());
        first.dispose();
        second.dispose();
        outside.dispose();
      });

      testWidgets('the focus returns to the opener after Escape, an outside '
          'tap and Back, and falls back when the opener went', (tester) async {
        for (final way in ['escape', 'outside', 'back', 'gone']) {
          final shell = make();
          final opener = FocusNode(debugLabel: 'opener');
          final other = FocusNode(debugLabel: 'other');
          final showOpener = ValueNotifier(true);
          await shell.pump(
            tester,
            Column(
              children: [
                Focus(focusNode: other, child: const SizedBox(height: 10)),
                ValueListenableBuilder(
                  valueListenable: showOpener,
                  builder: (context, show, _) => show
                      ? Focus(
                          focusNode: opener,
                          child: const SizedBox(height: 10),
                        )
                      : const SizedBox(height: 10),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          );
          other.requestFocus();
          await tester.pump();
          opener.requestFocus();
          await tester.pump();
          await shell.present(tester, _presentation([]));
          await tester.pump();
          await tester.pump();
          expect(opener.hasFocus, isFalse, reason: way);
          switch (way) {
            case 'escape':
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            case 'outside':
              await tester.tapAt(const Offset(5, 590));
            case 'back':
              await tester.binding.handlePopRoute();
            default:
              showOpener.value = false;
              await tester.pump();
              PresentationHandle.of(
                tester.element(find.byKey(_contentKey)),
              ).dismiss(DismissTrigger.programmatic);
          }
          await tester.pump();
          await _settle(tester);
          expect(shell.isPresented, isFalse, reason: way);
          if (way == 'gone') {
            final focused = FocusManager.instance.primaryFocus;
            expect(focused, isNotNull);
            expect(focused!.context?.mounted, isTrue, reason: way);
          } else {
            expect(opener.hasPrimaryFocus, isTrue, reason: way);
          }
          await tester.pumpWidget(const SizedBox());
          opener.dispose();
          other.dispose();
        }
      });

      testWidgets('announces itself: a route of its own, named by its '
          'label, with the role the presenter gives', (tester) async {
        final semantics = tester.ensureSemantics();
        final shell = make();
        await shell.pump(tester, const SizedBox.expand());
        await shell.present(
          tester,
          _presentation([], role: SemanticsRole.dialog),
        );
        await tester.pump();
        await _settle(tester);
        final root = find.bySemanticsLabel('Panel');
        expect(
          tester.getSemantics(root),
          matchesSemantics(
            label: 'Panel',
            textDirection: TextDirection.ltr,
            scopesRoute: true,
            namesRoute: true,
            hasDismissAction: true,
          ),
        );
        expect(
          tester.getSemantics(root).getSemanticsData().role,
          SemanticsRole.dialog,
        );
        await tester.pumpWidget(const SizedBox());

        final unnamed = make();
        await unnamed.pump(tester, const SizedBox.expand());
        await unnamed.present(
          tester,
          _presentation([], label: null, dismiss: DismissPolicy.modal),
        );
        await tester.pump();
        await _settle(tester);
        final scopes = <SemanticsData>[];
        bool visit(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.flagsCollection.scopesRoute) scopes.add(data);
          node.visitChildren(visit);
          return true;
        }

        visit(
          tester
              .binding
              .renderViews
              .first
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        final content = scopes.last;
        expect(content.flagsCollection.namesRoute, isFalse);
        expect(content.label, isEmpty);
        expect(content.role, SemanticsRole.none);
        expect(content.hasAction(SemanticsAction.dismiss), isTrue);
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

    testWidgets('presenting again while it leaves brings it back', (
      tester,
    ) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      final dismissed = <String?>[];
      await shell.pump(tester, const SizedBox.expand());
      await shell.present(tester, _presentation(made, dismissed: dismissed));
      await tester.pump();
      await _settle(tester);
      shell.controller.dismiss(DismissTrigger.programmatic);
      await tester.pump(const Duration(milliseconds: 16));
      expect(made.single.presence, PresenceStatus.leaving);
      shell.controller.present();
      await tester.pump();
      expect(made, hasLength(1));
      expect(made.single.presence, isNot(PresenceStatus.leaving));
      await _settle(tester);
      expect(made.single.presence, PresenceStatus.shown);
      expect(find.byKey(_contentKey), findsOneWidget);
      expect(dismissed, isEmpty);
      shell.controller.dismiss(DismissTrigger.outsideTap);
      expect(made.single.left, [
        DismissTrigger.programmatic,
        DismissTrigger.outsideTap,
      ]);
      await _settle(tester);
      expect(dismissed, [null]);
      expect(shell.isPresented, isFalse);
    });

    testWidgets('a new touch reaches what is below while it leaves, and one '
        'already on it stays', (tester) async {
      final shell = _PortalShell();
      final made = <_Card>[];
      var below = 0;
      var onIt = 0;
      await shell.pump(
        tester,
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => below++,
          child: const SizedBox.expand(),
        ),
      );
      await shell.present(
        tester,
        _presentation(
          made,
          dismiss: DismissPolicy.modal,
          onContentPointer: () => onIt++,
        ),
      );
      await tester.pump();
      await _settle(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(below, 0);

      final held = await tester.startGesture(
        tester.getCenter(find.byKey(_contentKey)),
      );
      expect(onIt, 1);
      shell.controller.dismiss(DismissTrigger.programmatic);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(below, 1);
      await held.moveBy(const Offset(1, 1));
      expect(onIt, 2);
      await held.up();

      shell.controller.present();
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(below, 1);
      await _settle(tester);
    });

    testWidgets('Tab leaves a presentation that is not modal', (tester) async {
      final shell = _PortalShell();
      final first = FocusNode();
      final outside = FocusNode();
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await shell.pump(
        tester,
        Focus(focusNode: outside, child: const SizedBox.expand()),
      );
      await shell.present(
        tester,
        _presentation([], focus: first, modal: false),
      );
      await tester.pump();
      await tester.pump();
      expect(first.hasPrimaryFocus, isTrue);
      final visited = <FocusNode?>[];
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        visited.add(FocusManager.instance.primaryFocus);
      }
      expect(visited, contains(outside));
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      outside.dispose();
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
