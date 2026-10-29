import 'package:apple_liquid_glass/src/menu/motion.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The colors of a glass menu, light and dark (iPhone 16 Pro).
@internal
@immutable
class MenuAppearance {
  /// Creates an appearance; the defaults are the iOS 27 light appearance.
  const MenuAppearance({
    this.glassColor = const Color(0xF2F9F9FF),
    this.shadowColor = const Color(0x33000000),
    this.shadowElevation = 12,
    this.textStyle = const TextStyle(fontSize: 17, color: Color(0xF5000000)),
    this.iconColor = const Color(0xF5000000),
    this.disabledIconColor = const Color(0x4C3C3C43),
    this.iconSize = MenuTuning.rowIconSize,
    this.destructiveColor = const Color(0xFFFF383C),
    this.highlightColor = const Color(0x1F000000),
    this.secondaryColor = const Color(0x993C3C43),
    this.disabledColor = const Color(0x4C3C3C43),
    this.separatorColor = const Color(0x14000000),
    this.submenuColor = const Color(0x66FFFFFF),
    this.glassTint = const Color(0x00000000),
    this.submenuRimColor = const Color(0xFFFFFFFF),
    this.submenuShadowColor = const Color(0x1E000000),
    this.paletteSelectionColor = const Color(0x10000000),
  });

  /// The fallback fill of the button and menu without a glass painter.
  /// The installed renderer uses [glassTint].
  final Color glassColor;

  /// The color of the shadow under the button and the menu.
  final Color shadowColor;

  /// The elevation of the shadow under the button and the menu.
  final double shadowElevation;

  /// The style of row titles.
  ///
  /// The menu shows in an overlay, outside the text style of the screen
  /// the button sits on, so this is the whole style of its titles: it
  /// replaces the overlay's ambient text style instead of merging into it.
  final TextStyle textStyle;

  /// The color of the button's default glyph and of row glyphs.
  final Color iconColor;

  /// The color of a disabled button's glyph: tertiaryLabel. UIKit leaves
  /// the glass of a disabled menu button untouched (iPhone 16 Pro, iOS
  /// 27.0.1, light and dark).
  final Color disabledIconColor;

  /// The size of row glyphs.
  final double iconSize;

  /// The color of destructive rows.
  final Color destructiveColor;

  /// The fill of the pill under the highlighted row.
  final Color highlightColor;

  /// The color of subtitles and section headers: secondaryLabel.
  final Color secondaryColor;

  /// The color of disabled rows and of the loading row: tertiaryLabel.
  final Color disabledColor;

  /// The color of the hairline between groups of rows (rendered 229 on
  /// the 249 light platter, 50 on the 32 dark one).
  final Color separatorColor;

  /// The fallback tint a submenu card lays over the list under it.
  ///
  /// A card is a translucent platter that blurs what lies under it by
  /// [MenuTuning.cardBlur]: where it covers the list it opened from
  /// it reads 252 on the 249 light menu and 57 on the 32 dark one; past
  /// that list's edge only the blur shows (device screenshots, iPhone 16
  /// Pro). Each further card under it adds half as much.
  final Color submenuColor;

  /// The tint of the button and menu cards in the installed renderer.
  /// Untinted regular glass reads 252 over a 249.5 light list and 57 over
  /// a 32 dark list on the iPhone 16 Pro; its transfer supplies the lift.
  final Color glassTint;

  /// The fallback highlight along a submenu card's top edge, fading over
  /// its first points (device: a one-pixel line at 251 - 255 over the 248
  /// light card, 65 - 83 over the 57 dark one).
  final Color submenuRimColor;

  /// The shadow color around a submenu card, on the liquid tier and in
  /// the fallback. Light: alpha 0.1188 (30 / 255) from a Gaussian fit of
  /// native straight side and bottom profiles over 242 gray, 0.273 gray
  /// RMS; dark is unmeasured.
  final Color submenuShadowColor;

  /// The platter under the selected palette cell (sampled: 233 on 249
  /// light, 53 on 32 dark).
  final Color paletteSelectionColor;

