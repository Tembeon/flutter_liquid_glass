import 'dart:ui' show ImageFilter;

import 'package:apple_liquid_glass/src/renderer/flat.dart';
import 'package:apple_liquid_glass/src/renderer/renderer.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// The liquid renderer: every surface is liquid glass, and the members of
/// a group share one glass layer.
///
/// A surface outside a group draws as a group of one, and a track as a
/// plain fill, as iOS draws one. A lens or knob is an opaque platter at
/// rest and gets a glass layer of its own over the platter only while it
/// is lifted; on fake glass the layer keeps the lifted optics for the whole
/// lift and the glass's fade carries the change, a NEAR trade that keeps
/// the fake layer from rebuilding every frame. A frame
/// reaches the renderer's live shape and live layer without a rebuild.
/// Layers use the fitted iOS 27 settings: clear for a lone clear surface,
/// regular in the ambient brightness ([GlassTraits.brightness]) otherwise.
/// Under Reduce Transparency the surfaces draw flat, an unmeasured
/// stand-in for iOS's frosted glass.
@internal
final class LiquidGlassRenderer extends GlassRenderer {
  /// Creates the liquid renderer.
  const LiquidGlassRenderer() : fake = false;

  /// Creates the renderer that draws fake glass.
  const LiquidGlassRenderer.fake() : fake = true;

  /// Whether every layer draws fake glass, which shows no touch glow.
  final bool fake;

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) {
    if (GlassTraits.of(context).reduceTransparency ||
        details.role == GlassRole.track) {
      return const FlatGlassRenderer().buildSurface(context, details);
    }
    if (_lifts(details.role)) return _LiquidLens(details: details, fake: fake);
    final surface = _LiquidSurface(details: details, glows: !fake);
    if (_LiquidGroupScope.maybeOf(context) != null) return surface;
    return _LiquidGroup(fake: fake, glass: details.glass, child: surface);
  }

  @override
  Widget buildGroup(BuildContext context, GlassGroupDetails details) {
    if (GlassTraits.of(context).reduceTransparency) return details.child;
    return _LiquidGroup(
      fake: fake,
      blend: details.merge.spacing,
      child: details.child,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassRenderer && other.fake == fake;

  @override
  int get hashCode => Object.hash(LiquidGlassRenderer, fake);

  /// The appearance of [glass] in [brightness].
  static LiquidGlassAppearance appearanceOf(
    Glass glass,
    Brightness brightness,
  ) {
    final tint = glass.tint;
    return switch ((glass.isClear, tint)) {
      (true, null) => const LiquidGlassAppearance.ios27Clear(),
      (true, final Color tint) => LiquidGlassAppearance.ios27Clear(tint: tint),
      (false, null) => LiquidGlassAppearance.ios27Regular(
        brightness: brightness,
      ),
      (false, final Color tint) => LiquidGlassAppearance.ios27Regular(
        brightness: brightness,
        tint: tint,
      ),
    };
  }

  /// The shadows of a body of [role] lifted by [lift].
  ///
  /// Engineering defaults from Morph, not measured: the control, menu and
  /// sheet shadow is Morph's body shadow; a lens's or knob's is Morph's
  /// floating platter shadow, which drops from 1.5 to 3.5 and blurs from 3
  /// to 9 as it lifts.
  static List<BoxShadow> shadowsOf(GlassRole role, {double lift = 0}) {
    final l = lift.clamp(0.0, 1.0);
    return switch (role) {
      GlassRole.control || GlassRole.menu || GlassRole.sheet => const [
        BoxShadow(
          color: Color(0x14000000),
          offset: Offset(0, 4),
          blurRadius: 16,
        ),
      ],
      GlassRole.lens || GlassRole.knob => [
        BoxShadow(
          color: const Color(0x1A000000),
          offset: Offset(0, 1.5 + 2 * l),
          blurRadius: 3 + 6 * l,
        ),
      ],
      GlassRole.bar || GlassRole.track => const [],
    };
  }
}

bool _lifts(GlassRole role) => role == GlassRole.knob || role == GlassRole.lens;

/// The settings of a lens or knob lifted by [lift]: UIKit's lens
/// configuration (read from UIKit, notes private) bends what is behind a
/// resting small lens by 50 and blurs it by 6, a lifted one bends it by 9
/// without blur, and a large lens rests clear. Morph's engineering factors,
/// not measured, double the bend, part the colors along the rim and
/// brighten the highlight by half as the lens lifts.
LiquidGlassSettings _lensSettings(
  LiquidGlassSettings base,
  double lift, {
  required bool small,
}) {
  final l = lift.clamp(0.0, 1.0);
  final displacement = small ? 50 + (9 - 50) * l : 9 * l;
  return base.copyWith(
    frost: small ? 6 * (1 - l) : 0,
    refractionAmount: displacement * 2,
    dispersion: -0.25 * l,
    highlight: base.highlight * (1 + 0.5 * l),
  );
}

// A group's layer is an ancestor: writes into it wait for the end of the
// frame when they come while the framework builds, lays out or paints, or
// from dispose.
void _afterFrame(VoidCallback callback) =>
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());

