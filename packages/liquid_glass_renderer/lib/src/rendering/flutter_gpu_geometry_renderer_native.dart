import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The edge distance of a geometry atlas's outside tile and of its texels
/// far from every shape: `kFarInward` in `matte_encoding.glsl`.
@internal
const double kFarInward = -4096;

/// The edge distance of a geometry atlas's deep tile: past every inward
/// reach, and within a 16-bit float.
@internal
const double kDeepInward = 4096;

/// Floats per instance of tile_vertex.glsl: rectangle, value and ramp.
const int _quadFloats = 12;

/// What an atlas pass writes beside the atlas, by [Tiling.looks]: no look,
/// the tint, or the whole look (look_targets.glsl).
enum _LookTargets {
  none(0, ''),
  tint(1, 'Tint'),
  all(3, 'Looks');

  const _LookTargets(this.count, this.shaderSuffix);

  factory _LookTargets.of(ShapeLooks? looks) => switch (looks) {
    null => none,
    ShapeLooks(tintOnly: true) => tint,
    _ => all,
  };

  /// The look textures written.
  final int count;

  /// What the atlas shaders' names end in, before `Fragment`.
  final String shaderSuffix;
}

const _tileVertexLayout = gpu.VertexLayout(
  buffers: [
    gpu.VertexBuffer(
      strideInBytes: 8,
      attributes: [
        gpu.VertexAttribute(name: 'corner', format: gpu.VertexFormat.float32x2),
      ],
    ),
    gpu.VertexBuffer(
      strideInBytes: _quadFloats * 4,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        gpu.VertexAttribute(name: 'rect', format: gpu.VertexFormat.float32x4),
        gpu.VertexAttribute(
          name: 'value',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 16,
        ),
        gpu.VertexAttribute(
          name: 'ramp',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
      ],
    ),
  ],
);

/// Renders liquid glass geometry atlases (geometry_tiling.dart) and the
/// looks beside them using flutter_gpu.
///
/// The atlases placed between two flushes share a page: one texture, drawn
/// in one pass and submitted once ([flush]). A renderer holds one atlas,
/// its latest, and with it the page: nothing draws over a page while a
/// renderer holds an atlas in it, nor for [reuseAfterFrames] frames after,
/// while the scenes that read it may still be drawn.
///
/// The image handles are the pages', disposed once every atlas of a page
/// is released. Recorded scenes hold independent native references; a
/// scene rasterized more than [reuseAfterFrames] frames after its atlas was
/// released may show other atlases.
@internal
class FlutterGpuGeometryRenderer {
  factory FlutterGpuGeometryRenderer._fromResolved(
    String assetKey,
    _SharedGeometryResources resources,
  ) {
    try {
      return FlutterGpuGeometryRenderer._fromShared(resources);
    } on Object {
      // Drop resources that failed to build a renderer so the next layer
      // reloads the bundle instead of failing the same way.
      if (identical(_resolvedAssetResources[assetKey], resources)) {
        _resolvedAssetResources.remove(assetKey);
      }
      rethrow;
    }
  }

  FlutterGpuGeometryRenderer._fromShared(this._resources)
    : assert(() {
        _debugActiveRendererCount++;
        return true;
      }(), 'Track live geometry renderers in debug builds.');

