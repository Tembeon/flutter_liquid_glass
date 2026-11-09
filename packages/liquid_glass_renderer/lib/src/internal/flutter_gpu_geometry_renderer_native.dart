import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_support.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The edge distance of a geometry atlas's outside tile and of its texels
/// far from every shape: `kFarInward` in `matte_encoding.glsl`.
@internal
const double kFarInward = -4096;

/// The edge distance of a geometry atlas's deep tile: past every inward
/// reach, and within a 16-bit float.
@internal
const double kDeepInward = 4096;

/// Floats per vertex of tile_vertex.glsl: position, value and ramp.
const int _tileVertexFloats = 10;

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
      strideInBytes: _tileVertexFloats * 4,
      attributes: [
        gpu.VertexAttribute(
          name: 'position',
          format: gpu.VertexFormat.float32x2,
        ),
        gpu.VertexAttribute(
          name: 'value',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 8,
        ),
        gpu.VertexAttribute(
          name: 'ramp',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 24,
        ),
      ],
    ),
  ],
);

/// Renders the liquid glass geometry atlas (geometry_tiling.dart) and the
/// looks beside it using flutter_gpu.
///
/// The atlas keeps a few retired textures, so a frame that renders twice
/// still reuses one; scenes and GC can keep dropped
/// textures alive longer. Textures grow as needed; rendering uses only the
/// top-left area, with shader UVs adjusted to match.
///
/// This renderer owns the image handles returned by [gpu.Texture.asImage].
/// Replacing/disposal releases those handles; recorded scenes hold independent
/// native references. A scene rasterized more than [reuseAfterFrames] frames
/// after it was recorded may show a newer atlas.
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

  FlutterGpuGeometryRenderer._fromShared(_SharedGeometryResources resources) {
    _pipelines = resources.pipelines;
    _tileFieldOffsets = resources.tileFieldOffsets;
    _tileFieldUniformData = ByteData(resources.tileFieldUniformSize);
    _uniformSize = resources.uniformSize;
    _offsets = resources.offsets;
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

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

  /// One bump allocator for every geometry pass in the current frame.
  ///
  /// A HostBuffer retains four device-buffer blocks, so one per renderer
  /// would cost four blocks per layer. A single scratch sized for a frame of
  /// layers keeps that off the native heap.
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

  /// Counts SDF submissions across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

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

  final _FieldTextures _fieldTextures = _FieldTextures();
  late final List<_TilePipelines> _pipelines;
  late final _TileFieldUniformOffsets _tileFieldOffsets;
  late final ByteData _tileFieldUniformData;

  // Latest geometry atlas and its looks. Older scenes retain their own
  // native references.
  gpu.Texture? _atlasTexture;
  ui.Image? _atlasImage;
  List<ui.Image> _lookImages = const [];

  final _TextureRing _atlases = _TextureRing();

  @visibleForTesting
  Object get debugPipelineIdentity => _pipelines.first.geometry;

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

  late final int _uniformSize;
  late final _GeometryUniformOffsets _offsets;
  late final ByteData _uniformData;
  int _writtenShapeFloats = 0;
  int _writtenRseFloats = 0;
  int _writtenRseLowerFloats = 0;

  /// The latest geometry atlas.
  ui.Image? get atlasImage => _atlasImage;

  /// The looks beside the latest atlas: none, the tint, or tint, response
  /// and color model shares.
  List<ui.Image> get lookImages => _lookImages;

  /// Atlas draws.
  @visibleForTesting
  int debugMatteDrawCount = 0;

  /// How many shapes the latest atlas left out: past
  /// [geometryMaxShapesPerDraw] reaching one tile (Tiling.droppedShapes).
  int droppedShapes = 0;

  /// Draws the geometry atlas of [tiling] (geometry_tiling.dart) in one
  /// pass: the constant tiles, the table and every ring strip, the strips
  /// evaluating the tiling's shapes set by set, or its field. With
  /// [Tiling.looks] the pass writes each texel's look into [lookImages]
  /// beside it, textures of the atlas's size.
  ///
  /// Table texels hold their tile's entry in x and y and 1 in w. The returned
  /// images belong to the renderer: do not dispose them. Their textures are
  /// written again [reuseAfterFrames] frames after a later atlas replaces
  /// them.
  ({
    ui.Image image,
    List<ui.Image> looks,
    AtlasLayout layout,
    int textureWidth,
    int textureHeight,
  })
  renderAtlas(Tiling tiling) {
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      debugMatteDrawCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    _ensureFrameCounter();
    final layout = AtlasLayout.of(tiling);
    final looks = tiling.looks;
    final lookTargets = _LookTargets.of(looks);
    _releaseAtlasHandles();
    final atlas = _atlases.next(
      _completedFrames,
      width: layout.width,
      height: layout.height,
      lookCount: lookTargets.count,
    );
    final texture = _atlasTexture = atlas.texture;
    final image = _atlasImage = texture.asImage();
    _lookImages = List.unmodifiable([
      for (final look in atlas.looks) look.asImage(),
    ]);
    assert(() {
      _debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track live geometry textures in debug builds.');

    const strip = Tiling.size + 2;
    final quads = _AtlasQuads(texture.width, texture.height)
      ..add(0, 0, strip, strip, value: (kFarInward, 0, 0, 0));
    for (var look = 0; look < (looks?.count ?? 1); look++) {
      quads.add(
        (look + 1) * strip,
        0,
        strip,
        strip,
        value: (kDeepInward, 0, 0, 0),
        look: look,
      );
    }
    final (tableX, tableY) = AtlasLayout.tableOrigin;
    for (var row = 0; row < tiling.rows; row++) {
      var column = 0;
      while (column < tiling.columns) {
        if (tiling.kindAt(column, row) != TileKind.deep) {
          column++;
          continue;
        }
        final look = tiling.deepLookAt(column, row);
        var end = column + 1;
        while (end < tiling.columns &&
            tiling.kindAt(end, row) == TileKind.deep &&
            tiling.deepLookAt(end, row) == look) {
          end++;
        }
        final (deepX, deepY) = AtlasLayout.deepEntryOf(look);
        quads.add(
          tableX + column,
          tableY + row,
          end - column,
          1,
          value: (deepX.toDouble(), deepY.toDouble(), 0, 1),
        );
        column = end;
      }
    }
    final runs = tiling.runs;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final (entryX, entryY) = layout.entryOf(i, 0);
      quads.add(
        tableX + run.column,
        tableY + run.row,
        run.length,
        1,
        value: (entryX.toDouble(), entryY.toDouble(), 0, 1),
        ramp: ((tableX + run.column).toDouble(), Tiling.size.toDouble()),
      );
    }
    final fills = quads.count;
    final sets = <(int, int, int)>[];
    for (var set = 0; set < tiling.shapeSets.length; set++) {
      final start = quads.count;
      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        if (run.shapes != set) continue;
        final x = layout.strips[i * 2];
        final y = layout.strips[i * 2 + 1];
        quads.add(
          x,
          y,
          run.length * Tiling.size + 2,
          strip,
          value: (
            (run.column * Tiling.size - x - 1).toDouble(),
            (run.row * Tiling.size - y - 1).toDouble(),
            0,
            0,
          ),
        );
      }
      if (quads.count > start) sets.add((set, start, quads.count - start));
    }

    final hostBuffer = _hostBufferForUniformSize(_uniformSize);
    final vertices = _vertexScratch.write(quads.bytes);
    gpu.BufferView range(int first, int count) => gpu.BufferView(
      vertices.buffer,
      offsetInBytes: vertices.offsetInBytes + first * _AtlasQuads.bytesPerQuad,
      lengthInBytes: count * _AtlasQuads.bytesPerQuad,
    );

    final commands = gpu.gpuContext.createCommandBuffer();
    final field = tiling.field;
    gpu.Texture? fieldTexture;
    try {
      fieldTexture = field == null ? null : _uploadField(field.field, commands);
    } on Object {
      commands.submit();
      rethrow;
    }
    final pipelines = _pipelines[lookTargets.index];
    final pass = commands.createRenderPass(atlas.renderTarget)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..bindPipeline(pipelines.fill);
    if (looks != null) {
      _packLooks(looks, [for (var look = 0; look < looks.count; look++) look]);
      pass.bindUniform(
        pipelines.fillShapes!,
        hostBuffer.emplace(_uniformData),
      );
    }
    // A binding outlives its draw: the fill's looks would bind over the
    // shapes of the passes after it.
    pass
      ..bindVertexBuffer(range(0, fills))
      ..draw(fills * 6)
      ..clearBindings();
    final shapes = tiling.shapes;
    gpu.BufferView shapeUniforms(List<int> members) {
      List<double> pick(List<double> data, int stride) => [
        for (final i in members) ...data.getRange(i * stride, (i + 1) * stride),
      ];
      _packShapes(
        reachOutward: tiling.reach.outward,
        numShapes: members.length.toDouble(),
        shapeData: pick(shapes.shapes, 12),
        rseData: pick(shapes.superellipses, 12),
        rseLowerData: pick(shapes.superellipsesLower, 12),
        boundsData: pick(shapes.boxes, 4),
      );
      if (looks != null) {
        _packLooks(looks, [for (final i in members) looks.lookOf[i]]);
      }
      return hostBuffer.emplace(_uniformData);
    }

    if (field != null) {
      final strips = quads.count - fills;
      if (strips > 0) {
        _packTileFieldUniformData(field, fieldTexture!);
        pass
          ..bindPipeline(pipelines.field)
          ..bindUniform(
            pipelines.fieldUniforms,
            hostBuffer.emplace(_tileFieldUniformData),
          )
          ..bindTexture(pipelines.fieldTexture, fieldTexture);
        if (looks != null) {
          pass.bindUniform(
            pipelines.fieldShapes!,
            shapeUniforms(tiling.shapeSets.first),
          );
        }
        pass
          ..bindVertexBuffer(range(fills, strips))
          ..draw(strips * 6);
      }
    } else if (sets.isNotEmpty) {
      pass.bindPipeline(pipelines.geometry);
      for (final (set, first, count) in sets) {
        pass
          ..bindUniform(
            pipelines.geometryShapes,
            shapeUniforms(tiling.shapeSets[set]),
          )
          ..bindVertexBuffer(range(first, count))
          ..draw(count * 6);
      }
    }
    _submitOrDefer(commands);
    droppedShapes = tiling.droppedShapes;
    return (
      image: image,
      looks: _lookImages,
      layout: layout,
      textureWidth: texture.width,
      textureHeight: texture.height,
    );
  }

  // Releases our handles; earlier submitted scenes hold their own.
  void _releaseAtlasHandles() {
    for (final look in _lookImages) {
      look.dispose();
    }
    _lookImages = const [];
    if (_atlasTexture == null) return;
    _atlasImage?.dispose();
    _atlasImage = null;
    _atlasTexture = null;
    assert(() {
      _debugActiveGeometryTextureCount--;
      return true;
    }(), 'Track replaced geometry textures in debug builds.');
  }

  void _packTileFieldUniformData(BufferField field, gpu.Texture texture) {
    final to = _tileFieldUniformData.buffer.asFloat32List();
    final offsets = _tileFieldOffsets;
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

  /// The texture holding [field], its copy recorded on [geometry] where a
  /// copy may precede the geometry pass on one command buffer, else on a
  /// command buffer of its own submitted ahead of it.
  gpu.Texture _uploadField(
    LiquidGlassField field,
    gpu.CommandBuffer geometry,
  ) {
    final held = _fieldTextures.held(field, _completedFrames);
    if (held != null) return held;
    if (_uploadsShareCommandBuffer) {
      return _fieldTextures.upload(field, _completedFrames, geometry);
    }
    final upload = gpu.gpuContext.createCommandBuffer();
    try {
      final texture = _fieldTextures.upload(field, _completedFrames, upload);
      _submitOrDefer(upload);
      return texture;
    } on Object {
      upload.submit();
      rethrow;
    }
  }

  // A copy recorded before a render pass on the same command buffer is
  // encoded ahead of it on Vulkan and GLES. Metal opens a blit encoder when
  // the copy is recorded and closes it only on submit, so the render pass's
  // encoder would nest: there the copy gets its own command buffer,
  // submitted first.
  static final bool _uploadsShareCommandBuffer =
      !(Platform.isIOS || Platform.isMacOS);

  // Every pass gets its own command buffer: Flutter GPU (3.47.1) begins the
  // backend pass in `createRenderPass` and ends it only in `submit`, so a
  // second pass on one command buffer nests inside the first. That segfaults
  // in the PowerVR Vulkan driver and SwiftShader (CmdEndRenderPass2) and
  // asserts on Metal ("A command encoder is already encoding"). Share one
  // only once the engine ends a pass before the next begins.
  static final List<gpu.CommandBuffer> _pendingCommandBuffers = [];
  static bool _postFrameFlushScheduled = false;

  /// Command buffers submitted by [flushPendingSubmissions].
  @visibleForTesting
  static int debugBatchedSubmitCount = 0;

  /// Flushes left to the post-frame safety net because no glass layer of the
  /// frame's scene flushed first.
  @visibleForTesting
  static int debugPostFrameFlushCount = 0;

  /// Passes whose submission was deferred to [flushPendingSubmissions].
  @visibleForTesting
  static int debugDeferredPassCount = 0;

  // Only the paint and compositing phases are followed by a scene build that
  // flushes before the scene reaches the raster thread.
  static bool get _deferring =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  static void _submitOrDefer(gpu.CommandBuffer commandBuffer) {
    if (!_deferring) {
      commandBuffer.submit();
      return;
    }
    assert(() {
      debugDeferredPassCount++;
      return true;
    }(), 'Count deferred geometry passes in debug builds.');
    _pendingCommandBuffers.add(commandBuffer);
    if (_postFrameFlushScheduled) return;
    _postFrameFlushScheduled = true;
    // Covers passes whose layer was painted but not composited.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameFlushScheduled = false;
      if (_pendingCommandBuffers.isEmpty) return;
      assert(() {
        debugPostFrameFlushCount++;
        return true;
      }(), 'Count safety-net flushes in debug builds.');
      flushPendingSubmissions();
    });
  }

  /// Submits the passes recorded since the last flush, in recording order.
  ///
  /// Glass layers call this while the scene is built, which is before the
  /// scene is handed to the raster thread, so every matte a scene samples has
  /// been submitted ahead of it on the GPU queue. A post-frame callback
  /// flushes passes of layers that were painted but not composited.
  static void flushPendingSubmissions() {
    if (_pendingCommandBuffers.isEmpty) return;
    for (final commandBuffer in _pendingCommandBuffers) {
      commandBuffer.submit();
      assert(() {
        debugBatchedSubmitCount++;
        return true;
      }(), 'Count batched submissions in debug builds.');
    }
    _pendingCommandBuffers.clear();
  }

  /// Frames to wait after retirement before reusing a texture.
  ///
  /// A texture retired in frame E was last read by frame E - 1. The engine's
  /// two-frame pipeline (`Animator.FramePipeline(2)`) submits that scene before
  /// frame E + 1 paints. Flutter GPU uses the same queue, which orders the next
  /// write after those reads (Metal/Vulkan hazards; GLES posting order).
  static const int reuseAfterFrames = 1;

  static int _completedFrames = 0;
  static bool _countingFrames = false;

  /// Counts scene-submitting frames for texture reuse.
  ///
  /// Renders outside a frame, as in unit tests, do not advance the count,
  /// so their textures are never reused.
  static void _ensureFrameCounter() {
    if (_countingFrames) return;
    _countingFrames = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
    });
  }

  /// Textures this renderer holds that are not in use.
  @visibleForTesting
  int get debugRetiredTextureCount => _atlases.spareCount;

  /// Atlas textures this renderer holds, including the one in use.
  @visibleForTesting
  int get debugMatteTextureCount => _atlases.textureCount;

  /// The latest atlas texture, compared by identity in tests.
  @visibleForTesting
  Object? get debugMatteTexture => _atlasTexture;

  /// Size of the latest atlas texture.
  @visibleForTesting
  (int, int)? get debugMatteTextureSize => switch (_atlasTexture) {
    final texture? => (texture.width, texture.height),
    null => null,
  };

  /// Renders that wrote into a reused texture instead of allocating one.
  @visibleForTesting
  static int debugReusedTextureCount = 0;

  /// Textures allocated, all renderers.
  @visibleForTesting
  static int debugAllocatedTextureCount = 0;

  /// Textures dropped, all renderers. Once a texture has lived a few young
  /// GCs its wrapper is promoted, and dropping it pins its storage until an
  /// old-generation GC.
  @visibleForTesting
  static int debugDroppedTextureCount = 0;

  static void _countDropped(_RingTexture entry) {
    assert(() {
      debugDroppedTextureCount += entry.textureCount;
      return true;
    }(), 'Count dropped geometry textures in debug builds.');
  }

  void _packLooks(ShapeLooks looks, List<int> entries) {
    final floatData = _uniformData.buffer.asFloat32List();
    final tints = _offsets.lookTints ~/ 4;
    final responses = _offsets.lookResponses ~/ 4;
    for (var row = 0; row < entries.length; row++) {
      final at = entries[row] * 8;
      for (var i = 0; i < 4; i++) {
        floatData[tints + row * 4 + i] = looks.looks[at + i];
        floatData[responses + row * 4 + i] = looks.looks[at + 4 + i];
      }
    }
  }

  // Writes the shapes' uniforms, which every draw replaces.
  void _packShapes({
    required double reachOutward,
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
    required List<double> rseLowerData,
    required List<double> boundsData,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();
    floatData[_offsets.props ~/ 4] = reachOutward;
    floatData[_offsets.props ~/ 4 + 1] = numShapes;

    final shapeDataStartIndex = _offsets.shapeData ~/ 4;
    const rows = geometryMaxShapesPerDraw * 12;
    final shapeFloats = math.min(shapeData.length, rows);
    for (var i = 0; i < shapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = shapeData[i];
    }
    for (var i = shapeFloats; i < _writtenShapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = 0;
    }
    _writtenShapeFloats = shapeFloats;

    final rseDataStartIndex = _offsets.rseData ~/ 4;
    final rseFloats = math.min(rseData.length, rows);
    for (var i = 0; i < rseFloats; i++) {
      floatData[rseDataStartIndex + i] = rseData[i];
    }
    for (var i = rseFloats; i < _writtenRseFloats; i++) {
      floatData[rseDataStartIndex + i] = 0;
    }
    _writtenRseFloats = rseFloats;

    // A pair's bottom half sits in the second half of uRseData.
    final lowerStartIndex = rseDataStartIndex + rows;
    final lowerFloats = math.min(rseLowerData.length, rows);
    for (var i = 0; i < lowerFloats; i++) {
      floatData[lowerStartIndex + i] = rseLowerData[i];
    }
    for (var i = lowerFloats; i < _writtenRseLowerFloats; i++) {
      floatData[lowerStartIndex + i] = 0;
    }
    _writtenRseLowerFloats = lowerFloats;

    // Shapes without bounds are never culled.
    final boundsStartIndex = _offsets.shapeBounds ~/ 4;
    final boundsFloats = math.min(
      boundsData.length,
      geometryMaxShapesPerDraw * 4,
    );
    for (var i = 0; i < geometryMaxShapesPerDraw * 4; i++) {
      floatData[boundsStartIndex + i] = i < boundsFloats
          ? boundsData[i]
          : (i % 4 < 2 ? -1e9 : 1e9);
    }
  }

  /// Releases borrowed output handles, keeping reusable rendering resources.
  ///
  /// Callers retaining an output must clone its images before calling this.
  /// Independent clones and submitted native scenes remain valid.
  void releaseOutput() {
    _atlases.release();
    _releaseAtlasHandles();
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

/// The quads of one atlas pass as tile_vertex.glsl reads them: two
/// triangles each, corners in clip space for a target of [_width] x
/// [_height] texels, top row first.
final class _AtlasQuads {
  _AtlasQuads(this._width, this._height);

  static const int bytesPerQuad = 6 * _tileVertexFloats * 4;

  final int _width;
  final int _height;
  final List<double> _floats = [];

  int get count => _floats.length ~/ (6 * _tileVertexFloats);

  ByteData get bytes => ByteData.sublistView(Float32List.fromList(_floats));

  /// The texels [x], [y] to [x] + [w], [y] + [h]; a fill pass with looks
  /// writes [look] beside a constant tile, none where it is negative.
  void add(
    int x,
    int y,
    int w,
    int h, {
    required (double, double, double, double) value,
    (double, double) ramp = (0, 0),
    int look = -1,
  }) {
    final x0 = 2 * x / _width - 1;
    final x1 = 2 * (x + w) / _width - 1;
    final y0 = 1 - 2 * y / _height;
    final y1 = 1 - 2 * (y + h) / _height;
    final (v0, v1, v2, v3) = value;
    final (r0, r1) = ramp;
    for (final (px, py) in [
      (x0, y0),
      (x1, y0),
      (x0, y1),
      (x1, y0),
      (x1, y1),
      (x0, y1),
    ]) {
      _floats.addAll([px, py, v0, v1, v2, v3, r0, r1, look.toDouble(), 0]);
    }
  }
}

/// The vertex data of a frame's atlas passes, written at a cursor into one of
/// four host-visible buffers, so a buffer is written again only once the
/// frames that read it are done, as [gpu.HostBuffer] cycles its blocks.
///
/// [gpu.HostBuffer] itself fails an emplacement that starts inside a block
/// and runs past its end, which variable-length vertex data does.
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
      throw StateError('Could not write $length bytes of atlas vertices.');
    }
    _cursor = (offset + length + alignment - 1) ~/ alignment * alignment;
    return gpu.BufferView(buffer, offsetInBytes: offset, lengthInBytes: length);
  }
}

