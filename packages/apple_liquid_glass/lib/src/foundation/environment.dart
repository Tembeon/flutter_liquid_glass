import 'dart:math' as math;
import 'dart:ui' show Display;

import 'package:apple_liquid_glass/src/foundation/platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The kind of device an app runs on, which decides where its bars go
/// before any size does: the Duo's inner display and an iPad window of the
/// same size are both regular in width and height, yet the Duo keeps its
/// tabs at the bottom and the iPad puts them at the top.
///
/// UIKit: `UIUserInterfaceIdiom`.
enum GlassFormFactor {
  /// A phone, the Duo's two displays included.
  phone,

  /// A tablet, in a window or full screen.
  tablet,

  /// A desktop window.
  desktop,
}

/// How much room the window has along one axis.
///
/// UIKit: `UIUserInterfaceSizeClass`.
enum GlassSizeClass {
  /// Little room: a phone's width, a phone's height in landscape, a narrow
  /// window.
  compact,

  /// Room for more than one column or for the full height of bars.
  regular,
}

/// The physical side of the window a [GlassBarColumn] runs along, the same
/// whatever the reading direction.
enum GlassBarColumnSide {
  /// Along the left edge.
  left,

  /// Along the right edge.
  right,
}

/// The column iPhone Duo keeps along one side of the window for an app's
/// bars, beside its status cluster.
///
/// Where the system wants the column and the room it reserved for it are two
/// facts: beside another app in the system's Split View, iOS wants the column
/// on the left but leaves a Flutter view no room for it.
@immutable
final class GlassBarColumn {
  /// A column on [side] with [reservedWidth] of the window's padding.
  const GlassBarColumn({
    required GlassBarColumnSide this.side,
    required this.reservedWidth,
  }) : assert(reservedWidth >= 0, 'A column reserves no negative room');

  const GlassBarColumn._none() : side = null, reservedWidth = 0;

  /// No column: every device but iPhone Duo, and the Duo when the app asked
  /// for the classic layout.
  static const GlassBarColumn none = GlassBarColumn._none();

  /// The side the system wants the column on, or null for [none].
  final GlassBarColumnSide? side;

  /// The room the system reserved for the column in the window's padding,
  /// 84 points on iPhone Duo; 0 where it wants a column and reserved none.
  final double reservedWidth;

  @override
  bool operator ==(Object other) =>
      other is GlassBarColumn &&
      other.side == side &&
      other.reservedWidth == reservedWidth;

  @override
  int get hashCode => Object.hash(side, reservedWidth);

  @override
  String toString() => side == null
      ? 'GlassBarColumn.none'
      : 'GlassBarColumn(${side!.name}, $reservedWidth)';
}

/// The window buttons in the first row of the window: a close, minimize and
/// zoom group on an iPad in a window or on a desktop whose app draws its own
/// title bar.
///
/// They are not part of the padding. Only the first row of bars makes room
/// for them, as UIKit moves a compact iPad window's navigation bar items
/// past the buttons: its first item's glass starts 16 points past them
/// (62 to 78). The content below never moves, and a centered title stays
/// on the window's center.
@immutable
final class GlassWindowControls {
  /// Buttons reaching [left] points in from the window's left edge, [right]
  /// from its right edge, or both, on a line [lineCenter] points below the
  /// window's top.
  const GlassWindowControls({this.left, this.right, this.lineCenter})
    : assert(
        (left ?? 0) >= 0 && (right ?? 0) >= 0,
        'Window buttons take no negative room',
      );

  /// No window buttons: a phone, a tablet full screen, a desktop window
  /// with a title bar of its own.
  static const GlassWindowControls none = GlassWindowControls();

  /// How far below the top padding the first row of bars centers its
  /// items: where a desktop app that draws its own title bar centers its
  /// window buttons, and where iPadOS centers an iPad window's.
  static const double rowCenter = 22;

  /// From the window's left edge to the far side of the last button at that
  /// edge (macOS, iPadOS), or null.
  final double? left;

  /// From the window's right edge to the far side of the last button at
  /// that edge (Windows), or null.
  final double? right;