bool get _framing =>
    SchedulerBinding.instance.schedulerPhase ==
    SchedulerPhase.persistentCallbacks;

class _LiquidSurface extends StatefulWidget {
  const _LiquidSurface({required this.details, required this.glows});

  final GlassSurfaceDetails details;
  final bool glows;

  @override
  State<_LiquidSurface> createState() => _LiquidSurfaceState();
}

class _LiquidSurfaceState extends State<_LiquidSurface> {
  late final _shape = ValueNotifier(_shapeFrame);
  late LiquidGlassAppearance _appearance;
  late Brightness _brightness;
  _LiquidGroupState? _group;
  LiquidGlassGlow? _glow;
  bool _glowPending = false;

  ValueListenable<GlassFrame> get _source => widget.details.frame;

  LiquidGlassShapeFrame get _shapeFrame {
    final frame = _source.value;
    final role = widget.details.role;
    final tint = frame.tint;
    return LiquidGlassShapeFrame(
      shape: frame.shape,
      appearance: _lifts(role)
          ? LiquidGlassAppearance(
              visibility: FlatGlassLook.glassness(frame.lift),
            )
          : tint == null
          ? _appearance
          : LiquidGlassRenderer.appearanceOf(
              widget.details.glass.isClear
                  ? Glass.clear(tint: tint)
                  : Glass.regular(tint: tint),
              _brightness,
            ),
      shadows: LiquidGlassRenderer.shadowsOf(role, lift: frame.lift),
      rect: frame.rect,
      scaleX: frame.scaleX,
      scaleY: frame.scaleY,
    );
  }

  @override
  void initState() {
    super.initState();
    _source.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(_LiquidSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.frame != _source) {
      oldWidget.details.frame.removeListener(_onFrame);
      _source.addListener(_onFrame);
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onFrame);
    _leave(_group);
    _shape.dispose();
    super.dispose();
  }

  void _leave(_LiquidGroupState? group) {
    if (group == null || _glow == null) return;
    _glow = null;
    _afterFrame(() => group.reportGlow(this, null));
  }

  void _onFrame() {
    _shape.value = _shapeFrame;
    if (_framing) {
      _writeGlowLater();
    } else {
      _writeGlow();
    }
  }

  void _writeGlow() {
    if (!widget.glows) return;
    final glow = _glowOf(_source.value);
    if (glow == _glow) return;
    _glow = glow;
    _group!.reportGlow(this, glow);
  }

  void _writeGlowLater() {
    if (!widget.glows || _glowPending) return;
    _glowPending = true;
    _afterFrame(() {
      _glowPending = false;
      if (mounted) _writeGlow();
    });
  }

