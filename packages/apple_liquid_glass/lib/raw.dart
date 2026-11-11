/// The behaviour cores of the controls: `GlassPressable` (the button's),
/// `RawGlassSwitch`, `RawGlassSlider`, `RawGlassStepper`,
/// `RawGlassSelector`, `RawGlassPageControl`, `RawGlassSearchField` and
/// `RawGlassList`, with the details each gives its builder.
///
/// For the author of a design system who wants iOS behaviour with a look
/// of their own. A core runs the measured motion of its control and takes
/// its input, focus, keys and semantics; it gives its builder where each
/// part of the control is and the control's states, and the builder
/// draws.
///
/// It promises that a frame of motion does not rebuild the builder: a
/// builder runs when the core builds, such as when its states change.
///
/// A core has no look of its own.
library;

export 'src/raw/button.dart'
    show GlassButtonBuilder, GlassButtonDetails, GlassPressable;
export 'src/raw/list.dart' show RawGlassList;
export 'src/raw/page_control.dart'
    show
        GlassPageControlBackground,
        GlassPageControlBuilder,
        GlassPageControlDetails,
        GlassPageControlPose,
        RawGlassPageControl;
export 'src/raw/search_controller.dart' show GlassSearchController;
export 'src/raw/search_field.dart'
    show GlassSearchFieldBuilder, GlassSearchFieldDetails, RawGlassSearchField;
export 'src/raw/selector.dart'
    show
        GlassSelectorBuilder,
        GlassSelectorDetails,
        GlassSelectorItemBuilder,
        GlassSelectorMotion,
        RawGlassSelector;
export 'src/raw/slider.dart'
    show GlassSliderBuilder, GlassSliderDetails, RawGlassSlider;
export 'src/raw/stepper.dart'
    show
        GlassStepperBuilder,
        GlassStepperDetails,
        GlassStepperHalf,
        RawGlassStepper;
export 'src/raw/switch.dart'
    show GlassSwitchBuilder, GlassSwitchDetails, RawGlassSwitch;
