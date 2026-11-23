part of 'package:kinesis/src/motion/animation.dart';

/// The distance from critical damping (1) within which a spring is treated
/// as critically damped to avoid numerical cancellation in the overdamped form.
const double _criticalDampingTolerance = 1e-9;

/// Whether a spring of damping ratio [z] oscillates: below critical by more
/// than [_criticalDampingTolerance].
@internal
bool isUnderdamped(double z) => z < 1 - _criticalDampingTolerance;

/// Whether a spring of damping ratio [z] is solved as exactly critical.
@internal
bool isNearCritical(double z) => (z - 1).abs() <= _criticalDampingTolerance;

const double _uikitSettlingConstant = 9.2335;

/// `UIScrollView.DecelerationRate.normal`: the share of its speed a flick
/// keeps each millisecond.
@internal
const double normalDecelerationRate = 0.998;

/// A spring's settling duration times its natural frequency, at damping
/// ratio [z] > 0: UIKit's exact constant at or above critical damping,
/// `[approx]` the 0.001 envelope `ln(1000 / sqrt(1 - z^2)) / z` below.
double _settlingPhase(double z) => isUnderdamped(z)
    ? math.log(1000 / math.sqrt(1 - z * z)) / z
    : _uikitSettlingConstant;

/// How a value travels to its target: a damped spring.
///
/// UIKit: `UISpringTimingParameters`. SwiftUI: `Spring`. Flutter:
/// [SpringDescription].
///
/// A spring can be written in four equivalent forms:
/// - SwiftUI's perceptual [duration] and [bounce] ([Spring.new]);
/// - UIKit's [response] and [dampingRatio] ([Spring.response]);
/// - Physical [mass], [stiffness] and [damping] ([Spring.mass]);
/// - UIKit's legacy [settlingDuration] and [dampingRatio] ([Spring.damping]).
///
/// A bounce of 0 is critically damped, above 0 overshoots, below 0 is
/// overdamped; the damping ratio is `1 - bounce` for a bounce of 0 or more
/// and `1 / (1 + bounce)` below it.
///
/// Besides the physics a spring carries what UIKit keeps beside it: the
/// [tracking] spring used while a finger drives the value, the retarget
/// [impulse], the release [projection] and a [reduced] alternative for
/// Reduce Motion.
@immutable
final class Spring extends MotionAnimation {
  /// Creates a spring from SwiftUI's perceptual [duration], in seconds, and
  /// [bounce].
  const Spring({
    double duration = 0.5,
    double this._bounce = 0,
    this.tracking,
    this.impulse = 0,
    this.projection = normalProjection,
    this.reduced,
  }) : _response = duration,
       _dampingRatio = null,
       _mass = 1,
       _stiffness = null,
       _damping = null,
       isImmediate = false;

  /// Creates a spring from UIKit's [response], the undamped period in
  /// seconds, and [dampingRatio], where 1 is critically damped and below 1
  /// overshoots.
  const Spring.response(
    double response, {
    double this._dampingRatio = 1,
    this.tracking,
    this.impulse = 0,
    this.projection = normalProjection,
    this.reduced,
  }) : _response = response,
       _bounce = null,
       _mass = 1,
       _stiffness = null,
       _damping = null,
       isImmediate = false;

  /// Creates a spring from physical [mass], [stiffness] and [damping].
  ///
  /// UIKit: `UISpringTimingParameters(mass:stiffness:damping:)`.
  /// SwiftUI: `Spring(mass:stiffness:damping:)`.
  const Spring.mass({
    required double stiffness,
    required double damping,
    double mass = 1,
    this.tracking,
    this.impulse = 0,
    this.projection = normalProjection,
    this.reduced,
  }) : assert(mass > 0, 'mass must be positive'),
       assert(stiffness > 0, 'stiffness must be positive'),
       assert(damping >= 0, 'damping must be non-negative'),
       _mass = mass,
       _stiffness = stiffness,
       _damping = damping,
       _response = null,
       _dampingRatio = null,
       _bounce = null,
       isImmediate = false;

