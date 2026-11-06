import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_underlay.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_render_object_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_underlay.dart';
import 'package:meta/meta.dart';

const Rect _everywhere = Rect.largest;

Rect _union(Rect a, Rect b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return a.expandToInclude(b);
}

/// The frame in paint order, retained and compared with the layer tree once a
/// frame.
///
/// A layer keeps its dirty bit private and a composited property update changes
/// a layer without touching its children, so the walk visits every layer. An
/// unchanged layer costs a few compares and allocates nothing.
///
/// After [lower], everything here equals what a fresh [Form] of the same tree
/// would hold. The soundness test asserts it after every generated mutation.
@internal
final class Form implements Scenery {
  @override
  final DirtyLog dirty = DirtyLog();

  /// This frame's number.
  int frame = 0;

  /// Layers visited by the last [lower], for tests.
  int get length => _count;

  /// The sites of the last [lower], in paint order.
  @override
  List<SiteFacts> get sites => _sites;
  final List<SiteFacts> _sites = [];
  final List<SiteNode> _siteNodes = [];

  /// The site nodes, parallel to [sites].
  List<SiteNode> get siteNodes => _siteNodes;

  @override
  Rect get screen => _screen;
  Rect _screen = Rect.zero;

  Layer? _root;
  double _dpr = 0;
  OpenNode? _top;
  FormWorld? _outside;

  final List<FormNode> _flat = [];
  int _count = 0;
  final List<VolatileNode> _volatile = [];
  int _volatileCount = 0;

  int _suppress = 0;
  int _next = 0;
  SiteNode? _site;

  /// Compares [root]'s tree with the last frame's.
  void lower(ContainerLayer root, double devicePixelRatio, Size physicalSize) {
    frame++;
    dirty.clear();
    _next = 0;
    _count = 0;
    _volatileCount = 0;
    _sites.length = 0;
    _siteNodes.length = 0;
    _screen = Offset.zero & (physicalSize / devicePixelRatio);
    if (!identical(root, _root) || devicePixelRatio != _dpr) {
      _root = root;
      _dpr = devicePixelRatio;
      _outside = FormWorld(
        Matrix4.diagonal3Values(1 / devicePixelRatio, 1 / devicePixelRatio, 1),
      );
      _top = switch (_nodeOf(root)) {
        final OpenNode node => node,
        _ => PlainNode(root),
      };
      dirty.add(0, _everywhere);
    }
    _top!.refreshIn(this, _outside!);
  }

  void _enter(FormNode node) {
    node.order = _next++;
    node.insideSite = _site;
    if (_count == _flat.length) {
      _flat.add(node);
    } else {
      _flat[_count] = node;
    }
    _count++;
  }

  void _log(int order, Rect rect) {
    if (_suppress == 0) dirty.add(order, rect);
  }

  /// The root's node, once a [lower] found one.
  FormNode? get top => _top;

  /// The node at [order] in paint order.
  FormNode nodeAt(int order) => _flat[order];

  /// Notes that [site]'s glass moved, which what lies over it reads.
  void noteSiteDrawn(SiteFacts site, Rect before) {
    if (before == site.drawn) return;
    dirty.add(site.order, _union(before, site.drawn));
  }

  /// Finds where each site may share a filter, once its rects are known.
  void settleFloors() {
    for (final site in _sites) {
      site.floor = site.hidden ? -1 : floorOf(site);
    }
  }

  /// The order of the last thing painted under [site]'s body: a leaf meeting
  /// what it draws, or anything that can't be replayed meeting what it reads.
  ///
  /// Walks back from the site, skipping groups its rects miss, so it usually
  /// stops at the card under the glass a few nodes back.
  ///
  /// A leaf's bounds are its layer's canvas bounds, the whole repaint boundary
  /// for a picture that shares one, so labels beside glass in one boundary
  /// count as under it.
  int floorOf(SiteFacts site) {
    final drawn = site.drawn;
    final reads = site.reads;
    var i = site.order - 1;
    while (i >= 0) {
      final node = _flat[i];
      // What another site paints with its glass moves back with it or lies
      // over it, as the plan decides from that site's own facts.
      final other = node.insideSite;
      if (other != null && other.end <= site.order) {
        i = other.order - 1;
        continue;
      }
      final parent = node.parent;
      if (parent != null &&
          parent.end <= site.order &&
          !parent.bounds.overlaps(reads) &&
          !parent.bounds.overlaps(drawn)) {
        i = parent.order - 1;
        continue;
      }
      switch (node) {
        case PictureNode(:final screen):
          if (screen.overlaps(drawn)) return i;
        case VolatileNode(:final screen):
          if (screen.overlaps(reads)) return i;
        case OpenNode() || OutputNode():
          break;
      }
      i--;
    }
    return -1;
  }

