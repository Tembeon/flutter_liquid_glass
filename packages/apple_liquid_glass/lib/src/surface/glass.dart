import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The glass a surface is made of: regular or clear, and an optional tint.
///
/// UIKit: `UIGlassEffect`. SwiftUI: `Glass`. A prominent button is glass
/// with a [tint].
@immutable
final class Glass {
  /// The regular glass, the one bars, buttons and menus use, filled with
  /// [tint] when given.
  const Glass.regular({this.tint}) : isClear = false;

  /// The clear glass, for surfaces over rich media: it passes the backdrop
  /// through almost untouched, so its content needs contrast of its own.
  /// Filled with [tint] when given.
  const Glass.clear({this.tint}) : isClear = true;

  /// The color the glass is filled with, or null for untinted glass.
  final Color? tint;

  /// Whether this is the clear glass.
  final bool isClear;

  @override
  bool operator ==(Object other) =>
      other is Glass && other.isClear == isClear && other.tint == tint;

  @override
  int get hashCode => Object.hash(isClear, tint);
}

/// The UIKit glass family a surface belongs to.
///
/// Renderers read it to give each family its look (fill, shadow).
enum GlassRole {
  /// A tab bar, toolbar or navigation bar platter.
  bar,

  /// A button or another free-standing control.
  control,

  /// A card that floats over the page: a menu, popover, alert or sheet.
  panel,

  /// A selection that slides over its control, or a knob or thumb that
  /// lifts into a clear lens under the finger.
  lens,

  /// A plain fill that draws no glass: a switch's or segmented control's
  /// track, a slider's track and fill, a disabled search field.
  track,
}

/// The package's own surface a [GlassRole] is drawn as, where its
/// renderers draw it apart from the rest of the role.
@internal
enum GlassPart {
  /// The lens a tab bar's selection slides as, over the bar.
  tabBarLens,

  /// The knob of a switch.
  knob,

  /// The thumb of a slider.
  thumb,

  /// A menu's, popover's or alert's card.
  menu,

  /// A sheet's card.
  sheet;

  /// The role the part belongs to.
  GlassRole get role => switch (this) {
    tabBarLens || knob || thumb => GlassRole.lens,
    menu || sheet => GlassRole.panel,
  };
}
