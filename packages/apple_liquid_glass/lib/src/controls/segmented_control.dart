import 'package:apple_liquid_glass/src/controls/selector.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/glass.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/style.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// One segment of a [GlassSegmentedControl].
///
/// UIKit: a segment of `UISegmentedControl`. SwiftUI: a tagged view in a
/// `Picker`. Flutter: `ButtonSegment`.
@immutable
final class GlassSegment<T> {
  /// Creates a segment that stands for [value].
  const GlassSegment({
    required this.value,
    required this.label,
    this.enabled = true,
    this.width,
    this.semanticLabel,
  });

  /// The value the segment stands for.
  final T value;

  /// What the segment shows, usually a [Text] or an icon.
  final Widget label;

  /// Whether the segment can be selected (UIKit
  /// `setEnabled(_:forSegmentAt:)`). A disabled segment draws its label at
  /// half opacity (not measured); a touch on it selects nothing and the
  /// arrow keys skip it.
  final bool enabled;

  /// The width of the segment in points, or null to share the room with
  /// the other segments (UIKit `setWidth(_:forSegmentAt:)`).
  final double? width;

  /// What accessibility reads for the segment; null lets its label speak.
  final String? semanticLabel;
}

/// The look of a [GlassSegmentedControl], like Flutter's `ButtonStyle`.
///
/// [backgroundColor] and [thumbColor] are resolved against the control's
/// states, [foregroundColor] and [textStyle] against each segment's, which
/// include [WidgetState.selected]. A control looks a field up in its own
/// style, then in the theme's, then in its defaults, state by state: a
/// property that gives null for a state leaves that state to the next one.
@immutable
class GlassSegmentedStyle {
  /// Creates a style.
  const GlassSegmentedStyle({
    this.backgroundColor,
    this.thumbColor,
    this.foregroundColor,
    this.textStyle,
    this.builder,
  });

  /// The track (UIKit `backgroundColor`); [GlassColors.tertiarySystemFill]
  /// by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The resting lens (UIKit `selectedSegmentTintColor`);
  /// [GlassSegmentedControl.thumb] by default.
  final WidgetStateProperty<Color?>? thumbColor;

  /// The color of a segment's label; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The text style of a segment's label: 13 points, regular, and medium
  /// when selected, by default (segmented control passport).
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// Builds the control's look in place of the default one; the control
  /// then ignores [backgroundColor] and [thumbColor]. Null leaves it to the
  /// theme's builder, then the default look.
  final GlassSelectorBuilder? builder;

  /// This style over [other], state by state.
  GlassSegmentedStyle merge(GlassSegmentedStyle? other) {
    if (other == null) return this;
    return GlassSegmentedStyle(
      backgroundColor: fallThrough(backgroundColor, other.backgroundColor),
      thumbColor: fallThrough(thumbColor, other.thumbColor),
      foregroundColor: fallThrough(foregroundColor, other.foregroundColor),
      textStyle: fallThrough(textStyle, other.textStyle),
      builder: builder ?? other.builder,
    );
  }

  /// The style between [a] and [b] at [t]; the builder switches at the
  /// middle.
  static GlassSegmentedStyle? lerp(
    GlassSegmentedStyle? a,
    GlassSegmentedStyle? b,
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
    return GlassSegmentedStyle(
      backgroundColor: color(a.backgroundColor, b.backgroundColor),
      thumbColor: color(a.thumbColor, b.thumbColor),
      foregroundColor: color(a.foregroundColor, b.foregroundColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        a.textStyle,
        b.textStyle,
        t,
        snapNull(TextStyle.lerp),
      ),
      builder: t < 0.5 ? a.builder : b.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSegmentedStyle &&
      other.backgroundColor == backgroundColor &&
      other.thumbColor == thumbColor &&
      other.foregroundColor == foregroundColor &&
      other.textStyle == textStyle &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    thumbColor,
    foregroundColor,
    textStyle,
    builder,
  );
}

/// An iOS 27 segmented control.
///
/// UIKit: `UISegmentedControl`. SwiftUI: `Picker` with
/// `.pickerStyle(.segmented)`. Flutter: `CupertinoSlidingSegmentedControl`.
///
/// Its track is a plain fill and its lens a platter that turns into clear
/// glass under a dragging finger, drawn by the ambient renderer; the lifted
/// lens bends the labels under its rim but does not magnify them, as
/// UIKit's does not (segmented control passport), and the label inside it
/// takes the selected style. Its motion is [RawGlassSelector]'s with
/// [GlassSelectorMotion.segmented]. Labels follow the text scale up to
/// [maxTextScale], and a segment is as wide as the wider of its label's
/// regular and selected styles. A disabled control draws at half opacity,
/// as UIKit does (iPhone 16 Pro, light and dark).
class GlassSegmentedControl<T> extends StatelessWidget {
  /// Creates a segmented control showing [groupValue] selected.
  const GlassSegmentedControl({
    required this.segments,
    required this.groupValue,
    required this.onChanged,
    this.onReselected,
    this.proportionalWidth = false,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// The segments, in reading order.
  final List<GlassSegment<T>> segments;

  /// The value of the selected segment, or null for none
  /// (`UISegmentedControl.noSegment`); see [RawGlassSelector.selectedIndex].
  final T? groupValue;

  /// Called with the value of the segment the user selects; with
  /// [onReselected] null too, the control is disabled. A control whose
  /// [groupValue] does not follow returns to it.
  final ValueChanged<T>? onChanged;

  /// Called with the selected segment's value when the user selects it
  /// again: to deselect it, set [groupValue] to null.
  final ValueChanged<T>? onReselected;

  /// Whether segments are as wide as their labels rather than equal (UIKit
  /// `apportionsSegmentWidthsByContent`).
  final bool proportionalWidth;

  /// The look, over the theme's and the control's defaults.
  final GlassSegmentedStyle? style;

  /// Where the control writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the control as a whole.
  final String? semanticLabel;

  /// The largest text scale the labels follow, not measured.
  static const double maxTextScale = 1.4;

  /// UISegmentedControl's resting lens: white, and systemGray2's dark
  /// colors in the dark (read from UIKit's color tables, notes private).
  static const thumb = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF636366),
    highContrastColor: Color(0xFFFFFFFF),
    darkHighContrastColor: Color(0xFF7C7C80),
  );

