import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The outline of a glass body.
///
/// UIKit: the shape of a `UIGlassEffect` view (`cornerConfiguration`).
/// SwiftUI: the shape in `.glassEffect(_:in:)`.
///
/// A corner radius larger than half the short side of the box the body is
/// drawn in draws as half of it, as Flutter's rounded borders do, so
/// [capsule] fits any box.
///
/// The kinds are [GlassSuperellipse], [GlassRoundedRect] and [GlassOval]: a
/// renderer of its own switches over them, or draws [pathIn].
@immutable
sealed class GlassShape {
  /// Continuous (superellipse) corners of [radius], UIKit's
  /// `.continuous` corner curve.
  const factory GlassShape.superellipse(double radius) = GlassSuperellipse;

  /// Circular corners of [radius].
  const factory GlassShape.roundedRect(double radius) = GlassRoundedRect;

  /// An ellipse filling the box.
  const factory GlassShape.oval() = GlassOval;

  const GlassShape._();

  /// A capsule: superellipse corners as round as the box allows.
  static const GlassShape capsule = GlassShape.superellipse(10000);

  /// The corner radius of the body drawn in [box].
  double radiusIn(Rect box);

  /// The edge of the body drawn in [box].
  Path pathIn(Rect box);
}

/// A [GlassShape] with continuous (superellipse) corners of [radius].
final class GlassSuperellipse extends GlassShape {
  /// Creates the shape, as [GlassShape.superellipse] does.
  const GlassSuperellipse(this.radius) : super._();

  /// The radius of the corners.
  final double radius;

  @override
  double radiusIn(Rect box) => math.min(radius, box.shortestSide / 2);

  @override
  Path pathIn(Rect box) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
  ).getOuterPath(box);

  @override
  bool operator ==(Object other) =>
      other is GlassSuperellipse && other.radius == radius;

  @override
  int get hashCode => Object.hash(GlassSuperellipse, radius);
}

/// A [GlassShape] with circular corners of [radius].
final class GlassRoundedRect extends GlassShape {
  /// Creates the shape, as [GlassShape.roundedRect] does.
  const GlassRoundedRect(this.radius) : super._();

  /// The radius of the corners.
  final double radius;

  @override
  double radiusIn(Rect box) => math.min(radius, box.shortestSide / 2);

  @override
  Path pathIn(Rect box) => RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
  ).getOuterPath(box);

  @override
  bool operator ==(Object other) =>
      other is GlassRoundedRect && other.radius == radius;

  @override
  int get hashCode => Object.hash(GlassRoundedRect, radius);
}

/// A [GlassShape] that is an ellipse filling its box.
final class GlassOval extends GlassShape {
  /// Creates the shape, as [GlassShape.oval] does.
  const GlassOval() : super._();

  @override
  double radiusIn(Rect box) => box.shortestSide / 2;

  @override
  Path pathIn(Rect box) => const OvalBorder().getOuterPath(box);

  @override
  bool operator ==(Object other) => other is GlassOval;

  @override
  int get hashCode => (GlassOval).hashCode;
}