  /// The class of the GPU the Flutter GPU context runs on. Flutter GPU
  /// names no backend, so it is read from capabilities: rendering into a
  /// mip level is not implemented on GLES yet, and ASTC HDR starts at the
  /// A13 (Apple6). A renderer exists only once the engine has created the
  /// context; reading it earlier blocks the UI thread on Android.
  LiquidGlassDeviceClass get deviceClass {
    final context = gpu.gpuContext;
    if (!context.doesSupportFramebufferRenderMipmap) {
      // Only an Android device without a usable Vulkan driver is short of
      // GPU on OpenGL ES; a desktop has plenty.
      return Platform.isAndroid
          ? LiquidGlassDeviceClass.gles
          : LiquidGlassDeviceClass.capable;
    }
    if (Platform.isIOS &&
        !context.supportsTextureCompression(
          gpu.TextureCompressionFamily.astcHdr,
        )) {
      return LiquidGlassDeviceClass.appleBeforeA13;
    }
    return LiquidGlassDeviceClass.capable;
  }

  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) async {
    if (_resolvedAssetResources[assetKey] case final resources?) {
      return FlutterGpuGeometryRenderer._fromResolved(assetKey, resources);
    }
    final resourcesFuture = _assetResources[assetKey] ??= () async {
      final library = await gpu.ShaderLibrary.fromAsset(assetKey);
      gpu.Shader shader(String name) =>
          library?[name] ??
          (throw StateError(
            'LiquidGlass requires Flutter GPU. Run with Flutter 3.47 or newer '
            'and enable Flutter GPU for the target platform.',
          ));
      return _SharedGeometryResources(shader);
    }();
    try {
      final resources = await resourcesFuture;
      final renderer = FlutterGpuGeometryRenderer._fromShared(resources);
      _resolvedAssetResources[assetKey] = resources;
      if (identical(_assetResources[assetKey], resourcesFuture)) {
        unawaited(_assetResources.remove(assetKey));
      }
      return renderer;
    } on Object {
      // Forget the failed load so a later layer retries it instead of
      // awaiting the same failed Future.
      if (identical(_assetResources[assetKey], resourcesFuture)) {
        unawaited(_assetResources.remove(assetKey));
      }
      rethrow;
    }
  }

  /// Synchronously builds a renderer from already resolved shared resources.
  ///
  /// Returns null when [fromAsset] has not resolved [assetKey] yet, or when
  /// the build fails, so callers can fall back to the asynchronous path.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) {
    final resources = _resolvedAssetResources[assetKey];
    if (resources == null) return null;
    try {
      return FlutterGpuGeometryRenderer._fromResolved(assetKey, resources);
    } on Object {
      return null;
    }
  }

  static final Map<String, Future<_SharedGeometryResources>> _assetResources =
      {};
  static final Map<String, _SharedGeometryResources> _resolvedAssetResources =
      {};

  /// One bump allocator for every page drawn in the current frame.
  ///
  /// A HostBuffer retains four device-buffer blocks, so one per renderer
  /// would cost four blocks per layer. A single scratch sized for a frame of
  /// draws keeps that off the native heap.
  static gpu.HostBuffer? _sharedHostBuffer;
  static int _sharedHostBufferBlockLength = 0;
  static Duration? _sharedHostBufferFrame;

  static const int _hostBufferSlotsPerFrame = 32;

  static final _VertexScratch _vertexScratch = _VertexScratch();

  // These ownership counters exclude clones held by callers and native
  // references retained by submitted scenes; they are not GPU memory metrics.
  static int _debugActiveRendererCount = 0;
  static int _debugActiveGeometryTextureCount = 0;
  static int _debugTotalRenderCount = 0;

  /// Counts atlases drawn across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  /// Renderers that hold an atlas.
  @visibleForTesting
  static int get debugActiveGeometryTextureCount =>
      _debugActiveGeometryTextureCount;

  static gpu.HostBuffer _hostBufferForUniformSize(int uniformSize) {
    final alignment = gpu.gpuContext.minimumUniformByteAlignment;
    final alignedSize =
        ((uniformSize + alignment - 1) ~/ alignment) * alignment;
    final blockLength = alignedSize * _hostBufferSlotsPerFrame;
    if (_sharedHostBuffer == null ||
        _sharedHostBufferBlockLength < blockLength) {
      _sharedHostBuffer = gpu.gpuContext.createHostBuffer(
        blockLengthInBytes: blockLength,
      );
      _sharedHostBufferBlockLength = blockLength;
    }
    // Unlike currentFrameTimeStamp this is defined outside a frame, where
    // tests call the renderer directly, and changes once per engine frame.
    final timestamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_sharedHostBufferFrame != timestamp) {
      _sharedHostBuffer!.reset();
      _sharedHostBufferFrame = timestamp;
    }
    return _sharedHostBuffer!;
  }

  final _SharedGeometryResources _resources;
  final _FieldTextures _fieldTextures = _FieldTextures();

  // The page holding the latest atlas, which it keeps from being drawn over.
  _Page? _page;
  ui.Image? _atlasImage;
  List<ui.Image> _lookImages = const [];
  AtlasPlace? _atlasPlace;

  @visibleForTesting
  Object get debugPipelineIdentity => _resources.pipelines.first.geometry;

  @visibleForTesting
  int get debugHostBufferBlockLength => _sharedHostBufferBlockLength;

  @visibleForTesting
  Object? get debugHostBufferIdentity => _sharedHostBuffer;

  /// Number of atlases rendered.
  @visibleForTesting
  int debugRenderCount = 0;

  @visibleForTesting
  bool get debugDisposed => _disposed;

  bool _disposed = false;

  // The corners of the unit square as two triangles, which every quad of
  // every atlas is an instance of.
  static gpu.BufferView? _corners;

  /// The latest geometry atlas, in the page it shares.
  ui.Image? get atlasImage => _atlasImage;

  /// The looks beside the latest atlas: none, the tint, or tint, response
  /// and color model shares.
  List<ui.Image> get lookImages => _lookImages;

  /// Where the latest atlas lies in [atlasImage].
  AtlasPlace? get atlasPlace => _atlasPlace;

  /// How many shapes the latest atlas left out: past
  /// [geometryMaxShapesPerDraw] reaching one tile (Tiling.droppedShapes).
  int droppedShapes = 0;

  /// Places the geometry atlas of [tiling] (geometry_tiling.dart) in the
  /// page of this frame: the constant tiles, the table and every ring
  /// strip, the strips evaluating the tiling's shapes, or its field. With
  /// [Tiling.looks] the page holds each texel's look beside it, in textures
  /// of its size.
  ///
  /// Table texels hold their tile's entry in x and y, the strip's texels a
  /// pixel in z (0 for a constant tile) and 1 in w. The page is drawn by
  /// [flush]: at once outside a frame, else once for every atlas of the
  /// frame, before its scene is built.
  ///
  /// The images are the page's: do not dispose them. This renderer keeps
  /// the page from being drawn over until it renders another atlas or
  /// releases this one. The images are disposed once every atlas of the
  /// page is released; a clone lives on, and [reuseAfterFrames] frames
  /// later may show other atlases.
  ({ui.Image image, List<ui.Image> looks, AtlasPlace place}) renderAtlas(
    Tiling tiling,
  ) {
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    _ensureFrameCounter();
    assert(
      tiling.layout.height <= AtlasLayout.maxSize,
      'A geometry atlas outgrew ${AtlasLayout.maxSize} rows at an inward '
      'reach of 1.',
    );
    final pages = _resources.pages[_LookTargets.of(tiling.looks).index];
    final (page, place) = pages.add(tiling, _fieldTextures);
    page.leases++;
    releaseAtlas();
    _page = page;
    assert(() {
      _debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track held geometry atlases in debug builds.');
    droppedShapes = tiling.droppedShapes;
    if (_deferring) {
      assert(() {
        debugDeferredPassCount++;
        return true;
      }(), 'Count deferred atlases in debug builds.');
      _flushAfterFrame();
    } else {
      flush();
    }
    return (
      image: _atlasImage = page.image,
      looks: _lookImages = page.lookImages,
      place: _atlasPlace = place,
    );
  }

  /// Lets go of the latest atlas: its page is drawn over once no renderer
  /// holds an atlas in it. Its images are not to be drawn with after this.
  void releaseAtlas() {
    final page = _page;
    if (page == null) return;
    _page = null;
    _atlasImage = null;
    _lookImages = const [];
    _atlasPlace = null;
    page.owner.release(page);
    assert(() {
      _debugActiveGeometryTextureCount--;
      return true;
    }(), 'Track released geometry atlases in debug builds.');
  }

  // A copy recorded before a render pass on the same command buffer is
  // encoded ahead of it on Vulkan and GLES. Metal opens a blit encoder when
  // the copy is recorded and closes it only on submit, so the render pass's
  // encoder would nest: there the copy gets its own command buffer,
  // submitted first.
  static final bool _uploadsShareCommandBuffer =
      !(Platform.isIOS || Platform.isMacOS);

  // The pages with atlases placed and not yet drawn.
  static final List<_Pages> _openPages = [];
  static bool _postFrameFlushScheduled = false;

  /// Pages drawn and submitted by [flush].
  @visibleForTesting
  static int debugBatchedSubmitCount = 0;

  /// Flushes left to the post-frame safety net because no glass layer of the
  /// frame's scene flushed first.
  @visibleForTesting
  static int debugPostFrameFlushCount = 0;

  /// Atlases placed in a page that a later [flush] drew.
  @visibleForTesting
  static int debugDeferredPassCount = 0;

  // Only the paint and compositing phases are followed by a scene build that
  // flushes before the scene reaches the raster thread.
  static bool get _deferring =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  // Covers atlases whose layer was painted but not composited.
  static void _flushAfterFrame() {
    if (_postFrameFlushScheduled) return;
    _postFrameFlushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameFlushScheduled = false;
      if (_openPages.isEmpty) return;
      assert(() {
        debugPostFrameFlushCount++;
        return true;
      }(), 'Count safety-net flushes in debug builds.');
      flush();
    });
  }

  /// Draws the pages holding the atlases placed since the last flush, each
  /// in one pass, and submits them.
  ///
  /// The composer calls this while the scene is built, which is before the
  /// scene is handed to the raster thread, so every atlas a scene samples
  /// has been submitted ahead of it on the GPU queue. A post-frame callback
  /// flushes atlases of layers that were painted but not composited.
  static void flush() {
    if (_openPages.isEmpty) return;
    final open = List.of(_openPages);
    _openPages.clear();
    for (final pages in open) {
      pages.flush();
    }
  }

  /// Forgets the size the pages grew to and drops the spares, as a new
  /// process starts. Where an atlas lies in its page moves a pixel's last
  /// bit, so a test that compares pixels starts from here, whatever ran
  /// before it.
  @visibleForTesting
  static void debugResetPages() {
    flush();
    for (final resources in _resolvedAssetResources.values) {
      for (final pages in resources.pages) {
        pages.reset();
      }
    }
  }

  /// Frames to wait after a page's last atlas is released before drawing
  /// into it again.
  ///
  /// A page released in frame E was last read by frame E - 1. The engine's
  /// two-frame pipeline (`Animator.FramePipeline(2)`) submits that scene before
  /// frame E + 1 paints. Flutter GPU uses the same queue, which orders the next
  /// write after those reads (Metal/Vulkan hazards; GLES posting order).
  static const int reuseAfterFrames = 1;

  static int _completedFrames = 0;
  static bool _countingFrames = false;

  /// Counts scene-submitting frames for page reuse.
  ///
  /// Renders outside a frame, as in unit tests, do not advance the count,
  /// so their pages are never reused.
  static void _ensureFrameCounter() {
    if (_countingFrames) return;
    _countingFrames = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
    });
  }

  /// The texture of the page holding the latest atlas, compared by identity
  /// in tests.
  @visibleForTesting
  Object? get debugMatteTexture => _page?.texture;

  /// Size of the page holding the latest atlas.
  @visibleForTesting
  (int, int)? get debugMatteTextureSize => switch (_page) {
    final page? => (page.width, page.height),
    null => null,
  };

  /// Pages drawn into a texture kept from an earlier one instead of a new
  /// one.
  @visibleForTesting
  static int debugReusedTextureCount = 0;

  /// Textures allocated, pages and their looks.
  @visibleForTesting
  static int debugAllocatedTextureCount = 0;

  /// Textures dropped. Once a texture has lived a few young GCs its wrapper
  /// is promoted, and dropping it pins its storage until an old-generation
  /// GC.
  @visibleForTesting
  static int debugDroppedTextureCount = 0;

  /// Releases the latest atlas and the field textures, keeping the
  /// pipelines.
  ///
  /// Callers retaining an output must clone its images before calling this.
  /// Independent clones and submitted native scenes remain valid.
  void releaseOutput() {
    releaseAtlas();
    _fieldTextures.release();
  }

  /// Releases the current output and retires this renderer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releaseOutput();
    assert(() {
      _debugActiveRendererCount--;
      return true;
    }(), 'Track disposed geometry renderers in debug builds.');
  }
}

