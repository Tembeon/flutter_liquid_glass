// Scene building reads as one statement per push and pop, without cascades.
// ignore_for_file: cascade_invocations

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/backdrop_rig.dart'
    show frostFilterOf;
import 'package:liquid_glass_renderer/src/composer/frame_report.dart';
import 'package:liquid_glass_renderer/src/internal/glass_blur.dart';
import 'package:liquid_glass_renderer/src/composer/form.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';
import 'package:liquid_glass_renderer/src/composer/scene_out.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/shader_frost.dart';

part 'copy_read.dart';

/// A layer the frame's plan decides for.
///
/// The view's composer asks each site for its facts, compiles the plan and
/// tells each its fate, in paint order, before the scene is built.
@internal
abstract interface class PlanSite {
  /// Where this frame's walk of the layers found the site.
  SiteNode? formNode;

  /// Writes what the frame's plan reads of this site.
  void fillPlanFacts(SiteFacts facts);

  /// This frame's [fate], before any read of the frame is drawn. A site that
  /// draws no read of its own takes its place here.
  void beginFate(Fate fate);

  /// Draws [read], which this site leads, as a layer of [copy], which replays
  /// when the scene is added.
  void showScene(Read read, ReadCopy copy);

  /// Draws [read], which this site leads, from [page].
  void showPage(Read read, PageCopy page);

  /// Reads the live backdrop.
  void showLive(BackdropKey? group);

  /// Adds the read this site leads to [out], inside a copy of what lies under
  /// glass over it.
  void addOutput(SceneOut out, ReadCopy outer);

  /// Whether this frame's read draws what the site's layer holds, so a replay
  /// leaves it out.
  bool get drawsOwnChildren;

  /// Whether a replay meets the site's output where it meets the site, rather
  /// than at a [GlassSlotLayer] further on.
  bool get outputsInPlace;

  /// What draws a read this site joins, if it can draw one.
  ReadPainter? get readPainter;

  /// The frame's plan is drawn: what held for the frame lets go.
  void endFrame();
}

/// Glass that draws other sites of its read in its own filter.
@internal
abstract interface class ReadPainter {
  /// What frosts [corner]'s copy where it lies for [read], or null where the
  /// glass frosts it fragment by fragment.
  ui.ImageFilter? readInPlace(Read read, CornerRead corner);

  /// The filter that draws [read] over [corner].
  ui.ImageFilter readFilter(
    Read read,
    CornerRead corner,
    ui.ImageFilter? inPlace,
  );

  /// Changes when what [recordPage] draws for [read] changes, its page aside.
  Object readRevision(Read read);

  /// Records [read] over [page], in the coordinates [screenToCanvas] takes the
  /// screen's device pixels to.
  ui.Picture recordPage(Read read, PageCopy page, Matrix4 screenToCanvas);
}

/// Where a site's fate shows in the layer tree: the walk does not go in, and
/// what is in here says nothing to the plan.
@internal
class GlassSlotLayer extends ContainerLayer {
  /// The site the slot shows.
  PlanSite? site;
}

/// A read as a layer of the scene.
///
/// While nothing under its band and nothing of its filter changed, it stays out
/// of the scene's rebuild: the engine layer it made holds.
@internal
final class ReadLayer extends ContainerLayer {
  ui.TransformEngineLayer? Function(ui.SceneBuilder builder)? _add;

  /// Shows what [add] adds, which returns the engine layer around it. Unless
  /// [changed], the engine layer of the last frame stands for it.
  void show(
    ui.TransformEngineLayer? Function(ui.SceneBuilder builder) add, {
    required bool changed,
  }) {
    _add = add;
    if (changed) markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    engineLayer = _add?.call(builder);
  }
}

/// Whether glass reads copies of what lies under it, wherever Impeller renders,
/// not under `flutter test` unless a test turns it on.
@internal
abstract final class GlassCopies {
  /// Replaces [enabled] for a test.
  @visibleForTesting
  static bool? debugEnabledOverride;

  static final bool _defaultEnabled =
      !kIsWeb &&
      ui.ImageFilter.isShaderFilterSupported &&
      !runningUnderFlutterTest;

  /// Whether glass layers keep copies of what lies under them.
  static bool get enabled => debugEnabledOverride ?? _defaultEnabled;

  /// How many images were drawn.
  @visibleForTesting
  static int debugImagesDrawn = 0;

