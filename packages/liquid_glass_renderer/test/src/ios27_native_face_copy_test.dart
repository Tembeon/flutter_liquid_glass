import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'ios27_native_faces.dart';
import 'submitted_scene_binding.dart';

void main() {
  runNativeFaceCopyTests(SubmittedSceneBinding());
}

/// Shared host/device workload: the native face table of
/// ios27_native_face_test.dart over glass that reads what lies under it,
/// which a device reads from a copy of the frame. flutter_tester reads a
/// backdrop filter, which it draws only in its first render, so the host
/// skips it.
void runNativeFaceCopyTests(TestWidgetsFlutterBinding testBinding) {
  final binding = (testBinding as SubmittedSceneCapture)
    ..captureWidth = nativeFaceView.width.toInt()
    ..captureHeight = nativeFaceView.height.toInt();
  testWidgets(
    'glass reading a copy over a plain color shows the face native glass '
    'of its size shows',
    (tester) async {
      await tester.runAsync(precacheLiquidGlass);
      tester.view
        ..physicalSize = nativeFaceView
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final off = <String>[];
      final misses = <int>[];
      final atTwo = <String>[];
      for (final (brightness, size, slider, page, native, tint)
          in nativeFaceCases) {
        await tester.pumpWidget(
          nativeFaceScene(
            brightness,
            size,
            slider,
            page,
            tint: tint,
            solid: false,
          ),
        );
        await tester.pump();
        binding
          ..captureNextScene = true
          ..scheduleFrame();
        await tester.pump();
        final image = (await tester.runAsync(() => binding.captured!))!;
        final bytes = (await tester.runAsync(image.toByteData))!;
        image.dispose();
        final rgba = bytes.buffer.asUint8List();
        final width = nativeFaceView.width.toInt();
        final at = ((nativeFaceView.height ~/ 2) * width + width ~/ 2) * 4;
        final drawn = [rgba[at], rgba[at + 1], rgba[at + 2]];
        final wanted = [
          (native.r * 255).round(),
          (native.g * 255).round(),
          (native.b * 255).round(),
        ];
        var miss = 0;
        for (var channel = 0; channel < 3; channel++) {
          final channelMiss = (drawn[channel] - wanted[channel]).abs();
          if (channelMiss > miss) miss = channelMiss;
        }
        misses.add(miss);
        final line =
            '${brightness?.name ?? 'clear'} ${size.height} pt at slider '
            '$slider over $page under $tint: drew $drawn, native $wanted';
        if (miss == 2) atTwo.add(line);
        if (miss > 2) {
          off.add(line);
        }
        await tester.pumpWidget(const SizedBox());
      }
      debugPrint(
        'copy path face: ${misses.length} cases, '
        '${misses.where((m) => m <= 1).length} within 1, '
        '${misses.where((m) => m == 2).length} at 2, '
        'worst ${misses.reduce((a, b) => a > b ? a : b)}\n'
        '${atTwo.join('\n')}',
      );
      expect(off, isEmpty, reason: off.join('\n'));
    },
    skip: binding.isFlutterTester,
  );
}