/// What a draw of a field atlas binds besides the shapes.
final class _FieldDraw {
  const _FieldDraw(this.uniforms, this.texture);

  final gpu.BufferView uniforms;
  final gpu.Texture texture;
}

/// A run of a page's quads: where the run starts and how many it has, the
/// block its shapes are read from where the pipeline reads shapes, and what
/// the field pipeline binds where the run is a field's.
typedef _Draw = ({
  int first,
  int count,
  gpu.BufferView? shapes,
  _FieldDraw? field,
});

/// The pages of the atlases that write one set of looks: every atlas placed
/// between two flushes shares one texture and is drawn in one pass, with one
/// submission, since each pass and each submission costs the UI thread
/// more than an atlas's quads do.
///
/// An atlas is placed when it is asked for: below the ones before it, laid
/// out to the page's width ([Tiling.layoutIn]), its quads written for the
/// page's size. So its image and its place are known at once, and [flush]
/// only draws. Atlases that outgrow the page go to a second one, drawn in a
/// pass of its own, and the pages grow to hold a flush like this one.
///
/// A pass clears and stores its whole target on a tiled GPU, and a texture
/// dropped may stay allocated until an old-generation GC. So every page
/// has one size, an eighth taller than the fullest flush needed, which
/// changes only when a flush outgrows it, at once, or once [_shrinkAfter]
/// flushes in a row would have fit in half of it. A page no renderer holds
/// an atlas in is a spare for later flushes, up to [_maxSpares] of them: a
/// page drawn every frame alternates between two.
final class _Pages {
  _Pages({
    required this._pipelines,
    required this._offsets,
    required int uniformSize,
    required this._fieldOffsets,
    required int fieldUniformSize,
    required this._lookCount,
  }) : _uniformSize = uniformSize,
       _uniformData = ByteData(uniformSize),
       _fieldUniformData = ByteData(fieldUniformSize);

  static const int _maxSpares = 3;
  static const int _shrinkAfter = 30;

  final _TilePipelines _pipelines;
  final _GeometryUniformOffsets _offsets;
  final _TileFieldUniformOffsets _fieldOffsets;
  final int _uniformSize;
  final int _lookCount;

  // The block the quads written next read, in rows of one shape or look.
  final ByteData _uniformData;
  late final Float32List _uniformFloats = _uniformData.buffer.asFloat32List();
  final ByteData _fieldUniformData;
  int _blockRows = 0;

  final _AtlasQuads _quads = _AtlasQuads();
  final List<_Draw> _draws = [];
  int _drawFrom = 0;
  _FieldDraw? _field;

  _Page? _open;
  final List<_Page> _spares = [];

