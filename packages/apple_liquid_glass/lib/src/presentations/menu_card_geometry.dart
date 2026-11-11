import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The frame card [index] shows at in the menu's content, scale included,
/// with the root list [visible] high in a menu [width] wide.
@internal
Rect menuCardShown(
  List<MenuCard> cards,
  int index,
  double width,
  double visible,
) {
  final card = cards[index];
  final s = card.scale;
  final rect = index == 0 ? Rect.fromLTWH(0, 0, width, visible) : card.rect;
  return Rect.fromLTWH(
    width / 2 + (rect.left - width / 2) * s,
    rect.top * s,
    rect.width * s,
    rect.height * s,
  );
}

/// Card [index]'s [header] now: its columns move from those of the row it
/// grew out of, scaled by the parent's scale, to its own.
@internal
MenuPlaced menuCardHeaderAt(
  List<MenuCard> cards,
  int index,
  MenuPlaced header,
) {
  final card = cards[index];
  final parent = cards[index - 1];
  final source = card.source;
  if (source == null || source >= parent.layout.targets.length) return header;
  final target = parent.layout.targets[source];
  if (target.element < 0) return header;
  final row = parent.layout.elements[target.element];
  final ratio = parent.scale / card.scale;
  final center = card.layout.width / 2;
  final q = card.progress.clamp(0.0, 1.0);
  double column(double source) {
    final from = center + (source - center) * ratio;
    return from + (source - from) * q;
  }

  final image = row.imageCenter;
  return MenuPlaced(
    kind: header.kind,
    rect: header.rect,
    entry: header.entry,
    title: header.title,
    imageCenter: image == null || header.imageCenter == null
        ? header.imageCenter
        : column(image),
    titleStart: column(row.titleStart),
    titleEnd: column(row.titleEnd),
    target: header.target,
  );
}
