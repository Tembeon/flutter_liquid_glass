// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_underlay.dart';

/// A copy of what is painted under one backdrop effect, optionally run
/// through the effect's filter, that the effect draws from instead of
/// reading the backdrop.
///
/// A backdrop filter anywhere in a frame makes Impeller render the whole
/// frame offscreen, split the root pass at every read and blit the result to
/// the screen; a frame whose glass all paints over copies has none of that.
/// The copy is drawn from the layer tree itself while the frame composites:
/// everything painted before the layer, in a band around what its glass
/// samples, replayed into one image with every other copy the frame draws,
/// which the frame renders before the glass. It serves later frames while
/// the layers painted before the glass in that band are the same ones it was
/// drawn from (the same pictures under the same transforms, clips, opacities
/// and filters); a frame in which they changed draws a new one.
///
/// Inside a fractional opacity the copy holds what the screen shows under
/// the glass, the faded content of the glass's own group included, and the
/// glass fades with its group; the live path seeds the group's pass with the
/// backdrop instead (approximation, while a group fades).
///
/// A band that holds a backdrop filter (glass that reads live), a texture, a
/// platform view or a layer type it does not know is never copied, and the
/// glass reads its backdrop.
@internal
class BackdropUnderlay {
  /// Replaces [enabled] for a test.
  @visibleForTesting
  static bool? debugEnabledOverride;

  static final bool _defaultEnabled =
      !kIsWeb &&
      ui.ImageFilter.isShaderFilterSupported &&
      !runningUnderFlutterTest &&
      const bool.fromEnvironment('LIQUID_GLASS_UNDERLAY', defaultValue: true);

  /// Whether glass layers keep copies of what lies under them: wherever
  /// Impeller renders, not under `flutter test` unless a test turns it on.
  static bool get enabled => debugEnabledOverride ?? _defaultEnabled;

  // Room past the band a copy holds, in logical pixels, so glass that moves
  // or grows a little stays inside it.
  static const double _margin = 12;

  ui.Image? _image;
  Offset _offset = Offset.zero;
  // The screen rect the copy holds.
  Rect _rect = Rect.zero;
  // What the copy was drawn from, with the copies drawn with it.
  _Island? _island;
  // This frame's request until it is served, and the island the composer
  // planned for it.
  _Ask? _ask;
  _Plan? _plan;

  /// How many copies were taken.
  @visibleForTesting
  int debugCaptures = 0;

  /// Why the last frame did not serve the copy, for diagnostics.
  @visibleForTesting
  String? debugMiss;

  /// How many copies served alone were refused, by what refused them: the
  /// type of the layer that blocked the band, `not reached` or `off screen`.
  @visibleForTesting
  static final debugMisses = <String, int>{};

  /// How many scroll edges glass signed, by whether its band meets the
  /// edge's output (`output`) or only the margin the edge reads (`margin`).
  @visibleForTesting
  static final debugEdgeSigns = <String, int>{};

  /// How many times the copies were drawn with copies pending, by what
  /// asked for them: the composer once the frame was planned, a read, or a
  /// scene the composer did not plan, which draws a copy at once.
  @visibleForTesting
  static final debugFlushes = <String, int>{};

  /// How many glass over copies not drawn yet were drawn into other copies
  /// of their frame, as the glass's filter over what those copies hold
  /// before it.
  @visibleForTesting
  static int debugFolds = 0;

  /// How many images the copies of all glass were drawn into.
  @visibleForTesting
  static int get debugImagesDrawn => _Atlas.drawn;

  /// How many filtered layers the copies were drawn in: one holds every copy
  /// of one blur in an image.
  @visibleForTesting
  static int debugBlurLayers = 0;

  /// How many islands of copies were drawn, by how many copies each held.
  @visibleForTesting
  static final debugIslands = <int, int>{};

  /// Whether [UnderlayFrame.plan] plans islands; without, every copy is
  /// drawn on its own.
  @visibleForTesting
  static bool debugIslandsEnabled = true;

  /// The image that holds the copy, once it is drawn.
  @visibleForTesting
  ui.Image? get debugImage => _image;

  /// The screen rect [debugImage] holds for this copy, in logical pixels,
  /// and where its top left lies in the image, in its pixels.
  @visibleForTesting
  (Rect, Offset) get debugPlace => (_rect, _offset);

  /// Asks for this frame's copy of the screen around [region], exact for
  /// everything inside it; [serve] hands it over.
  ///
  /// [anchor] is the layer the caller begins with in paint order: the copy
  /// holds what is painted before it, with [filter] applied as a backdrop
  /// filter with [filterBlendMode] inside [filterClip] (the whole copy when
  /// null), in screen logical pixels; a copy serves only callers that pass an
  /// equal filter. [blur] stands in for a [filter] that is a mirrored
  /// Gaussian blur over the whole copy by these sigmas in logical pixels:
  /// the copy is blurred at its own pixels, without reading
  /// a backdrop, together with the frame's other copies under the same blur.
  /// NEAR: past a copy's edge the blur reads what lies beside it in the
  /// shared layer rather than a mirror of the copy; a copy holds 3 sigma past
  /// what its glass samples, so that reaches the glass only as the tail of
  /// the blur. Glass stretched along the axes differs from reading the
  /// backdrop by up to 15 levels in a few hundred pixels on the Pixel 6a.
  /// [anchor] lies in a [RenderView]'s layer tree, and the copy is cut to its
  /// screen. The copy holds [downscale] device pixels in each of its pixels
  /// along each side, for a caller that blurs or frosts it enough that the
  /// detail lost is NEAR.
  ///
  /// [body] is the rect the caller's glass paints, in screen logical
  /// pixels: glass painted before [anchor] that does not meet it lies beside
  /// the caller's glass rather than under it and is left out of the copy, so
  /// glass side by side never waits on another's copy. Without [body] the
  /// copy is never drawn with others.
  ///
  /// [own] is the layer holding everything the caller paints with its glass
  /// (its shadows and children). Copies beside the caller's that are drawn
  /// together with it ignore what is painted there: NEAR, glass does not
  /// show its neighbour's shadow and label.
  ///
  /// While the view's composer plans the frame, every glass asks before any
  /// is served, and the composer plans the copies of glass side by side as
  /// one island (see [UnderlayFrame.plan]).
  void request({
    required Layer anchor,
    required double devicePixelRatio,
    required Rect region,
    OpacitySeedLayer? own,
    ui.ImageFilter? filter,
    (double, double)? blur,
    Rect? filterClip,
    BlendMode filterBlendMode = BlendMode.src,
    int downscale = 1,
    Rect? body,
  }) {
    assert(
      blur == null ||
          filter == null &&
              filterClip == null &&
              filterBlendMode == BlendMode.src,
      'A blur covers the whole copy and stands for its filter.',
    );
    _ask = null;
    _plan = null;
    final view = anchor.owner;
    if (view is! RenderView) return;
    final screen = Offset.zero & view.size;
    final pixels = devicePixelRatio / downscale;
    final ask = _Ask(
      frame: GlassComposer.planning(view),
      anchor: anchor,
      own: own,
      devicePixelRatio: devicePixelRatio,
      pixelRatio: pixels,
      screen: screen,
      band: _snapOut(region, pixels).intersect(screen),
      filter: filter,
      blur: blur,
      filterKey: blur ?? filter,
      filterClip: filterClip,
      filterBlendMode: filterBlendMode,
      body: body,
    );
    _ask = ask;
    if (!ask.band.isEmpty) ask.frame?._asks.add(this);
  }

  /// The copy the last [request] asked for, or null when what lies there
  /// cannot be drawn again, and the caller reads its backdrop this frame.
  ///
  /// The copy taken in an earlier frame serves while the layers it was
  /// drawn from are unchanged; otherwise a new one is recorded and drawn
  /// with the frame's other pending copies once the composer has composed
  /// every layer ([UnderlayFrame.drawPending]), or earlier if its image is
  /// read. In a scene the composer did not plan it is drawn at once.
  ///
  /// Called while the frame composites, when the layers before the
  /// request's anchor are final.
  UnderlayCopy? serve() {
    final ask = _ask;
    final plan = _plan;
    _ask = null;
    _plan = null;
    if (ask == null) return null;
    if (ask.band.isEmpty) {
      _count(debugMisses, 'off screen');
      return null;
    }
    final scan = _Scan.of(
      ask.frame,
      _rootOf(ask.anchor),
      ask.devicePixelRatio,
      ask.anchor,
    );
    final limit = scan.reach(ask.anchor);
    if (plan?.serve(this, ask, scan, limit) case final copy?) return copy;
    return _islandOf([this], [ask], scan, limit)?.copy;
  }

