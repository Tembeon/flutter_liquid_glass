import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/effects/effect_springs.dart';
import 'package:liquid_glass_renderer/src/effects/glass_drag_builder.dart';
import 'package:meta/meta.dart';

/// {@template glass_glow}
/// If placed as a descendant of a [GlassGlowLayer], this widget will
/// send touch updates to that layer to create a glow effect.
/// {@endtemplate}
class GlassGlow extends StatelessWidget {
  /// {@macro glass_glow}
  const GlassGlow({
    required this.child,
    this.glowColor = const Color(0x3DFFFFFF),
    this.glowRadius = 1,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.gestureMode = GestureMode.listener,
    super.key,
  });

  /// The radius of the glow effect relative to the layer's shortest side.
  ///
  /// A value of 0.8 means the glow radius will be 80% of the shortest
  /// dimension (width or height) of the [GlassGlowLayer].
  ///
  /// Defaults to 1.
  final double glowRadius;

  /// The color of the glow effect.
  ///
  /// The glow will have this colors opacity at the center, and will fade out
  /// to fully transparent at the edge of the glow.
  final Color glowColor;

  /// The hit test behavior of the internal gesture handler.
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior hitTestBehavior;

  /// {@macro gesture_mode}
  ///
  /// Defaults to [GestureMode.listener].
  final GestureMode gestureMode;

  /// The child that will be painted above the glow effect.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    switch (gestureMode) {
      case GestureMode.listener:
        return Listener(
          behavior: hitTestBehavior,
          onPointerDown: (event) =>
              _handlePointer(context, event.localPosition),
          onPointerMove: (event) =>
              _handlePointer(context, event.localPosition),
          onPointerUp: (event) => _removeTouch(context),
          onPointerCancel: (event) => _removeTouch(context),
          child: child,
        );
      case GestureMode.gestureDetector:
        return GestureDetector(
          behavior: hitTestBehavior,
          onPanStart: (details) =>
              _handlePointer(context, details.localPosition),
          onPanUpdate: (details) =>
              _handlePointer(context, details.localPosition),
          onPanEnd: (details) => _removeTouch(context),
          onPanCancel: () => _removeTouch(context),
          child: child,
        );
    }
  }

  void _handlePointer(BuildContext context, Offset position) {
    final layerState = GlassGlowLayer.maybeOf(context);

    layerState?.updateTouch(
      position,
      radius: glowRadius,
      color: glowColor,
    );
  }

  void _removeTouch(BuildContext context) {
    GlassGlowLayer.maybeOf(context)?.removeTouch();
  }
}

/// {@template glass_glow_layer}
/// Represents a layer that can paint a glowing effect below its child.
///
/// Any child [GlassGlow] will send touch updates to this layer to
/// update the glow effect.
///
/// This is similar to how an `InkWell` works with a `Material` widget.
/// {@endtemplate}
class GlassGlowLayer extends StatefulWidget {
  /// {@macro glass_glow_layer}
  const GlassGlowLayer({
    required this.child,
    super.key,
  });

  /// The child that will be painted above the glow effect.
  final Widget child;

  @override
  State<GlassGlowLayer> createState() => GlassGlowLayerState();

  /// The nearest glow layer above [context], or null when there is none or
  /// [context] is no longer mounted.
  @internal
  static GlassGlowLayerState? maybeOf(BuildContext context) {
    if (!context.mounted) return null;
    return context.findAncestorStateOfType<GlassGlowLayerState>();
  }
}

@internal
class GlassGlowLayerState extends State<GlassGlowLayer>
    with TickerProviderStateMixin {
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  late final _alpha = AnimationController.unbounded(vsync: this);
  late final _radius = AnimationController.unbounded(value: 10, vsync: this);

  static final _offsetSpring = smoothSpring(const Duration(seconds: 1));

  bool _dragging = false;
  double _baseRadius = 0;
  Color _baseColor = const Color.fromARGB(0, 0, 0, 0);

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _alpha.dispose();
    _radius.dispose();
    super.dispose();
  }

  void updateTouch(
    Offset offset, {
    required double radius,
    required Color color,
  }) {
    setState(() {
      _baseRadius = radius;
      _baseColor = color;
    });

    if (!_dragging) {
      _dragging = true;
      springTo(_radius, interactiveSpring, 1, from: 0);
      springTo(_alpha, interactiveSpring, 1, from: 0);
    }

    _x.value = offset.dx;
    _y.value = offset.dy;
  }

  void removeTouch() {
    if (!_dragging) return;
    _dragging = false;
    springTo(_x, _offsetSpring, 0);
    springTo(_y, _offsetSpring, 0);
    springTo(_radius, smoothSpring(), 10);
    springTo(_alpha, smoothSpring(), 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_x, _y, _alpha, _radius]),
      builder: (context, child) {
        return _RenderGlassGlowLayerWidget(
          glowRadius: _baseRadius * _radius.value,
          glowColor: _baseColor.withValues(
            alpha: _baseColor.a * _alpha.value,
          ),
          glowOffset: Offset(_x.value, _y.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RenderGlassGlowLayerWidget extends SingleChildRenderObjectWidget {
  const _RenderGlassGlowLayerWidget({
    required this.glowRadius,
    required this.glowColor,
    required this.glowOffset,
    required super.child,
  });

  final double glowRadius;
  final Color glowColor;
  final Offset glowOffset;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderGlassGlowLayer(
      glowRadius: glowRadius,
      glowColor: glowColor,
      glowOffset: glowOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassGlowLayer renderObject,
  ) {
    renderObject
      ..glowRadius = glowRadius
      ..glowColor = glowColor
      ..glowOffset = glowOffset;
  }
}

@internal
class RenderGlassGlowLayer extends RenderProxyBox {
  RenderGlassGlowLayer({
    required this._glowRadius,
    required this._glowColor,
    required this._glowOffset,
  });

  double _glowRadius;
  double get glowRadius => _glowRadius;
  set glowRadius(double value) {
    if (_glowRadius == value) return;
    _glowRadius = value;
    markNeedsPaint();
  }

  Color _glowColor;
  Color get glowColor => _glowColor;
  set glowColor(Color value) {
    if (_glowColor == value) return;
    _glowColor = value;
    markNeedsPaint();
  }

  Offset _glowOffset;
  Offset get glowOffset => _glowOffset;
  set glowOffset(Offset value) {
    if (_glowOffset == value) return;
    _glowOffset = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_glowColor.a == 0 || _glowRadius <= 0) {
      super.paint(context, offset);
      return;
    }

    final canvas = context.canvas;

    final glowPosition = offset + _glowOffset;

    final gradient = RadialGradient(
      colors: [
        _glowColor,
        _glowColor.withValues(alpha: 0),
      ],
    );

    final radius = _glowRadius * size.shortestSide;

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: glowPosition, radius: radius),
      )
      ..blendMode = BlendMode.plus;

    canvas.drawCircle(glowPosition, radius, paint);
    super.paint(context, offset);
  }
}
