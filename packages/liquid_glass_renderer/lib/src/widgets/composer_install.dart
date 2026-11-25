import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_frames.dart';
import 'package:meta/meta.dart';

/// Whether [installLiquidGlassComposer] installs the frame's composer
/// ([GlassComposer]); without it each glass reads its own backdrop
/// ([DirectReads]). A test of what glass draws without the composer turns it
/// off before the first glass widget builds.
@internal
bool installsGlassComposer = true;

/// Has the glass of every view planned by the renderer's composer, which
/// lets glass read copies of what lies under it and share one read between
/// glass; without it each glass reads its own backdrop.
///
/// The glass widgets call it as they make their render objects. A widget
/// whose render object hosts glass through the rendering library on its own
/// ([LiquidGlassBackdropFilterHost]) calls it the same way, before the
/// render object's first frame.
void installLiquidGlassComposer() {
  if (installsGlassComposer) GlassComposer.install();
}
