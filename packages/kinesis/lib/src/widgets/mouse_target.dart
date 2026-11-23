import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:kinesis/src/widgets/input_target.dart';

/// The box of an input target as the mouse tracker sees it: the target's
/// cursor and the mouse entering and leaving it.
///
/// The tracker reads [cursor] after every enter and exit and after every
/// frame, so the cursor is kept: resolved once per change of what it is
/// made of while the mouse is over the target, and on the next read
/// otherwise.
@internal
mixin MouseTarget on RenderBox implements MouseTrackerAnnotation {
  /// The target the mouse enters, or null once its host left the tree.
  InputTarget? get mouseTarget;

  /// The cursor the target asks for now.
  MouseCursor get currentCursor;

  MouseCursor? _cursor;

  /// The target's states, or what its cursor is made of, changed: a cursor
  /// that changes under the mouse asks for a frame, after which the
  /// tracker shows it.
  void cursorChanged() {
    final target = mouseTarget;
    if (target == null || !target.mouseOver) {
      _cursor = null;
      return;
    }
    final cursor = currentCursor;
    if (cursor == _cursor) return;
    _cursor = cursor;
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  MouseCursor get cursor =>
      mouseTarget == null ? MouseCursor.defer : _cursor ??= currentCursor;

  @override
  PointerEnterEventListener get onEnter => _entered;

  @override
  PointerExitEventListener get onExit => _exited;

  void _entered(PointerEnterEvent event) =>
      mouseTarget?.hover(event.localPosition, inside: true);

  void _exited(PointerExitEvent event) =>
      mouseTarget?.hover(event.localPosition, inside: false);

  @override
  bool get validForMouseTracker => attached && mouseTarget != null;
}
