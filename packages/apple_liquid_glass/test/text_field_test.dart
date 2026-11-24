import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _field = Key('field');

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) => Directionality(
        textDirection: direction,
        child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      ),
      home: Center(
        child: SizedBox(
          width: 300,
          child: KeyedSubtree(key: _field, child: child),
        ),
      ),
    );

Rect _text(WidgetTester tester) => tester.getRect(find.byType(EditableText));

Rect _box(WidgetTester tester) =>
    tester.getRect(find.byType(DecoratedBox).first);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a field of one line is 34 tall with its text 7 inside its '
      'edges, and its placeholder shows while it is empty', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(
      _app(GlassTextField(placeholder: 'Name', onChanged: changes.add)),
    );
    final box = _box(tester);
    expect(box.height, 34);
    expect(_text(tester).left, box.left + 7);
    expect(_text(tester).right, box.right - 7);
    expect(_text(tester).center.dy, box.center.dy);
    expect(find.text('Name'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Ann');
    await tester.pump();
    expect(changes, ['Ann']);
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, false);
  });

  testWidgets('a tap on the field away from its text focuses it', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(_app(GlassTextField(focusNode: focus)));
    await tester.tapAt(_box(tester).centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('side views stand flush on the edges, the text 7 after the '
      'leading one and up to the trailing one, mirrored right to left', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        _app(
          const GlassTextField(
            prefix: SizedBox(key: Key('prefix'), width: 24, height: 24),
            suffix: SizedBox(key: Key('suffix'), width: 24, height: 24),
          ),
          direction: direction,
        ),
      );
      final box = _box(tester);
      final prefix = tester.getRect(find.byKey(const Key('prefix')));
      final suffix = tester.getRect(find.byKey(const Key('suffix')));
      final text = _text(tester);
      expect(prefix.center.dy, box.center.dy);
      if (direction == TextDirection.ltr) {
        expect(prefix.left, box.left);
        expect(suffix.right, box.right);
        expect(text.left, prefix.right + 7);
        expect(text.right, suffix.left);
      } else {
        expect(prefix.right, box.right);
        expect(suffix.left, box.left);
        expect(text.right, prefix.left - 7);
        expect(text.left, suffix.right);
      }
    }
  });

  testWidgets('obscured text shows as dots on one line', (tester) async {
    await tester.pumpWidget(_app(const GlassTextField(obscureText: true)));
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.obscureText, isTrue);
    expect(editable.maxLines, 1);
  });

  testWidgets('a field of three lines grows by its lines and takes the '
      'multiline keyboard', (tester) async {
    await tester.pumpWidget(
      _app(const GlassTextField(minLines: 3, maxLines: 5)),
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.keyboardType, TextInputType.multiline);
    final box = _box(tester);
    final text = _text(tester);
    expect(text.top, box.top + 6);
    expect(text.bottom, box.bottom - 6);
    expect(box.height, greaterThan(3 * 20));
  });

  testWidgets('an error stands 6 under the field and says error', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    await tester.pumpWidget(
      _app(
        GlassTextField(
          errorText: 'Enter an email',
          statesController: states,
        ),
      ),
    );
    final box = _box(tester);
    final error = tester.getRect(find.text('Enter an email'));
    expect(error.top, box.bottom + 6);
    expect(error.left, box.left + 7);
    expect(states.value, contains(WidgetState.error));
    await tester.pumpWidget(_app(GlassTextField(statesController: states)));
    expect(find.text('Enter an email'), findsNothing);
    expect(states.value, isNot(contains(WidgetState.error)));
  });

  testWidgets('a disabled field takes no focus and no text', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(GlassTextField(focusNode: focus, enabled: false)),
    );
    await tester.tap(find.byKey(_field));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).readOnly,
      isTrue,
    );
  });

  testWidgets('the field is one Tab stop', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(_app(GlassTextField(focusNode: focus)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('screen readers read the label, then the placeholder', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const GlassTextField(semanticLabel: 'Email', placeholder: 'Ann')),
    );
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label == 'Email' &&
            node.hint == 'Ann' &&
            node.flagsCollection.isTextField,
      ),
      findsOne,
    );
    semantics.dispose();
  });
}
