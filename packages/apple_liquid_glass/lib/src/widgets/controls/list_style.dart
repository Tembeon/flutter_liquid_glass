import 'dart:ui' show lerpDouble;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';

/// The look of an inset grouped list, like Flutter's `ButtonStyle`.
///
/// Each color property but [focusColor] and [hoverColor] resolves against
/// the row's states (pressed, focused, hovered, disabled) and falls
/// through, state by state, from the row's style to its section's to the
/// theme's to the defaults: a null for a state leaves that state to the
/// next one. The defaults are the iOS 27 system colors the table resolves
/// (list passport, light and dark).
///
/// Each text style merges over the one below it the same way, and the
/// result over the default text of its part; its color is not used, the
/// color properties color the text.
@immutable
class GlassListStyle extends GlassStyle<GlassListStyle> {
  /// Creates a style.
  const GlassListStyle({
    this.backgroundColor,
    this.overlayColor,
    this.separatorColor,
    this.foregroundColor,
    this.secondaryColor,
    this.iconColor,
    this.disclosureColor,
    this.focusColor,
    this.hoverColor,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.detailTextStyle,
    this.headerTextStyle,
    this.footerTextStyle,
    this.minRowHeight,
  });

  /// The theme's [GlassListStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassListStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassListStyle>(context);

  /// The fill of a section's card;
  /// [GlassColors.secondarySystemGroupedBackground] by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The fill of a pressed row; [GlassColors.systemGray4], the
  /// grouped cell's highlighted color, by default.
  final WidgetStateProperty<Color?>? overlayColor;

  /// The separators between rows; [GlassColors.separator] by default.
  final WidgetStateProperty<Color?>? separatorColor;

  /// A row's title; [GlassColors.label] by default, and
  /// [GlassColors.tertiaryLabel] on a disabled row.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// A row's subtitle and detail, and a section's header and footer;
  /// [GlassColors.secondaryLabel] by default, and
  /// [GlassColors.quaternaryLabel] on a disabled row.
  final WidgetStateProperty<Color?>? secondaryColor;

  /// A row's leading symbol, checkmark and info button; the theme's
  /// primary color, else [GlassColors.systemBlue], by default. A disabled
  /// row's symbol takes [GlassColors.tertiaryLabel]; its checkmark and info
  /// button keep the enabled color.
  final WidgetStateProperty<Color?>? iconColor;

  /// The disclosure chevron; [GlassColors.tertiaryLabel] by default.
  final WidgetStateProperty<Color?>? disclosureColor;

  /// The ring inside a row, and around an info button, focused from the
  /// keyboard; null derives it from systemBlue as Flutter's Cupertino
  /// controls do, and a transparent color draws none.
  final Color? focusColor;

  /// What a mouse over a row or an info button fills under it; null for
  /// [overlayColor] at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// A row's title, over 17 point regular text.
  final TextStyle? titleTextStyle;

  /// The line under a row's title, over 15 point regular text.
  final TextStyle? subtitleTextStyle;

  /// A row's detail value, over 17 point regular text.
  final TextStyle? detailTextStyle;

  /// A section's header label, over 17 point semibold text.
  final TextStyle? headerTextStyle;

  /// A section's footer label, over 13 point regular text.
  final TextStyle? footerTextStyle;

  /// The least height of a row, in points; 53 by default, the least height
  /// UIKit gives an inset grouped table's row, with its text centered in
  /// it. A row whose text and its 15.5 point margins above and below need
  /// more grows.
  final double? minRowHeight;

  /// This style over [other], state by state.
  @override
  GlassListStyle merge(GlassListStyle? other) {
    if (other == null) return this;
    return GlassListStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      overlayColor: GlassStyle.mergeStates(overlayColor, other.overlayColor),
      separatorColor: GlassStyle.mergeStates(
        separatorColor,
        other.separatorColor,
      ),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      secondaryColor: GlassStyle.mergeStates(
        secondaryColor,
        other.secondaryColor,
      ),
      iconColor: GlassStyle.mergeStates(iconColor, other.iconColor),
      disclosureColor: GlassStyle.mergeStates(
        disclosureColor,
        other.disclosureColor,
      ),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      titleTextStyle: _merge(titleTextStyle, other.titleTextStyle),
      subtitleTextStyle: _merge(subtitleTextStyle, other.subtitleTextStyle),
      detailTextStyle: _merge(detailTextStyle, other.detailTextStyle),
      headerTextStyle: _merge(headerTextStyle, other.headerTextStyle),
      footerTextStyle: _merge(footerTextStyle, other.footerTextStyle),
      minRowHeight: minRowHeight ?? other.minRowHeight,
    );
  }

  static TextStyle? _merge(TextStyle? over, TextStyle? under) =>
      under?.merge(over) ?? over;

  /// The style between this one and [other] at [t].
  @override
  GlassListStyle lerp(GlassListStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    final text = GlassStyle.lerpNullable(TextStyle.lerp);
    return GlassListStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      overlayColor: color(overlayColor, other.overlayColor),
      separatorColor: color(separatorColor, other.separatorColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      secondaryColor: color(secondaryColor, other.secondaryColor),
      iconColor: color(iconColor, other.iconColor),
      disclosureColor: color(disclosureColor, other.disclosureColor),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      subtitleTextStyle: text(subtitleTextStyle, other.subtitleTextStyle, t),
      detailTextStyle: text(detailTextStyle, other.detailTextStyle, t),
      headerTextStyle: text(headerTextStyle, other.headerTextStyle, t),
      footerTextStyle: text(footerTextStyle, other.footerTextStyle, t),
      minRowHeight: GlassStyle.lerpNullable(lerpDouble)(
        minRowHeight,
        other.minRowHeight,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassListStyle &&
      other.backgroundColor == backgroundColor &&
      other.overlayColor == overlayColor &&
      other.separatorColor == separatorColor &&
      other.foregroundColor == foregroundColor &&
      other.secondaryColor == secondaryColor &&
      other.iconColor == iconColor &&
      other.disclosureColor == disclosureColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.titleTextStyle == titleTextStyle &&
      other.subtitleTextStyle == subtitleTextStyle &&
      other.detailTextStyle == detailTextStyle &&
      other.headerTextStyle == headerTextStyle &&
      other.footerTextStyle == footerTextStyle &&
      other.minRowHeight == minRowHeight;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    overlayColor,
    separatorColor,
    foregroundColor,
    secondaryColor,
    iconColor,
    disclosureColor,
    focusColor,
    hoverColor,
    titleTextStyle,
    subtitleTextStyle,
    detailTextStyle,
    headerTextStyle,
    footerTextStyle,
    minRowHeight,
  );
}
