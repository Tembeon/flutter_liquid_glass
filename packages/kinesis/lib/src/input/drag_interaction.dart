import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/src/input/interaction.dart';
import 'package:kinesis/src/input/interaction_event.dart';
import 'package:kinesis/src/input/interaction_input.dart';

/// Details of a drag at one input.
@immutable
final class DragInteractionDetails {
  /// Describes a drag at [time].
  const DragInteractionDetails({
    required this.time,
    required this.translation,
    required this.velocity,
  });

  /// The input's motion time.
  final double time;

  /// The travel since the slop, along the drag's axis when it has one.
  final Offset translation;

  /// The finger's velocity at the release, in logical pixels per second;
  /// zero before it.
  final Offset velocity;
}

/// A finger dragging past a slop.
///
/// UIKit: `UIPanGestureRecognizer`. SwiftUI: `DragGesture`. Flutter:
/// `PanGestureRecognizer`.
///
/// Travel counts from past the slop. The drag holds the touch once it
/// starts, unless a scroll view around the region scrolls along its
/// [axis]. With [followsTextDirection], a right-to-left touch is heard
/// mirrored, so the travel follows the reading direction. Feed the travel
/// to a `RubberBand` and a release to a `Projection`.
///
/// A drag that moves the box its region lies in, as a sheet does under the
/// finger, measures in [global] coordinates.
class DragInteraction extends Interaction {
  /// Creates a drag along [axis], or free when [axis] is null, past
  /// UIKit's pan hysteresis of 10 points.
  DragInteraction({
    super.role,
    this.axis,
    this.slop = 10,
    this.contends = false,
    this.global = false,
    this.followsTextDirection = false,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
  });

  /// The axis the drag follows, or null for any direction.
  Axis? axis;

  /// How far the finger travels before the drag starts, once the arena
  /// gave the region the touch ([PointerAcceptedInput]).
  double slop;

  /// Whether the drag takes touches from the controls inside its region
  /// ([contendsWithControls]): while another gesture still competes for the
  /// touch, it starts past the farther of [slop] and the arena's slop.
  final bool contends;

  /// Whether the drag measures the finger in global coordinates
  /// ([PointerDownInput.globalPosition]) instead of its region's: for a
  /// drag that moves its own region, whose coordinates would follow the
  /// finger, and whose scale at the touch would scale the travel. Global
  /// positions are not mirrored.
  bool global;

  /// Whether the travel follows the reading direction: a touch whose
  /// [PointerDownInput.textDirection] is right to left is heard mirrored,
  /// region positions only.
  final bool followsTextDirection;

  /// Called when the drag starts.
  ValueChanged<DragInteractionDetails>? onStart;

  /// Called on every move of a started drag.
  ValueChanged<DragInteractionDetails>? onUpdate;

  /// Called on the release of a started drag.
  ValueChanged<DragInteractionDetails>? onEnd;

  /// Called when a started drag ends without a release, with the time.
  void Function(double t)? onCancel;

  int? _pointer;
  Offset _origin = Offset.zero;
  double _width = 0;
  bool _mirrored = false;
  bool _started = false;
  bool _accepted = false;
  Set<Axis> _scrollAxes = const {};

  @override
  bool get dragged => _started;

  @override
  bool get contendsWithControls => contends;

  // The slop the drag started past: winning the arena later does not
  // shorten a travel that is already under way.
  double? _startSlop;
  double _touchSlop = 0;

  double get _slop {
    if (_startSlop case final started?) return started;
    return _accepted || !contends ? slop : math.max(slop, _touchSlop);
  }

  Offset _at(Offset local, Offset globalPosition) =>
      global ? globalPosition : local;

  Offset _along(Offset delta) => switch (axis) {
    Axis.horizontal => Offset(delta.dx, 0),
    Axis.vertical => Offset(0, delta.dy),
    null => delta,
  };

  Offset _travel(Offset at) {
    final delta = _along(at - _origin);
    final distance = delta.distance;
    if (distance <= _slop) return Offset.zero;
    return delta * ((distance - _slop) / distance);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        if (_pointer != null || !accepts(input)) return InteractionUpdate.none;
        _pointer = input.pointer;
        _width = input.regionSize.width;
        _started = false;
        _accepted = false;
        _startSlop = null;
        _touchSlop = input.touchSlop;
        _scrollAxes = input.scrollAxes;
        _mirrored =
            followsTextDirection && input.textDirection == TextDirection.rtl;
        final local = _mirrored ? input.mirrored(_width) : input;
        _origin = _at(local.position, local.globalPosition);
        return InteractionUpdate.none;
      case PointerAcceptedInput() when input.pointer == _pointer:
        _accepted = true;
        return InteractionUpdate.none;
      case PointerMoveInput() when input.pointer == _pointer:
        final local = _mirrored ? input.mirrored(_width) : input;
        final at = _at(local.position, local.globalPosition);
        final travel = _travel(at);
        final details = DragInteractionDetails(
          time: input.time,
          translation: travel,
          velocity: Offset.zero,
        );
        if (!_started) {
          if (travel == Offset.zero) return InteractionUpdate.none;
          _started = true;
          _startSlop = _slop;
          onStart?.call(details);
          final holds = axis == null || !_scrollAxes.contains(axis);
          return InteractionUpdate(claims: holds, recognizes: holds);
        }
        onUpdate?.call(details);
        return InteractionUpdate.none;
      case PointerUpInput() when input.pointer == _pointer:
        final started = _started;
        _pointer = null;
        _started = false;
        if (!started) return const InteractionUpdate(fails: true);
        final local = _mirrored ? input.mirrored(_width) : input;
        onEnd?.call(
          DragInteractionDetails(
            time: input.time,
            translation: _travel(_at(local.position, local.globalPosition)),
            velocity: _along(global ? local.globalVelocity : local.velocity),
          ),
        );
        return InteractionUpdate.none;
      case PointerCancelInput() when input.pointer == _pointer:
        final started = _started;
        _pointer = null;
        _started = false;
        if (started) onCancel?.call(input.time);
        return const InteractionUpdate(fails: true);
      default:
        return InteractionUpdate.none;
    }
  }
}
