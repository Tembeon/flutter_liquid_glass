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

/// The window buttons at one edge of the window's first row, which the
/// system or the app draws and glass only makes room for.
@immutable
final class GlassWindowControlsEdge {
  /// An edge whose buttons reach [width] in from the window's edge, the
  /// first of them [field] in.
  const GlassWindowControlsEdge({required this.width, this.field = 0})
    : assert(
        field >= 0 && field <= width,
        'The first button starts within the edge',
      );

  /// From the window's edge to the far side of the last button.
  final double width;

  /// From the window's edge to the near side of the first button: a bar item
  /// beside the buttons keeps the same field from the last of them.
  final double field;

  @override
  bool operator ==(Object other) =>
      other is GlassWindowControlsEdge &&
      other.width == width &&
      other.field == field;

  @override
  int get hashCode => Object.hash(width, field);

  @override
  String toString() => 'GlassWindowControlsEdge($width, field: $field)';
}

/// The window buttons in the first row of the window: a close, minimize and
/// zoom group on an iPad in a window or on a desktop whose app draws its own
/// title bar.
///
/// They are not part of the padding. Only the first row of bars makes room
/// for them, centered on their line, as UIKit moves the first row's items
/// past the buttons of an iPad window; the content below never moves.
@immutable
final class GlassWindowControls {
  /// Buttons at the [left] edge, the [right] edge or both, on a line
  /// [lineCenter] points below the window's top.
  const GlassWindowControls({this.left, this.right, this.lineCenter});

  /// No window buttons: a phone, a tablet full screen, a desktop window
  /// with a title bar of its own.
  static const GlassWindowControls none = GlassWindowControls();

  /// The buttons at the left edge of the window (macOS, iPadOS), or null.
  final GlassWindowControlsEdge? left;

  /// The buttons at the right edge of the window (Windows), or null.
  final GlassWindowControlsEdge? right;

  /// The vertical center of the buttons' line, from the window's top, where
  /// the system places them; null where the app places them on the first
  /// row's line, as a desktop app does through its runner.
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
/// kind of device, the size classes, the window buttons, iPhone Duo's bar
/// column and what the hardware covers.
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
///   Plus and Pro Max in landscape) or with both sides from 668 (the Duo's
///   inner display either way), compact otherwise.
/// - [verticalSizeClass]: a window is regular in height down to its minimum,
///   as an iPad window is; a phone is compact below 500 points tall, that is
///   in landscape.
/// - [barColumn]: on iOS, padding on one side alone with none at the top is
///   the Duo's column (an iPhone in landscape has both sides, an iPad the
///   top); read where the window's padding is whole, as a scaffold does.
///   Never on Android, where a camera cutout gives the same padding.
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
      windowControls: given?.windowControls ?? GlassWindowControls.none,
      barColumn:
          given?.barColumn ??
          reported?.barColumn ??
          _barColumnOf(MediaQuery.viewPaddingOf(context)),
      occlusions: given?.occlusions ?? reported?.occlusions ?? const [],
    );
  }

  static const double _tabletFrom = 700;
  static const double _windowRegularFrom = 668;
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
      GlassFormFactor.phone =>
        window.width >= _phoneRegularFrom ||
            window.shortestSide >= _windowRegularFrom,
      GlassFormFactor.tablet ||
      GlassFormFactor.desktop => window.width >= _windowRegularFrom,
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
      listEquals(other.occlusions, occlusions);

  @override
  int get hashCode => Object.hash(
    formFactor,
    horizontalSizeClass,
    verticalSizeClass,
    windowControls,
    barColumn,
    Object.hashAll(occlusions),
  );

  @override
  String toString() =>
      'GlassEnvironment(${formFactor.name}, '
      '${horizontalSizeClass.name} x ${verticalSizeClass.name}, '
      'windowControls: $windowControls, barColumn: $barColumn, '
      'occlusions: $occlusions)';
}

/// Gives the subtree below it what the app knows of the window: a desktop
/// app's window buttons, or a pose to try a layout in. It wins over what a
/// [GlassPlatformScope] reads, wherever the two stand. A null field keeps the
/// enclosing value, reported, derived or given; [GlassWindowControls.none]
/// and [GlassBarColumn.none] take one away.
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
    required super.child,
  });

  final GlassFormFactor? formFactor;
  final GlassSizeClass? horizontalSizeClass;
  final GlassSizeClass? verticalSizeClass;
  final GlassWindowControls? windowControls;
  final GlassBarColumn? barColumn;
  final List<Rect>? occlusions;

  @override
  bool updateShouldNotify(_GlassEnvironmentScope oldWidget) =>
      formFactor != oldWidget.formFactor ||
      horizontalSizeClass != oldWidget.horizontalSizeClass ||
      verticalSizeClass != oldWidget.verticalSizeClass ||
      windowControls != oldWidget.windowControls ||
      barColumn != oldWidget.barColumn ||
      !listEquals(occlusions, oldWidget.occlusions);
}
