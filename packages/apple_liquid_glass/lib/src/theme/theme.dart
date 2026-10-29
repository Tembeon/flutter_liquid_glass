import 'package:apple_liquid_glass/src/controls/button.dart';
import 'package:apple_liquid_glass/src/controls/list.dart';
import 'package:apple_liquid_glass/src/controls/page_control.dart';
import 'package:apple_liquid_glass/src/controls/search_field.dart';
import 'package:apple_liquid_glass/src/controls/segmented_control.dart';
import 'package:apple_liquid_glass/src/controls/slider.dart';
import 'package:apple_liquid_glass/src/controls/stepper.dart';
import 'package:apple_liquid_glass/src/controls/switch.dart';
import 'package:apple_liquid_glass/src/controls/tab_bar.dart';
import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The app's overrides of the iOS semantic colors.
///
/// Flutter: `ColorScheme`, as overrides: a null field keeps the native
/// color, and an app-wide color never replaces a look a control has of its
/// own (a prominent button's label stays white).
@immutable
final class GlassColorScheme {
  /// Creates a scheme; every field defaults to the native color.
  const GlassColorScheme({
    this.surfaces = const {},
    this.label,
    this.tertiaryLabel,
  });

  /// The fill of flat surfaces per role; glass keeps its own material and
  /// takes a color only as its tint.
  final Map<GlassRole, Color> surfaces;

  /// Primary text, in place of [GlassColors.label].
  final Color? label;

  /// Tertiary text and disabled labels, in place of
  /// [GlassColors.tertiaryLabel].
  final Color? tertiaryLabel;

  /// This scheme with the non-null fields of [other] over it.
  GlassColorScheme merge(GlassColorScheme? other) {
    if (other == null) return this;
    return GlassColorScheme(
      surfaces: {...surfaces, ...other.surfaces},
      label: other.label ?? label,
      tertiaryLabel: other.tertiaryLabel ?? tertiaryLabel,
    );
  }