  @override
  ReadLimit limitUnder(SiteFacts site) {
    var limit = ReadLimit.none;
    for (var i = 0; i < _volatileCount; i++) {
      final node = _volatile[i];
      if (node.order >= site.order || !node.screen.overlaps(site.reads))
        continue;
      if (node.limit == ReadLimit.liveOnly) return ReadLimit.liveOnly;
      limit = ReadLimit.sceneOnly;
    }
    return limit;
  }

  @override
  int lastChangedUnder(int order, Rect band) {
    var latest = 0;
    var i = 0;
    while (i < order && i < _count) {
      final node = _flat[i];
      if (node is OpenNode &&
          node.end <= order &&
          !node.bounds.overlaps(band)) {
        i = node.end;
        continue;
      }
      if (node.changedAt > latest && node.extent.overlaps(band)) {
        latest = node.changedAt;
      }
      i++;
    }
    return latest;
  }
}

/// What a container gives its children. Retained: an unchanged frame writes
/// nothing and allocates nothing.
@internal
final class FormWorld {
  /// Creates the world outside everything, under [base].
  FormWorld(this.base);

  /// The transform to the screen, without [dx] and [dy].
  Matrix4 base;

  /// The translation after [base].
  double dx = 0;

  /// The translation after [base].
  double dy = 0;

  /// The clip on the screen, if any.
  Rect? clip;

  /// Inherited alpha, filters and clips.
  StateChain state = StateChain.root;

  /// Whether a filter above may move what is drawn anywhere.
  bool filtered = false;

  /// Bumped when anything above changed.
  int stamp = 1;

  /// Where [local] lands on the screen.
  Rect reaching(Rect local) {
    if (filtered) return _everywhere;
    final shifted = local.shift(Offset(dx, dy));
    final bounds = MatrixUtils.transformRect(base, shifted);
    final held = clip;
    return held == null ? bounds : held.intersect(bounds);
  }

  /// Takes the values of [outside]; true when any differs.
  bool inherit(FormWorld outside) => set(
    outside.base,
    outside.dx,
    outside.dy,
    outside.clip,
    outside.state,
    filtered: outside.filtered,
  );

  /// Writes the values; true when any differs.
  bool set(
    Matrix4 base,
    double dx,
    double dy,
    Rect? clip,
    StateChain state, {
    required bool filtered,
  }) {
    if (identical(this.base, base) &&
        this.dx == dx &&
        this.dy == dy &&
        (identical(this.clip, clip) || this.clip == clip) &&
        identical(this.state, state) &&
        this.filtered == filtered) {
      return false;
    }
    this.base = base;
    this.dx = dx;
    this.dy = dy;
    this.clip = clip;
    this.state = state;
    this.filtered = filtered;
    stamp++;
    return true;
  }
}

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

  /// The innermost site whose layer holds it, itself if it is one.
  SiteNode? insideSite;

  /// What it covers on the screen.
  Rect get extent;

  /// Whether the frame's composing may change what lies here after the walk
  /// read it, so [extent] says nothing about it.
  bool get holdsComposed => false;

  /// Reads the layer; true when what it covers changed.
  bool refreshIn(Form form, FormWorld world);

  /// Notes that this node left the tree.
  void removedFrom(Form form) => form._log(order, extent);
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
  bool refreshIn(Form form, FormWorld world) {
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
    picture = drawn;
    local = bounds;
    _seen = world.stamp;
    screen = drawn == null ? Rect.zero : world.reaching(bounds);
    changedAt = form.frame;
    form._log(order, _union(before, screen));
    return true;
  }
}

/// What the composer itself paints for a site. The plan accounts for it through
/// the site's own facts, so it says nothing about what changed.
@internal
final class OutputNode extends FormNode {
  /// Creates the node.
  OutputNode(super.layer);

  @override
  Rect get extent => Rect.zero;

  @override
  bool get holdsComposed => true;

  @override
  void removedFrom(Form form) {}

  @override
  bool refreshIn(Form form, FormWorld world) {
    form._enter(this);
    return false;
  }
}

/// Content the layer tree can't vouch for between frames: its pixels change
/// with no layer changing. Logged every frame, so nothing holds over it.
@internal
final class VolatileNode extends FormNode {
  /// Creates the node.
  VolatileNode(super.layer, this.limit);