  // The size of the pages.
  int _width = 0;
  int _height = 0;
  // What this flush has placed: the texels of its atlases, each laid out
  // on its own, and the widest of them; and how many of those texels are
  // in pages it has drawn already.
  int _texels = 0;
  int _widest = 0;
  int _drawnTexels = 0;
  // How many flushes in a row have filled no more than half a page, and
  // the most they placed.
  int _slack = 0;
  int _slackTexels = 0;
  int _slackWidest = 0;
  int _slackRows = 0;

  gpu.HostBuffer get _hostBuffer =>
      FlutterGpuGeometryRenderer._hostBufferForUniformSize(_uniformSize);

  /// Places the atlas of [tiling] in the open page and writes its quads.
  (_Page, AtlasPlace) add(Tiling tiling, _FieldTextures fieldTextures) {
    final (page, layout, top) = _place(tiling);
    final quads = _quads..top = top;
    final looks = tiling.looks;
    final field = tiling.field;
    if (field != null) {
      final texture = _fieldTexture(fieldTextures, field.field, page);
      _packFieldUniforms(field, texture);
      _drawWith(_FieldDraw(_hostBuffer.emplace(_fieldUniformData), texture));
    }

    const block = Tiling.size + 2;
    quads.fill(0, 0, block, block, kFarInward, 0, 0, 0);
    for (var look = 0; look < (looks?.count ?? 1); look++) {
      var row = -1;
      if (looks != null) {
        row = _takeRows(1);
        _packLook(looks, look, row);
      }
      quads.fill(
        (look + 1) * block,
        0,
        block,
        block,
        kDeepInward,
        0,
        0,
        0,
        look: row,
      );
    }
    final (tableX, tableY) = AtlasLayout.tableOrigin;
    final deeps = tiling.deeps;
    for (var i = 0; i < deeps.length; i += 5) {
      final (deepX, deepY) = AtlasLayout.deepEntryOf(deeps[i + 4]);
      quads.fill(
        tableX + deeps[i],
        tableY + deeps[i + 1],
        deeps[i + 2],
        deeps[i + 3],
        deepX.toDouble(),
        (top + deepY).toDouble(),
        0,
        1,
      );
    }
    final runs = tiling.runs;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final (entryX, entryY) = layout.entryOf(i, 0);
      quads.fill(
        tableX + run.column,
        tableY + run.row,
        run.length,
        run.tall,
        entryX.toDouble(),
        (top + entryY).toDouble(),
        1 / run.texel,
        1,
      );
    }

    void strip(int i, {required double reach, int base = 0, int count = 0}) {
      final run = runs[i];
      final x = layout.strips[i * 2];
      final y = layout.strips[i * 2 + 1];
      final texel = run.texel;
      quads.strip(
        x,
        y,
        run.length * Tiling.size ~/ texel + 2,
        run.tall * Tiling.size ~/ texel + 2,
        bufferX: (run.column * Tiling.size - (x + 1) * texel).toDouble(),
        bufferY: (run.row * Tiling.size - (top + y + 1) * texel).toDouble(),
        texel: texel,
        reach: reach,
        base: base,
        count: count,
        members: field == null ? run.members : 0,
      );
    }

