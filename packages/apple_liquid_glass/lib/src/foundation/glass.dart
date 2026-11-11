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

  /// A card that floats over the page: a menu, popover, alert or sheet.
  panel,

  /// A selection that slides over its control, or a knob or thumb that
  /// lifts into a clear lens under the finger.
  lens,

  /// A plain fill that draws no glass: a switch's or segmented control's
  /// track, a slider's track and fill, a disabled search field.
  track,
}

/// What a lens body ([GlassRole.lens]) asks of the glass it lifts into,
/// beyond its frames: how its glass shows what lies under it, as the
/// control that owns the lens measured it.
///
/// A lifted lens shows what lies under it smaller, toward its center line,
/// so the edges of the track or bar under it show inside it with the page
/// between them and the rim. A renderer that draws no shrinking glass
/// ignores it.
@immutable
final class GlassLens {
  /// Describes a lens; the defaults shrink nothing and lift a large lens.
  const GlassLens({this.shrink = 0, this.shrinkRim = 0, this.small = false});

  /// How much the glass of a fully lifted lens shrinks what lies under it,
  /// 0 not at all: 0.2 shows it at four fifths of its size.
  final double shrink;

  /// How much of the lens's long side, less its short side, the center
  /// line it shrinks toward spans, 0 a point to 1 the whole line.
  final double shrinkRim;

  /// Whether the lens is a small one, a knob or a thumb, whose glass bends
  /// and frosts what lies under it strongly at rest and lifts clear; a
  /// large lens, a selection, rests clear.
  final bool small;

  @override
  bool operator ==(Object other) =>
      other is GlassLens &&
      other.shrink == shrink &&
      other.shrinkRim == shrinkRim &&
      other.small == small;

  @override
  int get hashCode => Object.hash(shrink, shrinkRim, small);
}
