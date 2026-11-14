import 'dart:ui';

import 'package:meta/meta.dart';

/// What lies in [box] and outside [body], to clip a shadow to.
///
/// An outline traced from a field is one even-odd path, so adding its loops
/// to the box under the same rule leaves the box less the body with nothing
/// worked out: a menu's outline changes every frame it opens, and
/// subtracting it took a Pixel 6a's UI thread 0.28 ms each. Any other path
/// is subtracted.
@internal
Path pathOutside(Path body, Rect box) {
  final whole = Path();
  whole.addRect(box);
  if (body.fillType != PathFillType.evenOdd) {
    return Path.combine(PathOperation.difference, whole, body);
  }
  whole.fillType = PathFillType.evenOdd;
  whole.addPath(body, Offset.zero);
  return whole;
}
