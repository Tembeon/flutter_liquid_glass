import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'paint_probe.dart';

Widget _app(
  Widget anchor, {
  Alignment alignment = const Alignment(0, -0.6),
  GlassRenderer renderer = const FlatGlassRenderer(),
}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => GlassScope(renderer: renderer, child: child!),
  home: Align(alignment: alignment, child: anchor),
);

List<GlassMenuEntry> _entries(List<String> log) => [
  for (final title in ['Copy', 'Share'])
    GlassMenuItem(title: title, onPressed: () => log.add(title)),
];

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// The layer the anchor puts its control on.
RenderBox _controlLayer(WidgetTester tester) => tester.renderObject(
  find
      .ancestor(
        of: find.byType(GlassSourceScope),
        matching: find.byType(RepaintBoundary),
      )
      .first,
);

// The nearest layer around what [finder] finds.
RenderBox _layerAround(WidgetTester tester, Finder finder) =>
    tester.renderObject(
      find.ancestor(of: finder, matching: find.byType(RepaintBoundary)).first,
    );

// Where the composited layers put [box]'s own layer on screen, in logical
// pixels, or null while that layer is on no screen.
Rect? _drawn(WidgetTester tester, RenderBox box) {
  final layer = box.debugLayer;
  if (layer is! OffsetLayer || !layer.attached) return null;
  final chain = <Layer>[];
  for (Layer? at = layer; at != null; at = at.parent) {
    chain.add(at);
  }
  final transform = Matrix4.identity();
  for (var i = chain.length - 1; i > 0; i--) {
    (chain[i] as ContainerLayer).applyTransform(chain[i - 1], transform);
  }
  transform.translateByDouble(layer.offset.dx, layer.offset.dy, 0, 1);
  final physical = MatrixUtils.transformRect(
    transform,
    Offset.zero & box.size,
  );
  final ratio = tester.view.devicePixelRatio;
  return Rect.fromLTRB(
    physical.left / ratio,
    physical.top / ratio,
    physical.right / ratio,
    physical.bottom / ratio,
  );
}

// Whether [drawn] stands off [rest] by more than half a point: drawn by the
// menu's morph, not in place.
bool _moved(Rect drawn, Rect rest) =>
    (drawn.left - rest.left).abs() > 0.5 ||
    (drawn.top - rest.top).abs() > 0.5 ||
    (drawn.right - rest.right).abs() > 0.5 ||
    (drawn.bottom - rest.bottom).abs() > 0.5;