  LiquidGlassGlow? _glowOf(GlassFrame frame) {
    final glow = frame.glow;
    if (glow == null) return null;
    final box = context.findRenderObject()! as RenderBox;
    if (!box.hasSize) {
      _writeGlowLater();
      return null;
    }
    final size = box.size;
    final body = frame.drawnIn(size);
    final transform = frame.contentTransformIn(size);
    return _group!.toLayer(
      box,
      LiquidGlassGlow(
        bounds: body,
        cornerRadius: switch (frame.shape) {
          LiquidRoundedSuperellipse(:final borderRadius) ||
          LiquidRoundedRectangle(:final borderRadius) => borderRadius,
          LiquidOval() => body.shortestSide / 2,
        },
        center: transform == null
            ? glow.center
            : MatrixUtils.transformPoint(transform, glow.center),
        radius: glow.radius * (frame.scaleX + frame.scaleY) / 2,
        gain: glow.gainOn(widget.details.glass, _brightness),
        wash: glow.wash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = _LiquidGroupScope.maybeOf(context)!;
    if (!identical(group, _group)) {
      _leave(_group);
      _group = group;
    }
    _brightness = GlassTraits.of(context).brightness;
    _appearance = LiquidGlassRenderer.appearanceOf(
      widget.details.glass,
      _brightness,
    );
    _shape.value = _shapeFrame;
    if (_source.value.glow != null || _glow != null) _writeGlowLater();
    return LiquidGlass.live(
      frame: _shape,
      grouped: group.blends,
      child: widget.details.child,
    );
  }
}

class _LiquidGroup extends StatefulWidget {
  const _LiquidGroup({
    required this.fake,
    required this.child,
    this.blend,
    this.glass,
    this.lens,
  });

  final bool fake;
  final double? blend;

  /// The glass of a lone surface, or null for a group.
  final Glass? glass;

  /// The lone lens or knob whose lift sets the layer's optics and whose
  /// glass sets its settings, or null.
  final GlassSurfaceDetails? lens;

  final Widget child;

  @override
  State<_LiquidGroup> createState() => _LiquidGroupState();
}

class _LiquidGroupState extends State<_LiquidGroup> {
  final _layer = ValueNotifier(const LiquidGlassLayerFrame());
  Object? _lit;
  LiquidGlassSettings _base = const LiquidGlassSettings();

  ValueListenable<GlassFrame>? get _lens => widget.lens?.frame;

  @override
  void initState() {
    super.initState();
    _lens?.addListener(_writeSettings);
  }

  @override
  void didUpdateWidget(_LiquidGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lens?.frame != _lens) {
      oldWidget.lens?.frame.removeListener(_writeSettings);
      _lens?.addListener(_writeSettings);
    }
  }

  LiquidGlassSettings get _settings {
    final lens = widget.lens;
    if (lens == null) return _base;
    final fake = widget.fake || !ImageFilter.isShaderFilterSupported;
    return _lensSettings(
      _base,
      fake ? 1 : lens.frame.value.lift,
      small: lens.role == GlassRole.knob,
    );
  }

  void _writeSettings() {
    final settings = _settings;
    final frame = _layer.value;
    if (settings == frame.settings) return;
    _layer.value = LiquidGlassLayerFrame(settings: settings, glow: frame.glow);
  }

  bool get blends => widget.blend != null;

  /// Sets the layer's glow to [glow] of [member], or clears it when [glow]
  /// is null and [member] was the one lit.
  void reportGlow(Object member, LiquidGlassGlow? glow) {
    if (!mounted || (glow == null && !identical(member, _lit))) return;
    _lit = glow == null ? null : member;
    final frame = _layer.value;
    if (glow == frame.glow) return;
    _layer.value = LiquidGlassLayerFrame(settings: frame.settings, glow: glow);
  }

  /// [glow] of [member] in the layer's coordinates.
  LiquidGlassGlow toLayer(RenderBox member, LiquidGlassGlow glow) {
    final transform = member.getTransformTo(
      context.findRenderObject()! as RenderBox,
    );
    return LiquidGlassGlow(
      bounds: MatrixUtils.transformRect(transform, glow.bounds),
      cornerRadius: glow.cornerRadius,
      center: MatrixUtils.transformPoint(transform, glow.center),
      radius: glow.radius,
      gain: glow.gain,
      wash: glow.wash,
    );
  }

  @override
  void dispose() {
    _lens?.removeListener(_writeSettings);
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _base = ((widget.lens?.glass ?? widget.glass)?.isClear ?? false)
        ? LiquidGlassSettings.ios27Clear()
        : LiquidGlassSettings.ios27Regular(
            brightness: GlassTraits.of(context).brightness,
          );
    _writeSettings();
    final blend = widget.blend;
    final child = widget.child;
    return LiquidGlassLayer.live(
      frame: _layer,
      fake: widget.fake,
      child: _LiquidGroupScope(
        group: this,
        blends: blends,
        child: blend == null
            ? child
            : LiquidGlassBlendGroup(blend: blend, child: child),
      ),
    );
  }
}

class _LiquidGroupScope extends InheritedWidget {
  const _LiquidGroupScope({
    required this.group,
    required this.blends,
    required super.child,
  });

  final _LiquidGroupState group;
  final bool blends;

  static _LiquidGroupState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidGroupScope>()?.group;

  @override
  bool updateShouldNotify(_LiquidGroupScope oldWidget) =>
      group != oldWidget.group || blends != oldWidget.blends;
}

class _LiquidLens extends StatefulWidget {
  const _LiquidLens({required this.details, required this.fake});

  final GlassSurfaceDetails details;
  final bool fake;

  @override
  State<_LiquidLens> createState() => _LiquidLensState();
}

class _LiquidLensState extends State<_LiquidLens> {
  late bool _lifted = _isLifted;

  ValueListenable<GlassFrame> get _source => widget.details.frame;

  bool get _isLifted => _source.value.lift > FlatGlassLook.restingLift;

  @override
  void initState() {
    super.initState();
    _source.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(_LiquidLens oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.frame != _source) {
      oldWidget.details.frame.removeListener(_onFrame);
      _source.addListener(_onFrame);
    }
    _lifted = _isLifted;
  }

  @override
  void dispose() {
    _source.removeListener(_onFrame);
    super.dispose();
  }

  void _onFrame() {
    if (_isLifted == _lifted) return;
    if (_framing) {
      _afterFrame(() {
        if (mounted) setState(() => _lifted = _isLifted);
      });
      return;
    }
    setState(() => _lifted = _isLifted);
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        FlatGlassRenderer.flatSurface(context, details, underGlass: true),
        if (_lifted)
          Positioned.fill(
            child: _LiquidGroup(
              fake: widget.fake,
              lens: details,
              child: _LiquidSurface(
                glows: !widget.fake,
                details: GlassSurfaceDetails(
                  role: details.role,
                  glass: details.glass,
                  frame: details.frame,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
