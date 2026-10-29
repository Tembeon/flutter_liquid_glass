import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/surface/group.dart';
import 'package:flutter/widgets.dart';

/// An iOS 27 toolbar: glass items floating over the bottom of the screen.
///
/// UIKit: `UIToolbar`. SwiftUI: `toolbar` with `ToolbarItem(placement:
/// .bottomBar)`. Flutter: a bottom bar of `CupertinoButton`s.
///
/// The [children] stand in a row 48 points tall, usually glass buttons
/// with a [Spacer] where UIKit puts its flexible space; glass items that
/// come within 12 points of each other fuse on liquid glass. The row sits
/// 28 points from the sides and the bottom of the screen
/// (`_UIToolbarPaddingSpec` phoneSides and phoneBottom), or 8 points above
/// a keyboard (phoneKeyboard), read from UIKit's tuning on iOS 27 and the
/// capsule frames on an iPhone 16 Pro. Put it in a [GlassPageScaffold]'s
/// toolbar: it reaches from the screen's bottom edge.
class GlassToolbar extends StatelessWidget implements ChromeBarWidget {
  /// Creates a toolbar of [children].
  const GlassToolbar({required this.children, super.key});

  /// The items, leading to trailing.
  final List<Widget> children;

  /// The height of the toolbar's items.
  static const double height = 48;

  /// The space between the screen's sides and the outer items.
  static const double sideInset = 28;

  /// The space between the screen's bottom and the items.
  static const double bottomInset = 28;

  /// The space between a keyboard and the items.
  static const double keyboardInset = 8;

  /// How close glass items come before they fuse.
  static const double fusion = 12;

  @override
  Size get preferredSize => const Size.fromHeight(height + bottomInset);

  @override
  ChromeBar get chromeBar => ChromeBar.floating;

  @override
  double get scrolledUnderAfter => 0;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          sideInset,
          0,
          sideInset,
          keyboard > 0 ? keyboard + keyboardInset : bottomInset,
        ),
        child: SizedBox(
          height: height,
          child: GlassGroup(
            merge: const GlassMerge.spacing(fusion),
            child: Row(children: children),
          ),
        ),
      ),
    );
  }
}
