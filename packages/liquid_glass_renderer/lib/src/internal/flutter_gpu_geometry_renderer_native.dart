import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:liquid_glass_renderer/src/internal/geometry_renderer_limits.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_support.dart';
import 'package:liquid_glass_renderer/src/rendering/glass/geometry_tiling.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The edge distance stored in low-res matte texels that are far away from
/// every shape. Must match `kFarInward` in `geometry_fragment.glsl`. The
/// texture is cleared to it.
@internal
const double kLowResFarInward = -4096;

/// The edge distance of a geometry atlas's deep tile: past every inward
/// reach, and within a 16-bit float.
@internal
const double kDeepInward = 4096;

/// Floats per vertex of tile_vertex.glsl: position, value and ramp.
const int _tileVertexFloats = 10;

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

/// Renders the liquid glass low-res matte (see `geometry_fragment.glsl`)
/// using flutter_gpu.
///
/// Each output keeps its current texture and up to two retired spares, so a
/// frame that renders twice still reuses one; scenes and GC can keep dropped
/// textures alive longer. Textures grow as needed; rendering uses only the
/// top-left area, with shader UVs adjusted to match.
///
/// This renderer owns the image handles returned by [gpu.Texture.asImage].
/// Replacing/disposal releases those handles; recorded scenes hold independent
/// native references. A scene rasterized more than [reuseAfterFrames] frames
/// after it was recorded may show a newer matte.
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
    _pipeline = resources.pipeline;
    _materialGradientPipeline = resources.materialGradientPipeline;
    _materialTintGradientPipeline = resources.materialTintGradientPipeline;
    _offsetULowRes = resources.offsetULowRes;
    _fieldPipeline = resources.fieldPipeline;
    _tileFillPipeline = resources.tileFillPipeline;
    _tileGeometryPipeline = resources.tileGeometryPipeline;
    _tileGeometryUniformSlot = resources.tileGeometryUniformSlot;
    _tileFieldPipeline = resources.tileFieldPipeline;
    _tileFieldUniformSlot = resources.tileFieldUniformSlot;
    _tileFieldTextureSlot = resources.tileFieldTextureSlot;
    _tileFieldOffsets = resources.tileFieldOffsets;
    _tileFieldUniformData = ByteData(resources.tileFieldUniformSize);
    _fieldUniformSlot = resources.fieldUniformSlot;
    _fieldTextureSlot = resources.fieldTextureSlot;
    _fieldUniformSize = resources.fieldUniformSize;
    _fieldOffsets = resources.fieldOffsets;
    _fieldUniformData = ByteData(_fieldUniformSize);
    _uniformSlot = resources.uniformSlot;
    _uniformSize = resources.uniformSize;
    _offsetUOffset = resources.offsetUOffset;
    _offsetUTextureSize = resources.offsetUTextureSize;
    _offsetOpticalProps = resources.offsetOpticalProps;
    _offsetContourProps = resources.offsetContourProps;
    _offsetShapeData = resources.offsetShapeData;
    _offsetRseData = resources.offsetRseData;
    _offsetShapeTints = resources.offsetShapeTints;
    _offsetShapeResponses = resources.offsetShapeResponses;
    _offsetShapeBounds = resources.offsetShapeBounds;
    _vertexBufferView = resources.vertexBufferView;
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

  // Flutter's centered half-pixel coverage transition.
  static const double _geometryAaHalfWidth = 0.5;

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
      final vertexShader = library?['GeometryVertex'];
      final fragmentShader = library?['GeometryFragment'];
      final materialGradientFragmentShader =
          library?['MaterialGradientFragment'];
      final materialTintGradientFragmentShader =
          library?['MaterialTintGradientFragment'];
      final fieldFragmentShader = library?['GeometryFieldFragment'];
      final tileVertexShader = library?['TileVertex'];
      final tileFillFragmentShader = library?['TileFillFragment'];
      final tileGeometryFragmentShader = library?['TileGeometryFragment'];
      final tileFieldFragmentShader = library?['TileFieldFragment'];
      if (vertexShader == null ||
          fragmentShader == null ||
          materialGradientFragmentShader == null ||
          materialTintGradientFragmentShader == null ||
          fieldFragmentShader == null ||
          tileVertexShader == null ||
          tileFillFragmentShader == null ||
          tileGeometryFragmentShader == null ||
          tileFieldFragmentShader == null) {
        throw StateError(
          'LiquidGlass requires Flutter GPU. Run with Flutter 3.47 or newer '
          'and enable Flutter GPU for the target platform.',
        );
      }
      return _SharedGeometryResources(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
        materialGradientFragmentShader: materialGradientFragmentShader,
        materialTintGradientFragmentShader: materialTintGradientFragmentShader,
        fieldFragmentShader: fieldFragmentShader,
        tileVertexShader: tileVertexShader,
        tileFillFragmentShader: tileFillFragmentShader,
        tileGeometryFragmentShader: tileGeometryFragmentShader,
        tileFieldFragmentShader: tileFieldFragmentShader,
      );
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
  static int _debugActiveMaterialTextureCount = 0;
  static int _debugTotalRenderCount = 0;

  /// Counts SDF submissions across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  @visibleForTesting
  static int get debugActiveGeometryTextureCount =>
      _debugActiveGeometryTextureCount;

  @visibleForTesting
  static int get debugActiveMaterialTextureCount =>
      _debugActiveMaterialTextureCount;

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

  late final gpu.RenderPipeline _pipeline;
  late final gpu.RenderPipeline _materialGradientPipeline;
  late final gpu.RenderPipeline _materialTintGradientPipeline;
  late final int _offsetULowRes;
  late final gpu.RenderPipeline _fieldPipeline;
  late final gpu.UniformSlot _fieldUniformSlot;
  late final gpu.UniformSlot _fieldTextureSlot;
  late final int _fieldUniformSize;
  late final _FieldUniformOffsets _fieldOffsets;
  late final ByteData _fieldUniformData;
  final _FieldTextures _fieldTextures = _FieldTextures();
  late final gpu.RenderPipeline _tileFillPipeline;
  late final gpu.RenderPipeline _tileGeometryPipeline;
  late final gpu.UniformSlot _tileGeometryUniformSlot;
  late final gpu.RenderPipeline _tileFieldPipeline;
  late final gpu.UniformSlot _tileFieldUniformSlot;
  late final gpu.UniformSlot _tileFieldTextureSlot;
  late final _TileFieldUniformOffsets _tileFieldOffsets;
  late final ByteData _tileFieldUniformData;

  // Latest geometry atlas. Older scenes retain their own native references.
  gpu.Texture? _atlasTexture;
  ui.Image? _atlasImage;

  // Cleared to the outside tile's table entry (geometry_tiling.dart).
  final _TextureRing _atlases = _TextureRing(
    format: gpu.PixelFormat.r16g16b16a16Float,
    clearValue: vm.Vector4(
      AtlasLayout.outsideEntry.$1.toDouble(),
      AtlasLayout.outsideEntry.$2.toDouble(),
      0,
      1,
    ),
  );

  @visibleForTesting
  Object get debugPipelineIdentity => _pipeline;

  @visibleForTesting
  int get debugHostBufferBlockLength => _sharedHostBufferBlockLength;

  @visibleForTesting
  Object? get debugHostBufferIdentity => _sharedHostBuffer;

  /// Number of output-update calls, including material-only updates.
  @visibleForTesting
  int debugRenderCount = 0;

  @visibleForTesting
  bool get debugDisposed => _disposed;

  bool _disposed = false;

  late final gpu.UniformSlot _uniformSlot;
  late final int _uniformSize;
  late final int _offsetUOffset;
  late final int _offsetUTextureSize;
  late final int _offsetOpticalProps;
  late final int _offsetContourProps;
  late final int _offsetShapeData;
  late final int _offsetRseData;
  late final int _offsetShapeTints;
  late final int _offsetShapeResponses;
  late final int _offsetShapeBounds;
  late final ByteData _uniformData;
  int _writtenShapeFloats = 0;
  int _writtenRseFloats = 0;
  int _writtenRseLowerFloats = 0;

  // Latest matte. Older scenes retain their own native references.
  gpu.Texture? _texture;
  ui.Image? _image;
  gpu.RenderTarget? _renderTarget;
  gpu.Texture? _materialTexture;
  ui.Image? _materialImage;
  gpu.RenderTarget? _materialRenderTarget;

  /// Appearance blending is decorative and only visible while shapes merge.
  /// One sample per 8x8 full-resolution block makes its SDF work 64x smaller.
  static const int materialRasterScale = geometryMaterialRasterScale;

  late final gpu.BufferView _vertexBufferView;

  /// Low-resolution contributor map from the latest appearance render.
  ///
  /// The map fills the top-left sub-rect of the image; its size follows from
  /// the matte size, as in the final shader.
  ui.Image? get materialImage => _materialImage;

  // The low-res matte is RGBA16F and is cleared to "far outside" (see
  // [kLowResFarInward]); the material maps are RGBA8.
  final _TextureRing _mattes = _TextureRing(
    format: gpu.PixelFormat.r16g16b16a16Float,
    clearValue: vm.Vector4(kLowResFarInward, 0, 0, 0),
  );
  final _TextureRing _materials = _TextureRing();

  /// Actual output draws, separate from calls that only retire a material map.
  @visibleForTesting
  int debugMatteDrawCount = 0;

  @visibleForTesting
  int debugMaterialDrawCount = 0;

  /// How many shapes the latest render left out: past
  /// [geometryMaxShapesPerDraw] in one cluster of shapes that blend or lie
  /// within reach of each other, or past it at all with a field or a
  /// per-shape material map.
  int droppedShapes = 0;

  /// Renders a new low-res matte and returns it as a [ui.Image].
  ///
  /// The low-res matte has one texel for every [matteScale] x [matteScale]
  /// (2 or 4) block of matte pixels, plus one extra row and column for the
  /// far edge. It fills the top-left of the image, which is `textureWidth` x
  /// `textureHeight`. `width` and `height` are the matte's size in pixels.
  /// The returned image belongs to the renderer: do not dispose it. Its
  /// texture is written again [reuseAfterFrames] frames after a later render
  /// replaces it.
  ///
  /// With [writeMatte] false, retain the current matte and only replace (or
  /// retire) the material output. The caller must verify that geometry,
  /// raster dimensions and optical settings still match the encoded matte.
  ///
  /// With a [field], the matte encodes the body the field describes instead
  /// of the shapes, at [fieldScale] device pixels per logical pixel of the
  /// field; the material output still reads the shapes.
  ({ui.Image image, int width, int height, int textureWidth, int textureHeight})
  render({
    required int width,
    required int height,
    required List<double> shapeData,
    required int numShapes,
    required double refractionHeight,
    required double refractionAmount,
    required double offsetX,
    required double offsetY,
    double? edgeDistanceRange,
    bool refractionFitsShape = true,
    double contourExtent = 0.5,
    bool writeMatte = true,
    bool writeMaterials = false,
    bool writeTintOnly = false,
    List<double> appearanceData = const <double>[],
    List<double> rseData = const <double>[],
    List<double> rseLowerData = const <double>[],
    List<double> boundsData = const <double>[],
    required int matteScale,
    LiquidGlassField? field,
    double fieldScale = 1,
  }) {
    assert(
      matteScale == 2 || matteScale == 4,
      'The matte scale must be 2 or 4.',
    );
    final scale = matteScale;
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    final matteWidth = _bucketDimension(width);
    final matteHeight = _bucketDimension(height);
    final (viewWidth, viewHeight) = _viewCapacity();

    _ensureFrameCounter();
    assert(
      writeMatte || _texture != null,
      'A material-only update requires an existing matte.',
    );
    if (writeMatte) {
      if (_texture != null) {
        // Release our handle; earlier submitted scenes hold their own.
        _image?.dispose();
        _image = null;
        _renderTarget = null;
        _texture = null;
        assert(() {
          _debugActiveGeometryTextureCount--;
          return true;
        }(), 'Track replaced geometry textures in debug builds.');
      }
      // The low-res matte has a texel on both edges of the matte, so it
      // needs one more texel than width / scale in each direction.
      final matte = _mattes.next(
        _completedFrames,
        width: matteWidth ~/ scale + 1,
        height: matteHeight ~/ scale + 1,
        maxWidth: viewWidth ~/ scale + 1,
        maxHeight: viewHeight ~/ scale + 1,
      );
      _texture = matte.texture;
      _renderTarget = matte.renderTarget;
      _image = _texture!.asImage();
      assert(() {
        _debugActiveGeometryTextureCount++;
        return true;
      }(), 'Track live geometry textures in debug builds.');
    }

    final materialMapWidth = math.max(
      1,
      (matteWidth + materialRasterScale - 1) ~/ materialRasterScale,
    );
    final materialMapHeight = math.max(
      1,
      (matteHeight + materialRasterScale - 1) ~/ materialRasterScale,
    );
    final materialWidth = writeTintOnly
        ? materialMapWidth
        : math.max(geometryMaxShapesPerDraw, materialMapWidth);
    final materialHeight = writeTintOnly
        ? materialMapHeight
        : materialMapHeight + 2;
    if (_materialTexture != null) {
      _materialImage?.dispose();
      _materialImage = null;
      _materialRenderTarget = null;
      _materialTexture = null;
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track replaced material textures in debug builds.');
    }
    if (writeMaterials) {
      final material = _materials.next(
        _completedFrames,
        width: materialWidth,
        height: materialHeight,
        maxWidth: math.max(
          geometryMaxShapesPerDraw,
          (viewWidth + materialRasterScale - 1) ~/ materialRasterScale,
        ),
        maxHeight:
            (viewHeight + materialRasterScale - 1) ~/ materialRasterScale + 2,
      );
      _materialTexture = material.texture;
      _materialRenderTarget = material.renderTarget;
      _materialImage = _materialTexture!.asImage();
      assert(() {
        _debugActiveMaterialTextureCount++;
        return true;
      }(), 'Track live material textures in debug builds.');
    } else {
      _materials.releaseCurrent(_completedFrames);
    }

    _packUniformData(
      offsetX: offsetX,
      offsetY: offsetY,
      textureWidth: matteWidth.toDouble(),
      textureHeight: matteHeight.toDouble(),
      refractionHeight: refractionHeight,
      refractionAmount: refractionAmount,
      edgeDistanceRange: edgeDistanceRange ?? math.max(12, refractionHeight),
      refractionFitsShape: refractionFitsShape,
      contourExtent: contourExtent,
      materialScale: writeMaterials ? materialRasterScale.toDouble() : 1.0,
      materialMapWidth: writeMaterials ? materialMapWidth.toDouble() : 1.0,
      materialMapHeight: writeMaterials ? materialMapHeight.toDouble() : 1.0,
      numShapes: math.min(numShapes, geometryMaxShapesPerDraw).toDouble(),
      shapeData: shapeData,
      rseData: rseData,
      rseLowerData: rseLowerData,
      appearanceData: appearanceData,
      boundsData: boundsData,
      matteScale: scale,
    );

    final uniformView = _hostBufferForUniformSize(_uniformSize)
        .emplace(_uniformData);

    // More shapes than one draw evaluates are drawn cluster by cluster, each
    // inside the texels only it can write.
    final clusters =
        writeMatte &&
            field == null &&
            !writeMaterials &&
            numShapes > geometryMaxShapesPerDraw
        ? _clusters(
            shapeData: shapeData,
            boundsData: boundsData,
            numShapes: numShapes,
            offsetX: offsetX,
            offsetY: offsetY,
            contourExtent: contourExtent,
            width: matteWidth,
            height: matteHeight,
            scale: scale,
          )
        : null;
    droppedShapes = clusters == null
        ? math.max(0, numShapes - geometryMaxShapesPerDraw)
        : clusters.fold(
            0,
            (dropped, cluster) =>
                dropped +
                math.max(0, cluster.shapes.length - geometryMaxShapesPerDraw),
          );

    if (writeMatte) {
      assert(() {
        debugMatteDrawCount++;
        return true;
      }(), 'Track matte draws in debug builds.');
      final geometryCommandBuffer = gpu.gpuContext.createCommandBuffer();
      gpu.Texture? fieldTexture;
      try {
        fieldTexture = field == null
            ? null
            : _uploadField(field, geometryCommandBuffer);
      } on Object {
        geometryCommandBuffer.submit();
        rethrow;
      }
      // Only texels near a shape hold anything but "far outside", which is
      // what the texture is cleared to, so the pass draws just those.
      final passWidth = matteWidth ~/ scale + 1;
      final passHeight = matteHeight ~/ scale + 1;
      final drawRect = clusters != null
          ? null
          : _occupiedRect(
              shapeData: shapeData,
              boundsData: boundsData,
              numShapes: numShapes,
              offsetX: offsetX,
              offsetY: offsetY,
              contourExtent: contourExtent,
              width: matteWidth,
              height: matteHeight,
              scale: scale,
            );
      final geometryPass = geometryCommandBuffer.createRenderPass(
        _renderTarget!,
      )..setPrimitiveType(gpu.PrimitiveType.triangleStrip);
      if (field != null) {
        _packFieldUniformData(field, fieldScale, fieldTexture!);
        geometryPass
          ..bindPipeline(_fieldPipeline)
          ..bindUniform(
            _fieldUniformSlot,
            _hostBufferForUniformSize(
              _fieldUniformSize,
            ).emplace(_fieldUniformData),
          )
          ..bindTexture(_fieldTextureSlot, fieldTexture);
      } else {
        geometryPass
          ..bindPipeline(_pipeline)
          ..bindUniform(_uniformSlot, uniformView);
      }
      geometryPass.bindVertexBuffer(_vertexBufferView);
      _restrictTo(geometryPass, _texture!, passWidth, passHeight);
      if (drawRect != null) {
        geometryPass.setScissor(
          gpu.Scissor(
            x: drawRect.left,
            y: drawRect.top,
            width: drawRect.width,
            height: drawRect.height,
          ),
        );
      }
      if (clusters == null) {
        geometryPass.draw(4);
      } else {
        for (final cluster in clusters) {
          final shapes = cluster.shapes.take(geometryMaxShapesPerDraw).toList();
          List<double> pick(List<double> data, int stride) => [
            for (final i in shapes)
              if (data.length >= (i + 1) * stride)
                ...data.getRange(i * stride, (i + 1) * stride),
          ];
          _packShapes(
            numShapes: shapes.length.toDouble(),
            shapeData: pick(shapeData, 12),
            rseData: pick(rseData, 12),
            rseLowerData: pick(rseLowerData, 12),
            boundsData: pick(boundsData, 4),
          );
          final rect = cluster.rect;
          geometryPass
            ..bindUniform(
              _uniformSlot,
              _hostBufferForUniformSize(_uniformSize).emplace(_uniformData),
            )
            ..setScissor(
              gpu.Scissor(
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height,
              ),
            )
            ..draw(4);
        }
      }
      _submitOrDefer(geometryCommandBuffer);
    }
    if (writeMaterials) {
      assert(() {
        debugMaterialDrawCount++;
        return true;
      }(), 'Track material draws in debug builds.');
      final materialCommandBuffer = gpu.gpuContext.createCommandBuffer();
      final materialPass =
          materialCommandBuffer.createRenderPass(_materialRenderTarget!)
            ..bindPipeline(
              writeTintOnly
                  ? _materialTintGradientPipeline
                  : _materialGradientPipeline,
            )
            ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
            ..bindUniform(_uniformSlot, uniformView)
            ..bindVertexBuffer(_vertexBufferView);
      _restrictTo(
        materialPass,
        _materialTexture!,
        materialWidth,
        materialHeight,
      );
      materialPass.draw(4);
      _submitOrDefer(materialCommandBuffer);
    }

    return (
      image: _image!,
      width: matteWidth,
      height: matteHeight,
      textureWidth: _texture!.width,
      textureHeight: _texture!.height,
    );
  }

  /// Draws the geometry atlas of [tiling] (geometry_tiling.dart) in one
  /// pass: the constant tiles, the table and every ring strip, the strips
  /// evaluating the tiling's shapes set by set, or its field.
  ///
  /// Table texels hold their tile's entry in x and y and 1 in w. The returned
  /// image belongs to the renderer, as [render]'s does: its texture is
  /// written again [reuseAfterFrames] frames after a later atlas replaces it.
  ({ui.Image image, AtlasLayout layout, int textureWidth, int textureHeight})
  renderAtlas(Tiling tiling) {
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      debugMatteDrawCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    _ensureFrameCounter();
    final layout = AtlasLayout.of(tiling);
    if (_atlasTexture != null) {
      _atlasImage?.dispose();
      _atlasImage = null;
      _atlasTexture = null;
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track replaced geometry textures in debug builds.');
    }
    final atlas = _atlases.next(
      _completedFrames,
      width: layout.width,
      height: layout.height,
      maxWidth: AtlasLayout.maxSize,
      maxHeight: AtlasLayout.maxSize,
    );
    final texture = _atlasTexture = atlas.texture;
    final image = _atlasImage = texture.asImage();
    assert(() {
      _debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track live geometry textures in debug builds.');

    const strip = Tiling.size + 2;
    final quads = _AtlasQuads(texture.width, texture.height)
      ..add(0, 0, strip, strip, value: (kLowResFarInward, 0, 0, 0))
      ..add(strip, 0, strip, strip, value: (kDeepInward, 0, 0, 0));
    final (tableX, tableY) = layout.tableOrigin;
    final (deepX, deepY) = AtlasLayout.deepEntry;
    for (var row = 0; row < tiling.rows; row++) {
      var column = 0;
      while (column < tiling.columns) {
        if (tiling.kindAt(column, row) != TileKind.deep) {
          column++;
          continue;
        }
        var end = column + 1;
        while (end < tiling.columns &&
            tiling.kindAt(end, row) == TileKind.deep) {
          end++;
        }
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
    final pass = commands.createRenderPass(atlas.renderTarget)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..bindPipeline(_tileFillPipeline)
      ..bindVertexBuffer(range(0, fills))
      ..draw(fills * 6);
    if (field != null) {
      final strips = quads.count - fills;
      if (strips > 0) {
        _packTileFieldUniformData(field, fieldTexture!);
        pass
          ..bindPipeline(_tileFieldPipeline)
          ..bindUniform(
            _tileFieldUniformSlot,
            hostBuffer.emplace(_tileFieldUniformData),
          )
          ..bindTexture(_tileFieldTextureSlot, fieldTexture)
          ..bindVertexBuffer(range(fills, strips))
          ..draw(strips * 6);
      }
    } else if (sets.isNotEmpty) {
      final shapes = tiling.shapes;
      pass.bindPipeline(_tileGeometryPipeline);
      for (final (set, first, count) in sets) {
        final members = tiling.shapeSets[set];
        List<double> pick(List<double> data, int stride) => [
          for (final i in members)
            ...data.getRange(i * stride, (i + 1) * stride),
        ];
        _packShapes(
          numShapes: members.length.toDouble(),
          shapeData: pick(shapes.shapes, 12),
          rseData: pick(shapes.superellipses, 12),
          rseLowerData: pick(shapes.superellipsesLower, 12),
          boundsData: pick(shapes.boxes, 4),
        );
        _uniformData.setFloat32(
          _offsetContourProps,
          tiling.reach.outward,
          Endian.host,
        );
        pass
          ..bindUniform(
            _tileGeometryUniformSlot,
            hostBuffer.emplace(_uniformData),
          )
          ..bindVertexBuffer(range(first, count))
          ..draw(count * 6);
      }
    }
    _submitOrDefer(commands);
    droppedShapes = tiling.droppedShapes;
    return (
      image: image,
      layout: layout,
      textureWidth: texture.width,
      textureHeight: texture.height,
    );
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

  /// The low-res matte texels (for a matte of [width] x [height] pixels at
  /// [scale]) that can hold anything but "far outside", or null to draw them
  /// all.
  ///
  /// This is the same test the geometry shader uses to skip a texel, done once
  /// for a whole rectangle: a texel farther from every shape's box than the
  /// border, two texels and the blend radius is "far outside". Without shape
  /// boxes there is nothing to go on.
  static _PixelRect? _occupiedRect({
    required List<double> shapeData,
    required List<double> boundsData,
    required int numShapes,
    required double offsetX,
    required double offsetY,
    required double contourExtent,
    required int width,
    required int height,
    required int scale,
  }) {
    final count = math.min(numShapes, geometryMaxShapesPerDraw);
    if (count <= 0 ||
        boundsData.length < count * 4 ||
        shapeData.length < count * 12) {
      return null;
    }
    return _texels(
      [for (var i = 0; i < count; i++) i],
      shapeData: shapeData,
      boundsData: boundsData,
      offsetX: offsetX,
      offsetY: offsetY,
      contourExtent: contourExtent,
      width: width,
      height: height,
      scale: scale,
    );
  }

  /// The low-res matte texels [shapes] can write anything but "far outside"
  /// into, or null when a shape has no finite box.
  static _PixelRect? _texels(
    List<int> shapes, {
    required List<double> shapeData,
    required List<double> boundsData,
    required double offsetX,
    required double offsetY,
    required double contourExtent,
    required int width,
    required int height,
    required int scale,
  }) {
    var smoothing = 0.0;
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final i in shapes) {
      final marker = shapeData[i * 12 + 11];
      if (marker >= 0) smoothing += marker * 0.25;
      left = math.min(left, boundsData[i * 4]);
      top = math.min(top, boundsData[i * 4 + 1]);
      right = math.max(right, boundsData[i * 4 + 2]);
      bottom = math.max(bottom, boundsData[i * 4 + 3]);
    }
    if (!(left.isFinite && top.isFinite && right.isFinite && bottom.isFinite)) {
      return null;
    }
    // One extra pixel covers float rounding in the shader's own test. The two
    // texels of margin make sure no visible pixel blends in a cleared
    // texel.
    final reach = contourExtent + 2 * scale + 2 + smoothing + 1;
    final x0 = (left - reach - offsetX).floor().clamp(0, width);
    final y0 = (top - reach - offsetY).floor().clamp(0, height);
    final x1 = (right + reach - offsetX).ceil().clamp(0, width);
    final y1 = (bottom + reach - offsetY).ceil().clamp(0, height);
    // The texels covering matte pixels x0..x1 (inclusive), and one more on
    // each side.
    final tx0 = (x0 ~/ scale - 1).clamp(0, width ~/ scale);
    final ty0 = (y0 ~/ scale - 1).clamp(0, height ~/ scale);
    final tx1 = ((x1 + scale - 1) ~/ scale + 2).clamp(0, width ~/ scale + 1);
    final ty1 = ((y1 + scale - 1) ~/ scale + 2).clamp(0, height ~/ scale + 1);
    if (tx1 <= tx0 || ty1 <= ty0) return const _PixelRect(0, 0, 1, 1);
    return _PixelRect(tx0, ty0, tx1 - tx0, ty1 - ty0);
  }

  /// The shapes in clusters whose texels meet no other cluster's, in paint
  /// order, each with those texels. A blend group stays in one cluster.
  static List<_Cluster> _clusters({
    required List<double> shapeData,
    required List<double> boundsData,
    required int numShapes,
    required double offsetX,
    required double offsetY,
    required double contourExtent,
    required int width,
    required int height,
    required int scale,
  }) {
    final everything = _PixelRect(
      0,
      0,
      width ~/ scale + 1,
      height ~/ scale + 1,
    );
    _PixelRect texels(List<int> shapes) =>
        (boundsData.length < numShapes * 4
            ? null
            : _texels(
                shapes,
                shapeData: shapeData,
                boundsData: boundsData,
                offsetX: offsetX,
                offsetY: offsetY,
                contourExtent: contourExtent,
                width: width,
                height: height,
                scale: scale,
              )) ??
        everything;
    final groups = <List<int>>[];
    for (var i = 0; i < numShapes; i++) {
      // A negative marker starts a group (see the geometry shader).
      if (groups.isEmpty || shapeData[i * 12 + 11] < 0) {
        groups.add([i]);
      } else {
        groups.last.add(i);
      }
    }
    final clusters = [
      for (final shapes in groups) _Cluster(shapes, texels(shapes)),
    ];
    var merged = true;
    while (merged) {
      merged = false;
      search:
      for (var a = 0; a < clusters.length; a++) {
        for (var b = a + 1; b < clusters.length; b++) {
          if (!clusters[a].rect.meets(clusters[b].rect)) continue;
          final shapes = [...clusters[a].shapes, ...clusters[b].shapes]..sort();
          clusters[a] = _Cluster(shapes, texels(shapes));
          clusters.removeAt(b);
          merged = true;
          break search;
        }
      }
    }
    return clusters;
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

  /// Writes the field pass's uniforms: the matte offset and scale the shape
  /// pass packed, and the field's frame in device pixels.
  void _packFieldUniformData(
    LiquidGlassField field,
    double fieldScale,
    gpu.Texture texture,
  ) {
    final from = _uniformData.buffer.asFloat32List();
    final to = _fieldUniformData.buffer.asFloat32List();
    void copy(int fromOffset, int toOffset, int count) {
      for (var i = 0; i < count; i++) {
        to[toOffset ~/ 4 + i] = from[fromOffset ~/ 4 + i];
      }
    }

    final offsets = _fieldOffsets;
    copy(_offsetULowRes, offsets.lowRes, 4);
    copy(_offsetUOffset, offsets.offset, 2);
    final frame = offsets.fieldFrame ~/ 4;
    to[frame] = field.origin.dx * fieldScale;
    to[frame + 1] = field.origin.dy * fieldScale;
    to[frame + 2] = field.step * fieldScale;
    to[frame + 3] = fieldScale;
    final size = offsets.fieldSize ~/ 4;
    to[size] = field.cols.toDouble();
    to[size + 1] = field.rows.toDouble();
    to[size + 2] = 1 / texture.width;
    to[size + 3] = 1 / texture.height;
  }

  /// Limits [pass] to the top-left [width] x [height] of [texture].
  ///
  /// `gl_FragCoord` stays framebuffer-relative, so the shaders need no
  /// offset for a sub-rect at the origin.
  static void _restrictTo(
    gpu.RenderPass pass,
    gpu.Texture texture,
    int width,
    int height,
  ) {
    if (texture.width == width && texture.height == height) return;
    pass
      ..setViewport(gpu.Viewport(width: width, height: height))
      ..setScissor(gpu.Scissor(width: width, height: height));
  }

  /// Largest view in physical pixels, the cap for texture growth.
  static (int, int) _viewCapacity() {
    var width = 0;
    var height = 0;
    for (final view in WidgetsBinding.instance.platformDispatcher.views) {
      width = math.max(width, view.physicalSize.width.ceil());
      height = math.max(height, view.physicalSize.height.ceil());
    }
    return (_bucketDimension(width), _bucketDimension(height));
  }

  static int _bucketDimension(int value) => (value + 63) & ~63;

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
  int get debugRetiredTextureCount =>
      _mattes.spareCount + _materials.spareCount;

  /// Matte textures this renderer holds, including the one in use.
  @visibleForTesting
  int get debugMatteTextureCount => _mattes.textureCount;

  /// The latest matte texture, compared by identity in tests.
  @visibleForTesting
  Object? get debugMatteTexture => _texture;

  /// Size of the latest matte texture.
  @visibleForTesting
  (int, int)? get debugMatteTextureSize => switch (_texture) {
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

  static void _countDropped() {
    assert(() {
      debugDroppedTextureCount++;
      return true;
    }(), 'Count dropped geometry textures in debug builds.');
  }

  void _packUniformData({
    required double offsetX,
    required double offsetY,
    required double textureWidth,
    required double textureHeight,
    required double refractionHeight,
    required double refractionAmount,
    required double edgeDistanceRange,
    required bool refractionFitsShape,
    required double contourExtent,
    required double materialScale,
    required double materialMapWidth,
    required double materialMapHeight,
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
    required List<double> rseLowerData,
    required List<double> appearanceData,
    required List<double> boundsData,
    required int matteScale,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();

    // Only the geometry pass has this uniform. It comes after the ones the
    // material passes share.
    floatData[_offsetULowRes ~/ 4] = matteScale.toDouble();

    final uOffsetIndex = _offsetUOffset ~/ 4;
    floatData[uOffsetIndex] = offsetX;
    floatData[uOffsetIndex + 1] = offsetY;

    final textureSizeIndex = _offsetUTextureSize ~/ 4;
    // X selects shape-fitted refraction; Y is the bevel's edge displacement,
    // which is also the codec scale.
    floatData[textureSizeIndex] = refractionFitsShape ? 1 : 0;
    floatData[textureSizeIndex + 1] = math.max(1e-3, refractionAmount);

    final opticalPropsIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalPropsIndex] = math.max(0, refractionHeight);
    floatData[opticalPropsIndex + 1] = _geometryAaHalfWidth;
    floatData[opticalPropsIndex + 2] = math.max(1, edgeDistanceRange);

    final contourPropsIndex = _offsetContourProps ~/ 4;
    floatData[contourPropsIndex] = math.max(0.5, contourExtent);
    floatData[contourPropsIndex + 1] = materialScale;
    floatData[contourPropsIndex + 2] = materialMapWidth;
    floatData[contourPropsIndex + 3] = materialMapHeight;

    _packShapes(
      numShapes: numShapes,
      shapeData: shapeData,
      rseData: rseData,
      rseLowerData: rseLowerData,
      boundsData: boundsData,
    );

    if (appearanceData.isNotEmpty &&
        appearanceData.length != geometryMaxShapesPerDraw * 2 * 4) {
      throw ArgumentError.value(
        appearanceData.length,
        'appearanceData.length',
        'must contain two vec4 rows for each of '
            '$geometryMaxShapesPerDraw shapes',
      );
    }
    if (appearanceData.isNotEmpty) {
      final shapeTintsStartIndex = _offsetShapeTints ~/ 4;
      final shapeResponsesStartIndex = _offsetShapeResponses ~/ 4;
      for (var i = 0; i < geometryMaxShapesPerDraw * 4; i++) {
        floatData[shapeTintsStartIndex + i] = appearanceData[i];
        floatData[shapeResponsesStartIndex + i] =
            appearanceData[geometryMaxShapesPerDraw * 4 + i];
      }
    }
  }

  // Writes the shapes' uniforms, which every draw of the matte replaces.
  void _packShapes({
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
    required List<double> rseLowerData,
    required List<double> boundsData,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();
    floatData[_offsetOpticalProps ~/ 4 + 3] = numShapes;

    final shapeDataStartIndex = _offsetShapeData ~/ 4;
    const rows = geometryMaxShapesPerDraw * 12;
    final shapeFloats = math.min(shapeData.length, rows);
    for (var i = 0; i < shapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = shapeData[i];
    }
    for (var i = shapeFloats; i < _writtenShapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = 0;
    }
    _writtenShapeFloats = shapeFloats;

    final rseDataStartIndex = _offsetRseData ~/ 4;
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
    final boundsStartIndex = _offsetShapeBounds ~/ 4;
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
    _mattes.release();
    _atlases.release();
    if (_atlasTexture != null) {
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track disposed geometry textures in debug builds.');
    }
    _atlasTexture = null;
    _atlasImage?.dispose();
    _atlasImage = null;
    _materials.release();
    _fieldTextures.release();
    _renderTarget = null;
    _image?.dispose();
    _image = null;
    _materialRenderTarget = null;
    _materialImage?.dispose();
    _materialImage = null;
    if (_materialTexture != null) {
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track disposed material textures in debug builds.');
    }
    _materialTexture = null;
    if (_texture != null) {
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track disposed geometry textures in debug builds.');
    }
    _texture = null;
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

  /// The texels [x], [y] to [x] + [w], [y] + [h].
  void add(
    int x,
    int y,
    int w,
    int h, {
    required (double, double, double, double) value,
    (double, double) ramp = (0, 0),
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
      _floats.addAll([px, py, v0, v1, v2, v3, r0, r1, 0, 0]);
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

/// An integer pixel rectangle.
final class _PixelRect {
  const _PixelRect(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;

  bool meets(_PixelRect other) =>
      left < other.left + other.width &&
      other.left < left + width &&
      top < other.top + other.height &&
      other.top < top + height;
}

// Shapes of the matte drawn together, and the texels they write.
final class _Cluster {
  const _Cluster(this.shapes, this.rect);
  final List<int> shapes;
  final _PixelRect rect;
}

/// A texture and its render target.
final class _RingTexture {
  _RingTexture(this.texture, {vm.Vector4? clearValue})
    : renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: texture, clearValue: clearValue),
      );

  final gpu.Texture texture;

  /// Clears the whole texture to the ring's `clearValue`, or transparent black
  /// when there is none. A pass that didn't clear left what a GPU has in that
  /// memory where glass reads it: old mattes on the host, black or white
  /// streaks across glass on phones.
  final gpu.RenderTarget renderTarget;

  /// Frame count when this texture was last replaced or released.
  int retiredFrame = 0;

  bool covers(int width, int height) =>
      texture.width >= width && texture.height >= height;
}

/// A current texture and up to two retired spares for one output.
///
/// Capacity grows in 1.5x steps, capped at the view unless a render needs more.
/// A second spare avoids allocations when a frame renders twice.
final class _TextureRing {
  _TextureRing({
    this.format = gpu.PixelFormat.r8g8b8a8UNormInt,
    this.clearValue,
  });

  /// Pixel format of the textures; the appearance maps are RGBA8.
  final gpu.PixelFormat format;

  /// What a clearing render target clears to; transparent black when null.
  final vm.Vector4? clearValue;

  static const int _maxSpares = 2;

  _RingTexture? _current;
  final List<_RingTexture> _spares = [];
  int _width = 0;
  int _height = 0;

  int get spareCount => _spares.length;
  int get textureCount => _spares.length + (_current == null ? 0 : 1);

  /// Replaces the texture in use with one that holds [width] x [height].
  _RingTexture next(
    int frame, {
    required int width,
    required int height,
    required int maxWidth,
    required int maxHeight,
  }) {
    if (width > _width || height > _height) {
      _width = _grow(_width, width, maxWidth);
      _height = _grow(_height, height, maxHeight);
      _spares.removeWhere((texture) {
        if (texture.covers(_width, _height)) return false;
        FlutterGpuGeometryRenderer._countDropped();
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
        FlutterGpuGeometryRenderer._countDropped();
      }
    }
    if (_spares.isNotEmpty &&
        frame - _spares.first.retiredFrame >=
            FlutterGpuGeometryRenderer.reuseAfterFrames) {
      assert(() {
        FlutterGpuGeometryRenderer.debugReusedTextureCount++;
        return true;
      }(), 'Count reused geometry textures in debug builds.');
      return _current = _spares.removeAt(0);
    }
    while (_spares.length > _maxSpares) {
      _spares.removeAt(0);
      FlutterGpuGeometryRenderer._countDropped();
    }
    return _current = _allocate(_width, _height);
  }

  /// Retires the texture in use without replacing it.
  void releaseCurrent(int frame) {
    final previous = _current;
    if (previous == null) return;
    _current = null;
    previous.retiredFrame = frame;
    _spares.add(previous);
  }

  /// Drops every texture and resets the ring's capacity.
  void release() {
    if (_current != null) {
      FlutterGpuGeometryRenderer._countDropped();
    }
    for (final _ in _spares) {
      FlutterGpuGeometryRenderer._countDropped();
    }
    _current = null;
    _spares.clear();
    _width = 0;
    _height = 0;
  }

  static int _grow(int capacity, int needed, int limit) {
    if (needed <= capacity) return capacity;
    if (capacity == 0) return needed;
    final stepped = (capacity * 3 + 1) >> 1;
    return math.max(needed, math.min(stepped, limit));
  }

  _RingTexture _allocate(int width, int height) {
    assert(() {
      FlutterGpuGeometryRenderer.debugAllocatedTextureCount++;
      return true;
    }(), 'Count allocated geometry textures in debug builds.');
    return _RingTexture(
      gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: format,
      ),
      clearValue: clearValue,
    );
  }
}

class _SharedGeometryResources {
  _SharedGeometryResources({
    required gpu.Shader vertexShader,
    required gpu.Shader fragmentShader,
    required gpu.Shader materialGradientFragmentShader,
    required gpu.Shader materialTintGradientFragmentShader,
    required gpu.Shader fieldFragmentShader,
    required gpu.Shader tileVertexShader,
    required gpu.Shader tileFillFragmentShader,
    required gpu.Shader tileGeometryFragmentShader,
    required gpu.Shader tileFieldFragmentShader,
  }) {
    gpu.RenderPipeline tilePipeline(gpu.Shader fragment) =>
        gpu.gpuContext.createRenderPipeline(
          tileVertexShader,
          fragment,
          vertexLayout: _tileVertexLayout,
        );
    tileFillPipeline = tilePipeline(tileFillFragmentShader);
    tileGeometryPipeline = tilePipeline(tileGeometryFragmentShader);
    tileGeometryUniformSlot = tileGeometryFragmentShader.getUniformSlot(
      'GeometryUniforms',
    );
    tileFieldPipeline = tilePipeline(tileFieldFragmentShader);
    tileFieldUniformSlot = tileFieldFragmentShader.getUniformSlot(
      'TileFieldUniforms',
    );
    tileFieldTextureSlot = tileFieldFragmentShader.getUniformSlot('uField');
    tileFieldUniformSize = tileFieldUniformSlot.sizeInBytes ?? 0;
    int tileField(String name) =>
        tileFieldUniformSlot.getMemberOffsetInBytes(name) ?? 0;
    tileFieldOffsets = (
      bufferToGrid: tileField('uBufferToGrid'),
      gridShift: tileField('uGridShift'),
      fieldSize: tileField('uFieldSize'),
    );
    pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fragmentShader,
    );
    materialGradientPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      materialGradientFragmentShader,
    );
    materialTintGradientPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      materialTintGradientFragmentShader,
    );
    fieldPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fieldFragmentShader,
    );
    fieldUniformSlot = fieldFragmentShader.getUniformSlot('FieldUniforms');
    fieldTextureSlot = fieldFragmentShader.getUniformSlot('uField');
    fieldUniformSize = fieldUniformSlot.sizeInBytes ?? 0;
    int field(String name) =>
        fieldUniformSlot.getMemberOffsetInBytes(name) ?? 0;
    fieldOffsets = (
      lowRes: field('uLowRes'),
      offset: field('uOffset'),
      fieldFrame: field('uFieldFrame'),
      fieldSize: field('uFieldSize'),
    );
    // The material passes use the same uniforms as the geometry pass, minus
    // the last one (the matte scale), so one buffer layout works for all of
    // them.
    uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    uniformSize = uniformSlot.sizeInBytes ?? 0;
    offsetULowRes = uniformSlot.getMemberOffsetInBytes('uLowRes') ?? 0;
    offsetUOffset = uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    offsetUTextureSize =
        uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    offsetOpticalProps =
        uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    offsetContourProps =
        uniformSlot.getMemberOffsetInBytes('uContourProps') ?? 0;
    offsetShapeData = uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    offsetRseData = uniformSlot.getMemberOffsetInBytes('uRseData') ?? 0;
    offsetShapeTints = uniformSlot.getMemberOffsetInBytes('uShapeTints') ?? 0;
    offsetShapeResponses =
        uniformSlot.getMemberOffsetInBytes('uShapeResponses') ?? 0;
    offsetShapeBounds = uniformSlot.getMemberOffsetInBytes('uShapeBounds') ?? 0;
    final vertices = Float32List.fromList([
      -1.0, -1.0, 0.0, 0.0, //
      1.0, -1.0, 1.0, 0.0, //
      -1.0, 1.0, 0.0, 1.0, //
      1.0, 1.0, 1.0, 1.0, //
    ]);
    vertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
    vertexBufferView = gpu.BufferView(
      vertexBuffer,
      offsetInBytes: 0,
      lengthInBytes: vertexBuffer.sizeInBytes,
    );
  }

  late final gpu.RenderPipeline pipeline;
  late final gpu.RenderPipeline materialGradientPipeline;
  late final gpu.RenderPipeline materialTintGradientPipeline;
  late final int offsetULowRes;
  late final gpu.RenderPipeline fieldPipeline;
  late final gpu.RenderPipeline tileFillPipeline;
  late final gpu.RenderPipeline tileGeometryPipeline;
  late final gpu.UniformSlot tileGeometryUniformSlot;
  late final gpu.RenderPipeline tileFieldPipeline;
  late final gpu.UniformSlot tileFieldUniformSlot;
  late final gpu.UniformSlot tileFieldTextureSlot;
  late final int tileFieldUniformSize;
  late final _TileFieldUniformOffsets tileFieldOffsets;
  late final gpu.UniformSlot fieldUniformSlot;
  late final gpu.UniformSlot fieldTextureSlot;
  late final int fieldUniformSize;
  late final _FieldUniformOffsets fieldOffsets;
  late final gpu.UniformSlot uniformSlot;
  late final int uniformSize;
  late final int offsetUOffset;
  late final int offsetUTextureSize;
  late final int offsetOpticalProps;
  late final int offsetContourProps;
  late final int offsetShapeData;
  late final int offsetRseData;
  late final int offsetShapeTints;
  late final int offsetShapeResponses;
  late final int offsetShapeBounds;
  late final gpu.DeviceBuffer vertexBuffer;
  late final gpu.BufferView vertexBufferView;
}

/// Byte offsets of the field pass's uniform members.
typedef _FieldUniformOffsets = ({
  int lowRes,
  int offset,
  int fieldFrame,
  int fieldSize,
});

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
