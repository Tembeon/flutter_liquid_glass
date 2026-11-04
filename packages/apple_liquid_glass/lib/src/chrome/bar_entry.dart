import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:flutter/widgets.dart';

/// The look of a bar's items; a null field leaves it to the default.
///
/// The bars of a navigator are shared by its pages and their capsules
/// change from one page's into the next's, so items take their look from
/// the theme: `GlassNavigationBarStyle.itemStyle` and
/// `GlassToolbarStyle.itemStyle` of `GlassThemeData`.
@immutable
class GlassBarItemStyle {
  /// Creates a style.
  const GlassBarItemStyle({
    this.foregroundColor,
    this.prominentColor,
    this.prominentForegroundColor,
    this.textStyle,
  });

  /// The glyphs and labels of items, resolved against
  /// [WidgetState.disabled] for an item without an action; label, and
  /// tertiaryLabel disabled, by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The capsule of a prominent item; the theme's primary color, then
  /// 0x0088FF, by default.
  final Color? prominentColor;

  /// The glyph and label of a prominent item; white by default.
  final Color? prominentForegroundColor;

  /// The labels, over 17 points, medium (semibold when prominent).
  final TextStyle? textStyle;

  /// This style over [other].
  GlassBarItemStyle merge(GlassBarItemStyle? other) {
    if (other == null) return this;
    return GlassBarItemStyle(
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      prominentColor: prominentColor ?? other.prominentColor,
      prominentForegroundColor:
          prominentForegroundColor ?? other.prominentForegroundColor,
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassBarItemStyle? lerp(
    GlassBarItemStyle? a,
    GlassBarItemStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    final color = snapNull(GlassDynamicColor.lerp);
    return GlassBarItemStyle(
      foregroundColor: WidgetStateProperty.lerp<Color?>(
        a.foregroundColor,
        b.foregroundColor,
        t,
        color,
      ),
      prominentColor: color(a.prominentColor, b.prominentColor, t),
      prominentForegroundColor: color(
        a.prominentForegroundColor,
        b.prominentForegroundColor,
        t,
      ),
      textStyle: snapNull(TextStyle.lerp)(a.textStyle, b.textStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassBarItemStyle &&
      other.foregroundColor == foregroundColor &&
      other.prominentColor == prominentColor &&
      other.prominentForegroundColor == prominentForegroundColor &&
      other.textStyle == textStyle;

  @override
  int get hashCode => Object.hash(
    foregroundColor,
    prominentColor,
    prominentForegroundColor,
    textStyle,
  );
}

/// One entry of a `GlassNavigationBar` side or of a `GlassToolbar`: an item
/// or a spacer.
///
/// UIKit: `UIBarButtonItem`. SwiftUI: `ToolbarItem`. Flutter: an action of
/// `AppBar`.
///
/// Entries describe what the bar shows; they are not widgets, and the bar
/// builds them. Adjacent [GlassBarItem]s share one glass capsule, as UIKit
/// groups adjacent bar items; a [GlassBarSpacer] or a
/// [GlassBarItem.prominent] item starts a capsule of its own.
@immutable
sealed class GlassBarEntry {
  const GlassBarEntry();
}

/// A button of a bar: an icon or a label and an action.
///
/// UIKit: `UIBarButtonItem`. SwiftUI: `Button` in a `ToolbarItem`. Flutter:
/// an `IconButton` in `AppBar.actions`.
///
/// Its identity keeps it across changes of the bar, so it travels to its
/// new place instead of leaving and arriving: [key] when given; else, as
/// UIKit derives a semantic id from an item's image and then its title, the
/// icon of an [icon] that is an [Icon], else the text of a [label] that is a
/// [Text], else its place; items that repeat an identity are told apart by
/// their order. Only a [key] crosses a push: other identities belong to
/// their page.
final class GlassBarItem extends GlassBarEntry {
  /// Creates a button showing [icon] or [label].
  const GlassBarItem({
    this.key,
    this.icon,
    this.label,
    this.onPressed,
    this.semanticLabel,
  }) : assert(icon != null || label != null, 'an icon or a label'),
       prominent = false,
       child = null;

  /// Creates a button in a capsule of its own, tinted with the theme's
  /// primary color, its label semibold (UIKit `.prominent`).
  const GlassBarItem.prominent({
    this.key,
    this.icon,
    this.label,
    this.onPressed,
    this.semanticLabel,
  }) : assert(icon != null || label != null, 'an icon or a label'),
       prominent = true,
       child = null;

  /// Creates an item of custom content in the capsule, such as a segmented
  /// control (UIKit `customView`); [child] handles its own input.
  const GlassBarItem.custom({
    required Widget this.child,
    this.key,
    this.semanticLabel,
  }) : icon = null,
       label = null,
       onPressed = null,
       prominent = false;

  /// The identity of the item across changes of the bar and across pages.
  final LocalKey? key;

  /// The icon, drawn at the bar's icon size and color.
  final Widget? icon;

  /// The label, drawn in the bar's text style; shown when there is no
  /// [icon].
  final Widget? label;

  /// Called on a tap; null disables the button.
  final VoidCallback? onPressed;

  /// What screen readers announce; the label's text by default.
  final String? semanticLabel;

  /// Whether the button is a tinted capsule of its own.
  final bool prominent;

  /// The custom content of [GlassBarItem.custom].
  final Widget? child;
}

/// A break between capsules.
///
/// UIKit: `UIBarButtonItem.fixedSpace(_:)` and `flexibleSpace()`. SwiftUI:
/// `ToolbarSpacer`. Flutter: [Spacer].
final class GlassBarSpacer extends GlassBarEntry {
  /// Creates a break between capsules.
  const GlassBarSpacer() : flexible = false;

  /// Creates a break that takes a toolbar's free room: the capsules before
  /// the first flexible spacer stand at the leading side, those after the
  /// last at the trailing side, and those between share the room left in
  /// equal parts, each centered in its own. A navigation bar takes it as a
  /// plain break.
  const GlassBarSpacer.flexible() : flexible = true;

  /// Whether the spacer takes a toolbar's free room.
  final bool flexible;
}

/// How a back button names the page below.
///
/// UIKit: `UINavigationItem.BackButtonDisplayMode`.
enum GlassBackButtonDisplayMode {
  /// The chevron and the page below's title, or the previous page title
  /// the page gives.
  title,

  /// The chevron and "Back".
  generic,

  /// The chevron only.
  minimal,
}
