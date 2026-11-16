/// The code that carries out a frame's plan: the render objects and layers
/// of glass, the reads and copies of the screen, the shaders and their
/// variants, the geometry computed on the GPU, the frost and the clips.
///
/// What a widget library builds on: `LiquidGlassBackdropFilterLayer` is a
/// backdrop filter drawn from a copy the frame's plan makes,
/// `LiquidGlassUnderlay` teaches glass how layer types of other packages
/// draw, so it can copy past them, and `LiquidGlassBentContent` paints what
/// lies over a glass shape bent at its rim, as a lifted iOS lens shows what
/// it selects. `debugPaintLiquidGlassGeometry` paints the geometry in place
/// of the glass and `debugGlassCopies` counts the copies of the screen.
///
/// It decides nothing the plan decides; it draws what the plan says. The
/// backdrop glass shows is never a frame late.
library;

export 'src/rendering/backdrop_filter_layer.dart'
    show LiquidGlassBackdropFilterHost, LiquidGlassBackdropFilterLayer;
export 'src/rendering/bent_content.dart'
    show LiquidGlassBentContent, LiquidGlassContentBend;
export 'src/rendering/debug.dart' show debugPaintLiquidGlassGeometry;
export 'src/rendering/liquid_glass_underlay.dart'
    show LiquidGlassLayerEffects, LiquidGlassUnderlay;
export 'src/rendering/read.dart' show debugGlassCopies;
