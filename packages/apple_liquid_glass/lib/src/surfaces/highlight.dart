import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// The one rule by which every interactive part shows the keyboard focus
/// and the pointer over it: a glass body through its renderer, a part that
/// is not glass (a list row, a page control's platter, a clear button)
/// through the same painter.
///
/// The focus ring is Flutter's Cupertino one (`cupertino_ui` 1.1.4,
/// `CupertinoButton`'s focus outline in `lib/src/button.dart` and
/// `CupertinoFocusHalo` in `lib/src/cupertino_focus_halo.dart`, constants
/// in `lib/src/constants.dart`): a 3.5 point stroke outside the body's
/// shape in the body's color at 0.8 opacity with its lightness and
/// saturation set to 0.69 and 0.835 ([ringColor]); the color of an
/// untinted body is derived from systemBlue, as Cupertino's from
/// `activeBlue`. It is an approximation of the platform pending a
/// measurement. Under Increase Contrast the ring is opaque and its base
/// color takes its increased contrast value: an approximation, not
/// measured.
///
/// The hover response is a pressed body's wash at [hoverGain] of its
/// strength: the touch glow's wash offset added to every color channel
/// ([hoverColor]), eased in and out on the spring a press's glow fades on,
/// with no scale, lift or spot. It also lifts the
/// content by the same amount, where a press's wash lies under it. A part
/// that is not glass fills with [hoverGain] of its pressed fill instead.
/// Both are approximations waiting for the owner's eye and for a
/// measurement on macOS. Under Reduce Motion the response switches without
/// motion. Only a mouse reports hover, so touch shows none.
abstract final class GlassHighlights {
  // `CupertinoButton`'s 3.5 point outside border (`cupertino_ui` 1.1.4,
  // `lib/src/button.dart:541`).
  static const double _ringWidth = 3.5;

  // `kCupertinoFocusColorOpacity` (`cupertino_ui` 1.1.4,
  // `lib/src/constants.dart:40`).
  static const double _ringOpacity = 0.8;

  // `kCupertinoFocusColorBrightness` (`lib/src/constants.dart:41`).
  static const double _ringLightness = 0.69;

  // `kCupertinoFocusColorSaturation` (`lib/src/constants.dart:42`).
  static const double _ringSaturation = 0.835;

  // The touch glow's wash offset: how much every color channel of a
  // pressed glass body rises at the press's full wash.
  static const double _pressedWash = 0.05;

  /// The share of its pressed response a hovered part shows.
  static const double hoverGain = 0.5;

  /// The spring the hover response eases in and out on: the one a press's
  /// glow fades on; under Reduce Motion it switches at once.
  @internal
  static const Spring hoverSpring = Spring.response(
    0.5,
    reduced: Spring.immediate,
  );

  /// The color added to a hovered glass body by default: white at
  /// [hoverGain] of the touch glow's wash offset.
  static const Color hoverColor = Color.from(
    alpha: _pressedWash * hoverGain,
    red: 1,
    green: 1,
    blue: 1,
  );

  /// The ring's color for a body of [base] color, as Cupertino derives it,
  /// or [given] itself when a style gives one; opaque under
  /// [highContrast].
  static Color ringColor(
    Color? given,
    Color base, {
    required bool highContrast,
  }) {
    final color =
        given ??
        HSLColor.fromColor(base.withValues(alpha: _ringOpacity))
            .withLightness(_ringLightness)
            .withSaturation(_ringSaturation)
            .toColor();
    return highContrast ? color.withValues(alpha: 1) : color;
  }

  // From the glass's tint, else from systemBlue. A tint without a hue
  // (white, a gray) gives systemBlue's ring too, where Cupertino's rule
  // would turn it red.
  static Color _ringColorOf(
    Color? given,
    Glass glass,
    GlassTraits traits,
  ) {
    Color resolved(Color color) =>
        color is GlassDynamicColor ? color.resolvedWith(traits) : color;
    var base = resolved(glass.tint ?? GlassColors.systemBlue);
    if (HSLColor.fromColor(base).saturation < _hueless) {
      base = resolved(GlassColors.systemBlue);
    }
    return ringColor(given, base, highContrast: traits.highContrast);
  }

