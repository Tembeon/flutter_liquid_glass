/// A way to say "here is a body of glass": `GlassSurface` and its shape
/// (`GlassShape`), outline (`GlassOutline`), material (`Glass`,
/// `GlassRole`), clip (`GlassClip`), fusion group (`GlassGroup`,
/// `GlassMerge`) and the solid backdrop that stands in for glass
/// (`GlassSolidBackdrop`); and the renderer seam, `GlassRenderer`, with
/// the details it builds every surface, group and scroll edge from.
///
/// For the app developer who makes glass bodies of their own, such as a
/// card or a panel, that follow the renderer the app picks, and for the
/// author of a renderer, who subclasses `GlassRenderer` and sets it in
/// `GlassTheme` like the package's own.
///
/// It promises that a surface describes what it needs and the renderer
/// decides how it is drawn: `GlassRenderer.flat()`, `.liquid()`, `.fake()`
/// and `.adaptive(...)` all build from the same details.
///
/// It declares no control.
library;

export 'src/surfaces/clip.dart' show GlassClip;
export 'src/surfaces/glass.dart' show Glass, GlassRole;
export 'src/surfaces/group.dart' show GlassGroup, GlassMerge;
export 'src/surfaces/outline.dart' show GlassOutline;
export 'src/surfaces/renderer.dart'
    show
        GlassGroupDetails,
        GlassRenderer,
        GlassScrollEdgeDetails,
        GlassSurfaceDetails;
export 'src/surfaces/shape.dart' show GlassShape;
export 'src/surfaces/solid_backdrop.dart' show GlassSolidBackdrop;
export 'src/surfaces/surface.dart' show GlassSurface;