  // The copy of the first of [members] from the island they make, held or
  // recorded anew, with the island and the rect each member holds of it, or
  // null when the island cannot be drawn: blocked, not reached, or, for more
  // than one copy, over glass whose copy is pending.
  static _Decision? _islandOf(
    List<BackdropUnderlay> members,
    List<_Ask> asks,
    _Scan scan,
    int limit,
  ) {
    final first = members.first;
    final ask = asks.first;
    final alone = members.length == 1;
    final bodies = [
      for (final ask in asks)
        if (ask.body case final body?) body,
    ];
    final last = first._island;
    // A copy drawn with others, served on its own, as in a scene the
    // composer does not plan, holds while the island does.
    if (alone &&
        last != null &&
        last.members.length > 1 &&
        first._holdsIn(last, ask, scan, limit)) {
      first.debugMiss = null;
      return (
        copy: UnderlayCopy._(first, first._rect, ask.pixelRatio),
        island: last,
        held: true,
        rects: [first._rect],
      );
    }
    // A later member that was not drawn with the first last time (something
    // else is painted between their glass) is served on its own again, and
    // the island holds for the others.
    final kept = last == null ? null : _kept(last.members, members);
    final known =
        last != null &&
        last.signature != null &&
        last.fits(ask) &&
        kept != null;
    // Signing replays no pictures: a copy is recorded only once it is
    // known to be drawn now.
    var signed = known
        ? _Prefix.signed(ask.anchor, last.rect, scan, limit, [
            for (final i in kept)
              if (asks[i].body case final body?) body,
          ])
        : null;
    final held =
        signed != null &&
        !signed.blocked &&
        signed.reached &&
        _same(signed.out, last!.signature);
    if (held) {
      var inside = true;
      for (final i in kept!) {
        inside = inside && rectContains(members[i]._rect, asks[i].band);
      }
      if (inside) {
        first.debugMiss = null;
        return (
          copy: UnderlayCopy._(first, first._rect, ask.pixelRatio),
          island: last,
          held: true,
          rects: [for (final member in members) member._rect],
        );
      }
    }
    // Glass that moved over content that held still takes room to move on;
    // under content that changes, the copy holds no more than the band.
    Rect roomy(_Ask ask) => _snapOut(
      ask.band.inflate(_margin),
      ask.pixelRatio,
    ).intersect(ask.screen);
    final rects = [
      for (final ask in asks)
        if (held && ask.filterClip == null) roomy(ask) else ask.band,
    ];
    final rect = rects.reduce((a, b) => a.expandToInclude(b));
    if (signed == null || signed.band != rect) {
      signed = _Prefix.signed(ask.anchor, rect, scan, limit, bodies);
    }
    if (signed.blocked || !signed.reached) {
      if (alone && !kReleaseMode) {
        final why = signed.blocked
            ? '${signed.blocker.runtimeType}'
            : 'not reached';
        _count(debugMisses, why);
        first.debugMiss = 'blocked by $why';
      }
      return null;
    }
    // A copy that holds glass over a copy not drawn yet draws that glass as
    // its filter, which takes the copy's pixels to be the screen's.
    final island = _Island(
      ask,
      rect,
      pixelRatio: signed.folds ? ask.devicePixelRatio : ask.pixelRatio,
    );
    final tile = _Tile(island);
    island.tile = tile;
    // Recorded when the frame's copies are drawn, not now: glass in the band
    // whose own copy is drawn with it is drawn by then as far as it can be.
    tile.redraw = () {
      final replay = _Prefix(
        ask.anchor,
        rect,
        ui.PictureRecorder(),
        scan: scan,
        limit: limit,
        bodies: [...island.bodies.nonNulls],
      );
      final picture = replay.record(island.pixelRatio);
      if (picture != null && !island.broken) island.signature = replay.out;
      tile.pieces = replay.pieces;
      return picture;
    };
    first._join(island, rects.first, ask);
    if (ask.frame case final frame?) {
      frame._atlas.add(tile);
    } else {
      final atlas = _Atlas();
      atlas.add(tile);
      atlas.flush('at once');
    }
    return (
      copy: UnderlayCopy._(first, first._rect, island.pixelRatio),
      island: island,
      held: false,
      rects: rects,
    );
  }

  // Whether this copy, drawn in [island] with others, still holds: what lies
  // under the island before its first glass is unchanged, and nothing but
  // the island's glass is painted in this copy's band between that glass
  // and this one.
  bool _holdsIn(_Island island, _Ask ask, _Scan scan, int limit) {
    final signature = island.signature;
    final body = ask.body;
    if (signature == null ||
        body == null ||
        limit < 0 ||
        !island.fits(ask) ||
        !rectContains(_rect, ask.band) ||
        island.members.any((member) => member._image == null)) {
      return false;
    }
    final first = island.anchors.first;
    final from = scan.startOf(first);
    if (from == null || from > limit) return false;
    final index = island.members.indexOf(this);
    final bodies = [
      for (final (i, other) in island.bodies.indexed)
        if (i == index) body else ?other,
    ];
    final signed = _Prefix.signed(first, island.rect, scan, from, bodies);
    if (signed.blocked || !signed.reached || !_same(signed.out, signature)) {
      return false;
    }
    return scan.onlyIslandBetween(
      from,
      limit,
      _rect,
      body,
      starts: {
        for (final anchor in island.anchors)
          if (scan.startOf(anchor) case final start? when start < limit) start,
      },
      owned: {...island.owns.nonNulls},
    );
  }

  // Draws this copy from [island] from now on, [rect] of it.
  void _join(_Island island, Rect rect, _Ask ask) {
    release();
    _rect = rect;
    _island = island;
    island.members.add(this);
    island.rects.add(rect);
    island.bodies.add(ask.body);
    island.anchors.add(ask.anchor);
    island.owns.add(ask.own);
    debugCaptures++;
    debugMiss = null;
  }

  /// Forgets the copy while the effect does not draw from one.
  void release() {
    _image?.dispose();
    _image = null;
    _island?._leave(this);
    _island = null;
  }

  // Where the copies [drawn] together lie in [members], or null when they
  // are not [members] less some of its later ones, or one has no image.
  static List<int>? _kept(
    List<BackdropUnderlay> drawn,
    List<BackdropUnderlay> members,
  ) {
    final kept = <int>[];
    for (final (i, member) in members.indexed) {
      if (kept.length < drawn.length && identical(drawn[kept.length], member)) {
        kept.add(i);
      }
    }
    if (kept.length != drawn.length ||
        kept.isEmpty ||
        kept.first != 0 ||
        drawn.any((member) => member._image == null)) {
      return null;
    }
    return kept;
  }

  static Layer _rootOf(Layer layer) {
    var root = layer;
    while (root.parent != null) {
      root = root.parent!;
    }
    return root;
  }

  static Rect _snapOut(Rect rect, double dpr) => Rect.fromLTRB(
    (rect.left * dpr).floorToDouble() / dpr,
    (rect.top * dpr).floorToDouble() / dpr,
    (rect.right * dpr).ceilToDouble() / dpr,
    (rect.bottom * dpr).ceilToDouble() / dpr,
  );

  static bool _same(List<Object?>? a, List<Object?>? b) {
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      // An image filter is unchanged only as the same object: comparing a
      // shader filter by value creates its native filter, which takes the
      // shader's uniforms then rather than when the scene is built.
      if (x is ui.ImageFilter) return false;
      if (x != y) return false;
    }
    return true;
  }
}

/// The copies the composer of one view plans in a frame: the scan of the
/// view's layers that every copy of the frame replays, and the copies
/// recorded and not drawn yet.
@internal
final class UnderlayFrame {
  _Scan? _scan;
  final _atlas = _Atlas();
  final _asks = <BackdropUnderlay>[];

  /// Plans the copies asked for so far as islands: copies of glass side by
  /// side, in paint order, with one filter at one pixel ratio, whose bands
  /// meet and together cover little more than the bands, and whose glass
  /// does not overlap. The composer calls it once every glass has asked and
  /// before any is served.
  void plan() {
    final plans = <_Plan>[];
    if (BackdropUnderlay.debugIslandsEnabled) {
      for (final underlay in _asks) {
        final ask = underlay._ask;
        if (ask == null || !ask.joins) continue;
        final joined = plans.where((plan) => plan.admits(ask)).firstOrNull;
        if (joined != null) {
          joined.add(underlay, ask);
        } else {
          plans.add(_Plan(underlay, ask));
        }
      }
    }
    _asks.clear();
    for (final plan in plans) {
      if (plan.members.length < 2) continue;
      for (final member in plan.members) {
        member._plan = plan;
      }
    }
  }

