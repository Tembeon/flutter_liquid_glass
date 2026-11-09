// The flags are the renderer's debug switches, which the library keeps
// private.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart' show Policy;
import 'package:liquid_glass_renderer/src/composer/read.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

/// A renderer switch for an A/B look on a phone: what it trades and where in
/// the gallery that shows.
class RendererFlag {
  const RendererFlag({
    required this.title,
    required this.what,
    required this.where,
    required this.read,
    required this.write,
  });

  final String title;
  final String what;
  final String where;
  final bool Function() read;
  final void Function({required bool on}) write;

  bool get value => read();

  set value(bool on) {
    write(on: on);
    void repaint(RenderObject node) {
      if (node.attached) node.markNeedsPaint();
      node.visitChildren(repaint);
    }

    RendererBinding.instance.renderViews.forEach(repaint);
  }
}

Policy _policy({required bool ownGridHolds}) {
  final p = GlassComposer.debugPolicy;
  return Policy(
    maxTargets: p.maxTargets,
    maxShapes: p.maxShapes,
    bands: p.bands,
    copies: p.copies,
    dropsFrost: p.dropsFrost,
    bakesFrost: p.bakesFrost,
    coarseHolds: p.coarseHolds,
    ownGridHolds: ownGridHolds,
  );
}

final rendererFlags = [
  RendererFlag(
    title: 'Coarse glass under glass',
    what:
        "Frosted glass reads a copy of the backdrop at half the screen's "
        'resolution, and other glass under it is drawn into that copy. On '
        "(default): that glass is drawn at the copy's own pixels, which is "
        'cheaper (Pixel, Motion tab scroll: 12 % less fragment work). Off: '
        "at the screen's pixels, a little sharper at the edge and bevel of "
        'the glass seen through the frosted glass.',
    where:
        'glass that passes under the tab bar. Scroll the Controls tab so the '
        'slider, the segmented controls, the stepper or the buttons go '
        'under it; the Motion tab with its grid and list cards and the '
        'chips under it. This sheet over the tab bar, the More menu in the '
        "Present tab over the navigation bar, and a photo's toolbar while "
        'it replaces the tab bar (tap a photo).',
    read: () => GlassComposer.debugPolicy.ownGridHolds,
    write: ({required on}) =>
        GlassComposer.debugPolicy = _policy(ownGridHolds: on),
  ),
  RendererFlag(
    title: 'Weak frost at blur scale',
    what:
        'On (default): glass with a weak frost reads a copy of the backdrop '
        "at half the screen's resolution, as Impeller's own blur would. Off: "
        'at a quarter, as before. Off is cheaper (Pixel: about 20 to 28 % '
        'less GPU on a sheet and on the Controls scroll) but the backdrop '
        'under weak frost looks blocky and short of detail. The further the '
        'Liquid Glass slider above goes toward Tinted, the less this '
        'changes: a strong frost hides it.',
    where:
        'almost all chrome over a picture. The tab bar and search button '
        'over Photos and the Liquid tab, the bar buttons at the top, the '
        "Present tab's sheet with detents over its hero image, a photo's "
        'bars (tap a photo), the Video page. Flip it with the slider at '
        'Clear.',
    read: () => RenderLiquidGlassLayer.debugFrostAtBlurScale,
    write: ({required on}) => RenderLiquidGlassLayer.debugFrostAtBlurScale = on,
  ),
  RendererFlag(
    title: 'Video in the copy',
    what:
        "On (default): the current video frame goes into the glass's copy "
        'with the rest of the backdrop. Off: glass over a video or any '
        'other texture reads the live backdrop, which takes its own passes '
        '(Pixel, a list of videos under glass: 17 passes on, 50 off, about '
        '770 mW apart). A copy that held another frame than the one around '
        "the glass would break the clip's moving bars at the glass's edge.",
    where:
        'Present, Pages, Video. Watch the white and black bars where they '
        'cross the play, Live and fullscreen buttons, the navigation bar '
        'and the toolbar, while the clip plays and while you scroll. The '
        'settings button on that page opens this sheet over the video. '
        'Nothing else in the gallery draws a texture.',
    read: () => GlassCopies.debugTextureInScene,
    write: ({required on}) => GlassCopies.debugTextureInScene = on,
  ),
];
