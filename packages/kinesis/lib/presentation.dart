/// Everything that appears above the screen: the presentation engine
/// (`Presentation`), its three shells (`PresentationRoute`,
/// `PresentationPageRoute`, `PresentationPortal`) and the source an overlay
/// grows out of (`MotionSource`).
///
/// For the author of any overlay: a menu, a sheet, an alert or a panel of
/// one's own.
///
/// It promises the focus moved in at the open, Tab kept inside a modal
/// presentation (a page keeps its navigator's rule) and the focus handed
/// back to the opener however the presentation goes, Escape,
/// the Back button and gesture (Android's predictive back drives a route
/// whose motion is `PredictiveBack`), a barrier that hides the screen from the
/// screen reader in a route and, labelled by the presenter, offers the
/// dismissal after the content, an overlay that announces itself to the
/// screen reader as a route of its own with the label and role the
/// presenter gives, and an overlay that is inert while it closes: no
/// touches, no focus, no semantics.
///
/// It never knows how an overlay looks or which spring it moves on.
library;

export 'src/presentation/level.dart'
    show PresentationContext, PresentationLevel, showPresentation;
export 'src/presentation/portal.dart'
    show PresentationPortal, PresentationPortalController;
export 'src/presentation/presentation.dart'
    show Presentation, PresentationEnvironment, PresentationHandle;
export 'src/presentation/route.dart'
    show PresentationPageRoute, PresentationRoute;
export 'src/presentation/source.dart' show MotionSource, MotionSourceBox;
