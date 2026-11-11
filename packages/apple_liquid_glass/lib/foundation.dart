/// The iOS design language as values, for anyone who wants iOS's colours
/// and type in their own widgets.
///
/// Colours that resolve against the brightness, contrast and interface
/// level around them (`GlassDynamicColor`, the palette `GlassColors`); text
/// roles and their typography (`GlassTextRole`, `GlassDefaultTextStyle`);
/// the traits of the environment (`GlassTraits`); the values that describe
/// a glass body, which name no renderer: its material (`Glass`,
/// `GlassRole`), shape (`GlassShape`), free outline (`GlassOutline`),
/// touch glow (`GlassTouchGlow`) and one frame of it (`GlassFrame`); and
/// the theme (`GlassTheme`, `GlassThemeData`, `GlassColorScheme`,
/// `AnimatedGlassTheme`).
///
/// It promises that the traits report what Flutter reports (contrast, bold
/// text) and Reduce Motion through kinesis's one channel,
/// `MotionTraitsOverride`. Flutter reports no Reduce Transparency, so an
/// app gives it, and the other traits Flutter does not know, with
/// `GlassTraitsOverride`.
///
/// It declares no control and no presentation.
library;

export 'src/foundation/colors.dart' show GlassColors, GlassDynamicColor;
export 'src/foundation/frame.dart' show GlassFrame;
export 'src/foundation/glass.dart' show Glass, GlassRole;
export 'src/foundation/outline.dart' show GlassOutline;
export 'src/foundation/shape.dart'
    show GlassOval, GlassRoundedRect, GlassShape, GlassSuperellipse;
export 'src/foundation/theme.dart'
    show AnimatedGlassTheme, GlassColorScheme, GlassTheme, GlassThemeData;
export 'src/foundation/touch_glow.dart' show GlassTouchGlow;
export 'src/foundation/traits.dart'
    show GlassInterfaceLevel, GlassTraits, GlassTraitsOverride;
export 'src/foundation/typography.dart'
    show GlassDefaultTextStyle, GlassTextRole;
