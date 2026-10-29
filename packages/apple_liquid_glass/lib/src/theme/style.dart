import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// [lerp] with a null end jumping to the other end at the middle: in a
/// style a null value falls through to what lies under it, so it does not
/// fade.
@internal
T? Function(T?, T?, double) snapNull<T>(T? Function(T?, T?, double) lerp) =>
    (a, b, t) => a == null || b == null ? (t < 0.5 ? a : b) : lerp(a, b, t);

/// [first] over [second], state by state: a state [first] resolves to
/// null takes [second]'s value.
@internal
WidgetStateProperty<T?>? fallThrough<T>(
  WidgetStateProperty<T?>? first,
  WidgetStateProperty<T?>? second,
) {
  if (first == null) return second;
  if (second == null) return first;
  return _FallThrough(first, second);
}

@immutable
final class _FallThrough<T> implements WidgetStateProperty<T?> {
  const _FallThrough(this.first, this.second);

  final WidgetStateProperty<T?> first;
  final WidgetStateProperty<T?> second;

  @override
  T? resolve(Set<WidgetState> states) =>
      first.resolve(states) ?? second.resolve(states);

  @override
  bool operator ==(Object other) =>
      other is _FallThrough<T> &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

/// [enabled] in every state but disabled, where it is [disabled].
@internal
@immutable
final class ByState<T> implements WidgetStateProperty<T?> {
  /// Creates the property.
  const ByState(this.enabled, this.disabled);

  /// The value of every state but disabled.
  final T? enabled;

  /// The value of the disabled state.
  final T? disabled;

  @override
  T? resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled) ? disabled : enabled;

  @override
  bool operator ==(Object other) =>
      other is ByState<T> &&
      other.enabled == enabled &&
      other.disabled == disabled;

  @override
  int get hashCode => Object.hash(enabled, disabled);
}

/// A [ByState], or null when both values are.
@internal
WidgetStateProperty<T?>? byState<T>(T? enabled, T? disabled) =>
    enabled == null && disabled == null ? null : ByState(enabled, disabled);

/// [value] in every state, or null.
@internal
WidgetStateProperty<T?>? allStates<T>(T? value) =>
    value == null ? null : WidgetStatePropertyAll(value);

/// [unselected] in every state but selected, where it is [selected].
@internal
@immutable
final class BySelection<T> implements WidgetStateProperty<T?> {
  /// Creates the property.
  const BySelection(this.unselected, this.selected);

  /// The value of every state but selected.
  final T? unselected;

  /// The value of the selected state.
  final T? selected;

  @override
  T? resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) ? selected : unselected;

  @override
  bool operator ==(Object other) =>
      other is BySelection<T> &&
      other.unselected == unselected &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(unselected, selected);
}
