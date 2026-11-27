import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 300.0;

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    Directionality(
      textDirection: direction,
      child: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: Center(
          child: SizedBox(width: _width, child: child),
        ),
      ),
    );

Finder get _bar => find.descendant(
  of: find.byType(GlassProgressView),
  matching: find.byType(CustomPaint),
);

RRect _capsule(double left, double width, double height) =>
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 0, width, height),
      Radius.circular(height / 2),
    );

PaintPattern _fill(double width, {double left = 0, double height = 4}) => paints
  ..rrect(rrect: _capsule(0, _width, height))
  ..rrect(rrect: _capsule(left, width, height));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a capsule 4 tall on its track, the fill as far as the '
      'progress, never under 8, none at 0', (tester) async {
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.4)));
    expect(tester.getSize(find.byType(GlassProgressView)), const Size(300, 4));
    expect(_bar, _fill(120));
    await tester.pumpWidget(
      _app(const GlassProgressView(value: 0.01, animated: false)),
    );
    expect(_bar, _fill(8));
    await tester.pumpWidget(
      _app(const GlassProgressView(value: 0, animated: false)),
    );
    expect(
      _bar,
      paints
        ..rrect(rrect: _capsule(0, _width, 4))
        ..everything((method, arguments) => method != #drawRRect),
    );
  });

  testWidgets('the bar style is 2.67 tall with no track', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassProgressView(
          value: 0.5,
          style: GlassProgressViewStyle.bar,
        ),
      ),
    );
    expect(tester.getSize(find.byType(GlassProgressView)).height, 2.67);
    expect(_bar, paints..rrect(rrect: _capsule(0, 150, 2.67)));
  });

  testWidgets('right to left, the fill grows from the right', (tester) async {
    await tester.pumpWidget(
      _app(
        const GlassProgressView(value: 0.5),
        direction: TextDirection.rtl,
      ),
    );
    expect(_bar, _fill(150, left: 150));
  });

  testWidgets('a change moves a bar a second, linearly; from 0 it takes '
      'at least 0.2 s', (tester) async {
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.2)));
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.3)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_bar, _fill(_width * 0.25));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_bar, _fill(_width * 0.3));

    await tester.pumpWidget(
      _app(const GlassProgressView(value: 0, animated: false)),
    );
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.05)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_bar, _fill(8), reason: 'half way, under the narrowest fill');
    await tester.pump(const Duration(milliseconds: 110));
    expect(_bar, _fill(15));
  });

  testWidgets('changes that overlap add up: a retarget plateaus until the '
      'first change ends (device run, 0.2 to 0.9 then 0.4)', (tester) async {
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.2)));
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.9)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(_app(const GlassProgressView(value: 0.4)));
    for (final ms in [100, 200, 140]) {
      await tester.pump(Duration(milliseconds: ms));
      expect(_bar, _fill(_width * 0.45));
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(_bar, _fill(_width * 0.4));
  });

  testWidgets('screen readers read the label and the percentage', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const GlassProgressView(value: 0.4, semanticLabel: 'Download')),
    );
    expect(
      find.semantics.byPredicate(
        (node) => node.label == 'Download' && node.value == '40%',
      ),
      findsOne,
    );
    semantics.dispose();
  });
}
