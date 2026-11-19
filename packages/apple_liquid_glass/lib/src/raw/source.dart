import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// What a presentation that grows out of a control carries of it: the
/// outline of its body, its tint, and its name.
///
/// A control publishes it with a [GlassSource] around its body.
@immutable
final class GlassSourceDescription {
  /// Describes a body of [shape], tinted [tint], named [semanticLabel].
  const GlassSourceDescription({
    this.shape = LiquidRoundedSuperellipse.capsule,
    this.tint,
    this.semanticLabel,
  });

  /// The outline of the control's body.
  final LiquidShape shape;

  /// The color of the control's glass at rest, or null for untinted glass.
  final Color? tint;

  /// What accessibility calls the control, which names the presentation;
  /// null for the presentation's own name.
  final String? semanticLabel;
}

/// The body of a control that a presentation around it, such as the menu
/// of a `GlassMenuAnchor`, grows out of: the presentation grows out of
/// [child]'s box and reads [description] when it opens.
///
/// A control puts it around its body and keeps its own input, focus,
/// states and semantics. Outside such a presentation it is [child] alone,
/// and inside another [GlassSource] it is [child] too: the outer one
/// describes the control. `GlassButton` and `RawGlassButton` describe
/// their glass this way; a control of your own does the same, with a
/// [GlassSourceContent] around what it draws on its glass.
///
/// A body with glass in it hands the presentation its glass, and its
/// [GlassSourceContent] rides the presentation's glass. A control with no
/// glass in its body, or no [GlassSource] at all, is drawn whole as the
/// presentation grows out of the box of everything it wraps, while the
/// presentation's glass takes over from the control's own look.
class GlassSource extends StatelessWidget {
  /// Describes [child] as [description].
  const GlassSource({
    required this.description,
    required this.child,
    super.key,
  });

  /// What the presentation carries of [child].
  final GlassSourceDescription description;

  /// The control's body.
  final Widget child;

  /// Whether a presentation above [context] grows out of the control
  /// there and presses it as it measures: a control then draws its body at
  /// rest, as `RawGlassButton` does.
  static bool isSourceAt(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSourceScope>() != null;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<GlassSourceScope>();
    if (scope == null ||
        context.getInheritedWidgetOfExactType<_Described>() != null) {
      return child;
    }
    return _Described(
      child: MotionSourceBox(source: scope.source, child: child),
    );
  }
}

/// The part of a glass control's body that a presentation growing out of
/// the control, such as the menu of a `GlassMenuAnchor`, draws in the
/// control's place while it hides the control: what the control draws on
/// its glass, such as a button's label, which rides the presentation's
/// glass as the control's glass hands over to it.
///
/// The presentation draws [child] as it is in every frame, so a label that
/// changes while the presentation shows, such as a pop-up button's title
/// taking the chosen item, rides the presentation with its new look.
/// `RawGlassButton` puts one around its label; a glass control of your own
/// puts one around the content of its [GlassSource]. Outside such a
/// presentation it is [child] alone.
class GlassSourceContent extends StatelessWidget {
  /// Marks [child] as the content of the glass around it.
  const GlassSourceContent({required this.child, super.key});

  /// What the control draws on its glass.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GlassSource.isSourceAt(context) ? RepaintBoundary(child: child) : child;
}

/// Marks the body a [GlassSource] above already describes.
class _Described extends InheritedWidget {
  const _Described({required super.child});

  @override
  bool updateShouldNotify(_Described oldWidget) => false;
}

/// Puts the [source] a presentation grows out of above [child], for a
/// [GlassSource] in it to show; a `GlassMenuAnchor` puts one around its
/// control.
class GlassSourceScope extends InheritedWidget {
  /// Puts [source] above [child].
  const GlassSourceScope({
    required this.source,
    required super.child,
    super.key,
  });

  /// The source a [GlassSource] below shows.
  final MotionSource source;

  @override
  bool updateShouldNotify(GlassSourceScope oldWidget) =>
      !identical(source, oldWidget.source);
}
