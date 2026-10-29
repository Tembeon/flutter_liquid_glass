import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// How far forward an interface sits; wrap presented content in a
/// `GlassTraitsOverride` to raise it (the package's presentations do not).
///
/// UIKit: `UIUserInterfaceLevel`.
enum GlassInterfaceLevel {
  /// The app's own pages.
  base,

  /// Content presented over them: sheets, popovers, menus.
  elevated,
}

/// The traits glass widgets resolve their looks against: appearance,
/// contrast and the accessibility settings.
///
/// UIKit: `UITraitCollection`. Flutter: the accessibility fields of
/// `MediaQueryData`.
///
/// [GlassTraits.of] reads the theme's brightness, then the platform's;
/// contrast and Bold Text from `MediaQuery`; Reduce Motion from
/// `MediaQuery.disableAnimations` or `MotionAccessibility.reduceMotion`; the
/// interface level and the settings Flutter does not report from the
/// nearest `GlassTraitsOverride`.
@immutable
final class GlassTraits {
  /// Creates traits; the defaults are the light appearance with no
  /// accessibility setting on.
  const GlassTraits({
    this.brightness = Brightness.light,
    this.interfaceLevel = GlassInterfaceLevel.base,
    this.highContrast = false,
    this.boldText = false,
    this.reduceMotion = false,
    this.reduceTransparency = false,
    this.prefersCrossFade = false,
    this.showBorders = false,
  });

  /// The traits at [context].
  factory GlassTraits.of(BuildContext context) {
    final overrides = context
        .dependOnInheritedWidgetOfExactType<_GlassTraitsScope>();
    final reduceMotion =
        MotionAccessibility.reduceMotion ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    // iOS offers Prefer Cross-Fade Transitions with Reduce Motion, on by
    // default: unreported, it follows Reduce Motion.
    final crossFade =
        overrides?.prefersCrossFade ??
        MotionAccessibility.preferCrossFade ??
        reduceMotion;
    return GlassTraits(
      brightness:
          GlassTheme.brightnessOf(context) ??
          MediaQuery.maybePlatformBrightnessOf(context) ??
          Brightness.light,
      interfaceLevel: overrides?.interfaceLevel ?? GlassInterfaceLevel.base,
      highContrast: MediaQuery.maybeHighContrastOf(context) ?? false,
      boldText: MediaQuery.maybeBoldTextOf(context) ?? false,
      reduceMotion: reduceMotion,
      reduceTransparency: overrides?.reduceTransparency ?? false,
      prefersCrossFade: reduceMotion && crossFade,
      showBorders: overrides?.showBorders ?? false,
    );
  }

  /// Light or dark.
  final Brightness brightness;

  /// Whether the content is presented over other content.
  final GlassInterfaceLevel interfaceLevel;

  /// Increase Contrast (iOS) or high contrast text (Android).
  final bool highContrast;

  /// Bold Text.
  final bool boldText;

  /// Reduce Motion.
  final bool reduceMotion;

  /// Reduce Transparency: the liquid renderer draws its surfaces flat, an
  /// unmeasured stand-in for iOS's frosted glass.
  final bool reduceTransparency;

  /// Prefer Cross-Fade Transitions, which iOS offers with Reduce Motion:
  /// pages cross-fade instead of sliding. On only with [reduceMotion].
  final bool prefersCrossFade;

  /// Show Borders: glass surfaces draw a hairline around their bodies, an
  /// unmeasured stand-in for iOS's (the label color at 35 percent, one
  /// point).
  final bool showBorders;

  @override
  bool operator ==(Object other) =>
      other is GlassTraits &&
      other.brightness == brightness &&
      other.interfaceLevel == interfaceLevel &&
      other.highContrast == highContrast &&
      other.boldText == boldText &&
      other.reduceMotion == reduceMotion &&
      other.reduceTransparency == reduceTransparency &&
      other.prefersCrossFade == prefersCrossFade &&
      other.showBorders == showBorders;

  @override
  int get hashCode => Object.hash(
    brightness,
    interfaceLevel,
    highContrast,
    boldText,
    reduceMotion,
    reduceTransparency,
    prefersCrossFade,
    showBorders,
  );
}

/// Sets the traits Flutter does not report for the subtree below it; a
/// null field keeps the enclosing value.
///
/// Bold Text, contrast, Reduce Motion and text size are overridden through
/// `MediaQuery`, brightness through `GlassThemeData.brightness`. Reduce
/// Motion is also on while kinesis's `MotionAccessibility.reduceMotion` is.
class GlassTraitsOverride extends StatelessWidget {
  /// Overrides the given traits for [child].
  const GlassTraitsOverride({
    required this.child,
    this.interfaceLevel,
    this.reduceTransparency,
    this.prefersCrossFade,
    this.showBorders,
    super.key,
  });

  /// See [GlassTraits.interfaceLevel].
  final GlassInterfaceLevel? interfaceLevel;

  /// See [GlassTraits.reduceTransparency].
  final bool? reduceTransparency;

  /// See [GlassTraits.prefersCrossFade]; it applies under Reduce Motion.
  final bool? prefersCrossFade;

  /// See [GlassTraits.showBorders].
  final bool? showBorders;

  /// The subtree the traits apply to.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outer = context
        .dependOnInheritedWidgetOfExactType<_GlassTraitsScope>();
    return _GlassTraitsScope(
      interfaceLevel: interfaceLevel ?? outer?.interfaceLevel,
      reduceTransparency: reduceTransparency ?? outer?.reduceTransparency,
      prefersCrossFade: prefersCrossFade ?? outer?.prefersCrossFade,
      showBorders: showBorders ?? outer?.showBorders,
      child: child,
    );
  }
}

class _GlassTraitsScope extends InheritedWidget {
  const _GlassTraitsScope({
    required this.interfaceLevel,
    required this.reduceTransparency,
    required this.prefersCrossFade,
    required this.showBorders,
    required super.child,
  });

  final GlassInterfaceLevel? interfaceLevel;
  final bool? reduceTransparency;
  final bool? prefersCrossFade;
  final bool? showBorders;

  @override
  bool updateShouldNotify(_GlassTraitsScope oldWidget) =>
      interfaceLevel != oldWidget.interfaceLevel ||
      reduceTransparency != oldWidget.reduceTransparency ||
      prefersCrossFade != oldWidget.prefersCrossFade ||
      showBorders != oldWidget.showBorders;
}
