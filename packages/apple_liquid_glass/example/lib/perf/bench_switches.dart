// The switches a bench can flip, by name.
// ignore_for_file: implementation_imports, depend_on_referenced_packages
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart' show Policy;
import 'package:liquid_glass_renderer/src/composer/read.dart';

/// The switches an A/B run can flip, by name, for questions still open.
/// `none` flips nothing: an A/A run that shows the noise floor.
final benchSwitches = <String, void Function({required bool on})>{
  'none': ({required on}) {},
  // B: a read keeps what did not change between frames, A walks all of it.
  'keeps_layers': ({required on}) => GlassCopies.debugKeepsLayers = on,
  // B draws every second vsync while nothing fast moves; A every vsync.
  'cadence': ({required on}) => FrameCadence.enabled = on,
  // B draws the copies asked for without a filter in the frame, A into
  // images.
  'in_frame': ({required on}) =>
      GlassComposer.debugPolicy = Policy(maxTargets: on ? 8 : 0),
  // B reads the backdrop live instead of drawing copies.
  'live_reads': ({required on}) =>
      GlassCopies.debugEnabledOverride = on ? false : null,
};