  /// Creates a spring whose settling duration matches [duration] seconds at
  /// [dampingRatio], matching UIKit's legacy
  /// `UIView.animate(withDuration:usingSpringWithDamping:)`.
  ///
  /// For critical or overdamped ratios (`dampingRatio >= 1`), uses UIKit's
  /// exact relation `omega = 9.2335 / duration` (`m = 1`).
  ///
  /// `[approx]` For underdamped ratios (`0 < dampingRatio < 1`), solves the
  /// analytic 0.001 envelope `omega = ln(1000 / sqrt(1 - z^2)) / (z * duration)`
  /// because UIKit's exact internal underdamped solver is unmeasured.
  factory Spring.damping({
    required double duration,
    required double dampingRatio,
    Spring? tracking,
    double impulse = 0,
    double projection = normalProjection,
    Spring? reduced,
  }) {
    assert(dampingRatio > 0, 'dampingRatio must be positive');
    if (duration <= 0) return immediate;
    final omega = _settlingPhase(dampingRatio) / duration;
    return Spring.response(
      2 * math.pi / omega,
      dampingRatio: dampingRatio,
      tracking: tracking,
      impulse: impulse,
      projection: projection,
      reduced: reduced,
    );
  }

  const Spring._immediate()
    : _response = 0,
      _dampingRatio = 1,
      _bounce = null,
      _mass = 1,
      _stiffness = null,
      _damping = null,
      tracking = null,
      impulse = 0,
      projection = 0,
      reduced = null,
      isImmediate = true;

  /// Linearly interpolates response and damping ratio between [a] and [b].
  ///
  /// The result carries the physics only: no tracking spring, impulse or
  /// Reduce Motion alternative, and the default [projection].
  factory Spring.lerp(Spring a, Spring b, double t) => Spring.response(
    a.response + (b.response - a.response) * t,
    dampingRatio: a.dampingRatio + (b.dampingRatio - a.dampingRatio) * t,
  );

  /// The [projection] of `UIScrollView.DecelerationRate.normal`, about
  /// 0.499 s: how far ahead a flick slowing at that rate comes to rest.
  static const double normalProjection =
      normalDecelerationRate / (1000 * (1 - normalDecelerationRate));

  /// A change that takes no time: the value jumps to its target.
  static const Spring immediate = Spring._immediate();

  /// SwiftUI's `.smooth`: 0.5 s, no bounce.
  static const Spring smooth = Spring();

  /// SwiftUI's `.snappy`: 0.5 s, bounce 0.15.
  static const Spring snappy = Spring(bounce: 0.15);

  /// SwiftUI's `.bouncy`: 0.5 s, bounce 0.3.
  static const Spring bouncy = Spring(bounce: 0.3);

  /// SwiftUI's `.interactiveSpring`: 0.15 s, bounce 0.15, for a value that
  /// follows a finger.
  static const Spring interactive = Spring(duration: 0.15, bounce: 0.15);

  /// UIKit's default `UISpringTimingParameters()` and keyboard curve (curve 7):
  /// mass 3, stiffness 1000, damping 500 (`dampingRatio` 4.564, settling
  /// duration 0.5058 s).
  static const Spring keyboard = Spring.mass(
    mass: 3,
    stiffness: 1000,
    damping: 500,
  );

  final double? _bounce;
  final double? _response;
  final double? _dampingRatio;
  final double _mass;
  final double? _stiffness;
  final double? _damping;

  @override
  final bool isImmediate;

  /// The spring a value follows while a finger drives it, or null to use
  /// this spring.
  final Spring? tracking;

  /// The duration, in seconds, of the push a changed target gives the
  /// value: its velocity grows by this times the change of target times
  /// the stiffness of the spring it moves on, the [tracking] spring while a
  /// finger drives it. UIKit's retarget impulse; 0 for none. A tracking
  /// spring's own impulse is not used.
  final double impulse;

  /// How far ahead, in seconds at the current velocity, a released value
  /// is projected to land (`Projection.of`), as UIKit projects a
  /// flick through a deceleration rate `r` per millisecond:
  /// `r / (1000 * (1 - r))` seconds.
  final double projection;

  @override
  final Spring? reduced;

  /// The spring mass; 1 unless constructed with [Spring.mass].
  double get mass => _mass;

  /// The undamped period, in seconds.
  double get response {
    if (_response case final value?) return value;
    return 2 * math.pi / math.sqrt(_stiffness! / _mass);
  }