/// An atlas texture and the look textures beside it.
///
/// The set is fixed: Impeller's Vulkan backend keeps the framebuffer of a
/// pass on the texture of its first attachment and hands it to the next pass
/// that draws into that texture, whatever else that pass draws into, so the
/// atlas texture always draws with the same looks.
final class _RingTexture {
  _RingTexture(this.texture, int lookCount)
    : looks = List.unmodifiable([
        for (var i = 0; i < lookCount; i++)
          _TextureRing._create(texture.width, texture.height),
      ]) {
    renderTarget = gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(texture: texture, clearValue: _outsideEntry),
        for (final look in looks) gpu.ColorAttachment(texture: look),
      ],
    );
  }

  final gpu.Texture texture;

  /// Look textures of [texture]'s size.
  final List<gpu.Texture> looks;

  /// Clears the atlas to the outside tile's table entry and the looks to
  /// zero. Without a clear, texels no quad writes hold whatever the memory
  /// held: old mattes on the host, black or white streaks across glass on
  /// phones.
  late final gpu.RenderTarget renderTarget;

  static final vm.Vector4 _outsideEntry = vm.Vector4(
    AtlasLayout.outsideEntry.$1.toDouble(),
    AtlasLayout.outsideEntry.$2.toDouble(),
    0,
    1,
  );

  /// The textures this entry holds.
  int get textureCount => 1 + looks.length;

  /// Frame count when this texture was last replaced or released.
  int retiredFrame = 0;

  bool covers(int width, int height) =>
      texture.width >= width && texture.height >= height;
}

