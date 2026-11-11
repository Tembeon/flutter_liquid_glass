import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// The look of a [GlassSwitch], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the switch's states. A
/// switch looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSwitchStyle extends GlassStyle<GlassSwitchStyle> {
  /// Creates a style.
  const GlassSwitchStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassSwitchStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassSwitchStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassSwitchStyle>(context);

  /// The fill of the resting knob (UIKit `thumbTintColor`).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track when on (UIKit `onTintColor`).
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track when off.
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// The ring around a switch focused from the keyboard; null derives it
  /// from systemBlue as Flutter's Cupertino controls do, and a transparent
  /// color draws none.
  final Color? focusColor;

  /// What a mouse over the switch adds to its track; null for a pressed
  /// glass's wash at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// Builds the switch's look in place of the default one; the switch then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSwitchBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassSwitchStyle merge(GlassSwitchStyle? other) {
    if (other == null) return this;
    return GlassSwitchStyle(
      thumbColor: GlassStyle.mergeStates(thumbColor, other.thumbColor),
      activeTrackColor: GlassStyle.mergeStates(
        activeTrackColor,
        other.activeTrackColor,
      ),
      inactiveTrackColor: GlassStyle.mergeStates(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassSwitchStyle lerp(GlassSwitchStyle other, double t) {
    if (identical(this, other)) return this;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      GlassStyle.lerpNullable(GlassDynamicColor.lerp),
    );
    return GlassSwitchStyle(
      thumbColor: color(thumbColor, other.thumbColor),
      activeTrackColor: color(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: color(inactiveTrackColor, other.inactiveTrackColor),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSwitchStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    thumbColor,
    activeTrackColor,
    inactiveTrackColor,
    focusColor,
    hoverColor,
    builder,
  );
}

/// A small lens that shows the track's edges 0.755 of its height apart
/// (iPhone 16 Pro references): a shrink of 0.25 toward the whole center
/// line; NEAR, 0.77 on the liquid renderer.
const _knobLens = GlassLens(shrink: 0.25, shrinkRim: 1, small: true);

/// An iOS 27 switch.
///
/// UIKit: `UISwitch`. SwiftUI: `Toggle` with the switch style. Flutter:
/// `CupertinoSwitch`.
///
/// Its track is a plain fill and its knob a platter that turns into glass
/// under the finger, drawn by the ambient renderer; its motion is
/// [RawGlassSwitch]'s. A disabled switch draws at half opacity, as UIKit
/// does (iPhone 16 Pro, light and dark, on and off).
///
/// Focused from the keyboard its track draws the renderer's focus ring, and
/// under a mouse it takes the renderer's hover response: approximations of
/// the platform, not measured.
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
    thumbColor: GlassStyle.allOrNull(thumbColor),
    activeTrackColor: GlassStyle.allOrNull(activeTrackColor),
    inactiveTrackColor: GlassStyle.allOrNull(inactiveTrackColor),
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
      GlassSwitchStyle.maybeOf(context),
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
            states: details.statesListenable,
            focusColor: look.focusColor,
            hoverColor: look.hoverColor,
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
            lens: _knobLens,
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