  /// The vertical center of the buttons' line, from the window's top, where
  /// the system places them; null where the app places them on the first
  /// row's line, [rowCenter] below the window's top padding.
  final double? lineCenter;

  /// Whether no edge holds buttons.
  bool get isEmpty => left == null && right == null;

  @override
  bool operator ==(Object other) =>
      other is GlassWindowControls &&
      other.left == left &&
      other.right == right &&
      other.lineCenter == lineCenter;

  @override
  int get hashCode => Object.hash(left, right, lineCenter);

  @override
  String toString() =>
      'GlassWindowControls(left: $left, right: $right, '
      'lineCenter: $lineCenter)';
}

/// What the system decides about the window and what it takes of it: the
/// kind of device, the size classes, the window buttons and corners, iPhone
/// Duo's bar column and what the hardware covers.
///
/// Layouts read it instead of `Platform` checks, so a window lays out alike
/// on every desktop and in a browser.
///
/// [GlassEnvironment.of] takes what the nearest [GlassEnvironmentOverride]
/// gives, then what the operating system reported to the nearest
/// [GlassPlatformScope] (UIKit on iOS), and derives the rest:
/// - [formFactor]: a desktop operating system is a desktop. Elsewhere the
///   display decides, not the window: a shortest side under 700 points is a
///   phone, the Duo's inner display included; from 700 a tablet.
/// - [horizontalSizeClass]: a tablet or desktop window is compact below 668
///   points wide, as an iPad window is. A phone is regular from 900 wide (the
///   Plus and Pro Max in landscape, the Duo's inner display in landscape),
///   compact otherwise: the Duo's inner display in portrait, 669 wide, is
///   compact (fold passport).
/// - [verticalSizeClass]: a window is regular in height down to its minimum,
///   as an iPad window is; a phone is compact below 500 points tall, that is
///   in landscape.
/// - [barColumn]: on iOS, padding on one side alone with none at the top is
///   the Duo's column (an iPhone in landscape has both sides, an iPad the
///   top); read where the window's padding is whole, as a scaffold does.
///   Never on Android, where a camera cutout gives the same padding.
/// - [windowCornerRadius]: the display's top left corner where Flutter
///   reports it (Android), the window filling the display; elsewhere null,
///   for an app that knows its window's corners to give.
///
/// The phone thresholds are derived from the sizes UIKit documents, not
/// measured; on iOS a [GlassPlatformScope] reads the real classes.
@immutable
final class GlassEnvironment {
  /// Creates an environment; the defaults are a phone in portrait with no
  /// window buttons, column or occlusion.
  const GlassEnvironment({
    this.formFactor = GlassFormFactor.phone,
    this.horizontalSizeClass = GlassSizeClass.compact,
    this.verticalSizeClass = GlassSizeClass.regular,
    this.windowControls = GlassWindowControls.none,
    this.barColumn = GlassBarColumn.none,
    this.occlusions = const [],
    this.windowCornerRadius,
  });

  /// The environment at [context].
  factory GlassEnvironment.of(BuildContext context) {
    final given = context
        .dependOnInheritedWidgetOfExactType<_GlassEnvironmentScope>();
    final reported = GlassPlatformReport.maybeOf(context);
    final window = MediaQuery.sizeOf(context);
    final formFactor =
        given?.formFactor ??
        reported?.formFactor ??
        _formFactorOf(View.maybeOf(context)?.display, window);
    return GlassEnvironment(
      formFactor: formFactor,
      horizontalSizeClass:
          given?.horizontalSizeClass ??
          reported?.horizontalSizeClass ??
          _horizontalOf(formFactor, window),
      verticalSizeClass:
          given?.verticalSizeClass ??
          reported?.verticalSizeClass ??
          _verticalOf(formFactor, window),
      windowControls:
          given?.windowControls ??
          reported?.windowControls ??
          GlassWindowControls.none,
      barColumn:
          given?.barColumn ??
          reported?.barColumn ??
          _barColumnOf(MediaQuery.viewPaddingOf(context)),
      occlusions: given?.occlusions ?? reported?.occlusions ?? const [],
      windowCornerRadius:
          given?.windowCornerRadius ??
          MediaQuery.maybeDisplayCornerRadiiOf(context)?.topLeft.x,
    );
  }