  /// The light appearance.
  static const light = MenuAppearance();

  /// The dark appearance, sampled from the iOS 27 dark menu.
  static const dark = MenuAppearance(
    glassColor: Color(0xF2222222),
    shadowColor: Color(0x66000000),
    textStyle: TextStyle(fontSize: 17, color: Color(0xF5FFFFFF)),
    iconColor: Color(0xF5FFFFFF),
    disabledIconColor: Color(0x4CEBEBF5),
    destructiveColor: Color(0xFFFF4245),
    highlightColor: Color(0x29FFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    disabledColor: Color(0x4CEBEBF5),
    separatorColor: Color(0x14FFFFFF),
    submenuColor: Color(0x1DFFFFFF),
    submenuRimColor: Color(0x33FFFFFF),
    submenuShadowColor: Color(0x33000000),
    paletteSelectionColor: Color(0x18FFFFFF),
  );

  /// The table for the brightness at [context].
  static MenuAppearance resolve(BuildContext context) =>
      switch (GlassTraits.of(context).brightness) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// A copy of this appearance with the given fields replaced.
  MenuAppearance copyWith({
    Color? glassColor,
    Color? shadowColor,
    double? shadowElevation,
    TextStyle? textStyle,
    Color? iconColor,
    Color? disabledIconColor,
    double? iconSize,
    Color? destructiveColor,
    Color? highlightColor,
    Color? secondaryColor,
    Color? disabledColor,
    Color? separatorColor,
    Color? submenuColor,
    Color? glassTint,
    Color? submenuRimColor,
    Color? submenuShadowColor,
    Color? paletteSelectionColor,
  }) => MenuAppearance(
    glassColor: glassColor ?? this.glassColor,
    shadowColor: shadowColor ?? this.shadowColor,
    shadowElevation: shadowElevation ?? this.shadowElevation,
    textStyle: textStyle ?? this.textStyle,
    iconColor: iconColor ?? this.iconColor,
    disabledIconColor: disabledIconColor ?? this.disabledIconColor,
    iconSize: iconSize ?? this.iconSize,
    destructiveColor: destructiveColor ?? this.destructiveColor,
    highlightColor: highlightColor ?? this.highlightColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    disabledColor: disabledColor ?? this.disabledColor,
    separatorColor: separatorColor ?? this.separatorColor,
    submenuColor: submenuColor ?? this.submenuColor,
    glassTint: glassTint ?? this.glassTint,
    submenuRimColor: submenuRimColor ?? this.submenuRimColor,
    submenuShadowColor: submenuShadowColor ?? this.submenuShadowColor,
    paletteSelectionColor: paletteSelectionColor ?? this.paletteSelectionColor,
  );

  @override
  bool operator ==(Object other) =>
      other is MenuAppearance &&
      other.glassColor == glassColor &&
      other.shadowColor == shadowColor &&
      other.shadowElevation == shadowElevation &&
      other.textStyle == textStyle &&
      other.iconColor == iconColor &&
      other.disabledIconColor == disabledIconColor &&
      other.iconSize == iconSize &&
      other.destructiveColor == destructiveColor &&
      other.highlightColor == highlightColor &&
      other.secondaryColor == secondaryColor &&
      other.disabledColor == disabledColor &&
      other.separatorColor == separatorColor &&
      other.submenuColor == submenuColor &&
      other.glassTint == glassTint &&
      other.submenuRimColor == submenuRimColor &&
      other.submenuShadowColor == submenuShadowColor &&
      other.paletteSelectionColor == paletteSelectionColor;

  @override
  int get hashCode => Object.hash(
    glassColor,
    shadowColor,
    shadowElevation,
    textStyle,
    iconColor,
    disabledIconColor,
    iconSize,
    destructiveColor,
    highlightColor,
    secondaryColor,
    disabledColor,
    separatorColor,
    submenuColor,
    glassTint,
    submenuRimColor,
    submenuShadowColor,
    paletteSelectionColor,
  );
}
