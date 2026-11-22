import 'dart:math' as math;
import 'dart:ui'
    show Color, FontVariation, FontWeight, Offset, Radius, Rect, Size;

import 'package:flutter/painting.dart'
    show Alignment, BorderRadius, EdgeInsets, TextStyle;
import 'package:kinesis/src/motion/rest.dart';

/// Maps a value of type [T] to the doubles an animation moves and back.
///
/// Every component moves on the same animation. [restDistance] is how far a
/// component may still swing from its target before the swing is
/// invisible.
abstract class MotionConverter<T> {
  /// Creates a converter.
  const MotionConverter();

  /// A plain double. Its unit is unknown, so it rests by its swing
  /// ([MotionRest.unitless]): within 0.1 after a move of 50 or more, as a
  /// length in logical pixels does, and within 1/500 of a smaller move, so a
  /// 0..1 progress or an index lands without a step.
  static const MotionConverter<double> single = _SingleConverter();

  /// An [Offset] as dx and dy, at rest within 0.1 logical pixels.
  static const MotionConverter<Offset> offset = _OffsetConverter();

  /// A [Size] as width and height, at rest within 0.1 logical pixels.
  static const MotionConverter<Size> size = _SizeConverter();

  /// A [Rect] as its left, top, right and bottom edges, at rest within 0.1
  /// logical pixels.
  static const MotionConverter<Rect> rect = _RectConverter();

  /// A [Radius] as x and y, at rest within 0.1 logical pixels.
  static const MotionConverter<Radius> radius = _RadiusConverter();

  /// An sRGB [Color] as its alpha, red, green and blue channels, each
  /// clamped to 0..1 on the way back, at rest within 0.002 (half an 8-bit
  /// step).
  static const MotionConverter<Color> color = _ColorConverter();

  /// An [EdgeInsets] as left, top, right and bottom, at rest within 0.1
  /// logical pixels.
  static const MotionConverter<EdgeInsets> edgeInsets = _EdgeInsetsConverter();

  /// A [BorderRadius] as the x and y radii of its four corners, at rest
  /// within 0.1 logical pixels.
  static const MotionConverter<BorderRadius> borderRadius =
      _BorderRadiusConverter();

  /// An [Alignment] as x and y, at rest within 0.002.
  static const MotionConverter<Alignment> alignment = _AlignmentConverter();

  /// The built-in converter for [T]; throws for a type without one.
  static MotionConverter<T> of<T>() {
    final MotionConverter<Object?> converter = switch (T) {
      const (double) => single,
      const (Offset) => offset,
      const (Size) => size,
      const (Rect) => rect,
      const (Radius) => radius,
      const (Color) => color,
      const (EdgeInsets) => edgeInsets,
      const (BorderRadius) => borderRadius,
      const (Alignment) => alignment,
      const (TextStyle) => const TextStyleMotionConverter(TextStyle()),
      _ => throw ArgumentError(
        'No built-in MotionConverter for $T; pass a converter.',
      ),
    };
    return converter as MotionConverter<T>;
  }

  /// The number of components a value has.
  int get dimensions;

  /// The swing of one component below which it counts as at rest.
  double get restDistance;

  /// The rest of a value whose largest swing since it last rested is
  /// [swing]; [restDistance] for a converter that knows its unit.
  double restFor(double swing) => restDistance;

  /// Writes the components of [value] into [out], starting at index 0.
  void write(T value, List<double> out);

  /// Reads a value from the components in [values].
  T read(List<double> values);
}

abstract class _LengthConverter<T> extends MotionConverter<T> {
  const _LengthConverter();

  @override
  double get restDistance => MotionRest.length;
}

class _SingleConverter extends _LengthConverter<double> {
  const _SingleConverter();

  @override
  double restFor(double swing) => MotionRest.unitless(swing);

  @override
  int get dimensions => 1;

  @override
  void write(double value, List<double> out) => out[0] = value;

  @override
  double read(List<double> values) => values[0];
}

class _OffsetConverter extends _LengthConverter<Offset> {
  const _OffsetConverter();

  @override
  int get dimensions => 2;

  @override
  void write(Offset value, List<double> out) {
    out[0] = value.dx;
    out[1] = value.dy;
  }

  @override
  Offset read(List<double> values) => Offset(values[0], values[1]);
}

