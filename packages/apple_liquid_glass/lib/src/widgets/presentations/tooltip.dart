import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// A hint that names [child] while a mouse rests on it.
///
/// UIKit: `UIToolTipInteraction`. SwiftUI: `help(_:)`. Flutter: `Tooltip`.
///
/// ```dart
/// GlassTooltip(
///   message: 'New letter',
///   child: GlassButton(
///     onPressed: compose,
///     child: const Icon(CupertinoIcons.square_pencil),
///   ),
/// )
/// ```
///
/// Once a mouse has rested on [child] for [waitDuration], the hint shows
/// [message] in footnote text, and [shortcut] after it, on a small glass
/// panel 6 points below [child] and centered on it, or above it where the
/// room below runs out, 8 points inside the screen's safe area at the least
/// (a window's buttons are not in it, `GlassWindowControls`). It follows
/// [child] while it shows and leaves at once when the mouse leaves [child]
/// or presses a button, a scroll that carries [child] away from the mouse
/// included; after a press it waits for the mouse to come back. It is not
/// modal: it dims nothing, takes no focus and no pointer, so every click
/// reaches what lies under it, and it hears the mouse over [child] without
/// joining the gesture arena, so [child] gets every touch it would get
/// without it. A touch shows nothing.
///
/// Screen readers read [message] as the tooltip of [child], which names a
/// glyph button that has no label of its own; the hint itself is not read.
///
/// The hint is laid out in the nearest `Overlay` from where [child] stands,
/// with no layer around [child] while it is closed or open, so glass beside
/// [child] keeps reading what lies under it the way it would without the
/// tooltip.
///
/// Fidelity. Not measured on iOS: the wait, the place, the type and the
/// panel are stand-ins, and the hint shows and leaves without a fade.
class GlassTooltip extends StatefulWidget {
  /// Names [child] with [message].
  const GlassTooltip({
    required this.message,
    required this.child,
    this.shortcut,
    this.enabled = true,
    super.key,
  });

  /// What the hint says, and what screen readers read as the tooltip of
  /// [child].
  final String message;

  /// What follows [message] in the hint, such as the keys of the command,
  /// in the secondary label color; null for none.
  final Widget? shortcut;

  /// What the hint names.
  final Widget child;

  /// Whether a resting mouse shows the hint; screen readers read [message]
  /// either way.
  final bool enabled;

  /// How long a mouse rests on the child before the hint shows.
  static const Duration waitDuration = Duration(milliseconds: 500);

  /// The space between the child and the hint.
  static const double gap = 6;

  /// The least space between the hint and the edges of the safe area.
  static const double margin = 8;

  @override
  State<GlassTooltip> createState() => _GlassTooltipState();
}

class _GlassTooltipState extends State<GlassTooltip> {
  final _portal = OverlayPortalController();
  late final _follow = FollowInteraction(
    _HoverFollower(this),
    role: InteractionRole.observer,
  );
  VoidCallback? _cancelWait;
  bool _pressed = false;

  @override
  void didUpdateWidget(GlassTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hide();
  }

  @override
  void dispose() {
    _cancelWait?.call();
    super.dispose();
  }

  void _hover({required bool inside}) {
    if (!inside) {
      _pressed = false;
      _hide();
      return;
    }
    if (!widget.enabled || _pressed) return;
    if (_portal.isShowing || _cancelWait != null) return;
    final clock = MotionClockScope.of(context);
    final wait =
        GlassTooltip.waitDuration.inMicroseconds /
        Duration.microsecondsPerSecond;
    _cancelWait = clock.schedule(clock.now + wait, (_) {
      _cancelWait = null;
      if (mounted && widget.enabled) _portal.show();
    });
  }

  void _down() {
    _pressed = true;
    _hide();
  }

  void _hide() {
    _cancelWait?.call();
    _cancelWait = null;
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    tooltip: widget.message,
    child: OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _tip,
      child: InputRegion(interactions: [_follow], child: widget.child),
    ),
  );

  Widget _tip(BuildContext context, OverlayChildLayoutInfo info) {
    final anchor = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final shortcut = widget.shortcut;
    final secondary = GlassDynamicColor.resolve(
      GlassColors.secondaryLabel,
      context,
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ExcludeFocus(
          child: CustomSingleChildLayout(
            delegate: _TipLayout(
              anchor: anchor,
              padding: GlassMediaQueryData.overlayPaddingOf(
                context,
                anchorPoint: anchor.center,
              ),
            ),
            child: GlassSurface(
              shape: const LiquidRoundedSuperellipse(radius: _radius),
              child: Padding(
                padding: _padding,
                child: GlassDefaultTextStyle(
                  role: GlassTextRole.footnote,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: GlassDynamicColor.resolve(
                        GlassTheme.labelColorOf(context),
                        context,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(widget.message)),
                        if (shortcut != null) ...[
                          const SizedBox(width: _shortcutGap),
                          DefaultTextStyle.merge(
                            style: TextStyle(color: secondary),
                            child: shortcut,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _radius = 10;
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  );
  static const double _shortcutGap = 12;
  static const double _maxWidth = 320;
}

/// Hears the mouse come over a tooltip's child and leave it, and the
/// presses on it.
final class _HoverFollower extends PointerFollower {
  _HoverFollower(this.state);

  final _GlassTooltipState state;

  @override
  void down(PointerDownInput input) => state._down();

  @override
  void move(PointerMoveInput input) {}

  @override
  void up(PointerUpInput input) {}

  @override
  void cancel(PointerCancelInput input) {}

  @override
  void hover(PointerHoverInput input) => state._hover(inside: input.inside);
}

/// Places a tooltip's hint under [anchor], or over it where the room under
/// it runs out, inside the overlay less [padding] and the margin.
class _TipLayout extends SingleChildLayoutDelegate {
  _TipLayout({required this.anchor, required this.padding});

  final Rect anchor;
  final EdgeInsets padding;

  Rect _room(Size size) => padding
      .add(const EdgeInsets.all(GlassTooltip.margin))
      .resolve(TextDirection.ltr)
      .deflateRect(Offset.zero & size);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = _room(constraints.biggest);
    return BoxConstraints.loose(
      Size(
        math.max(0, math.min(room.width, _GlassTooltipState._maxWidth)),
        math.max(0, room.height),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = _room(size);
    final below = anchor.bottom + GlassTooltip.gap;
    final above = anchor.top - GlassTooltip.gap - childSize.height;
    final top = below + childSize.height <= room.bottom || above < room.top
        ? below
        : above;
    return Offset(
      math.max(
        room.left,
        math.min(
          anchor.center.dx - childSize.width / 2,
          room.right - childSize.width,
        ),
      ),
      math.max(room.top, math.min(top, room.bottom - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_TipLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}
