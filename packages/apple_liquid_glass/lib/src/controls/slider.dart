import 'package:apple_liquid_glass/src/foundation/colors.dart';
import 'package:apple_liquid_glass/src/foundation/frame.dart';
import 'package:apple_liquid_glass/src/foundation/style.dart';
import 'package:apple_liquid_glass/src/foundation/theme.dart';
import 'package:apple_liquid_glass/src/raw/slider.dart';
import 'package:apple_liquid_glass/src/surfaces/glass.dart';
import 'package:apple_liquid_glass/src/surfaces/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of a [GlassSlider], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the slider's states. A
/// slider looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSliderStyle {
  /// Creates a style.
  const GlassSliderStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.tickColor,
    this.builder,
  });

  /// The fill of the resting thumb (UIKit `thumbTintColor`); white in both
  /// appearances by default (slider passport).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track below the value (UIKit `minimumTrackTintColor`); the theme's
  /// primary color by default, else [GlassColors.systemBlue].
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track above the value (UIKit `maximumTrackTintColor`);
  /// [GlassSlider.inactiveTrack] by default.
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// The tick marks of a stepped slider; [GlassColors.opaqueSeparator] by
  /// default, the dot color the slider passport measured.
  final WidgetStateProperty<Color?>? tickColor;

  /// Builds the slider's look in place of the default one; the slider then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSliderBuilder? builder;

  /// This style over [other], state by state.
  GlassSliderStyle merge(GlassSliderStyle? other) {
    if (other == null) return this;
    return GlassSliderStyle(
      thumbColor: fallThrough(thumbColor, other.thumbColor),
      activeTrackColor: fallThrough(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: fallThrough(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      tickColor: fallThrough(tickColor, other.tickColor),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassSliderStyle? lerp(
    GlassSliderStyle? a,
    GlassSliderStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    WidgetStateProperty<Color?>? color(
      WidgetStateProperty<Color?>? from,
      WidgetStateProperty<Color?>? to,
    ) => WidgetStateProperty.lerp<Color?>(
      from,
      to,
      t,
      snapNull(GlassDynamicColor.lerp),
    );
    return GlassSliderStyle(
      thumbColor: color(a.thumbColor, b.thumbColor),
      activeTrackColor: color(a.activeTrackColor, b.activeTrackColor),
      inactiveTrackColor: color(a.inactiveTrackColor, b.inactiveTrackColor),
      tickColor: color(a.tickColor, b.tickColor),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSliderStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.tickColor == tickColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    thumbColor,
    activeTrackColor,
    inactiveTrackColor,
    tickColor,
    builder,
  );
}

/// An iOS 27 slider.
///
/// UIKit: `UISlider`. SwiftUI: `Slider`. Flutter: `CupertinoSlider`.
///
/// Its track and fill are plain fills and its thumb a platter that turns
/// into glass under the finger, drawn by the ambient renderer; its motion
/// is [RawGlassSlider]'s. A disabled slider draws at half opacity, as
/// UIKit does (iPhone 16 Pro, light and dark).
class GlassSlider extends StatefulWidget {
  /// Creates a slider showing [value] between [min] and [max].
  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.ticks = 0,
    this.animated = false,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// See [RawGlassSlider.value].
  final double value;

  /// See [RawGlassSlider.onChanged].
  final ValueChanged<double>? onChanged;

  /// See [RawGlassSlider.onChangeStart].
  final ValueChanged<double>? onChangeStart;

  /// See [RawGlassSlider.onChangeEnd].
  final ValueChanged<double>? onChangeEnd;

  /// See [RawGlassSlider.min].
  final double min;

  /// See [RawGlassSlider.max].
  final double max;

  /// See [RawGlassSlider.ticks].
  final int ticks;

  /// See [RawGlassSlider.animated].
  final bool animated;

  /// The look, over the theme's and the slider's defaults.
  final GlassSliderStyle? style;

  /// Where the slider writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The slider's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the slider takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the slider.
  final String? semanticLabel;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassSliderStyle styleFrom({
    Color? thumbColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? tickColor,
  }) => GlassSliderStyle(
    thumbColor: allStates(thumbColor),
    activeTrackColor: allStates(activeTrackColor),
    inactiveTrackColor: allStates(inactiveTrackColor),
    tickColor: allStates(tickColor),
  );

  /// UISlider's track above the value: black or white at 10 percent (slider
  /// passport).
  static const inactiveTrack = GlassDynamicColor.withBrightness(
    color: Color(0x1A000000),
    darkColor: Color(0x1AFFFFFF),
  );

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  GlassSliderStyle? _look;
  late GlassSliderBuilder _builder;

  // One builder per look: the core keeps the look it built until the
  // builder changes, so a style or theme change reaches it through a new
  // builder; brightness and contrast reach it through [_SliderLook].
  GlassSliderBuilder _builderFor(GlassSliderStyle look) {
    if (look == _look) return _builder;
    _look = look;
    return _builder =
        look.builder ??
        (context, details) => _SliderLook(details: details, look: look);
  }

  @override
  Widget build(BuildContext context) {
    final look = (widget.style ?? const GlassSliderStyle()).merge(
      GlassTheme.of(context).sliderStyle,
    );
    return RawGlassSlider(
      value: widget.value,
      onChanged: widget.onChanged,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
      min: widget.min,
      max: widget.max,
      ticks: widget.ticks,
      animated: widget.animated,
      statesController: widget.statesController,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      semanticLabel: widget.semanticLabel,
      builder: _builderFor(look),
    );
  }
}

class _SliderLook extends StatelessWidget {
  const _SliderLook({required this.details, required this.look});

  final GlassSliderDetails details;
  final GlassSliderStyle look;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property, Color fallback) =>
        GlassDynamicColor.resolve(
          property?.resolve(states) ?? fallback,
          context,
        );
    final active = resolve(
      look.activeTrackColor,
      GlassTheme.of(context).primaryColor ?? GlassColors.systemBlue,
    );
    Widget surface(
      GlassRole role,
      MotionSelection<GlassFrame> frame,
      Color tint, {
      GlassPart? part,
    }) => Positioned.fill(
      child: GlassSurface.live(
        role: role,
        part: part,
        glass: Glass.regular(tint: tint),
        frame: frame,
        child: const SizedBox.expand(),
      ),
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? 0.5 : 1,
      child: Stack(
        children: [
          surface(
            GlassRole.track,
            details.track,
            resolve(look.inactiveTrackColor, GlassSlider.inactiveTrack),
          ),
          surface(GlassRole.track, details.fill, active),
          if (details.ticks.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _TickPainter(
                  details.ticks,
                  resolve(look.tickColor, GlassColors.opaqueSeparator),
                ),
              ),
            ),
          surface(
            GlassRole.lens,
            details.thumb,
            resolve(look.thumbColor, const Color(0xFFFFFFFF)),
            part: GlassPart.thumb,
          ),
        ],
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.ticks, this.color);

  final List<Offset> ticks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    for (final center in ticks) {
      canvas.drawCircle(center, RawGlassSlider.tickSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      !listEquals(oldDelegate.ticks, ticks) || oldDelegate.color != color;
}
