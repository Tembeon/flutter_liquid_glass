import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
import 'package:liquid_glass_renderer/widgets.dart';

/// Loads full glass once, outside any test's fake clock: a load a layer
/// starts inside one never settles there, and a later test awaiting it
/// would wait forever. A test turns the renderer's copies on or sets its
/// policy freely: after it they are what they were before any test ran.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await precacheLiquidGlass();
  final copies = glassReadsCopies;
  final policy = debugGlassPolicy;
  tearDown(() {
    glassReadsCopies = copies;
    debugGlassPolicy = policy;
  });
  await testMain();
}