  /// Whether a copy smaller than the screen draws its text where it lies
  /// rather than on the copy's pixels, for an A/B run.
  @visibleForTesting
  static bool debugPlaceText = true;

  /// How many filtered layers the pages were drawn in.
  @visibleForTesting
  static int debugBlurLayers = 0;

  /// Whether a read over a texture adds the texture again in the scene, for an
  /// A/B run: until a run says it holds, what lies over one reads live.
  @internal
  static bool debugTextureInScene = false;

  /// What a frame's reads added of the layers under them, since cleared.
  @visibleForTesting
  static int debugReplayed = 0;

  /// Whether Impeller draws a layer of [layer] whole inside a clip of
  /// [clip] (both in the same space): it cuts the layer to the clip, and
  /// starts fragment coordinates at the cut, only once the part it cuts off
  /// either axis is 30 % or more of what is left (ComputeSaveLayerCoverage,
  /// impeller/entity/save_layer_utils.cc).
  static bool keepsWhole(Rect layer, Rect clip) {
    final cut = layer.intersect(clip);
    if (cut.isEmpty) return false;
    return (layer.width - cut.width) / cut.width < 0.3 &&
        (layer.height - cut.height) / cut.height < 0.3;
  }
}

Rect _snapOutAt(Rect rect, double dpr) => Rect.fromLTRB(
  (rect.left * dpr).floorToDouble() / dpr,
  (rect.top * dpr).floorToDouble() / dpr,
  (rect.right * dpr).ceilToDouble() / dpr,
  (rect.bottom * dpr).ceilToDouble() / dpr,
);

// Content clipped away reaches no band, even where its empty rect lies across
// one.
bool _meets(Rect bounds, Rect band) => !bounds.isEmpty && bounds.overlaps(band);

// The layer that holds [band] inside [clip] (both in the screen's logical
// pixels), on [grid]. Impeller cuts a layer its clip cuts
// by 30 % or more of what is left (see [GlassCopies.keepsWhole]), and fragment
// coordinates start at the cut; the glass reads what lies past the clip.
// The layer grows into the clip, empty, until the part cut off is less
// than that; where the clip leaves no room, it is cut to the clip. NEAR:
// there, glass reads the copy mirrored at the clip, up to 163 levels off
// over the 30 px of glass the host test leaves above such a clip.
Rect _layerIn(Rect band, Rect clip, CopyGrid grid) {
  if (GlassCopies.keepsWhole(band, clip)) return band;
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
  return GlassCopies.keepsWhole(grown, clip)
      ? grown
      : grid._snapOut(band.intersect(clip));
}

/// What lies under one read of a frame, drawn again from the frame's own
/// layers: the layer tree before the read's lead, in a band of the screen.
///
/// Glass in the band that the plan says lies under the read adds its own read
/// in here, so a read holding glass takes one more target per glass it holds.
/// The read's filter reads it: Impeller renders it into a target of its render
/// target cache, ahead of the frame's pass in the frame's one submission, and
/// draws the filter's output straight into the pass. The text in the copy is
/// the frame's own, sharing its glyph atlas and its text shadow cache, which an
/// image drawn between frames empties.
@internal
final class ReadCopy {
  ReadCopy._(
    this.read,
    this._plan,
    this._form,
    this._band,
    this.layer,
    this._grid,
  );

  /// The copy of [read] in [plan], of [form]'s frame.
  factory ReadCopy.of(
    Read read,
    Plan plan,
    Form form,
    double devicePixelRatio,
  ) {
    final asked = CopyGrid._(devicePixelRatio, read.downscale);
    final grid = read.holds.isEmpty ? asked : asked._screen;
    final band = asked._snapOut(read.band).intersect(form.screen);
    final clip = read.lead.clip?.intersect(form.screen);
    final layer = switch (clip) {
      null => band,
      // A smaller copy lies in its layer's corner, which a layer grown past
      // the clip leaves outside it, and Impeller draws none of the copy there
      // (host test): the layer starts inside the clip. NEAR: glass reads what
      // lies past the clip mirrored at it, as where a clip leaves no room to
      // grow.
      _ when grid._share > 1 => grid._snapOut(band.intersect(clip)),
      _ => _layerIn(band, clip, grid),
    };
    return ReadCopy._(read, plan, form, band, layer, grid);
  }

  /// The read this copy is for.
  final Read read;

  final Plan _plan;
  final Form _form;
  final CopyGrid _grid;

