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
/// For a renderer, `compile` takes a `Scenery` (the frame's sites, each a
/// `SiteFacts` holding the `SiteAsk` its glass made) with the `Ledger` kept
/// between frames, the `Prices` and the `Policy`, and returns the `Plan`: a
/// `Fate` for every site and the frame's `Read`s, each with the
/// `ReadGeometry` of its copy on a `Lattice`. `GlassWork` counts what the
/// renderer did beyond the plan for the frame's report.
///
/// For those who develop the renderer, and for an app that holds its glass
/// to a budget.
///
/// It creates no engine layer and touches no shader or texture: the
/// rendering library carries the plan out.
library;

export 'src/composer/backdrop_frost.dart' show LiquidGlassBackdropFrost;
export 'src/composer/band_look.dart' show BandLook, FrostBandPaint;
export 'src/composer/frame_report.dart'
    show
        GlassFrameReport,
        GlassReadReport,
        GlassReadSource,
        GlassWork,
        debugDumpGlassPlan;
export 'src/composer/geometry.dart'
    show
        CopyNeed,
        ImpellerLayers,
        Lattice,
        ReadGeometry,
        ceilPixels,
        frostLatticeWidest,
        frostSquareWidest;
export 'src/composer/geometry_renderer_limits.dart'
    show geometryMaxShapesPerDraw;
export 'src/composer/plan.dart'
    show
        BandRole,
        ComputedShape,
        DirtyLog,
        Fate,
        Follows,
        GeometryKind,
        GlassBody,
        GlassRole,
        Hidden,
        ImageRead,
        Leads,
        Ledger,
        LedgerEdits,
        LiveRead,
        Look,
        NoJoin,
        OwnAtlas,
        PageFilter,
        Plan,
        Policy,
        Prices,
        Read,
        ReadLimit,
        ReadMemo,
        ReadSource,
        SceneRead,
        Scenery,
        SharedAtlas,
        SiteAsk,
        SiteFacts,
        SiteRole,
        StateChain,
        compile,
        geometryKindOf;
