import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
import 'package:material_ui/material_ui.dart';

const expectFlutterGpuFallback = bool.fromEnvironment(
  'EXPECT_FLUTTER_GPU_FALLBACK',
);

bool get skipProperGlassTests =>
    expectFlutterGpuFallback || !ui.ImageFilter.isShaderFilterSupported;

/// Alchemist still calls `testWidgets` when a golden is tagged `golden`, and
/// Flutter 3.44 asserts that the variant is non-empty. Platform goldens are
/// macOS-only, so skip registration on other hosts instead of loading an
/// empty variant.
bool get skipGoldenTests => skipProperGlassTests || !Platform.isMacOS;

void expectGeneratedFile(String path, String text) {
  final file = File(path);
  if (const bool.fromEnvironment('UPDATE_SHADER_CONSTANTS')) {
    file.writeAsStringSync(text);
    return;
  }
  expect(
    file.readAsStringSync(),
    text,
    reason:
        '$path is generated: run with '
        '--dart-define=UPDATE_SHADER_CONSTANTS=true.',
  );
}

/// Compares [actual] with the pixel reference at [path], on macOS only.
///
/// References are rendered by `flutter test --update-goldens` on the macOS
/// image the CI golden job uses; flutter_tester rasterizes differently on
/// other hosts, so they skip the comparison and keep the test's other checks.
Future<void> expectMacOSGolden(Object? actual, String path) async {
  if (!Platform.isMacOS) return;
  await expectLater(actual, matchesGoldenFile(path));
}

final testScenarioConstraints = BoxConstraints.tight(const Size(500, 500));

const settingsWithoutLighting = LiquidGlassSettings(
  glintStrength: 0,
  contourStrength: 0,
  bevelShadowStrength: 0,
  frost: LiquidGlassFrost.sigma(0),
);

Matrix4 stretchedBy(Offset pull, Size size) {
  final relX = pull.dx.abs() / size.width;
  final relY = pull.dy.abs() / size.height;
  final baseX = 1 + relX;
  final baseY = 1 + relY;
  final areaGrowth = 1 + math.sqrt(relX * relX + relY * relY) * 0.5;
  final correction = math.sqrt(areaGrowth / (baseX * baseY));
  final move = pull * 1.5;
  return Matrix4.translationValues(move.dx, move.dy, 0)
    ..scaleByDouble(baseX * correction, baseY * correction, 1, 1);
}

Widget buildWithGridPaper(Widget child) {
  return ColoredBox(
    color: Colors.white,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const Positioned.fill(
            child: GridPaper(
              color: Colors.black,
            ),
          ),
          Center(
            child: child,
          ),
        ],
      ),
    ),
  );
}

/// Draws every copy of the current test into an image, as copies asked for
/// with a filter always are, for tests of how images are shared and held.
void copyIntoImages() {
  debugGlassPolicy = const PlanPolicy(maxTargets: 0);
  addTearDown(() => debugGlassPolicy = const PlanPolicy());
}