  /// Draws the copies recorded in this frame and not drawn yet and lets go
  /// of the frame's scan. The composer calls it once every glass of the
  /// frame has been served, so no copy is drawn while the scene is built.
  void drawPending() {
    _asks.clear();
    _atlas.flush('planned');
    _scan = null;
  }
}

// [rects] holds one rect per member of the island, in member order.
typedef _Decision = ({
  UnderlayCopy copy,
  _Island island,
  bool held,
  List<Rect> rects,
});

// What a copy is asked for in a frame; see [BackdropUnderlay.request].
final class _Ask {
  _Ask({
    required this.frame,
    required this.anchor,
    required this.own,
    required this.devicePixelRatio,
    required this.pixelRatio,
    required this.screen,
    required this.band,
    required this.filter,
    required this.blur,
    required this.filterKey,
    required this.filterClip,
    required this.filterBlendMode,
    required this.body,
  });

  // The frame the view's composer plans, or null in a scene it does not.
  final UnderlayFrame? frame;
  final Layer anchor;
  final OpacitySeedLayer? own;
  final double devicePixelRatio;
  final double pixelRatio;
  final Rect screen;
  final Rect band;
  final ui.ImageFilter? filter;
  final (double, double)? blur;
  final Object? filterKey;
  final Rect? filterClip;
  final BlendMode filterBlendMode;
  final Rect? body;

  bool get filtered => filter != null || blur != null;

  // Whether the copy can be drawn with copies beside it.
  bool get joins =>
      body != null && filterClip == null && filterBlendMode == BlendMode.src;
}

// Copies the composer planned to draw as one island in a frame, in paint
// order. The first one served decides for all: it signs what lies under
// the island before its glass once, and the island holds or is recorded
// again. Each later one joins only while nothing but the island's glass is
// painted in its band between the first glass and its own; otherwise it is
// served on its own.
final class _Plan {
  _Plan(BackdropUnderlay first, _Ask ask)
    : rect = ask.band,
      _covered = ask.band.width * ask.band.height {
    add(first, ask);
  }

  final members = <BackdropUnderlay>[];
  final _asks = <_Ask>[];
  Rect rect;
  double _covered;

  // What the first member decided for all, in [_scan].
  _Decision? _decision;
  _Scan? _scan;
  // Where the glass of the island's members served so far begins in the
  // scan, and what each paints with its glass.
  final _starts = <int>{};
  final _owned = <Layer>{};

  bool admits(_Ask ask) {
    final first = _asks.first;
    if (ask.pixelRatio != first.pixelRatio ||
        ask.filterKey != first.filterKey ||
        ask.filtered != first.filtered ||
        !_meets(rect, ask.band)) {
      return false;
    }
    for (final other in _asks) {
      if (_meets(other.body!, ask.body!)) return false;
    }
    final joined = rect.expandToInclude(ask.band);
    final overlap = rect.intersect(ask.band);
    final covered =
        _covered +
        ask.band.width * ask.band.height -
        overlap.width * overlap.height;
    return joined.width * joined.height <= covered * 1.25;
  }

  void add(BackdropUnderlay underlay, _Ask ask) {
    final overlap = rect.intersect(ask.band);
    _covered +=
        ask.band.width * ask.band.height - overlap.width * overlap.height;
    rect = rect.expandToInclude(ask.band);
    members.add(underlay);
    _asks.add(ask);
  }

  // The copy of [underlay], a member, from the island, or null when it is
  // served on its own.
  UnderlayCopy? serve(
    BackdropUnderlay underlay,
    _Ask ask,
    _Scan scan,
    int limit,
  ) {
    final index = members.indexOf(underlay);
    if (index == 0) {
      if (limit < 0) return null;
      final decided = BackdropUnderlay._islandOf(members, _asks, scan, limit);
      if (decided == null) return null;
      _decision = decided;
      _scan = scan;
      _starts.add(limit);
      if (ask.own case final own?) _owned.add(own);
      return decided.copy;
    }
    final decision = _decision;
    if (decision == null ||
        decision.held && !decision.island.members.contains(underlay) ||
        limit < 0 ||
        !identical(scan, _scan) ||
        !scan.onlyIslandBetween(
          _starts.first,
          limit,
          decision.rects[index],
          ask.body!,
          starts: _starts,
          owned: _owned,
        )) {
      decision?.island._leave(underlay);
      return null;
    }
    _starts.add(limit);
    if (ask.own case final own?) _owned.add(own);
    if (!decision.held) {
      underlay._join(decision.island, decision.rects[index], ask);
    }
    return UnderlayCopy._(
      underlay,
      underlay._rect,
      decision.island.pixelRatio,
    );
  }
}

// What the copies drawn as one were drawn from: the band they were
// recorded over, from what is painted before the first one's glass, and its
// signature; and each copy's rect of it.
final class _Island {
  _Island(_Ask ask, this.rect, {required this.pixelRatio})
    : filter = ask.filter,
      blur = ask.blur,
      filterKey = ask.filterKey,
      filterClip = ask.filterClip,
      filterBlendMode = ask.filterBlendMode,
      devicePixelRatio = ask.devicePixelRatio;

  final Rect rect;
  final ui.ImageFilter? filter;
  final (double, double)? blur;
  final Object? filterKey;
  final Rect? filterClip;
  final BlendMode filterBlendMode;
  final double devicePixelRatio;
  final double pixelRatio;
  final members = <BackdropUnderlay>[];
  final rects = <Rect>[];
  final bodies = <Rect?>[];
  final anchors = <Layer>[];
  final owns = <OpacitySeedLayer?>[];
  List<Object?>? signature;
  _Tile? tile;
  // Once a copy has left, the signature no longer tells whether the others
  // hold: the island is recorded again.
  bool broken = false;

  bool fits(_Ask ask) =>
      ask.filterKey == filterKey &&
      ask.filterClip == filterClip &&
      ask.filterBlendMode == filterBlendMode &&
      ask.devicePixelRatio == devicePixelRatio &&
      ask.pixelRatio == pixelRatio;

  void _leave(BackdropUnderlay underlay) {
    final index = members.indexOf(underlay);
    if (index < 0) return;
    members.removeAt(index);
    rects.removeAt(index);
    bodies.removeAt(index);
    anchors.removeAt(index);
    owns.removeAt(index);
    broken = true;
    signature = null;
    if (members.isEmpty) {
      if (tile case final tile?) tile.atlas?.cancel(tile);
      tile = null;
    }
  }
}

// Replays a pass's scan up to [stop], collecting what draws into [band]
// and, with a [recorder], drawing it the way the engine draws each
// layer: canvas calls rather than a scene, which would make an engine layer
// and its Dart handle for every push.
class _Prefix {
  _Prefix(
    this.stop,
    this.band,
    this.recorder, {
    required this.scan,
    required this.limit,
    this.bodies = const [],
  }) : canvas = recorder == null ? null : Canvas(recorder);

  // What is painted before [stop] in [band], signed without drawing it.
  factory _Prefix.signed(
    Layer stop,
    Rect band,
    _Scan scan,
    int limit,
    List<Rect> bodies,
  ) {
    final prefix = _Prefix(
      stop,
      band,
      null,
      scan: scan,
      limit: limit,
      bodies: bodies,
    );
    prefix.run();
    return prefix;
  }

  final Layer stop;
  final Rect band;
  double get devicePixelRatio => scan.devicePixelRatio;
  // The bodies of the glass the copy is for, if it is for glass.
  final List<Rect> bodies;
  // Without one, the walk only signs what it meets.
  ui.PictureRecorder? recorder;
  Canvas? canvas;
  final out = <Object?>[];
  double _pixels = 1;

  // What the copy draws before each glass over a copy not drawn yet, and
  // that glass, which reads it: the copy goes on in a picture after it.
  final pieces = <(ui.Picture, _Fold)>[];

  // The pass's scan this walk replays, and where [stop] lies in it, or -1
  // when the scan cannot reach it.
  final _Scan scan;
  final int limit;

  bool reached = false;
  bool blocked = false;
  Layer? blocker;

  // Whether the band holds glass over a copy not drawn yet.
  bool folds = false;

  static Set<Layer> _ancestors(Layer layer) {
    final path = Set<Layer>.identity();
    for (var node = layer.parent; node != null; node = node.parent) {
      path.add(node);
    }
    return path;
  }