  // The screen rect the copy holds, in logical pixels, on its grid.
  final Rect _band;

  /// The rect of the layer the copy is drawn in, in the screen's logical
  /// pixels: the copy's band, grown where a clip would cut the layer, or the
  /// part of the band inside a clip that leaves no room to grow or that cuts
  /// a copy smaller than the screen.
  final Rect layer;

  /// The screen rect the copy holds, in logical pixels.
  Rect get band => _band;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio => _grid._devicePixelRatio;

  // The frost, in logical pixels, that stands for [frost] over what the copy
  // left out.
  double _frostOver(double frost) => frost > 0 && read.frostLeftOut > 0
      ? sqrt(frost * frost + read.frostLeftOut * read.frostLeftOut)
      : frost;

  /// The part of the copy's layer inside [region] (screen logical pixels),
  /// or null where none of it is.
  CornerRead? readIn(Rect region) {
    final cut = region.intersect(layer);
    return cut.isEmpty ? null : CornerRead._(this, cut);
  }

  /// The region of this copy's layer to read inside [outer], where the layer of
  /// the read holding this one is cut by [clip], the clip around this one's
  /// lead on the screen.
  Rect regionIn(ReadCopy outer, Rect? clip) {
    final held = clip == null ? outer.band : outer.band.intersect(clip);
    return GlassCopies.keepsWhole(layer, held) ? layer : held;
  }

  void _addTo(ui.SceneBuilder builder, Offset origin, Rect within) {
    final pixels = _grid._pixels;
    builder.pushClipRect(
      (origin & Size(_band.width * pixels, _band.height * pixels)).intersect(
        within,
      ),
      clipBehavior: Clip.hardEdge,
    );
    _replay(builder, _grid, _band, origin);
    builder.pop();
  }

  // Adds the glass of [site] if this copy holds its read.
  void _addHeld(PlanSite site, SceneOut out) {
    final facts = site.formNode?.facts;
    if (facts == null || facts.index >= _plan.fates.length) return;
    final fate = _plan.fates[facts.index];
    if (fate is Leads && read.holds.contains(fate.read)) {
      site.addOutput(out, this);
    }
  }

  void _replay(ui.SceneBuilder builder, CopyGrid grid, Rect rect, Offset at) {
    final out = SceneOut(builder, grid._copyMatrix(rect, at));
    final top = _form.top;
    if (top is OpenNode) _Replay(out, this, rect).from(top);
    out.finish();
  }
}

// Adds what lies before a read's lead in a rect of the screen. Stops at the
// lead: past it, nothing of the frame lies under the glass.
final class _Replay {
  _Replay(this.out, this.copy, this.band) : stop = copy.read.lead.order;

  final SceneOut out;
  final ReadCopy copy;
  final Rect band;
  final int stop;

  void from(OpenNode top) {
    out.mark();
    top.enter(out, band);
    children(top);
    out.leave();
  }

  // False once the replay reached the lead.
  bool children(OpenNode node) {
    final read = copy.read;
    final parts = read.members.length > 1 && read.imageRect == null
        ? read.members
        : null;
    for (var child = node.first; child != null; child = child.next) {
      if (child.order >= stop) return false;
      switch (child) {
        case PictureNode(:final screen):
          final layer = child.layer as PictureLayer;
          // Glass moved its shadows into its slot this frame.
          if (!identical(layer.parent, node.layer)) continue;
          if (layer.picture == null || !_meets(screen, band)) continue;
          if (parts != null && !parts.any((m) => _meets(screen, m.reads))) {
            continue;
          }
          if (!kReleaseMode) GlassWork.replayed++;
          GlassCopies.debugReplayed++;
          out.picture(layer.picture!);
        case OutputNode(:final site?):
          copy._addHeld(site, out);
        case OutputNode():
          break;
        case VolatileNode():
          break;
        case final SiteNode site:
          if (!site.holdsComposed &&
              site.end <= stop &&
              !_meets(site.bounds, band)) {
            continue;
          }
          out.mark();
          site.enter(out, band);
          if (site.site.outputsInPlace) copy._addHeld(site.site, out);
          final through = site.site.drawsOwnChildren
              ? site.end <= stop
              : children(site);
          out.leave();
          if (!through) return false;
        case final OpenNode open:
          if (!open.holdsComposed &&
              open.end <= stop &&
              !_meets(open.bounds, band)) {
            continue;
          }
          out.mark();
          open.enter(out, band);
          final through = children(open);
          out.leave();
          if (!through) return false;
      }
    }
    return true;
  }
}

