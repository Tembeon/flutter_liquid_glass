import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/rendering.dart';

const _key = ValueKey('page');
const _shape = Rect.fromLTWH(40, 30, 120, 70);
const _red = Color(0xFFFF0000);

class _Bent extends LeafRenderObjectWidget {
  const _Bent({required this.bends, required this.marks, super.key});

  final List<LiquidGlassContentBend> bends;
  final List<Rect> marks;

  @override
  _RenderBent createRenderObject(BuildContext context) =>
      _RenderBent(bends, marks);
}

class _RenderBent extends RenderBox {
  _RenderBent(this.bends, this.marks);

  final List<LiquidGlassContentBend> bends;
  final List<Rect> marks;
  final bent = LiquidGlassBentContent();

  /// Whether the content was painted into the context of this box.
  bool paintedInPlace = false;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void dispose() {
    bent.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = _shape.shift(offset);
    bent.paint(
      context,
      offset,
      rect: rect,
      radius: 35,
      clip: Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(35))),
      bends: bends,
      devicePixelRatio: 1,
      content: (inner, offset) {
        paintedInPlace = identical(inner, context);
        for (final mark in marks) {
          inner.canvas.drawRect(mark.shift(offset), Paint()..color = _red);
        }
      },
    );
  }
}

/// The red of a black page under [marks] as the shape shows them through
/// [bends].
Future<int Function(int x, int y)> _reds(
  WidgetTester tester,
  List<LiquidGlassContentBend> bends,
  List<Rect> marks,
) async {
  tester.view.physicalSize = const Size(200, 140);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: _Bent(key: ValueKey((bends, marks)), bends: bends, marks: marks),
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
  const bend = LiquidGlassContentBend(amount: 10, height: 10);
  // A line across the shape 12 to 14 px under its top, deeper than the
  // bends below reach.
  final line = Rect.fromLTWH(_shape.left, _shape.top + 12, _shape.width, 2);
  final x = _shape.center.dx.round();
  int row(int depth) => _shape.top.round() + depth;
  bool inPlace(WidgetTester tester) =>
      tester.renderObject<_RenderBent>(find.byType(_Bent)).paintedInPlace;

  test('a bend shows at the rim what lies its amount deeper, along a '
      'quarter circle to nothing at its height', () {
    expect(bend.shownDepth(0), 10);
    // Half way the quarter circle has fallen to 1 - sqrt(0.75).
    expect(bend.shownDepth(5), moreOrLessEquals(6.340, epsilon: 1e-3));
    expect(bend.shownDepth(10), 10);
    expect(bend.shownDepth(20), 20);
    expect(bend.shownDepth(-1), -1);
  });

  testWidgets('without a bend the content is painted as it is, into the '
      'context it was given', (tester) async {
    final reds = await _reds(tester, const [], [line]);
    expect(reds(x, row(12)), 255);
    expect(reds(x, row(13)), 255);
    expect(reds(x, row(11)), 0);
    expect(reds(x, row(0)), 0);
    expect(inPlace(tester), isTrue);
  });

  testWidgets('a bend shows a line deeper than it reaches in place and '
      'again under the rim', (tester) async {
    // 0.5 px deep a bend of 18 over 10 shows what lies 0.5 + 18 * (1 -
    // sqrt(1 - 0.95 * 0.95)) = 12.9 px deep, the line, and 1.5 px deep
    // what lies 10.0 px deep, nothing.
    final reds = await _reds(
      tester,
      const [LiquidGlassContentBend(amount: 18, height: 10)],
      [line],
    );
    expect(inPlace(tester), isFalse);
    expect(reds(x, row(12)), greaterThan(252));
    expect(reds(x, row(13)), greaterThan(252));
    expect(reds(x, row(14)), lessThan(3));
    expect(reds(x, row(1)), lessThan(3));
    expect(reds(x, row(5)), lessThan(3));
    expect(reds(x, row(0)), greaterThan(150));
  });

  testWidgets('bends apply in order, each to what the one before it shows', (
    tester,
  ) async {
    // The first reads 10 px deep at the rim, where the second reaches no
    // more: together they show there what one shows, not the line.
    final reds = await _reds(tester, const [bend, bend], [line]);
    expect(reds(x, row(0)), lessThan(3));
    expect(reds(x, row(12)), greaterThan(252));
  });

  testWidgets('what the bends do not reach shows pixel for pixel, and '
      'nothing shows outside the clip', (tester) async {
    final mark = Rect.fromLTWH(_shape.center.dx, _shape.top + 30, 1, 10);
    final reds = await _reds(
      tester,
      const [bend],
      [
        mark,
        const Rect.fromLTWH(0, 0, 10, 140),
      ],
    );
    final column = mark.left.round();
    for (var y = row(30); y < row(40); y++) {
      expect(reds(column, y), greaterThan(252));
      expect(reds(column - 1, y), lessThan(3));
      expect(reds(column + 1, y), lessThan(3));
    }
    expect(reds(5, 70), 0);
  });
}