    if (field != null) {
      // A field takes its looks from its first set of shapes.
      var base = 0;
      var count = 0;
      if (looks != null && runs.isNotEmpty) {
        final members = tiling.shapeSets.first;
        count = math.min(members.length, geometryMaxShapesPerDraw);
        base = _takeRows(count);
        _packShapes(tiling.shapes, members, base, looks);
      }
      for (var i = 0; i < runs.length; i++) {
        strip(i, reach: 0, base: base, count: count);
      }
      _drawWith(null);
    } else {
      for (var set = 0; set < tiling.shapeSets.length; set++) {
        final members = tiling.shapeSets[set];
        final count = math.min(members.length, geometryMaxShapesPerDraw);
        final reach = tiling.reach.outward + _smoothing(tiling.shapes, members);
        var base = -1;
        for (var i = 0; i < runs.length; i++) {
          if (runs[i].shapes != set) continue;
          if (base < 0) {
            base = _takeRows(count);
            _packShapes(tiling.shapes, members, base, looks);
          }
          strip(i, reach: reach, base: base, count: count);
        }
      }
    }
    return (
      page,
      (
        tableX: tableX,
        tableY: top + tableY,
        width: page.width,
        height: page.height,
      ),
    );
  }

  // The open page with room for [tiling], its layout there and its top row.
  (_Page, AtlasLayout, int) _place(Tiling tiling) {
    final own = tiling.layout;
    _texels += own.width * own.height;
    _widest = math.max(_widest, own.width);
    var page = _open;
    if (page != null) {
      final layout = tiling.layoutIn(page.width);
      if (layout != null && page.rows + layout.height <= page.height) {
        final top = page.rows;
        page.rows += layout.height;
        return (page, layout, top);
      }
      // The flush outgrew its page: the atlases so far are drawn now, and
      // the pages from here on have room for them and this one.
      _drawnTexels = _texels - own.width * own.height;
      _draw();
    }
    final layout = _fit(tiling);
    page = _open = _take();
    if (!FlutterGpuGeometryRenderer._openPages.contains(this)) {
      FlutterGpuGeometryRenderer._openPages.add(this);
    }
    _quads.reset(page.width, page.height);
    page.rows = layout.height;
    return (page, layout, 0);
  }

  // The layout of [tiling] at the top of a new page, the pages growing to
  // hold what this flush has placed so far.
  AtlasLayout _fit(Tiling tiling) {
    // Up to twice as tall as wide the pages keep their width, so their
    // textures are replaced less often.
    if (tiling.layoutIn(_width) == null || _texels > 2 * _width * _width) {
      _width = math.min(AtlasLayout.maxSize, _squareWidth(_texels, _widest));
    }
    final layout = tiling.layoutIn(_width)!;
    final rows = layout.height + (_drawnTexels / _width).ceil();
    if (rows > _height) _height = _roomFor(rows);
    return layout;
  }

  // The width of a square page of [texels], no narrower than [widest].
  static int _squareWidth(int texels, int widest) =>
      math.max(widest, (math.sqrt(texels).ceil() + 31) & ~31);

  // A page of the capacity no scene still reads: a spare, or a new one.
  _Page _take() {
    final frame = FlutterGpuGeometryRenderer._completedFrames;
    _spares.removeWhere((spare) {
      if (spare.sized(_width, _height)) return false;
      spare.drop();
      return true;
    });
    final reusable = _spares.indexWhere(
      (spare) =>
          frame - spare.retiredFrame >=
          FlutterGpuGeometryRenderer.reuseAfterFrames,
    );
    if (reusable < 0) {
      return _Page(this, _width, _height, _lookCount)..begin();
    }
    assert(() {
      FlutterGpuGeometryRenderer.debugReusedTextureCount++;
      return true;
    }(), 'Count reused geometry textures in debug builds.');
    return _spares.removeAt(reusable)..begin();
  }

  // An eighth over [rows], in the 16 rows a tiled GPU stores at a time, so
  // atlases that grow a little keep their page's size and its textures.
  static int _roomFor(int rows) =>
      math.min(AtlasLayout.maxSize, (rows + (rows >> 3) + 15) & ~15);

  /// Lets go of one atlas in [page]: once none is held and the page is
  /// drawn, it is a spare.
  void release(_Page page) {
    page.leases--;
    if (page.leases == 0 && !page.open) _retire(page);
  }

  void _retire(_Page page) {
    page
      ..retiredFrame = FlutterGpuGeometryRenderer._completedFrames
      ..disposeImages();
    if (!page.sized(_width, _height)) {
      page.drop();
      return;
    }
    _spares.add(page);
    while (_spares.length > _maxSpares) {
      _spares.removeAt(0).drop();
    }
  }

  /// Draws the open page. Once [_shrinkAfter] flushes in a row have filled
  /// no more than half a page, the pages shrink to the fullest of them.
  void flush() {
    final page = _open;
    if (page == null) return;
    final texels = _texels;
    final widest = _widest;
    final rows = page.rows + (_drawnTexels / _width).ceil();
    _texels = 0;
    _widest = 0;
    _drawnTexels = 0;
    _draw();
    if (_roomFor(rows) * 2 > _height) {
      _slack = 0;
      _slackTexels = 0;
      _slackWidest = 0;
      _slackRows = 0;
      return;
    }
    _slackTexels = math.max(_slackTexels, texels);
    _slackWidest = math.max(_slackWidest, widest);
    _slackRows = math.max(_slackRows, rows);
    if (++_slack < _shrinkAfter) return;
    // Narrower too where the pages would be flatter than two to one.
    if (_roomFor(_slackRows) * 2 < _width) {
      _width = _squareWidth(_slackTexels, _slackWidest);
      _height = _roomFor((_slackTexels / _width).ceil());
    } else {
      _height = _roomFor(_slackRows);
    }
    _slack = 0;
    _slackTexels = 0;
    _slackWidest = 0;
    _slackRows = 0;
  }

  /// Drops the spares and forgets the pages' size.
  void reset() {
    for (final spare in _spares) {
      spare.drop();
    }
    _spares.clear();
    _width = 0;
    _height = 0;
    _slack = 0;
    _slackTexels = 0;
    _slackWidest = 0;
    _slackRows = 0;
  }

  // Draws the open page's quads in one pass and submits it.
  void _draw() {
    final page = _open!;
    _open = null;
    _endDraw();
    try {
      final instances = FlutterGpuGeometryRenderer._vertexScratch.write(
        _quads.bytes,
      );
      final corners = FlutterGpuGeometryRenderer._corners ??= gpu.BufferView(
        gpu.gpuContext.createDeviceBufferWithCopy(
          ByteData.sublistView(
            Float32List.fromList(const [0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1]),
          ),
        ),
        offsetInBytes: 0,
        lengthInBytes: 48,
      );
      final commands = page.commands ?? gpu.gpuContext.createCommandBuffer();
      page.commands = null;
      final pass = commands.createRenderPass(page.renderTarget)
        ..setPrimitiveType(gpu.PrimitiveType.triangle);
      gpu.RenderPipeline? bound;
      for (final draw in _draws) {
        final field = draw.field;
        final pipeline = field == null ? _pipelines.geometry : _pipelines.field;
        if (!identical(pipeline, bound)) {
          // A binding outlives its draw, and a field's would bind over the
          // shapes of the draws after it.
          pass
            ..clearBindings()
            ..bindPipeline(bound = pipeline)
            ..bindVertexBuffer(corners);
        }
        if (field != null) {
          pass
            ..bindUniform(_pipelines.fieldUniforms, field.uniforms)
            ..bindTexture(_pipelines.fieldTexture, field.texture);
        }
        final slot = field == null
            ? _pipelines.geometryShapes
            : _pipelines.fieldShapes;
        if (slot != null) pass.bindUniform(slot, draw.shapes!);
        pass
          ..bindVertexBuffer(
            gpu.BufferView(
              instances.buffer,
              offsetInBytes:
                  instances.offsetInBytes +
                  draw.first * _AtlasQuads.bytesPerQuad,
              lengthInBytes: draw.count * _AtlasQuads.bytesPerQuad,
            ),
            slot: 1,
          )
          ..draw(6, instanceCount: draw.count);
      }
      commands.submit();
      assert(() {
        FlutterGpuGeometryRenderer.debugBatchedSubmitCount++;
        return true;
      }(), 'Count submitted pages in debug builds.');
    } finally {
      _draws.clear();
      _drawFrom = 0;
      page.open = false;
      if (page.leases == 0) _retire(page);
    }
  }

  // The quads written next are drawn with [field], or with the shapes'
  // pipeline.
  void _drawWith(_FieldDraw? field) {
    if (identical(field, _field)) return;
    _endDraw();
    _field = field;
  }

  // Ends the draw of the quads written since the last, which read the
  // block as it is; the quads after them read a new one.
  void _endDraw() {
    final count = _quads.count - _drawFrom;
    if (count > 0) {
      final field = _field;
      _draws.add((
        first: _drawFrom,
        count: count,
        shapes: field == null || _pipelines.fieldShapes != null
            ? _hostBuffer.emplace(_uniformData)
            : null,
        field: field,
      ));
      _drawFrom = _quads.count;
    }
    _blockRows = 0;
  }

  // The first of [count] rows of the block for the quads written next.
  int _takeRows(int count) {
    if (_blockRows + count > geometryMaxShapesPerDraw) _endDraw();
    final base = _blockRows;
    _blockRows += count;
    return base;
  }

  // Writes [look] of [looks] into [row] of the block.
  void _packLook(ShapeLooks looks, int look, int row) {
    final floats = _uniformFloats;
    final tints = _offsets.lookTints ~/ 4 + row * 4;
    final responses = _offsets.lookResponses ~/ 4 + row * 4;
    for (var i = 0; i < 4; i++) {
      floats[tints + i] = looks.looks[look * 8 + i];
      floats[responses + i] = looks.looks[look * 8 + 4 + i];
    }
  }

  // Writes [members] of [shapes], at most geometryMaxShapesPerDraw, into
  // the block's rows from [base], with their [looks] if any. The strips
  // name the rows they read, so the other rows hold whatever they held.
  void _packShapes(
    ShapeSet shapes,
    List<int> members,
    int base,
    ShapeLooks? looks,
  ) {
    final floats = _uniformFloats;
    final count = math.min(members.length, geometryMaxShapesPerDraw);
    const rows = geometryMaxShapesPerDraw * 12;
    final shapeAt = _offsets.shapeData ~/ 4 + base * 12;
    final rseAt = _offsets.rseData ~/ 4 + base * 12;
    // A pair's bottom half sits in the second half of uRseData.
    final lowerAt = rseAt + rows;
    final boundsAt = _offsets.shapeBounds ~/ 4 + base * 4;
    for (var row = 0; row < count; row++) {
      final member = members[row];
      final from = member * 12;
      for (var i = 0; i < 12; i++) {
        floats[shapeAt + row * 12 + i] = shapes.shapes[from + i];
        floats[rseAt + row * 12 + i] = shapes.superellipses[from + i];
        floats[lowerAt + row * 12 + i] = shapes.superellipsesLower[from + i];
      }
      for (var i = 0; i < 4; i++) {
        floats[boundsAt + row * 4 + i] = shapes.boxes[member * 4 + i];
      }
      if (looks != null) _packLook(looks, looks.lookOf[member], base + row);
    }
  }

  // How far past the reach the blends of [members] can still pull a texel's
  // distance in: a quarter of each blend.
  static double _smoothing(ShapeSet shapes, List<int> members) {
    final count = math.min(members.length, geometryMaxShapesPerDraw);
    var smoothing = 0.0;
    for (var row = 0; row < count; row++) {
      final marker = shapes.shapes[members[row] * 12 + 11];
      if (marker > 0) smoothing += marker * 0.25;
    }
    return smoothing;
  }

  // The texture holding [field], its samples copied in ahead of [page]'s
  // pass.
  gpu.Texture _fieldTexture(
    _FieldTextures textures,
    LiquidGlassField field,
    _Page page,
  ) {
    final frame = FlutterGpuGeometryRenderer._completedFrames;
    final held = textures.held(field, frame);
    if (held != null) return held;
    if (FlutterGpuGeometryRenderer._uploadsShareCommandBuffer) {
      return textures.upload(
        field,
        frame,
        page.commands ??= gpu.gpuContext.createCommandBuffer(),
      );
    }
    final upload = gpu.gpuContext.createCommandBuffer();
    try {
      return textures.upload(field, frame, upload);
    } finally {
      upload.submit();
    }
  }

  void _packFieldUniforms(BufferField field, gpu.Texture texture) {
    final to = _fieldUniformData.buffer.asFloat32List();
    final offsets = _fieldOffsets;
    final (xx, xy, yx, yy, dx, dy) = field.bufferToGrid;
    final toGrid = offsets.bufferToGrid ~/ 4;
    to[toGrid] = xx;
    to[toGrid + 1] = xy;
    to[toGrid + 2] = yx;
    to[toGrid + 3] = yy;
    final shift = offsets.gridShift ~/ 4;
    to[shift] = dx;
    to[shift + 1] = dy;
    to[shift + 2] = field.distanceScale;
    final size = offsets.fieldSize ~/ 4;
    to[size] = field.field.cols.toDouble();
    to[size + 1] = field.field.rows.toDouble();
    to[size + 2] = 1 / texture.width;
    to[size + 3] = 1 / texture.height;
  }
}