  /// The scheme between [a] and [b] at [t].
  static GlassColorScheme? lerp(
    GlassColorScheme? a,
    GlassColorScheme? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return GlassColorScheme(
      surfaces: {
        for (final role in {...a.surfaces.keys, ...b.surfaces.keys})
          if (GlassDynamicColor.lerp(a.surfaces[role], b.surfaces[role], t)
              case final color?)
            role: color,
      },
      label: GlassDynamicColor.lerp(a.label, b.label, t),
      tertiaryLabel: GlassDynamicColor.lerp(
        a.tertiaryLabel,
        b.tertiaryLabel,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassColorScheme &&
      mapEquals(other.surfaces, surfaces) &&
      other.label == label &&
      other.tertiaryLabel == tertiaryLabel;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(surfaces.entries.map((e) => (e.key, e.value))),
    label,
    tertiaryLabel,
  );
}

/// The look of the glass widgets below a [GlassTheme].
///
/// Every field is an override: null keeps the enclosing theme's value, and
/// at the root the native one. A nested theme merges into the enclosing
/// one field by field.
@immutable
class GlassThemeData {
  /// Creates a theme.
  const GlassThemeData({
    this.brightness,
    this.primaryColor,
    this.fontFamily,
    this.renderer,
    this.colorScheme,
    this.buttonStyle,
    this.prominentButtonStyle,
    this.switchStyle,
    this.sliderStyle,
    this.stepperStyle,
    this.pageControlStyle,
    this.segmentedStyle,
    this.tabBarStyle,
    this.searchFieldStyle,
    this.listStyle,
  });

  /// The theme between [a] and [b] at [t]: colors and styles interpolate;
  /// brightness, font and renderer take [b]'s at once.
  factory GlassThemeData.lerp(
    GlassThemeData a,
    GlassThemeData b,
    double t,
  ) {
    if (identical(a, b) || t == 0) return a;
    if (t == 1) return b;
    return GlassThemeData(
      brightness: b.brightness,
      primaryColor: GlassDynamicColor.lerp(a.primaryColor, b.primaryColor, t),
      fontFamily: b.fontFamily,
      renderer: b.renderer,
      colorScheme: GlassColorScheme.lerp(a.colorScheme, b.colorScheme, t),
      buttonStyle: GlassButtonStyle.lerp(a.buttonStyle, b.buttonStyle, t),
      prominentButtonStyle: GlassButtonStyle.lerp(
        a.prominentButtonStyle,
        b.prominentButtonStyle,
        t,
      ),
      switchStyle: GlassSwitchStyle.lerp(a.switchStyle, b.switchStyle, t),
      sliderStyle: GlassSliderStyle.lerp(a.sliderStyle, b.sliderStyle, t),
      stepperStyle: GlassStepperStyle.lerp(a.stepperStyle, b.stepperStyle, t),
      pageControlStyle: GlassPageControlStyle.lerp(
        a.pageControlStyle,
        b.pageControlStyle,
        t,
      ),
      segmentedStyle: GlassSegmentedStyle.lerp(
        a.segmentedStyle,
        b.segmentedStyle,
        t,
      ),
      tabBarStyle: GlassTabBarStyle.lerp(a.tabBarStyle, b.tabBarStyle, t),
      searchFieldStyle: GlassSearchFieldStyle.lerp(
        a.searchFieldStyle,
        b.searchFieldStyle,
        t,
      ),
      listStyle: GlassListStyle.lerp(a.listStyle, b.listStyle, t),
    );
  }

  /// Light or dark, or null to follow the platform.
  final Brightness? brightness;

  /// The accent, UIKit's `tintColor`; [GlassColors.systemBlue] when null.
  final Color? primaryColor;

  /// The font of every label, or null for the system font.
  final String? fontFamily;

  /// How every glass surface is drawn; liquid glass when null.
  final GlassRenderer? renderer;

  /// The app's semantic colors.
  final GlassColorScheme? colorScheme;

  /// The look of regular and clear glass buttons.
  final GlassButtonStyle? buttonStyle;

  /// The look of prominent glass buttons.
  final GlassButtonStyle? prominentButtonStyle;

  /// The look of switches.
  final GlassSwitchStyle? switchStyle;

  /// The look of sliders.
  final GlassSliderStyle? sliderStyle;

  /// The look of steppers.
  final GlassStepperStyle? stepperStyle;

  /// The look of page controls.
  final GlassPageControlStyle? pageControlStyle;

  /// The look of segmented controls.
  final GlassSegmentedStyle? segmentedStyle;

  /// The look of tab bars.
  final GlassTabBarStyle? tabBarStyle;

  /// The look of search fields.
  final GlassSearchFieldStyle? searchFieldStyle;

  /// The look of inset grouped lists.
  final GlassListStyle? listStyle;

  /// This theme with the non-null fields of [other] over it; styles and
  /// schemes merge too.
  GlassThemeData merge(GlassThemeData? other) {
    if (other == null) return this;
    return GlassThemeData(
      brightness: other.brightness ?? brightness,
      primaryColor: other.primaryColor ?? primaryColor,
      fontFamily: other.fontFamily ?? fontFamily,
      renderer: other.renderer ?? renderer,
      colorScheme: colorScheme?.merge(other.colorScheme) ?? other.colorScheme,
      buttonStyle: other.buttonStyle?.merge(buttonStyle) ?? buttonStyle,
      prominentButtonStyle:
          other.prominentButtonStyle?.merge(prominentButtonStyle) ??
          prominentButtonStyle,
      switchStyle: other.switchStyle?.merge(switchStyle) ?? switchStyle,
      sliderStyle: other.sliderStyle?.merge(sliderStyle) ?? sliderStyle,
      stepperStyle: other.stepperStyle?.merge(stepperStyle) ?? stepperStyle,
      pageControlStyle:
          other.pageControlStyle?.merge(pageControlStyle) ?? pageControlStyle,
      segmentedStyle:
          other.segmentedStyle?.merge(segmentedStyle) ?? segmentedStyle,
      tabBarStyle: other.tabBarStyle?.merge(tabBarStyle) ?? tabBarStyle,
      searchFieldStyle:
          other.searchFieldStyle?.merge(searchFieldStyle) ?? searchFieldStyle,
      listStyle: other.listStyle?.merge(listStyle) ?? listStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassThemeData &&
      other.brightness == brightness &&
      other.primaryColor == primaryColor &&
      other.fontFamily == fontFamily &&
      other.renderer == renderer &&
      other.colorScheme == colorScheme &&
      other.buttonStyle == buttonStyle &&
      other.prominentButtonStyle == prominentButtonStyle &&
      other.switchStyle == switchStyle &&
      other.sliderStyle == sliderStyle &&
      other.stepperStyle == stepperStyle &&
      other.pageControlStyle == pageControlStyle &&
      other.segmentedStyle == segmentedStyle &&
      other.tabBarStyle == tabBarStyle &&
      other.searchFieldStyle == searchFieldStyle &&
      other.listStyle == listStyle;

  @override
  int get hashCode => Object.hash(
    brightness,
    primaryColor,
    fontFamily,
    renderer,
    colorScheme,
    buttonStyle,
    prominentButtonStyle,
    switchStyle,
    sliderStyle,
    stepperStyle,
    pageControlStyle,
    segmentedStyle,
    tabBarStyle,
    searchFieldStyle,
    listStyle,
  );
}

/// Sets the look of the glass widgets below it.
///
/// Flutter: `CupertinoTheme`, except that a nested theme merges into the
/// enclosing one instead of replacing it.
///
/// A widget that reads one part of the theme ([rendererOf], [brightnessOf])
/// rebuilds only when that part changes.
class GlassTheme extends StatelessWidget {
  /// Applies [data] to [child].
  const GlassTheme({required this.data, required this.child, super.key});

  /// The theme.
  final GlassThemeData data;

  /// The subtree the theme applies to.
  final Widget child;

  /// The merged theme at [context], or an empty one.
  static GlassThemeData of(BuildContext context) =>
      maybeOf(context) ?? const GlassThemeData();

  /// The merged theme at [context], or null without a theme above.
  static GlassThemeData? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_GlassThemeScope>(context)?.data;

  static GlassThemeData? _of(BuildContext context, _GlassThemeAspect aspect) =>
      InheritedModel.inheritFrom<_GlassThemeScope>(
        context,
        aspect: aspect,
      )?.data;

  /// The renderer at [context]; liquid glass without one.
  static GlassRenderer rendererOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.renderer)?.renderer ??
      const GlassRenderer.liquid();

  /// The theme's brightness at [context], or null to follow the platform.
  static Brightness? brightnessOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.brightness)?.brightness;

  /// The theme's color scheme at [context], or null without one.
  static GlassColorScheme? colorSchemeOf(BuildContext context) =>
      _of(context, _GlassThemeAspect.colorScheme)?.colorScheme;

  @override
  Widget build(BuildContext context) {
    final outer = maybeOf(context);
    return _GlassThemeScope(data: outer?.merge(data) ?? data, child: child);
  }
}

enum _GlassThemeAspect { renderer, brightness, colorScheme }

class _GlassThemeScope extends InheritedModel<_GlassThemeAspect> {
  const _GlassThemeScope({required this.data, required super.child});

  final GlassThemeData data;

  @override
  bool updateShouldNotify(_GlassThemeScope oldWidget) => data != oldWidget.data;

  @override
  bool updateShouldNotifyDependent(
    _GlassThemeScope oldWidget,
    Set<_GlassThemeAspect> dependencies,
  ) => dependencies.any(
    (aspect) => switch (aspect) {
      _GlassThemeAspect.renderer => data.renderer != oldWidget.data.renderer,
      _GlassThemeAspect.brightness =>
        data.brightness != oldWidget.data.brightness,
      _GlassThemeAspect.colorScheme =>
        data.colorScheme != oldWidget.data.colorScheme,
    },
  );
}

/// A [GlassTheme] that moves to a new [data] on [spring], as
/// [GlassThemeData.lerp] interpolates.
///
/// Flutter: `AnimatedTheme`. Under Reduce Motion it switches at once. While
/// it moves, widgets that read the whole theme ([GlassTheme.of]) rebuild
/// every frame; at rest it is [data] exactly.
class AnimatedGlassTheme extends StatefulWidget {
  /// Animates [child]'s theme to [data] on [spring].
  const AnimatedGlassTheme({
    required this.data,
    required this.child,
    this.spring = Spring.smooth,
    super.key,
  });

  /// The theme to move to.
  final GlassThemeData data;

  /// The spring the theme moves on.
  final Spring spring;

  /// The subtree the theme applies to.
  final Widget child;

  @override
  State<AnimatedGlassTheme> createState() => _AnimatedGlassThemeState();
}

class _AnimatedGlassThemeState extends State<AnimatedGlassTheme> {
  // The double converter's rest distance is a pixel's; this runs 0 to 1.
  final _progress = MotionValue<double>(1, restDistance: 0.002);
  late GlassThemeData _from = widget.data;

  GlassThemeData get _shown =>
      GlassThemeData.lerp(_from, widget.data, _progress.value.clamp(0, 1));

  @override
  void didUpdateWidget(AnimatedGlassTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data == widget.data) return;
    _from = GlassThemeData.lerp(
      _from,
      oldWidget.data,
      _progress.value.clamp(0, 1),
    );
    final now = _progress.clock.now;
    if (GlassTraits.of(context).reduceMotion) {
      _progress.snap(now, 1);
      return;
    }
    _progress.snap(now, 0);
    withSpring(widget.spring, () => _progress.target = 1);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _progress,
    builder: (context, child) => GlassTheme(data: _shown, child: child!),
    child: widget.child,
  );
}
