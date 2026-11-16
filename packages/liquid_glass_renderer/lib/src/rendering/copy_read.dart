import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/copy_place.dart';
import 'package:liquid_glass_renderer/src/composer/impeller.dart';
import 'package:liquid_glass_renderer/src/composer/read_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:meta/meta.dart';

/// How the final glass shader reads a copy: the one place that says where
/// its fragments lie and what its texture holds, written to the shader by
/// the glass alone.
///
/// The shader takes its fragments for the screen's device pixels, or for
/// [scale] of them where the glass is drawn inside a coarser copy. A copy
/// whose pixels are larger stands for a texture as many times larger
/// ([size]), or lies in the top-left share of a layer of the screen's pixels
/// ([reduced]).
@internal
@immutable
final class GlassSampling {
  /// Creates the sampling.
  const GlassSampling({
    required this.origin,
    required this.reduced,
    this.frost = 0,
    this.image,
    this.size,
    this.holds,
    this.scale = 1,
  });

  /// Where the shader's fragment coordinate zero lies on the screen, in
  /// device pixels.
  final Offset origin;

  /// How many device pixels along each side one fragment stands for: 1, or
  /// the share of the copy the glass is drawn in, whose pixels its layer is
  /// drawn at.
  final int scale;

  /// uBackdropReduced: 0 where every fragment reads its own texel of the
  /// copy; 1 for an image copy at fewer pixels than the screen, which [size]
  /// stretches; the share for a copy in the top-left share of a layer.
  final double reduced;

  /// uBackdropFrost: the sigma, in device pixels, the shader's taps frost
  /// the copy by, 0 for none. A reading takes the sigma of the Impeller blur
  /// the frost stands for, in the screen's logical pixels, and leaves out
  /// what the copy's pixels already blur by.
  final double frost;

  /// The image the shader samples, for glass painted over an image copy.
  /// Null where the glass filters a layer, whose texture the engine binds.
  final ui.Image? image;

  /// uSize for glass painted over [image]: the image as many times larger
  /// as the copy is smaller, so a texel spans as many fragments as device
  /// pixels. Null where the engine sets it to the filtered layer's size.
  final Size? size;

  /// The screen rect (logical pixels) past which the read holds nothing,
  /// and the shader mirrors at it. Null where the glass's own bounds say.
  final Rect? holds;
}

/// The part [shown] (screen logical pixels) of a page that a surface paints
/// from its image.
@internal
final class PagePart {
  /// The part [shown] of [copy].
  PagePart(PageCopy copy, this.shown) : _copy = copy;

  final PageCopy _copy;

  /// The part painted, in the screen's logical pixels.
  final Rect shown;

  /// [shown] in the image's pixels.
  Rect get source => _copy.place.texelsOf(shown);

  /// Takes [canvas] from the screen's logical pixels to the image's, so
  /// that [source] drawn there lands on [shown].
  void toImage(Canvas canvas) {
    final source = this.source;
    canvas
      ..translate(shown.left, shown.top)
      ..scale(1 / _copy.place.pixels)
      ..translate(-source.left, -source.top);
  }

  /// How `backdrop_frost.frag` reads [source] drawn under [toImage] to frost
  /// it for Impeller's blur by [frost] (see [GlassSampling.frost]).
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling frostSampling(
    double frost, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final image = _copy.image;
    return _copy.place.frostSampling(
      Size(image.width.toDouble(), image.height.toDouble()),
      _copy.frostLeft(frost),
      dissolve: dissolve,
    );
  }
}

/// One layer of the screen's pixels holding a read's copy for the part
/// of it inside a region, laid out as its [place] says.
@internal
final class CornerRead {
  /// The copy [_copy] laid out at [place].
  CornerRead(this._copy, this.place);

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerRead.inFrame(ReadCopy copy) =>
      CornerRead(copy, CornerPlace.inFrame(copy.read.geometry));

  final ReadCopy _copy;

  /// Where the copy lies in the layer.
  final CornerPlace place;

