// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_filter_layer.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart'
    show debugFrostsInPlace, frostFilterOf;
import 'package:liquid_glass_renderer/src/composer/backdrop_seed.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composer.dart';
import 'package:liquid_glass_renderer/src/composer/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/internal/follower_transform.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_clip.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_render_object_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_underlay.dart';

part 'copy_read.dart';
part 'filter_group.dart';

/// A copy of what is painted under one backdrop effect, optionally run
/// through the effect's filter, that the effect draws from instead of
/// reading the backdrop.
///
/// Glass that paints over copies spares the frame the offscreen render a
/// backdrop read costs (see [LiquidGlassBackdropFilterLayer]). The copy is
/// drawn from the layer tree itself while the frame composites: everything
/// painted before the layer, in a band around what its glass samples. A copy
/// without a filter is drawn in the frame itself ([serveInFrame]). A
/// filtered one is replayed into one image with every other copy the frame
/// draws, which the frame renders before the glass; it serves later frames
/// while the layers painted before the glass in that band are the same ones
/// it was drawn from (the same pictures under the same transforms, clips,
/// opacities and filters), and a frame in which they changed draws a new
/// one.
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
      !runningUnderFlutterTest;

  /// Whether glass layers keep copies of what lies under them: wherever
  /// Impeller renders, not under `flutter test` unless a test turns it on.
  static bool get enabled => debugEnabledOverride ?? _defaultEnabled;

  // Room past the band a copy holds, in logical pixels, so glass that moves
  // or grows a little stays inside it.
  static const double _margin = 12;
  static const double _roomMost = 400;

  ui.Image? _image;
  // The frost [_image] holds, in logical pixels.
  double _heldFrost = 0;
  Offset _offset = Offset.zero;
  // The screen rect the copy holds.
  Rect _rect = Rect.zero;
  // What the copy was drawn from, with the copies drawn with it, and what
  // this copy asked for when it joined.
  _Island? _island;
  _Ask? _joined;
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
  static int debugImagesDrawn = 0;

  /// Whether a copy smaller than the screen draws its text where it lies
  /// rather than on the copy's pixels, for an A/B run.
  @visibleForTesting
  static bool debugPlaceText = true;

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

  /// Whether a copy asked for without a filter or blur is drawn in the frame
  /// itself (see [serveInFrame]) rather than into an image. Building with
  /// `--dart-define=LIQUID_GLASS_IN_FRAME=false` draws every copy into an
  /// image.
  @visibleForTesting
  static bool debugInFrame = const bool.fromEnvironment(
    'LIQUID_GLASS_IN_FRAME',
    defaultValue: true,
  );

  /// How many islands were recorded into images, by the type of the layer
  /// that leads each and how its copy is filtered: `blur`, `filter` or
  /// `plain`.
  @visibleForTesting
  static final debugImageAsks = <String, int>{};

  /// Whether a copy drawn in the frame without glass in it is added to the
  /// scene as the layers it holds rather than recorded into a picture.
  static bool debugInScene = true;

  /// Whether glass of equal looks shares one filter ([FilterGroup]).
  static bool debugGroups = true;

  /// Whether a scroll edge joins the filter of the glass over it.
  static bool debugBandGroups = true;

  /// Whether a copy of few pixels leaves glass out.
  static bool debugDropsGlass = true;

  /// Whether a copy for frosted glass leaves out a backdrop frost no wider
  /// than the glass's and frosts by what it left out: Gaussians add in
  /// variance, so the frost that lies under the glass stays in its frost.
  ///
  /// NEAR: where the band that frost covers ends under the glass, the rest of
  /// the glass frosts that much wider than what lies under it asks: a
  /// tab bar's 2.2 logical px against 2.7 over the scroll edge's 1.5. A frost
  /// that also changes the color loses that under the glass: a hard scroll
  /// edge's saturation of 1.25 and brightness of 0.03, on the Pixel 6a about
  /// 2 levels of 255 on average under a search button over photos, 14 at most.
  static bool debugDropsFrost = true;

  /// Whether the last [request] is served by [serveInFrame], not [serve].
  bool get servesInFrame => (_ask?.inFrame ?? false) && !_held;

  /// Whether a copy that drew the same in the frames before moves to an image,
  /// which holds until what lies under it changes: glass moving over a page
  /// that holds still then takes no offscreen pass. The frame that finds a
  /// change draws from a new copy, so the backdrop is never a frame late. On
  /// the Pixel 6a a menu opening takes 28 % fewer fragment cycles and 2.7 ms
  /// less on the raster thread, a tab bar drag 9 % and 1.3 ms
  /// (tool/audit/2026-11-05-one-pass/results.md).
  static bool debugPromotes = true;

  // What the copy drawn in the frame last drew.
  List<Object?>? _inFrameOut;

  // Whether what lies under the copy held still, so an image serves it.
  bool _stillUnder = false;

  // How many frames in a row the copy drawn in the frame drew the same.
  int _stillFrames = 0;

  // How many it takes for an image to serve it. An image that holds for a few
  // frames costs more than the copies it saves, and clears the text shadows
  // the frame keeps: one that did not hold long doubles it.
  int _stillNeeded = _stillFramesFirst;

  // How many frames the image has served since it was drawn.
  int _heldFrames = 0;

  static const int _stillFramesFirst = 2;
  static const int _stillFramesMost = 64;
  static const int _heldFramesLong = 30;

  // The room an image takes around glass that moves in it, in logical pixels:
  // glass that leaves it doubles it, so that a sheet on its way up asks for
  // few images and not one each frame.
  double _room = _margin;

  bool get _held => debugPromotes && _stillUnder;

  void _stirred() {
    _stillUnder = false;
    _stillFrames = 0;
    _inFrameOut = null;
    _stillNeeded = _heldFrames < _heldFramesLong
        ? min(_stillNeeded * 2, _stillFramesMost)
        : _stillFramesFirst;
    _heldFrames = 0;
  }

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
  /// Gaussian blur over the whole copy by these sigmas in logical pixels. Up
  /// to `_Atlas._maxImageBlurSigma` copy pixels the copy is blurred at its
  /// own pixels, in one image-filter layer with the frame's other copies
  /// under the same blur, without reading a backdrop. NEAR: past a copy's
  /// edge that blur reads what lies beside it in the shared layer rather than
  /// a mirror of the copy; a copy holds 3 sigma past what its glass samples,
  /// so that reaches the glass only as the tail of the blur. Glass stretched
  /// along the axes differs from reading the backdrop by up to 15 levels in
  /// a few hundred pixels on the Pixel 6a. A wider blur filters the copy as
  /// a backdrop filter in a layer of its own.
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
    double frost = 0,
    List<Rect>? parts,
    List<Rect>? bodies,
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
    _outOfSight = false;
    final view = anchor.owner;
    if (view is! RenderView) return;
    final screen = Offset.zero & view.size;
    final grid = CopyGrid._(devicePixelRatio, downscale);
    final ask = _Ask(
      frame: GlassComposer.planning(view),
      anchor: anchor,
      own: own,
      grid: grid,
      screen: screen,
      band: grid._snapOut(region).intersect(screen),
      filter: filter,
      blur: blur,
      filterClip: filterClip,
      filterBlendMode: filterBlendMode,
      body: body,
      frost: frost,
      parts: parts,
      bodies: bodies,
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
    _heldFrames++;
    _ask = null;
    _plan = null;
    if (ask == null) return null;
    if (ask.band.isEmpty) {
      _outOfSight = true;
      _count(debugMisses, 'off screen');
      return null;
    }
    final scan = _scanOf(ask);
    final limit = scan.reach(ask.anchor);
    if (plan?.serve(this, ask, scan, limit) case final copy?) return copy;
    return _islandOf([this], [ask], scan, limit)?.copy;
  }

  // Whether the last request lies off the screen or outside its clips.
  bool _outOfSight = false;

  /// Whether the glass of the last [request] lies off the screen or outside
  /// its clips, as far as it reads: [serve] and [serveInFrame] gave no copy
  /// because none of it shows, and it needs no backdrop either.
  bool get outOfSight => _outOfSight;

  // Whether the copy drawn in the frame last held glass. The next is likely to,
  // so it starts at the screen's pixels without recording it twice.
  bool _heldGlass = false;

  /// The copy the last [request] asked for as a picture this frame draws, or
  /// null when it cannot be drawn in the frame: [serve] then takes the
  /// request, while what lies there might still be drawn into an image.
  ///
  /// The caller draws the copy ([InFrameCopy.readIn]) into a layer whose
  /// image filter reads it: Impeller renders the layer into a target of its
  /// render target cache, ahead of the frame's pass in the frame's one
  /// submission, and draws the filter's output straight into the pass. No
  /// image is drawn, so the text in the copy is the frame's own text, sharing
  /// its glyph atlas and its text shadow cache, which an image drawn between
  /// frames empties.
  ///
  /// Glass in the band that composited before the caller is drawn as its
  /// picture over its own copy; one whose layer reaches past the caller's
  /// records itself again inside it (see [InFrameGlassLayer]). A copy that
  /// holds glass is drawn at the screen's pixels.
  InFrameCopy? serveInFrame() {
    final ask = _ask;
    _ask = null;
    _plan = null;
    if (ask == null) return null;
    if (ask.band.isEmpty) {
      release();
      _outOfSight = true;
      _count(debugMisses, 'off screen');
      return null;
    }
    final scan = _scanOf(ask);
    final limit = scan.reach(ask.anchor);
    return _drawInFrame(ask, scan, limit, limit < 0 ? null : scan.clip);
  }

  // [serveInFrame] over [scan], walked to [limit], the entry of [ask]'s anchor,
  // with [around] the clip around it.
  InFrameCopy? _drawInFrame(_Ask ask, _Scan scan, int limit, Rect? around) {
    final clip = around?.intersect(ask.screen);
    if (clip != null && ask.band.intersect(clip).isEmpty) {
      release();
      _outOfSight = true;
      _count(debugMisses, 'off screen');
      return null;
    }
    var grid = _heldGlass ? ask.grid._screen : ask.grid;
    var inScene = debugInScene && !_heldGlass;
    while (true) {
      final shown = inScene ? <_Entry>[] : null;
      final replay = _Prefix(
        ask.anchor,
        ask.band,
        inScene ? null : ui.PictureRecorder(),
        scan: scan,
        limit: limit,
        bodies: ask.bodies ?? [?ask.body],
        dropsGlass: BackdropUnderlay.debugDropsGlass && grid._share >= 4,
        shown: shown,
        frost: BackdropUnderlay.debugDropsFrost ? ask.frost : 0,
        parts: ask.parts,
      );
      final content = inScene ? null : replay.record(grid);
      if (inScene) {
        replay.run();
        if (replay.metGlass) {
          inScene = false;
          continue;
        }
      }
      if (inScene ? replay.blocked || !replay.reached : content == null) {
        if (!kReleaseMode) {
          final why = replay.blocked
              ? '${replay.blocker.runtimeType}'
              : 'not reached';
          _count(debugMisses, why);
          debugMiss = 'blocked by $why';
        }
        _ask = ask;
        return null;
      }
      // An image can fold glass over a copy not drawn yet, which the frame
      // cannot: [serve] takes the request.
      if (replay.pieces.isNotEmpty) {
        content!.dispose();
        for (final (picture, _) in replay.pieces) {
          picture.dispose();
        }
        _ask = ask;
        return null;
      }
      _heldGlass = replay.holdsGlass;
      if (replay.holdsGlass && grid != grid._screen) {
        content!.dispose();
        grid = grid._screen;
        continue;
      }
      _stillFrames = debugPromotes && _same(replay.out, _inFrameOut)
          ? _stillFrames + 1
          : 0;
      _inFrameOut = replay.out;
      _stillUnder = _stillFrames >= _stillNeeded;
      _room = _margin;
      release();
      debugCaptures++;
      debugMiss = null;
      return InFrameCopy._(
        content,
        shown,
        replay.frostLeftOut,
        ask.band,
        switch (clip) {
          null => ask.band,
          // A smaller copy lies in its layer's corner, which a layer grown
          // past the clip leaves outside it, and Impeller draws none of the
          // copy there (host test): the layer starts inside the clip. NEAR:
          // glass reads what lies past the clip mirrored at it, as where a
          // clip leaves no room to grow.
          _ when grid != grid._screen => grid._snapOut(
            ask.band.intersect(clip),
          ),
          _ => _layerIn(ask.band, clip, grid),
        },
        grid,
      );
    }
  }

  // The layer that holds [band] inside [clip] (both in the screen's logical
  // pixels), on [grid]. Impeller cuts a layer its clip cuts
  // by 30 % or more of what is left (see [keepsWhole]), and fragment
  // coordinates start at the cut; the glass reads what lies past the clip.
  // The layer grows into the clip, empty, until the part cut off is less
  // than that; where the clip leaves no room, it is cut to the clip. NEAR:
  // there, glass reads the copy mirrored at the clip, up to 163 levels off
  // over the 30 px of glass the host test leaves above such a clip.
  static Rect _layerIn(Rect band, Rect clip, CopyGrid grid) {
    if (keepsWhole(band, clip)) return band;
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
      return grid._snapOut(band.intersect(clip));
    }
    final grown = grid._snapOut(Rect.fromLTRB(x.$1, y.$1, x.$2, y.$2));
    return keepsWhole(grown, clip)
        ? grown
        : grid._snapOut(band.intersect(clip));
  }

  /// Whether Impeller draws a layer of [layer] whole inside a clip of
  /// [clip] (both in the same space): it cuts the layer to the clip, and
  /// starts fragment coordinates at the cut, only once the part it cuts off
  /// either axis is 30 % or more of what is left (ComputeSaveLayerCoverage,
  /// impeller/entity/save_layer_utils.cc).
  @internal
  static bool keepsWhole(Rect layer, Rect clip) {
    final cut = layer.intersect(clip);
    if (cut.isEmpty) return false;
    return (layer.width - cut.width) / cut.width < 0.3 &&
        (layer.height - cut.height) / cut.height < 0.3;
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
        copy: UnderlayCopy._(first, first._rect, last.grid),
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
    if (!held && first._stillUnder && last != null) first._stirred();
    if (held) {
      var inside = true;
      for (final i in kept!) {
        inside = inside && rectContains(members[i]._rect, asks[i].band);
      }
      if (!inside) first._room = min(first._room * 2, _roomMost);
      if (inside) {
        first.debugMiss = null;
        return (
          copy: UnderlayCopy._(first, first._rect, last.grid),
          island: last,
          held: true,
          rects: [for (final member in members) member._rect],
        );
      }
    }
    // Glass that moved over content that held still takes room to move on;
    // under content that changes, the copy holds no more than the band.
    Rect roomy(_Ask ask) =>
        ask.grid._snapOut(ask.band.inflate(first._room)).intersect(ask.screen);
    final rects = [
      for (final ask in asks)
        if ((held || first._held) && ask.filterClip == null)
          roomy(ask)
        else
          ask.band,
    ];
    final rect = rects.reduce((a, b) => a.expandToInclude(b));
    if (signed == null || signed.band != rect) {
      signed = _Prefix.signed(ask.anchor, rect, scan, limit, bodies);
    }
    if (signed.blocked || !signed.reached) {
      if (first._stillUnder) first._stirred();
      if (alone && !kReleaseMode) {
        final why = signed.blocked
            ? '${signed.blocker.runtimeType}'
            : 'not reached';
        _count(debugMisses, why);
        first.debugMiss = 'blocked by $why';
      }
      return null;
    }
    if (!kReleaseMode) {
      final kind = ask.blur != null
          ? 'blur'
          : ask.filter != null
          ? 'filter'
          : 'plain';
      _count(debugImageAsks, '${ask.anchor.runtimeType} $kind');
    }
    final island = _Island(
      ask,
      rect,
      grid: signed.filtersGlass ? ask.grid._screen : ask.grid,
    );
    // Recorded when the frame's copies are drawn, not now: glass in the band
    // whose own copy is drawn with it is drawn by then as far as it can be.
    island.redraw = () {
      final replay = _Prefix(
        ask.anchor,
        rect,
        ui.PictureRecorder(),
        scan: scan,
        limit: limit,
        bodies: [
          for (final member in island.members) ?member._joined!.body,
        ],
      );
      final picture = replay.record(island.grid);
      if (picture != null && !island.broken) island.signature = replay.out;
      island.pieces = replay.pieces;
      return picture;
    };
    first._join(island, rects.first, ask);
    if (ask.frame case final frame?) {
      frame._atlas.add(island);
    } else {
      final atlas = _Atlas();
      atlas.add(island);
      atlas.flush('at once');
    }
    return (
      copy: UnderlayCopy._(first, first._rect, island.grid),
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
    final first = island.members.first._joined!.anchor;
    final from = scan.startOf(first);
    if (from == null || from > limit) return false;
    final index = island.members.indexOf(this);
    final bodies = [
      for (final (i, other) in island.members.indexed)
        if (i == index) body else ?other._joined!.body,
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
        for (final member in island.members)
          if (scan.startOf(member._joined!.anchor) case final start?
              when start < limit)
            start,
      },
      owned: {for (final member in island.members) ?member._joined!.own},
    );
  }

  // Draws this copy from [island] from now on, [rect] of it.
  void _join(_Island island, Rect rect, _Ask ask) {
    release();
    _rect = rect;
    _island = island;
    _joined = ask;
    island.members.add(this);
    debugCaptures++;
    debugMiss = null;
  }

  /// Forgets the copy while the effect does not draw from one.
  void release() {
    _image?.dispose();
    _image = null;
    _island?._leave(this);
    _island = null;
    _joined = null;
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

  static _Scan _scanOf(_Ask ask) => _Scan.of(
    ask.frame,
    _rootOf(ask.anchor),
    ask.grid._devicePixelRatio,
    ask.anchor,
  );

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
  final _offers = <FilterOffer>[];

  /// Whether layers should [offer] themselves rather than ask for copies.
  bool get groups =>
      BackdropUnderlay.debugGroups && BackdropUnderlay.debugInFrame;

  /// Takes this frame's [offer], which [planGroups] answers.
  void offer(FilterOffer offer) => _offers.add(offer);

  /// Sorts the offers of this frame into groups that share a filter, and has
  /// the rest ask alone. The composer calls it once every layer has prepared.
  void planGroups() {
    if (_offers.isEmpty) return;
    final view = _offers.first.anchor.owner;
    final size = view is RenderView ? view.size : Size.zero;
    // What lies under an offer that held still comes from an image, which
    // takes no filter of its own.
    final groups = _groupsOf([
      for (final offer in _offers)
        if (!offer.underlay._held) offer,
    ], size.width * size.height);
    final grouped = Set<FilterOffer>.identity();
    for (final group in groups) {
      group._ask();
      grouped.add(group.lead);
      grouped.addAll(group._offered);
    }
    for (final offer in _offers) {
      if (!grouped.contains(offer)) offer.askAlone();
    }
    _offers.clear();
  }

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
    required this.grid,
    required this.screen,
    required this.band,
    required this.filter,
    required this.blur,
    required this.filterClip,
    required this.filterBlendMode,
    required this.body,
    this.frost = 0,
    this.parts,
    this.bodies,
  });

  // The parts of the band a group reads, and what it paints.
  final List<Rect>? parts;
  final List<Rect>? bodies;

  // The frame the view's composer plans, or null in a scene it does not.
  final UnderlayFrame? frame;
  final Layer anchor;
  final OpacitySeedLayer? own;
  // The grid asked for, which a copy holding glass may not be drawn on.
  final CopyGrid grid;
  final Rect screen;
  final Rect band;
  final ui.ImageFilter? filter;
  final (double, double)? blur;
  final Rect? filterClip;
  final BlendMode filterBlendMode;
  final Rect? body;
  // The frost of the glass the copy is for, in logical pixels.
  final double frost;

  // What copies under the same filter share.
  Object? get filterKey => blur ?? filter;

  bool get filtered => filterKey != null;

  bool get inFrame => BackdropUnderlay.debugInFrame && !filtered;

  // Whether the copy can be drawn with copies beside it.
  bool get joins =>
      !inFrame &&
      body != null &&
      filterClip == null &&
      filterBlendMode == BlendMode.src;
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
    if (ask.grid != first.grid ||
        ask.filterKey != first.filterKey ||
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
    return UnderlayCopy._(underlay, underlay._rect, decision.island.grid);
  }
}

