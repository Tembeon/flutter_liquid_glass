import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/composer/glass_form.dart';
import 'package:liquid_glass_renderer/src/painting/glass_work.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/plan/rects.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart'
    show InPlaceFrost, frostInPlace;
import 'package:liquid_glass_renderer/src/rendering/copy_levels.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_read.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_site.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';

/// What the copies drew, counted for tests.
@internal
abstract final class GlassCopies {
  /// How many images were drawn.
  @visibleForTesting
  static int debugImagesDrawn = 0;

  /// How many filtered layers the copies were drawn in.
  @visibleForTesting
  static int debugBlurLayers = 0;
}

/// What lies under one read of a frame, drawn again from the frame's own
/// layers: the layer tree before the read's lead, in the read's footprint.
///
/// The read's filter reads it: Impeller renders it into a target of its render
/// target cache, ahead of the frame's pass in the frame's one submission, and
/// draws the filter's output straight into the pass. The text in the copy is
/// the frame's own, sharing its glyph atlas and its text shadow cache, which an
/// image drawn between frames empties.
@internal
final class ReplayedCopy implements ReadCopy {
  /// The copy of [read], replayed from the layers of the frame a form
  /// lowered, under the frame's plan.
  ReplayedCopy(this.read, this._plan, this._form);

  @override
  final GlassRead read;

  final GlassPlan _plan;
  final GlassForm _form;

  @override
  CornerRead? cornerOf(GlassRead held) => switch (CornerPlace.heldIn(
    held.layout,
    read.layout,
  )) {
    final place? => CornerRead(ReplayedCopy(held, _plan, _form), place),
    null => null,
  };

  @override
  void addTo(
    ui.SceneBuilder builder,
    CornerPlace place,
    Rect within,
    HeldLayers held,
  ) {
    builder.pushClipRect(place.copyIn(within), clipBehavior: Clip.hardEdge);
    _replay(builder, place, place.copyOrigin, held);
    builder.pop();
  }

  // Adds the glass of [site] if this copy holds its read.
  void _addHeld(PlanSite site, SceneOut out) {
    final facts = switch (site.walk) {
      SiteNode(:final facts) => facts,
      _ => null,
    };
    if (facts == null || facts.index >= _plan.fates.length) return;
    final fate = _plan.fates[facts.index];
    if (fate is LeadFate && read.holds.contains(fate.read)) {
      site.addOutput(out, this);
    }
  }

  void _replay(
    ui.SceneBuilder builder,
    CopyPlace place,
    Offset origin,
    HeldLayers held,
  ) {
    final out = SceneOut(
      builder,
      place.deviceToCopy(origin),
      held,
      flat: read.flat,
    );
    final rect = place.layout.view.logical(place.replayed);
    final top = _form.top;
    if (top is OpenNode) _Replay(out, this, rect).from(top);
    out.finish();
  }
}

// Adds what lies before a read's lead in a rect of the screen. Stops at the
// lead: past it, nothing of the frame lies under the glass.
final class _Replay {
  _Replay(this.out, this.copy, this.footprint) : stop = copy.read.lead.order;

  final SceneOut out;
  final ReplayedCopy copy;
  final Rect footprint;
  final int stop;

  void from(OpenNode top) {
    out.mark();
    top.enter(out, footprint);
    children(top);
    out.leave();
  }

