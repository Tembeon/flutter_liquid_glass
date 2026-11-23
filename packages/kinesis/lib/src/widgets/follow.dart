import 'package:flutter/widgets.dart';
import 'package:kinesis/src/motion/listen.dart';
import 'package:meta/meta.dart';

/// Whether what is built at [context] follows its motion: false under a
/// muted `TickerMode`, where a host stops hearing its motion so that
/// nothing it shows keeps the clock stepping, and reads it again when the
/// ticker runs again.
@internal
bool followsMotion(BuildContext context) =>
    TickerMode.valuesOf(context).enabled;

/// What a host hears of its motion: each listenable of [heard] by its
/// callback, while the host is attached and [following].
@internal
final class MotionFollow {
  /// Hears nothing until [attach].
  MotionFollow({required this._following});

  bool _following;
  bool _attached = false;
  bool _hearing = false;
  List<(Listenable, VoidCallback)> _heard = const [];

  /// Whether the host follows its motion ([followsMotion]).
  bool get following => _following;
  set following(bool value) {
    if (value == _following) return;
    _stop();
    _following = value;
    _start();
  }

  /// What it hears, each listenable by its callback.
  List<(Listenable, VoidCallback)> get heard => _heard;
  set heard(List<(Listenable, VoidCallback)> value) {
    _stop();
    _heard = value;
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
      listenable.addRenderListener(callback);
    }
  }

  void _stop() {
    if (!_hearing) return;
    _hearing = false;
    for (final (listenable, callback) in _heard) {
      listenable.removeRenderListener(callback);
    }
  }
}