// What the copies drawn as one were drawn from: the band they were
// recorded over, from what is painted before the first one's glass, and its
// signature; and each copy's rect of it.
final class _Island {
  _Island(this._ask, this.rect, {required this.grid})
    : width = (rect.width * grid._pixels).round(),
      height = (rect.height * grid._pixels).round();

  // What the first copy asked for, which every copy drawn with it shares.
  final _Ask _ask;
  final Rect rect;
  // The grid the island is drawn on.
  final CopyGrid grid;
  final members = <BackdropUnderlay>[];
  List<Object?>? signature;
  // Once a copy has left, the signature no longer tells whether the others
  // hold: the island is recorded again.
  bool broken = false;

  // The atlas that draws the island while it is pending.
  _Atlas? atlas;
  late final ui.Picture? Function() redraw;
  ui.Picture? content;
  // What the copy draws before each glass it folds in, drawn under
  // [content].
  List<(ui.Picture, _Fold)> pieces = const [];
  final int width;
  final int height;
  // Where the island lies in the atlas's image, in its pixels.
  Offset offset = Offset.zero;

  ui.ImageFilter? get filter => _ask.filter;
  (double, double)? get blur => _ask.blur;
  Object? get filterKey => _ask.filterKey;
  bool get filtered => _ask.filtered;
  Rect? get filterClip => _ask.filterClip;
  BlendMode get filterBlendMode => _ask.filterBlendMode;

