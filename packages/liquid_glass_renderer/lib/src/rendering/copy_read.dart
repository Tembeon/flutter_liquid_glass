import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/impeller_blur.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_levels.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';

/// How the final glass shader reads a copy: the one place that says where
/// its fragments lie and what its texture holds, written to the shader by
/// the glass alone.
///
/// The shader takes its fragments for the screen's device pixels, or for
/// [targetShare] of them where the glass is drawn inside a coarser copy. A copy
/// whose pixels are larger stands for a texture as many times larger
/// ([size]), or lies in the top-left corner of a layer of the screen's pixels
/// ([texels]).
@internal
@immutable
final class GlassSampling {
  /// Creates the sampling.
  const GlassSampling({
    required this.origin,
    required this.texels,
    required this.copy,
    this.image,
    this.size,
    this.covers,
    this.targetShare = 1,
  });

  /// Where the shader's fragment coordinate zero lies on the screen, in
  /// device pixels.
  final Offset origin;

  /// How many device pixels along each side one fragment stands for: 1, or
  /// the share of the copy the glass is drawn in, whose pixels its layer is
  /// drawn at.
  final int targetShare;

  /// How the copy lies in the texture the shader samples.
  final CopyTexels texels;

  /// uCopy, by CopyLane: the levels beside the copy and how the glass
  /// blurs it from them ([copyLanes]).
  final List<double> copy;

  /// The image the shader samples, for glass painted over an image copy.
  /// Null where the glass filters a layer, whose texture the engine binds.
  final ui.Image? image;

  /// uSize for glass painted over [image]: the image as many times larger
  /// as the copy is smaller, so a texel spans as many fragments as device
  /// pixels. Null where the engine sets it to the filtered layer's size.
  final Size? size;

  /// The screen rect (logical pixels) past which the read holds nothing,
  /// and the shader mirrors at it. Null where the glass's own bounds say.
  final Rect? covers;
}

/// How the copy a draw reads lies in the texture it samples, against the
/// draw's fragments: what the final shader decodes from uBackdropReduced.
@internal
@immutable
sealed class CopyTexels {
  const CopyTexels();

  /// The float the shader takes (EffectsLane.backdropReduced).
  double get encoded;
}

/// Every fragment reads its own texel of the copy.
@internal
final class OwnTexels extends CopyTexels {
  /// Every fragment reads its own texel.
  const OwnTexels();

  @override
  double get encoded => 0;

  @override
  bool operator ==(Object other) => other is OwnTexels;

  @override
  int get hashCode => (OwnTexels).hashCode;
}

/// An image copy at fewer pixels than the screen, which the draw's size
/// stretches over as many fragments as device pixels.
@internal
final class StretchedTexels extends CopyTexels {
  /// An image copy the draw stretches.
  const StretchedTexels();

  @override
  double get encoded => 1;

  @override
  bool operator ==(Object other) => other is StretchedTexels;

  @override
  int get hashCode => (StretchedTexels).hashCode;
}

/// A copy in the top-left corner of the layer the draw filters, each of its
/// texels [perTexel] fragments along each side, more than one.
@internal
final class CornerTexels extends CopyTexels {
  /// A corner copy of [perTexel] fragments a texel.
  const CornerTexels(this.perTexel)
    : assert(
        perTexel > 1,
        'A texel of a corner copy spans more than one fragment.',
      );

  /// The fragments a texel spans along each side.
  final int perTexel;

  @override
  double get encoded => perTexel.toDouble();

  @override
  bool operator ==(Object other) =>
      other is CornerTexels && other.perTexel == perTexel;

  @override
  int get hashCode => perTexel.hashCode;
}

/// The part [shown] (screen logical pixels) of an image copy that a surface
/// paints from its image.
@internal
final class ImagePart {
  /// The part [shown] of [copy].
  ImagePart(ImageCopy copy, this.shown) : _copy = copy;

