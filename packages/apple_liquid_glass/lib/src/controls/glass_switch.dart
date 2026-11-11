import 'package:apple_liquid_glass/src/controls/switch.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of a [GlassSwitch], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the switch's states. A
/// switch looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSwitchStyle {
  /// Creates a style.
  const GlassSwitchStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.builder,
  });

  /// The fill of the resting knob (UIKit `thumbTintColor`).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track when on (UIKit `onTintColor`).
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track when off.
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// Builds the switch's look in place of the default one; the switch then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSwitchBuilder? builder;

  /// This style over [other], state by state.
  GlassSwitchStyle merge(GlassSwitchStyle? other) {
    if (other == null) return this;
    return GlassSwitchStyle(
      thumbColor: fallThrough(thumbColor, other.thumbColor),
      activeTrackColor: fallThrough(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: fallThrough(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassSwitchStyle? lerp(
    GlassSwitchStyle? a,
    GlassSwitchStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassSwitchStyle(
      thumbColor: color(a.thumbColor, b.thumbColor),
      activeTrackColor: color(a.activeTrackColor, b.activeTrackColor),
      inactiveTrackColor: color(a.inactiveTrackColor, b.inactiveTrackColor),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSwitchStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.builder == builder;

  @override
  int get hashCode =>
      Object.hash(thumbColor, activeTrackColor, inactiveTrackColor, builder);
}

/// An iOS 27 switch.
///
/// UIKit: `UISwitch`. SwiftUI: `Toggle` with the switch style. Flutter:
/// `CupertinoSwitch`.
///
/// Its track is a plain fill and its knob a platter that turns into glass
/// under the finger, drawn by the ambient renderer; its motion is
/// [RawGlassSwitch]'s. A disabled switch draws at half opacity, as UIKit
/// does (iPhone 16 Pro, light and dark, on and off).
class GlassSwitch extends StatelessWidget {
  /// Creates a switch showing [value].
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when the user toggles the switch; null
  /// disables it.
  final ValueChanged<bool>? onChanged;

  /// The look, over the theme's and the switch's defaults.
  final GlassSwitchStyle? style;

  /// Where the switch writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The switch's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the switch takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the switch.
  final String? semanticLabel;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassSwitchStyle styleFrom({
    Color? thumbColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
  }) => GlassSwitchStyle(
    thumbColor: allStates(thumbColor),
    activeTrackColor: allStates(activeTrackColor),
    inactiveTrackColor: allStates(inactiveTrackColor),
  );

  /// UISwitch's off track: secondarySystemFill, and under Increase Contrast
  /// its own color, 78 percent of 0x787880 in light and 90 in dark (read
  /// from UIKit's color tables, notes private; not rendered on a device).
  static const inactiveTrack = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x29787880),
    darkColor: Color(0x52787880),
    highContrastColor: Color(0xC7787880),
    darkHighContrastColor: Color(0xE5787880),
  );

  static const _disabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassSwitchStyle()).merge(
      GlassTheme.of(context).switchStyle,
    );
    return RawGlassSwitch(
      value: value,
      onChanged: onChanged,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      builder:
          look.builder ??
          (context, details) => _defaultBody(context, details, look),
    );
  }

  Widget _defaultBody(
    BuildContext context,
    GlassSwitchDetails details,
    GlassSwitchStyle look,
  ) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    final off = resolve(look.inactiveTrackColor, inactiveTrack);
    final on = resolve(look.activeTrackColor, GlassColors.systemGreen);
    final body = Stack(
      children: [
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.track,
            frame: MotionSelection(
              () => GlassFrame(
                tint: Color.lerp(
                  off,
                  on,
                  details.progress.value.clamp(0.0, 1.0),
                ),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.lens,
            part: GlassPart.knob,
            glass: Glass.regular(
              tint: resolve(look.thumbColor, const Color(0xFFFFFFFF)),
            ),
            frame: details.thumb,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? _disabledOpacity : 1,
      child: body,
    );
  }
}