  /// The width from which a tablet's or a desktop's window is regular
  /// across, as an iPad window is (measured), and from which a column of a
  /// split view standing beside another is.
  static const double regularWidthFrom = 668;

  static const double _tabletFrom = 700;
  static const double _phoneRegularFrom = 900;
  static const double _phoneCompactHeightBelow = 500;

  static GlassFormFactor _formFactorOf(Display? display, Size window) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux:
        return GlassFormFactor.desktop;
      case TargetPlatform.android ||
          TargetPlatform.fuchsia ||
          TargetPlatform.iOS:
        // A window is never larger than its display; a display that is not
        // reported has no size, and the window stands in for it.
        final ratio = display?.devicePixelRatio ?? 0;
        final screen = ratio > 0 ? (display!.size / ratio).shortestSide : 0.0;
        return math.max(screen, window.shortestSide) < _tabletFrom
            ? GlassFormFactor.phone
            : GlassFormFactor.tablet;
    }
  }

  static GlassSizeClass _horizontalOf(GlassFormFactor formFactor, Size window) {
    final regular = switch (formFactor) {
      GlassFormFactor.phone => window.width >= _phoneRegularFrom,
      GlassFormFactor.tablet ||
      GlassFormFactor.desktop => window.width >= regularWidthFrom,
    };
    return regular ? GlassSizeClass.regular : GlassSizeClass.compact;
  }

  static GlassSizeClass _verticalOf(GlassFormFactor formFactor, Size window) =>
      formFactor == GlassFormFactor.phone &&
          window.height < _phoneCompactHeightBelow
      ? GlassSizeClass.compact
      : GlassSizeClass.regular;

  static GlassBarColumn _barColumnOf(EdgeInsets padding) {
    if (defaultTargetPlatform != TargetPlatform.iOS || padding.top > 0) {
      return GlassBarColumn.none;
    }
    return switch ((padding.left, padding.right)) {
      (0, final right) when right > 0 => GlassBarColumn(
        side: GlassBarColumnSide.right,
        reservedWidth: right,
      ),
      (final left, 0) when left > 0 => GlassBarColumn(
        side: GlassBarColumnSide.left,
        reservedWidth: left,
      ),
      _ => GlassBarColumn.none,
    };
  }

  /// Phone, tablet or desktop.
  final GlassFormFactor formFactor;

  /// The window's size class across.
  final GlassSizeClass horizontalSizeClass;

  /// The window's size class up and down.
  final GlassSizeClass verticalSizeClass;

  /// The window buttons the first row makes room for.
  final GlassWindowControls windowControls;

  /// iPhone Duo's bar column, or [GlassBarColumn.none].
  final GlassBarColumn barColumn;

  /// What the hardware covers inside the window, such as the Duo's status
  /// cluster and camera, in the window's coordinates.
  ///
  /// They stay out of `MediaQueryData.displayFeatures`, which Flutter's
  /// dialogs and the package's presentations avoid whatever a feature's type:
  /// a sheet keeps the window's center, as UIKit's does.
  final List<Rect> occlusions;

  /// The radius of the window's corners in points, or null where it is not
  /// known. Glass that stands in from the window's edges rounds its corners
  /// concentric with them, as a floating tab sidebar does.
  final double? windowCornerRadius;

  /// Whether the window is regular across.
  bool get isRegularWidth => horizontalSizeClass == GlassSizeClass.regular;

  /// Whether the window is regular up and down.
  bool get isRegularHeight => verticalSizeClass == GlassSizeClass.regular;

  @override
  bool operator ==(Object other) =>
      other is GlassEnvironment &&
      other.formFactor == formFactor &&
      other.horizontalSizeClass == horizontalSizeClass &&
      other.verticalSizeClass == verticalSizeClass &&
      other.windowControls == windowControls &&
      other.barColumn == barColumn &&
      listEquals(other.occlusions, occlusions) &&
      other.windowCornerRadius == windowCornerRadius;

  @override
  int get hashCode => Object.hash(
    formFactor,
    horizontalSizeClass,
    verticalSizeClass,
    windowControls,
    barColumn,
    Object.hashAll(occlusions),
    windowCornerRadius,
  );

  @override
  String toString() =>
      'GlassEnvironment(${formFactor.name}, '
      '${horizontalSizeClass.name} x ${verticalSizeClass.name}, '
      'windowControls: $windowControls, barColumn: $barColumn, '
      'occlusions: $occlusions, '
      'windowCornerRadius: $windowCornerRadius)';
}

