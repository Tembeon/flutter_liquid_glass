import 'dart:ui';

import 'package:meta/meta.dart';

/// Whether [a] and [b] share any area. An empty rect meets nothing, wherever
/// it lies: content clipped away, or a picture that draws nothing, reaches
/// no read.
@internal
bool meets(Rect a, Rect b) => !a.isEmpty && !b.isEmpty && a.overlaps(b);

/// Whether [outer] holds all of [inner].
@internal
bool encloses(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;
