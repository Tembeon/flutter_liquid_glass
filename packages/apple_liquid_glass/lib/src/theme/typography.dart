import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Apple's Dynamic Type text styles, each on its own size curve.
///
/// UIKit: `UIFont.TextStyle`. SwiftUI: `Font.TextStyle`.
///
/// The sizes per text size setting, from extra small through the five
/// accessibility sizes, are Apple's published Dynamic Type table (Human
/// Interface Guidelines, iOS); the weights are the styles' own. Not
/// measured on iOS 27.
enum GlassTextRole {
  /// UIKit's large title text style; a navigation bar's large title is
  /// bold.
  largeTitle(FontWeight.w400, [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60]),

  /// A first-level title.
  title1(FontWeight.w400, [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58]),

  /// A second-level title.
  title2(FontWeight.w400, [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56]),

  /// A third-level title.
  title3(FontWeight.w400, [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55]),

  /// A heading.
  headline(FontWeight.w600, [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]),

  /// Body text.
  body(FontWeight.w400, [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]),

  /// A callout.
  callout(FontWeight.w400, [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 51]),

  /// A subheading.
  subheadline(FontWeight.w400, [
    12,
    13,
    14,
    15,
    17,
    19,
    21,
    25,
    30,
    36,
    42,
    49,
  ]),

  /// A footnote.
  footnote(FontWeight.w400, [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44]),

  /// A standard caption.
  caption1(FontWeight.w400, [11, 11, 11, 12, 14, 16, 18, 22, 26, 32, 37, 43]),

  /// A small caption.
  caption2(FontWeight.w400, [11, 11, 11, 11, 13, 15, 17, 20, 24, 29, 34, 40]);

  const GlassTextRole(this.weight, this.sizes);

  /// The weight of the style.
  final FontWeight weight;

  /// The size at every text size setting, extra small to the largest
  /// accessibility size.
  final List<double> sizes;

  /// The size at the default setting, large.
  double get size => sizes[3];

  /// The style at the default setting.
  TextStyle get style => TextStyle(fontSize: size, fontWeight: weight);

  /// The size this role takes where text is scaled by [scaler].
  ///
  /// The setting is read off the size [scaler] gives body text, the size
  /// iOS reports its text scale by, and placed on this role's own curve:
  /// a caption does not grow as fast as body text. Between settings the
  /// sizes interpolate linearly, and beyond the ends they continue the
  /// last step.
  double sizeFor(TextScaler scaler) {
    final base = scaler is _RoleTextScaler ? scaler.base : scaler;
    final setting = _position(body.sizes, base.scale(body.size));
    return _at(sizes, setting);
  }

  static double _position(List<double> curve, double value) {
    var i = 0;
    while (i < curve.length - 2 && value > curve[i + 1]) {
      i++;
    }
    final step = curve[i + 1] - curve[i];
    return i + (value - curve[i]) / step;
  }

  static double _at(List<double> curve, double position) {
    final i = position.floor().clamp(0, curve.length - 2);
    return curve[i] + (curve[i + 1] - curve[i]) * (position - i);
  }
}

/// Merges a [GlassTextRole] into the default text style of [child], scaled
/// on that role's own Dynamic Type curve.
///
/// Flutter: `DefaultTextStyle.merge`.
///
/// Text below takes the role's size at the ambient text size setting
/// instead of Flutter's single linear scale; other sizes below scale by the
/// same factor. A nested one scales from the ambient setting, not from the
/// enclosing role.
class GlassDefaultTextStyle extends StatelessWidget {
  /// Applies [role] to the text in [child].
  const GlassDefaultTextStyle({
    required this.role,
    required this.child,
    super.key,
  });

  /// The text style.
  final GlassTextRole role;

  /// The subtree the style applies to.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;
    final base = scaler is _RoleTextScaler ? scaler.base : scaler;
    return MediaQuery(
      data: media.copyWith(
        textScaler: _RoleTextScaler(base, role.sizeFor(base) / role.size),
      ),
      child: Builder(
        builder: (context) => DefaultTextStyle.merge(
          style: resolveGlassText(role.style, context),
          child: child,
        ),
      ),
    );
  }
}

