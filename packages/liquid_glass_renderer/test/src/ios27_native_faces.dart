import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

const nativeFaceKey = ValueKey('face');
const nativeFaceView = Size(260, 190);

// The face of native iOS 27 glass at its center over a plain color:
// captures of `glassEffect` and `.buttonStyle(.glass)` on the iOS 27
// simulator for dark glass, and on an iPhone 16 Pro, whose slider is at 0.1,
// for light glass over anything but black (the simulator caps the luminance
// of light glass).
const nativePanel = Size(210, 150);
const nativeToolbar = Size(224, 94);
const nativeControl = Size(148, 63);
const nativeFaces = <(Brightness, Size, double, Color, Color)>[
  (Brightness.dark, nativePanel, 0, Color(0xFF000000), Color(0xFF202020)),
  (Brightness.dark, nativePanel, 0, Color(0xFF333333), Color(0xFF494949)),
  (Brightness.dark, nativePanel, 0, Color(0xFF737373), Color(0xFF747474)),
  (Brightness.dark, nativePanel, 0, Color(0xFF999999), Color(0xFF858585)),
  (Brightness.dark, nativePanel, 0, Color(0xFFDDDDDD), Color(0xFF939393)),
  (Brightness.dark, nativePanel, 0, Color(0xFFFFFFFF), Color(0xFF929292)),
  (Brightness.dark, nativePanel, 0, Color(0xFFEF4444), Color(0xFFFE4747)),
  (Brightness.dark, nativePanel, 0, Color(0xFF22C55E), Color(0xFF12AE4B)),
  (Brightness.dark, nativePanel, 0, Color(0xFF3B82F6), Color(0xFF367FF6)),
  (Brightness.dark, nativePanel, 0.5, Color(0xFFFFFFFF), Color(0xFF797979)),
  (Brightness.dark, nativePanel, 0.5, Color(0xFF737373), Color(0xFF6F6F6F)),
  (Brightness.dark, nativePanel, 0.5, Color(0xFFEF4444), Color(0xFFF44444)),
  (Brightness.dark, nativePanel, 1, Color(0xFFFFFFFF), Color(0xFF555555)),
  (Brightness.dark, nativePanel, 1, Color(0xFF737373), Color(0xFF494949)),
  (Brightness.dark, nativePanel, 1, Color(0xFF3B82F6), Color(0xFF264F92)),
  (Brightness.dark, nativeToolbar, 0, Color(0xFFFFFFFF), Color(0xFF9C9C9C)),
  (Brightness.dark, nativeToolbar, 0.5, Color(0xFFFFFFFF), Color(0xFF898989)),
  (Brightness.dark, nativeToolbar, 1, Color(0xFFFFFFFF), Color(0xFF575757)),
  (Brightness.dark, nativeControl, 0, Color(0xFFFFFFFF), Color(0xFFB9B9B9)),
  (Brightness.dark, nativeControl, 0.5, Color(0xFFFFFFFF), Color(0xFFB9B9B9)),
  (Brightness.dark, nativeControl, 1, Color(0xFFFFFFFF), Color(0xFF6C6C6C)),
  (Brightness.light, nativePanel, 0.1, Color(0xFF000000), Color(0xFF6E6E6E)),
  (Brightness.light, nativePanel, 0.1, Color(0xFF333333), Color(0xFF8F8F8F)),
  (Brightness.light, nativePanel, 0.1, Color(0xFF737373), Color(0xFFB8B8B8)),
  (Brightness.light, nativePanel, 0.1, Color(0xFF999999), Color(0xFFD0D0D0)),
  (Brightness.light, nativePanel, 0.1, Color(0xFFDDDDDD), Color(0xFFF5F5F5)),
  (Brightness.light, nativePanel, 0.1, Color(0xFFFFFFFF), Color(0xFFFFFFFF)),
  (Brightness.light, nativePanel, 0.1, Color(0xFFEF4444), Color(0xFFFF8888)),
  (Brightness.light, nativePanel, 0.1, Color(0xFF22C55E), Color(0xFF45FF8B)),
  (Brightness.light, nativePanel, 0.1, Color(0xFF3B82F6), Color(0xFF73C6FF)),
  (Brightness.light, nativeControl, 0, Color(0xFF000000), Color(0xFF666666)),
  (Brightness.light, nativeControl, 0.5, Color(0xFF000000), Color(0xFF858585)),
  (Brightness.light, nativeControl, 1, Color(0xFF000000), Color(0xFFB3B3B3)),
];