  static const _label = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const _selectedLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// A style from plain colors and text styles; a null value leaves the
  /// field to the theme, then the default.
  static GlassSegmentedStyle styleFrom({
    Color? backgroundColor,
    Color? thumbColor,
    Color? foregroundColor,
    TextStyle? textStyle,
    TextStyle? selectedTextStyle,
  }) => GlassSegmentedStyle(
    backgroundColor: allStates(backgroundColor),
    thumbColor: allStates(thumbColor),
    foregroundColor: allStates(foregroundColor),
    textStyle: textStyle == null && selectedTextStyle == null
        ? null
        : BySelection(textStyle, selectedTextStyle),
  );

  GlassSegmentedStyle _defaults(BuildContext context) => GlassSegmentedStyle(
    backgroundColor: const WidgetStatePropertyAll(
      GlassColors.tertiarySystemFill,
    ),
    thumbColor: const WidgetStatePropertyAll(thumb),
    foregroundColor: WidgetStatePropertyAll(
      GlassTheme.of(context).colorScheme?.label ?? GlassColors.label,
    ),
    textStyle: const BySelection(_label, _selectedLabel),
  );

  int? get _selectedIndex {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].value == groupValue) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final themed = GlassTheme.of(context).segmentedStyle;
    final look = (style ?? const GlassSegmentedStyle())
        .merge(themed)
        .merge(_defaults(context));
    final onChanged = this.onChanged;
    final onReselected = this.onReselected;
    return RawGlassSelector(
      itemCount: segments.length,
      selectedIndex: groupValue == null ? null : _selectedIndex,
      onChanged: onChanged == null
          ? null
          : (index) => onChanged(segments[index].value),
      onReselected: onReselected == null
          ? null
          : (index) => onReselected(segments[index].value),
      disabledItems: {
        for (var i = 0; i < segments.length; i++)
          if (!segments[i].enabled) i,
      },
      itemWidths: segments.any((segment) => segment.width != null)
          ? [for (final segment in segments) segment.width]
          : null,
      proportionalWidth: proportionalWidth,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      itemBuilder: (context, index, states) =>
          _SegmentLabel(segment: segments[index], look: look, states: states),
      builder:
          style?.builder ??
          themed?.builder ??
          (context, details) => _SegmentedLook(details: details, look: look),
    );
  }
}

class _SegmentedLook extends StatelessWidget {
  const _SegmentedLook({required this.details, required this.look});

  final GlassSelectorDetails details;
  final GlassSegmentedStyle look;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    Color resolve(WidgetStateProperty<Color?>? property) =>
        GlassDynamicColor.resolve(property!.resolve(states)!, context);
    Widget surface(
      GlassRole role,
      ValueListenable<GlassFrame> frame,
      Color tint,
    ) => GlassSurface.live(
      role: role,
      glass: Glass.regular(tint: tint),
      frame: frame,
      child: const SizedBox.expand(),
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? 0.5 : 1,
      child: Stack(
        children: [
          Positioned.fill(
            child: surface(
              GlassRole.track,
              details.body,
              resolve(look.backgroundColor),
            ),
          ),
          details.items(
            lens: details.selectedIndex == null
                ? null
                : surface(
                    GlassRole.lens,
                    details.lens,
                    resolve(look.thumbColor),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A segment's label in its style, as wide as the wider of its regular and
/// selected looks.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.look,
    required this.states,
  });

  final GlassSegment<Object?> segment;
  final GlassSegmentedStyle look;
  final Set<WidgetState> states;

  Widget _styled(BuildContext context, Set<WidgetState> states) {
    final color = GlassDynamicColor.resolve(
      look.foregroundColor!.resolve(states)!,
      context,
    );
    return IconTheme.merge(
      data: IconThemeData(color: color),
      child: DefaultTextStyle.merge(
        style: resolveGlassText(
          look.textStyle!.resolve(states)!.copyWith(color: color),
          context,
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: segment.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = states.contains(WidgetState.selected);
    final other = selected
        ? states.difference({WidgetState.selected})
        : {...states, WidgetState.selected};
    final label = MediaQuery.withClampedTextScaling(
      maxScaleFactor: GlassSegmentedControl.maxTextScale,
      child: Builder(
        builder: (context) => IndexedStack(
          alignment: Alignment.center,
          children: [_styled(context, states), _styled(context, other)],
        ),
      ),
    );
    final semanticLabel = segment.semanticLabel;
    final labelled = semanticLabel == null
        ? label
        : Semantics(
            label: semanticLabel,
            child: ExcludeSemantics(child: label),
          );
    return segment.enabled ? labelled : Opacity(opacity: 0.5, child: labelled);
  }
}