  /// The damping ratio; 1 is critically damped.
  double get dampingRatio {
    if (_dampingRatio case final ratio?) return ratio;
    if (_damping case final c?) {
      return c / (2 * math.sqrt(_stiffness! * _mass));
    }
    final bounce = _bounce!;
    return bounce >= 0 ? 1 - bounce : 1 / (1 + bounce);
  }

  /// SwiftUI's perceptual duration, in seconds: the [response].
  double get duration => response;

  /// SwiftUI's bounce: `1 - dampingRatio` up to critical damping and
  /// `1 / dampingRatio - 1` beyond it.
  double get bounce {
    final bounce = _bounce;
    if (bounce != null) return bounce;
    final ratio = dampingRatio;
    return ratio <= 1 ? 1 - ratio : 1 / ratio - 1;
  }

  /// The angular frequency of the undamped spring, in radians per second.
  double get omega => _stiffness != null
      ? math.sqrt(_stiffness / _mass)
      : 2 * math.pi / response;

  /// The spring stiffness `k`.
  double get stiffness => _stiffness ?? _mass * omega * omega;

  /// The damping coefficient `c`.
  double get damping => _damping ?? 2 * dampingRatio * _mass * omega;

  /// The estimated settling duration, in seconds, matching UIKit's
  /// `CASpringAnimation.settlingDuration` / `UISpringTimingParameters`.
  ///
  /// For `dampingRatio >= 1`, uses UIKit's exact formula `9.2335 / omega`.
  /// `[approx]` For `0 < dampingRatio < 1`, uses the 0.001 envelope
  /// `ln(1000 / sqrt(1 - z^2)) / (z * omega)`. Returns [double.infinity] for
  /// undamped springs (`dampingRatio <= 0`) and 0 for [Spring.immediate].
  double get settlingDuration {
    if (isImmediate) return 0;
    final z = dampingRatio;
    if (z <= 0) return double.infinity;
    return _settlingPhase(z) / omega;
  }

  /// The spring used while a finger drives the value.
  Spring get trackingSpring => tracking ?? this;

  /// The physical description of this spring.
  ///
  /// A damping ratio within 1e-9 of 1 is described as exactly critical: the
  /// SDK picks its solution by the sign of the discriminant, and next to
  /// critical damping its overdamped form loses about 1e-8 of the distance
  /// to cancellation.
  SpringDescription get description {
    final ratio = isNearCritical(dampingRatio) ? 1.0 : dampingRatio;
    return SpringDescription(
      mass: _mass,
      stiffness: stiffness,
      damping: 2 * ratio * _mass * omega,
    );
  }

  @override
  Spring resolve({required bool reduceMotion}) =>
      reduceMotion ? (reduced ?? this) : this;

  /// A copy of this spring with the given [tracking], [impulse],
  /// [projection] and [reduced] replaced; [Spring.immediate] returns
  /// itself.
  Spring copyWith({
    Spring? tracking,
    double? impulse,
    double? projection,
    Spring? reduced,
  }) {
    if (isImmediate) return this;
    if (_stiffness != null) {
      return Spring.mass(
        mass: _mass,
        stiffness: _stiffness,
        damping: _damping!,
        tracking: tracking ?? this.tracking,
        impulse: impulse ?? this.impulse,
        projection: projection ?? this.projection,
        reduced: reduced ?? this.reduced,
      );
    }
    return Spring.response(
      response,
      dampingRatio: dampingRatio,
      tracking: tracking ?? this.tracking,
      impulse: impulse ?? this.impulse,
      projection: projection ?? this.projection,
      reduced: reduced ?? this.reduced,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Spring &&
      other.isImmediate == isImmediate &&
      other.mass == mass &&
      other.response == response &&
      other.dampingRatio == dampingRatio &&
      other.tracking == tracking &&
      other.impulse == impulse &&
      other.projection == projection &&
      other.reduced == reduced;

  @override
  int get hashCode => Object.hash(
    isImmediate,
    mass,
    response,
    dampingRatio,
    tracking,
    impulse,
    projection,
    reduced,
  );

  @override
  String toString() => isImmediate
      ? 'Spring.immediate'
      : _stiffness != null
      ? 'Spring.mass(mass: $_mass, stiffness: $_stiffness, damping: $_damping)'
      : 'Spring.response($response, dampingRatio: $dampingRatio)';
}
