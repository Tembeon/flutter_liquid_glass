/// Liquid glass as widgets: `LiquidGlass` puts a shape of glass in the tree,
/// `LiquidGlassLayer` lets glass share one layer and its settings,
/// `LiquidGlassBlendGroup` makes nearby glass blend into one surface, and
/// `FakeGlass` gives a cheaper look drawn with backdrop filters.
/// `LiquidGlassVisibility` fades glass in and out, `precacheLiquidGlass`
/// loads the shaders before the first frame, `liquidGlassSupport` says
/// whether the device draws full glass, `LiquidGlassReportOverlay` shows
/// what each frame's glass took over the app, and
/// `installLiquidGlassComposer` lets glass share copies of what lies under
/// it, as the glass widgets do for every view.
///
/// For app developers who want glass.
///
/// Glass is cheap out of the box: an app optimizes nothing by hand to keep
/// its frames.
library;

export 'src/widgets/composer_install.dart' show installLiquidGlassComposer;
export 'src/widgets/fake_glass.dart' show FakeGlass;
export 'src/widgets/liquid_glass.dart' show LiquidGlass;
export 'src/widgets/liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'src/widgets/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'src/widgets/liquid_glass_precache.dart'
    show
        debugOverrideLiquidGlassSupport,
        liquidGlassSupport,
        precacheLiquidGlass;
export 'src/widgets/liquid_glass_report_overlay.dart'
    show LiquidGlassReportOverlay;
export 'src/widgets/liquid_glass_visibility.dart' show LiquidGlassVisibility;
