/// The code that carries out a frame's plan: the render objects and layers
/// of glass, the reads and copies of the screen, the shaders and their
/// variants, the geometry computed on the GPU, the frost and the clips.
///
/// `LiquidGlassLayerFrame` is what a live layer shades with,
/// `LiquidGlassBackdropFilterLayer` a backdrop filter drawn from a copy the
/// frame's plan makes, and `LiquidGlassUnderlay` teaches glass how layer
/// types of other packages draw, so it can copy past them.
/// `debugPaintLiquidGlassGeometry` paints the geometry in place of the glass.
/// `RenderLiquidGlassContent` holds the child of one glass shape and the
/// light a touch raises under it.
///
/// For those who write their own glass render object at a low level.
///
/// It decides nothing the plan decides; it draws what the plan says. The
/// backdrop glass shows is never a frame late.
library;

export 'src/rendering/backdrop_filter_layer.dart'
    show LiquidGlassBackdropFilterLayer;
export 'src/rendering/debug.dart' show debugPaintLiquidGlassGeometry;
export 'src/rendering/glass_content.dart' show RenderLiquidGlassContent;
export 'src/rendering/liquid_glass_layer.dart' show LiquidGlassLayerFrame;
export 'src/rendering/liquid_glass_underlay.dart'
    show LiquidGlassLayerEffects, LiquidGlassUnderlay;
