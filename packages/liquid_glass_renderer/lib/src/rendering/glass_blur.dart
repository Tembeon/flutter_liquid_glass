import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// What a glass's frost blur reads past the backdrop's edge.
@internal
const glassBlurTileMode = TileMode.mirror;

/// The color matrix that leaves a color as it is.
@internal
const identityColorMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// A filter that leaves what it filters as it is.
@internal
const ui.ImageFilter identityColorFilter = ui.ColorFilter.matrix(
  identityColorMatrix,
);
