import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// One side of a tab switch's cross-fade: a spring's response and the delay
/// before it starts, in seconds.
typedef TabSwitchStep = ({double response, double delay});

/// UIKit's cross-fade between a tab controller's pages (iOS 27, read from
/// UIKit, notes private; not measured): the page that goes shrinks to
/// [fadedOutScale] and fades out, the page that comes fades in over it and
/// grows from [fadedOutScale], each on its own spring after its own delay,
/// critically damped.
@immutable
final class TabSwitchSpec {
  /// Creates a spec.
  const TabSwitchSpec({
    required this.fadedOutScale,
    required this.fadeOut,
    required this.scaleOut,
    required this.fadeIn,
    required this.scaleIn,
  });

  /// A window compact across.
  static const compact = TabSwitchSpec(
    fadedOutScale: 0.9933,
    fadeOut: (response: 0.1333, delay: 0.1833),
    scaleOut: (response: 0.2, delay: 0),
    fadeIn: (response: 0.1333, delay: 0.05),
    scaleIn: (response: 0.4, delay: 0.067),
  );

  /// A window regular across.
  static const regular = TabSwitchSpec(
    fadedOutScale: 0.99,
    fadeOut: (response: 0.2, delay: 0.275),
    scaleOut: (response: 0.3, delay: 0),
    fadeIn: (response: 0.2, delay: 0.075),
    scaleIn: (response: 0.6, delay: 0.1),
  );

  /// The scale of a page faded out.
  final double fadedOutScale;

  /// The going page's fade.
  final TabSwitchStep fadeOut;

  /// The going page's shrink.
  final TabSwitchStep scaleOut;

  /// The coming page's fade.
  final TabSwitchStep fadeIn;

  /// The coming page's growth.
  final TabSwitchStep scaleIn;
}

/// How a tab scaffold's page goes and the chosen one comes: [goingOpacity]
/// and [goingScale] of the page that goes, [comingOpacity] and
/// [comingScale] of the one that comes, by a [TabSwitchSpec]. Under Reduce
/// Motion the pages only fade.
final class TabSwitchMotion {
  /// Creates the switch at rest, nothing going, on [clock].
  TabSwitchMotion({required MotionClock clock})
    : goingOpacity = MotionValue<double>(0, clock: clock),
      goingScale = MotionValue<double>(1, clock: clock),
      comingOpacity = MotionValue<double>(1, clock: clock),
      comingScale = MotionValue<double>(1, clock: clock);

  /// The opacity of the page that goes.
  final MotionValue<double> goingOpacity;

  /// The scale of the page that goes.
  final MotionValue<double> goingScale;

  /// The opacity of the page that comes.
  final MotionValue<double> comingOpacity;

  /// The scale of the page that comes.
  final MotionValue<double> comingScale;

  /// Starts a switch by [spec], from a page at rest to the chosen one;
  /// [reduceMotion] keeps both at full size.
  void start(TabSwitchSpec spec, {required bool reduceMotion}) {
    goingOpacity.target = 1;
    goingScale.target = 1;
    comingOpacity.target = 0;
    comingScale.target = reduceMotion ? 1 : spec.fadedOutScale;
    void step(TabSwitchStep step, void Function() change) => withSpring(
      Spring.response(step.response, dampingRatio: 1),
      change,
      delay: step.delay,
    );
    step(spec.fadeOut, () => goingOpacity.target = 0);
    step(spec.fadeIn, () => comingOpacity.target = 1);
    if (reduceMotion) return;
    step(spec.scaleOut, () => goingScale.target = spec.fadedOutScale);
    step(spec.scaleIn, () => comingScale.target = 1);
  }

  /// The four values, for a listener that waits for the switch to rest.
  List<MotionValue<double>> get values => [
    goingOpacity,
    goingScale,
    comingOpacity,
    comingScale,
  ];

  /// Whether the going page has gone and the coming one stands at rest, at
  /// time [t].
  bool settledAt(double t) =>
      goingOpacity.settledAt(t) &&
      comingOpacity.settledAt(t) &&
      goingScale.settledAt(t) &&
      comingScale.settledAt(t);
}
