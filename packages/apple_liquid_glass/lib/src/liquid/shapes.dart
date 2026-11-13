import 'package:apple_liquid_glass/foundation.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:meta/meta.dart';

// Keyed by the value object: a still frame hands the same shape and the
// same outline on every rebuild, so neither allocates a renderer object
// again, and a value no frame holds any longer lets its entry go.
final _shapes = Expando<LiquidShape>('GlassShape to LiquidShape');
final _fields = Expando<LiquidGlassField>('GlassField to LiquidGlassField');

/// The renderer's shape of [shape], made once per shape object.
@internal
LiquidShape liquidShapeOf(GlassShape shape) =>
    _shapes[shape] ??= switch (shape) {
      GlassSuperellipse(:final radius) => LiquidRoundedSuperellipse(
        borderRadius: radius,
      ),
      GlassRoundedRect(:final radius) => LiquidRoundedRectangle(
        borderRadius: radius,
      ),
      GlassOval() => const LiquidOval(),
    };

/// The renderer's field of [outline], or null when it has none; sampled
/// the first time it is read and made once per field.
@internal
LiquidGlassField? liquidFieldOf(GlassOutline outline) {
  final field = outline.field;
  if (field == null) return null;
  return _fields[field] ??= LiquidGlassField(
    samples: field.samples,
    cols: field.cols,
    rows: field.rows,
    origin: field.origin,
    step: field.step,
  );
}