/// The current atlas and up to three retired spares, RGBA16F.
///
/// Capacity grows in 1.5x steps up to [AtlasLayout.maxSize]. The spares
/// cover a frame that renders twice, alternating between atlases with and
/// without looks, without allocating.
final class _TextureRing {
  static const int _maxSpares = 3;

  _RingTexture? _current;
  final List<_RingTexture> _spares = [];
  int _width = 0;
  int _height = 0;

  int get spareCount => _spares.length;
  int get textureCount => _spares.length + (_current == null ? 0 : 1);

  /// Replaces the atlas in use with one that holds [width] x [height] and
  /// [lookCount] looks beside it.
  _RingTexture next(
    int frame, {
    required int width,
    required int height,
    required int lookCount,
  }) {
    if (width > _width || height > _height) {
      _width = _grow(_width, width);
      _height = _grow(_height, height);
      _spares.removeWhere((entry) {
        if (entry.covers(_width, _height)) return false;
        FlutterGpuGeometryRenderer._countDropped(entry);
        return true;
      });
    }
    final previous = _current;
    _current = null;
    if (previous != null) {
      if (previous.covers(_width, _height)) {
        previous.retiredFrame = frame;
        _spares.add(previous);
      } else {
        FlutterGpuGeometryRenderer._countDropped(previous);
      }
    }
    final reusable = _spares.indexWhere(
      (entry) =>
          entry.looks.length == lookCount &&
          frame - entry.retiredFrame >=
              FlutterGpuGeometryRenderer.reuseAfterFrames,
    );
    if (reusable >= 0) {
      assert(() {
        FlutterGpuGeometryRenderer.debugReusedTextureCount++;
        return true;
      }(), 'Count reused geometry textures in debug builds.');
      return _current = _spares.removeAt(reusable);
    }
    while (_spares.length > _maxSpares) {
      FlutterGpuGeometryRenderer._countDropped(_spares.removeAt(0));
    }
    return _current = _RingTexture(_create(_width, _height), lookCount);
  }