/// Where a read's page lies in an image: [rect] of the screen, in logical
/// pixels. Glass reads it as [glassSampling] says, a surface paints the part
/// [readOf] gives.
@internal
final class PageCopy {
  PageCopy._(
    this.image,
    this.rect,
    this._offset,
    this._grid,
    this._heldFrost,
    this._frostLeftOut,
  );

  /// The image, shared with other pages of its frame.
  final ui.Image image;

  /// The screen rect the page holds, in logical pixels.
  final Rect rect;

  final Offset _offset;
  final CopyGrid _grid;

  final double _heldFrost;

  // The widest frost left out of the page under glass that frosts as wide.
  final double _frostLeftOut;

  /// Where the page lies in [image].
  @visibleForTesting
  Offset get debugOffset => _offset;

  /// Equal while the page lies at the same place on the same grid.
  Object get placement => (_offset, _grid);

  /// The frost the page holds, in logical pixels, 0 for none.
  double get heldFrost => _heldFrost;

  /// What [glassSampling] stands for by the frost [sigma] of a band.
  double frostOf(double sigma) => _grid._frost(sigma);

  /// How the final shader reads the page, painted in the screen's device
  /// pixels, to frost it for Impeller's blur by [frost] (see
  /// [GlassSampling.frost]).
  GlassSampling glassSampling(double frost) {
    final share = _grid._share;
    return GlassSampling._(
      origin:
          rect.topLeft * _grid._devicePixelRatio - _offset * share.toDouble(),
      reduced: share > 1 ? 1 : 0,
      frost: frost == _heldFrost
          ? 0
          : _grid._frost(
              frost > 0 && _frostLeftOut > 0
                  ? sqrt(frost * frost + _frostLeftOut * _frostLeftOut)
                  : frost,
            ),
      image: image,
      size: Size(
        image.width * share.toDouble(),
        image.height * share.toDouble(),
      ),
    );
  }

  /// The part [shown] (screen logical pixels, inside [rect]) of the page.
  PagePart readOf(Rect shown) => PagePart._(this, shown);

  /// The rect [drawn] (screen logical pixels) covers in the fragments
  /// [glassSampling] gives.
  Rect fragmentsOf(Rect drawn) {
    final dpr = _grid._devicePixelRatio;
    final cut = drawn.intersect(rect);
    return Rect.fromLTRB(
      cut.left * dpr,
      cut.top * dpr,
      cut.right * dpr,
      cut.bottom * dpr,
    ).shift(-glassSampling(0).origin);
  }

  void _dispose() => image.dispose();
}

// One read's page in a frame's images.
final class _Tile {
  _Tile(this.copy, this.page, this.rect, this.grid)
    : width = (rect.width * grid._pixels).round(),
      height = (rect.height * grid._pixels).round();

  final ReadCopy copy;
  final PageFilter page;
  final Rect rect;
  final CopyGrid grid;
  final int width;
  final int height;

  // Where the page lies in the image, in its pixels.
  Offset offset = Offset.zero;

  Rect get bounds => offset & Size(width.toDouble(), height.toDouble());

  bool get filtered => page.key != null;

  // Whether the page is filtered in the image's layer of pages rather than as
  // a backdrop of its own.
  bool get layered => switch (page.blur) {
    (final x, final y) => max(x, y) * grid._pixels <= _Pages._maxImageBlurSigma,
    null => false,
  };

  // The frost the page holds, in logical pixels: frosted once, at the page's
  // own pixels, so glass over it takes one read per fragment (see
  // inPlaceFrostFilter). A page holding glass holds it at the screen's pixels,
  // where the frost would cost more than the taps.
  double get holdsFrost =>
      copy.read.bakesFrost && !filtered ? copy.read.frost : 0;

  // How `backdrop_frost.frag` frosts the page in a layer of its own.
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
}

// The pages of a frame's reads, one image for all that can share one: every
// image drawn on its own costs the raster thread a render pass, a texture and a
// command buffer, and the GPU driver a submission.
final class _Pages {
  // Gap between pages, in device pixels: sampling between pixels at a page's
  // edge reads no neighbour.
  static const int _gap = 2;
  static const int _rowWidth = 2048;
  static const int _maxHeight = 4096;

