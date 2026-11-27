import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/page_control.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/page_scroll_physics.dart';
import 'package:flutter/widgets.dart';

/// When a [GlassPageView] shows its page control.
///
/// SwiftUI: `PageTabViewStyle.IndexDisplayMode`.
enum GlassPageIndexDisplay {
  /// Only with more than one page.
  automatic,

  /// Always, one page or none included.
  always,

  /// Never.
  never,
}

/// Pages that turn under a finger, with a page control over their bottom
/// edge that follows them and turns them.
///
/// UIKit: a `UIPageViewController` with a `UIPageControl`. SwiftUI: a
/// `TabView` with `.tabViewStyle(.page)`. Flutter: a `PageView`.
///
/// The pages turn on [GlassPageScrollPhysics]. A [GlassPageControl] stands
/// centered across the bottom edge, 25.67 points tall, as SwiftUI's page
/// style lays it out (page control API passport: 402 wide at the foot of a
/// full-screen `TabView`); its current page changes as a turning page
/// passes halfway, and a tap or a scrub on it turns the pages there.
/// [indexDisplay] says when it shows, and [backgroundStyle] when its
/// platter does: SwiftUI's `.always` background display mode is
/// [GlassPageControlBackground.prominent].
///
/// Fidelity. The control's place is the passport's; the turn a tap on the
/// control starts runs 0.35 s on an ease-out curve, not measured.
class GlassPageView extends StatefulWidget {
  /// Creates pages of [children].
  const GlassPageView({
    required this.children,
    this.controller,
    this.onPageChanged,
    this.indexDisplay = GlassPageIndexDisplay.automatic,
    this.backgroundStyle = GlassPageControlBackground.automatic,
    this.semanticLabel,
    super.key,
  });

  /// The pages.
  final List<Widget> children;

  /// Which page shows and turns them from code, or null for the view's
  /// own.
  final PageController? controller;

  /// Called with the page that shows as a turning page passes halfway.
  final ValueChanged<int>? onPageChanged;

  /// When the page control shows.
  final GlassPageIndexDisplay indexDisplay;

  /// When the page control's platter shows.
  final GlassPageControlBackground backgroundStyle;

  /// What screen readers read for the page control.
  final String? semanticLabel;

  @override
  State<GlassPageView> createState() => _GlassPageViewState();
}

class _GlassPageViewState extends State<GlassPageView> {
  PageController? _own;
  late int _page = _controller.initialPage;

  PageController get _controller =>
      widget.controller ?? (_own ??= PageController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _shown(int page) {
    setState(() => _page = page);
    widget.onPageChanged?.call(page);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.children.length;
    final shows = switch (widget.indexDisplay) {
      GlassPageIndexDisplay.never => false,
      GlassPageIndexDisplay.always => true,
      GlassPageIndexDisplay.automatic => count > 1,
    };
    final pages = PageView(
      controller: _controller,
      pageSnapping: false,
      physics: const GlassPageScrollPhysics(),
      onPageChanged: _shown,
      children: widget.children,
    );
    if (!shows) return pages;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        pages,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Center(
            child: GlassPageControl(
              count: count,
              page: _page.clamp(0, count == 0 ? 0 : count - 1),
              backgroundStyle: widget.backgroundStyle,
              semanticLabel: widget.semanticLabel,
              onChanged: (page) => _controller.animateToPage(
                page,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
