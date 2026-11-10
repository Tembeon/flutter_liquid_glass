// ignore_for_file: invalid_use_of_internal_member
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/src/surface/outline.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> _filled(WidgetTester tester, Path path) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawPath(
    path,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = false,
  );
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(120, 100));
  final bytes = await tester.runAsync(() => image!.toByteData());
  image!.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  const box = Rect.fromLTWH(10, 10, 100, 80);

  testWidgets('what lies outside an even-odd outline is the box less the '
      'body, holes left in', (tester) async {
    // A body with a hole, as an outline traced from a field has them.
    final body = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(30, 25, 60, 50),
          const Radius.circular(14),
        ),
      )
      ..addOval(const Rect.fromLTWH(50, 40, 20, 20));
    final whole = Path()..addRect(box);
    final subtracted = Path.combine(PathOperation.difference, whole, body);
    final outside = pathOutside(body, box);
    expect(outside.fillType, PathFillType.evenOdd);
    expect(await _filled(tester, outside), await _filled(tester, subtracted));
  });

  testWidgets('a path under another rule is subtracted', (tester) async {
    // Two rects that overlap: under the even-odd rule their overlap would
    // count as outside.
    final body = Path()
      ..addRect(const Rect.fromLTWH(30, 25, 40, 40))
      ..addRect(const Rect.fromLTWH(50, 35, 40, 40));
    final whole = Path()..addRect(box);
    final subtracted = Path.combine(PathOperation.difference, whole, body);
    expect(
      await _filled(tester, pathOutside(body, box)),
      await _filled(tester, subtracted),
    );
  });
}
