import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// Builds the content of a toast, usually a [GlassToast]; [toast]
/// dismisses it, as its action does.
typedef GlassToastBuilder = Widget Function(
  BuildContext context,
  GlassToastEntry toast,
);

/// A toast [showGlassToast] showed.
final class GlassToastEntry {
  GlassToastEntry._(this._host, this._builder, this._duration);

  _GlassToasterState? _host;
  final GlassToastBuilder _builder;
  final Duration? _duration;
  bool _hasAction = false;

  /// Whether the toast is still there: false from its dismissal on, while
  /// it leaves.
  bool get isShown => _host != null;

  /// Dismisses the toast, which leaves on its spring. A toast already
  /// dismissed stays so: it is safe to call more than once, and after the
  /// toast timed out.
  void dismiss() {
    final host = _host;
    _host = null;
    host?._remove(this);
  }
}

/// Shows [builder]'s toast on the nearest [GlassToaster] above [context],
/// for [duration] or, when [duration] is null, until it is dismissed.
///
/// ```dart
/// showGlassToast(
///   context: context,
///   builder: (context, toast) => GlassToast(
///     title: const Text('Moved to Archive'),
///     action: GlassButton.plain(
///       onPressed: () {
///         toast.dismiss();
///         unarchive();
///       },
///       child: const Text('Undo'),
///     ),
///   ),
/// );
/// ```
///
/// Any context under the toaster works, a page's or its navigator's: the
/// toast belongs to the toaster and outlives the page that showed it. It
/// throws without a toaster.
GlassToastEntry showGlassToast({
  required BuildContext context,
  required GlassToastBuilder builder,
  Duration? duration = GlassToaster.duration,
}) {
  final scope = context.getInheritedWidgetOfExactType<_ToasterScope>();
  if (scope == null) {
    throw FlutterError.fromParts([
      ErrorSummary('showGlassToast found no GlassToaster.'),
      ErrorHint(
        'Put a GlassToaster above the navigator, such as in '
        'WidgetsApp.builder under the GlassScope.',
      ),
    ]);
  }
  return scope.state._show(builder, duration);
}

/// Where the toasts of [showGlassToast] show: over [child], at the top
/// center of its safe area.
///
/// UIKit has no toast; this is the package's own. Flutter:
/// `ScaffoldMessenger` with its `SnackBar`s.
///
/// Put it above the navigator, under the `GlassScope` and the theme its
/// toasts draw with, as in `WidgetsApp.builder`. It stacks the toasts down
/// from the top, newest first, at most [maxShown]: a newer one dismisses
/// the oldest. Each toast leaves on its own after its duration, unless a
/// mouse rests on it or a finger holds it; a toast with an action stays
/// while a screen reader navigates (`MediaQuery.accessibleNavigationOf`),
/// as a `SnackBar` does. A swipe up dismisses a toast.
///
/// The toasts are not modal: they take no focus, and touches beside them
/// reach the app. Screen readers hear a toast as it shows (a live region)
/// and can dismiss it. With no toast the toaster adds nothing to [child]:
/// no layer, no frame.
///
/// Fidelity. Nothing is measured: iOS shows its own notices, such as a
/// paste's, as glass capsules at the top, and the toast follows that look;
/// the sizes, springs and durations are this package's.
class GlassToaster extends StatefulWidget {
  /// Creates a toaster over [child].
  const GlassToaster({required this.child, super.key});

  /// The app under the toasts.
  final Widget child;

  /// How long a toast shows by default.
  static const Duration duration = Duration(seconds: 5);

  /// The most toasts shown at once.
  static const int maxShown = 3;

  /// The space between the safe area's edges and the toasts.
  static const double margin = 8;

  /// The space between two toasts.
  static const double gap = 8;

  /// The widest a toast grows.
  static const double maxWidth = 400;

  @override
  State<GlassToaster> createState() => _GlassToasterState();
}

class _GlassToasterState extends State<GlassToaster> {
  final _entries = <GlassToastEntry>[];

  GlassToastEntry _show(GlassToastBuilder builder, Duration? duration) {
    final entry = GlassToastEntry._(this, builder, duration);
    setState(() => _entries.insert(0, entry));
    while (_entries.length > GlassToaster.maxShown) {
      _entries.last.dismiss();
    }
    return entry;
  }

  void _remove(GlassToastEntry entry) {
    if (mounted) setState(() => _entries.remove(entry));
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry._host = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ToasterScope(
    state: this,
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(child: _ToastStack(entries: List.of(_entries))),
      ],
    ),
  );
}

class _ToasterScope extends InheritedWidget {
  const _ToasterScope({required this.state, required super.child});

  final _GlassToasterState state;

  @override
  bool updateShouldNotify(_ToasterScope oldWidget) => false;
}

class _ToastStack extends StatelessWidget {
  const _ToastStack({required this.entries});