  // False once the replay reached the lead.
  bool children(OpenNode node) {
    final read = copy.read;
    final parts = read.members.length > 1 && read.layout.room == null
        ? read.members
        : null;
    for (var child = node.first; child != null; child = child.next) {
      if (child.order >= stop) return false;
      switch (child) {
        case PictureNode(:final screen):
          final layer = child.layer as PictureLayer;
          // Glass moved its shadows into its slot this frame.
          if (!identical(layer.parent, node.layer)) continue;
          if (layer.picture == null || !meets(screen, footprint)) continue;
          if (parts != null && !parts.any((m) => meets(screen, m.ask.reads))) {
            continue;
          }
          if (!kReleaseMode) GlassWork.replayed++;
          out.picture(layer.picture!);
        case OutputNode(:final site?):
          copy._addHeld(site, out);
        case OutputNode():
          break;
        case VolatileNode(
          kind: VolatileKind.texture,
          layer: final TextureLayer texture,
          :final screen,
        ):
          if (meets(screen, footprint)) out.texture(texture);
        case VolatileNode() || ForeignNode():
          break;
        case final SiteNode site:
          if (!site.holdsComposed &&
              site.end <= stop &&
              !meets(site.bounds, footprint)) {
            continue;
          }
          out.mark();
          site.enter(out, footprint);
          if (site.site.outputsInPlace) copy._addHeld(site.site, out);
          final through = site.site.drawsOwnChildren
              ? site.end <= stop
              : children(site);
          out.leave();
          if (!through) return false;
        case final OpenNode open:
          if (!open.holdsComposed &&
              open.end <= stop &&
              !meets(open.bounds, footprint)) {
            continue;
          }
          if (_addHeld(open, parts)) continue;
          out.mark();
          open.enter(out, footprint);
          final through = children(open);
          out.leave();
          if (!through) return false;
      }
    }
    return true;
  }

  // Adds [open] as one layer the reader keeps between scenes, while it holds
  // no glass and nothing in it changed: a scroll moves rows, not what lies in
  // them. False where it has to be walked.
  bool _addHeld(OpenNode open, List<SiteFacts>? parts) {
    final layers = out.held;
    if (open.holdsComposed ||
        open.drawnByKind ||
        open.contentAt == copy._form.frame ||
        layers.holds(open) ||
        open.end - open.order < _heldLayers) {
      return false;
    }
    if (parts != null && !parts.any((m) => meets(open.bounds, m.ask.reads))) {
      return true;
    }
    final moves = open is ShiftNode;
    out.mark();
    if (moves) open.enter(out, footprint);
    out.settle();
    final builder = out.builder;
    if (layers.take(open, open.contentAt) case final held?) {
      builder.addRetained(held);
    } else {
      layers.keep(open, open.contentAt, builder.pushOffset(0, 0));
      final inner = SceneOut(builder, null, layers);
      if (!moves) open.enter(inner, Rect.largest);
      _addWhole(open, inner);
      inner.finish();
      builder.pop();
    }
    out.leave();
    return true;
  }

  // All that [node] holds, wherever it lies now: the next frames' reads keep it
  // as it moves into them.
  void _addWhole(OpenNode node, SceneOut out) {
    for (var child = node.first; child != null; child = child.next) {
      switch (child) {
        case PictureNode(:final picture?):
          if (!kReleaseMode) GlassWork.replayed++;
          out.picture(picture);
        case final OpenNode open:
          out.mark();
          open.enter(out, Rect.largest);
          _addWhole(open, out);
          out.leave();
        default:
          break;
      }
    }
  }
}

// Fewer layers than this add no fewer calls to a scene held than walked: an
// offset and its picture take as many as an offset and a held layer.
const _heldLayers = 3;

final class _Tile {
  _Tile(this.copy, this.imageRead)
    : _pixels = ImagePlace.reservedOf(copy.read.layout);

  final ReplayedCopy copy;
  final ImageReadFilter imageRead;
  final (int, int) _pixels;

  ReadLayout get layout => copy.read.layout;
  Rect get rect => layout.imageRect!;

  int get width => _pixels.$1;
  int get height => _pixels.$2;

  // The copy and the levels under it, from its top left.
  Size get reserved => Size(width.toDouble(), height.toDouble());

  // Set once packed.
  late ImagePlace place;

  Offset get offset => place.at;
  Rect get bounds => place.bounds;

  bool get filtered => imageRead is! PlainImage;

  bool get layered => layout.imageFilterBlurs;