/// One texture of atlases and the look textures beside it, with what one
/// use of it holds: the rows placed, the atlases renderers still hold.
///
/// The set of textures is fixed: Impeller's Vulkan backend keeps the
/// framebuffer of a pass on the texture of its first attachment and hands
/// it to the next pass that draws into that texture, whatever else that
/// pass draws into, so a page always draws with the same looks.
final class _Page {
  _Page(this.owner, int width, int height, int lookCount)
    : texture = _create(width, height),
      looks = List.unmodifiable([
        for (var i = 0; i < lookCount; i++) _create(width, height),
      ]) {
    renderTarget = gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(texture: texture, clearValue: _outsideEntry),
        for (final look in looks) gpu.ColorAttachment(texture: look),
      ],
    );
  }

  final _Pages owner;
  final gpu.Texture texture;

  /// Look textures of [texture]'s size.
  final List<gpu.Texture> looks;

  /// Clears the page to the outside tile's table entry, which the first
  /// atlas placed holds at that texel, and the looks to zero. Without a
  /// clear, texels no quad writes hold whatever the memory held: old
  /// mattes on the host, black or white streaks across glass on phones.
  late final gpu.RenderTarget renderTarget;

  static final vm.Vector4 _outsideEntry = vm.Vector4(
    AtlasLayout.outsideEntry.$1.toDouble(),
    AtlasLayout.outsideEntry.$2.toDouble(),
    0,
    1,
  );

  int get width => texture.width;
  int get height => texture.height;

  bool sized(int width, int height) =>
      texture.width == width && texture.height == height;

  /// The handles of this use of the page, disposed with its last atlas:
  /// new ones each use, so what compares images sees that the page holds
  /// other atlases, and what draws with a released atlas fails.
  late ui.Image image;
  List<ui.Image> lookImages = const [];

  /// Rows placed, the atlases renderers hold, and whether it is yet to be
  /// drawn.
  int rows = 0;
  int leases = 0;
  bool open = false;

  /// Frame count when the last atlas held was released.
  int retiredFrame = 0;

  /// What copies fields in ahead of the pass, where one is recorded.
  gpu.CommandBuffer? commands;

  /// Starts a use of the page.
  void begin() {
    image = texture.asImage();
    lookImages = List.unmodifiable([for (final look in looks) look.asImage()]);
    _hasImages = true;
    rows = 0;
    open = true;
  }

  /// Gives the page up.
  void drop() {
    disposeImages();
    assert(() {
      FlutterGpuGeometryRenderer.debugDroppedTextureCount += 1 + looks.length;
      return true;
    }(), 'Count dropped geometry textures in debug builds.');
  }

  bool _hasImages = false;

  /// Disposes the handles of the use that ended.
  void disposeImages() {
    if (!_hasImages) return;
    _hasImages = false;
    image.dispose();
    for (final look in lookImages) {
      look.dispose();
    }
    lookImages = const [];
  }

  static gpu.Texture _create(int width, int height) {
    assert(() {
      FlutterGpuGeometryRenderer.debugAllocatedTextureCount++;
      return true;
    }(), 'Count allocated geometry textures in debug builds.');
    return gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
    );
  }
}

