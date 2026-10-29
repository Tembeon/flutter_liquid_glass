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
    this.textStyle = const TextStyle(fontSize: 17, color: Color(0xF5000000)),
    this.iconSize = MenuTuning.rowIconSize,
    this.destructiveColor = const Color(0xFFFF383C),
    this.highlightColor = const Color(0x1F000000),
    this.secondaryColor = const Color(0x993C3C43),
    this.disabledColor = const Color(0x4C3C3C43),
    this.separatorColor = const Color(0x14000000),
    this.submenuColor = const Color(0x66FFFFFF),
    this.paletteSelectionColor = const Color(0x10000000),
  });

  /// The style of row titles, whose color also draws row glyphs.
  ///
  /// The menu shows in an overlay, outside the text style of the screen
  /// the button sits on, so this is the whole style of its titles: it
  /// replaces the overlay's ambient text style instead of merging into it.
  final TextStyle textStyle;

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

  /// The tint a submenu card lays over the list under it, measured; the
  /// cards draw on the menu glass role without it.
  ///
  /// A card is a translucent platter that blurs what lies under it by
  /// [MenuTuning.cardBlur]: where it covers the list it opened from
  /// it reads 252 on the 249 light menu and 57 on the 32 dark one; past
  /// that list's edge only the blur shows (device screenshots, iPhone 16
  /// Pro). Each further card under it adds half as much.
  final Color submenuColor;

  /// The platter under the selected palette cell (sampled: 233 on 249
  /// light, 53 on 32 dark).
  final Color paletteSelectionColor;

  /// The light appearance.
  static const light = MenuAppearance();

  /// The dark appearance, sampled from the iOS 27 dark menu.
  static const dark = MenuAppearance(
    textStyle: TextStyle(fontSize: 17, color: Color(0xF5FFFFFF)),
    destructiveColor: Color(0xFFFF4245),
    highlightColor: Color(0x29FFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    disabledColor: Color(0x4CEBEBF5),
    separatorColor: Color(0x14FFFFFF),
    submenuColor: Color(0x1DFFFFFF),
    paletteSelectionColor: Color(0x18FFFFFF),
  );

  /// The table for the brightness at [context].
  static MenuAppearance resolve(BuildContext context) =>
      switch (GlassTraits.of(context).brightness) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}
