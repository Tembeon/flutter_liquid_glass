import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:kinesis/src/clock.dart';
import 'package:kinesis/src/transaction.dart';
import 'package:meta/meta.dart';

/// A render object that places its presentation from this frame's layout,
/// in the frame's resolve phase: after the whole view is laid out, before
/// compositing bits and paint.
///
/// [resolve] may retarget values and mark paint and composited layers; it
/// must not mark layout. Values it changes publish at once
/// ([MotionClock.resolve]), so what draws them shows this frame's
/// presentation, never the previous one.
@internal
mixin MotionResolveHost on RenderObject {
  /// Places the presentation from this frame's layout.
  void resolve();

  /// Asks for [resolve] in this frame's resolve phase; call it from layout.
  void scheduleResolve() {
    final owner = this.owner;
    if (owner != null) _ResolveOwner.of(owner)._schedule(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ResolveOwner.of(owner)._hosts.add(this);
  }

  @override
  void detach() {
    final owner = this.owner;
    if (owner != null) _ResolveOwner._release(owner, this);
    super.detach();
  }
}

/// The resolve phase of one view: a child of the view's pipeline owner,
/// which Flutter flushes after the view's own layout and before its
/// compositing bits and paint.
///
/// It stays adopted while hosts are attached to the view and drops itself
/// with the last one, so the view's owner has no children when it is
/// disposed.
final class _ResolveOwner extends PipelineOwner {
  factory _ResolveOwner.of(PipelineOwner view) {
    final existing = _owners[view];
    if (existing != null) return existing;
    final owner = _ResolveOwner._(view);
    _owners[view] = owner;
    _live++;
    MotionTransaction.onLayoutTransaction = _clearAfterFrame;
    view.adoptChild(owner);
    return owner;
  }

  // It owns no render objects, so it never has semantics to send; Flutter
  // still asks for the callback once semantics turn on.
  _ResolveOwner._(this._view) : super(onSemanticsUpdate: (_) {});

  static final Expando<_ResolveOwner> _owners = Expando<_ResolveOwner>();
  static int _live = 0;

  final PipelineOwner _view;
  final Set<MotionResolveHost> _hosts = {};
  final Set<MotionResolveHost> _scheduled = {};

  static void _release(PipelineOwner view, MotionResolveHost host) {
    final owner = _owners[view];
    if (owner == null) return;
    owner._hosts.remove(host);
    owner._scheduled.remove(host);
    if (owner._hosts.isNotEmpty) return;
    _owners[view] = null;
    view.dropChild(owner);
    if (--_live == 0) MotionTransaction.onLayoutTransaction = null;
  }

  static bool _clearing = false;

  static void _clearAfterFrame() {
    if (_clearing) return;
    _clearing = true;
    final scheduler = SchedulerBinding.instance;
    scheduler.addPostFrameCallback((_) {
      _clearing = false;
      MotionTransaction.clearLayout();
    }, debugLabel: 'MotionTransaction.clearLayout');
    scheduler.scheduleFrame();
  }

  void _schedule(MotionResolveHost host) => _scheduled.add(host);

  @override
  void flushLayout() {
    super.flushLayout();
    if (_scheduled.isEmpty) return;
    final hosts = List<MotionResolveHost>.of(_scheduled);
    _scheduled.clear();
    hosts.sort((a, b) => a.depth - b.depth);
    MotionClock.instance.resolve(() {
      for (final host in hosts) {
        if (host.attached && identical(host.owner, _view)) {
          guardMotion(host.resolve, 'while resolving a layout motion');
        }
      }
    });
  }
}