  final List<GlassToastEntry> entries;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left + GlassToaster.margin,
        padding.top + GlassToaster.margin,
        padding.right + GlassToaster.margin,
        0,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: GlassToaster.maxWidth),
          child: MotionLayout(
            planner: ToastMotion.planner,
            layoutBuilder: (context, children) =>
                Column(mainAxisSize: MainAxisSize.min, children: children),
            children: [
              for (final entry in entries)
                _ToastView(key: ObjectKey(entry), entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({required this.entry, super.key});

  final GlassToastEntry entry;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  MotionClock? _clock;
  late final MotionValue<double> _drag;
  late final List<Interaction> _interactions = [
    FollowInteraction(_Hold(this), role: InteractionRole.observer),
    DragInteraction(
      axis: Axis.vertical,
      contends: true,
      global: true,
      onUpdate: _dragged,
      onEnd: _released,
      onCancel: (_) => _settle(),
    ),
  ];
  VoidCallback? _cancelTimer;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_clock != null) return;
    final clock = _clock = MotionClockScope.of(context);
    _drag = MotionValue<double>(0, clock: clock);
    _arm();
  }

  @override
  void dispose() {
    _cancelTimer?.call();
    super.dispose();
  }

  void _arm() {
    _cancelTimer?.call();
    _cancelTimer = null;
    final duration = widget.entry._duration;
    final clock = _clock;
    if (duration == null || clock == null || _hovered || _pressed) return;
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    _cancelTimer = clock.schedule(clock.now + seconds, (_) {
      _cancelTimer = null;
      if (!mounted) return;
      final entry = widget.entry;
      if (entry._hasAction && MediaQuery.accessibleNavigationOf(context)) {
        return;
      }
      entry.dismiss();
    });
  }

  void _hold({bool? hovered, bool? pressed}) {
    _hovered = hovered ?? _hovered;
    _pressed = pressed ?? _pressed;
    if (_hovered || _pressed) {
      _cancelTimer?.call();
      _cancelTimer = null;
    } else if (_cancelTimer == null) {
      _arm();
    }
  }

  void _dragged(DragInteractionDetails details) =>
      _drag.target = ToastMotion.drag.apply(details.translation.dy);

  void _released(DragInteractionDetails details) {
    if (details.translation.dy < -ToastMotion.dismissTravel ||
        details.velocity.dy < -ToastMotion.dismissVelocity) {
      widget.entry.dismiss();
      return;
    }
    _settle();
  }

  void _settle() => withSpring(ToastMotion.settle, () => _drag.target = 0);

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Semantics(
      container: true,
      liveRegion: true,
      onDismiss: entry.dismiss,
      child: Padding(
        padding: const EdgeInsets.only(bottom: GlassToaster.gap),
        child: MotionTransition(
          translateY: _drag,
          child: InputRegion(
            interactions: _interactions,
            child: _ToastScope(
              entry: entry,
              child: Builder(
                builder: (context) => entry._builder(context, entry),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _Hold extends PointerFollower {
  _Hold(this._view);

  final _ToastViewState _view;

  @override
  void down(PointerDownInput input) => _view._hold(pressed: true);

  @override
  void move(PointerMoveInput input) {}

  @override
  void up(PointerUpInput input) => _view._hold(pressed: false);

  @override
  void cancel(PointerCancelInput input) => _view._hold(pressed: false);

  @override
  void hover(PointerHoverInput input) => _view._hold(hovered: input.inside);
}

class _ToastScope extends InheritedWidget {
  const _ToastScope({required this.entry, required super.child});

  final GlassToastEntry entry;

  static GlassToastEntry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ToastScope>()?.entry;

  @override
  bool updateShouldNotify(_ToastScope oldWidget) => entry != oldWidget.entry;
}

/// The look of a toast: an [icon], a [title] with a [subtitle] under it,
/// and an [action] at its end, on a body of glass.
///
/// The body is a capsule while the toast holds one line and rounds its
/// corners by [radius] as its text wraps. The title is subheadline
/// semibold and the subtitle footnote in the secondary label; the icon
/// takes the label color, and an icon of its own color, such as a red
/// mark for a failure, keeps it. Give [action] a `GlassButton.plain`: a
/// glass button on glass reads as a second toast.
///
/// A toast with an [action] stays while a screen reader navigates.
class GlassToast extends StatelessWidget {
  /// Creates the look of a toast.
  const GlassToast({
    required this.title,
    this.icon,
    this.subtitle,
    this.action,
    super.key,
  });

  /// What the toast says, usually a [Text].
  final Widget title;

  /// What stands before the text, such as a symbol, or null for nothing.
  final Widget? icon;

  /// What the toast adds under its title, or null for nothing.
  final Widget? subtitle;

  /// The toast's action, such as an undo, or null for none.
  final Widget? action;

  /// The radius of the body's corners: half the height of a toast of one
  /// line.
  static const double radius = 22;

  @override
  Widget build(BuildContext context) {
    _ToastScope.maybeOf(context)?._hasAction = this.action != null;
    final label = GlassDynamicColor.resolve(
      GlassTheme.labelColorOf(context),
      context,
    );
    final secondary = GlassDynamicColor.resolve(
      GlassColors.secondaryLabel,
      context,
    );
    final icon = this.icon;
    final subtitle = this.subtitle;
    final action = this.action;
    return GlassSurface(
      shape: const LiquidRoundedSuperellipse(radius: radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 2 * radius),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            icon == null ? 20 : 14,
            action == null ? 12 : 4,
            action == null ? 20 : 4,
            action == null ? 12 : 4,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: label, size: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon, const SizedBox(width: 10)],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassDefaultTextStyle(
                        role: GlassTextRole.subheadline,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: label,
                            fontWeight: FontWeight.w600,
                          ),
                          child: title,
                        ),
                      ),
                      if (subtitle != null)
                        GlassDefaultTextStyle(
                          role: GlassTextRole.footnote,
                          child: DefaultTextStyle.merge(
                            style: TextStyle(color: secondary),
                            child: subtitle,
                          ),
                        ),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
