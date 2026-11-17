/// The plan of a frame of glass: which copies of the screen its glass reads,
/// at what size and frost, which geometry it takes, and how many passes that
/// costs.
///
/// Every decision about copies, frost, geometry and passes is made in the
/// plan and only there. The plan is a pure function of what the frame's
/// glass answered about itself, so it is checked without a GPU or a layer
/// tree.
///
/// What an app sees of it: `GlassFrameReport` tells what a frame's glass
/// took, for budgets held in tests and for tuning, and `debugDumpGlassPlan`
/// prints it. `LiquidGlassBackdropFrost` says how a backdrop filter is
/// frosted and `FrostBandPaint` what a scroll edge paints over its frost.
///
/// It creates no engine layer and touches no shader or texture: the
/// rendering library carries the plan out.
library;

export 'src/plan/backdrop_frost.dart' show LiquidGlassBackdropFrost;
export 'src/plan/band_look.dart' show FrostBandPaint;
export 'src/plan/frame_report.dart'
    show GlassFrameReport, GlassReadReport, GlassReadSource, debugDumpGlassPlan;