  /// What it lets a read over it be.
  final ReadLimit limit;

  /// What it may reach on the screen.
  Rect screen = Rect.zero;

  @override
  Rect get extent => screen;

  @override
  bool refreshIn(Form form, FormWorld world) {
    form._enter(this);
    final local = switch (layer) {
      TextureLayer(:final rect) || PlatformViewLayer(:final rect) => rect,
      _ => null,
    };
    final Rect next;
    if (local != null) {
      next = world.reaching(local);
    } else if (layer is BackdropFilterLayer) {
      next = world.filtered ? _everywhere : world.clip ?? _everywhere;
    } else {
      next = _everywhere;
    }
    final changed = next != screen;
    if (changed) screen = next;
    changedAt = form.frame;
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

/// A container: what it gives its children is its own [world].
@internal
abstract class OpenNode extends FormNode {
  /// Creates the node.
  OpenNode(ContainerLayer super.layer);

  /// What its children inherit.
  late final FormWorld world = FormWorld(_noTransform);

  static final Matrix4 _noTransform = Matrix4.identity();

  /// The first child.
  FormNode? first;

  /// The union of what its children cover.
  Rect bounds = Rect.zero;

  /// One past its last descendant in paint order.
  int end = 0;

  @override
  Rect get extent => bounds;

  /// Whether the frame's composing edits this layer's children.
  bool get composes => false;

  bool _holdsComposed = false;

  @override
  bool get holdsComposed => _holdsComposed;

  /// Whether its children show at all.
  bool get shows => true;

  /// Writes [world] from [outside] and the layer's values; true when any
  /// differs.
  bool updateWorld(FormWorld outside);

  @override
  void removedFrom(Form form) => form._log(order, bounds);

  @override
  bool refreshIn(Form form, FormWorld outside) {
    form._enter(this);
    final moved = updateWorld(outside);
    if (moved) {
      changedAt = form.frame;
      form._log(order, bounds);
      form._suppress++;
    }
    var changed = moved;
    if (shows) {
      if (_walkChildren(form)) changed = true;
    } else {
      _holdsComposed = composes;
      if (first != null || !bounds.isEmpty) {
        first = null;
        changed = true;
      }
    }
    if (moved) {
      form._suppress--;
    }
    end = form._next;
    if (changed) {
      _recomputeBounds();
      changedAt = form.frame;
      if (moved) form._log(order, bounds);
    }
    return changed;
  }

  /// What the layer may draw beyond its children, in its parent's coordinates.
  Rect get extra => Rect.zero;

  void _recomputeBounds() {
    var union = extra;
    for (var child = first; child != null; child = child.next) {
      union = _union(union, child.extent);
    }
    bounds = union;
  }

  bool _walkChildren(Form form) {
    final layer = this.layer as ContainerLayer;
    var changed = false;
    var composed = composes;
    var old = first;
    FormNode? last;
    for (
      var child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      FormNode node;
      if (old != null && identical(old.layer, child)) {
        node = old;
        old = old.next;
      } else {
        final found = _ahead(old, child);
        if (found != null) {
          var gone = old!;
          while (!identical(gone, found)) {
            gone.removedFrom(form);
            changed = true;
            gone = gone.next!;
          }
          node = found;
          old = found.next;
        } else {
          node = _nodeOf(child);
          node.parent = this;
          if (node is! OutputNode) changed = true;
        }
      }
      if (node.refreshIn(form, world)) changed = true;
      if (node.holdsComposed) composed = true;
      if (last == null) {
        first = node;
      } else {
        last.next = node;
      }
      last = node;
    }
    for (var gone = old; gone != null; gone = gone.next) {
      if (gone is! OutputNode) changed = true;
      gone.removedFrom(form);
    }
    if (last == null) {
      first = null;
    } else {
      last.next = null;
    }
    _holdsComposed = composed;
    return changed;
  }

  // A list item that left: its next siblings are the same layers.
  static FormNode? _ahead(FormNode? from, Layer child) {
    var node = from?.next;
    for (var i = 0; node != null && i < 8; i++) {
      if (identical(node.layer, child)) return node;
      node = node.next;
    }
    return null;
  }
}

// Teaches the walk a layer type: this is the only place that switches on one.
FormNode _nodeOf(Layer layer) {
  switch (layer) {
    case GlassPictureLayer() || ThinOffsetLayer():
      return OutputNode(layer);
    case PictureLayer():
      return PictureNode(layer);
    case TextureLayer():
      return VolatileNode(layer, ReadLimit.sceneOnly);
    case PlatformViewLayer():
      return VolatileNode(layer, ReadLimit.liveOnly);
    case OpacitySeedLayer():
      return PlainNode(layer);
    case BackdropFilterLayer():
      return VolatileNode(layer, ReadLimit.liveOnly);
    case SeededBackdropPassLayer():
      return PlainNode(layer);
    case LiquidGlassBackdropFilterLayer():
      return SiteNode(layer);
    case GeometryTransformTrackingLayer():
      return SiteNode(layer);
    case TransformLayer():
      return TransformNode(layer);
    case FollowerLayer():
      return FollowerNode(layer);
    case OpacityLayer():
      return AlphaNode(layer);
    case ImageFilterLayer():
      return FilterNode(layer);
    case OffsetLayer() when layer.runtimeType == OffsetLayer:
      return ShiftNode(layer);
    case ColorFilterLayer():
      return TokenNode(layer, () => layer.colorFilter);
    case ShaderMaskLayer():
      return MaskNode(layer);
    case ClipRectLayer() ||
        ClipRRectLayer() ||
        ClipRSuperellipseLayer() ||
        ClipPathLayer() ||
        NativeClipLayer():
      return ClipNode(layer as ContainerLayer);
    case LeaderLayer():
      return ShiftNode(layer);
    case AnnotatedRegionLayer():
      return PlainNode(layer as ContainerLayer);
    case ContainerLayer() when layer.runtimeType == ContainerLayer:
      return PlainNode(layer);
    case ContainerLayer() when LiquidGlassUnderlay.effectsOf(layer) != null:
      return EffectsNode(layer);
    case _:
      return VolatileNode(layer, ReadLimit.liveOnly);
  }
}

/// A container that adds nothing.
@internal
final class PlainNode extends OpenNode {
  /// Creates the node.
  PlainNode(super.layer);

  // The rig's slots are plain containers, as is what glass adds to the scene.
  @override
  bool get composes => true;

  @override
  bool updateWorld(FormWorld outside) => world.inherit(outside);
}

/// An offset: what most repaint boundaries are, and all a scroll changes.
@internal
class ShiftNode extends OpenNode {
  /// Creates the node.
  ShiftNode(super.layer);

  Offset get _offset => switch (layer) {
    OffsetLayer(:final offset) => offset,
    LeaderLayer(:final offset) => offset,
    _ => Offset.zero,
  };

  @override
  bool updateWorld(FormWorld outside) {
    final offset = _offset;
    return world.set(
      outside.base,
      outside.dx + offset.dx,
      outside.dy + offset.dy,
      outside.clip,
      outside.state,
      filtered: outside.filtered,
    );
  }
}

/// A site: where glass or a scroll edge draws. It has one [facts] for its life.
@internal
final class SiteNode extends ShiftNode {
  /// Creates the node.
  SiteNode(super.layer) : facts = SiteFacts(layer) {
    if (layer case final GeometryTransformTrackingLayer tracking) {
      tracking.formNode = this;
    }
  }

  /// What the plan reads of it.
  final SiteFacts facts;

  /// Reads [facts] from the layer.
  void fill() => (layer as PlanSite).fillPlanFacts(facts);

  @override
  bool get composes => true;

  Form? _form;
  int _seen = -1;

  /// Whether this frame's walk reached the site and found nothing changed
  /// around it: where it lies, and all that its parent holds, which is all
  /// that paints with it.
  bool get rests {
    final frame = _form?.frame;
    return frame == _seen &&
        changedAt != frame &&
        parent != null &&
        parent!.changedAt != frame;
  }

  @override
  bool refreshIn(Form form, FormWorld outside) {
    _form = form;
    _seen = form.frame;
    facts.order = form._next;
    facts.state = outside.state;
    facts.clip = outside.clip;
    form._sites.add(facts);
    form._siteNodes.add(this);
    final above = form._site;
    form._site = this;
    final changed = super.refreshIn(form, outside);
    form._site = above;
    return changed;
  }
}

mixin _Matrix on OpenNode {
  Matrix4? _own;
  Matrix4? _ownedBase;
  double _ownedDx = 0;
  double _ownedDy = 0;
  late Matrix4 _combined;

  // The transform of what this layer holds. Allocates only when it changed.
  Matrix4 _resolve(FormWorld outside, Matrix4 own) {
    final held = _own;
    if (held == null ||
        !identical(_ownedBase, outside.base) ||
        _ownedDx != outside.dx ||
        _ownedDy != outside.dy ||
        !_storageEqual(held.storage, own.storage)) {
      _own = own;
      _ownedBase = outside.base;
      _ownedDx = outside.dx;
      _ownedDy = outside.dy;
      final at = outside.base.clone();
      at.translateByDouble(outside.dx, outside.dy, 0, 1);
      at.multiply(own);
      _combined = at;
    }
    return _combined;
  }

  static bool _storageEqual(List<double> a, List<double> b) {
    for (var i = 0; i < 16; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A transform.
@internal
final class TransformNode extends OpenNode with _Matrix {
  /// Creates the node.
  TransformNode(TransformLayer super.layer);

  // Most transforms sit at a zero offset and keep their matrix, so the walk
  // compares it without building the effective one.
  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as TransformLayer;
    final offset = layer.offset;
    final matrix = layer.transform;
    final Matrix4 own;
    if (matrix != null && offset == Offset.zero) {
      own = matrix;
    } else {
      own = Matrix4.translationValues(offset.dx, offset.dy, 0);
      if (matrix != null) own.multiply(matrix);
    }
    return world.set(
      _resolve(outside, own),
      0,
      0,
      outside.clip,
      outside.state,
      filtered: outside.filtered,
    );
  }
}

/// A follower: its transform comes from its leader, which moves with no change
/// to this layer, so it is read every frame.
@internal
final class FollowerNode extends OpenNode with _Matrix {
  /// Creates the node.
  FollowerNode(FollowerLayer super.layer);

  @override
  bool get shows {
    final layer = this.layer as FollowerLayer;
    return layer.link.leader != null || (layer.showWhenUnlinked ?? false);
  }

  @override
  bool updateWorld(FormWorld outside) => world.set(
    _resolve(outside, followerTransformNow(layer as FollowerLayer)),
    0,
    0,
    outside.clip,
    outside.state,
    filtered: outside.filtered,
  );
}

/// An opacity.
@internal
final class AlphaNode extends OpenNode {
  /// Creates the node.
  AlphaNode(OpacityLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  int? _chainAlpha;

  @override
  bool get shows => (layer as OpacityLayer).alpha != 0;

  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as OpacityLayer;
    final alpha = layer.alpha ?? 255;
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        _chainAlpha != alpha) {
      _chain = StateChain(outside.state, alpha);
      _chainParent = outside.state;
      _chainAlpha = alpha;
    }
    final offset = layer.offset;
    return world.set(
      outside.base,
      outside.dx + offset.dx,
      outside.dy + offset.dy,
      outside.clip,
      _chain!,
      filtered: outside.filtered,
    );
  }
}

/// An image filter: what lies under it may land anywhere.
@internal
final class FilterNode extends OpenNode {
  /// Creates the node.
  FilterNode(ImageFilterLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  ui.ImageFilter? _chainFilter;

  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as ImageFilterLayer;
    final filter = layer.imageFilter;
    if (filter == null) return world.inherit(outside);
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        !identical(_chainFilter, filter)) {
      _chain = StateChain(outside.state, filter);
      _chainParent = outside.state;
      _chainFilter = filter;
    }
    final offset = layer.offset;
    return world.set(
      outside.base,
      outside.dx + offset.dx,
      outside.dy + offset.dy,
      null,
      _chain!,
      filtered: true,
    );
  }
}

/// A layer that adds one value to the state of what it holds.
@internal
final class TokenNode extends OpenNode {
  /// Creates the node, reading its value from [token].
  TokenNode(super.layer, this.token);

  /// Reads the value.
  final Object? Function() token;

  StateChain? _chain;
  StateChain? _chainParent;

  @override
  bool updateWorld(FormWorld outside) {
    final value = token();
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        _chain!.token != value) {
      _chain = value == null ? outside.state : StateChain(outside.state, value);
      _chainParent = outside.state;
    }
    return world.set(
      outside.base,
      outside.dx,
      outside.dy,
      outside.clip,
      _chain!,
      filtered: outside.filtered,
    );
  }
}

/// A shader mask. A fragment shader keeps its identity while its uniforms
/// change, so it counts as changed every frame.
@internal
final class MaskNode extends OpenNode {
  /// Creates the node.
  MaskNode(ShaderMaskLayer super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  Object? _shader;
  Rect? _rect;
  BlendMode? _blend;
  Rect _extra = Rect.zero;

  @override
  Rect get extra => _extra;

  @override
  bool updateWorld(FormWorld outside) {
    final layer = this.layer as ShaderMaskLayer;
    final shader = layer.shader;
    final rect = layer.maskRect;
    final blend = layer.blendMode;
    if (shader == null || rect == null || blend == null) {
      return world.inherit(outside);
    }
    if (_chain == null ||
        shader is ui.FragmentShader ||
        !identical(_chainParent, outside.state) ||
        !identical(_shader, shader) ||
        _rect != rect ||
        _blend != blend) {
      _chain = StateChain(
        StateChain(outside.state, rect),
        shader is ui.FragmentShader ? Object() : shader,
      );
      _chainParent = outside.state;
      _shader = shader;
      _rect = rect;
      _blend = blend;
      _extra = outside.reaching(rect);
    }
    return world.set(
      outside.base,
      outside.dx,
      outside.dy,
      outside.clip,
      _chain!,
      filtered: outside.filtered,
    );
  }
}

/// A clip of any shape.
@internal
final class ClipNode extends OpenNode {
  /// Creates the node.
  ClipNode(super.layer);

