part of 'flutter_gpu_geometry_renderer_native.dart';

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