  static const double _hueless = 0.05;

  /// Fills the ring of [width], by default the focus ring's 3.5 points,
  /// around a body of [shape] drawn at [body], outside it, or inside it
  /// when [inside]; an [outline] gives the body's edge in place of the
  /// shape.
  static void paintRing(
    Canvas canvas,
    Color color, {
    required GlassShape shape,
    required Rect body,
    GlassOutline? outline,
    double width = _ringWidth,
    bool inside = false,
  }) {
    if (color.a <= 0 || body.isEmpty) return;
    final paint = Paint();
    paint.color = color;
    if (outline != null) {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = width * 2;
      canvas.save();
      var clip = outline.path;
      if (!inside) {
        clip = Path();
        clip.fillType = PathFillType.evenOdd;
        clip.addRect(outline.bounds.inflate(width + 1));
        clip.addPath(outline.path, Offset.zero);
      }
      canvas.clipPath(clip);
      canvas.drawPath(outline.path, paint);
      canvas.restore();
      return;
    }
    final edge = shape.pathIn(body);
    final offset = _offset(shape, body, inside ? -width : width);
    final ring = inside || offset == null ? edge : offset;
    if (offset != null) ring.addPath(inside ? offset : edge, Offset.zero);
    ring.fillType = PathFillType.evenOdd;
    canvas.drawPath(ring, paint);
  }

  // The edge [by] outside the body's, inside for a negative [by]: its
  // corners grow and shrink with the box. Null when nothing is left.
  static Path? _offset(GlassShape shape, Rect body, double by) {
    final box = body.inflate(by);
    if (box.isEmpty) return null;
    final radius = shape.radiusIn(body);
    final grown = radius <= 0 ? 0.0 : (radius + by).clamp(0.0, double.infinity);
    return switch (shape) {
      GlassSuperellipse() => GlassSuperellipse(grown),
      GlassRoundedRect() => GlassRoundedRect(grown),
      GlassOval() => shape,
    }.pathIn(box);
  }

  /// Adds [color] at [amount] to every color channel of [body], as a
  /// press's wash does.
  static void paintHover(
    Canvas canvas,
    Path body,
    Color color,
    double amount,
  ) {
    if (amount <= 0 || color.a <= 0) return;
    final paint = Paint();
    paint.blendMode = BlendMode.plus;
    paint.color = color.withValues(alpha: color.a * amount.clamp(0.0, 1.0));
    canvas.drawPath(body, paint);
  }
}

/// Whether an interactive part shows the keyboard focus and how strongly it
/// shows the pointer over it, from its states: the hover strength eases on
/// [GlassHighlights.hoverSpring].
///
/// A listener hears every change of either, the hover strength also in the
/// frame's resolve phase; while nobody listens it follows nothing.
final class GlassHighlight implements Listenable {
  /// Follows [states], or else the states [held].
  GlassHighlight({
    this._states,
    this._held = const {},
    this.reduceMotion = false,
  });

  ValueListenable<Set<WidgetState>>? _states;

  /// The states of the part, or null for a part that shows neither.
  ValueListenable<Set<WidgetState>>? get states => _states;
  set states(ValueListenable<Set<WidgetState>>? value) {
    if (identical(value, _states)) return;
    if (_listeners.isNotEmpty) _states?.removeListener(_changed);
    _states = value;
    if (_listeners.isNotEmpty) {
      value?.addListener(_changed);
      _changed();
    }
  }

  Set<WidgetState> _held;

  /// The states of a part whose owner builds it again when they change,
  /// followed while [states] is null.
  Set<WidgetState> get held => _held;
  set held(Set<WidgetState> value) {
    if (setEquals(value, _held)) return;
    _held = value;
    if (_listeners.isNotEmpty && _states == null) _changed();
  }

