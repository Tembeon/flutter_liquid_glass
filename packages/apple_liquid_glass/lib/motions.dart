/// The measured laws of iOS motion: how the switch, slider, lens, sheet,
/// bars, menus, alert, search and page zoom move, as pure classes on
/// kinesis's `Motion`, and the bar and menu layouts as plain math.
///
/// For the controls of this package, and for the tests that replay
/// recordings from an iPhone against the same laws. Its public names
/// today are the values a control's parameters take: `GlassSheetDetent`
/// and `GlassTabBarMinimizeBehavior`; the laws themselves are the
/// package's own.
///
/// It promises that a number in a law carries its source, a measurement on
/// the device or UIKit's tuning, in its dartdoc.
///
/// It never imports Flutter's widgets or rendering libraries, and never
/// decides what is drawn.
library;

export 'src/motions/sheet_motion.dart' show GlassSheetDetent;
export 'src/motions/tab_minimize.dart' show GlassTabBarMinimizeBehavior;
