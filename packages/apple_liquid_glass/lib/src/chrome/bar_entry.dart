import 'package:flutter/widgets.dart';

/// One entry of a side of a `GlassNavigationBar`: an item or a spacer.
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
