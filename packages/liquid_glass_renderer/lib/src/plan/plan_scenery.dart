import 'dart:ui';

import 'package:meta/meta.dart';

/// What a kind of layer lets a read over it be.
enum ReadLimit {
  /// Anything: pictures and known containers.
  none,

  /// Added to the scene again but not recorded: a texture.
  sceneOnly,

  /// Cannot be drawn twice: a platform view, a foreign backdrop filter or a
  /// layer type the composer does not know.
  backdropOnly;

  /// Whether a read under this limit keeps to the backdrop: one that may not
  /// read the scene has only an image to fall back on.
  bool keepsToBackdrop({required bool noScene}) =>
      this == backdropOnly || (noScene && this == sceneOnly);
}

/// Inherited alpha, filters and clips, one link per layer that adds any.
///
/// Links are shared while a layer's value holds, so siblings compare by
/// identity first.
final class StateChain {
  /// Adds [token] under [parent], an opacity short of whole where [fades].
  StateChain(this.parent, this.token, {bool fades = false})
    : fades = fades || (parent?.fades ?? false);

  /// The state outside every layer.
  static final StateChain root = StateChain(null, null);

  /// The link above.
  final StateChain? parent;

  /// The value this link adds.
  final Object? token;

  /// Whether an opacity short of whole lies among these links.
  final bool fades;

  /// Whether both chains hold equal values in the same order.
  bool same(StateChain other) {
    StateChain? a = this;
    StateChain? b = other;
    while (true) {
      if (identical(a, b)) return true;
      if (a == null || b == null) return false;
      if (a.token != b.token) return false;
      a = a.parent;
      b = b.parent;
    }
  }
}

/// Why a site can never share a filter.
enum NoJoin {
  /// Part of a fused field, or its shapes have appearances of their own.
  field,

  /// Its glow is drawn per surface.
  glow,

  /// Its backdrop shrinks, pulls or parts around its own center.
  ownCenter,

  /// Its shadows fade with their shape, cut outside a filter drawn later.
  fadingShadows,

  /// It has no geometry yet, or draws through no filter it could share.
  noGeometry,

  /// Scaled, so its shapes lie in no atlas the others share.
  scaled,
}

/// What an image read draws alike under: the filter image reads share and
/// how its output composites ([ImageReadFilter.look]).
typedef ImageReadLook = ({Object? key, BlendMode blendMode});

/// What a read that can only come from an image does to it, past the plain
/// copy glass blurs by itself.
@immutable
sealed class ImageReadFilter {
  const ImageReadFilter();

  /// What image reads under one filter share, or null for a plain image.
  Object? get key;

  /// Where the filter applies on the screen, the whole image when null.
  Rect? get clip => null;

  /// How the filter's output composites over the image.
  BlendMode get blendMode => BlendMode.src;

  /// What an image of it draws alike under.
  ImageReadLook get look => (key: key, blendMode: blendMode);
}

/// A plain copy, which what reads it composites as it needs to.
final class PlainImage extends ImageReadFilter {
  /// A plain copy.
  const PlainImage();

  @override
  Object? get key => null;

  @override
  bool operator ==(Object other) => other is PlainImage;

  @override
  int get hashCode => (PlainImage).hashCode;
}

/// An image blurred by a mirrored Gaussian of [x] and [y] logical pixels.
final class BlurredImage extends ImageReadFilter {
  /// An image blurred by [x] and [y].
  const BlurredImage(this.x, this.y);

  /// The sigma along x, in logical pixels.
  final double x;

  /// The sigma along y, in logical pixels.
  final double y;

  @override
  Object? get key => (x, y);

  @override
  bool operator ==(Object other) =>
      other is BlurredImage && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// An image under [filter], applied as a backdrop filter over it.
final class FilteredImage extends ImageReadFilter {
  /// An image under [filter] in [clip], composited by [blendMode].
  const FilteredImage({
    required this.filter,
    this.clip,
    this.blendMode = BlendMode.src,
  });

  /// The filter.
  final ImageFilter filter;

  @override
  final Rect? clip;

  @override
  final BlendMode blendMode;

  @override
  Object? get key => filter;

  @override
  bool operator ==(Object other) =>
      other is FilteredImage &&
      other.filter == filter &&
      other.clip == clip &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(filter, clip, blendMode);
}