// The opacity of the menu's glass, or null once the menu has gone.
double? _menuGlass(WidgetTester tester) {
  final panels = tester
      .widgetList<GlassSurface>(find.byType(GlassSurface))
      .where((surface) => surface.role == GlassRole.panel);
  return panels.isEmpty ? null : panels.single.frame!.value.opacity;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a menu covers the window band at the top of the padding and '
      'keeps clear of the rest', (tester) async {
    Rect? menu;
    for (final band in [0.0, 52.0]) {
      _phone(tester);
      tester.view.padding = const FakeViewPadding(top: 52 * 3);
      final controller = GlassMenuController();
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          pageRouteBuilder: <T>(settings, builder) =>
              GlassPageRoute<T>(builder: builder, settings: settings),
          builder: (context, child) => GlassWindowBand(
            height: band,
            child: GlassScope(
              renderer: const FlatGlassRenderer(),
              child: child!,
            ),
          ),
          home: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GlassMenuAnchor(
                controller: controller,
                menuChildren: _entries(<String>[]),
                builder: (context, controller, child) =>
                    const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        ),
      );
      controller.open();
      await _settle(tester);
      menu = tester.getRect(find.text('Copy'));
      if (band == 0) {
        expect(menu.top, greaterThanOrEqualTo(52));
      } else {
        expect(menu.top, lessThan(52));
      }
      await tester.pumpWidget(const SizedBox());
    }
    expect(menu, isNotNull);
  });

  testWidgets('what the menu grows out of leaves the screen while the menu '
      'is open and comes back when it closes, a button or not', (tester) async {
    for (final button in [true, false]) {
      _phone(tester);
      final controller = GlassMenuController();
      var paints = 0;
      final label = SizedBox(
        width: 60,
        height: 30,
        child: CustomPaint(
          key: const Key('probe'),
          painter: PaintProbe(() => paints++),
        ),
      );
      await tester.pumpWidget(
        _app(
          GlassMenuAnchor(
            controller: controller,
            menuChildren: _entries(<String>[]),
            child: button
                ? GlassButton(onPressed: controller.open, child: label)
                : label,
          ),
        ),
      );
      Future<bool> painted() async {
        paints = 0;
        await repaint(tester, find.byKey(const Key('probe')));
        return paints > 0;
      }

      expect(await painted(), isTrue, reason: 'button $button');
      controller.open();
      await _settle(tester);
      expect(find.text('Copy'), findsOneWidget);
      expect(await painted(), isFalse, reason: 'button $button');
      controller.close();
      await _settle(tester);
      expect(await painted(), isTrue, reason: 'button $button');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a title that takes the chosen item rides the closing menu '
      'live and lands where the control stands with it', (tester) async {
    _phone(tester);
    const long = 'Date of the last watering';
    var sort = 'Name';
    await tester.pumpWidget(
      _app(
        alignment: const Alignment(-0.9, -0.6),
        StatefulBuilder(
          builder: (context, setState) => GlassMenuAnchor(
            menuChildren: [
              for (final title in const ['Name', long])
                GlassMenuItem(
                  title: title,
                  onPressed: () => setState(() => sort = title),
                ),
            ],
            builder: (context, controller, child) => GlassButton(
              onPressed: controller.open,
              child: Text('Sort by $sort'),
            ),
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byType(GlassButton));
    await tester.tap(find.byType(GlassButton));
    await _settle(tester);
    await tester.tap(find.text(long));
    final title = find.text('Sort by $long');
    for (var i = 0; i < 4 && title.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(title, findsOneWidget);
    Rect? last;
    var frames = 0;
    for (; frames < 120; frames++) {
      if (_drawn(tester, _controlLayer(tester)) != null) break;
      last = _drawn(tester, _layerAround(tester, title)) ?? last;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frames, lessThan(120), reason: 'the control shows again');
    expect(find.text('Name'), findsNothing);
    expect(
      tester.getRect(find.byType(GlassButton)).width,
      greaterThan(before.width + 40),
    );
    final rest = tester.getRect(title);
    expect(last, isNotNull, reason: 'the new title rode the morph');
    for (final (drawn, real) in [
      (last!.left, rest.left),
      (last.top, rest.top),
      (last.right, rest.right),
      (last.bottom, rest.bottom),
    ]) {
      expect(drawn, moreOrLessEquals(real, epsilon: 0.5));
    }
  });

  testWidgets('a control without glass rides the morph whole as the menu '
      'glass appears over it, and comes back as the glass goes; glass in the '
      "control keeps the menu's glass whole, and a glass button's label "
      'rides it', (tester) async {
    for (final kind in ['text', 'raw', 'glass', 'undescribed']) {
      _phone(tester);
      final controller = GlassMenuController();
      await tester.pumpWidget(
        _app(
          GlassMenuAnchor(
            controller: controller,
            menuChildren: _entries(<String>[]),
            builder: (context, controller, child) => switch (kind) {
              'text' => const Text('More'),
              'raw' => RawGlassButton(
                onPressed: controller.open,
                builder: (context, details) => ColoredBox(
                  color: const Color(0xFF3060F0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: details.label,
                  ),
                ),
                child: const Text('More'),
              ),
              'glass' => GlassButton(
                onPressed: controller.open,
                child: const Text('More'),
              ),
              _ => const GlassSurface(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('More'),
                ),
              ),
            },
          ),
        ),
      );
      final control = _controlLayer(tester);
      final controlRest = _drawn(tester, control)!;
      final labelRest = tester.getRect(find.text('More'));
      controller.open();
      await tester.pump();
      final opening = <double>[];
      var controlRode = false;
      var controlShown = false;
      var labelRode = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        opening.add(_menuGlass(tester)!);
        final drawn = _drawn(tester, control);
        if (drawn != null) {
          controlShown = true;
          if (_moved(drawn, controlRest)) controlRode = true;
        }
        final label = _drawn(tester, _layerAround(tester, find.text('More')));
        if (label != null && _moved(label, labelRest)) labelRode = true;
      }
      await _settle(tester);
      expect(_menuGlass(tester), 1, reason: kind);
      expect(_drawn(tester, control), isNull, reason: kind);
      controller.close();
      final closing = <double>[];
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final glass = _menuGlass(tester);
        if (glass == null) break;
        closing.add(glass);
      }
      expect(_menuGlass(tester), isNull, reason: kind);
      expect(_drawn(tester, control), controlRest, reason: kind);
      if (kind == 'glass' || kind == 'undescribed') {
        expect(controlShown, isFalse, reason: 'its glass is drawn once');
        if (kind == 'glass') expect(labelRode, isTrue, reason: kind);
        expect(opening.every((glass) => glass == 1), isTrue, reason: kind);
        expect(closing.every((glass) => glass == 1), isTrue, reason: kind);
      } else {
        expect(controlRode, isTrue, reason: kind);
        expect(opening.first, lessThan(0.25), reason: kind);
        expect(closing.last, lessThan(0.05), reason: kind);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('on the liquid renderer the control rides the morph from its '
      'own layer, glass or not', (tester) async {
    for (final glass in [false, true]) {
      _phone(tester);
      final controller = GlassMenuController();
      await tester.pumpWidget(
        _app(
          renderer: const LiquidGlassRenderer(),
          GlassMenuAnchor(
            controller: controller,
            menuChildren: _entries(<String>[]),
            builder: (context, controller, child) => glass
                ? GlassButton(
                    onPressed: controller.open,
                    child: const Text('More'),
                  )
                : const Text('More'),
          ),
        ),
      );
      final rides = glass
          ? _layerAround(tester, find.text('More'))
          : _controlLayer(tester);
      final rest = tester.getRect(find.text('More'));
      final at = rides.localToGlobal(Offset.zero);
      final restOfRides = at & rides.size;
      controller.open();
      await tester.pump();
      var rode = false;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final drawn = _drawn(tester, rides);
        if (drawn != null && _moved(drawn, restOfRides)) rode = true;
      }
      expect(rode, isTrue, reason: 'glass $glass');
      await _settle(tester);
      controller.close();
      await _settle(tester);
      expect(_menuGlass(tester), isNull, reason: 'glass $glass');
      expect(tester.getRect(find.text('More')), rest, reason: 'glass $glass');
      expect(_drawn(tester, rides), restOfRides, reason: 'glass $glass');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a button whose action opens the menu opens it on a tap after '
      'the measured delay, and the builder sees it open', (tester) async {
    _phone(tester);
    final open = <bool>[];
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) {
            open.add(controller.isOpen);
            return GlassButton(
              key: const Key('button'),
              onPressed: controller.open,
              child: child!,
            );
          },
          child: const Text('More'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('button')));
    await tester.pump();
    expect(find.text('Copy'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Copy'), findsOneWidget);
    await _settle(tester);
    expect(open.last, isTrue);
  });

  testWidgets('onOpen and onClose bracket the menu, and a menu that goes '
      'with its anchor reports it closed', (tester) async {
    _phone(tester);
    final calls = <String>[];
    final controller = GlassMenuController();
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          controller: controller,
          onOpen: () => calls.add('open'),
          onClose: () => calls.add('close'),
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => GlassButton(
            onPressed: controller.open,
            child: const Text('More'),
          ),
        ),
      ),
    );
    controller.open();
    await _settle(tester);
    expect(calls, ['open']);
    controller.close();
    await _settle(tester);
    expect(calls, ['open', 'close']);
    controller.open();
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['open', 'close', 'open', 'close']);
  });

  testWidgets('plain text in a raw button is a source: a tap opens the menu '
      'and a row closes it', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(log),
          builder: (context, controller, child) => RawGlassButton(
            onPressed: controller.open,
            builder: (context, details) => details.label,
            child: child!,
          ),
          child: const SizedBox(
            width: 100,
            height: 44,
            child: Center(child: Text('Sort')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sort'));
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await _settle(tester);
    expect(log, ['Share']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a button with an action of its own runs it on a tap, Space '
      'and Enter, and a hold opens the menu', (tester) async {
    _phone(tester);
    final log = <String>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(log),
          builder: (context, controller, child) => GlassButton(
            key: const Key('button'),
            focusNode: focus,
            onPressed: () => log.add('pressed'),
            child: const Text('Share'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('button')));
    await _settle(tester);
    expect(log, ['pressed']);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(log, ['pressed', 'pressed']);
    expect(find.text('Copy'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('button'))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Copy'), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(log, ['pressed', 'pressed']);
  });

  testWidgets('the control reads as an expandable button named by its label, '
      'and the focus comes back to it when the menu closes', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => GlassButton(
            focusNode: focus,
            onPressed: controller.open,
            semanticLabel: 'More',
            child: const Text('...'),
          ),
        ),
      ),
    );
    final node = tester
        .getSemantics(find.bySemanticsLabel('More'))
        .getSemanticsData();
    expect(node.flagsCollection.isExpanded, Tristate.isFalse);
    expect(node.flagsCollection.isButton, isTrue);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(focus.hasFocus, isTrue);
    handle.dispose();
  });

  testWidgets('a menu its source does not name reads "Menu" over a barrier '
      'read as "Dismiss menu"', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => RawGlassButton(
            onPressed: controller.open,
            builder: (context, details) => details.label,
            child: child!,
          ),
          child: const SizedBox(width: 100, height: 44, child: Text('Sort')),
        ),
      ),
    );
    await tester.tap(find.text('Sort'));
    await _settle(tester);
    expect(find.bySemanticsLabel('Menu'), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss menu'), findsOneWidget);
    handle.dispose();
  });
}
