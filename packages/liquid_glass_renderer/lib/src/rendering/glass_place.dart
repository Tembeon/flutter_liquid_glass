import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';

/// Where glass draws: on a layer, in one of its blend groups, or inside the
/// body of another glass.
@internal
@immutable
sealed class GlassPlace {
  const GlassPlace();
}

/// Where glass that registers its geometry draws: on a layer, alone or in
/// one of its blend groups.
@internal
sealed class DrawnPlace extends GlassPlace {
  const DrawnPlace(this.link);

  /// The link of the layer it draws on.
  final GeometryRenderLink link;
}

/// On the layer [link] gathers, alone.
@internal
final class OnLayer extends DrawnPlace {
  /// On the layer [link] gathers.
  const OnLayer(super.link);

  @override
  bool operator ==(Object other) =>
      other is OnLayer && identical(other.link, link);

  @override
  int get hashCode => identityHashCode(link);
}

/// In the blend group [group] of the layer [link] gathers, which packs its
/// shapes.
@internal
final class InGroup extends DrawnPlace {
  /// In [group] on the layer [link] gathers.
  const InGroup(super.link, this.group);

  /// The blend group it joins.
  final GlassGroupLink group;

  @override
  bool operator ==(Object other) =>
      other is InGroup &&
      identical(other.link, link) &&
      identical(other.group, group);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(link), identityHashCode(group));
}

/// Inside the body of another glass, which draws it on a layer of its own.
@internal
final class InBody extends GlassPlace {
  /// Inside the body of another glass.
  const InBody();

  @override
  bool operator ==(Object other) => other is InBody;

  @override
  int get hashCode => (InBody).hashCode;
}
