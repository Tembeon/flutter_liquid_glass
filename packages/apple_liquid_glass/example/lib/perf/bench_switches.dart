import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
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
  // B draws glass's haze into its copies; A frosts by the one blur that
  // stands in for it.
  'haze': ({required on}) {
    debugGlassHaze = on;
    _repaintGlass();
  },
  // B leans the normals of large regular glass and draws it from an atlas;
  // A keeps its edge's normals, its one shape worked out by the shader.
  'lean': ({required on}) {
    debugGlassLean = on;
    _repaintGlass();
  },
};

// A debug switch changes what glass asks of the frame, and glass that
// nothing moves asks again only when it paints.
void _repaintGlass() {
  void repaint(RenderObject object) {
    if (object is RenderLiquidGlassLayer) object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  RendererBinding.instance.renderViews.forEach(repaint);
}
