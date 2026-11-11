import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The look of a glass menu's rows; a null field leaves it to the theme's
/// style, then the default, which follows the brightness (iPhone 16 Pro,
/// iOS 27).
@immutable
class GlassMenuStyle {
  /// Creates a style.
  const GlassMenuStyle({
    this.textStyle,
    this.destructiveColor,
    this.highlightColor,
    this.secondaryColor,
    this.disabledColor,
    this.separatorColor,
    this.paletteSelectionColor,
  });

  /// The row titles, whose color also draws row glyphs, over the default
  /// 17 points in label at 96 percent. The menu measures its titles in it
  /// to lay out the rows.
  final TextStyle? textStyle;

  /// The titles and glyphs of destructive rows; systemRed by default.
  final Color? destructiveColor;

  /// The pill under the highlighted row.
  final Color? highlightColor;

  /// Subtitles and section headers; secondaryLabel by default.
  final Color? secondaryColor;

  /// Disabled rows and the loading row; tertiaryLabel by default.
  final Color? disabledColor;

  /// The hairline between groups of rows.
  final Color? separatorColor;

  /// The platter under the selected palette cell.
  final Color? paletteSelectionColor;

  /// This style over [other].
  GlassMenuStyle merge(GlassMenuStyle? other) {
    if (other == null) return this;
    return GlassMenuStyle(
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
      destructiveColor: destructiveColor ?? other.destructiveColor,
      highlightColor: highlightColor ?? other.highlightColor,
      secondaryColor: secondaryColor ?? other.secondaryColor,
      disabledColor: disabledColor ?? other.disabledColor,
      separatorColor: separatorColor ?? other.separatorColor,
      paletteSelectionColor:
          paletteSelectionColor ?? other.paletteSelectionColor,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassMenuStyle? lerp(GlassMenuStyle? a, GlassMenuStyle? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    final color = snapNull(GlassDynamicColor.lerp);
    return GlassMenuStyle(
      textStyle: snapNull(TextStyle.lerp)(a.textStyle, b.textStyle, t),
      destructiveColor: color(a.destructiveColor, b.destructiveColor, t),
      highlightColor: color(a.highlightColor, b.highlightColor, t),
      secondaryColor: color(a.secondaryColor, b.secondaryColor, t),
      disabledColor: color(a.disabledColor, b.disabledColor, t),
      separatorColor: color(a.separatorColor, b.separatorColor, t),
      paletteSelectionColor: color(
        a.paletteSelectionColor,
        b.paletteSelectionColor,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassMenuStyle &&
      other.textStyle == textStyle &&
      other.destructiveColor == destructiveColor &&
      other.highlightColor == highlightColor &&
      other.secondaryColor == secondaryColor &&
      other.disabledColor == disabledColor &&
      other.separatorColor == separatorColor &&
      other.paletteSelectionColor == paletteSelectionColor;

  @override
  int get hashCode => Object.hash(
    textStyle,
    destructiveColor,
    highlightColor,
    secondaryColor,
    disabledColor,
    separatorColor,
    paletteSelectionColor,
  );
}

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
    this.paletteSelectionColor = const Color(0x10000000),
  });

  /// The table for the brightness at [context] under [style] and the
  /// theme's style.
  factory MenuAppearance.of(BuildContext context, GlassMenuStyle? style) {
    final table = switch (GlassTraits.of(context).brightness) {
      Brightness.dark => dark,
      Brightness.light => light,
    };
    final look = (style ?? const GlassMenuStyle()).merge(
      GlassTheme.of(context).menuStyle,
    );
    if (look == const GlassMenuStyle()) return table;
    Color color(Color? override, Color fallback) => override == null
        ? fallback
        : GlassDynamicColor.resolve(override, context);
    final text = table.textStyle.merge(look.textStyle);
    return MenuAppearance(
      textStyle: text.copyWith(
        color: color(text.color, table.textStyle.color!),
      ),
      iconSize: table.iconSize,
      destructiveColor: color(look.destructiveColor, table.destructiveColor),
      highlightColor: color(look.highlightColor, table.highlightColor),
      secondaryColor: color(look.secondaryColor, table.secondaryColor),
      disabledColor: color(look.disabledColor, table.disabledColor),
      separatorColor: color(look.separatorColor, table.separatorColor),
      paletteSelectionColor: color(
        look.paletteSelectionColor,
        table.paletteSelectionColor,
      ),
    );
  }

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
    paletteSelectionColor: Color(0x18FFFFFF),
  );

  @override
  bool operator ==(Object other) =>
      other is MenuAppearance &&
      other.textStyle == textStyle &&
      other.iconSize == iconSize &&
      other.destructiveColor == destructiveColor &&
      other.highlightColor == highlightColor &&
      other.secondaryColor == secondaryColor &&
      other.disabledColor == disabledColor &&
      other.separatorColor == separatorColor &&
      other.paletteSelectionColor == paletteSelectionColor;

  @override
  int get hashCode => Object.hash(
    textStyle,
    iconSize,
    destructiveColor,
    highlightColor,
    secondaryColor,
    disabledColor,
    separatorColor,
    paletteSelectionColor,
  );
}
