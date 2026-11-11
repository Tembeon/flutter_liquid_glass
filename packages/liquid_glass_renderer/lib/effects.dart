/// Interactive effects on glass: `GlassGlow` lights the glass under a
/// finger inside a `GlassGlowLayer`, and `LiquidStretch` stretches glass as
/// it is dragged (`RawLiquidStretch` takes the drag from its caller).
///
/// For those who build their own interactive glass without a widget library
/// on top.
///
/// An effect reacts to touches and drives the glass it lies in; it draws no
/// glass of its own.
library;

export 'src/effects/glass_drag_builder.dart' show GestureMode;
export 'src/effects/glass_glow.dart' show GlassGlow, GlassGlowLayer;
export 'src/effects/stretch.dart'
    show LiquidStretch, OffsetResistanceExtension, RawLiquidStretch;
