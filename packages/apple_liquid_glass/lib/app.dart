/// The root widget of an app's glass, `GlassScope`: the theme, animated
/// when it changes, the renderer, liquid glass where the device draws it
/// well, and the frame rate fed by the app's scrolls, in one place.
///
/// For the app developer who wants the package's glass with one widget at
/// the root. It sits above every other library of the package and may
/// import all of them; nothing but the umbrella imports it, so the other
/// libraries never pick a glass renderer for the app. Without a scope,
/// controls draw flat.
///
/// It declares no control.
library;

export 'src/app/scope.dart' show GlassScope;
