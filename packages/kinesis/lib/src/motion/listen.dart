import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';

/// A listenable that a render object also hears in the frame's resolve
/// phase, after layout and before paint, so what draws it shows this
/// frame's presentation.
abstract interface class RenderListenable implements Listenable {
  /// The clock that publishes it.
  MotionClock get clock;

  /// Adds a listener of a render object that only marks paint, composited
  /// layers or layout; what it marks for layout in the resolve phase is
  /// laid out again in that frame.
  void addRenderListener(VoidCallback listener);

  /// Removes a listener added with [addRenderListener].
  void removeRenderListener(VoidCallback listener);
}

/// Listening to any [Listenable] as a render object does.
extension RenderListening on Listenable {
  /// Listens as a render object does: a [RenderListenable] is heard also in
  /// the frame's resolve phase, any other listenable as usual.
  ///
  /// For a render object that paints from a listenable it is given, such as
  /// a layer that follows a motion: the listener may mark paint, composited
  /// layers and layout. When it runs after layout, what it marks for layout
  /// is laid out again in the same frame. Stop it with
  /// [removeRenderListener].
  void addRenderListener(VoidCallback listener) => switch (this) {
    final RenderListenable value => value.addRenderListener(listener),
    _ => addListener(listener),
  };

  /// Stops a listener added with [addRenderListener].
  void removeRenderListener(VoidCallback listener) => switch (this) {
    final RenderListenable value => value.removeRenderListener(listener),
    _ => removeListener(listener),
  };
}