  // Records what is painted before [stop] in [band] (screen logical pixels)
  // at [pixels] per logical pixel from the band's origin, or returns null
  // when that cannot be drawn again.
  ui.Picture? record(double pixels) {
    _pixels = pixels;
    _begin();
    run();
    final content = recorder!.endRecording();
    if (blocked || !reached) {
      content.dispose();
      for (final (picture, _) in pieces) {
        picture.dispose();
      }
      pieces.clear();
      return null;
    }
    return content;
  }

  void _begin() {
    final rect = band;
    final dpr = devicePixelRatio;
    final c = canvas!;
    // A picture drawn into a canvas clipped to the copy is culled to what
    // reaches it while it is recorded.
    c.clipRect(
      Rect.fromLTWH(0, 0, rect.width * _pixels, rect.height * _pixels),
      doAntiAlias: false,
    );
    if (_pixels != dpr) c.scale(_pixels / dpr);
    c.translate(-rect.left * dpr, -rect.top * dpr);
  }

  // Ends the picture before [fold] and begins the next one inside the
  // groups [open] around it.
  void fold(_Fold fold, List<(int, _Open)> open) {
    folds = true;
    final c = canvas;
    if (c == null) return;
    for (final (saves, group) in open.reversed) {
      group.finish(c, saves);
    }
    pieces.add((recorder!.endRecording(), fold));
    final next = ui.PictureRecorder();
    recorder = next;
    canvas = Canvas(next);
    _begin();
    for (var k = 0; k < open.length; k++) {
      final group = open[k].$2;
      open[k] = (group.apply(canvas!), group);
    }
  }

  // Draws what is painted before [stop] in [band] from the pass's scan. A
  // scan that cannot reach [stop] met a layer it cannot draw again on the
  // way there.
  void run() {
    if (limit < 0) {
      blocked = scan.blocker != null;
      blocker = scan.blocker;
      return;
    }
    scan.replay(this, limit);
  }

  // Whether glass drawn inside [bounds] lies beside the copy's glass rather
  // than under it.
  bool beside(Rect bounds) =>
      bodies.isNotEmpty && !bodies.any((body) => _meets(bounds, body));

  static Paint _alpha(int alpha) {
    final paint = Paint();
    paint.color = Color.fromARGB(alpha, 0, 0, 0);
    return paint;
  }

  static Paint _filtering(ui.ImageFilter filter) {
    final paint = Paint();
    paint.imageFilter = filter;
    return paint;
  }

  // Whether anything [layer] draws may land in the band, judged by its
  // pictures placed through each layer's own transform and grown by a
  // generous blur reach, since what the layer adds besides is unknown.
  bool _mayReach(
    Layer layer,
    Matrix4 transform,
    Rect? clip, {
    required bool filtered,
  }) {
    if (filtered) return true;
    var reach = false;
    void visit(Layer node, Matrix4 m) {
      if (reach) return;
      if (identical(node, stop)) {
        // The glass sits inside it: the walk cannot stop there.
        reach = true;
        return;
      }
      switch (node) {
        case PictureLayer():
          var bounds = MatrixUtils.transformRect(m, node.canvasBounds);
          if (clip != null) bounds = bounds.intersect(clip);
          if (bounds.inflate(64).overlaps(band)) reach = true;
        case TextureLayer() || PlatformViewLayer():
          reach = true;
        case ContainerLayer():
          for (var c = node.firstChild; c != null; c = c.nextSibling) {
            final childTransform = m.clone();
            applyTransformNow(node, c, childTransform);
            visit(c, childTransform);
          }
        default:
          reach = true;
      }
    }

    visit(layer, transform);
    return reach;
  }
}

// What a compositing pass paints, in paint order, walked once as far as the
// glass that composites last: each copy of the pass replays the part before
// its glass instead of walking the layer tree again. Glass composites in
// paint order and changes only its own subtree, so what lies before the
// glass that composites is final; the layers whose drawing glass decides
// while it composites are kept and read when a copy replays them.
final class _Scan {
  _Scan._(this.root, this.devicePixelRatio) {
    _cursors.add(
      _Cursor(
        null,
        root,
        Matrix4.diagonal3Values(1 / devicePixelRatio, 1 / devicePixelRatio, 1),
        null,
        const [],
        filtered: false,
        open: -1,
      ),
    );
  }

  // The scan of the pass that composites [root] in [frame], begun anew when
  // the scan walked to or past [anchor] already: the tree composites again.
  // A scene the composer did not plan, such as an image taken after the
  // frame, scans for each copy alone.
  factory _Scan.of(
    UnderlayFrame? frame,
    Layer root,
    double devicePixelRatio,
    Layer anchor,
  ) {
    if (frame == null) return _Scan._(root, devicePixelRatio);
    final scan = frame._scan;
    if (scan != null &&
        identical(scan.root, root) &&
        scan.devicePixelRatio == devicePixelRatio &&
        scan._walked[anchor] == null) {
      return scan;
    }
    return frame._scan = _Scan._(root, devicePixelRatio);
  }

  final Layer root;
  final double devicePixelRatio;
  final _walked = Expando<int>();

  // Where [layer] begins in [entries], once the walk reached it.
  int? startOf(Layer layer) => _walked[layer];
  final entries = <_Entry>[];
  final _cursors = <_Cursor>[];

  // The container above the last anchor [reach] could not reach whose
  // children it does not walk, if one stopped it.
  Layer? blocker;

  // Walks on to [anchor] and returns how many entries lie before it, or -1
  // when the walk cannot reach it.
  int reach(Layer anchor) {
    blocker = null;
    Set<Layer>? path;
    while (true) {
      final at = _cursors.last;
      final layer = at.next;
      if (layer == null) {
        if (at.layer == null) return -1;
        _close();
        continue;
      }
      if (identical(layer, anchor)) {
        _walked[anchor] = entries.length;
        return entries.length;
      }
      at.next = layer.nextSibling;
      if (!_visit(layer, at)) {
        path ??= _Prefix._ancestors(anchor);
        if (path.contains(layer)) {
          blocker = layer;
          return -1;
        }
      }
    }
  }

  void _add(_Cursor at, _Entry entry, Rect bounds) {
    entries.add(entry);
    at.include(bounds);
  }

  void _push(
    ContainerLayer layer,
    _Open open,
    Matrix4 transform,
    Rect? clip,
    List<Object?> state, {
    required bool filtered,
  }) {
    entries.add(open);
    _walked[layer] = entries.length - 1;
    _cursors.add(
      _Cursor(
        layer,
        layer.firstChild,
        transform,
        clip,
        state,
        filtered: filtered,
        open: entries.length - 1,
      ),
    );
  }

  void _close() {
    final at = _cursors.removeLast();
    final open = entries[at.open] as _Open;
    open.bounds = _Cursor.union(at.bounds, open.extra);
    open.end = entries.length;
    entries.add(const _Close());
    _cursors.last.include(open.bounds);
  }

