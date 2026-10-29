import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:flutter/widgets.dart';

/// The look of the glass widgets below a `GlassTheme`.
@immutable
class GlassThemeData {
  /// Creates a theme.
  const GlassThemeData({this.renderer = const GlassRenderer.liquid()});

  /// How every glass surface is drawn.
  final GlassRenderer renderer;

  @override
  bool operator ==(Object other) =>
      other is GlassThemeData && other.renderer == renderer;

  @override
  int get hashCode => renderer.hashCode;
}

/// Sets the look of the glass widgets below it.
///
/// Flutter: `CupertinoTheme`.
///
/// A widget that reads only the renderer ([rendererOf]) rebuilds only when
/// the renderer changes.
class GlassTheme extends StatelessWidget {
  /// Applies [data] to [child].
  const GlassTheme({required this.data, required this.child, super.key});

  /// The theme.
  final GlassThemeData data;

  /// The subtree the theme applies to.
  final Widget child;

  /// The nearest theme, or the default one.
  static GlassThemeData of(BuildContext context) =>
      InheritedModel.inheritFrom<_GlassThemeScope>(context)?.data ??
      const GlassThemeData();

  /// The nearest theme's renderer, or the default one.
  static GlassRenderer rendererOf(BuildContext context) =>
      InheritedModel.inheritFrom<_GlassThemeScope>(
        context,
        aspect: _GlassThemeAspect.renderer,
      )?.data.renderer ??
      const GlassRenderer.liquid();

  @override
  Widget build(BuildContext context) =>
      _GlassThemeScope(data: data, child: child);
}

enum _GlassThemeAspect { renderer }

class _GlassThemeScope extends InheritedModel<_GlassThemeAspect> {
  const _GlassThemeScope({required this.data, required super.child});

  final GlassThemeData data;

  @override
  bool updateShouldNotify(_GlassThemeScope oldWidget) => data != oldWidget.data;

  @override
  bool updateShouldNotifyDependent(
    _GlassThemeScope oldWidget,
    Set<_GlassThemeAspect> dependencies,
  ) => dependencies.any(
    (aspect) => switch (aspect) {
      _GlassThemeAspect.renderer => data.renderer != oldWidget.data.renderer,
    },
  );
}
