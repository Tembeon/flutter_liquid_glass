import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/src/screen/resolve.dart';
import 'package:kinesis/src/transaction.dart';

final List<String> _log = [];

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe(this.name, {this.onResolve, super.child});

  final String name;
  final void Function(_RenderProbe probe)? onResolve;

  @override
  _RenderProbe createRenderObject(BuildContext context) =>
      _RenderProbe(name, onResolve);

  @override
  void updateRenderObject(BuildContext context, _RenderProbe renderObject) {
    renderObject.onResolve = onResolve;
    renderObject.markNeedsLayout();
  }
}

class _RenderProbe extends RenderProxyBox with MotionResolveHost {
  _RenderProbe(this.name, this.onResolve);

  final String name;
  void Function(_RenderProbe probe)? onResolve;

  @override
  void performLayout() {
    super.performLayout();
    _log.add('layout $name');
    scheduleResolve();
  }

  @override
  void resolve() {
    _log.add('resolve $name');
    onResolve?.call(this);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _log.add('paint $name');
    super.paint(context, offset);
  }
}

class _Follower extends LeafRenderObjectWidget {
  const _Follower(this.value);

  final MotionValue<double> value;

  @override
  _RenderFollower createRenderObject(BuildContext context) =>
      _RenderFollower(value);
}

class _RenderFollower extends RenderBox {
  _RenderFollower(this.value);

  final MotionValue<double> value;
  final List<double> painted = [];

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    value.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    value.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() => size = constraints.smallest;

  @override
  void paint(PaintingContext context, Offset offset) {
    painted.add(value.value);
  }
}

int _children(PipelineOwner owner) {
  var count = 0;
  owner.visitChildren((_) => count++);
  return count;
}

void main() {
  setUp(() {
    MotionClock.debugReset();
    _log.clear();
  });

  testWidgets('resolve runs after the whole view is laid out and before '
      'any paint', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            _Probe('a', child: SizedBox(height: 10)),
            _Probe('b', child: SizedBox(height: 20)),
          ],
        ),
      ),
    );
    final resolved = _log.indexOf('resolve a');
    expect(resolved, greaterThan(_log.lastIndexOf('layout b')));
    expect(resolved, lessThan(_log.indexOf('paint a')));
    expect(_log.indexOf('resolve b'), lessThan(_log.indexOf('paint a')));
  });

  testWidgets('a value changed in resolve paints in the same frame', (
    tester,
  ) async {
    final value = MotionValue<double>(0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            _Probe('a', onResolve: (_) => value.snap(value.clock.now, 7)),
            _Follower(value),
          ],
        ),
      ),
    );
    final follower = tester.renderObject<_RenderFollower>(
      find.byType(_Follower),
    );
    expect(follower.painted.last, 7);
  });

  testWidgets('a change in resolve reaches render listeners at once and '
      'widget listeners in the next frame', (tester) async {
    final value = MotionValue<double>(0);
    final heard = <String>[];
    value.addRenderListener(() => heard.add('render ${value.value}'));
    value.addListener(() => heard.add('widget ${value.value}'));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _Probe(
          'a',
          onResolve: (_) => value.snap(value.clock.now, 3),
        ),
      ),
    );
    expect(heard, ['render 3.0']);
    await tester.pump(const Duration(milliseconds: 16));
    expect(heard, ['render 3.0', 'render 3.0', 'widget 3.0']);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('marking layout in resolve asserts', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            _Probe('a', onResolve: (probe) => probe.markNeedsLayout()),
          ],
        ),
      ),
    );
    // Flutter rejects a layout mark while its layout phase runs.
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('the resolve phase leaves the view with its last host', (
    tester,
  ) async {
    await tester.pumpWidget(const _Probe('a'));
    final owner = tester.renderObject(find.byType(_Probe)).owner!;
    expect(_children(owner), 1);
    await tester.pumpWidget(const SizedBox());
    expect(_children(owner), 0);
  });

  testWidgets('a transaction belongs to the frame it closes before', (
    tester,
  ) async {
    await tester.pumpWidget(const _Probe('a'));
    withSpring(Spring.snappy, () {});
    expect(MotionTransaction.layout?.spring, Spring.snappy);
    withSpring(Spring.snappy, () {}, tracking: true);
    expect(MotionTransaction.layout?.spring, Spring.snappy);
    await tester.pump();
    expect(MotionTransaction.layout, isNull);
  });
}
