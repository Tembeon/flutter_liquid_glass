import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// `UIScrollView.DecelerationRate.normal`: the share of its speed a flick
/// keeps each millisecond.
@internal
const double normalDecelerationRate = 0.998;

/// Direction along an axis in which a [ProjectionExit] triggers.
enum ProjectionDirection {
  /// Triggers past [ProjectionExit.threshold] toward larger positions (`+1`).
  forward,

  /// Triggers past [ProjectionExit.threshold] toward smaller positions (`-1`).
  backward,
}

/// Where a release lands and what it picks: the position plus the velocity
/// times [rate], the nearest of a set of stops, or an exit it passes (a
/// sheet's dismiss, a page's pop).
///
/// ```dart
/// final choice = Projection.normal.choose(
///   offset,
///   velocity,
///   stops: detents,
///   exits: [ProjectionExit(threshold: hidden / 2, flickVelocity: 1000)],
/// );
/// ```
///
/// UIKit: the `project(initialVelocity:decelerationRate:)` of Apple's
/// fluid interfaces talk at a `UIScrollView.DecelerationRate`. Flutter: a
/// `FrictionSimulation`'s `finalX`.
@immutable
final class Projection {
  /// Creates a projection [rate] seconds ahead; a projected travel shorter
  /// than [minDistance] is dropped, so a slow release lands where it is.
  const Projection({required this.rate, this.minDistance = 0});

  /// Where a flick slowing at `UIScrollView.DecelerationRate.normal`
  /// comes to rest: about 0.499 s of its velocity ahead.
  static const Projection normal = Projection(
    rate: normalDecelerationRate / (1000 * (1 - normalDecelerationRate)),
  );

  /// How many seconds of the release velocity the landing adds.
  final double rate;

  /// The shortest projected travel that counts.
  final double minDistance;

  /// Where a release at [position] moving at [velocity] lands.
  double landing(double position, double velocity) {
    final ahead = velocity * rate;
    return ahead.abs() < minDistance ? position : position + ahead;
  }

  /// What a release at [position] moving at [velocity] picks: the first of
  /// [exits] it passes, in order, or else the stop nearest its [landing]
  /// (the lower index on a tie).
  ProjectionChoice choose(
    double position,
    double velocity, {
    List<double> stops = const [],
    List<ProjectionExit> exits = const [],
  }) {
    final lands = landing(position, velocity);
    for (final exit in exits) {
      if (exit.passes(lands, velocity)) return ProjectionExited(exit);
    }
    assert(stops.isNotEmpty, 'a release that exits nowhere needs a stop');
    var best = 0;
    for (var i = 1; i < stops.length; i++) {
      if ((stops[i] - lands).abs() < (stops[best] - lands).abs()) best = i;
    }
    return ProjectionStop(best, stops[best]);
  }

  @override
  bool operator ==(Object other) =>
      other is Projection &&
      other.rate == rate &&
      other.minDistance == minDistance;

  @override
  int get hashCode => Object.hash(rate, minDistance);

  @override
  String toString() => 'Projection(rate: $rate, minDistance: $minDistance)';
}

/// A way out of a release: a landing past [threshold] in [direction], or a
/// flick that way faster than [flickVelocity].
@immutable
final class ProjectionExit {
  /// Creates an exit past [threshold] in [direction] (defaults to
  /// [ProjectionDirection.forward]).
  const ProjectionExit({
    required this.threshold,
    this.direction = ProjectionDirection.forward,
    this.flickVelocity,
  });

  /// The landing past which the release exits.
  final double threshold;

  /// The direction of the exit along the axis.
  final ProjectionDirection direction;

  /// The speed in [direction] that exits wherever the release lands; none
  /// when null.
  final double? flickVelocity;

  int get _sign => direction == ProjectionDirection.forward ? 1 : -1;

  /// Whether a release that lands at [landing], moving at [velocity],
  /// takes this exit.
  bool passes(double landing, double velocity) {
    final sign = _sign;
    if (sign * (landing - threshold) > 0) return true;
    final flick = flickVelocity;
    return flick != null && sign * velocity > flick;
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectionExit &&
      other.threshold == threshold &&
      other.direction == direction &&
      other.flickVelocity == flickVelocity;

  @override
  int get hashCode => Object.hash(threshold, direction, flickVelocity);

  @override
  String toString() =>
      'ProjectionExit(threshold: $threshold, direction: $direction, '
      'flickVelocity: $flickVelocity)';
}

/// What [Projection.choose] picks.
@immutable
sealed class ProjectionChoice {
  const ProjectionChoice();
}

/// The release settles on stop [index], at [value].
@immutable
final class ProjectionStop extends ProjectionChoice {
  /// Creates the choice of stop [index].
  const ProjectionStop(this.index, this.value);

  /// The index of the stop in the list given to [Projection.choose].
  final int index;

  /// The stop itself.
  final double value;

  @override
  bool operator ==(Object other) =>
      other is ProjectionStop && other.index == index && other.value == value;

  @override
  int get hashCode => Object.hash(index, value);

  @override
  String toString() => 'ProjectionStop($index, $value)';
}

/// The release takes [exit].
@immutable
final class ProjectionExited extends ProjectionChoice {
  /// Creates the choice of [exit].
  const ProjectionExited(this.exit);

  /// The exit taken.
  final ProjectionExit exit;

  @override
  bool operator ==(Object other) =>
      other is ProjectionExited && other.exit == exit;

  @override
  int get hashCode => exit.hashCode;

  @override
  String toString() => 'ProjectionExited($exit)';
}