  Object? _geometry;
  Clip? _behavior;
  Rect? _clip;
  StateChain? _chain;
  StateChain? _chainParent;
  int _seen = 0;

  static final _pathBounds = Expando<Rect>();

  (Object?, Clip) _read() => switch (layer) {
    ClipRectLayer(:final clipRect, :final clipBehavior) => (
      clipRect,
      clipBehavior,
    ),
    ClipRRectLayer(:final clipRRect, :final clipBehavior) => (
      clipRRect,
      clipBehavior,
    ),
    ClipRSuperellipseLayer(:final clipRSuperellipse, :final clipBehavior) => (
      clipRSuperellipse,
      clipBehavior,
    ),
    ClipPathLayer(:final clipPath, :final clipBehavior) => (
      clipPath,
      clipBehavior,
    ),
    NativeClipLayer(:final enabled, :final geometry, :final clipBehavior) => (
      enabled ? geometry : null,
      clipBehavior,
    ),
    _ => (null, Clip.none),
  };

  static Rect _boundsOf(Object geometry) => switch (geometry) {
    final Rect rect => rect,
    final RRect rect => rect.outerRect,
    final RSuperellipse rect => rect.outerRect,
    final Path path => _pathBounds[path] ??= path.getBounds(),
    _ => Rect.largest,
  };

