import 'package:flutter/widgets.dart';

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

  /// The lens a selection slides as: a segmented control's or tab bar's.
  lens,

  /// The thumb of a switch or slider.
  knob,

  /// A control's track and a slider's fill: the plain bar under a lens or a
  /// knob.
  track,

  /// A menu's card.
  menu,

  /// A sheet's card.
  sheet,
}
