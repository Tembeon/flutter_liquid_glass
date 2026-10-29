import 'package:flutter/foundation.dart';

/// Records which listenables a computation reads, so a derived value
/// follows exactly its inputs.
@internal
abstract final class ReadTracker {
  static Set<Listenable>? _reads;

  /// Notes that [source] was read by the computation being tracked.
  static void read(Listenable source) => _reads?.add(source);

  /// Runs [body], collecting what it reads into [into].
  static T track<T>(Set<Listenable> into, T Function() body) {
    final saved = _reads;
    into.clear();
    _reads = into;
    try {
      return body();
    } finally {
      _reads = saved;
    }
  }
}
