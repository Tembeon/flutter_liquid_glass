import 'package:flutter/widgets.dart';

/// Says that [color] is what lies under the glass in [child], so the glass
/// reads nothing of the screen: no copy, no pass, no blur.
///
/// [GlassListSection] and [GlassSliverListSection] say it for their cards. A
/// card of the app's own says it with this widget, around the content it
/// paints on an opaque color. A translucent [color] reads the screen as
/// usual. So does a [null] one, for glass in [child] over content of its own,
/// such as a photo on a card.
///
/// NEAR: what is painted between the color and the glass does not show
/// through the glass, such as a separator its rim would bend. A button on a
/// plain card is 0.02 levels of 255 off the read on average and 16 at most, at
/// its rim (host test, 3 dpr). Thumbs and other lifted lenses keep reading,
/// because what they magnify is the point.
class GlassSolidBackdrop extends InheritedWidget {
  /// Creates the scope.
  const GlassSolidBackdrop({
    required this.color,
    required super.child,
    super.key,
  });

  /// The color under the glass, or null to read the screen.
  final Color? color;

  /// The color under the glass at [context], or null to read the screen.
  static Color? colorOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSolidBackdrop>()?.color;

  @override
  bool updateShouldNotify(GlassSolidBackdrop oldWidget) =>
      color != oldWidget.color;
}
