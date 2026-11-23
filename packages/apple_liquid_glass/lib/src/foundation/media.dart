import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What a glass overlay reads of the screen's insets.
extension GlassMediaQueryData on MediaQueryData {
  /// The bottom inset an overlay keeps clear: the larger of the safe area's
  /// and the keyboard's.
  double get bottomAboveKeyboard => math.max(padding.bottom, viewInsets.bottom);

  /// The safe area with its bottom grown to [bottomAboveKeyboard].
  EdgeInsets get paddingAboveKeyboard =>
      padding.copyWith(bottom: bottomAboveKeyboard);
}

/// The band at the top of a desktop window that holds the window's own
/// buttons when the app draws no title bar, which the app counts in the top
/// of `MediaQueryData.padding` so that its content stays clear of them.
///
/// Menus, popovers and the date picker's overlay cover the band, as a menu
/// covers a window's title bar: they keep clear of the top padding without
/// it ([overlayPaddingOf]). An app that merges such a band into the padding
/// names its [height] here, beside that padding and above its `Navigator`,
/// whose overlay the presentations are laid out in.
class GlassWindowBand extends InheritedWidget {
  /// Names a band [height] points tall at the top of the padding of
  /// [child].
  const GlassWindowBand({
    required this.height,
    required super.child,
    super.key,
  });

  /// How much of the top padding the band takes.
  final double height;

  /// The height of the band around [context], or 0 without a
  /// [GlassWindowBand].
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassWindowBand>()?.height ??
      0;

  /// The insets a menu, popover or other floating layer keeps clear around
  /// [context]: the safe area above the keyboard
  /// ([GlassMediaQueryData.paddingAboveKeyboard]) without the window band
  /// at its top.
  static EdgeInsets overlayPaddingOf(BuildContext context) {
    final padding = MediaQuery.of(context).paddingAboveKeyboard;
    return padding.copyWith(top: math.max(0, padding.top - of(context)));
  }

  @override
  bool updateShouldNotify(GlassWindowBand oldWidget) =>
      oldWidget.height != height;
}
