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

  /// Whether a read under this limit keeps to the backdrop: one whose glass
  /// reads only an image has no scene read to fall back on.
  bool keepsToBackdrop({required bool imageOnly}) =>
      this == backdropOnly || (imageOnly && this == sceneOnly);
}

/// Inherited alpha, filters and clips, one link per layer that adds any.
///
/// Links are shared while a layer's value holds, so siblings compare by
/// identity first.
final class StateChain {
  /// Adds [token] under [parent].
  const StateChain(this.parent, this.token);

  /// The state outside every layer.
  static const StateChain root = StateChain(null, null);

  /// The link above.
  final StateChain? parent;

  /// The value this link adds.
  final Object? token;

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

/// What a read that can only come from an image does to it, past the plain
/// copy glass frosts by itself.
@immutable
final class ImageReadFilter {
  /// Creates the filter of an image read.
  const ImageReadFilter({
    this.filter,
    this.blur,
    this.clip,
    this.blendMode = BlendMode.src,
  });

  /// A plain copy, which what reads it composites as it needs to.
  static const ImageReadFilter none = ImageReadFilter();

  /// A filter applied as a backdrop filter over the image.
  final ImageFilter? filter;

  /// A mirrored Gaussian blur by these sigmas in logical pixels, standing for
  /// [filter].
  final (double, double)? blur;

  /// Where [filter] applies, the whole image when null, on the screen.
  final Rect? clip;

  /// How [filter]'s output composites over the image.
  final BlendMode blendMode;

  /// What image reads under one filter share.
  Object? get key => blur ?? filter;

  @override
  bool operator ==(Object other) =>
      other is ImageReadFilter &&
      other.filter == filter &&
      other.blur == blur &&
      other.clip == clip &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(filter, blur, clip, blendMode);
}
