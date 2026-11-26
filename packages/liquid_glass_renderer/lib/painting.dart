/// Liquid glass described as values: its shape, its look and how it meets
/// what lies behind it.
///
/// `LiquidShape` and its kinds give the outline, `LiquidGlassSettings` the
/// optics (the lens and the blur), `LiquidGlassAppearance` and
/// `LiquidGlassColorModel` the color, the material and the lit rim,
/// `LiquidGlassMaterial` settings, an appearance and shadows that belong
/// together, `LiquidGlassBackdrop` where the
/// glass takes what it shows through, `LiquidGlassBackdropFilter` what a
/// backdrop filter layer of the renderer does to what lies under it (a
/// frost, or the band of a scroll edge), `LiquidGlassField` the outline of a
/// body its owner computed itself, `LiquidGlassGlow` the light a finger
/// raises on a shape, `LiquidGlassShadow` a shadow a shape casts and
/// `LiquidGlassSilhouette` the outline glass casts its shadows by,
/// `LiquidGlassContentBend` how a shape bends what is drawn over
/// it at its rim, `LiquidGlassShapeFrame` one frame of a live shape and
/// `LiquidGlassBody` where that frame draws its body.
/// `LiquidGlassSupport` says whether the device draws full glass, and on
/// what GPU.
///
/// For anyone who describes glass without drawing it, such as a widget
/// library that maps its own shapes and materials onto glass.
///
/// Its types are immutable values. It creates no render object, no layer and
/// no shader: the libraries above it draw what these values describe. A
/// shape fills itself and glass casts its shadows on a canvas, so a widget
/// library paints a body as the renderer does.
library;

export 'src/painting/lens_settings.dart' show LensSettings;
export 'src/painting/liquid_glass_appearance.dart' show LiquidGlassAppearance;
export 'src/painting/liquid_glass_backdrop.dart'
    show LiquidGlassBackdrop, LiquidGlassReadBackdrop, LiquidGlassSolidBackdrop;
export 'src/painting/liquid_glass_backdrop_filter.dart'
    show
        LiquidGlassBackdropFilter,
        LiquidGlassBackdropFrost,
        LiquidGlassFrostBand,
        LiquidGlassHardFrostBand,
        LiquidGlassImageBackdropFilter,
        LiquidGlassSoftFrostBand;
export 'src/painting/liquid_glass_body.dart' show LiquidGlassBody;
export 'src/painting/liquid_glass_color_model.dart'
    show
        LiquidGlassColorModel,
        LiquidGlassDirectColorModel,
        LiquidGlassIos27ClearColorModel,
        LiquidGlassIos27RegularColorModel;
export 'src/painting/liquid_glass_content_bend.dart'
    show LiquidGlassContentBend;
export 'src/painting/liquid_glass_field.dart' show LiquidGlassField;
export 'src/painting/liquid_glass_glow.dart' show LiquidGlassGlow;
export 'src/painting/liquid_glass_layer_frame.dart' show LiquidGlassLayerFrame;
export 'src/painting/liquid_glass_material.dart' show LiquidGlassMaterial;
export 'src/painting/liquid_glass_settings.dart' show LiquidGlassSettings;
export 'src/painting/liquid_glass_shadow.dart'
    show
        LiquidGlassFixedShadow,
        LiquidGlassIos27RegularShadow,
        LiquidGlassPathSilhouette,
        LiquidGlassShadow,
        LiquidGlassShapeSilhouette,
        LiquidGlassSilhouette;
export 'src/painting/liquid_glass_shape_frame.dart' show LiquidGlassShapeFrame;
export 'src/painting/liquid_glass_support.dart'
    show
        LiquidGlassAvailableSupport,
        LiquidGlassDeviceClass,
        LiquidGlassPendingSupport,
        LiquidGlassSupport,
        LiquidGlassUnavailableSupport;
export 'src/painting/liquid_shape.dart'
    show
        LiquidOval,
        LiquidRoundedRectangle,
        LiquidRoundedSuperellipse,
        LiquidShape;