/// The quads of one page as tile_vertex.glsl reads its instances: a
/// rectangle in clip space for a target of [_width] x [_height] texels, top
/// row first, with a value and a ramp. Rows count from [top], the first row
/// of the atlas being written.
final class _AtlasQuads {
  static const int bytesPerQuad = _quadFloats * 4;

  int _width = 1;
  int _height = 1;
  Float32List _floats = Float32List(256 * _quadFloats);
  int count = 0;

  /// The page row of the atlas's row 0.
  int top = 0;

  /// Starts the quads of a page of [width] x [height] texels.
  void reset(int width, int height) {
    _width = width;
    _height = height;
    count = 0;
    top = 0;
  }

  /// The quads written since [reset].
  ByteData get bytes => ByteData.sublistView(_floats, 0, count * _quadFloats);

  /// A fill quad over the texels [x], [y] to [x] + [w], [y] + [h]: its
  /// first texel gets ([v0], [v1], [v2], [v3]), and x and y step by a
  /// tile's texels (16 x [v2]) a texel from there; with looks the look in
  /// row [look] of the draw's block lies beside it, none where it is
  /// negative (tile_fill.glsl).
  void fill(
    int x,
    int y,
    int w,
    int h,
    double v0,
    double v1,
    double v2,
    double v3, {
    int look = -1,
  }) {
    final floats = _rect(x, y, w, h);
    final at = count * _quadFloats;
    floats[at + 4] = v0;
    floats[at + 5] = v1;
    floats[at + 6] = v2;
    floats[at + 7] = v3;
    floats[at + 8] = 128;
    floats[at + 9] = x.toDouble();
    floats[at + 10] = look.toDouble();
    floats[at + 11] = (top + y).toDouble();
    count++;
  }

  /// A strip over the texels [x], [y] to [x] + [w], [y] + [h], each [texel]
  /// buffer pixels a side with texel (0, 0) of the target at the buffer
  /// point ([bufferX], [bufferY]). A texel farther than [reach] from every
  /// shape's box is outside. The texels evaluate [members]
  /// ([TileRun.members]), which count from row [base] of the draw's block:
  /// each a row plus 16 where it starts its group, 32 past the last; or,
  /// where it lists none, the [count] rows from [base].
  void strip(
    int x,
    int y,
    int w,
    int h, {
    required double bufferX,
    required double bufferY,
    required int texel,
    required double reach,
    required int base,
    required int count,
    required int members,
  }) {
    final floats = _rect(x, y, w, h);
    final at = this.count * _quadFloats;
    floats[at + 4] = bufferX;
    floats[at + 5] = bufferY;
    floats[at + 6] = texel.toDouble();
    floats[at + 7] = reach;
    if (members == 0) {
      floats[at + 8] = 64.0 + base;
      floats[at + 9] = count.toDouble();
      floats[at + 10] = 0;
      floats[at + 11] = 0;
    } else {
      for (var slot = 0; slot < 4; slot++) {
        final byte = (members >> (8 * slot)) & 0xff;
        floats[at + 8 + slot] = byte == 0
            ? 32
            : base + (byte & 0x7f) - 1 + (byte & 0x80 != 0 ? 16 : 0);
      }
    }
    this.count++;
  }

  // Makes room for one more quad and writes its rectangle.
  Float32List _rect(int x, int y, int w, int h) {
    if ((count + 1) * _quadFloats > _floats.length) {
      _floats = Float32List(_floats.length * 2)..setAll(0, _floats);
    }
    final floats = _floats;
    final at = count * _quadFloats;
    final y0 = top + y;
    floats[at] = 2 * x / _width - 1;
    floats[at + 1] = 1 - 2 * y0 / _height;
    floats[at + 2] = 2 * (x + w) / _width - 1;
    floats[at + 3] = 1 - 2 * (y0 + h) / _height;
    return floats;
  }
}

/// The quads of a frame's atlas passes, written at a cursor into one of
/// four host-visible buffers, so a buffer is written again only once the
/// frames that read it are done, as [gpu.HostBuffer] cycles its blocks.
///
/// [gpu.HostBuffer] itself fails an emplacement that starts inside a block
/// and runs past its end, which a variable number of quads does.
final class _VertexScratch {
  static const int _frames = 4;

  final List<gpu.DeviceBuffer?> _buffers = List.filled(_frames, null);
  int _frame = 0;
  int _cursor = 0;
  Duration? _stamp;

  gpu.BufferView write(ByteData bytes) {
    final stamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_stamp != stamp) {
      _stamp = stamp;
      _frame = (_frame + 1) % _frames;
      _cursor = 0;
    }
    final alignment = gpu.gpuContext.minimumUniformByteAlignment;
    final length = bytes.lengthInBytes;
    var buffer = _buffers[_frame];
    if (buffer == null || _cursor + length > buffer.sizeInBytes) {
      // Views into the buffer this replaces keep it alive for the passes
      // that read them.
      buffer = _buffers[_frame] = gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        math.max(length, math.max(16384, (buffer?.sizeInBytes ?? 0) * 2)),
      );
      _cursor = 0;
    }
    final offset = _cursor;
    if (!buffer.overwrite(bytes, destinationOffsetInBytes: offset)) {
      throw StateError('Could not write $length bytes of atlas quads.');
    }
    _cursor = (offset + length + alignment - 1) ~/ alignment * alignment;
    return gpu.BufferView(buffer, offsetInBytes: offset, lengthInBytes: length);
  }
}

/// The pipelines of an atlas pass that writes one set of looks, with their
/// uniform slots: one for shapes, one for a field. Without looks a field
/// pass reads no shapes, so it has no shape slot.
typedef _TilePipelines = ({
  gpu.RenderPipeline geometry,
  gpu.UniformSlot geometryShapes,
  gpu.RenderPipeline field,
  gpu.UniformSlot fieldUniforms,
  gpu.UniformSlot fieldTexture,
  gpu.UniformSlot? fieldShapes,
});

