/// The liquid glass renderer and the renderers built on it, and the only
/// library of the package that knows the glass package
/// `liquid_glass_renderer`.
///
/// For the app that picks a renderer or lets its user pick one:
/// `LiquidGlassRenderer` (real glass), `FakeGlassRenderer` (blurred and
/// lit, no refraction) and `AdaptiveGlassRenderer` (real glass where the
/// device draws it well, fake glass elsewhere and on the web), set in a
/// `GlassRendererScope`, and `precacheGlass`, which readies the glass
/// before the first frame. It also publishes what the liquid renderer
/// reports of a frame for debugging (`GlassFrameReport`,
/// `GlassPlanOverlay`, `debugDumpGlassPlan`).
///
/// It declares no control, and no renderer here knows a control by name:
/// what a body needs arrives as data in its description.
library;

export 'src/liquid/adaptive.dart' show AdaptiveGlassRenderer, precacheGlass;
export 'src/liquid/frame_report.dart'
    show
        GlassFrameReport,
        GlassPlanOverlay,
        GlassReadReport,
        GlassReadSource,
        debugDumpGlassPlan;
export 'src/liquid/liquid.dart' show FakeGlassRenderer, LiquidGlassRenderer;
