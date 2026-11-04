import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// The outline of a glass body.
///
/// UIKit: the shape of a `UIGlassEffect` view (`cornerConfiguration`).
/// SwiftUI: the shape in `.glassEffect(_:in:)`.
///
/// A corner radius larger than half the short side of the box the body is
/// drawn in draws as half of it, as Flutter's rounded borders do, so
/// [capsule] fits any box.
@immutable
sealed class GlassShape {
  /// Continuous (superellipse) corners of [radius], UIKit's
  /// `.continuous` corner curve.
  const factory GlassShape.superellipse(double radius) = _Superellipse;

  /// Circular corners of [radius].
  const factory GlassShape.roundedRect(double radius) = _RoundedRect;

  /// An ellipse filling the box.
  const factory GlassShape.oval() = _Oval;

  const GlassShape._();

  /// A capsule: superellipse corners as round as the box allows.
  static const GlassShape capsule = GlassShape.superellipse(10000);

  /// The renderer's shape of this outline.
  @internal
  LiquidShape get liquid;

  /// The corner radius drawn in [box].
  @internal
  double radiusIn(Rect box);

  /// The edge of the body drawn in [box].
  @internal
  Path pathIn(Rect box) => liquid.getOuterPath(box);

  /// Clips [child] to the body drawn in its box.
  @internal
  Widget clip(Widget? child);
}

final class _Superellipse extends GlassShape {
  const _Superellipse(this.radius) : super._();

  final double radius;

  @override
  LiquidShape get liquid => LiquidRoundedSuperellipse(borderRadius: radius);

  @override
  double radiusIn(Rect box) => math.min(radius, box.shortestSide / 2);

  @override
  Widget clip(Widget? child) => ClipRSuperellipse(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
    child: child,
  );

  @override
  bool operator ==(Object other) =>
      other is _Superellipse && other.radius == radius;

  @override
  int get hashCode => Object.hash(_Superellipse, radius);
}

final class _RoundedRect extends GlassShape {
  const _RoundedRect(this.radius) : super._();

  final double radius;

  @override
  LiquidShape get liquid => LiquidRoundedRectangle(borderRadius: radius);

  @override
  double radiusIn(Rect box) => math.min(radius, box.shortestSide / 2);

  @override
  Widget clip(Widget? child) => ClipRRect(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
    child: child,
  );

  @override
  bool operator ==(Object other) =>
      other is _RoundedRect && other.radius == radius;

  @override
  int get hashCode => Object.hash(_RoundedRect, radius);
}

final class _Oval extends GlassShape {
  const _Oval() : super._();

  @override
  LiquidShape get liquid => const LiquidOval();

  @override
  double radiusIn(Rect box) => box.shortestSide / 2;

  @override
  Widget clip(Widget? child) => ClipOval(child: child);

  @override
  bool operator ==(Object other) => other is _Oval;

  @override
  int get hashCode => (_Oval).hashCode;
}
