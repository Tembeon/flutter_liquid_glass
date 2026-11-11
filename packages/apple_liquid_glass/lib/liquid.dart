/// The liquid glass renderer and the renderers built on it: the fake glass
/// for platforms without real glass and the adaptive choice between them,
/// with the scroll edge and the layers they draw under glass.
///
/// For the app that picks a renderer or lets its user pick one. An app
/// chooses them through `GlassRenderer.liquid()`, `.fake()` and
/// `.adaptive(...)`; this library publishes what the liquid renderer
/// reports of a frame for debugging (`GlassFrameReport`,
/// `GlassPlanOverlay`, `debugDumpGlassPlan`).
///
/// It declares no control.
library;

export 'src/liquid/frame_report.dart'
    show
        GlassFrameReport,
        GlassPlanOverlay,
        GlassReadReport,
        GlassReadSource,
        debugDumpGlassPlan;
