import 'dart:typed_data';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/liquid/lens_content.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ValueKey('page');
const _lens = Rect.fromLTWH(40, 30, 114, 70);
const _red = Color(0xFFFF0000);

class _Shown extends LeafRenderObjectWidget {
  const _Shown({required this.frame, required this.marks, super.key});

  final GlassFrame frame;
  final List<Rect> marks;

  @override
  _RenderShown createRenderObject(BuildContext context) =>
      _RenderShown(frame, marks);
}

class _RenderShown extends RenderBox {
  _RenderShown(this.frame, this.marks);

  final GlassFrame frame;
  final List<Rect> marks;
  final shown = LensContentBend();
  int contents = 0;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void dispose() {
    shown.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) => shown.paint(
    context,
    offset,
    frame: frame,
    size: size,
    content: (context, offset) {
      contents++;
      for (final mark in marks) {
        context.canvas.drawRect(mark.shift(offset), Paint()..color = _red);
      }
    },
  );
}

/// The red of a black page under [marks] as the lens at [_lens] lifted by
/// [lift] shows them.
Future<int Function(int x, int y)> _reds(
  WidgetTester tester,
  List<Rect> marks, {
  double lift = 1,
}) async {
  tester.view.physicalSize = const Size(200, 140);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: _Shown(
          key: ValueKey((marks, lift)),
          frame: GlassFrame(rect: _lens, lift: lift),
          marks: marks,
        ),
      ),
    ),
  );
  final (Uint8List bytes, int width) = (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes!.buffer.asUint8List(), width);
  }))!;
  return (int x, int y) => bytes[(y * width + x) * 4];
}

void main() {
  group('the law', () {
    test('a tab bar lens shows at its rim what lies 14 pt inside it, and '
        'never what lies nearer than 8.4 pt', () {
      double shown(double depth) =>
          LensContentLaw.shownDepth(depth, height: 70);
      expect(shown(0), moreOrLessEquals(14, epsilon: 1e-9));
      expect(shown(1), moreOrLessEquals(9.494, epsilon: 2e-3));
      expect(shown(4.2), moreOrLessEquals(8.385, epsilon: 2e-3));
      expect(shown(8), moreOrLessEquals(9.068, epsilon: 2e-3));
      var nearest = double.infinity;
      for (var depth = 0.0; depth <= 35; depth += 0.05) {
        if (shown(depth) < nearest) nearest = shown(depth);
      }
      expect(nearest, moreOrLessEquals(8.383, epsilon: 5e-3));
    });

    test('from 11.2 pt deep everything shows in place', () {
      expect(LensContentLaw.shownDepth(11.2, height: 70), 11.2);
      expect(LensContentLaw.shownDepth(20, height: 70), 20);
      // A segmented control's lens bends by its own height first, and the
      // lift's bend reaches as deep as on a tab bar.
      expect(LensContentLaw.shownDepth(11.2, height: 44), 11.2);
      expect(
        LensContentLaw.shownDepth(0, height: 44),
        moreOrLessEquals(9.207, epsilon: 2e-3),
      );
    });

    test('the bends grow with the lift', () {
      expect(LensContentLaw.shownDepth(3, height: 70, lift: 0), 3);
      // Half the first bend reads 7 pt deep, where half the second still
      // reaches.
      expect(
        LensContentLaw.shownDepth(0, height: 70, lift: 0.5),
        moreOrLessEquals(7.639, epsilon: 2e-3),
      );
    });
  });

  group('the picture', () {
    // A line across the lens 9 to 10 pt under its top.
    final line = Rect.fromLTWH(_lens.left, _lens.top + 9, _lens.width, 1);
    final x = _lens.center.dx.round();
    int row(double depth) => (_lens.top + depth).floor();

    testWidgets('a resting lens shows its content as it is, without a '
        'picture', (tester) async {
      final reds = await _reds(tester, [line], lift: 0);
      expect(reds(x, row(9)), 255);
      expect(reds(x, row(8)), 0);
      expect(reds(x, row(1)), 0);
      expect(
        tester.renderObject<_RenderShown>(find.byType(_Shown)).contents,
        1,
      );
    });

    testWidgets('a lifted lens shows a line 9 pt deep twice: under the rim '
        'and 8 to 10 pt deep', (tester) async {
      final reds = await _reds(tester, [line]);
      // The middle of each row reads the picture between two of its rows:
      // 1.5 pt deep what lies 9.02 pt deep, half the line.
      expect(reds(x, row(1)), closeTo(132, 12));
      // 3.5 to 5.5 pt deep what lies nearer than 8.5 pt: none of it.
      expect(reds(x, row(3)), lessThan(10));
      expect(reds(x, row(4)), lessThan(10));
      expect(reds(x, row(5)), lessThan(10));
      // 6.5, 7.5, 8.5 and 9.5 pt deep what lies 8.63, 8.90, 9.30 and 9.85
      // pt deep.
      expect(reds(x, row(6)), closeTo(34, 12));
      expect(reds(x, row(7)), closeTo(103, 12));
      expect(reds(x, row(8)), closeTo(204, 12));
      expect(reds(x, row(9)), closeTo(165, 12));
      // 10.5 pt deep and deeper what lies there.
      expect(reds(x, row(10)), lessThan(10));
      expect(reds(x, row(12)), lessThan(10));
    });

    testWidgets('what lies deeper than the bends shows pixel for pixel', (
      tester,
    ) async {
      final mark = Rect.fromLTWH(_lens.center.dx, _lens.top + 30, 1, 10);
      final reds = await _reds(tester, [mark]);
      final column = mark.left.round();
      for (var y = row(30); y < row(40); y++) {
        expect(reds(column, y), greaterThan(252));
        expect(reds(column - 1, y), lessThan(3));
        expect(reds(column + 1, y), lessThan(3));
      }
      expect(reds(column, row(29)), lessThan(3));
      expect(reds(column, row(40)), lessThan(3));
    });

    testWidgets('nothing shows outside the lens', (tester) async {
      final reds = await _reds(tester, const [Rect.fromLTWH(0, 0, 200, 140)]);
      expect(reds(_lens.center.dx.round(), _lens.center.dy.round()), 255);
      expect(reds(_lens.left.round() - 2, _lens.center.dy.round()), 0);
      expect(reds(_lens.center.dx.round(), _lens.top.round() - 2), 0);
      // The corner of the lens's box lies outside its capsule.
      expect(reds(_lens.left.round() + 2, _lens.top.round() + 2), 0);
    });
  });
}