  /// Drops every texture and resets the ring's capacity.
  void release() {
    for (final entry in [?_current, ..._spares]) {
      FlutterGpuGeometryRenderer._countDropped(entry);
    }
    _current = null;
    _spares.clear();
    _width = 0;
    _height = 0;
  }

  static int _grow(int capacity, int needed) {
    if (needed <= capacity) return capacity;
    if (capacity == 0) return needed;
    final stepped = (capacity * 3 + 1) >> 1;
    return math.max(needed, math.min(stepped, AtlasLayout.maxSize));
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

/// The pipelines of an atlas pass that writes one set of looks, with their
/// uniform slots. Without looks the fill and field passes read no shapes,
/// so they have no shape slots.
typedef _TilePipelines = ({
  gpu.RenderPipeline fill,
  gpu.UniformSlot? fillShapes,
  gpu.RenderPipeline geometry,
  gpu.UniformSlot geometryShapes,
  gpu.RenderPipeline field,
  gpu.UniformSlot fieldUniforms,
  gpu.UniformSlot fieldTexture,
  gpu.UniformSlot? fieldShapes,
});

/// Byte offsets of GeometryUniforms' members (geometry_uniforms.glsl).
typedef _GeometryUniformOffsets = ({
  int props,
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
          final fill = shader('TileFill${looks}Fragment');
          final geometry = shader('TileGeometry${looks}Fragment');
          final field = shader('TileField${looks}Fragment');
          final shapes = targets != _LookTargets.none;
          return (
            fill: pipeline(fill),
            fillShapes: shapes ? fill.getUniformSlot('GeometryUniforms') : null,
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
      props: member('uProps'),
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