class _SizeConverter extends _LengthConverter<Size> {
  const _SizeConverter();

  @override
  int get dimensions => 2;

  @override
  void write(Size value, List<double> out) {
    out[0] = value.width;
    out[1] = value.height;
  }

  @override
  Size read(List<double> values) => Size(values[0], values[1]);
}

class _RectConverter extends _LengthConverter<Rect> {
  const _RectConverter();

  @override
  int get dimensions => 4;

  @override
  void write(Rect value, List<double> out) {
    out[0] = value.left;
    out[1] = value.top;
    out[2] = value.right;
    out[3] = value.bottom;
  }

  @override
  Rect read(List<double> values) =>
      Rect.fromLTRB(values[0], values[1], values[2], values[3]);
}

class _RadiusConverter extends _LengthConverter<Radius> {
  const _RadiusConverter();

  @override
  int get dimensions => 2;

  @override
  void write(Radius value, List<double> out) {
    out[0] = value.x;
    out[1] = value.y;
  }

  @override
  Radius read(List<double> values) => Radius.elliptical(values[0], values[1]);
}

class _ColorConverter extends MotionConverter<Color> {
  const _ColorConverter();

  @override
  int get dimensions => 4;

  @override
  double get restDistance => MotionRest.opacity;

  @override
  void write(Color value, List<double> out) {
    out[0] = value.a;
    out[1] = value.r;
    out[2] = value.g;
    out[3] = value.b;
  }

  @override
  Color read(List<double> values) => Color.from(
    alpha: values[0].clamp(0, 1),
    red: values[1].clamp(0, 1),
    green: values[2].clamp(0, 1),
    blue: values[3].clamp(0, 1),
  );
}

class _EdgeInsetsConverter extends _LengthConverter<EdgeInsets> {
  const _EdgeInsetsConverter();

  @override
  int get dimensions => 4;

  @override
  void write(EdgeInsets value, List<double> out) {
    out[0] = value.left;
    out[1] = value.top;
    out[2] = value.right;
    out[3] = value.bottom;
  }

  @override
  EdgeInsets read(List<double> values) =>
      EdgeInsets.fromLTRB(values[0], values[1], values[2], values[3]);
}

class _BorderRadiusConverter extends _LengthConverter<BorderRadius> {
  const _BorderRadiusConverter();

  @override
  int get dimensions => 8;

  @override
  void write(BorderRadius value, List<double> out) {
    out[0] = value.topLeft.x;
    out[1] = value.topLeft.y;
    out[2] = value.topRight.x;
    out[3] = value.topRight.y;
    out[4] = value.bottomRight.x;
    out[5] = value.bottomRight.y;
    out[6] = value.bottomLeft.x;
    out[7] = value.bottomLeft.y;
  }

  @override
  BorderRadius read(List<double> values) => BorderRadius.only(
    topLeft: Radius.elliptical(
      values[0] < 0 ? 0 : values[0],
      values[1] < 0 ? 0 : values[1],
    ),
    topRight: Radius.elliptical(
      values[2] < 0 ? 0 : values[2],
      values[3] < 0 ? 0 : values[3],
    ),
    bottomRight: Radius.elliptical(
      values[4] < 0 ? 0 : values[4],
      values[5] < 0 ? 0 : values[5],
    ),
    bottomLeft: Radius.elliptical(
      values[6] < 0 ? 0 : values[6],
      values[7] < 0 ? 0 : values[7],
    ),
  );
}

class _AlignmentConverter extends MotionConverter<Alignment> {
  const _AlignmentConverter();

  @override
  int get dimensions => 2;

  @override
  double get restDistance => MotionRest.opacity;

  @override
  void write(Alignment value, List<double> out) {
    out[0] = value.x;
    out[1] = value.y;
  }

  @override
  Alignment read(List<double> values) => Alignment(values[0], values[1]);
}

