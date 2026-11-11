import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Where each of a few choices lies, for a finger that slides across them
/// (a `ScrubInteraction`'s hit): a [SlotMapOrigin] marks the box positions
/// are given in, and every [SlotMapEntry] below it registers its own box as
/// it attaches, so [at] answers the choice under a point with no keys and
/// wherever the layout or a scroll put the boxes.
@internal
final class SlotMap<T extends Object> {
  RenderBox? _origin;
  final Map<T, RenderBox> _slots = {};

  /// The choice whose box holds [position], in the origin's coordinates,
  /// or null.
  T? at(Offset position) {
    final origin = _origin;
    if (origin == null || !origin.attached) return null;
    final global = origin.localToGlobal(position);
    for (final MapEntry(key: id, value: box) in _slots.entries) {
      if (!box.attached || !box.hasSize) continue;
      if ((Offset.zero & box.size).contains(box.globalToLocal(global))) {
        return id;
      }
    }
    return null;
  }
}

/// Marks the box a [SlotMap]'s positions are given in.
@internal
class SlotMapOrigin<T extends Object> extends SingleChildRenderObjectWidget {
  /// Marks [child]'s box as [map]'s origin.
  const SlotMapOrigin({required this.map, required super.child, super.key});

  /// The map.
  final SlotMap<T> map;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlot<T>(map, null);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSlot<T>).place(map, null);
}

/// Registers [child]'s box as where [id] lies in [map].
@internal
class SlotMapEntry<T extends Object> extends SingleChildRenderObjectWidget {
  /// Registers [child] as [id] in [map].
  const SlotMapEntry({
    required this.map,
    required this.id,
    required super.child,
    super.key,
  });

  /// The map.
  final SlotMap<T> map;

  /// The choice the box shows.
  final T id;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlot<T>(map, id);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSlot<T>).place(map, id);
}

// An origin when id is null.
class _RenderSlot<T extends Object> extends RenderProxyBox {
  _RenderSlot(this._map, this._id);

  SlotMap<T> _map;
  T? _id;

  void place(SlotMap<T> map, T? id) {
    if (identical(map, _map) && id == _id) return;
    if (attached) _leave();
    _map = map;
    _id = id;
    if (attached) _enter();
  }

  void _enter() {
    final id = _id;
    if (id == null) {
      _map._origin = this;
    } else {
      _map._slots[id] = this;
    }
  }

  void _leave() {
    final id = _id;
    if (id == null) {
      if (identical(_map._origin, this)) _map._origin = null;
    } else if (identical(_map._slots[id], this)) {
      _map._slots.remove(id);
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _enter();
  }

  @override
  void detach() {
    _leave();
    super.detach();
  }
}
