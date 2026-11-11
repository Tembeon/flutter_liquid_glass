/// The plan of a frame of glass: which copies of the screen its glass reads,
/// at what size and frost, which geometry it takes, and how many passes that
/// costs.
///
/// Every decision about copies, frost, geometry and passes is made in the
/// plan and only there. The plan is a pure function of what the frame's
/// glass answered about itself, so it is checked without a GPU or a layer
/// tree. `GlassFrameReport` tells an app what a frame's glass took, for
/// budgets held in tests and for tuning; `debugDumpGlassPlan` prints it.
/// `LiquidGlassBackdropFrost` says how a backdrop filter is frosted and
/// `FrostBandPaint` what a scroll edge paints over its frost.
///
/// For those who develop the renderer, and for an app that holds its glass
/// to a budget.
///
/// It creates no engine layer and touches no shader or texture: the
/// rendering library carries the plan out.
library;

export 'src/composer/backdrop_frost.dart' show LiquidGlassBackdropFrost;
export 'src/composer/band_look.dart' show FrostBandPaint;
export 'src/composer/frame_report.dart'
    show GlassFrameReport, GlassReadReport, GlassReadSource, debugDumpGlassPlan;
