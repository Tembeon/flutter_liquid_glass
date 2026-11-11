part of 'input_zones.dart';

final class _ZoneTarget<T extends Object> extends InputTarget {
  _ZoneTarget(this.zone) : super(zone.zone.interactions);

  final _ZoneState<T> zone;

  @override
  BuildContext get context => zone.context;

  @override
  bool get mounted => zone.mounted;

  @override
  MotionClock get clock => zone.host._clock;

  @override
  PointerLine get line => zone.host._line;

  @override
  bool get enabled => zone.zone.enabled;

  @override
  Offset toGlobal(Offset local) =>
      zone.host._box?.localToGlobal(local + zone._origin) ?? local;

  @override
  InteractionInput local(InteractionInput input) => zone._local(input);

  @override
  void write(WidgetState state, {required bool on}) =>
      zone._set(state, add: on);

  @override
  MotionHaptic? feedback(InteractionEvent event) =>
      zone.host.widget.feedback?.call(zone.id, event);

  @override
  AdjustRange get range => zone.zone.adjustRange?.value ?? AdjustRange.open;

  @override
  Offset get centre => zone.bounds.center;

  @override
  FocusNode get focusNode => zone.node;

  @override
  bool get focusable => zone._focusable;

  @override
  NavigationMode? get navigation => zone.host._navigation;

  @override
  Map<Type, Action<Intent>> get moreActions => {
    DirectionalFocusIntent: _ZoneMove<T>(zone),
    _ZoneEndIntent: _ZoneEnd<T>(zone),
  };
}

// The host's own interactions: its box as one more target, which hears
// every touch on it.
final class _HostTarget<T extends Object> extends InputTarget {
  _HostTarget(this.host) : super(host.widget.interactions);

  final _InputZonesState<T> host;

  @override
  BuildContext get context => host.context;

  @override
  bool get mounted => host.mounted;

  @override
  MotionClock get clock => host._clock;

  @override
  PointerLine get line => host._line;

  @override
  bool get enabled => true;

  @override
  Offset toGlobal(Offset local) => host._box?.localToGlobal(local) ?? local;

  // The host's box has no states of its own.
  @override
  void write(WidgetState state, {required bool on}) {}

  @override
  MotionHaptic? feedback(InteractionEvent event) =>
      host.widget.hostFeedback?.call(event);

  @override
  Offset get centre => switch (host._box) {
    final box? when box.hasSize => box.size.center(Offset.zero),
    _ => Offset.zero,
  };
}

final class _ZonesLine<T extends Object> extends PointerLine {
  _ZonesLine(this.host);

  final _InputZonesState<T> host;

  @override
  BuildContext get context => host.context;

  @override
  bool get mounted => host.mounted;

  @override
  MotionClock get clock => host._clock;

  @override
  RenderBox? get box => host._box;

  @override
  InputTarget get base => host._base;

  @override
  InputTarget? partAt(Offset position) {
    final zone = host._zoneAt(position);
    return zone != null && zone.takesInput ? zone.target : null;
  }

  @override
  bool get slides => host.widget.slides;

  @override
  void slidOnto(InputTarget part, double time, {required bool atDown}) {
    if (part is! _ZoneTarget<T>) return;
    part.play(
      ScrubChangeEvent(time: time, selected: part.zone.id, atDown: atDown),
    );
  }
}
