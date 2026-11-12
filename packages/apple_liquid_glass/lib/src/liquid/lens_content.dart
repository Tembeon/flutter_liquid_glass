import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/liquid/lens_shadows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/rendering.dart';

/// How a lifted lens shows what it selects, as iOS 27 does.
///
/// Read from UIKit's lifted tab bar and segmented control lenses on iOS
/// 27.2 (notes private). UIKit draws the selected look of the items over
/// the lens's glass and moves it away from the rim twice, each time along
/// a quarter circle that is strongest at the rim: first by the bend the
/// lens gives its content, 0.2 of its height over 0.16 of it
/// ([LensShadowLaw.contentBend]), then by the bend the lift adds,
/// [liftBend] over [liftBendHeight] on every lens. So the rim of a tab
/// bar's lens shows what lies 14 points inside it, 4.2 points deep shows
/// what lies 8.4 points deep, the nearest to the rim that ever shows, and
/// from 11.2 points deep everything shows in place. Both bends grow with
/// the lift.
@internal
abstract final class LensContentLaw {
  /// How far the lift moves the content away from the rim, at the rim.
  static const double liftBend = 17.5;

  /// How deep from the rim [liftBend] reaches.
  static const double liftBendHeight = 11.2;

  /// The bends of a lens of [height] across its short side lifted by
  /// [lift], from the one nearest the eye.
  static List<LiquidGlassContentBend> bends(double height, {double lift = 1}) {
    final own = LensShadowLaw.contentBend(height, small: false);
    return [
      LiquidGlassContentBend(amount: own.bend * lift, height: own.height),
      LiquidGlassContentBend(amount: liftBend * lift, height: liftBendHeight),
    ];
  }

  /// How deep from the rim lies what a lens of [height] across its short
  /// side, lifted by [lift], shows [depth] from its rim.
  static double shownDepth(
    double depth, {
    required double height,
    double lift = 1,
  }) {
    var shown = depth;
    for (final bend in bends(height, lift: lift)) {
      shown = bend.shownDepth(shown);
    }
    return shown;
  }
}

/// Shows the content a control draws over a lifted lens by
/// [LensContentLaw], through the renderer's [LiquidGlassBentContent]: one
/// offscreen pass the size of the lens while it is lifted, none at rest,
/// where the content is painted as it is.
///
/// Fidelity. The bend is UIKit's law, NEAR: sampled between rings at most
/// a point apart and along an outline with circular corners. NEAR: UIKit
/// parts the colors of the content with the rest of the lens and lays the
/// rim's light and the inner shadow over it; here the content lies over
/// the glass with its light, parting and shadows, which shows only where
/// content reaches the rim.
@internal
final class LensContentBend implements GlassLensContent {
  /// The device pixels per logical pixel the content is drawn at.
  double devicePixelRatio = 1;

  final _bent = LiquidGlassBentContent();

  /// Releases the last picture.
  void dispose() => _bent.dispose();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required GlassFrame frame,
    required Size size,
    required PaintingContextCallback content,
  }) {
    final body = frame.drawnIn(size);
    if (frame.lift <= GlassFrame.restingLift ||
        frame.outline != null ||
        body.isEmpty) {
      // A resting lens keeps no picture.
      _bent.dispose();
      return content(context, offset);
    }
    final lift = frame.lift.clamp(0.0, 1.0);
    final drawn = body.shift(offset);
    _bent.paint(
      context,
      offset,
      rect: drawn,
      radius: frame.shape.radiusIn(body),
      clip: frame.shape.pathIn(drawn),
      bends: LensContentLaw.bends(body.shortestSide, lift: lift),
      devicePixelRatio: devicePixelRatio,
      content: content,
    );
  }
}
