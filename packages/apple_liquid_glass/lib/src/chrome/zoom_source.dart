import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Connects a [GlassZoomSource] to the page that zooms out of it, as a
/// `LayerLink` connects a follower to its target.
///
/// UIKit: the `sourceViewProvider` of `.zoom`. SwiftUI:
/// `matchedTransitionSource(id:in:)`.
class GlassZoomLink {
  _GlassZoomSourceState? _source;

  /// Whether a source is attached and laid out.
  bool get isAttached {
    final box = _source?.context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize;
  }

  /// The source's rect in [ancestor]'s coordinates, or null without a
  /// laid out source.
  @internal
  Rect? rectIn(RenderBox ancestor) {
    final box = _source?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(ancestor),
      Offset.zero & box.size,
    );
  }

  /// The source's corner radius.
  @internal
  double get radius => _source?.widget.borderRadius ?? 0;

  /// What the zoom draws of the source while it crossfades into the page.
  @internal
  Widget? get look => _source?.widget.child;

  /// Hides the source while a page zooms out of it and back into it.
  @internal
  void hide() => _source?._hidden(true);

  /// Shows the source again.
  @internal
  void reveal() => _source?._hidden(false);
}

/// The widget a `GlassPageRoute` with a [link] grows out of when it is
/// pushed and lands in when it is popped.
///
/// The source hides while its page shows or moves, as UIKit hides a zoom
/// transition's source view.
class GlassZoomSource extends StatefulWidget {
  /// Marks [child] as the source of [link]'s page.
  const GlassZoomSource({
    required this.link,
    required this.child,
    this.borderRadius = 0,
    super.key,
  });

  /// The link the page is pushed with.
  final GlassZoomLink link;

  /// The radius of the source's corners, which the zoom's corners turn
  /// from into the display's.
  final double borderRadius;

  /// The source.
  final Widget child;

  @override
  State<GlassZoomSource> createState() => _GlassZoomSourceState();
}

class _GlassZoomSourceState extends State<GlassZoomSource> {
  bool _hide = false;

  @override
  void initState() {
    super.initState();
    widget.link._source = this;
  }

  @override
  void didUpdateWidget(GlassZoomSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link) {
      if (identical(oldWidget.link._source, this)) {
        oldWidget.link._source = null;
      }
      widget.link._source = this;
    }
  }

  @override
  void dispose() {
    if (identical(widget.link._source, this)) widget.link._source = null;
    super.dispose();
  }

  // A hide or reveal one frame late shows the source and its zoomed copy
  // together, or neither: it lands in this frame when it can.
  void _hidden(bool hide) {
    if (hide == _hide || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _hidden(hide));
      return;
    }
    setState(() => _hide = hide);
  }

  @override
  Widget build(BuildContext context) =>
      Visibility.maintain(visible: !_hide, child: widget.child);
}