  /// Whether the hover response switches without motion.
  bool reduceMotion;

  final _hover = MotionValue<double>(0, spring: GlassHighlights.hoverSpring);
  final _listeners = <VoidCallback>[];
  bool _focused = false;

  bool _has(WidgetState state) => (_states?.value ?? _held).contains(state);

  /// Whether the part shows the keyboard focus.
  bool get focused => _focused;

  /// How strongly the part shows the pointer over it, 0 to 1.
  double get hovered => _hover.value.clamp(0.0, 1.0);

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      _states?.addListener(_changed);
      _focused = _has(WidgetState.focused);
      final hovered = _has(WidgetState.hovered) ? 1.0 : 0.0;
      if (_hover.target != hovered) _hover.snap(_hover.clock.now, hovered);
    }
    _listeners.add(listener);
    _hover.addRenderListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _hover.removeRenderListener(listener);
    if (_listeners.isEmpty) _states?.removeListener(_changed);
  }

  void _changed() {
    final focused = _has(WidgetState.focused);
    final hovered = _has(WidgetState.hovered) ? 1.0 : 0.0;
    if (_hover.target != hovered) {
      _hover.retarget(
        _hover.clock.now,
        hovered,
        spring: GlassHighlights.hoverSpring.resolve(
          reduceMotion: reduceMotion,
        ),
      );
    }
    if (focused == _focused) return;
    _focused = focused;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

/// Draws the focus ring and hover response of the glass body [child] that
/// follows [frame]: the hover over the body, the ring outside it, both
/// where the frame draws the body and faded with it. Plain painting after
/// the body's own, so it reads nothing behind the glass.
@internal
class GlassHighlightBox extends SingleChildRenderObjectWidget {
  /// Draws the highlights of the body [child].
  const GlassHighlightBox({
    required this.frame,
    required this.states,
    required this.focusColor,
    required this.hoverColor,
    required this.reduceMotion,
    required super.child,
    super.key,
  });

  /// The body's frames.
  final ValueListenable<GlassFrame> frame;

  /// The body's states.
  final ValueListenable<Set<WidgetState>> states;

  /// The ring's color, resolved.
  final Color focusColor;

  /// The color the hover adds, resolved.
  final Color hoverColor;

  /// Whether the hover switches without motion.
  final bool reduceMotion;

  /// Wraps [body] in the highlights [details] asks for, or returns it as
  /// it is when the surface reports no states.
  static Widget around(
    BuildContext context,
    GlassSurfaceDetails details,
    Widget body,
  ) {
    final states = details.states;
    if (states == null) return body;
    final traits = GlassTraits.of(context);
    return GlassHighlightBox(
      frame: details.frame,
      states: states,
      focusColor: GlassHighlights._ringColorOf(
        details.focusColor,
        details.glass,
        traits,
      ),
      hoverColor: details.hoverColor ?? GlassHighlights.hoverColor,
      reduceMotion: traits.reduceMotion,
      child: body,
    );
  }

  @override
  RenderGlassHighlight createRenderObject(BuildContext context) =>
      RenderGlassHighlight(
        frame: frame,
        highlight: GlassHighlight(states: states, reduceMotion: reduceMotion),
        focusColor: focusColor,
        hoverColor: hoverColor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassHighlight renderObject,
  ) {
    renderObject.frame = frame;
    renderObject.highlight.states = states;
    renderObject.highlight.reduceMotion = reduceMotion;
    renderObject.focusColor = focusColor;
    renderObject.hoverColor = hoverColor;
  }
}

/// Paints a glass body's highlights over it; see [GlassHighlightBox].
@internal
class RenderGlassHighlight extends RenderProxyBox {
  /// Paints the highlights of a body that follows [frame].
  RenderGlassHighlight({
    required this._frame,
    required this.highlight,
    required this._focusColor,
    required this._hoverColor,
  });

  /// Whether the body shows focus and hover.
  final GlassHighlight highlight;

  ValueListenable<GlassFrame> _frame;

  /// The frames the body follows.
  ValueListenable<GlassFrame> get frame => _frame;
  set frame(ValueListenable<GlassFrame> value) {
    if (value == _frame) return;
    if (attached) _frame.removeListener(_framed);
    _frame = value;
    if (attached) _frame.addListener(_framed);
    markNeedsPaint();
  }

  Color _focusColor;

  /// The ring's color.
  Color get focusColor => _focusColor;
  set focusColor(Color value) {
    if (value == _focusColor) return;
    _focusColor = value;
    markNeedsPaint();
  }

  Color _hoverColor;

  /// The color the hover adds.
  Color get hoverColor => _hoverColor;
  set hoverColor(Color value) {
    if (value == _hoverColor) return;
    _hoverColor = value;
    markNeedsPaint();
  }

  bool get _shows => highlight.focused || highlight.hovered > 0;

  void _framed() {
    if (_shows) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_framed);
    highlight.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _frame.removeListener(_framed);
    highlight.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_shows) return;
    final frame = _frame.value;
    final opacity = frame.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) return;
    final body = frame.drawnIn(size).shift(offset);
    final outline = frame.outline;
    final canvas = context.canvas;
    final hovered = highlight.hovered;
    if (hovered > 0) {
      GlassHighlights.paintHover(
        canvas,
        outline?.path.shift(offset) ?? frame.shape.pathIn(body),
        _hoverColor,
        hovered * opacity,
      );
    }
    if (!highlight.focused) return;
    final color = _focusColor.withValues(
      alpha: _focusColor.a * opacity,
    );
    if (outline != null) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      GlassHighlights.paintRing(
        canvas,
        color,
        shape: frame.shape,
        body: frame.drawnIn(size),
        outline: outline,
      );
      canvas.restore();
      return;
    }
    GlassHighlights.paintRing(canvas, color, shape: frame.shape, body: body);
  }
}

