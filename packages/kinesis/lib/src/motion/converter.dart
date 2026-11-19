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

  /// A plain double, at rest within 0.1: a tenth of a logical pixel for a
  /// length. An opacity or a fraction gives `MotionValue` its own
  /// `restDistance`.
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

  /// Creates a converter for [TextStyle] that preserves non-numeric fields of
  /// [base] (`fontFamily`, `decoration`, `fontFeatures`, etc.) while animating
  /// `fontSize`, `fontWeight`, `letterSpacing`, `wordSpacing`, `height`,
  /// `decorationThickness`, `color`, and any OpenType [variationAxes] (such as
  /// `wght`, `opsz`, or `GRAD`).
  static MotionConverter<TextStyle> textStyle(
    TextStyle base, {
    List<String> variationAxes = const [],
  }) => TextStyleMotionConverter(base, variationAxes: variationAxes);

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

/// A [MotionConverter] for [TextStyle] that interpolates typographic metrics,
/// color channels, and variable-font [variationAxes] while preserving
/// non-numeric properties from [base].
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

  static const int _fixedDimensions = 10;

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
    final fontSize = value.fontSize ?? base.fontSize ?? 14;
    final weight = (value.fontWeight ?? base.fontWeight ?? FontWeight.w400)
        .value
        .toDouble();
    final letterSpacing = value.letterSpacing ?? base.letterSpacing ?? 0;
    final wordSpacing = value.wordSpacing ?? base.wordSpacing ?? 0;
    final height = value.height ?? base.height ?? 0;
    final decorationThickness =
        value.decorationThickness ?? base.decorationThickness ?? 1;
    final color = value.color ?? base.color ?? const Color(0xFF000000);
    out[0] = fontSize;
    out[1] = weight;
    out[2] = letterSpacing;
    out[3] = wordSpacing;
    out[4] = height;
    out[5] = decorationThickness;
    out[6] = color.a;
    out[7] = color.r;
    out[8] = color.g;
    out[9] = color.b;
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
    final fontSize = values[0] < 0 ? 0.0 : values[0];
    final weightIndex = ((values[1] / 100).round().clamp(1, 9)) - 1;
    final fontWeight = FontWeight.values[weightIndex];
    final height = values[4] > 0 ? values[4] : null;
    final color = Color.from(
      alpha: values[6].clamp(0, 1),
      red: values[7].clamp(0, 1),
      green: values[8].clamp(0, 1),
      blue: values[9].clamp(0, 1),
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
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: values[2],
      wordSpacing: values[3],
      height: height,
      decorationThickness: values[5] < 0 ? 0.0 : values[5],
      color: color,
      fontVariations: variations,
    );
  }
}
