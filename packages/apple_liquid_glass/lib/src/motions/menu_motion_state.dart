part of 'menu_motion.dart';

enum _Phase { idle, opening, closing }

class _Pointer {
  _Pointer({
    required this.fromButton,
    required this.position,
  });

  final bool fromButton;
  Offset position;
  bool openedByHold = false;
  bool holdForfeited = false;
  bool scrolled = false;
  bool leftButton = false;

  /// Whether the touch started on the top list, and so stretches and lights
  /// it, highlights its rows and can choose one. A touch elsewhere does none
  /// of this wherever it goes (an iPhone 16 Pro).
  bool touchesTopList = true;

  /// Whether the touch started on the parent list showing under a submenu.
  bool startedOnParent = false;

  /// Where a touch off the top list started.
  Offset start = Offset.zero;

  /// The flex this finger stretches, once it does.
  MenuFlex? flex;
}

/// A damped spring driven by an input.
class _DrivenKick {
  double value = 0;
  double velocity = 0;

  bool get isAtRest =>
      value.abs() < MenuTuning.kickRestValue &&
      velocity.abs() < MenuTuning.kickRestVelocity;

  void reset() {
    value = 0;
    velocity = 0;
  }

  /// One step of [h] seconds on [spring] toward [target].
  void integrate(double h, Spring spring, double target) {
    velocity +=
        (spring.stiffness * (target - value) - spring.damping * velocity) * h;
    value += velocity * h;
  }
}

/// The menu's two driven kicks, stepped on a fixed grid of
/// [MenuTuning.kickIntegrationStep] whatever the frames sample: the
/// recorded kicks were fitted with this step, and the grid makes a replay
/// at any frame rate step the same frames (NEAR, see
/// [MenuTuning.kickIntegrationStep]).
///
/// The loop sleeps once both kicks and the springs that drive them rest,
/// keeping what is left (below [MenuTuning.kickRestValue]), and wakes when
/// the menu opens, closes or kicks. It steps up to three seconds of a
/// longer gap, in which every kick rings out.
final class _KickLoop extends MotionLoop {
  _KickLoop(this._motion)
    : super(
        rate: 1 / MenuTuning.kickIntegrationStep,
        maxFrames: (3 / MenuTuning.kickIntegrationStep).round(),
      );

  final MenuMotion _motion;

  final menu = _DrivenKick();
  final button = _DrivenKick();

  @override
  bool step(double t) => _motion._stepKicks(t, menu, button);

  /// Answers [read] with the kicks stepped on to time [t] as the loop will
  /// step them while nothing else changes, then puts them back.
  T peek<T>(double t, T Function() read) {
    if (!isMoving) return read();
    final (mv, mw, bv, bw) = (
      menu.value,
      menu.velocity,
      button.value,
      button.velocity,
    );
    try {
      final end = (t * rate + 1e-6).floor();
      for (var k = (lastFrame * rate).round() + 1; k <= end; k++) {
        if (!_motion._stepKicks(k / rate, menu, button)) break;
      }
      return read();
    } finally {
      menu.value = mv;
      menu.velocity = mw;
      button.value = bv;
      button.velocity = bw;
    }
  }
}

/// A submenu card stacked over the menu.
class _Card {
  _Card({
    required this.layout,
    required this.source,
    required this.from,
    required this.top,
    required this.progress,
  });

  MenuLayout layout;

  /// The index of the target in the card below that opened this one.
  final int source;

  /// The frame the card grows out of, in content coordinates.
  final Rect from;

  /// The top of the open card, in content coordinates.
  double top;

  final MotionValue<double> progress;

  /// The card's own flex: UIKit attaches one to each list, and a finger on a
  /// card leaves the list under it where it is.
  late final MenuFlex flex;
  bool backing = false;

  /// The progress the card had when it started back to its row.
  double backFrom = 1;
}

const List<(double, double)> _kickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (188, 1.488),
  (230, 1.628),
  (272, 1.61),
  (356, 1.563),
  (440, 1.481),
];

// The closing amplitudes were captured at 146, 230 and 440 pixels;
// below 146 the opening's amplitude stands in.
const List<(double, double)> _closeKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.644),
  (440, 1.61),
];

const List<(double, double)> _sourceKickAmplitude = [
  (62, 0.814),
  (104, 0.814),
  (146, 1),
  (230, 1.488),
  (440, 1.777),
];
