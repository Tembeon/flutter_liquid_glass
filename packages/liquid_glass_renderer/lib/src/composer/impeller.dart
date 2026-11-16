import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/read_geometry.dart';
import 'package:liquid_glass_renderer/src/painting/rect_scaling.dart';
import 'package:meta/meta.dart';

/// What Impeller does to a layer a clip cuts, and the only code that knows:
/// it cuts the layer to the clip, and starts fragment coordinates at the cut,
/// only once the part it cuts off either axis is 30 % or more of what is left
/// (ComputeSaveLayerCoverage, impeller/entity/save_layer_utils.cc;
/// in_frame_copy_test and copy_layer_extent_test fail when it changes).
@internal
abstract final class ImpellerLayers {
  /// How far above and left of its pixels a read's layers are added, in
  /// device pixels.
  ///
  /// Impeller places a layer drawn inside another, such as the one a
  /// paragraph that fades at its edge is painted through, by the floor of its
  /// origin less the origin of the layer around it. Where the copy's edge
  /// cuts such a layer the two origins are the same number, less what 32-bit
  /// floats lose on the way: the copy's passes through the place of the glass
  /// on the screen, a fraction that moves with it. A hair above a whole pixel
  /// the floor is one pixel short, and the layer's content, all of the text,
  /// stood one pixel of the copy aside, up to four of the screen's, for the
  /// frames the glass spent there (a lens sweeping over faded text on a
  /// Pixel 6a: 46 to 58 frames in 12 s, none without the fade). Drawn a
  /// little below whole pixels the floor always falls the same way. The
  /// read's own layers are placed by rounding, so nothing on the screen
  /// moves. Measured on the device only: no host test sees it.
  static const double nestedOriginBias = 1 / 32;

  /// The skew under which text drawn into a smaller copy lies where it is
  /// drawn: under a translation and a scale alone Impeller sets glyphs on
  /// whole pixels of their target (impeller/entity/contents/text_contents.cc).
  /// See [Lattice.deviceToCopy]; copy_text_motion_test fails when that
  /// changes.
  static const double glyphSkew = 1e-6;

  /// The rows a layer keeps past the rows pinned in it. Impeller sometimes
  /// sizes a layer drawn under a transform a hair off whole pixels, as a
  /// pressed sheet's, a row short; without the spare row a haze's mix finds
  /// no strip and draws the copy unhazed, and the glass flickers from frame
  /// to frame (sheet_haze_host_test).
  static const int spareRows = 1;

  /// Where an opacity pass that a glass seeds starts on the screen, in
  /// logical pixels: Impeller bounds it by the clips around it, rounded out
  /// to device pixels, and fragment coordinates start there.
  static Offset passOrigin(Rect clip, double devicePixelRatio) => Offset(
    (clip.left * devicePixelRatio).floorToDouble() / devicePixelRatio,
    (clip.top * devicePixelRatio).floorToDouble() / devicePixelRatio,
  );

  /// Whether Impeller draws a layer of [layer] whole inside a clip of
  /// [clip], both in the same space.
  static bool keepsWhole(Rect layer, Rect clip) {
    final cut = layer.intersect(clip);
    if (cut.isEmpty) return false;
    return (layer.width - cut.width) / cut.width < 0.3 &&
        (layer.height - cut.height) / cut.height < 0.3;
  }

  /// Whether Impeller draws a copy of [layer] on [lattice] whole inside [clip]
  /// (both logical pixels). It measures the layer as drawn: the whole pixels
  /// it grows to can tip a layer just under the bound over it.
  static bool keepsWholeOn(Lattice lattice, Rect layer, Rect clip) {
    final dpr = lattice.devicePixelRatio;
    return keepsWhole(
      lattice.toDevice(layer),
      clip.scaled(dpr),
    );
  }