  // Adds [layer] as a child of [at]; false when it is a container whose
  // children are not walked.
  bool _visit(Layer layer, _Cursor at) {
    final transform = at.transform;
    final clip = at.clip;
    final state = at.state;
    final filtered = at.filtered;

    Rect clipped(Rect local) {
      final bounds = MatrixUtils.transformRect(transform, local);
      return clip == null ? bounds : clip.intersect(bounds);
    }

    Rect reaching(Rect local) => filtered ? _everywhere : clipped(local);

    // Transforms are never changed in place, so a layer that does not
    // shift shares its parent's.
    Matrix4 shifted(Offset offset) {
      if (offset == Offset.zero) return transform;
      final next = transform.clone();
      next.translateByDouble(offset.dx, offset.dy, 0, 1);
      return next;
    }

    void push(
      ContainerLayer layer,
      _Open open, {
      Matrix4? next,
      Rect? nextClip,
      bool keepClip = true,
      List<Object?>? nextState,
      bool nextFiltered = false,
    }) => _push(
      layer,
      open,
      next ?? transform,
      keepClip ? clip : nextClip,
      nextState ?? state,
      filtered: filtered || nextFiltered,
    );

    _Open clipping(
      Rect bounds,
      Clip behavior,
      void Function(Canvas c, {required bool antiAlias}) clipTo,
    ) => _Open((c) {
      c.save();
      clipTo(c, antiAlias: behavior != Clip.hardEdge);
      if (behavior != Clip.antiAliasWithSaveLayer) return 1;
      c.saveLayer(bounds, Paint());
      return 2;
    }, layered: behavior == Clip.antiAliasWithSaveLayer);

    switch (layer) {
      case UnderlayPictureLayer():
        final bounds = reaching(layer.canvasBounds);
        _add(at, _Glass(layer, transform, clip, state, bounds), bounds);
      case PictureLayer(:final picture?):
        final bounds = reaching(layer.canvasBounds);
        _add(
          at,
          _Leaf(
            picture,
            transform,
            clip,
            state,
            bounds,
            glass: layer is GlassPictureLayer,
          ),
          bounds,
        );
      case PictureLayer():
        break;
      case TextureLayer(:final rect) || PlatformViewLayer(:final rect):
        final bounds = reaching(rect);
        _add(at, _Block(layer, bounds), bounds);
      case OpacitySeedLayer():
        final reads = filtered ? _everywhere : clip ?? _everywhere;
        push(layer, _Seed(layer, reads));
      case BackdropFilterLayer():
        final reads = filtered ? _everywhere : clip ?? _everywhere;
        _add(at, _Block(layer, reads), reads);
        return false;
      case SeededBackdropPassLayer():
        push(layer, _Pass(layer, transform, clip, filtered: filtered));
      case LiquidGlassBackdropFilterLayer(clip: final rect, :final reach):
        push(
          layer,
          _Served(
            layer,
            transform,
            clip,
            state,
            filtered ? _everywhere : clipped(rect.inflate(reach)),
            filtered ? _everywhere : clipped(rect),
          ),
        );
      case TransformLayer(:final offset):
        final effective = Matrix4.translationValues(offset.dx, offset.dy, 0);
        if (layer.transform case final matrix?) effective.multiply(matrix);
        push(
          layer,
          _Open((c) {
            c.save();
            c.transform(effective.storage);
            return 1;
          }),
          next: transform.multiplied(effective),
        );
      // Shown nowhere: its addToScene adds nothing.
      case FollowerLayer(:final link, :final showWhenUnlinked)
          when link.leader == null && showWhenUnlinked != true:
        return false;
      case FollowerLayer():
        final effective = followerTransformNow(layer);
        push(
          layer,
          _Open((c) {
            c.save();
            c.transform(effective.storage);
            return 1;
          }),
          next: transform.multiplied(effective),
        );
      // Transparent: it shows nothing, though drawing it would still pay
      // for its layers and filters.
      case OpacityLayer(alpha: 0):
        return false;
      case OpacityLayer(:final offset):
        final alpha = layer.alpha ?? 255;
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            if (alpha == 255) return 1;
            c.saveLayer(null, _Prefix._alpha(alpha));
            return 2;
          }, layered: alpha != 255),
          next: shifted(offset),
          nextState: [...state, alpha],
        );
      case ImageFilterLayer(:final imageFilter?, :final offset):
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            c.saveLayer(_drawnBounds(layer), _Prefix._filtering(imageFilter));
            return 2;
          }, layered: true),
          next: shifted(offset),
          keepClip: false,
          nextState: [...state, imageFilter],
          nextFiltered: true,
        );
      case OffsetLayer(:final offset)
          when layer.runtimeType == OffsetLayer ||
              layer is GeometryTransformTrackingLayer:
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            return 1;
          }),
          next: shifted(offset),
        );
      case ColorFilterLayer(:final colorFilter?):
        push(
          layer,
          _Open((c) {
            final paint = Paint();
            paint.colorFilter = colorFilter;
            c.saveLayer(null, paint);
            return 1;
          }, layered: true),
          nextState: [...state, colorFilter],
        );
      case ShaderMaskLayer(
        :final shader?,
        :final maskRect?,
        :final blendMode?,
      ):
        // A FragmentShader keeps its identity while its uniforms change.
        final token = shader is ui.FragmentShader ? Object() : shader;
        final open = _Open(
          (c) {
            c.saveLayer(null, Paint());
            return 1;
          },
          mask: (shader, maskRect, blendMode),
          layered: true,
        );
        open.extra = reaching(maskRect);
        push(
          layer,
          open,
          nextState: [...state, token, maskRect, blendMode],
        );
      case ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        push(
          layer,
          clipping(
            clipRect,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipRect(clipRect, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(clipRect),
          nextState: [...state, clipRect, clipBehavior],
        );
      case ClipRRectLayer(:final clipRRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        push(
          layer,
          clipping(
            clipRRect.outerRect,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipRRect(clipRRect, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(clipRRect.outerRect),
          nextState: [...state, clipRRect, clipBehavior],
        );
      case ClipRSuperellipseLayer(
            :final clipRSuperellipse?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        push(
          layer,
          clipping(
            clipRSuperellipse.outerRect,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipRSuperellipse(clipRSuperellipse, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(clipRSuperellipse.outerRect),
          nextState: [...state, clipRSuperellipse, clipBehavior],
        );
      case ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none:
        final bounds = clipPath.getBounds();
        push(
          layer,
          clipping(
            bounds,
            clipBehavior,
            (c, {required antiAlias}) =>
                c.clipPath(clipPath, doAntiAlias: antiAlias),
          ),
          keepClip: false,
          nextClip: clipped(bounds),
          nextState: [...state, clipPath, clipBehavior],
        );
      case NativeClipLayer(
            enabled: true,
            :final geometry?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        final (bounds, clipTo) = switch (geometry) {
          final Rect rect => (
            rect,
            (Canvas c, {required bool antiAlias}) =>
                c.clipRect(rect, doAntiAlias: antiAlias),
          ),
          final RRect rect => (
            rect.outerRect,
            (Canvas c, {required bool antiAlias}) =>
                c.clipRRect(rect, doAntiAlias: antiAlias),
          ),
          final RSuperellipse rect => (
            rect.outerRect,
            (Canvas c, {required bool antiAlias}) =>
                c.clipRSuperellipse(rect, doAntiAlias: antiAlias),
          ),
          final Path path => (
            path.getBounds(),
            (Canvas c, {required bool antiAlias}) =>
                c.clipPath(path, doAntiAlias: antiAlias),
          ),
          _ => (Rect.largest, null),
        };
        push(
          layer,
          clipTo == null
              ? _Undrawable(layer)
              : clipping(bounds, clipBehavior, clipTo),
          keepClip: false,
          nextClip: clipped(bounds),
          nextState: [...state, geometry, clipBehavior],
        );
      case LeaderLayer(:final offset):
        push(
          layer,
          _Open((c) {
            c.save();
            c.translate(offset.dx, offset.dy);
            return 1;
          }),
          next: shifted(offset),
        );
      case ClipRectLayer() ||
          ClipRRectLayer() ||
          ClipRSuperellipseLayer() ||
          ClipPathLayer() ||
          NativeClipLayer() ||
          AnnotatedRegionLayer():
        push(layer as ContainerLayer, _Open.plain());
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        push(layer, _Open.plain());
      case ContainerLayer() when LiquidGlassUnderlay.effectsOf(layer) != null:
        final effects = LiquidGlassUnderlay.effectsOf(layer)!;
        if (effects.alpha == 0) return false;
        final next = transform.multiplied(effects.transform);
        var nextClip = clip;
        final effectState = <Object?>[];
        final rounded = effects.clip;
        if (rounded != null) {
          final bounds = MatrixUtils.transformRect(next, rounded.outerRect);
          nextClip = clip == null ? bounds : clip.intersect(bounds);
          effectState.add(rounded);
        }
        final alpha = effects.alpha;
        if (alpha != null) effectState.add(alpha);
        final blur = effects.blur;
        if (blur > 0) {
          effectState.add(blur);
          nextClip = null;
        }
        push(
          layer,
          _Open((c) {
            c.save();
            c.transform(effects.transform.storage);
            if (rounded != null) c.clipRRect(rounded);
            var saves = 1;
            if (alpha != null) {
              c.saveLayer(null, _Prefix._alpha(alpha));
              saves++;
            }
            if (blur > 0) {
              c.saveLayer(
                _drawnBounds(layer),
                _Prefix._filtering(
                  ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ),
              );
              saves++;
            }
            return saves;
          }, layered: alpha != null || blur > 0),
          next: next,
          keepClip: false,
          nextClip: nextClip,
          nextState: [...state, ...effectState],
          nextFiltered: blur > 0,
        );
      default:
        _add(
          at,
          _Unknown(layer, transform, clip, filtered: filtered),
          _everywhere,
        );
        return layer is! ContainerLayer;
    }
    return true;
  }

  // Whether nothing is painted in [band] between entries [from] and [to] but
  // the glass of an island, what it paints with its glass ([owned]) and
  // glass beside [body], and nothing there reads the backdrop: then the copy
  // of what lies before the island's first glass holds what lies under the
  // glass at [to]. [starts] are where the island's glass begins.
  bool onlyIslandBetween(
    int from,
    int to,
    Rect band,
    Rect body, {
    required Set<int> starts,
    required Set<Layer> owned,
  }) {
    for (var i = from; i < to && i < entries.length; i++) {
      final entry = entries[i];
      if (entry is _Open &&
          entry.end > i &&
          (starts.contains(i) ||
              entry is _Seed && owned.contains(entry.layer) ||
              !_meets(entry.bounds, band))) {
        i = entry.end;
        continue;
      }
      switch (entry) {
        case _Leaf(glass: true, :final bounds) || _Glass(:final bounds)
            when !_meets(bounds, body):
          break;
        case _Leaf(:final bounds) ||
            _Glass(:final bounds) ||
            _Block(:final bounds):
          if (_meets(bounds, band)) return false;
        case _Served(:final reads):
          if (_meets(reads, band)) return false;
        case _Seed(:final layer, :final reads) when layer.seeded:
          if (_meets(reads, band)) return false;
        case _Pass(
          layer: final layer && SeededBackdropPassLayer(:final scenePass?),
        ):
          if (!layer.hidden && _meets(entry.reads(scenePass.rect), band)) {
            return false;
          }
        case _Unknown() || _Undrawable():
          return false;
        case _Open() || _Close():
          break;
      }
    }
    return true;
  }

  // Replays the entries before [limit] that reach [prefix]'s band onto its
  // canvas, if it has one, and signs them.
  void replay(_Prefix prefix, int limit) {
    final band = prefix.band;
    final drawing = prefix.canvas != null;
    final out = prefix.out;
    final open = <(int, _Open)>[];
    var i = 0;
    var through = true;

    void sign(
      ui.Picture picture,
      Matrix4 transform,
      Rect? clip,
      List<Object?> state,
    ) {
      out.add(picture);
      out.add(transform);
      out.add(clip);
      out.addAll(state);
      out.add(#leaf);
      prefix.canvas?.drawPicture(picture);
    }

    // Glass over a copy not drawn yet: the copy draws it as its filter over
    // what the copy holds before it, which a group that draws its children
    // in a layer of their own would not hold. A signature that holds it
    // matches none.
    bool fold(Layer layer, UnderlayFold add, Matrix4 transform, Rect? clip) {
      out.add(Object());
      if (open.any((group) => group.$2.layered)) {
        prefix.blocked = true;
        prefix.blocker ??= layer;
        return false;
      }
      prefix.fold((add: add, transform: transform, clip: clip), open);
      return true;
    }

    // Steps past a group, or ends the replay when the stop lies inside it.
    void skip(_Open group) {
      if (group.end < 0 || group.end >= limit) {
        through = false;
      } else {
        i = group.end + 1;
      }
    }

    loop:
    while (i < limit) {
      final entry = entries[i];
      switch (entry) {
        case _Leaf(glass: true) when prefix.beside(entry.bounds):
          break;
        case _Glass() when prefix.beside(entry.bounds):
          break;
        case _Leaf(:final picture, :final transform, :final clip, :final state):
          if (_meets(entry.bounds, band)) {
            sign(picture, transform, clip, state);
          }
        case _Glass(:final layer, :final transform, :final clip, :final state):
          if (_meets(entry.bounds, band)) {
            if (layer.picture == null) {
              if (layer.pending) {
                if (!fold(layer, layer.fold, transform, clip)) break loop;
                i++;
                continue loop;
              }
              layer.resolve();
            }
            if (layer.picture case final picture?) {
              sign(picture, transform, clip, state);
            }
          }
        case _Block(:final layer, :final bounds):
          if (_meets(bounds, band)) {
            prefix.blocked = true;
            prefix.blocker ??= layer;
            break loop;
          }
        case _Unknown(:final layer, :final transform, :final clip):
          if (prefix._mayReach(
            layer,
            transform,
            clip,
            filtered: entry.filtered,
          )) {
            prefix.blocked = true;
            prefix.blocker ??= layer;
            break loop;
          }
        case _Close():
          final (saves, group) = open.removeLast();
          if (prefix.canvas case final c?) group.finish(c, saves);
        case _Open():
          if (entry.end >= 0 &&
              entry.end < limit &&
              !_meets(entry.bounds, band)) {
            i = entry.end + 1;
            continue loop;
          }
          switch (entry) {
            case _Seed(:final layer, :final reads) when layer.seeded:
              if (_meets(reads, band)) {
                prefix.blocked = true;
                prefix.blocker ??= layer;
                break loop;
              }
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Pass(:final layer) when layer.hidden:
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Pass(
              layer: final layer && SeededBackdropPassLayer(:final scenePass?),
            ):
              if (_meets(entry.reads(scenePass.rect), band)) {
                prefix.blocked = true;
                prefix.blocker ??= layer;
                break loop;
              }
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Served(:final layer) when !layer.serves:
              if (_meets(entry.reads, band)) {
                prefix.blocked = true;
                prefix.blocker ??= layer;
                break loop;
              }
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Served(:final layer, :final transform, :final clip):
              if (!kReleaseMode) {
                _count(
                  BackdropUnderlay.debugEdgeSigns,
                  _meets(entry.output, band) ? 'output' : 'margin',
                );
              }
              if (layer.pending) {
                if (!fold(layer, layer.addFold, transform, clip)) break loop;
              } else {
                sign(layer.servedPicture!, transform, clip, entry.state);
              }
            case _Undrawable(:final layer) when drawing:
              prefix.blocked = true;
              prefix.blocker ??= layer;
              break loop;
            default:
              break;
          }
          open.add((
            prefix.canvas == null ? 0 : entry.apply(prefix.canvas!),
            entry,
          ));
      }
      i++;
    }
    prefix.reached = through && !prefix.blocked && i >= limit;
    if (prefix.canvas case final c?) {
      for (final (saves, group) in open.reversed) {
        group.finish(c, saves);
      }
    }
  }
}

const _everywhere = Rect.largest;

// Content clipped away reaches no band, even where its empty rect lies
// across one.
bool _meets(Rect bounds, Rect band) => !bounds.isEmpty && bounds.overlaps(band);

final class _Cursor {
  _Cursor(
    this.layer,
    this.next,
    this.transform,
    this.clip,
    this.state, {
    required this.filtered,
    required this.open,
  });

  final ContainerLayer? layer;
  Layer? next;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final bool filtered;
  final int open;
  Rect bounds = Rect.zero;

  void include(Rect rect) => bounds = union(bounds, rect);

  static Rect union(Rect a, Rect b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return a.expandToInclude(b);
  }
}

// What [layer]'s children draw, in its coordinates, or null where one may
// draw anywhere; it bounds a filtered layer in a copy. Unbounded,
// Impeller sizes a filtered layer to the clip, the whole atlas, where the
// scene sizes it to its children, so a blurred title would blur every copy.
// The bounds are the content's; Impeller adds the filter's reach.
Rect? _drawnBounds(ContainerLayer layer) {
  var bounds = Rect.zero;
  for (var child = layer.firstChild; child != null; child = child.nextSibling) {
    final effects = LiquidGlassUnderlay.effectsOf(child);
    final Rect? drawn;
    if (child is PictureLayer) {
      drawn = child.canvasBounds;
    } else if (child is! ContainerLayer) {
      drawn = null;
    } else if (effects != null) {
      final blurred = _drawnBounds(child)?.inflate(3 * effects.blur);
      final clipped = switch (effects.clip) {
        final clip? => blurred?.intersect(clip.outerRect),
        null => blurred,
      };
      drawn = clipped == null
          ? null
          : MatrixUtils.transformRect(effects.transform, clipped);
    } else {
      final inner = _drawnBounds(child);
      drawn = inner == null
          ? null
          : switch (child) {
              TransformLayer(:final offset, :final transform) =>
                MatrixUtils.transformRect(
                  transform ?? Matrix4.identity(),
                  inner,
                ).shift(offset),
              OpacityLayer(:final offset) => inner.shift(offset),
              ClipRectLayer(:final clipRect?) => inner.intersect(clipRect),
              OffsetLayer(:final offset)
                  when child.runtimeType == OffsetLayer ||
                      child is GeometryTransformTrackingLayer =>
                inner.shift(offset),
              _ when child.runtimeType == ContainerLayer => inner,
              _ => null,
            };
    }
    if (drawn == null) return null;
    bounds = _Cursor.union(bounds, drawn);
  }
  return bounds;
}

sealed class _Entry {
  const _Entry();
}

/// Adds glass to a scene as its live filter over what the scene draws
/// before it, in the glass's own coordinates: the scene holds the copy of
/// [rect] of the screen (logical pixels), one pixel of it per device pixel
/// of the screen, and a filter's fragment lies [offset] past the copy's
/// pixel.
@internal
typedef UnderlayFold = void Function(
  ui.SceneBuilder builder,
  Rect rect,
  Offset offset,
);

// Glass a copy draws as its filter: [add] in [transform] from the glass's
// coordinates to the screen's, inside [clip] of the screen.
typedef _Fold = ({UnderlayFold add, Matrix4 transform, Rect? clip});

final class _Leaf extends _Entry {
  _Leaf(
    this.picture,
    this.transform,
    this.clip,
    this.state,
    this.bounds, {
    this.glass = false,
  });

  // Glass whose copy is drawn.
  final bool glass;

  final ui.Picture picture;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect bounds;
}

// Glass over a copy, whose picture is recorded once its copy is drawn.
final class _Glass extends _Entry {
  _Glass(this.layer, this.transform, this.clip, this.state, this.bounds);

  final UnderlayPictureLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect bounds;
}

// What a copy cannot draw: a copy whose band it reaches fails.
final class _Block extends _Entry {
  _Block(this.layer, this.bounds);

  final Layer layer;
  final Rect bounds;
}

// A layer of a type the copy does not know.
final class _Unknown extends _Entry {
  _Unknown(this.layer, this.transform, this.clip, {required this.filtered});

  final Layer layer;
  final Matrix4 transform;
  final Rect? clip;
  final bool filtered;
}

final class _Close extends _Entry {
  const _Close();
}

// A container: what it applies to the canvas around its children and how
// many saves that takes, and the extent of what it draws once its children
// are walked.
class _Open extends _Entry {
  _Open(this.apply, {this.mask, this.layered = false});

  _Open.plain() : apply = _none, mask = null, layered = false;

  static int _none(Canvas c) => 0;

  final int Function(Canvas c) apply;
  final (Shader, Rect, BlendMode)? mask;
  // Whether it draws its children in a layer of their own.
  final bool layered;
  Rect extra = Rect.zero;
  Rect bounds = _everywhere;
  int end = -1;

  void finish(Canvas c, int saves) {
    if (mask case (final shader, final rect, final blendMode)) {
      // The engine draws a shader mask over what it masks, in a layer.
      final paint = Paint();
      paint.shader = shader;
      paint.blendMode = blendMode;
      c.translate(rect.left, rect.top);
      c.drawRect(Offset.zero & rect.size, paint);
    }
    for (var n = 0; n < saves; n++) {
      c.restore();
    }
  }
}

// A clip the copy cannot draw: a copy drawn under it fails.
final class _Undrawable extends _Open {
  _Undrawable(this.layer) : super(_Open._none);

  final Layer layer;
}

// An opacity pass that glass seeds with its backdrop while it reads it.
final class _Seed extends _Open {
  _Seed(this.layer, this.reads) : super(_Open._none) {
    extra = reads;
  }

  final OpacitySeedLayer layer;
  final Rect reads;
}

// A seeded backdrop pass, hidden or read as glass composites.
final class _Pass extends _Open {
  _Pass(this.layer, this.transform, this.clip, {required this.filtered})
    : super(_Open._none) {
    extra = _everywhere;
  }

  final SeededBackdropPassLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final bool filtered;

  Rect reads(Rect local) {
    if (filtered) return _everywhere;
    final bounds = MatrixUtils.transformRect(transform, local);
    return clip == null ? bounds : clip!.intersect(bounds);
  }
}

// A filter that draws its copy once it composites, or reads its backdrop.
final class _Served extends _Open {
  _Served(
    this.layer,
    this.transform,
    this.clip,
    this.state,
    this.reads,
    this.output,
  ) : super(_Open._none) {
    extra = reads;
  }

  final LiquidGlassBackdropFilterLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect reads;
  final Rect output;
}

/// A copy that [BackdropUnderlay.serve] hands over: [rect] of the screen, in
/// logical pixels, at [offset] (the image's pixels) in [image], at
/// [pixelRatio].
///
/// A copy recorded this frame is drawn by [UnderlayFrame.drawPending] with
/// the frame's other copies; reading [image] or [offset] earlier draws the
/// pending copies then.
@internal
final class UnderlayCopy {
  const UnderlayCopy._(this._underlay, this.rect, this.pixelRatio);

  final BackdropUnderlay _underlay;

  /// The screen rect the copy holds, in logical pixels.
  final Rect rect;

  /// The copy's pixels per logical pixel along each side.
  final double pixelRatio;

  /// Whether [image] is drawn already.
  bool get ready => _underlay._image != null;

  /// Whether the copy is drawn with the frame's copies, not yet drawn.
  bool get pending => !ready && _underlay._island?.tile != null;

  /// The image that holds the copy, shared with other copies of the frame.
  ui.Image get image {
    if (!ready) _underlay._island?.tile?.atlas?.flush('read');
    return _underlay._image!;
  }

  /// Where [rect]'s top left corner sits in [image], in its pixels.
  Offset get offset {
    if (!ready) _underlay._island?.tile?.atlas?.flush('read');
    return _underlay._offset;
  }
}

/// A picture of glass, drawn over its copy.
@internal
class GlassPictureLayer extends PictureLayer {
  /// A layer of glass painting inside [canvasBounds].
  GlassPictureLayer(super.canvasBounds);
}

/// A picture of glass over a copy that is recorded when the scene is added,
/// or earlier when another copy holds it, so that the copies of a frame are
/// drawn together.
@internal
class UnderlayPictureLayer extends GlassPictureLayer {
  /// A layer whose [record] records its picture once [copy] is drawn, and
  /// that [fold] draws into the frame's other copies until then.
  UnderlayPictureLayer(super.canvasBounds, this.copy, this.record, this.fold);

  /// The copy the picture is drawn over.
  final UnderlayCopy copy;

  /// Records the picture.
  final ui.Picture Function() record;

  /// Adds the glass to a copy drawn with [copy] that holds it.
  final UnderlayFold fold;

  /// Whether [copy] is drawn with the frame's copies, not yet drawn.
  bool get pending => copy.pending;

  /// Records the picture now, if it is not yet.
  void resolve() {
    if (picture == null && attached) picture = record();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    resolve();
    if (picture != null) super.addToScene(builder);
  }
}

class _Tile {
  _Tile(this.island)
    : width = (island.rect.width * island.pixelRatio).round(),
      height = (island.rect.height * island.pixelRatio).round();

  final _Island island;

  // The atlas that draws it.
  _Atlas? atlas;

  ui.Picture? content;
  // What the copy draws before each glass it folds in, drawn under
  // [content].
  List<(ui.Picture, _Fold)> pieces = const [];
  ui.Picture? Function()? redraw;
  final int width;
  final int height;
  Offset offset = Offset.zero;

  Rect get rect => island.rect;
  double get pixelRatio => island.pixelRatio;
  ui.ImageFilter? get filter => island.filter;
  (double, double)? get blur => island.blur;
  bool get filtered => island.filter != null || island.blur != null;

  // Whether the copy is filtered in the atlas's layer of copies rather than
  // as a backdrop of its own.
  bool get layered => switch (blur) {
    (final x, final y) => max(x, y) * pixelRatio <= _Atlas._maxImageBlurSigma,
    null => false,
  };
  Object? get filterKey => island.filterKey;
  Rect? get filterClip => island.filterClip;
  BlendMode get filterBlendMode => island.filterBlendMode;

  Rect get bounds => offset & Size(width.toDouble(), height.toDouble());
}

// The copies recorded in a frame, drawn into one image: every image drawn
// on its own costs the raster thread a render pass, a texture and a command
// buffer, and the GPU driver a submission.
final class _Atlas {
  // Gap between copies, in device pixels: sampling between pixels at a
  // copy's edge reads no neighbour.
  static const int _gap = 2;
  static const int _rowWidth = 2048;
  static const int _maxHeight = 4096;

  // Impeller downsamples an image filter's blur on a grid of its own and a
  // backdrop filter's on the target's: past this sigma in a copy's pixels
  // the two part by up to 15 levels at some sizes (host parity), so a [blur]
  // copy blurred more is blurred as a backdrop filter.
  static const double _maxImageBlurSigma = 14;

  static int drawn = 0;

  // The copies' blurs, held across frames: dart:ui converts each new filter
  // to a native one again. Glass asks for few distinct blurs, so the held
  // ones are dropped all at once when that grows past a handful.
  static final _blurs = <(double, double), ui.ImageFilter>{};

  static ui.ImageFilter _blur(double sigmaX, double sigmaY) {
    final key = (sigmaX, sigmaY);
    if (_blurs[key] case final held?) return held;
    if (_blurs.length >= 16) _blurs.clear();
    return _blurs[key] = ui.ImageFilter.blur(
      sigmaX: sigmaX,
      sigmaY: sigmaY,
      tileMode: glassBlurTileMode,
    );
  }

  final _pending = <_Tile>[];
  bool _flushing = false;

  void add(_Tile tile) {
    tile.atlas = this;
    _pending.add(tile);
  }

  void cancel(_Tile tile) {
    if (!_pending.remove(tile)) return;
    tile.content?.dispose();
    for (final (picture, _) in tile.pieces) {
      picture.dispose();
    }
  }

  // Draws the pending copies; [why] names what asked, for diagnostics.
  void flush(String why) {
    if (_flushing || _pending.isEmpty) return;
    _count(BackdropUnderlay.debugFlushes, why);
    _flushing = true;
    try {
      final batch = [..._pending];
      _pending.clear();
      for (final tile in batch) {
        if (tile.content != null) continue;
        final picture = tile.redraw?.call();
        assert(picture != null, 'A copy recorded again is never blocked.');
        tile.content = picture ?? ui.PictureRecorder().endRecording();
      }
      // Copies filtered in the layer of copies lie side by side, to share
      // it.
      final runs = <Object?, List<_Tile>>{};
      for (final tile in batch) {
        runs
            .putIfAbsent(
              !tile.filtered
                  ? null
                  : (tile.filterKey, tile.pixelRatio, tile.layered),
              () => [],
            )
            .add(tile);
      }
      _pack(runs.values.toList());
    } finally {
      _flushing = false;
    }
  }

  // Every run starts a row of its own, so that the rect around a run's
  // copies holds no other copy.
  static void _pack(List<List<_Tile>> runs) {
    final batch = [for (final run in runs) ...run];
    final starts = Set<_Tile>.identity();
    for (final run in runs) {
      starts.add(run.first);
    }
    var start = 0;
    while (start < batch.length) {
      final tiles = <_Tile>[];
      var x = 0;
      var y = 0;
      var row = 0;
      var width = 0;
      for (final tile in batch.skip(start)) {
        final limit = tile.width > _rowWidth ? tile.width : _rowWidth;
        if (x > 0 && (x + tile.width > limit || starts.contains(tile))) {
          x = 0;
          y += row + _gap;
          row = 0;
        }
        if (tiles.isNotEmpty && y + tile.height > _maxHeight) break;
        tile.offset = Offset(x.toDouble(), y.toDouble());
        tiles.add(tile);
        x += tile.width + _gap;
        if (x - _gap > width) width = x - _gap;
        if (tile.height > row) row = tile.height;
      }
      start += tiles.length;
      _draw(tiles, width, y + row);
    }
  }

  // From the screen's logical pixels to [tile]'s place in the image.
  static Matrix4 _toAtlas(_Tile tile) {
    final pixels = tile.pixelRatio;
    final toAtlas = Matrix4.translationValues(
      tile.offset.dx - tile.rect.left * pixels,
      tile.offset.dy - tile.rect.top * pixels,
      0,
    );
    toAtlas.scaleByDouble(pixels, pixels, 1, 1);
    return toAtlas;
  }

  // Adds [tile]'s copy, each glass it folds in over what the copy draws
  // before it. [origin] is where the copy lies in the pass the folds draw
  // into: its place in the image, or zero in a layer of its own. NEAR:
  // outside such a layer the glass's filter reads past the copy's edge what
  // lies beside it in the image, as a copy's blur does.
  static void _add(ui.SceneBuilder b, _Tile tile, {required Offset origin}) {
    for (final (picture, fold) in tile.pieces) {
      b.addPicture(tile.offset, picture);
      BackdropUnderlay.debugFolds++;
      b.pushClipRect(tile.bounds, clipBehavior: Clip.hardEdge);
      b.pushTransform(_toAtlas(tile).storage);
      if (fold.clip case final clip?) {
        b.pushClipRect(clip, clipBehavior: Clip.hardEdge);
      }
      b.pushTransform(fold.transform.storage);
      fold.add(b, tile.rect, origin);
      b.pop();
      if (fold.clip != null) b.pop();
      b.pop();
      b.pop();
    }
    b.addPicture(tile.offset, tile.content!);
  }

  static void _draw(List<_Tile> tiles, int width, int height) {
    drawn++;
    // A copy's picture is clipped to the copy when it is recorded.
    void place(Canvas canvas, _Tile tile) {
      canvas.save();
      canvas.translate(tile.offset.dx, tile.offset.dy);
      canvas.drawPicture(tile.content!);
      canvas.restore();
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final isolated = <_Tile>[];
    final folding = <_Tile>[];
    // Copies under one blur share one filtered layer: the filter reads the
    // copies alone, so no backdrop is copied for it, and the layer is
    // clipped to the rows of the copies' run, which hold no other copy.
    final layered = <(Object?, double), List<_Tile>>{};
    for (final tile in tiles) {
      if (!tile.filtered) {
        if (tile.pieces.isEmpty) {
          place(canvas, tile);
        } else {
          folding.add(tile);
        }
      } else if (tile.layered) {
        layered
            .putIfAbsent((tile.filterKey, tile.pixelRatio), () => [])
            .add(tile);
      } else {
        isolated.add(tile);
      }
    }
    final content = recorder.endRecording();
    final ui.Image image;
    if (isolated.isEmpty && layered.isEmpty && folding.isEmpty) {
      image = content.toImageSync(width, height);
    } else {
      final b = ui.SceneBuilder();
      b.addPicture(Offset.zero, content);
      // A copy's filter, folded or its own, reads what lies under it as a
      // backdrop filter reads the screen. In a layer around its copy it
      // reads that layer alone, which a pass split at the filter loads and
      // stores; drawn straight into the atlas, Impeller blurs the whole
      // atlas for it. A fragment in the layer lies in the copy's pixels.
      for (final tile in folding) {
        b.pushClipRect(tile.bounds, clipBehavior: Clip.antiAliasWithSaveLayer);
        _add(b, tile, origin: Offset.zero);
        b.pop();
      }
      for (final group in layered.values) {
        BackdropUnderlay.debugBlurLayers++;
        final first = group.first;
        var bounds = first.bounds;
        for (final tile in group.skip(1)) {
          bounds = bounds.expandToInclude(tile.bounds);
        }
        b.pushClipRect(bounds, clipBehavior: Clip.hardEdge);
        // Impeller takes an image filter's sigmas in the pixels it draws
        // into, whatever the canvas scale: here the copies' own.
        b.pushImageFilter(
          _blur(
            first.blur!.$1 * first.pixelRatio,
            first.blur!.$2 * first.pixelRatio,
          ),
        );
        for (final tile in group) {
          _add(b, tile, origin: tile.offset);
        }
        b.pop();
        b.pop();
      }
      // A copy's own filter stands under the view's scale, as the backdrop
      // filter it replaces does.
      for (final tile in isolated) {
        final filter = tile.filter ?? _blur(tile.blur!.$1, tile.blur!.$2);
        b.pushClipRect(tile.bounds, clipBehavior: Clip.antiAliasWithSaveLayer);
        _add(b, tile, origin: Offset.zero);
        b.pushTransform(_toAtlas(tile).storage);
        b.pushClipRect(
          tile.filterClip?.intersect(tile.rect) ?? tile.rect,
          clipBehavior: Clip.hardEdge,
        );
        b.pushBackdropFilter(filter, blendMode: tile.filterBlendMode);
        b.pop();
        b.pop();
        b.pop();
        b.pop();
      }
      final scene = b.build();
      image = scene.toImageSync(width, height);
      scene.dispose();
    }
    for (final tile in tiles) {
      tile.content!.dispose();
      for (final (picture, _) in tile.pieces) {
        picture.dispose();
      }
    }
    content.dispose();
    for (final tile in tiles) {
      final island = tile.island;
      island.tile = null;
      final size = island.members.length;
      if (size > 1) _count(BackdropUnderlay.debugIslands, size);
      for (final (i, member) in island.members.indexed) {
        final shift =
            (island.rects[i].topLeft - tile.rect.topLeft) * tile.pixelRatio;
        member._image = image.clone();
        member._offset =
            tile.offset +
            Offset(shift.dx.roundToDouble(), shift.dy.roundToDouble());
      }
    }
    image.dispose();
  }
}

// The debug counters count in debug and profile builds, for tests and the
// benches; a release build pays nothing for them.
void _count<K>(Map<K, int> counts, K key) {
  if (kReleaseMode) return;
  counts[key] = (counts[key] ?? 0) + 1;
}
