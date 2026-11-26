import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

void main() {
  test('a group follows its link only while it is attached', () {
    final link = GlassGroupLink();
    addTearDown(link.dispose);
    final group = RenderLiquidGlassBlendGroup(
      renderLink: null,
      devicePixelRatio: 1,
      link: link,
      blend: 10,
    );
    expect(link.onMembershipChanged, isNull);
    group.attach(PipelineOwner());
    expect(link.onMembershipChanged, isNotNull);
    group
      ..detach()
      ..dispose();
    expect(link.onMembershipChanged, isNull);
    expect(link.onGlowChanged, isNull);
  });

  testWidgets('a group moved to another layer registers on that layer', (
    tester,
  ) async {
    final group = GlobalKey();
    Widget tree({required int on}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          for (final i in [0, 1])
            Expanded(
              child: LiquidGlassLayer(
                key: ValueKey('layer $i'),
                child: i == on
                    ? LiquidGlassBlendGroup(
                        key: group,
                        child: const LiquidGlass(
                          shape: LiquidOval(),
                          child: SizedBox(width: 40, height: 40),
                        ),
                      )
                    : const SizedBox(),
              ),
            ),
        ],
      ),
    );
    await tester.pumpWidget(tree(on: 0));
    await tester.pumpWidget(tree(on: 1));
    final render = group.currentContext!.findRenderObject()!;
    final blend = render is RenderLiquidGlassBlendGroup
        ? render
        : _below<RenderLiquidGlassBlendGroup>(render);
    expect(blend.renderLink, same(_above<LiquidGlassRenderObject>(blend).link));
  });
}

T _above<T extends RenderObject>(RenderObject node) {
  for (var at = node.parent; at != null; at = at.parent) {
    if (at is T) return at;
  }
  throw StateError('No $T above $node');
}

T _below<T extends RenderObject>(RenderObject node) {
  T? found;
  void visit(RenderObject child) {
    if (found != null) return;
    if (child is T) {
      found = child;
      return;
    }
    child.visitChildren(visit);
  }

  node.visitChildren(visit);
  return found ?? (throw StateError('No $T below $node'));
}
