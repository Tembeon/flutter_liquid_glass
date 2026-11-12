// The switches a bench can flip, by name.
// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/rendering.dart';

/// The switches an A/B run can flip, by name, for questions still open.
/// `none` flips nothing: an A/A run that shows the noise floor.
final benchSwitches = <String, void Function({required bool on})>{
  'none': ({required on}) {},
  // B draws every second vsync while nothing fast moves; A every vsync.
  'cadence': ({required on}) => FrameCadence.enabled = on,
  // B draws the copies asked for without a filter in the frame, A into
  // images.
  'in_frame': ({required on}) =>
      debugGlassPolicy = PlanPolicy(maxTargets: on ? 8 : 0),
  // B reads the backdrop live instead of drawing copies.
  'live_reads': ({required on}) => debugGlassCopies = on ? false : null,
};
