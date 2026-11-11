import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/selection.dart';
import 'package:kinesis/src/motion/value.dart';

/// Listens to [listenable] as a render object does: a motion value or a
/// derived value (`MotionValue`, `MotionSelection`) is heard also in the
/// frame's resolve phase, after layout and before paint, so what draws it
/// shows this frame's presentation; any other listenable as usual.
///
/// For a render object that paints from a listenable it is given, such as
/// a layer that follows a motion: the listener may mark paint and
/// composited layers, not layout, since it can run after layout. Stop it
/// with [unlistenForRender].
void listenForRender(Listenable listenable, VoidCallback listener) =>
    switch (listenable) {
      final MotionValue<Object?> value => value.addRenderListener(listener),
      final MotionSelection<Object?> value => value.addRenderListener(listener),
      _ => listenable.addListener(listener),
    };

/// Stops a listener added with [listenForRender].
void unlistenForRender(Listenable listenable, VoidCallback listener) =>
    switch (listenable) {
      final MotionValue<Object?> value => value.removeRenderListener(listener),
      final MotionSelection<Object?> value => value.removeRenderListener(
        listener,
      ),
      _ => listenable.removeListener(listener),
    };