  // Impeller downsamples an image filter's blur on a grid of its own and a
  // backdrop filter's on the target's: past this sigma in a page's pixels
  // the two part by up to 15 levels at some sizes (host parity), so a page
  // blurred more is blurred as a backdrop filter.
  static const double _maxImageBlurSigma = 14;

  // The pages' blurs, held across frames: dart:ui converts each new filter
  // to a native one again. Glass asks for few distinct blurs, so the held
  // ones are dropped all at once when that grows past a handful.
  static final _blurs = <(double, double), ui.ImageFilter>{};

  static ui.ImageFilter _blur(double sigmaX, double sigmaY) {
    final key = (sigmaX, sigmaY);
    if (_blurs[key] case final held?) return held;
    if (_blurs.length >= 16) _blurs.clear();
    if (!kReleaseMode) GlassWork.filters++;
    return _blurs[key] = ui.ImageFilter.blur(
      sigmaX: sigmaX,
      sigmaY: sigmaY,
      tileMode: glassBlurTileMode,
    );
  }

  final _held = Map<Object, PageCopy>.identity();

  PageCopy? held(Read read) => _held[read.lead.id];

  // Draws [tiles], which hold no glass one of them reads from an image not yet
  // drawn.
  void draw(List<_Tile> tiles) {
    final runs = <Object?, List<_Tile>>{};
    for (final tile in tiles) {
      runs
          .putIfAbsent(
            !tile.filtered ? null : (tile.page.key, tile.grid, tile.layered),
            () => [],
          )
          .add(tile);
    }
    _pack(runs.values.toList());
  }

  // Every run starts a row of its own, so that the rect around a run's
  // pages holds no other page.
  void _pack(List<List<_Tile>> runs) {
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
    final pixels = tile.grid._pixels;
    final toAtlas = Matrix4.translationValues(
      tile.offset.dx - tile.rect.left * pixels,
      tile.offset.dy - tile.rect.top * pixels,
      0,
    );
    toAtlas.scaleByDouble(pixels, pixels, 1, 1);
    return toAtlas;
  }

  void _draw(List<_Tile> tiles, int width, int height) {
    if (!kReleaseMode) GlassWork.images++;
    GlassCopies.debugImagesDrawn++;
    final b = ui.SceneBuilder();
    void add(_Tile tile, Rect within) {
      b.pushClipRect(within, clipBehavior: Clip.hardEdge);
      tile.copy._replay(b, tile.grid, tile.rect, tile.offset);
      b.pop();
    }

    final isolated = <_Tile>[];
    // Pages under one blur share one filtered layer: the filter reads the
    // pages alone, so no backdrop is copied for it, and the layer is
    // clipped to the rows of the pages' run, which hold no other page.
    final layered = <(Object?, CopyGrid), List<_Tile>>{};
    for (final tile in tiles) {
      if (!tile.filtered) {
        final frost = tile.holdsFrost;
        final filter = frost > 0
            ? frostFilterOf(tile.frostSampling(tile.copy._frostOver(frost)))
            : null;
        if (filter == null) {
          add(tile, tile.bounds);
        } else {
          final size = tile.bounds.size;
          b.pushOffset(tile.offset.dx, tile.offset.dy);
          b.pushImageFilter(filter);
          // Impeller sizes a layer by what is drawn in it.
          b.addPicture(Offset.zero, CornerRead._corners(size));
          b.pushClipRect(Offset.zero & size, clipBehavior: Clip.hardEdge);
          tile.copy._replay(b, tile.grid, tile.rect, Offset.zero);
          b.pop();
          b.pop();
          b.pop();
        }
      } else if (tile.layered) {
        layered.putIfAbsent((tile.page.key, tile.grid), () => []).add(tile);
      } else {
        isolated.add(tile);
      }
    }
    for (final group in layered.values) {
      GlassCopies.debugBlurLayers++;
      final first = group.first;
      var bounds = first.bounds;
      for (final tile in group.skip(1)) {
        bounds = bounds.expandToInclude(tile.bounds);
      }
      b.pushClipRect(bounds, clipBehavior: Clip.hardEdge);
      // Impeller takes an image filter's sigmas in the pixels it draws
      // into, whatever the canvas scale: here the pages' own.
      b.pushImageFilter(
        _blur(
          first.page.blur!.$1 * first.grid._pixels,
          first.page.blur!.$2 * first.grid._pixels,
        ),
      );
      for (final tile in group) {
        add(tile, tile.bounds);
      }
      b.pop();
      b.pop();
    }
    // A page's own filter stands under the view's scale, as the backdrop
    // filter it replaces does. In a layer around its page it reads that layer
    // alone; drawn straight into the image, Impeller blurs the whole image.
    for (final tile in isolated) {
      final page = tile.page;
      final filter = page.filter ?? _blur(page.blur!.$1, page.blur!.$2);
      b.pushClipRect(tile.bounds, clipBehavior: Clip.antiAliasWithSaveLayer);
      add(tile, tile.bounds);
      b.pushTransform(_toAtlas(tile).storage);
      b.pushClipRect(
        page.clip?.intersect(tile.rect) ?? tile.rect,
        clipBehavior: Clip.hardEdge,
      );
      b.pushBackdropFilter(filter, blendMode: page.blendMode);
      b.pop();
      b.pop();
      b.pop();
      b.pop();
    }
    final scene = b.build();
    final image = scene.toImageSync(width, height);
    scene.dispose();
    for (final tile in tiles) {
      final id = tile.copy.read.lead.id;
      _held[id]?._dispose();
      _held[id] = PageCopy._(
        image.clone(),
        tile.rect,
        tile.offset,
        tile.grid,
        tile.holdsFrost,
        tile.copy.read.frostLeftOut,
      );
    }
    image.dispose();
  }