/// A [MotionConverter] for [TextStyle] that interpolates `fontSize`,
/// `fontWeight`, `letterSpacing`, `wordSpacing`, `height`,
/// `decorationThickness`, `color` and the OpenType [variationAxes] (such as
/// `wght`, `opsz` or `GRAD`) while keeping the non-numeric fields of [base]
/// (`fontFamily`, `decoration`, `fontFeatures` and the like).
///
/// A metric or color that neither the style nor [base] sets stays unset, so
/// a style merged over `DefaultTextStyle` still inherits it. One set on only
/// one side of a change switches halfway through, straight to its own value.
final class TextStyleMotionConverter extends MotionConverter<TextStyle> {
  /// Creates a [TextStyle] converter grounded on [base].
  const TextStyleMotionConverter(
    this.base, {
    this.variationAxes = const [],
  });

  /// The base style whose non-numeric properties (`fontFamily`, `decoration`,
  /// `fontStyle`, etc.) are preserved on read-back.
  final TextStyle base;

  /// OpenType variable-font axis tags (4-character strings such as `'wght'`,
  /// `'opsz'`, or `'GRAD'`) animated alongside the standard style metrics.
  final List<String> variationAxes;

  // Metrics 0..5 and color channels 6..9, each times its presence, a 1 where
  // the style sets it and a 0 where it does not: 10..15 for the metrics, 16
  // for the color.
  static const int _presence = 10;
  static const int _colorPresence = 16;
  static const int _fixedDimensions = 17;

  @override
  int get dimensions => _fixedDimensions + variationAxes.length;

  @override
  double get restDistance => MotionRest.opacity;

  static double _variationValue(
    List<FontVariation>? variations,
    String axis,
    double fallback,
  ) {
    if (variations != null) {
      for (final variation in variations) {
        if (variation.axis == axis) return variation.value;
      }
    }
    return fallback;
  }

  @override
  void write(TextStyle value, List<double> out) {
    void metric(int i, double? amount) {
      out[i] = amount ?? 0;
      out[_presence + i] = amount == null ? 0 : 1;
    }

    metric(0, value.fontSize ?? base.fontSize);
    metric(1, (value.fontWeight ?? base.fontWeight)?.value.toDouble());
    metric(2, value.letterSpacing ?? base.letterSpacing);
    metric(3, value.wordSpacing ?? base.wordSpacing);
    metric(4, value.height ?? base.height);
    metric(5, value.decorationThickness ?? base.decorationThickness);
    final color = value.color ?? base.color;
    out[6] = color?.a ?? 0;
    out[7] = color?.r ?? 0;
    out[8] = color?.g ?? 0;
    out[9] = color?.b ?? 0;
    out[_colorPresence] = color == null ? 0 : 1;
    for (var i = 0; i < variationAxes.length; i++) {
      final axis = variationAxes[i];
      final fallback = _variationValue(base.fontVariations, axis, 0);
      out[_fixedDimensions + i] = _variationValue(
        value.fontVariations,
        axis,
        fallback,
      );
    }
  }

  @override
  TextStyle read(List<double> values) {
    double? metric(int i) {
      final presence = values[_presence + i];
      return presence < 0.5 ? null : values[i] / presence;
    }

    final fontSize = metric(0);
    final weight = metric(1);
    final height = metric(4);
    final decorationThickness = metric(5);
    final colorPresence = values[_colorPresence];
    final color = colorPresence < 0.5
        ? null
        : Color.from(
            alpha: (values[6] / colorPresence).clamp(0, 1),
            red: (values[7] / colorPresence).clamp(0, 1),
            green: (values[8] / colorPresence).clamp(0, 1),
            blue: (values[9] / colorPresence).clamp(0, 1),
          );
    var variations = base.fontVariations;
    if (variationAxes.isNotEmpty) {
      final list = <FontVariation>[];
      if (base.fontVariations case final existing?) {
        for (final variation in existing) {
          if (!variationAxes.contains(variation.axis)) {
            list.add(variation);
          }
        }
      }
      for (var i = 0; i < variationAxes.length; i++) {
        list.add(FontVariation(variationAxes[i], values[_fixedDimensions + i]));
      }
      variations = list;
    }
    return base.copyWith(
      fontSize: fontSize == null ? null : math.max(fontSize, 0),
      fontWeight: weight == null
          ? null
          : FontWeight.values[(weight / 100).round().clamp(1, 9) - 1],
      letterSpacing: metric(2),
      wordSpacing: metric(3),
      height: height != null && height > 0 ? height : null,
      decorationThickness: decorationThickness == null
          ? null
          : math.max(decorationThickness, 0),
      color: color,
      fontVariations: variations,
    );
  }
}