  final ImageCopy _copy;

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
  /// it for Impeller's blur by [frost] logical pixels, less what the copy's
  /// pixels and the frost it holds already blur by.
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling frostSampling(
    double frost, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final image = _copy.image;
    return _copy.place.frostSampling(
      Size(image.width.toDouble(), image.height.toDouble()),
      _copy._frostLeft(frost),
      dissolve: dissolve,
    );
  }
}

// The lanes a place's copy was last read with: chrome over a scroll keeps
// its place and its blur.
final _lanesOf = Expando<(GlassBlur, List<double>)>();

/// A read's copy where glass reads it: laid out over a layer of the frame's
/// scene ([CornerRead]) or held in an image ([ImageCopy]).
@internal
sealed class PlacedCopy {
  const PlacedCopy();

  /// Where the copy lies.
  CopyPlace get place;

  double get _baked;

  double _frostLeft(double frost) => place.tapFrost(frost, baked: _baked);

  /// The texels of the texture the copy lies in to a pixel of the final
  /// shader's size.
  double get _texels;

  List<double> _copyLanes(GlassBlur blur) {
    if (_lanesOf[place] case (final held, final lanes) when held == blur) {
      return lanes;
    }
    final layout = place.layout;
    final lanes = copyLanes(
      strip: place.levels,
      blur: blur,
      frost: layout.frostLeftOut * layout.view.devicePixelRatio,
      at: place.levelAt,
      texels: _texels,
      share: place.share,
    );
    _lanesOf[place] = (blur, lanes);
    return lanes;
  }

  /// How the final shader reads the copy to blur it by [blur] from the
  /// levels beside it.
  GlassSampling glassSampling(GlassBlur blur);
}

/// A read's copy in an image held between frames: [rect] of the screen, in
/// logical pixels. A surface paints the part [readOf] gives.
@internal
final class ImageCopy extends PlacedCopy {
  /// The copy at [place] in [image], with the frost drawn into it.
  ImageCopy(this.image, this.place, this._baked);

  /// The image, shared with other copies of its frame.
  final ui.Image image;

  @override
  final ImagePlace place;

  @override
  final double _baked;

  /// The screen rect the copy holds, in logical pixels.
  Rect get rect => place.rect;

  /// Where the copy lies in [image].
  @visibleForTesting
  Offset get debugOffset => place.at;

  /// Equal while the copy lies at the same place on the same grid.
  Object get placement => (place.at, place.share);

  /// The shader's size is the image's, scaled to the screen's device
  /// pixels (see [glassSampling]).
  @override
  double get _texels => 1 / place.share;

  @override
  GlassSampling glassSampling(GlassBlur blur) {
    final share = place.share;
    return GlassSampling(
      origin: place.zero,
      texels: share > 1 ? const StretchedTexels() : const OwnTexels(),
      copy: _copyLanes(blur),
      image: image,
      size: Size(
        image.width * share.toDouble(),
        image.height * share.toDouble(),
      ),
    );
  }

  /// The part [shown] (screen logical pixels, inside [rect]) of the copy.
  ImagePart readOf(Rect shown) => ImagePart(this, shown);
}

/// One layer of the screen's pixels holding a read's copy for the part
/// of it inside a region, laid out as its [place] says.
@internal
final class CornerRead extends PlacedCopy {
  /// The copy [_copy] laid out at [place].
  CornerRead(this._copy, this.place);

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerRead.inFrame(ReadCopy copy) =>
      CornerRead(copy, CornerPlace.inFrame(copy.read.layout));

  final ReadCopy _copy;

  @override
  final CornerPlace place;

  @override
  double get _baked => inPlace.sigma;

  /// The copy lies in the top-left corner of the layer the shader filters,
  /// at the screen's pixels or coarser.
  @override
  double get _texels => 1;

  @override
  GlassSampling glassSampling(GlassBlur blur) {
    final perTexel = place.fragmentsPerTexel;
    return GlassSampling(
      origin: place.zero,
      texels: perTexel > 1 ? CornerTexels(perTexel) : const OwnTexels(),
      copy: _copyLanes(blur),
      targetShare: place.targetShare,
      covers: place.covers,
    );
  }

