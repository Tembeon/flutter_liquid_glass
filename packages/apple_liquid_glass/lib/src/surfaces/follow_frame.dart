import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';

/// Listens to [frame] as a renderer does: a selection is heard also in the
/// frame's resolve phase, so a body moves in the frame whose layout moved what
/// the selection reads, together with its content.
void followFrame(ValueListenable<GlassFrame> frame, VoidCallback listener) =>
    switch (frame) {
      final MotionSelection<GlassFrame> selection =>
        selection.addRenderListener(listener),
      _ => frame.addListener(listener),
    };

/// Stops a listener added with [followFrame].
void unfollowFrame(ValueListenable<GlassFrame> frame, VoidCallback listener) =>
    switch (frame) {
      final MotionSelection<GlassFrame> selection =>
        selection.removeRenderListener(listener),
      _ => frame.removeListener(listener),
    };
