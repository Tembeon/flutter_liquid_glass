import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The message a tooltip names its child with, for a control under it that
/// reads it as its own tooltip: a glass button's semantics node is its own,
/// and a tooltip around it would name a node the screen reader passes by.
///
/// `GlassTooltip` puts one around its child; a tooltip of an app's own does
/// the same for the raw controls under it. A `RawGlassButton` takes the
/// message and counts itself in [claims] while it stands under the scope;
/// the tooltip names nothing itself while any does.
final class RawTooltipScope extends InheritedWidget {
  /// Gives [message] to the controls of [child], counted in [claims].
  const RawTooltipScope({
    required this.message,
    required this.claims,
    required super.child,
    super.key,
  });

  /// The tooltip's message.
  final String message;

  /// How many controls under the scope read [message] as their own.
  final ValueNotifier<int> claims;

  /// The scope around [context], or null.
  static RawTooltipScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RawTooltipScope>();

  @override
  bool updateShouldNotify(RawTooltipScope oldWidget) =>
      message != oldWidget.message || !identical(claims, oldWidget.claims);
}

/// Takes the message of the [RawTooltipScope] around a control as its own,
/// counted while it stands there.
@internal
mixin RawTooltipClaim<T extends StatefulWidget> on State<T> {
  ValueNotifier<int>? _claims;

  /// The message of the tooltip around the control, or null.
  String? tooltip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = RawTooltipScope.maybeOf(context);
    tooltip = scope?.message;
    final claims = scope?.claims;
    if (identical(claims, _claims)) return;
    _claims?.value -= 1;
    _claims = claims;
    claims?.value += 1;
  }

  @override
  void dispose() {
    _claims?.value -= 1;
    _claims = null;
    super.dispose();
  }
}
