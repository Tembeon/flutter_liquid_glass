/// Everything that appears above the screen: the presentation engine
/// (`Presentation`), its three shells (`PresentationRoute`,
/// `PresentationPageRoute`, `PresentationPortal`) and the source an overlay
/// grows out of (`MotionSource`).
///
/// For the author of any overlay: a menu, a sheet, an alert or a panel of
/// one's own.
///
/// It promises a focus trap and focus handed back to the opener, Escape,
/// the Back button and gesture, a barrier that hides the screen from the
/// screen reader, an overlay that announces itself to the screen reader,
/// and an overlay that is inert while it closes: no touches, no focus, no
/// semantics.
///
/// It never knows how an overlay looks or which spring it moves on.
library;

export 'src/presentation/level.dart'
    show PresentationContext, PresentationLevel, showPresentation;
export 'src/presentation/portal.dart'
    show PresentationPortal, PresentationPortalController;
export 'src/presentation/presentation.dart'
    show Presentation, PresentationEnvironment, PresentationHandle;
export 'src/presentation/presented.dart' show DismissPolicy, Presented;
export 'src/presentation/route.dart'
    show DismissTrigger, PresentationPageRoute, PresentationRoute;
export 'src/presentation/source.dart'
    show MotionSource, MotionSourceBox, SourceGeometry, Sourced;