/// Draws the focus ring and hover response of a part that is not glass
/// (a list row, a page control, a clear button) by the rule of
/// [GlassHighlights]: [hoverColor] fills the part's [shape] at the hover's
/// strength, under the part, or added over it as a glass body's wash when
/// [wash]; the ring follows the shape outside the part, or inside it when
/// [inside].
class GlassHighlightPaint extends SingleChildRenderObjectWidget {
  /// Draws the highlights of the part [child].
  const GlassHighlightPaint({
    required this.focusColor,
    required this.hoverColor,
    required this.reduceMotion,
    this.states,
    this.heldStates = const {},
    this.shape = GlassShape.capsule,
    this.inside = false,
    this.wash = false,
    super.child,
    super.key,
  }) : assert(
         states == null || heldStates.length == 0,
         'Either the states or the held states.',
       );

  /// Draws the highlights of [child] with [focusColor] and [hoverColor]
  /// as given, or else from [base]: the ring Cupertino derives from it
  /// (systemBlue by default) and the wash of a glass body. The part's
  /// states are [states], or [heldStates] when its owner builds it again
  /// as they change.
  static Widget of(
    BuildContext context, {
    required Widget child,
    ValueListenable<Set<WidgetState>>? states,
    Set<WidgetState> heldStates = const {},
    Color? focusColor,
    Color? hoverColor,
    Color? base,
    GlassShape shape = GlassShape.capsule,
    bool inside = false,
    bool wash = false,
  }) {
    final traits = GlassTraits.of(context);
    Color resolved(Color color) =>
        color is GlassDynamicColor ? color.resolvedWith(traits) : color;
    return GlassHighlightPaint(
      states: states,
      heldStates: heldStates,
      focusColor: GlassHighlights.ringColor(
        focusColor == null ? null : resolved(focusColor),
        resolved(base ?? GlassColors.systemBlue),
        highContrast: traits.highContrast,
      ),
      hoverColor: resolved(hoverColor ?? GlassHighlights.hoverColor),
      reduceMotion: traits.reduceMotion,
      shape: shape,
      inside: inside,
      wash: wash,
      child: child,
    );
  }

