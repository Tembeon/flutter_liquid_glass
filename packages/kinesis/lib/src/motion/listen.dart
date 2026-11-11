import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/selection.dart';
import 'package:kinesis/src/motion/value.dart';

/// Listens to [listenable] as a render object does: a motion value or a
/// derived value is heard also in the resolve phase, any other listenable
/// as usual.
@internal
void listenForRender(Listenable listenable, VoidCallback listener) =>
    switch (listenable) {
      final MotionValue<Object?> value => value.addRenderListener(listener),
      final MotionSelection<Object?> value => value.addRenderListener(listener),
      _ => listenable.addListener(listener),
    };

/// Stops a listener added with [listenForRender].
@internal
void unlistenForRender(Listenable listenable, VoidCallback listener) =>
    switch (listenable) {
      final MotionValue<Object?> value => value.removeRenderListener(listener),
      final MotionSelection<Object?> value => value.removeRenderListener(
        listener,
      ),
      _ => listenable.removeListener(listener),
    };
