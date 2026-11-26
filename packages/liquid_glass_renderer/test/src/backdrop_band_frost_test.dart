import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';

class _HardBand extends LeafRenderObjectWidget {
  const _HardBand();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHardBand();
}

class _RenderHardBand extends RenderBox with LiquidGlassBackdropFilterHost {
  final layerHandle = LayerHandle<LiquidGlassBackdropFilterLayer>();

  @override
  LiquidGlassBackdropFilterLayer? get backdropFilterLayer => layerHandle.layer;

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer = layerHandle.layer ??= LiquidGlassBackdropFilterLayer(
      filter: const LiquidGlassFrostBand.hard(
        sigma: 2,
        edge: AxisDirection.up,
        fade: Color(0x80FFFFFF),
        line: Color(0x1A000000),
        saturation: 1.25,
        lighten: 0.03,
      ),
      clip: offset & size,
    )..clip = offset & size;
    context.pushLayer(layer, (_, _) {}, offset);
  }

  @override
  void dispose() {
    layerHandle.layer = null;
    super.dispose();
  }
}

void main() {
  testWidgets('a band frosts at half resolution where that costs a little '
      'more blur, at the pixel ratio of its view', (tester) async {
    addTearDown(tester.view.reset);
    Future<LiquidGlassBackdropFilterLayer> band(double ratio) async {
      tester.view.devicePixelRatio = ratio;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 300, height: 60, child: _HardBand()),
          ),
        ),
      );
      return tester
          .renderObject<_RenderHardBand>(find.byType(_HardBand))
          .layerHandle
          .layer!;
    }

    final pixel = await band(_pixel6aDevicePixelRatio);
    expect((pixel.filter as LiquidGlassFrostBand).sigma, 2);
    expect(pixel.frost!.sigma, greaterThan(2.15));
    expect(pixel.frost!.sigma, lessThan(2 * 1.12));
    expect(identical(pixel.imageFilter, pixel.frost!.filter), isTrue);

    final iphone = await band(3);
    expect(iphone.frost!.sigma, 2);
  });
}

const _pixel6aDevicePixelRatio = 2.625;