  // Whether the copy is filtered in the atlas's layer of copies rather than
  // as a backdrop of its own.
  bool get layered => switch (blur) {
    (final x, final y) => max(x, y) * grid._pixels <= _Atlas._maxImageBlurSigma,
    null => false,
  };

  Rect get bounds => offset & Size(width.toDouble(), height.toDouble());

  // How `backdrop_frost.frag` frosts the island's copy in a layer of its own.
  FrostSampling frostSampling(double frost) {
    final size = Size(width.toDouble(), height.toDouble());
    return FrostSampling._(
      size: size,
      bounds: Rect.fromLTRB(0.5, 0.5, size.width - 0.5, size.height - 0.5),
      frost: grid._frost(frost) / grid._share,
      scale: 1,
      shown: Offset.zero & size,
    );
  }

  // The frost the island's copy holds, in logical pixels: frosted once, at the
  // copy's own pixels, so glass over it takes one read per fragment (see
  // inPlaceFrostFilter). A copy that folds glass in holds it at the screen's
  // pixels, where the frost would cost more than the taps.
  double get holdsFrost =>
      debugFrostsInPlace && !filtered && pieces.isEmpty && grid._share >= 2
      ? _ask.frost
      : 0;

  bool fits(_Ask ask) =>
      (!debugFrostsInPlace || ask.frost == _ask.frost) &&
      ask.filterKey == filterKey &&
      ask.filterClip == filterClip &&
      ask.filterBlendMode == filterBlendMode &&
      ask.grid == _ask.grid;

  void _leave(BackdropUnderlay underlay) {
    if (!members.remove(underlay)) return;
    broken = true;
    signature = null;
    if (members.isEmpty) {
      atlas?._pending.remove(this);
      atlas = null;
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
    this.dropsGlass = false,
    this.shown,
    this.frost = 0,
    this.parts,
  }) : canvas = recorder == null ? null : Canvas(recorder);

  // The parts of the band read, where glass reads less than the band.
  final List<Rect>? parts;

  bool readsAt(Rect bounds) {
    final held = parts;
    if (held == null) return true;
    for (final part in held) {
      if (_meets(bounds, part)) return true;
    }
    return false;
  }

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
  // The bodies of the glass the copy is for, if it is for glass.
  final List<Rect> bodies;
  // Without one, the walk only signs what it meets.
  ui.PictureRecorder? recorder;
  Canvas? canvas;
  final out = <Object?>[];
  late CopyGrid _grid;

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

  // Whether the copy draws glass as an image filter (glass over a copy not
  // drawn yet, or drawn in the frame), whose fragment coordinates are the
  // copy's pixels: the glass takes them to be the screen's.
  bool filtersGlass = false;

  // Whether the copy draws glass.
  bool holdsGlass = false;

