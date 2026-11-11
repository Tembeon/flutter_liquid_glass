import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';

/// What a presentation that grows out of a control, such as the menu of a
/// `GlassMenuAnchor`, and the control tell each other.
///
/// The presentation makes the link and puts it above the control with
/// [GlassSourceScope]. A control that finds it with [maybeOf] calls [lend]
/// when it builds: it then takes no touch, key or focus of its own, the
/// presentation's input region takes them and calls [onPressed] on a tap,
/// Space, Enter or the accessibility tap, and the control draws its body at
/// rest, which the presentation presses as it measures it. The control shows
/// [source] around its body (a `MotionSourceBox`), so the presentation
/// grows out of that box and hides it while it shows, and describes its
/// glass: [shape], [tint], and [look], what of it the presentation's glass
/// carries as it grows. `RawGlassButton` lends itself and `GlassButton`
/// describes its glass; a control of your own does the same.
///
/// What lends nothing keeps its input and stays drawn under the
/// presentation, which then grows out of the box of everything it wraps.
final class GlassSourceLink {
  /// Creates a link no control has taken, over the presentation's [states].
  GlassSourceLink({required this.states});

  /// The link of the closest [GlassSourceScope] around [context], or null.
  static GlassSourceLink? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSourceScope>()?.link;

  /// The states of the presentation's input region, which the lending
  /// control's look follows: the keyboard focus and the mouse over it.
  final ValueListenable<Set<WidgetState>> states;

  /// The source the lending control shows around its body.
  final MotionSource source = MotionSource(debugLabel: 'GlassSourceLink');

  Object? _owner;

  /// Whether a control lent itself.
  bool get isLent => _owner != null;

  /// What a tap on the control does, as the control's own `onPressed`; null
  /// while it does nothing.
  VoidCallback? get onPressed => _onPressed;
  VoidCallback? _onPressed;

  /// The outline of the control's body.
  GlassShape get shape => _shape;
  GlassShape _shape = GlassShape.capsule;

  /// What accessibility reads for the control, or null for its label.
  String? get semanticLabel => _semanticLabel;
  String? _semanticLabel;

  /// The color of the control's glass at rest, or null for untinted glass.
  Color? tint;

  /// What the presentation's glass carries of the control as it grows out
  /// of it, such as its label without its glass; null for nothing.
  Widget? look;

  /// [owner] lends its input to the presentation: [onPressed] is its tap,
  /// [shape] the outline of its body, [semanticLabel] its name. Called
  /// again whenever it builds.
  void lend(
    Object owner, {
    required VoidCallback? onPressed,
    GlassShape shape = GlassShape.capsule,
    String? semanticLabel,
  }) {
    _owner = owner;
    _onPressed = onPressed;
    _shape = shape;
    _semanticLabel = semanticLabel;
  }

  /// [owner] no longer lends itself, if it did.
  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _onPressed = null;
    _shape = GlassShape.capsule;
    _semanticLabel = null;
    tint = null;
    look = null;
  }
}

/// Puts [link] above [child], for the control in it to lend itself to.
class GlassSourceScope extends InheritedWidget {
  /// Puts [link] above [child].
  const GlassSourceScope({
    required this.link,
    required super.child,
    super.key,
  });

  /// The link.
  final GlassSourceLink link;

  @override
  bool updateShouldNotify(GlassSourceScope oldWidget) =>
      !identical(link, oldWidget.link);
}