  @override
  bool updateWorld(FormWorld outside) {
    final (geometry, behavior) = _read();
    if (geometry == null || behavior == Clip.none) {
      return world.inherit(outside);
    }
    if (_chain == null ||
        _seen != outside.stamp ||
        !identical(_chainParent, outside.state) ||
        _behavior != behavior ||
        !(identical(_geometry, geometry) || _geometry == geometry)) {
      _geometry = geometry;
      _behavior = behavior;
      _seen = outside.stamp;
      _clip = outside.reaching(_boundsOf(geometry));
      _chain = StateChain(StateChain(outside.state, geometry), behavior);
      _chainParent = outside.state;
    }
    return world.set(
      outside.base,
      outside.dx,
      outside.dy,
      _clip,
      _chain!,
      filtered: outside.filtered,
    );
  }
}

/// A layer type registered with [LiquidGlassUnderlay].
@internal
final class EffectsNode extends OpenNode with _Matrix {
  /// Creates the node.
  EffectsNode(super.layer);

  StateChain? _chain;
  StateChain? _chainParent;
  Object? _token;
  bool _hidden = false;

  @override
  bool get shows => !_hidden;

  @override
  bool updateWorld(FormWorld outside) {
    final effects = LiquidGlassUnderlay.effectsOf(layer)!;
    _hidden = effects.alpha == 0;
    final at = _resolve(outside, effects.transform);
    final token = (effects.clip, effects.alpha, effects.blur);
    if (_chain == null ||
        !identical(_chainParent, outside.state) ||
        _token != token) {
      final adds =
          effects.clip != null || effects.alpha != null || effects.blur > 0;
      _chain = adds ? StateChain(outside.state, token) : outside.state;
      _chainParent = outside.state;
      _token = token;
    }
    var clip = outside.clip;
    if (effects.clip case final rounded?) {
      final bounds = MatrixUtils.transformRect(at, rounded.outerRect);
      clip = clip == null ? bounds : clip.intersect(bounds);
    }
    final blurred = effects.blur > 0;
    return world.set(
      at,
      0,
      0,
      blurred ? null : clip,
      _chain!,
      filtered: outside.filtered || blurred,
    );
  }
}