  late final InPlaceFrost inPlace = frostInPlace(place);

  late final CopyLevelPasses? levels = switch (place.levels) {
    final strip? => CopyLevelPasses.of(strip, Offset.zero),
    null => null,
  };
}

// Every image drawn on its own costs the raster thread a render pass, a
// texture and a command buffer, and the GPU driver a submission.
final class _ImageCopies {
  // Sampling between pixels at a copy's edge reads no neighbour.
  static const int _gap = 2;
  static const int _rowWidth = 2048;
  static const int _maxHeight = 4096;

  // The copies' blurs, held across frames: dart:ui converts each new filter
  // to a native one again.
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

  final _held = Map<Object, ImageCopy>.identity();

  // What the images keep of the frame between the scenes they are drawn from.
  final _layers = HeldLayers();

  ImageCopy? held(GlassRead read) => _held[read.lead.id];

  // Draws [tiles], which hold no glass one of them reads from an image not yet
  // drawn.
  void draw(List<_Tile> tiles) {
    final runs = <Object?, List<_Tile>>{};
    for (final tile in tiles) {
      runs
          .putIfAbsent(
            !tile.filtered
                ? null
                : (tile.imageRead.key, tile.layout.share, tile.layered),
            () => [],
          )
          .add(tile);
    }
    _pack(runs.values.toList());
  }

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
        tile.place = ImagePlace(
          tile.layout,
          Offset(x.toDouble(), y.toDouble()),
        );
        tiles.add(tile);
        x += tile.width + _gap;
        if (x - _gap > width) width = x - _gap;
        if (tile.height > row) row = tile.height;
      }
      start += tiles.length;
      _draw(tiles, width, y + row);
    }
  }

  void _draw(List<_Tile> tiles, int width, int height) {
    if (!kReleaseMode) GlassWork.images++;
    GlassCopies.debugImagesDrawn++;
    final b = ui.SceneBuilder();
    void add(_Tile tile, Rect within) {
      b.pushClipRect(within, clipBehavior: Clip.hardEdge);
      tile.copy._replay(b, tile.place, tile.offset, _layers);
      b.pop();
    }

    final isolated = <_Tile>[];
    final layered = <(Object?, int), List<_Tile>>{};
    for (final tile in tiles) {
      if (!tile.filtered) {
        final filter = tile.inPlace.filter;
        final levels = tile.levels;
        if (filter == null && levels == null) {
          add(tile, tile.bounds);
        } else {
          final size = tile.bounds.size;
          b.pushOffset(tile.offset.dx, tile.offset.dy);
          drawThroughCopyPasses(
            b,
            origin: Offset.zero,
            levels: levels,
            levelSize: tile.reserved,
            blur: null,
            frost: filter,
            copySize: size,
            draw: () {
              b.pushClipRect(Offset.zero & size, clipBehavior: Clip.hardEdge);
              tile.copy._replay(b, tile.place, Offset.zero, _layers);
              b.pop();
            },
          );
          b.pop();
        }
      } else if (tile.layered) {
        layered
            .putIfAbsent((tile.imageRead.key, tile.layout.share), () => [])
            .add(tile);
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
      b
        ..pushClipRect(bounds, clipBehavior: Clip.hardEdge)
        // Impeller takes an image filter's sigmas in the pixels it draws
        // into, whatever the canvas scale: here the copies' own.
        ..pushImageFilter(switch (first.imageRead) {
          BlurredImage(:final x, :final y) => _blur(
            x * first.layout.pixels,
            y * first.layout.pixels,
          ),
          _ => throw StateError('Images blurred alike are blurred.'),
        });
      for (final tile in group) {
        add(tile, tile.bounds);
      }
      b
        ..pop()
        ..pop();
    }
    // A copy's own filter stands under the view's scale, as the backdrop
    // filter it replaces does. In a layer around its copy it reads that layer
    // alone; drawn straight into the image, Impeller blurs the whole image.
    for (final tile in isolated) {
      final imageRead = tile.imageRead;
      final filter = switch (imageRead) {
        FilteredImage(:final filter) => filter,
        BlurredImage(:final x, :final y) => _blur(x, y),
        PlainImage() => throw StateError('A plain image is not filtered.'),
      };
      b.pushClipRect(tile.bounds, clipBehavior: Clip.antiAliasWithSaveLayer);
      add(tile, tile.bounds);
      b
        ..pushTransform(tile.place.screenToImage.storage)
        ..pushClipRect(
          imageRead.clip?.intersect(tile.rect) ?? tile.rect,
          clipBehavior: Clip.hardEdge,
        )
        ..pushBackdropFilter(filter, blendMode: imageRead.blendMode)
        ..pop()
        ..pop()
        ..pop()
        ..pop();
    }
    final scene = b.build();
    final image = scene.toImageSync(width, height);
    scene.dispose();
    for (final tile in tiles) {
      final id = tile.copy.read.lead.id;
      _held[id]?.image.dispose();
      _held[id] = ImageCopy(
        image.clone(),
        tile.place,
        tile.filtered ? 0 : tile.inPlace.sigma,
      );
    }
    image.dispose();
  }

  void retain(Set<Object> keep) {
    _held.removeWhere((id, copy) {
      if (keep.contains(id)) return false;
      copy.image.dispose();
      return true;
    });
  }

  /// The frame's images are drawn.
  void drawn() => _layers.built();

  void dispose() {
    retain(const {});
    _layers.dispose();
  }
}

