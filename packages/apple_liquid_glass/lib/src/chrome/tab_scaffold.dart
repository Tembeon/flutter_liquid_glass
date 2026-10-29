import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/controls/tab_bar.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// An iOS 27 tab interface: a tab bar floating over the bottom of the
/// screen and the selected tab's page under it.
///
/// UIKit: `UITabBarController`. SwiftUI: `TabView`. Flutter:
/// `CupertinoTabScaffold`.
///
/// [tabBuilder] builds a tab the first time it is selected; a tab left
/// keeps its state, offstage, with its tickers muted and its focus kept
/// apart. The bar stands 21 points from the screen's sides and bottom (tab
/// bar passport), and the media query padding of the tabs grows to clear
/// it, so a page's content scrolls clear of the bar and a
/// [GlassPageScaffold] in a tab sees the floating bar at its bottom edge.
class GlassTabScaffold extends StatefulWidget {
  /// Creates a tab interface.
  const GlassTabScaffold({
    required this.tabBar,
    required this.tabBuilder,
    this.backgroundColor,
    super.key,
  });

  /// The tab bar; its selected index picks the tab shown.
  final GlassTabBar tabBar;

  /// Builds the tab at an index.
  final IndexedWidgetBuilder tabBuilder;

  /// The background behind the tabs; [GlassColors.systemBackground] by
  /// default.
  final Color? backgroundColor;

  /// The space between the screen's sides and bottom and the bar (tab bar
  /// passport, 402 point screen).
  static const double inset = 21;

  @override
  State<GlassTabScaffold> createState() => _GlassTabScaffoldState();
}

class _GlassTabScaffoldState extends State<GlassTabScaffold> {
  final _active = ValueNotifier<MotionScrollObserver?>(null);
  final _built = <int>{};
  final _focus = <FocusScopeNode>[];

  @override
  void dispose() {
    _active.dispose();
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  FocusScopeNode _focusOf(int index) {
    while (_focus.length <= index) {
      _focus.add(FocusScopeNode(debugLabel: 'GlassTabScaffold tab'));
    }
    return _focus[index];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final count = widget.tabBar.destinations.length;
    final selected = count == 0
        ? -1
        : widget.tabBar.selectedIndex.clamp(0, count - 1);
    if (selected >= 0) _built.add(selected);
    _built.removeWhere((index) => index >= count);
    final bottom = math.max(
      media.padding.bottom,
      GlassTabScaffold.inset +
          GlassTabBar.groupHeight(
            accessory: widget.tabBar.bottomAccessory != null,
          ),
    );
    final background = GlassDynamicColor.resolve(
      widget.backgroundColor ?? GlassColors.systemBackground,
      context,
    );
    return GlassChrome(
      edges: ChromeEdges(
        top: ChromeBar.none,
        topExtent: media.padding.top,
        scrolledUnderAfter: 0,
        bottom: ChromeBar.floating,
        bottomExtent: bottom,
        background: background,
      ),
      active: _active,
      outer: GlassChrome.maybeOf(context),
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: bottom),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (var i = 0; i < count; i++)
                    if (_built.contains(i))
                      Offstage(
                        key: ValueKey(i),
                        offstage: i != selected,
                        child: TickerMode(
                          enabled: i == selected,
                          child: FocusScope(
                            node: _focusOf(i),
                            child: Builder(
                              builder: (context) =>
                                  widget.tabBuilder(context, i),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            Positioned(
              left: GlassTabScaffold.inset,
              right: GlassTabScaffold.inset,
              bottom: GlassTabScaffold.inset,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1,
                child: widget.tabBar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
