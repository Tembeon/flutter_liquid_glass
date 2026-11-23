import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/listen.dart';

/// Whether what is built at [context] follows its motion: false under a
/// muted `TickerMode`, where a host stops hearing its motion so that
/// nothing it shows keeps the clock stepping, and reads it again when the
/// ticker runs again.
///
/// Flutter: `TickerMode.valuesOf(context).enabled`.
bool followsMotion(BuildContext context) =>
    TickerMode.valuesOf(context).enabled;

/// What a host hears of its motion: each listenable of its heard list by
/// its callback, while the host is attached and [following].
///
/// When [following] turns on while the host is attached, each distinct
/// callback of the heard list runs once, so the host catches up with
/// whatever moved while it did not hear. Nothing runs at [attach]: a host
/// detaches and attaches again within one build or one layout, where no
/// motion moves.
///
/// ```dart
/// // In a render object's constructor, once its listenables exist:
/// _follow = MotionFollow.render(
///   following: following,
///   heard: [(opacity, markNeedsPaint)],
/// );
/// // In attach and detach:
/// _follow.attach();
/// _follow.detach();
/// // In updateRenderObject:
/// renderObject.following = followsMotion(context);
/// ```
final class MotionFollow {
  /// A follow for a render object or an element: it hears in the frame's
  /// render phase (`Listenable.addRenderListener`), as the frame lays out
  /// and paints.
  MotionFollow.render({
    required this._following,
    this._heard = const [],
  }) : _render = true;

  /// A follow for a `State` whose callbacks set its state: it hears as a
  /// plain listener, which the clock calls outside the frame's build.
  MotionFollow.widget({
    required this._following,
    this._heard = const [],
  }) : _render = false;

  final bool _render;
  bool _following;
  bool _attached = false;
  bool _hearing = false;
  List<(Listenable, VoidCallback)> _heard;

  /// Whether the host follows its motion ([followsMotion]).
  bool get following => _following;
  set following(bool value) {
    if (value == _following) return;
    _stop();
    _following = value;
    _start();
    if (!_hearing) return;
    final run = <VoidCallback>{};
    for (final (_, callback) in _heard) {
      if (run.add(callback)) callback();
    }
  }

  /// Hears [heard], each listenable by its callback, instead of what it
  /// heard before. Nothing runs: a host that swaps what it hears marks
  /// itself.
  void hear(List<(Listenable, VoidCallback)> heard) {
    _stop();
    _heard = heard;
    _start();
  }

  /// Starts hearing as the host attaches.
  void attach() {
    _attached = true;
    _start();
  }

  /// Stops hearing as the host detaches.
  void detach() {
    _stop();
    _attached = false;
  }

  void _start() {
    if (!_attached || !_following || _hearing) return;
    _hearing = true;
    for (final (listenable, callback) in _heard) {
      if (_render) {
        listenable.addRenderListener(callback);
      } else {
        listenable.addListener(callback);
      }
    }
  }

  void _stop() {
    if (!_hearing) return;
    _hearing = false;
    for (final (listenable, callback) in _heard) {
      if (_render) {
        listenable.removeRenderListener(callback);
      } else {
        listenable.removeListener(callback);
      }
    }
  }
}