// The same under a tint, on the simulator: `.tint(#007AFF)` at full and at
// 40 % opacity on a regular panel, and at full opacity on a clear one, where
// both appearances draw alike.
const nativeBlue = Color(0xFF007AFF);
const nativeBlue40 = Color(0x66007AFF);
const nativeTintedFaces = <(Brightness?, Color, Color, Color)>[
  (Brightness.light, nativeBlue, Color(0xFF000000), Color(0xFF0057C2)),
  (Brightness.light, nativeBlue, Color(0xFF737373), Color(0xFF0069E1)),
  (Brightness.light, nativeBlue, Color(0xFFFFFFFF), Color(0xFF007AFF)),
  (Brightness.light, nativeBlue, Color(0xFFEF4444), Color(0xFF0063D7)),
  (Brightness.light, nativeBlue40, Color(0xFF000000), Color(0xFF3E618C)),
  (Brightness.light, nativeBlue40, Color(0xFF333333), Color(0xFF5278A5)),
  (Brightness.light, nativeBlue40, Color(0xFF737373), Color(0xFF6B95C5)),
  (Brightness.light, nativeBlue40, Color(0xFF3B82F6), Color(0xFF419DF3)),
  (Brightness.light, nativeBlue40, Color(0xFFEF4444), Color(0xFF9975A3)),
  (Brightness.light, nativeBlue40, Color(0xFFF97316), Color(0xFF998E7D)),
  (Brightness.dark, nativeBlue, Color(0xFF000000), Color(0xFF0079FF)),
  (Brightness.dark, nativeBlue, Color(0xFF737373), Color(0xFF1081FC)),
  (Brightness.dark, nativeBlue, Color(0xFFFFFFFF), Color(0xFF1684FB)),
  (Brightness.dark, nativeBlue, Color(0xFFF97316), Color(0xFF1282FC)),
  (Brightness.dark, nativeBlue40, Color(0xFF000000), Color(0xFF134479)),
  (Brightness.dark, nativeBlue40, Color(0xFF333333), Color(0xFF2F5E91)),
  (Brightness.dark, nativeBlue40, Color(0xFF737373), Color(0xFF4C7AAB)),
  (Brightness.dark, nativeBlue40, Color(0xFFFFFFFF), Color(0xFF618DBC)),
  (Brightness.dark, nativeBlue40, Color(0xFF3B82F6), Color(0xFF2780F9)),
  (Brightness.dark, nativeBlue40, Color(0xFFEF4444), Color(0xFF9E5E90)),
  (Brightness.dark, nativeBlue40, Color(0xFFF97316), Color(0xFF96736C)),
  (null, nativeBlue, Color(0xFF000000), Color(0xFF0047A6)),
  (null, nativeBlue, Color(0xFF737373), Color(0xFF0060D2)),
  (null, nativeBlue, Color(0xFFDDDDDD), Color(0xFF0077FA)),
  (null, nativeBlue, Color(0xFFEF4444), Color(0xFF005DCC)),
];

/// Every case of [nativeFaces] and of [nativeTintedFaces], the tinted
/// ones on a panel at slider 0: brightness (null for clear glass), size,
/// slider, page, the native face and the tint.
final nativeFaceCases = [
  for (final (brightness, size, slider, page, native) in nativeFaces)
    (brightness as Brightness?, size, slider, page, native, null as Color?),
  for (final (brightness, tint, page, native) in nativeTintedFaces)
    (brightness, nativePanel, 0.0, page, native, tint as Color?),
];

Widget nativeFaceScene(
  Brightness? brightness,
  Size size,
  double slider,
  Color page, {
  Color? tint,
  bool solid = true,
}) => nativeFaceGlass(
  brightness == null
      ? LiquidGlassSettings.ios27Clear(sliderPosition: slider)
      : LiquidGlassSettings.ios27Regular(
          brightness: brightness,
          sliderPosition: slider,
        ),
  switch ((brightness, tint)) {
    (null, null) => const LiquidGlassAppearance.ios27Clear(),
    (null, final tint?) => LiquidGlassAppearance.ios27Clear(tint: tint),
    (final brightness?, null) => LiquidGlassAppearance.ios27Regular(
      brightness: brightness,
    ),
    (final brightness?, final tint?) => LiquidGlassAppearance.ios27Regular(
      brightness: brightness,
      tint: tint,
    ),
  },
  size,
  page,
  solid: solid,
);

/// Glass of [size] in [appearance] centred over [page]: over a solid
/// backdrop of the page where [solid], else reading what lies under it.
Widget nativeFaceGlass(
  LiquidGlassSettings settings,
  LiquidGlassAppearance appearance,
  Size size,
  Color page, {
  bool solid = true,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: nativeFaceKey,
    child: ColoredBox(
      color: page,
      child: Center(
        child: LiquidGlassLayer(
          settings: settings,
          // Painted without a backdrop filter, so flutter_tester draws
          // every render in this process, not only the first.
          backdrop: solid
              ? LiquidGlassBackdrop.solid(page)
              : const LiquidGlassBackdrop.read(),
          child: LiquidGlass(
            shape: const LiquidRoundedSuperellipse(radius: 30),
            appearance: appearance,
            child: SizedBox.fromSize(size: size),
          ),
        ),
      ),
    ),
  ),
);
