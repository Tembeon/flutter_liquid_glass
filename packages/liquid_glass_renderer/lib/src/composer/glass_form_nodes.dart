part of 'glass_form.dart';

/// One layer as the composer knows it.
@internal
sealed class FormNode {
  /// Creates the node of [layer].
  FormNode(this.layer);

  /// The layer.
  final Layer layer;

  /// Its place in paint order this frame.
  int order = 0;

  /// The container above.
  OpenNode? parent;

  /// The next sibling.
  FormNode? next;

  /// The frame it last changed.
  int changedAt = 0;

  /// The frame what a read adds for it last changed. A move of what holds it,
  /// which [changedAt] counts, changes none of that, and neither does a
  /// [ShiftNode]'s own offset, which counts for its parent.
  int contentAt = -1;

  /// The innermost container of what one site paints with its glass that
  /// holds it, itself if it is one.
  OpenNode? owner;

  /// What it covers on the screen.
  Rect get extent;

  /// Whether the frame's composing may change what lies here after the walk
  /// read it, so [extent] says nothing about it.
  bool get holdsComposed => false;

  /// Reads the layer; true when what it covers changed.
  bool refreshIn(GlassForm form, FormWorld world);

  /// Notes that this node left the tree.
  void removedFrom(GlassForm form) => form._logGone(extent);
}

/// A picture.
@internal
final class PictureNode extends FormNode {
  /// Creates the node.
  PictureNode(PictureLayer super.layer);

  /// What it drew last.
  ui.Picture? picture;

  /// Its canvas bounds.
  Rect local = Rect.zero;

  /// Where it lies on the screen.
  Rect screen = Rect.zero;

  int _seen = 0;

  @override
  Rect get extent => screen;

  @override
  bool refreshIn(GlassForm form, FormWorld world) {
    form._enter(this);
    final layer = this.layer as PictureLayer;
    final drawn = layer.picture;
    final bounds = layer.canvasBounds;
    if (identical(drawn, picture) &&
        (identical(bounds, local) || bounds == local) &&
        _seen == world.stamp) {
      return false;
    }
    final before = screen;
    if (!identical(drawn, picture)) contentAt = form.frame;
    picture = drawn;
    local = bounds;
    _seen = world.stamp;
    screen = drawn == null ? Rect.zero : world.reaching(bounds);
    changedAt = form.frame;
    form._log(order, _union(before, screen));
    return true;
  }
}

/// What the composer itself shows for a site, whose fate holds no layer of the
/// walk. The plan accounts for it through the site's own facts, so it says
/// nothing about what changed.
@internal
final class OutputNode extends FormNode {
  /// Creates the node.
  OutputNode(GlassSlotLayer super.layer);

  /// The site the slot shows.
  PlanSite? get site => (layer as GlassSlotLayer).site;

  @override
  Rect get extent => Rect.zero;

  @override
  bool get holdsComposed => true;

  @override
  void removedFrom(GlassForm form) {}

  @override
  bool refreshIn(GlassForm form, FormWorld world) {
    form._enter(this);
    return false;
  }
}

/// A kind of content the layer tree can't vouch for between frames: what a
/// read over it may be, what it reaches on the screen and how a person is
/// told it limits a read.
@internal
enum VolatileKind {
  /// A [TextureLayer]: the scene holds the frame it shows under the glass.
  texture(ReadLimit.sceneOnly, 'a texture'),

  /// A [PlatformViewLayer], which only the engine composites.
  platformView(ReadLimit.backdropOnly, 'a platform view'),

  /// A [BackdropFilterLayer], which reads what lies under it.
  backdropFilter(ReadLimit.backdropOnly, 'a backdrop filter'),

  /// A layer type nobody registered: a container ([ForeignNode]), or another
  /// layer, which may draw anywhere.
  unregistered(ReadLimit.backdropOnly, null);

  const VolatileKind(this.limit, this._named);

  /// What it lets a read over it be.
  final ReadLimit limit;

  final String? _named;

  /// Why [layer] of this kind limits a read over it, for a person.
  String reasonFor(Layer layer) => switch (_named) {
    final named? => '$named lies under it',
    null =>
      '${layer.runtimeType} (unregistered) reaches its footprint -> '
          'LiquidGlassUnderlay.registerLayer',
  };
}