  // Lets go of the pages of leads [keep] does not name.
  void retain(Set<Object> keep) {
    _held.removeWhere((id, page) {
      if (keep.contains(id)) return false;
      page._dispose();
      return true;
    });
  }

  void dispose() => retain(const {});
}

/// Draws a frame's [Plan]: every route of the frame is a value in there.
// Keys of the frame's live groups, the same ones every frame, so a plan that
// holds adds nothing to the scene again.
final _liveKeys = <BackdropKey>[];

BackdropKey? _liveKeyOf(Read read) {
  final group = read.liveGroup;
  if (group == null) return null;
  while (_liveKeys.length <= group) {
    _liveKeys.add(BackdropKey());
  }
  return _liveKeys[group];
}

@internal
final class GlassEmit {
  final _pages = _Pages();

  /// Tells each site of [form] its fate and draws what the reads need before
  /// the scene is built, deepest last, so what a page holds is drawn by then.
  void emit(Plan plan, Form form, double devicePixelRatio) {
    final reads = plan.reads;
    var deepest = 0;
    final keep = Set<Object>.identity();
    for (final read in reads) {
      if (read.source is! LiveRead) {
        read.output = ReadCopy.of(read, plan, form, devicePixelRatio);
      }
      if (read.source is ImageRead) keep.add(read.lead.id);
      deepest = max(deepest, read.level);
    }
    _pages.retain(keep);
    for (var i = 0; i < plan.fates.length; i++) {
      form.siteNodes[i].site.beginFate(plan.fates[i]);
    }
    // What the pages hold reads the mattes paint and the fates wrote.
    FlutterGpuGeometryRenderer.flushPendingSubmissions();
    for (var level = 0; level <= deepest; level++) {
      final tiles = <_Tile>[];
      for (final read in reads) {
        if (read.level != level) continue;
        if (read.source case ImageRead(:final held)) {
          final page = _pages.held(read);
          final copy = read.output! as ReadCopy;
          if (held && page != null && page._grid == copy._grid) continue;
          tiles.add(_tileOf(read, form));
        }
      }
      if (tiles.isNotEmpty) _pages.draw(tiles);
      for (final read in reads) {
        if (read.level != level) continue;
        final lead = form.siteNodes[read.lead.index].site;
        switch (read.source) {
          case SceneRead():
            lead.showScene(read, read.output! as ReadCopy);
          case ImageRead():
            lead.showPage(read, _pages.held(read)!);
          case LiveRead():
            lead.showLive(_liveKeyOf(read));
        }
      }
    }
  }

  _Tile _tileOf(Read read, Form form) {
    final copy = read.output! as ReadCopy;
    final grid = copy._grid;
    final room = read.imageRect ?? read.band;
    final rect = grid._snapOut(room).intersect(form.screen);
    return _Tile(copy, read.lead.look.page ?? PageFilter.none, rect, grid);
  }

  /// Lets go of what the frame's reads hold.
  void dispose() => _pages.dispose();
}
