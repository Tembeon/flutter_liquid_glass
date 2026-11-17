/// The plan of a frame of glass: which copies of the screen its glass reads,
/// at what size and frost, which glass shares them, which geometry it takes,
/// and how many passes that costs.
///
/// The plan is a pure function of what the frame's glass answered about
/// itself, checked without a GPU or a layer tree: beyond the filter a
/// `LiquidGlassBackdropFrost` builds, it touches nothing of the engine.
///
/// What an app sees of it: `GlassFrameReport` tells what a frame's glass
/// took, for budgets held in tests and for tuning, and `debugDumpGlassPlan`
/// prints it. `LiquidGlassBackdropFrost` says how a backdrop filter is
/// frosted and `FrostBandPaint` what a scroll edge paints over its frost.
library;

export 'src/plan/backdrop_frost.dart' show LiquidGlassBackdropFrost;
export 'src/plan/band_look.dart' show FrostBandPaint;
export 'src/plan/frame_report.dart'
    show GlassFrameReport, GlassReadReport, GlassReadSource, debugDumpGlassPlan;