  // Whether glass is left out of the copy, whose frost is wide enough to hide
  // it, and only what lies on it is drawn.
  final bool dropsGlass;

  // Where the walk leaves what the copy draws, to add it to the scene,
  // instead of drawing it on a canvas or signing it. It gives up at glass.
  final List<_Entry>? shown;

  // Whether a walk that leaves what it draws met glass in the band.
  bool metGlass = false;

  // The frost of the glass the copy is for, in logical pixels, which hides a
  // backdrop frost no wider, and the widest it left out.
  final double frost;
  double frostLeftOut = 0;

  bool _hides(LiquidGlassBackdropFilterLayer layer) {
    final hidden = layer.frost;
    if (hidden == null || hidden.sigma > frost) return false;
    frostLeftOut = max(frostLeftOut, hidden.sigma);
    return true;
  }

  static Set<Layer> _ancestors(Layer layer) {
    final path = Set<Layer>.identity();
    for (var node = layer.parent; node != null; node = node.parent) {
      path.add(node);
    }
    return path;
  }

  // Records what is painted before [stop] in [band] (screen logical pixels)
  // on [grid] from the band's origin, or returns null when that cannot be
  // drawn again.
  ui.Picture? record(CopyGrid grid) {
    _grid = grid;
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

  void _begin() => _beginCopy(canvas!, band, _grid);

  static void _beginCopy(Canvas c, Rect rect, CopyGrid grid) {
    final pixels = grid._pixels;
    // A picture drawn into a canvas clipped to the copy is culled to what
    // reaches it while it is recorded.
    c.clipRect(
      Rect.fromLTWH(0, 0, rect.width * pixels, rect.height * pixels),
      doAntiAlias: false,
    );
    if (grid._share > 1) {
      c.scale(1 / grid._share);
      // Impeller sets text drawn at a translation and a scale alone on whole
      // pixels of its target (impeller/entity/contents/text_contents.cc):
      // text moving under glass would step a pixel of the copy, up to four
      // of the screen's, at a time. Under a skew too small to see it lies
      // where it is drawn, read from its atlas bilinearly.
      if (BackdropUnderlay.debugPlaceText) c.skew(0, 1e-6);
    }
    c.translate(
      -rect.left * grid._devicePixelRatio,
      -rect.top * grid._devicePixelRatio,
    );
  }

  // Ends the picture before [fold] and begins the next one inside the
  // groups [open] around it.
  void fold(_Fold fold, List<(int, _Open)> open) {
    filtersGlass = true;
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
        Offset.zero,
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
  final _walked = Map<Layer, int>.identity();

  // Where [layer] begins in [entries], once the walk reached it.
  int? startOf(Layer layer) => _walked[layer];
  final entries = <_Entry>[];
  final _cursors = <_Cursor>[];

  // The container above the last anchor [reach] could not reach whose
  // children it does not walk, if one stopped it.
  Layer? blocker;

  // The clip around the anchor [reach] last reached, in the screen's logical
  // pixels, or null for none.
  Rect? get clip => _cursors.last.clip;

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

  // Where the walk stands, for [_rewind].
  _ScanMark _mark() => (
    entries: entries.length,
    cursors: [
      for (final cursor in _cursors) (cursor, cursor.next, cursor.bounds),
    ],
  );

  // Forgets the walk past [mark], which read layers that have not composed
  // yet: the next [reach] walks them as they are then.
  void _rewind(_ScanMark mark) {
    _cursors.clear();
    for (final (cursor, next, bounds) in mark.cursors) {
      cursor.next = next;
      cursor.bounds = bounds;
      _cursors.add(cursor);
      if (cursor.open >= 0) {
        final open = entries[cursor.open] as _Open;
        open.end = -1;
        open.bounds = _everywhere;
      }
    }
    entries.length = mark.entries;
    _walked.removeWhere((_, at) => at >= mark.entries);
    blocker = null;
  }

  void _add(_Cursor at, _Entry entry, Rect bounds) {
    entries.add(entry);
    at.include(bounds);
  }

  void _push(
    ContainerLayer layer,
    _Open open,
    _Cursor at, {
    Matrix4? transform,
    Offset shift = Offset.zero,
    bool dropClip = false,
    Rect? clip,
    List<Object?>? state,
    bool filters = false,
  }) {
    entries.add(open);
    // Only these anchor a copy.
    if (layer is GeometryTransformTrackingLayer ||
        layer is LiquidGlassBackdropFilterLayer) {
      _walked[layer] = entries.length - 1;
    }
    _cursors.add(
      _Cursor(
        layer,
        layer.firstChild,
        transform ?? at.base,
        transform == null ? at.shift + shift : Offset.zero,
        dropClip ? clip : at.clip,
        state ?? at.state,
        filtered: at.filtered || filters,
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
    final clip = at.clip;
    final state = at.state;
    final filtered = at.filtered;

    switch (layer) {
      case UnderlayPictureLayer():
        final bounds = _reaching(layer.canvasBounds, at);
        _add(at, _Glass(layer, at.transform, clip, state, bounds), bounds);
      case InFrameGlassLayer():
        final bounds = _reaching(layer.canvasBounds, at);
        _add(
          at,
          _Leaf(null, at, clip, state, bounds, inFrame: layer),
          bounds,
        );
      case PictureLayer(:final picture?):
        final bounds = _reaching(layer.canvasBounds, at);
        _add(
          at,
          _Leaf(
            picture,
            at,
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
        final bounds = _reaching(rect, at);
        _add(at, _Block(layer, bounds), bounds);
      case OpacitySeedLayer():
        final reads = filtered ? _everywhere : clip ?? _everywhere;
        _push(layer, _Seed(layer, reads), at);
      case BackdropFilterLayer():
        final reads = filtered ? _everywhere : clip ?? _everywhere;
        _add(at, _Block(layer, reads), reads);
        return false;
      case SeededBackdropPassLayer():
        _push(layer, _Pass(layer, at.transform, clip, filtered: filtered), at);
      case LiquidGlassBackdropFilterLayer(clip: final rect, :final reach):
        _push(
          layer,
          _Served(
            layer,
            at.transform,
            clip,
            state,
            filtered ? _everywhere : _clipped(rect.inflate(reach), at),
          ),
          at,
        );
      case TransformLayer(:final offset):
        final effective = Matrix4.translationValues(offset.dx, offset.dy, 0);
        if (layer.transform case final matrix?) effective.multiply(matrix);
        _push(
          layer,
          _MatrixOpen(effective),
          at,
          transform: at.transform.multiplied(effective),
        );
      // Shown nowhere: its addToScene adds nothing.
      case FollowerLayer(:final link, :final showWhenUnlinked)
          when link.leader == null && showWhenUnlinked != true:
        return false;
      case FollowerLayer():
        final effective = followerTransformNow(layer);
        _push(
          layer,
          _MatrixOpen(effective),
          at,
          transform: at.transform.multiplied(effective),
        );
      // Transparent: it shows nothing, though drawing it would still pay
      // for its layers and filters.
      case OpacityLayer(alpha: 0):
        return false;
      case OpacityLayer(:final offset):
        final alpha = layer.alpha ?? 255;
        _push(
          layer,
          _AlphaOpen(alpha, offset),
          at,
          shift: offset,
          state: [...state, alpha],
        );
      case ImageFilterLayer(:final imageFilter?, :final offset):
        _push(
          layer,
          _FilterOpen(layer, imageFilter, offset),
          at,
          shift: offset,
          dropClip: true,
          state: [...state, imageFilter],
          filters: true,
        );
      case OffsetLayer(:final offset)
          when layer.runtimeType == OffsetLayer ||
              layer is GeometryTransformTrackingLayer ||
              layer is ThinOffsetLayer:
        // A repaint boundary over one picture, a list's item: its scan takes
        // one entry, not a group of three, and no cursor.
        final child = layer.firstChild;
        if (child is PictureLayer &&
            identical(child, layer.lastChild) &&
            child.runtimeType == PictureLayer &&
            layer is! GeometryTransformTrackingLayer) {
          if (child.picture case final picture?) {
            final bounds = at.filtered
                ? _everywhere
                : _clipped(child.canvasBounds.shift(offset), at);
            _add(
              at,
              _Leaf(picture, at, clip, state, bounds, shift: offset),
              bounds,
            );
            return true;
          }
        }
        _push(layer, _ShiftOpen(offset), at, shift: offset);
      case ColorFilterLayer(:final colorFilter?):
        _push(
          layer,
          _ColorOpen(colorFilter),
          at,
          state: [...state, colorFilter],
        );
      case ShaderMaskLayer(
        :final shader?,
        :final maskRect?,
        :final blendMode?,
      ):
        // A FragmentShader keeps its identity while its uniforms change.
        final token = shader is ui.FragmentShader ? Object() : shader;
        final open = _MaskOpen(shader, maskRect, blendMode);
        open.extra = _reaching(maskRect, at);
        _push(
          layer,
          open,
          at,
          state: [...state, token, maskRect, blendMode],
        );
      case ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        _pushClip(layer, clipRect, clipRect, clipBehavior, at);
      case ClipRRectLayer(:final clipRRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        _pushClip(layer, clipRRect, clipRRect.outerRect, clipBehavior, at);
      case ClipRSuperellipseLayer(
            :final clipRSuperellipse?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        _pushClip(
          layer,
          clipRSuperellipse,
          clipRSuperellipse.outerRect,
          clipBehavior,
          at,
        );
      case ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none:
        _pushClip(layer, clipPath, _boundsOf(clipPath), clipBehavior, at);
      case NativeClipLayer(
            enabled: true,
            :final geometry?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        _pushClip(
          layer,
          geometry,
          switch (geometry) {
            final Rect rect => rect,
            final RRect rect => rect.outerRect,
            final RSuperellipse rect => rect.outerRect,
            final Path path => _boundsOf(path),
            _ => Rect.largest,
          },
          clipBehavior,
          at,
        );
      case LeaderLayer(:final offset):
        _push(layer, _ShiftOpen(offset), at, shift: offset);
      case ClipRectLayer() ||
          ClipRRectLayer() ||
          ClipRSuperellipseLayer() ||
          ClipPathLayer() ||
          NativeClipLayer() ||
          AnnotatedRegionLayer():
        _push(layer as ContainerLayer, _Open(), at);
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        _push(layer, _Open(), at);
      case ContainerLayer() when LiquidGlassUnderlay.effectsOf(layer) != null:
        final effects = LiquidGlassUnderlay.effectsOf(layer)!;
        if (effects.alpha == 0) return false;
        final next = at.transform.multiplied(effects.transform);
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
        _push(
          layer,
          _EffectsOpen(layer, effects.transform, rounded, alpha, blur),
          at,
          transform: next,
          dropClip: true,
          clip: nextClip,
          state: [...state, ...effectState],
          filters: blur > 0,
        );
      default:
        _add(
          at,
          _Unknown(layer, at.transform, clip, filtered: filtered),
          _everywhere,
        );
        return layer is! ContainerLayer;
    }
    return true;
  }

  // A clip layer keeps its path from frame to frame, and asking the engine
  // for its bounds crosses to native code.
  static final _pathBounds = Expando<Rect>();

  static Rect _boundsOf(Path path) => _pathBounds[path] ??= path.getBounds();

  static Rect _clipped(Rect local, _Cursor at) {
    final bounds = MatrixUtils.transformRect(at.base, local.shift(at.shift));
    final clip = at.clip;
    return clip == null ? bounds : clip.intersect(bounds);
  }

  static Rect _reaching(Rect local, _Cursor at) =>
      at.filtered ? _everywhere : _clipped(local, at);

  void _pushClip(
    ContainerLayer layer,
    Object geometry,
    Rect bounds,
    Clip behavior,
    _Cursor at,
  ) {
    final known =
        geometry is Rect ||
        geometry is RRect ||
        geometry is RSuperellipse ||
        geometry is Path;
    final onScreen = _clipped(bounds, at);
    _push(
      layer,
      known
          ? _ClipOpen(
              geometry,
              bounds,
              behavior,
              at.filtered ? null : onScreen,
            )
          : _Undrawable(layer),
      at,
      dropClip: true,
      clip: onScreen,
      state: [...at.state, geometry, behavior],
    );
  }

  // Whether the entries between [from] and [to] leave the glass at [to] free
  // to draw at [from], over the copy of what lies before it: nothing but the
  // glass of an island and what it paints with its glass ([owned]) is painted
  // under [body], nothing reads the backdrop in [band], and nothing a copy
  // cannot draw lies there. [starts] are where the island's glass begins.
  //
  // What is painted beside [body] stays over the glass, as it is, and stays
  // out of what the glass reads at its rim.
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
        case _Leaf(:final bounds) || _Glass(:final bounds):
          if (_meets(bounds, body)) return false;
        case _Block(:final bounds):
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
    final shown = prefix.shown;
    final drawing = prefix.canvas != null || shown != null;
    final out = prefix.out;
    final open = <(int, _Open)>[];
    var i = 0;
    var through = true;

    void sign(
      ui.Picture picture,
      Matrix4 transform,
      Rect? clip,
      List<Object?> state, {
      Offset shift = Offset.zero,
    }) {
      out.add(picture);
      out.add(transform);
      out.add(clip);
      out.addAll(state);
      out.add(#leaf);
      final canvas = prefix.canvas;
      if (canvas == null) return;
      if (shift == Offset.zero) {
        canvas.drawPicture(picture);
        return;
      }
      canvas.save();
      canvas.translate(shift.dx, shift.dy);
      canvas.drawPicture(picture);
      canvas.restore();
    }

    // A picture drawn in the frame over a layer of [layer] (see
    // InFrameGlassLayer): drawn whole where the copy's pass holds the layer,
    // else its part inside the pass, recorded only when drawing. A
    // signature that holds that part matches none.
    void signInFrame(
      Rect layer,
      ui.Picture whole,
      ui.Picture? Function(Rect region) within,
      Matrix4 transform,
      Rect? clip,
      List<Object?> state,
    ) {
      prefix.filtersGlass = true;
      final region = clip == null ? band : band.intersect(clip);
      if (BackdropUnderlay.keepsWhole(layer, region)) {
        sign(whole, transform, clip, state);
      } else if (drawing) {
        if (within(region) case final cut?) {
          sign(cut, transform, clip, state);
          cut.dispose();
        }
      } else {
        out.add(Object());
      }
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
        case _Leaf(glass: true) when prefix.dropsGlass:
          break;
        case _Glass() when prefix.dropsGlass:
          break;
        case _Leaf(glass: true) when prefix.beside(entry.bounds):
          break;
        case _Glass() when prefix.beside(entry.bounds):
          break;
        case _Leaf(glass: false) when shown != null:
          if (_meets(entry.bounds, band) && prefix.readsAt(entry.bounds)) {
            shown.add(entry);
            sign(entry.picture, entry.transform, entry.clip, entry.state);
          }
        case _Leaf() || _Glass() when shown != null:
          final bounds = entry is _Leaf
              ? entry.bounds
              : (entry as _Glass).bounds;
          if (_meets(bounds, band)) {
            prefix.metGlass = true;
            break loop;
          }
        case _Leaf(
          :final transform,
          :final clip,
          :final state,
          :final inFrame,
        ):
          if (_meets(entry.bounds, band)) {
            if (entry.glass) prefix.holdsGlass = true;
            if (inFrame == null) {
              sign(entry.picture, transform, clip, state, shift: entry.shift);
            } else {
              signInFrame(
                inFrame.layer,
                entry.picture,
                inFrame.within,
                transform,
                clip,
                state,
              );
            }
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
          shown?.add(entry);
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
            case _Served(:final layer, :final transform, :final clip)
                when layer.drawsGroup && !prefix.dropsGlass && shown == null:
              prefix.holdsGlass = true;
              signInFrame(
                layer.inFrameLayer!,
                layer.servedPicture!,
                layer.servedWithin,
                transform,
                clip,
                entry.state,
              );
              skip(entry);
              if (!through) break loop;
              continue loop;
            case _Served(:final layer)
                when !layer.drawsGroup && prefix._hides(layer):
              break;
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
              if (prefix.dropsGlass) {
                // Only what lies on the glass is drawn.
              } else if (shown != null) {
                prefix.metGlass = true;
                break loop;
              } else if (layer.pending) {
                if (!fold(layer, layer.addFold, transform, clip)) break loop;
              } else if (layer.inFrameLayer case final inFrame?) {
                prefix.holdsGlass = true;
                signInFrame(
                  inFrame,
                  layer.servedPicture!,
                  layer.servedWithin,
                  transform,
                  clip,
                  entry.state,
                );
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
          shown?.add(
            entry is _ClipOpen && entry.keepsAll(band) ? _Open.nothing : entry,
          );
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

typedef _ScanMark = ({
  int entries,
  List<(_Cursor, Layer?, Rect)> cursors,
});

final class _Cursor {
  _Cursor(
    this.layer,
    this.next,
    this.base,
    this.shift,
    this.clip,
    this.state, {
    required this.filtered,
    required this.open,
  });

  final ContainerLayer? layer;
  Layer? next;

  // The transform to the screen as [base] and the translation after it: most
  // layers only shift, and most of those lie outside every copy.
  final Matrix4 base;
  final Offset shift;
  Matrix4? _transform;

  // Transforms are never changed in place, so a layer that does not shift
  // shares its parent's.
  Matrix4 get transform {
    if (_transform case final held?) return held;
    if (shift == Offset.zero) return _transform = base;
    final next = base.clone();
    next.translateByDouble(shift.dx, shift.dy, 0, 1);
    return _transform = next;
  }

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
/// before it, in the glass's own coordinates: the scene holds [target].
@internal
typedef UnderlayFold = void Function(
  ui.SceneBuilder builder,
  FoldTarget target,
);

// Glass a copy draws as its filter: [add] in [transform] from the glass's
// coordinates to the screen's, inside [clip] of the screen.
typedef _Fold = ({UnderlayFold add, Matrix4 transform, Rect? clip});

final class _Leaf extends _Entry {
  _Leaf(
    this._picture,
    this._at,
    this.clip,
    this.state,
    this.bounds, {
    bool glass = false,
    this.inFrame,
    this.shift = Offset.zero,
  }) : glass = glass || inFrame != null;

  // Glass whose copy is drawn.
  final bool glass;

  // Glass over a copy drawn in the frame.
  final InFrameGlassLayer? inFrame;

  final ui.Picture? _picture;
  ui.Picture get picture => _picture ?? inFrame!.picture!;
  final _Cursor _at;
  // Where the picture lies in its cursor's coordinates.
  final Offset shift;
  Matrix4 get transform {
    if (shift == Offset.zero) return _at.transform;
    final moved = _at.transform.clone();
    moved.translateByDouble(shift.dx, shift.dy, 0, 1);
    return moved;
  }

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

// A container: what it applies around its children and the extent of what it
// draws once its children are walked.
class _Open extends _Entry {
  _Open({this.layered = false});

  // What stands for a container that adds nothing to a copy.
  static final nothing = _Open();

  // Whether it draws its children in a layer of their own.
  final bool layered;
  Rect extra = Rect.zero;
  Rect bounds = _everywhere;
  int end = -1;

  // Applies it to [c] and returns how many saves that takes.
  int apply(Canvas c) => 0;

  void finish(Canvas c, int saves) {
    for (var n = 0; n < saves; n++) {
      c.restore();
    }
  }

  // Adds it to a scene as the layer it is.
  void enter(_SceneOut out) {}
}

final class _ShiftOpen extends _Open {
  _ShiftOpen(this.offset);

  final Offset offset;

  @override
  int apply(Canvas c) {
    c.save();
    c.translate(offset.dx, offset.dy);
    return 1;
  }

  @override
  void enter(_SceneOut out) => out.at += offset;
}

final class _MatrixOpen extends _Open {
  _MatrixOpen(this.matrix);

  final Matrix4 matrix;

  @override
  int apply(Canvas c) {
    c.save();
    c.transform(matrix.storage);
    return 1;
  }

  @override
  void enter(_SceneOut out) => out.transform(matrix);
}

final class _AlphaOpen extends _Open {
  _AlphaOpen(this.alpha, this.offset) : super(layered: alpha != 255);

  final int alpha;
  final Offset offset;

  @override
  int apply(Canvas c) {
    c.save();
    c.translate(offset.dx, offset.dy);
    if (alpha == 255) return 1;
    c.saveLayer(null, _Prefix._alpha(alpha));
    return 2;
  }

  @override
  void enter(_SceneOut out) {
    if (alpha == 255) {
      out.at += offset;
      return;
    }
    out.settleMatrix();
    out.builder.pushOpacity(alpha, offset: out.at + offset);
    out.at = Offset.zero;
    out.pushes++;
  }
}

final class _FilterOpen extends _Open {
  _FilterOpen(this.layer, this.filter, this.offset) : super(layered: true);

  final ContainerLayer layer;
  final ui.ImageFilter filter;
  final Offset offset;

  @override
  int apply(Canvas c) {
    c.save();
    c.translate(offset.dx, offset.dy);
    c.saveLayer(_drawnBounds(layer), _Prefix._filtering(filter));
    return 2;
  }

  @override
  void enter(_SceneOut out) {
    out.settleMatrix();
    out.builder.pushImageFilter(filter, offset: out.at + offset);
    out.at = Offset.zero;
    out.pushes++;
  }
}

final class _ColorOpen extends _Open {
  _ColorOpen(this.filter) : super(layered: true);

  final ColorFilter filter;

  @override
  int apply(Canvas c) {
    final paint = Paint();
    paint.colorFilter = filter;
    c.saveLayer(null, paint);
    return 1;
  }

  @override
  void enter(_SceneOut out) {
    out.settle();
    out.builder.pushColorFilter(filter);
    out.pushes++;
  }
}

final class _MaskOpen extends _Open {
  _MaskOpen(this.shader, this.rect, this.blendMode) : super(layered: true);

  final Shader shader;
  final Rect rect;
  final BlendMode blendMode;

  @override
  int apply(Canvas c) {
    c.saveLayer(null, Paint());
    return 1;
  }

  @override
  void finish(Canvas c, int saves) {
    // The engine draws a shader mask over what it masks, in a layer.
    final paint = Paint();
    paint.shader = shader;
    paint.blendMode = blendMode;
    c.translate(rect.left, rect.top);
    c.drawRect(Offset.zero & rect.size, paint);
    super.finish(c, saves);
  }

  @override
  void enter(_SceneOut out) {
    out.settle();
    out.builder.pushShaderMask(shader, rect, blendMode);
    out.pushes++;
  }
}

final class _ClipOpen extends _Open {
  _ClipOpen(this.geometry, this.rect, this.behavior, this.onScreen)
    : super(layered: behavior == Clip.antiAliasWithSaveLayer);

  final Object geometry;
  final Rect rect;
  final Clip behavior;

  // The clip on the screen, null where a filter lies above it, which draws
  // what the clip cuts into what it keeps.
  final Rect? onScreen;

  // Whether the clip cuts nothing of a copy of [band].
  bool keepsAll(Rect band) =>
      geometry is Rect &&
      behavior != Clip.antiAliasWithSaveLayer &&
      onScreen != null &&
      rectContains(onScreen!, band);

  @override
  int apply(Canvas c) {
    c.save();
    final antiAlias = behavior != Clip.hardEdge;
    switch (geometry) {
      case final Rect rect:
        c.clipRect(rect, doAntiAlias: antiAlias);
      case final RRect rect:
        c.clipRRect(rect, doAntiAlias: antiAlias);
      case final RSuperellipse rect:
        c.clipRSuperellipse(rect, doAntiAlias: antiAlias);
      case final Path path:
        c.clipPath(path, doAntiAlias: antiAlias);
    }
    if (behavior != Clip.antiAliasWithSaveLayer) return 1;
    c.saveLayer(rect, Paint());
    return 2;
  }

  @override
  void enter(_SceneOut out) {
    out.settle();
    final builder = out.builder;
    switch (geometry) {
      case final Rect rect:
        builder.pushClipRect(rect, clipBehavior: behavior);
      case final RRect rect:
        builder.pushClipRRect(rect, clipBehavior: behavior);
      case final RSuperellipse rect:
        builder.pushClipRSuperellipse(rect, clipBehavior: behavior);
      case final Path path:
        builder.pushClipPath(path, clipBehavior: behavior);
    }
    out.pushes++;
  }
}

// What [LiquidGlassUnderlay] applies, a layer the copy knows by its effects.
final class _EffectsOpen extends _Open {
  _EffectsOpen(
    this.layer,
    this.matrix,
    this.rounded,
    this.alpha,
    this.blur,
  ) : super(layered: alpha != null || blur > 0);

  final ContainerLayer layer;
  final Matrix4 matrix;
  final RRect? rounded;
  final int? alpha;
  final double blur;

  @override
  int apply(Canvas c) {
    c.save();
    c.transform(matrix.storage);
    if (rounded case final rounded?) c.clipRRect(rounded);
    var saves = 1;
    if (alpha case final alpha?) {
      c.saveLayer(null, _Prefix._alpha(alpha));
      saves++;
    }
    if (blur > 0) {
      c.saveLayer(
        _drawnBounds(layer),
        _Prefix._filtering(ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur)),
      );
      saves++;
    }
    return saves;
  }

  @override
  void enter(_SceneOut out) {
    out.transform(matrix);
    final builder = out.builder;
    if (rounded case final rounded?) {
      out.settle();
      builder.pushClipRRect(rounded);
      out.pushes++;
    }
    if (alpha case final alpha? when alpha != 255) {
      out.settleMatrix();
      builder.pushOpacity(alpha, offset: out.at);
      out.at = Offset.zero;
      out.pushes++;
    }
    if (blur > 0) {
      out.settleMatrix();
      builder.pushImageFilter(
        ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        offset: out.at,
      );
      out.at = Offset.zero;
      out.pushes++;
    }
  }
}

// A scene a copy adds itself to. What only moves the coordinates waits for
// what needs them: a picture takes a translation as its offset, and a layer
// pushed costs both threads.
final class _SceneOut {
  _SceneOut(this.builder, this.matrix);

  final ui.SceneBuilder builder;

  // The transform no layer holds yet, then the translation after it.
  Matrix4? matrix;
  Offset at = Offset.zero;
  int pushes = 0;
  final _marks = <(Matrix4?, Offset, int)>[];

  void transform(Matrix4 by) {
    if (MatrixUtils.getAsTranslation(by) case final shift?) {
      at += shift;
      return;
    }
    final next = (matrix ?? Matrix4.identity()).clone();
    next.translateByDouble(at.dx, at.dy, 0, 1);
    next.multiply(by);
    matrix = next;
    at = Offset.zero;
  }

  // Pushes the waiting transform with its translation.
  void settleMatrix() {
    final held = matrix;
    if (held == null) return;
    if (at != Offset.zero) {
      final next = held.clone();
      next.translateByDouble(at.dx, at.dy, 0, 1);
      builder.pushTransform(next.storage);
    } else {
      builder.pushTransform(held.storage);
    }
    matrix = null;
    at = Offset.zero;
    pushes++;
  }

  // Leaves the coordinates of what comes next to the layers pushed.
  void settle() {
    settleMatrix();
    if (at == Offset.zero) return;
    builder.pushOffset(at.dx, at.dy);
    at = Offset.zero;
    pushes++;
  }

  void leave() {
    final (heldMatrix, heldAt, pushed) = _marks.removeLast();
    while (pushes > pushed) {
      builder.pop();
      pushes--;
    }
    matrix = heldMatrix;
    at = heldAt;
  }

  void add(List<_Entry> entries) {
    for (final entry in entries) {
      switch (entry) {
        case _Leaf(:final picture, :final shift):
          settleMatrix();
          builder.addPicture(at + shift, picture);
        case _Close():
          leave();
        case _Open():
          _marks.add((matrix, at, pushes));
          entry.enter(this);
        default:
          break;
      }
    }
    while (pushes > 0) {
      builder.pop();
      pushes--;
    }
  }
}

// A clip the copy cannot draw: a copy drawn under it fails.
final class _Undrawable extends _Open {
  _Undrawable(this.layer);

  final Layer layer;
}

// An opacity pass that glass seeds with its backdrop while it reads it.
final class _Seed extends _Open {
  _Seed(this.layer, this.reads) {
    extra = reads;
  }

  final OpacitySeedLayer layer;
  final Rect reads;
}

// A seeded backdrop pass, hidden or read as glass composites.
final class _Pass extends _Open {
  _Pass(this.layer, this.transform, this.clip, {required this.filtered}) {
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
  ) {
    extra = reads;
  }

  final LiquidGlassBackdropFilterLayer layer;
  final Matrix4 transform;
  final Rect? clip;
  final List<Object?> state;
  final Rect reads;
}

/// A copy that [BackdropUnderlay.serve] hands over: [rect] of the screen, in
/// logical pixels, somewhere in [image]. Glass reads it as [glassSampling]
/// says, a surface paints the part [readOf] gives.
///
/// A copy recorded this frame is drawn by [UnderlayFrame.drawPending] with
/// the frame's other copies; reading [image], [placement] or a read earlier
/// draws the pending copies then.
@internal
final class UnderlayCopy {
  const UnderlayCopy._(this._underlay, this.rect, this._grid);

  final BackdropUnderlay _underlay;
  final CopyGrid _grid;

  /// The screen rect the copy holds, in logical pixels.
  final Rect rect;

  /// Whether [image] is drawn already.
  bool get ready => _underlay._image != null;

  /// Whether the copy is drawn with the frame's copies, not yet drawn.
  bool get pending => !ready && _underlay._island?.atlas != null;

  /// The image that holds the copy, shared with other copies of the frame.
  ui.Image get image {
    if (!ready) _underlay._island?.atlas?.flush('read');
    return _underlay._image!;
  }

  /// Equal while the copy lies at the same place in [image] on the same
  /// grid.
  Object get placement => (_offset, _grid);

  // Where [rect]'s top left corner sits in [image], in its pixels.
  Offset get _offset {
    if (!ready) _underlay._island?.atlas?.flush('read');
    return _underlay._offset;
  }

  /// How the final shader reads the copy, painted in the screen's device
  /// pixels, to frost it for Impeller's blur by [frost] (see
  /// [GlassSampling.frost]).
  GlassSampling glassSampling(double frost) {
    final image = this.image;
    final share = _grid._share;
    return GlassSampling._(
      origin:
          rect.topLeft * _grid._devicePixelRatio - _offset * share.toDouble(),
      reduced: share > 1 ? 1 : 0,
      frost: frost == _underlay._heldFrost ? 0 : _grid._frost(frost),
      image: image,
      size: Size(
        image.width * share.toDouble(),
        image.height * share.toDouble(),
      ),
    );
  }

  /// The part [shown] (screen logical pixels, inside [rect]) of the copy.
  ImageRead readOf(Rect shown) => ImageRead._(this, shown);
}

/// A copy that [BackdropUnderlay.serveInFrame] hands over: what is painted
/// before the glass in a band of the screen, drawn in a layer of [layer].
/// A reader draws the part of the layer [readIn] gives; its owner disposes
/// it.
@internal
final class InFrameCopy {
  InFrameCopy._(
    this._picture,
    this._shown,
    this._frostLeftOut,
    this._band,
    this.layer,
    this._grid,
  );

  final CopyGrid _grid;
  ui.Picture? _picture;
  // What the copy draws, for a copy that is added to the scene.
  final List<_Entry>? _shown;
  // The backdrop frost the copy left out, in logical pixels.
  final double _frostLeftOut;

  // The frost, in logical pixels, that stands for [frost] over what the copy
  // left out.
  double _frostOver(double frost) => frost > 0 && _frostLeftOut > 0
      ? sqrt(frost * frost + _frostLeftOut * _frostLeftOut)
      : frost;

  /// Whether readers can add the copy to the scene instead of drawing
  /// [_content].
  bool get inScene => _shown != null;

  // The copy as a picture, recorded only for a reader that draws it.
  ui.Picture get _content => _picture ??= _record();

  ui.Picture _record() {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    _Prefix._beginCopy(c, _band, _grid);
    final open = <(int, _Open)>[];
    for (final entry in _shown!) {
      switch (entry) {
        case _Leaf(:final picture, :final shift):
          if (shift == Offset.zero) {
            c.drawPicture(picture);
          } else {
            c.save();
            c.translate(shift.dx, shift.dy);
            c.drawPicture(picture);
            c.restore();
          }
        case _Close():
          final (saves, group) = open.removeLast();
          group.finish(c, saves);
        case _Open():
          open.add((entry.apply(c), entry));
        default:
          break;
      }
    }
    for (final (saves, group) in open.reversed) {
      group.finish(c, saves);
    }
    return recorder.endRecording();
  }

  // Adds the copy's layers to [builder], with the copy's top-left corner at
  // [origin] in the coordinates there, cut to [within].
  void _addTo(ui.SceneBuilder builder, Offset origin, Rect within) {
    final grid = _grid;
    final pixels = grid._pixels;
    builder.pushClipRect(
      (origin & Size(_band.width * pixels, _band.height * pixels)).intersect(
        within,
      ),
      clipBehavior: Clip.hardEdge,
    );
    // _Prefix._beginCopy as one matrix.
    final share = grid._share;
    final scale = 1 / share;
    final skew = share > 1 && BackdropUnderlay.debugPlaceText ? 1e-6 : 0.0;
    final left = _band.left * grid._devicePixelRatio;
    final top = _band.top * grid._devicePixelRatio;
    final matrix = Matrix4.zero();
    final storage = matrix.storage;
    storage[0] = scale;
    storage[1] = scale * skew;
    storage[5] = scale;
    storage[10] = 1;
    storage[12] = origin.dx - scale * left;
    storage[13] = origin.dy - scale * top - scale * skew * left;
    storage[15] = 1;
    _SceneOut(builder, matrix).add(_shown!);
    builder.pop();
  }

  // The screen rect the copy holds, in logical pixels, on its grid.
  final Rect _band;

  /// The rect of the layer the copy is drawn in, in the screen's logical
  /// pixels: the copy's band, grown where a clip would cut the layer, or the
  /// part of the band inside a clip that leaves no room to grow or that cuts
  /// a copy smaller than the screen.
  final Rect layer;

  /// The part of the copy's layer inside [region] (screen logical pixels),
  /// or null where none of it is.
  CornerRead? readIn(Rect region) {
    final cut = region.intersect(layer);
    return cut.isEmpty ? null : CornerRead._(this, cut);
  }

  /// Releases the copy.
  void dispose() => _picture?.dispose();
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

/// A picture of glass over a copy drawn in the frame, which owns the copy:
/// the glass's shader filters a layer of [layer] (the screen's logical
/// pixels) holding the copy.
///
/// Impeller cuts a layer drawn inside a smaller pass (see
/// [BackdropUnderlay.keepsWhole]), and its fragment coordinates start at the
/// cut: a copy for other glass whose pass does not hold [layer] draws this
/// glass with [within] instead.
@internal
class InFrameGlassLayer extends GlassPictureLayer {
  /// A layer whose picture draws the glass over [copy] inside
  /// [canvasBounds].
  InFrameGlassLayer(super.canvasBounds, this.copy, this.within);

  /// The copy the glass is drawn over.
  final InFrameCopy copy;

  /// The rect of the layer the glass's shader filters.
  Rect get layer => copy.layer;

  /// Records the glass over the part of its copy inside a rect of the screen
  /// (logical pixels), or returns null when none of it is.
  final ui.Picture? Function(Rect region) within;

  CornerRead? _read;
  late ui.ImageFilter _filter;
  late Matrix4 _deviceToLocal;

  /// Adds the glass to the scene as [read] filtered by [filter], in
  /// coordinates [deviceToLocal] takes the screen's device pixels to, and
  /// records it only for a copy that draws it.
  void showInScene(
    CornerRead read,
    ui.ImageFilter filter,
    Matrix4 deviceToLocal, {
    ui.Path? clip,
    List<(ui.Picture, Offset)> under = const [],
    ui.ImageFilter? inPlace,
  }) {
    _read = read;
    _filter = filter;
    _deviceToLocal = deviceToLocal;
    _clip = clip;
    _under = under;
    _inPlace = inPlace;
  }

  ui.Path? _clip;
  ui.ImageFilter? _inPlace;
  List<(ui.Picture, Offset)> _under = const [];

  @override
  ui.Picture? get picture {
    if (super.picture == null && _read != null) {
      super.picture = within(layer);
    }
    return super.picture;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_read case final read?) {
      for (final (picture, offset) in _under) {
        builder.addPicture(offset, picture);
      }
      read.addToScene(
        builder,
        _filter,
        _deviceToLocal,
        clip: _clip,
        inPlace: _inPlace,
      );
    } else {
      super.addToScene(builder);
    }
  }

  @override
  void dispose() {
    copy.dispose();
    super.dispose();
  }
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

  final _pending = <_Island>[];
  bool _flushing = false;

  void add(_Island island) {
    island.atlas = this;
    _pending.add(island);
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
        final picture = tile.redraw();
        assert(picture != null, 'A copy recorded again is never blocked.');
        tile.content = picture ?? ui.PictureRecorder().endRecording();
      }
      // Copies filtered in the layer of copies lie side by side, to share
      // it.
      final runs = <Object?, List<_Island>>{};
      for (final tile in batch) {
        runs
            .putIfAbsent(
              !tile.filtered ? null : (tile.filterKey, tile.grid, tile.layered),
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
  static void _pack(List<List<_Island>> runs) {
    final batch = [for (final run in runs) ...run];
    final starts = Set<_Island>.identity();
    for (final run in runs) {
      starts.add(run.first);
    }
    var start = 0;
    while (start < batch.length) {
      final tiles = <_Island>[];
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
  static Matrix4 _toAtlas(_Island tile) {
    final pixels = tile.grid._pixels;
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
  static void _add(ui.SceneBuilder b, _Island tile, {required Offset origin}) {
    for (final (picture, fold) in tile.pieces) {
      b.addPicture(tile.offset, picture);
      BackdropUnderlay.debugFolds++;
      b.pushClipRect(tile.bounds, clipBehavior: Clip.hardEdge);
      b.pushTransform(_toAtlas(tile).storage);
      if (fold.clip case final clip?) {
        b.pushClipRect(clip, clipBehavior: Clip.hardEdge);
      }
      b.pushTransform(fold.transform.storage);
      fold.add(b, FoldTarget._(tile.grid, tile.rect, origin));
      b.pop();
      if (fold.clip != null) b.pop();
      b.pop();
      b.pop();
    }
    b.addPicture(tile.offset, tile.content!);
  }

  static void _draw(List<_Island> tiles, int width, int height) {
    BackdropUnderlay.debugImagesDrawn++;
    // A copy's picture is clipped to the copy when it is recorded.
    void place(Canvas canvas, _Island tile) {
      canvas.save();
      canvas.translate(tile.offset.dx, tile.offset.dy);
      final frost = tile.holdsFrost;
      final filter = frost > 0
          ? frostFilterOf(tile.frostSampling(frost))
          : null;
      if (filter != null) {
        final inner = Paint();
        inner.imageFilter = filter;
        final size = Size(tile.width.toDouble(), tile.height.toDouble());
        canvas.saveLayer(Offset.zero & size, inner);
        // Impeller sizes a layer by what is drawn in it.
        final clear = Paint();
        clear.blendMode = BlendMode.clear;
        canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), clear);
        canvas.drawRect(
          Rect.fromLTRB(
            size.width - 1,
            size.height - 1,
            size.width,
            size.height,
          ),
          clear,
        );
      }
      canvas.drawPicture(tile.content!);
      if (filter != null) canvas.restore();
      canvas.restore();
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final isolated = <_Island>[];
    final folding = <_Island>[];
    // Copies under one blur share one filtered layer: the filter reads the
    // copies alone, so no backdrop is copied for it, and the layer is
    // clipped to the rows of the copies' run, which hold no other copy.
    final layered = <(Object?, CopyGrid), List<_Island>>{};
    for (final tile in tiles) {
      if (!tile.filtered) {
        if (tile.pieces.isEmpty) {
          place(canvas, tile);
        } else {
          folding.add(tile);
        }
      } else if (tile.layered) {
        layered.putIfAbsent((tile.filterKey, tile.grid), () => []).add(tile);
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
            first.blur!.$1 * first.grid._pixels,
            first.blur!.$2 * first.grid._pixels,
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
      tile.atlas = null;
      final size = tile.members.length;
      if (size > 1) _count(BackdropUnderlay.debugIslands, size);
      for (final member in tile.members) {
        final shift =
            (member._rect.topLeft - tile.rect.topLeft) * tile.grid._pixels;
        member._image = image.clone();
        member._heldFrost = tile.holdsFrost;
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