  /// How `backdrop_frost.frag` reads the layer to cover [shown] (screen
  /// logical pixels) pixel by pixel, frosted for Impeller's blur by [frost]
  /// logical pixels less what the copy holds, or null where
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
    size: place.layerSize,
    dissolve: dissolve,
  );

  /// What frosts the copy where it lies in the layer, at its own pixels, by
  /// the frost its layout holds there ([ReadLayout.bakedIn]), which glass
  /// then reads as it is; no filter where the glass frosts it fragment by
  /// fragment.
  late final InPlaceFrost inPlace = frostInPlace(place);

  /// What draws the copy's levels beside it where it lies in the layer, or
  /// null where it carries none.
  ///
  /// Its filters see the pixels of the target the layer is drawn into, as
  /// many times fewer than the layer's own coordinates count as the target
  /// is coarser than the screen.
  late final CopyLevelPasses? levels = switch (place.levels) {
    final strip? => CopyLevelPasses.of(strip, place.levelAt),
    null => null,
  };

  /// What blurs the copy where it lies in the layer, by the most its glass
  /// blurs it, where the layer has no room for the copy's levels: the
  /// shader then reads it as it is.
  ///
  /// NEAR: the glass blurs by one sigma over all of its face, and mixes in
  /// no fill.
  late final ui.ImageFilter? _blurInPlace = switch (place.layout.levels) {
    final wanted? when place.blursInPlace => ui.ImageFilter.blur(
      sigmaX: _impellerSigma(wanted.most),
      sigmaY: _impellerSigma(wanted.most),
      tileMode: glassBlurTileMode,
    ),
    _ => null,
  };

  // The sigma, in the target's pixels, to ask of Impeller's blur for a blur
  // by [sigma] logical pixels.
  double _impellerSigma(double sigma) =>
      sigma *
      place.devicePixelRatio /
      place.targetShare /
      ImpellerBlur.deliveredFraction;

  /// Adds the layer to [builder] with [filter] as its image filter, in
  /// coordinates [deviceToLocal] takes the screen's device pixels to. The
  /// copy passes through [inPlace] first, then through its [levels], and it
  /// keeps in [retained] what holds between scenes ([ReadCopy.addTo]).
  /// Returns the outermost engine layer.
  ui.TransformEngineLayer addToScene(
    ui.SceneBuilder builder,
    ui.ImageFilter filter,
    Matrix4 deviceToLocal,
    RetainedLayers retained, {
    ui.Path? clip,
  }) {
    final inPlace = this.inPlace.filter;
    final levels = this.levels;
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
    PinnedLayers.push(builder, filter, device.topLeft, place.layerSize);
    drawThroughCopyPasses(
      builder,
      origin: device.topLeft,
      levels: levels,
      levelSize: place.levelsSize,
      blur: _blurInPlace,
      frost: inPlace,
      copySize: copySize,
      draw: () => _copy.addTo(
        builder,
        place,
        inPlace == null ? device.rect : device.topLeft & copySize,
        retained,
      ),
    );
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    return engine;
  }
}

/// Adds what [draw] adds to [builder] through a placed copy's passes, from
/// [origin]: under its [levels], held to [levelSize], then Impeller's [blur]
/// where the copy has no room for levels, then its in-place [frost], each
/// held to [copySize].
@internal
void drawThroughCopyPasses(
  ui.SceneBuilder builder, {
  required Offset origin,
  required CopyLevelPasses? levels,
  required Size levelSize,
  required ui.ImageFilter? blur,
  required CopyFrost? frost,
  required Size copySize,
  required VoidCallback draw,
}) {
  levels?.push(builder, origin, levelSize);
  if (blur != null) PinnedLayers.push(builder, blur, origin, copySize);
  frost?.push(builder, origin, copySize);
  draw();
  frost?.pop(builder);
  if (blur != null) builder.pop();
  levels?.pop(builder);
}
