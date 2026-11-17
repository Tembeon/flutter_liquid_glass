import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

const _shape = LiquidRoundedSuperellipse(radius: 12);

final _placements = <String, Widget Function(Widget)>{
  'on the layer': (child) => LiquidGlass(shape: _shape, child: child),
  'grouped': (child) => LiquidGlass.grouped(shape: _shape, child: child),
  'auto': (child) => LiquidGlass.auto(shape: _shape, child: child),
  'with its own layer': (child) =>
      LiquidGlass.withOwnLayer(shape: _shape, child: child),
};

final _places = <String, Widget Function(Widget)>{
  'beside other glass': (inner) => inner,
  'in a body': (inner) => LiquidGlass(shape: _shape, child: inner),
  'in a body in a blend group': (inner) => LiquidGlassBlendGroup(
    child: LiquidGlass.grouped(shape: _shape, child: inner),
  ),
};

Widget _scene(Widget Function(Widget) place, Widget inner) => Directionality(
  textDirection: TextDirection.ltr,
  child: LiquidGlassLayer(
    fake: true,
    child: Center(
      child: SizedBox(
        width: 200,
        height: 120,
        child: place(
          Center(child: SizedBox.square(dimension: 40, child: inner)),
        ),
      ),
    ),
  ),
);

bool _holds(LiquidGlassRenderObject layer, RenderLiquidGlass glass) =>
    layer.link.shapes.any(
      (shape) =>
          identical(shape, glass) ||
          shape is RenderLiquidGlassBlendGroup &&
              shape.link.shapes.contains(glass),
    );

void main() {
  for (final MapEntry(key: where, value: place) in _places.entries) {
    for (final MapEntry(key: how, value: glass) in _placements.entries) {
      final nests =
          where != 'beside other glass' || how == 'with its own layer';
      testWidgets('glass $how $where draws on '
          '${nests ? 'a layer of its own' : 'the outer layer'}', (
        tester,
      ) async {
        await tester.pumpWidget(_scene(place, glass(const SizedBox.expand())));
        await tester.pump();

        final layers = tester.allRenderObjects
            .whereType<LiquidGlassRenderObject>()
            .toSet()
            .toList();
        final inner = tester.allRenderObjects
            .whereType<RenderLiquidGlass>()
            .toSet()
            .singleWhere((glass) => glass.size == const Size.square(40));
        final outer = layers.first;
        expect(layers, hasLength(nests ? 2 : 1));
        expect(_holds(outer, inner), !nests);
        expect(layers.where((layer) => _holds(layer, inner)), hasLength(1));
      });
    }
  }
}