/// Draws a frame's [GlassPlan]: every route of the frame is a value in there.
@internal
final class GlassEmit {
  final _imageCopies = _ImageCopies();

  final _backdropKeys = <BackdropKey>[];

  BackdropKey? _backdropKeyOf(GlassRead read) {
    final group = read.backdropGroup;
    if (group == null) return null;
    while (_backdropKeys.length <= group) {
      _backdropKeys.add(BackdropKey());
    }
    return _backdropKeys[group];
  }

  /// Tells each site of [form] its fate and draws what the reads need before
  /// the scene is built, deepest last, so what a copy holds is drawn by then.
  ///
  /// [again] shows a plan an earlier frame emitted: the images it bought are
  /// drawn already.
  void emit(GlassPlan plan, GlassForm form, {required bool again}) {
    final reads = plan.reads;
    var deepest = 0;
    final keep = Set<Object>.identity();
    for (final read in reads) {
      if (read.source is ImageRead) keep.add(read.lead.id);
      deepest = max(deepest, read.level);
    }
    _imageCopies.retain(keep);
    for (var i = 0; i < plan.fates.length; i++) {
      form.siteNodes[i].site.beginFate(plan.fates[i]);
    }
    FlutterGpuGeometryRenderer.flush();
    for (var level = 0; level <= deepest; level++) {
      final tiles = <_Tile>[];
      for (final read in reads) {
        if (read.level != level) continue;
        if (read.source case ImageRead(:final held)) {
          if ((held || again) && _imageCopies.held(read) != null) continue;
          tiles.add(
            _Tile(
              ReplayedCopy(read, plan, form),
              read.lead.ask.look.imageRead ?? const PlainImage(),
            ),
          );
        }
      }
      if (tiles.isNotEmpty) _imageCopies.draw(tiles);
      for (final read in reads) {
        if (read.level != level) continue;
        form.siteNodes[read.lead.index].site.show(read, switch (read.source) {
          SceneRead() => ScenePixels(
            CornerRead.inFrame(ReplayedCopy(read, plan, form)),
          ),
          ImageRead() => ImagePixels(_imageCopies.held(read)!),
          BackdropRead() => BackdropPixels(_backdropKeyOf(read)),
        });
      }
    }
    _imageCopies.drawn();
  }

  /// Lets go of what the frame's reads hold.
  void dispose() => _imageCopies.dispose();
}
