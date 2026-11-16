import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const shape = LiquidRoundedSuperellipse(borderRadius: 20);
final key = BackdropKey();

void debugGeometry() {
  debugPaintLiquidGlassGeometry = true;
}

LiquidGlassSettings settings(BuildContext context) =>
    LiquidGlassSettings.of(context);

Widget backdropGroups() {
  return LiquidGlassLayer(
    useBackdropGroup: true,
    backdropKey: key,
    child: Column(
      children: [
        LiquidGlass.auto(
          shape: shape,
          useBackdropGroup: true,
          backdropKey: key,
          child: const SizedBox(),
        ),
        LiquidGlass.withOwnLayer(
          shape: shape,
          useBackdropGroup: true,
          child: const SizedBox(),
        ),
        FakeGlass(shape: shape, backdropKey: key, child: const SizedBox()),
      ],
    ),
  );
}