/// A zone of the screen the layer tree can't vouch for between frames: its
/// pixels may change with no layer changing, so it is logged every frame,
/// nothing holds over it, and glass painted after it reads over it as
/// [kind] allows.
@internal
mixin VolatileZone {
  /// The layer that holds it.
  Layer get layer;

  /// Its place in paint order this frame.
  int get order;

  /// The frame it last changed.
  abstract int changedAt;

  /// The frame what a read adds for it last changed.
  abstract int contentAt;

  /// What content it is.
  VolatileKind get kind;

  /// What it may reach on the screen.
  Rect screen = Rect.zero;

  /// Whether it may reach into [rect] on the screen, once the sites of
  /// [form] were asked.
  bool reaches(GlassForm form, Rect rect) => meets(screen, rect);

  // Takes [next] as this frame's zone; true when it moved.
  bool _noteZone(GlassForm form, Rect next) {
    final changed = next != screen;
    if (changed) screen = next;
    changedAt = form.frame;
    contentAt = form.frame;
    if (form._volatileCount == form._volatile.length) {
      form._volatile.add(this);
    } else {
      form._volatile[form._volatileCount] = this;
    }
    form._volatileCount++;
    form.dirty.add(order, screen);
    return changed;
  }
}

// Where content of unknown reach under [world] may draw: inside the clip
// above it, which no filter spreads, or anywhere.
Rect _clipOrEverywhere(FormWorld world) =>
    world.spread == 0 ? world.clip ?? _everywhere : _everywhere;

/// Content the layer tree can't vouch for between frames, holding no layer
/// the form reads.
@internal
final class VolatileNode extends FormNode with VolatileZone {
  /// Creates the node.
  VolatileNode(super.layer, this.kind);

  @override
  final VolatileKind kind;

  @override
  Rect get extent => screen;

  @override
  bool refreshIn(GlassForm form, FormWorld world) {
    form._enter(this);
    return _noteZone(form, switch ((kind, layer)) {
      (VolatileKind.texture, TextureLayer(:final rect)) ||
      (
        VolatileKind.platformView,
        PlatformViewLayer(:final rect),
      ) => world.reaching(rect),
      (VolatileKind.backdropFilter || VolatileKind.unregistered, _) =>
        _clipOrEverywhere(world),
      _ => _everywhere,
    });
  }
}

/// A container of a type nobody registered with `LiquidGlassUnderlay`, such
/// as a package's copy of [LeaderLayer]. A copy of the scene leaves out what
/// it holds, since its `addToScene` may draw that otherwise than its fields
/// say, and glass painted after it reads the backdrop over it.
///
/// It is read as a container all the same, so the glass inside it is
/// planned, and it places what it holds where its `applyTransform` says.
/// The zone glass reads the backdrop over is what it holds, once its type
/// has shown that `applyTransform` tells at paint where it draws: the same
/// after the scene was built as before, which a copy of [FollowerLayer],
/// placing its children while the scene is built, is not. Until then, and
/// for good for a type that told otherwise, the zone is the clip above it,
/// or the whole screen.
@internal
final class ForeignNode extends OpenNode with _Matrix, VolatileZone {
  /// Creates the node.
  ForeignNode(super.layer);

  static final Set<Type> _placedAtPaint = {};
  static final Set<Type> _placedLater = {};
  static final Matrix4 _scratch = Matrix4.zero();

  @override
  VolatileKind get kind => VolatileKind.unregistered;

  // The sites inside it, as a range of the form's.
  int _firstSite = 0;
  int _endSite = 0;

  // The glass inside it draws where it does, which no layer bounds tell.
  @override
  bool reaches(GlassForm form, Rect rect) {
    if (meets(screen, rect)) return true;
    for (var i = _firstSite; i < _endSite; i++) {
      if (meets(form._sites[i].ask.drawn, rect)) return true;
    }
    return false;
  }

  Matrix4 _placement() {
    final layer = this.layer as ContainerLayer;
    final placement = _scratch..setIdentity();
    if (layer.firstChild case final child?) {
      layer.applyTransform(child, placement);
    }
    return placement;
  }

  @override
  bool updateWorld(FormWorld outside) {
    final placement = _placement();
    final last = _own;
    return _placeUnder(
      outside,
      last != null && FormWorld._sameMatrix(last, placement)
          ? last
          : placement.clone(),
      outside.clip,
      outside.state,
      spread: outside.spread,
    );
  }

  @override
  bool refreshIn(GlassForm form, FormWorld outside) {
    final type = layer.runtimeType;
    final known = _placedAtPaint.contains(type) && !_placedLater.contains(type);
    _firstSite = form._sites.length;
    final moved = super.refreshIn(form, outside);
    _endSite = form._sites.length;
    final zoned = _noteZone(form, known ? bounds : _clipOrEverywhere(outside));
    form._foreignSeen = true;
    return moved || zoned;
  }

  // Called once the scene was built: what [applyTransform] says now, against
  // what it said before the scene, tells when the type places what it holds.
  void _checkPlacement() {
    final layer = this.layer as ContainerLayer;
    final before = _own;
    if (!layer.attached || layer.firstChild == null || before == null) return;
    if (bounds.isEmpty) return;
    final type = layer.runtimeType;
    if (FormWorld._sameMatrix(before, _placement())) {
      _placedAtPaint.add(type);
    } else {
      _placedLater.add(type);
    }
  }
}
