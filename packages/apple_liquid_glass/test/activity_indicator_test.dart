import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: GlassScope(
    renderer: const FlatGlassRenderer(),
    child: Center(child: child),
  ),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('medium is 20 across and large 37, read as loading while it '
      'turns', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const GlassActivityIndicator()));
    expect(
      tester.getSize(find.byType(GlassActivityIndicator)),
      const Size(20, 20),
    );
    expect(find.bySemanticsLabel('Loading...'), findsOneWidget);
    await tester.pumpWidget(
      _app(
        const GlassActivityIndicator(size: GlassActivityIndicatorSize.large),
      ),
    );
    expect(
      tester.getSize(find.byType(GlassActivityIndicator)),
      const Size(37, 37),
    );
    semantics.dispose();
  });

  testWidgets('stopped, it hides in place and is not read; kept, it stays '
      'on its step', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const GlassActivityIndicator(animating: false)),
    );
    expect(
      tester.getSize(find.byType(GlassActivityIndicator)),
      const Size(20, 20),
    );
    expect(find.byType(GlassActivityIndicator), paintsNothing);
    expect(find.bySemanticsLabel('Loading...'), findsNothing);
    await tester.pumpWidget(
      _app(
        const GlassActivityIndicator(animating: false, hidesWhenStopped: false),
      ),
    );
    expect(find.byType(GlassActivityIndicator), paints..line());
    semantics.dispose();
  });
}