  /// The part's states, or null when [heldStates] are them.
  final ValueListenable<Set<WidgetState>>? states;

  /// The part's states when its owner builds it again as they change.
  final Set<WidgetState> heldStates;

  /// The ring's color, resolved.
  final Color focusColor;

  /// The hover's color at full strength, resolved.
  final Color hoverColor;

  /// Whether the hover switches without motion.
  final bool reduceMotion;

  /// The part's shape in its box.
  final GlassShape shape;

  /// Whether the ring lies inside the part, for a part clipped at its
  /// edge.
  final bool inside;

  /// Whether the hover adds to the part's colors over it, as a glass
  /// body's does, rather than filling under it.
  final bool wash;

  @override
  RenderGlassHighlightPaint createRenderObject(BuildContext context) =>
      RenderGlassHighlightPaint(
        highlight: GlassHighlight(
          states: states,
          held: heldStates,
          reduceMotion: reduceMotion,
        ),
        focusColor: focusColor,
        hoverColor: hoverColor,
        shape: shape,
        inside: inside,
        wash: wash,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassHighlightPaint renderObject,
  ) {
    renderObject.highlight.states = states;
    renderObject.highlight.held = heldStates;
    renderObject.highlight.reduceMotion = reduceMotion;
    renderObject.focusColor = focusColor;
    renderObject.hoverColor = hoverColor;
    renderObject.shape = shape;
    renderObject.inside = inside;
    renderObject.wash = wash;
  }
}

/// Paints the highlights of a part that is not glass; see
/// [GlassHighlightPaint].
@internal
class RenderGlassHighlightPaint extends RenderProxyBox {
  /// Paints the highlights a part's [highlight] shows.
  RenderGlassHighlightPaint({
    required this.highlight,
    required this._focusColor,
    required this._hoverColor,
    required this._shape,
    required this._inside,
    required this._wash,
  });

  /// Whether the part shows focus and hover.
  final GlassHighlight highlight;

  Color _focusColor;

  /// The ring's color.
  Color get focusColor => _focusColor;
  set focusColor(Color value) {
    if (value == _focusColor) return;
    _focusColor = value;
    markNeedsPaint();
  }

  Color _hoverColor;

  /// The hover's color at full strength.
  Color get hoverColor => _hoverColor;
  set hoverColor(Color value) {
    if (value == _hoverColor) return;
    _hoverColor = value;
    markNeedsPaint();
  }

  GlassShape _shape;

  /// The part's shape in its box.
  GlassShape get shape => _shape;
  set shape(GlassShape value) {
    if (value == _shape) return;
    _shape = value;
    markNeedsPaint();
  }

  bool _inside;

  /// Whether the ring lies inside the part.
  bool get inside => _inside;
  set inside(bool value) {
    if (value == _inside) return;
    _inside = value;
    markNeedsPaint();
  }

  bool _wash;

  /// Whether the hover adds to the part's colors over it.
  bool get wash => _wash;
  set wash(bool value) {
    if (value == _wash) return;
    _wash = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    highlight.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    highlight.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final body = offset & size;
    final hovered = highlight.hovered;
    if (hovered > 0 && !_wash && _hoverColor.a > 0) {
      final paint = Paint();
      paint.color = _hoverColor.withValues(alpha: _hoverColor.a * hovered);
      context.canvas.drawPath(_shape.pathIn(body), paint);
    }
    super.paint(context, offset);
    final canvas = context.canvas;
    if (hovered > 0 && _wash) {
      GlassHighlights.paintHover(
        canvas,
        _shape.pathIn(body),
        _hoverColor,
        hovered,
      );
    }
    if (!highlight.focused) return;
    GlassHighlights.paintRing(
      canvas,
      _focusColor,
      shape: _shape,
      body: body,
      inside: _inside,
    );
  }
}