@immutable
final class _RoleTextScaler extends TextScaler {
  const _RoleTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => fontSize * factor;

  @override
  double get textScaleFactor => factor;

  @override
  bool operator ==(Object other) =>
      other is _RoleTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// [style] as glass widgets paint it at [context]: in the theme's font,
/// and, for the system font on Apple platforms, with what CoreText applies
/// to it by itself and Flutter does not.
///
/// That is the optical size axis (`opsz`, the painted point size), UIKit's
/// weight axis values (`wght` 510 for medium, 590 for semibold) and SF
/// Pro's size-dependent tracking ([glassTracking]), all at the size the
/// ambient text scaler paints. Under Bold Text the weight axis is left to
/// Flutter's bold, an approximation: iOS's bold weights are not measured.
@internal
TextStyle resolveGlassText(TextStyle style, BuildContext context) {
  final family = GlassTheme.of(context).fontFamily;
  final themed = style.fontFamily == null && family != null
      ? style.copyWith(fontFamily: family)
      : style;
  if (!_appleSystemFont || !_isSystemFamily(themed.fontFamily)) return themed;
  final size =
      themed.fontSize ??
      DefaultTextStyle.of(context).style.fontSize ??
      kDefaultFontSize;
  final painted = MediaQuery.textScalerOf(context).scale(size);
  final wght = GlassTraits.of(context).boldText
      ? null
      : _weightAxis(themed.fontWeight ?? FontWeight.w400);
  return themed.copyWith(
    letterSpacing: themed.letterSpacing ?? glassTracking(painted),
    fontVariations:
        themed.fontVariations ??
        [
          FontVariation('opsz', painted),
          if (wght != null) FontVariation('wght', wght),
        ],
  );
}

bool get _appleSystemFont =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

bool _isSystemFamily(String? family) => switch (family) {
  null || '.AppleSystemUIFont' || 'CupertinoSystemText' => true,
  _ => false,
};

double? _weightAxis(FontWeight weight) => switch (weight) {
  FontWeight.w400 => 400,
  FontWeight.w500 => 510,
  FontWeight.w600 => 590,
  FontWeight.w700 => 700,
  _ => null,
};

/// SF Pro's tracking at [size], in logical pixels per glyph.
///
/// Measured on iOS 27 as the advance CoreText gives the system font at
/// [size] minus the advance of the same instance without tracking; it
/// matches Apple's published SF Pro tracking table (17 pt -0.43, 13 pt
/// -0.08, 12 pt 0, 28 pt +0.38). Linear between measured sizes, 0 from
/// 80 pt up, the 6 pt value below 6 pt (typography passport).
@internal
double glassTracking(double size) {
  const table = _tracking;
  if (size <= table.first.$1) return table.first.$2;
  if (size >= table.last.$1) return table.last.$2;
  var i = 1;
  while (size > table[i].$1) {
    i++;
  }
  final (s0, t0) = table[i - 1];
  final (s1, t1) = table[i];
  return t0 + (t1 - t0) * (size - s0) / (s1 - s0);
}

const List<(double, double)> _tracking = [
  (6, 0.240),
  (7, 0.228),
  (8, 0.203),
  (9, 0.167),
  (10, 0.117),
  (11, 0.064),
  (12, 0),
  (13, -0.076),
  (14, -0.150),
  (15, -0.234),
  (16, -0.313),
  (17, -0.431),
  (18, -0.440),
  (19, -0.446),
  (20, -0.449),
  (21, -0.359),
  (22, -0.258),
  (23, -0.101),
  (24, 0.070),
  (25, 0.135),
  (26, 0.216),
  (27, 0.290),
  (28, 0.383),
  (29, 0.382),
  (30, 0.395),
  (31, 0.393),
  (32, 0.407),
  (33, 0.387),
  (34, 0.382),
  (35, 0.376),
  (36, 0.369),
  (37, 0.361),
  (38, 0.372),
  (39, 0.362),
  (40, 0.371),
  (44, 0.365),
  (48, 0.352),
  (56, 0.301),
  (64, 0.219),
  (72, 0.105),
  (80, 0),
];
