/// The seam for an app's own glass renderer: a `GlassRenderer` subclass
/// builds every surface, group and scroll edge from the details here and
/// is set in `GlassTheme` like the package's own.
library;

export 'src/renderer/renderer.dart'
    show
        GlassGroupDetails,
        GlassRenderer,
        GlassScrollEdgeDetails,
        GlassSurfaceDetails;