/// Gives the subtree below it what the app knows of the window: a desktop
/// app's window buttons and corners, or a pose to try a layout in. It wins
/// over what a [GlassPlatformScope] reads, wherever the two stand. A null
/// field keeps the enclosing value, reported, derived or given;
/// [GlassWindowControls.none] and [GlassBarColumn.none] take one away.
class GlassEnvironmentOverride extends StatelessWidget {
  /// Overrides the given parts of the environment for [child].
  const GlassEnvironmentOverride({
    required this.child,
    this.formFactor,
    this.horizontalSizeClass,
    this.verticalSizeClass,
    this.windowControls,
    this.barColumn,
    this.occlusions,
    this.windowCornerRadius,
    super.key,
  });

  /// See [GlassEnvironment.formFactor].
  final GlassFormFactor? formFactor;

  /// See [GlassEnvironment.horizontalSizeClass].
  final GlassSizeClass? horizontalSizeClass;

  /// See [GlassEnvironment.verticalSizeClass].
  final GlassSizeClass? verticalSizeClass;

  /// See [GlassEnvironment.windowControls].
  final GlassWindowControls? windowControls;

  /// See [GlassEnvironment.barColumn].
  final GlassBarColumn? barColumn;

  /// See [GlassEnvironment.occlusions].
  final List<Rect>? occlusions;

  /// See [GlassEnvironment.windowCornerRadius].
  final double? windowCornerRadius;

  /// The subtree the environment applies to.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final outer = context
        .dependOnInheritedWidgetOfExactType<_GlassEnvironmentScope>();
    return _GlassEnvironmentScope(
      formFactor: formFactor ?? outer?.formFactor,
      horizontalSizeClass: horizontalSizeClass ?? outer?.horizontalSizeClass,
      verticalSizeClass: verticalSizeClass ?? outer?.verticalSizeClass,
      windowControls: windowControls ?? outer?.windowControls,
      barColumn: barColumn ?? outer?.barColumn,
      occlusions: occlusions ?? outer?.occlusions,
      windowCornerRadius: windowCornerRadius ?? outer?.windowCornerRadius,
      child: child,
    );
  }
}

class _GlassEnvironmentScope extends InheritedWidget {
  const _GlassEnvironmentScope({
    required this.formFactor,
    required this.horizontalSizeClass,
    required this.verticalSizeClass,
    required this.windowControls,
    required this.barColumn,
    required this.occlusions,
    required this.windowCornerRadius,
    required super.child,
  });

  final GlassFormFactor? formFactor;
  final GlassSizeClass? horizontalSizeClass;
  final GlassSizeClass? verticalSizeClass;
  final GlassWindowControls? windowControls;
  final GlassBarColumn? barColumn;
  final List<Rect>? occlusions;
  final double? windowCornerRadius;

  @override
  bool updateShouldNotify(_GlassEnvironmentScope oldWidget) =>
      formFactor != oldWidget.formFactor ||
      horizontalSizeClass != oldWidget.horizontalSizeClass ||
      verticalSizeClass != oldWidget.verticalSizeClass ||
      windowControls != oldWidget.windowControls ||
      barColumn != oldWidget.barColumn ||
      !listEquals(occlusions, oldWidget.occlusions) ||
      windowCornerRadius != oldWidget.windowCornerRadius;
}