  /// The layer that holds [band] inside [clip] (both logical pixels) on
  /// [lattice].
  ///
  /// The glass reads what lies past the clip, so the layer grows into the
  /// clip, empty, until the part cut off is less than Impeller's bound;
  /// where the clip leaves no room, it is cut to the clip. NEAR: there,
  /// glass reads the copy mirrored at the clip, up to 163 levels off over
  /// the 30 px of glass the host test leaves above such a clip.
  static Rect layerIn(Rect band, Rect clip, Lattice lattice) {
    if (keepsWholeOn(lattice, band, clip)) return band;
    // Along one axis: the span from [lo] to [hi] grown inside [from, to].
    (double, double)? grow(double lo, double hi, double from, double to) {
      final cut = max(from - lo, 0) + max(hi - to, 0);
      final inside = min(hi, to) - max(lo, from);
      if (inside <= 0) return null;
      // A margin below 30 % keeps rounding off the threshold.
      final wanted = cut / 0.28;
      if (inside >= wanted) return (lo, hi);
      if (lo < from && hi > to) return null;
      if (lo < from) {
        final end = max(lo, from) + wanted;
        return end <= to ? (lo, end) : null;
      }
      final start = min(hi, to) - wanted;
      return start >= from ? (start, hi) : null;
    }

    final x = grow(band.left, band.right, clip.left, clip.right);
    final y = grow(band.top, band.bottom, clip.top, clip.bottom);
    if (x == null || y == null) {
      return lattice.snapOut(band.intersect(clip));
    }
    final grown = lattice.snapOut(Rect.fromLTRB(x.$1, y.$1, x.$2, y.$2));
    return keepsWholeOn(lattice, grown, clip)
        ? grown
        : lattice.snapOut(band.intersect(clip));
  }

  /// A device pixel at the top left and one at the bottom right of [layer]
  /// (logical pixels): a clip path that covers them too keeps its bounds at
  /// the layer's, so Impeller does not cut the layer.
  static (Rect, Rect) pinsOf(Rect layer, double devicePixelRatio) {
    final pixel = 1 / devicePixelRatio;
    return (
      layer.topLeft & Size.square(pixel),
      Rect.fromPoints(
        layer.bottomRight - Offset(pixel, pixel),
        layer.bottomRight,
      ),
    );
  }
}

/// What Impeller's Gaussian blur does to a sigma, and the only code that
/// knows: the plan, the settings and the widgets' scroll edge ask here.
/// backdrop_underlay_frost_test fails when it changes.
abstract final class ImpellerBlur {
  /// How many device pixels along each side one pixel holds where Impeller's
  /// blur by [sigma] device pixels downsamples (GaussianBlurFilterContents::
  /// CalculateScale: none up to 4, else 2^round(log2(sigma / 4))).
  static int share(double sigma) =>
      sigma <= 4 ? 1 : 1 << max(0, (log(sigma / 4) / ln2).round());

  /// The device-pixel sigma Impeller blurs with for [sigma] logical pixels
  /// at [devicePixelRatio]: its sigma correction, then the canvas scale.
  static double deviceSigma(double sigma, double devicePixelRatio) {
    final clamped = min<double>(sigma, 500);
    return clamped * _correction(clamped) * devicePixelRatio;
  }

  static double _correction(double sigma) =>
      1 - 3.4e-3 * sigma + 3.4e-6 * sigma * sigma;

  /// The logical pixels around a region that Impeller's blur of [sigma]
  /// logical pixels reads at [devicePixelRatio]: its kernel reaches 1.732 of
  /// its device sigma, plus the texels its downsample and upsample add,
  /// rounded up to whole device pixels.
  static double reach(double sigma, double devicePixelRatio) {
    final scaled = deviceSigma(sigma, devicePixelRatio);
    final scale = scaled <= 4
        ? 1.0
        : pow(
            2.0,
            max(-4.0, (log(4 / scaled) / ln2).roundToDouble()),
          ).toDouble();
    return (1.7320508 * scaled + 2 / scale + 2).ceilToDouble() /
        devicePixelRatio;
  }

  /// [sigma] raised to the smallest sigma Impeller blurs at half resolution
  /// at [devicePixelRatio] (a device sigma of 4 sqrt 2), when that is at most
  /// 1.12 times larger; else [sigma] itself. Just below that threshold
  /// Impeller blurs every device pixel at about three times the cost on a
  /// Mali GPU. NEAR: the blur is up to 12 % wider than asked.
  static double halfResolution(double sigma, double devicePixelRatio) {
    const threshold = 4 * sqrt2;
    if (sigma <= 0 || devicePixelRatio <= 0) return sigma;
    if (deviceSigma(sigma, devicePixelRatio) >= threshold) return sigma;
    final target = threshold * 1.001 / devicePixelRatio;
    var raised = target;
    for (var i = 0; i < 4; i++) {
      raised = target / _correction(raised);
    }
    return raised <= sigma * 1.12 ? raised : sigma;
  }
}
