import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUp(MotionClock.debugReset);

  testWidgets("the popover's glass takes the style's background", (
    tester,
  ) async {
    phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);
    await tester.pumpWidget(overlayApp(navigator, opener: opener));
    unawaited(
      showGlassPopover<void>(
        navigator.currentContext!,
        anchorRect: const Rect.fromLTWH(180, 600, 40, 40),
        adaptsToSheet: false,
        style: const GlassPopoverStyle(backgroundColor: Color(0x80FF0000)),
        builder: (context) => const SizedBox(width: 200, height: 80),
      ),
    );
    await settle(tester);
    final glass = tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .where((surface) => surface.role == GlassRole.panel)
        .single
        .glass;
    expect(glass.tint, const Color(0x80FF0000));
  });
}