/// Byte offsets of GeometryUniforms' members (geometry_uniforms.glsl).
typedef _GeometryUniformOffsets = ({
  int shapeData,
  int rseData,
  int shapeBounds,
  int lookTints,
  int lookResponses,
});

class _SharedGeometryResources {
  _SharedGeometryResources(gpu.Shader Function(String name) shader) {
    final vertex = shader('TileVertex');
    gpu.RenderPipeline pipeline(gpu.Shader fragment) =>
        gpu.gpuContext.createRenderPipeline(
          vertex,
          fragment,
          vertexLayout: _tileVertexLayout,
        );
    pipelines = List.unmodifiable([
      for (final targets in _LookTargets.values)
        () {
          final looks = targets.shaderSuffix;
          final geometry = shader('TileGeometry${looks}Fragment');
          final field = shader('TileField${looks}Fragment');
          final shapes = targets != _LookTargets.none;
          return (
            geometry: pipeline(geometry),
            geometryShapes: geometry.getUniformSlot('GeometryUniforms'),
            field: pipeline(field),
            fieldUniforms: field.getUniformSlot('TileFieldUniforms'),
            fieldTexture: field.getUniformSlot('uField'),
            fieldShapes: shapes
                ? field.getUniformSlot('GeometryUniforms')
                : null,
          );
        }(),
    ]);
    final fieldSlot = pipelines.first.fieldUniforms;
    tileFieldUniformSize = fieldSlot.sizeInBytes ?? 0;
    int tileField(String name) => fieldSlot.getMemberOffsetInBytes(name) ?? 0;
    tileFieldOffsets = (
      bufferToGrid: tileField('uBufferToGrid'),
      gridShift: tileField('uGridShift'),
      fieldSize: tileField('uFieldSize'),
    );
    // The pass with looks reads every member.
    final slot = pipelines[_LookTargets.all.index].geometryShapes;
    uniformSize = slot.sizeInBytes ?? 0;
    int member(String name) => slot.getMemberOffsetInBytes(name) ?? 0;
    offsets = (
      shapeData: member('uShapeData'),
      rseData: member('uRseData'),
      shapeBounds: member('uShapeBounds'),
      lookTints: member('uLookTints'),
      lookResponses: member('uLookResponses'),
    );
  }

  late final List<_TilePipelines> pipelines;
  late final int tileFieldUniformSize;
  late final _TileFieldUniformOffsets tileFieldOffsets;
  late final int uniformSize;
  late final _GeometryUniformOffsets offsets;

  /// The pages every renderer of these resources places its atlases in,
  /// by the looks they write.
  late final List<_Pages> pages = List.unmodifiable([
    for (final targets in _LookTargets.values)
      _Pages(
        pipelines: pipelines[targets.index],
        offsets: offsets,
        uniformSize: uniformSize,
        fieldOffsets: tileFieldOffsets,
        fieldUniformSize: tileFieldUniformSize,
        lookCount: targets.count,
      ),
  ]);
}

/// Byte offsets of the tile field pass's uniform members.
typedef _TileFieldUniformOffsets = ({
  int bufferToGrid,
  int gridShift,
  int fieldSize,
});

/// The float textures a renderer uploads its fields into, reused: a body
/// whose field changes every frame - a menu opening - reuses its textures
/// instead of creating one per frame. A field fills the top-left of its
/// texture; the field pass reads only that region. The samples are copied
/// in by a command recorded on the caller's command buffer. At most four
/// textures survive; command buffers in flight retain theirs.
///
/// A slot is rewritten only three frames after its last use: the CPU
/// overwrites its staging buffer at once, which nothing orders behind a copy
/// from it the GPU may not have run yet, and Impeller keeps up to two frames
/// in flight besides the one being built (its Vulkan swapchain's
/// kMaxFramesInFlight).
final class _FieldTextures {
  static const int _reuseAfterFrames = 3;
  static const int _maxTextures = 4;
  static const int _bucket = 16;
  static const int _bytesPerNode = 16;

  final List<_FieldTexture> _textures = [];

  static int _capacity(int nodes) => (nodes + _bucket - 1) ~/ _bucket * _bucket;

  /// The texture already holding [field], marked as used in [frame], or
  /// null.
  gpu.Texture? held(LiquidGlassField field, int frame) {
    for (final entry in _textures) {
      if (identical(entry.samples, field.samples) &&
          entry.cols == field.cols &&
          entry.rows == field.rows) {
        entry.frame = frame;
        return entry.texture;
      }
    }
    return null;
  }

  /// A texture holding [field], its samples copied into it by a command
  /// recorded on [commands]; called when no texture [held] it.
  gpu.Texture upload(
    LiquidGlassField field,
    int frame,
    gpu.CommandBuffer commands,
  ) {
    _FieldTexture? slot;
    for (final entry in _textures) {
      if (entry.texture.width >= field.cols &&
          entry.texture.height >= field.rows &&
          frame - entry.frame >= _reuseAfterFrames) {
        slot = entry;
        break;
      }
    }
    if (slot == null) {
      final width = _capacity(field.cols);
      final height = _capacity(field.rows);
      slot = _FieldTexture(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          width,
          height,
          format: gpu.PixelFormat.r32g32b32a32Float,
          enableRenderTargetUsage: false,
        ),
        gpu.gpuContext.createDeviceBuffer(
          gpu.StorageMode.hostVisible,
          width * height * _bytesPerNode,
        ),
      );
      if (_textures.length >= _maxTextures) {
        // The one used longest ago: a field held every frame keeps its own.
        _textures.remove(
          _textures.reduce((a, b) => a.frame <= b.frame ? a : b),
        );
      }
      _textures.add(slot);
    }
    final bytes = ByteData.sublistView(
      field.samples,
      0,
      field.cols * field.rows * 4,
    );
    slot.buffer.overwrite(bytes);
    commands.copyBufferToTexture(
      gpu.BufferView(
        slot.buffer,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      ),
      gpu.TextureRegion(slot.texture, width: field.cols, height: field.rows),
    );
    slot
      ..samples = field.samples
      ..cols = field.cols
      ..rows = field.rows
      ..frame = frame;
    return slot.texture;
  }

  void release() => _textures.clear();
}

final class _FieldTexture {
  _FieldTexture(this.texture, this.buffer);

  final gpu.Texture texture;
  final gpu.DeviceBuffer buffer;
  Float32List? samples;
  int cols = 0;
  int rows = 0;
  int frame = 0;
}