  /// What [glassSampling] stands for by the whole frost [sigma] of a band.
  double frostOf(double sigma) => place.residual(sigma);

  /// What [glassSampling] stands for by the frost drawn into the copy: 0
  /// where it holds none.
  double get heldFrost => place.residual(inPlace.sigma);

  double _frostLeft(double frost) => place.tapFrost(frost, held: inPlace.sigma);

  /// How the final shader reads the layer to frost it for Impeller's blur
  /// by [frost] (see [GlassSampling.frost]), less what the copy holds.
  GlassSampling glassSampling(double frost) {
    final share = place.share;
    return GlassSampling(
      origin: place.zero,
      reduced: share > 1 ? share.toDouble() : 0,
      frost: _frostLeft(frost),
      scale: place.scale,
      holds: place.holds,
    );
  }

  /// How `backdrop_frost.frag` reads the layer to cover [shown] (screen
  /// logical pixels) pixel by pixel, frosted for Impeller's blur by [frost]
  /// (see [GlassSampling.frost]) less what the copy holds, or null where
  /// none of [shown] lies in it.
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling? frostSampling(
    Rect shown,
    double frost, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) => place.frostSampling(
    shown,
    _frostLeft(frost),
    size: _layerSize,
    dissolve: dissolve,
  );

  /// The fragments of the layer that [shown] (screen logical pixels) covers,
  /// or null where none of it lies in the layer.
  Rect? fragmentsOf(Rect shown) => place.fragmentsOf(shown);

  /// What frosts the copy where it lies in the layer, at its own pixels, by
  /// the frost its geometry holds there ([ReadGeometry.bakedIn]), which glass
  /// then reads as it is; no filter where the glass frosts it fragment by
  /// fragment.
  late final InPlaceFrost inPlace = frostInPlace(
    place.baked,
    () => place.inPlace,
  );

  /// What mixes the copy's haze into it where it lies in the layer, or null
  /// where it has none.
  ///
  /// Its filters see the pixels of the target the layer is drawn into, as
  /// many times fewer than the layer's own coordinates count as the target
  /// is coarser than the screen.
  late final CopyHaze? haze = switch ((place.geometry.haze, place.haze)) {
    (final haze?, final layout?) => CopyHaze.of(haze, layout),
    _ => null,
  };

  // The layer's size in device pixels.
  Size get _layerSize => switch (haze) {
    final haze? => place.sizeWith(haze.size * place.scale.toDouble()),
    null => place.device.size,
  };

  /// Adds the layer to [builder] with [filter] as its image filter, in
  /// coordinates [deviceToLocal] takes the screen's device pixels to. The
  /// copy passes through [inPlace] first, then through its [haze], and it
  /// keeps in [held] what holds between scenes ([ReadCopy.addTo]).
  /// Returns the outermost engine layer.
  ui.TransformEngineLayer addToScene(
    ui.SceneBuilder builder,
    ui.ImageFilter filter,
    Matrix4 deviceToLocal,
    HeldLayers held, {
    ui.Path? clip,
  }) {
    final inPlace = this.inPlace.filter;
    final haze = this.haze;
    final device = place.device;
    final copySize = place.copySize;
    final engine = builder.pushTransform(
      (deviceToLocal.clone()..translateByDouble(
            -ImpellerLayers.nestedOriginBias,
            -ImpellerLayers.nestedOriginBias,
            0,
            1,
          ))
          .storage,
    );
    if (clip != null) builder.pushClipPath(clip, clipBehavior: Clip.hardEdge);
    PinnedLayers.push(builder, filter, device.topLeft, _layerSize);
    haze?.push(builder, device.topLeft, scale: place.scale);
    inPlace?.push(builder, device.topLeft, copySize);
    final within = inPlace == null ? device.rect : device.topLeft & copySize;
    _copy.addTo(builder, place, within, held);
    inPlace?.pop(builder);
    haze?.pop(builder);
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    return engine;
  }
}
