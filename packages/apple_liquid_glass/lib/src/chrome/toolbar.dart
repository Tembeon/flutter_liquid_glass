import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/bar.dart';
import 'package:apple_liquid_glass/src/chrome/bar_entry.dart';
import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/controls/glass_button.dart';
import 'package:apple_liquid_glass/src/controls/glass_search_field.dart';
import 'package:apple_liquid_glass/src/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/controls/search_stacking.dart';
import 'package:apple_liquid_glass/src/motion/search_motion.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// The look of toolbars, set on the theme.
@immutable
class GlassToolbarStyle {
  /// Creates a style.
  const GlassToolbarStyle({this.itemStyle});

  /// The look of the toolbar's items and of its search's close button.
  final GlassBarItemStyle? itemStyle;

  /// This style over [other].
  GlassToolbarStyle merge(GlassToolbarStyle? other) {
    if (other == null) return this;
    return GlassToolbarStyle(
      itemStyle: itemStyle?.merge(other.itemStyle) ?? other.itemStyle,
    );
  }

  /// The style between [a] and [b] at [t].
  static GlassToolbarStyle? lerp(
    GlassToolbarStyle? a,
    GlassToolbarStyle? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return GlassToolbarStyle(
      itemStyle: GlassBarItemStyle.lerp(a.itemStyle, b.itemStyle, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassToolbarStyle && other.itemStyle == itemStyle;

  @override
  int get hashCode => itemStyle.hashCode;
}

/// An iOS 27 toolbar: glass capsules floating over the bottom of the
/// screen.
///
/// UIKit: `UIToolbar` with `toolbarItems`. SwiftUI: `toolbar` with
/// `ToolbarItem(placement: .bottomBar)`. Flutter: a bottom bar of
/// `CupertinoButton`s.
///
/// The [items] stand in capsules 48 points tall, adjacent items sharing
/// one, a [GlassBarSpacer.flexible] where UIKit puts its flexible space;
/// capsules that come within 12 points fuse on liquid glass. They sit 28
/// points from the sides and the bottom of the screen
/// (`_UIToolbarPaddingSpec` phoneSides and phoneBottom), or 8 points above a
/// keyboard (phoneKeyboard), read from UIKit's tuning on iOS 27 and the
/// capsule frames on an iPhone 16 Pro. Put it in a [GlassPageScaffold]'s
/// toolbar. The glass pages of a navigator share one toolbar, as UIKit's
/// navigation controller does: when a page's items change, or another
/// page comes, its capsules change as `setToolbarItems(_:animated:)` changes
/// them (device recordings, replayed).
///
/// A [GlassBarItem.custom] holding a [GlassSearchField] makes it iOS 27's
/// bottom search bar (`UISearchController` in the toolbar), drawn with its
/// page: the field fills the room between the items before and after it,
/// 12 points from each, every item 48 points tall. Focusing the field
/// starts the search as the keyboard starts to rise: on one spring (0.25
/// s, bounce 0.1) the field widens to 8 points from the sides and rises to
/// 10 points above the keyboard, the other items swell to 1.2 and fade
/// where they stand, and a close button travels in with the field from its
/// resting place, growing from 1.2 and sharpening from a blur. The close
/// button ends the search 0.067 s later: the text clears, the keyboard
/// leaves, the field and the close button return from where they were,
/// without following the keyboard down, and the items come back from the
/// focused layout. Tapping elsewhere leaves the search active, as in UIKit
/// (read from UIKit, notes private; search passport, simulator and iPhone
/// 16 Pro recordings). UIKit aims the field at the keyboard's final top;
/// Flutter reports the keyboard as it rises, so the field follows it
/// there. Without a keyboard the search starts 0.3 s after the focus, a
/// guard of the port: UIKit has no such wait.
class GlassToolbar extends StatefulWidget implements PreferredSizeWidget {
  /// Creates a toolbar of [items].
  const GlassToolbar({
    required this.items,
    this.closeSemanticLabel,
    super.key,
  });

  /// The capsules' items, leading to trailing.
  final List<GlassBarEntry> items;

  /// What accessibility reads for the search's close button; `Close` when
  /// null.
  final String? closeSemanticLabel;

  /// The height of the toolbar's items.
  static const double height = 48;

  /// The space between the screen's sides and the outer items (bars
  /// passport).
  static const double sideInset = 28;

  /// The space between the screen's bottom and the items (read from UIKit).
  static const double bottomInset = 28;

  /// The space between a keyboard and the items (read from UIKit).
  static const double keyboardInset = 8;

  /// How close glass items come before they fuse: the spacing of the glass
  /// container a bar's capsules share (bars passport: 12, constant through
  /// item changes).
  static const double fusion = 12;

  @override
  Size get preferredSize => const Size.fromHeight(height + bottomInset);

  @override
  State<GlassToolbar> createState() => _GlassToolbarState();
}

class _GlassToolbarState extends State<GlassToolbar> {
  GlassPageBarLink? _link;
  GlassBarHost? _standalone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _link = GlassPageBarLink.maybeOf(context);
    if (_link == null) {
      _standalone ??= GlassBarHost.standalone();
    } else if (_standalone case final host?) {
      host.detach(host.standaloneLink);
      _standalone = null;
    }
  }

  @override
  void dispose() {
    if (_standalone case final host?) host.detach(host.standaloneLink);
    _withdrawLater();
    super.dispose();
  }

  void _withdrawLater() {
    if (_link case final link?) link.host.withdraw(link, this);
  }

  static Widget _button(GlassBarItem item) =>
      item.child ??
      GlassButton(onPressed: item.onPressed, child: item.icon ?? item.label!);

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final link = _link ?? _standalone!.standaloneLink;
    final search = items.indexWhere(
      (entry) => entry is GlassBarItem && entry.child is GlassSearchField,
    );
    final shown = GlassTabShown.of(context);
    if (!shown) _withdrawLater();
    if (search >= 0) {
      if (shown) link.host.declareToolbar(link, null, by: this);
      return _SearchBar(
        leading: [
          for (final entry in items.take(search))
            if (entry is GlassBarItem) _button(entry),
        ],
        field: (items[search] as GlassBarItem).child!,
        trailing: [
          for (final entry in items.skip(search + 1))
            if (entry is GlassBarItem) _button(entry),
        ],
        closeSemanticLabel: widget.closeSemanticLabel ?? 'Close',
      );
    }
    if (shown) link.host.declareToolbar(link, items, by: this);
    final standalone = _standalone;
    if (standalone == null) {
      return SizedBox(height: widget.preferredSize.height);
    }
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    return Padding(
      padding: EdgeInsets.only(
        bottom: keyboard > 0
            ? keyboard + GlassToolbar.keyboardInset
            : GlassToolbar.bottomInset,
      ),
      child: SizedBox(
        height: GlassToolbar.height,
        child: GlassBarView(host: standalone, only: GlassBarKind.toolbar),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.leading,
    required this.field,
    required this.trailing,
    required this.closeSemanticLabel,
  });

  final List<Widget> leading;
  final Widget field;
  final List<Widget> trailing;
  final String closeSemanticLabel;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _motion = SearchMotion();
  final _ends = SearchEndSignal();
  late final _progress = _motion.select((m) => m.progress);
  late final _swell = _motion.select(
    (m) => 1 + (SearchTuning.appearScale - 1) * m.progress,
  );
  late final _fade = _motion.select((m) => 1 - m.progress);
  late final _arriveScale = _motion.select(
    (m) =>
        SearchTuning.appearScale + (1 - SearchTuning.appearScale) * m.progress,
  );
  late final _arriveBlur = _motion.select(
    (m) => SearchTuning.appearBlur * (1 - m.progress),
  );
  bool _focused = false;

  // A search ended: the keyboard inset the bar keeps its layout at while
  // the field returns, so nothing follows the keyboard down.
  double? _frozen;

  double get _now => MotionClock.instance.now;

  @override
  void initState() {
    super.initState();
    _progress.addListener(_returned);
  }

  void _returned() {
    if (_frozen == null || _focused || _progress.value != 0) return;
    setState(() => _frozen = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (keyboard > 0) {
      _motion.keyboardRose(_now, lag: SearchTuning.keyboardLag);
    }
  }

  @override
  void dispose() {
    _progress.removeListener(_returned);
    _ends.dispose();
    super.dispose();
  }

  void _focusChanged(bool focused) {
    if (!focused || _motion.isFocused) return;
    setState(() {
      _focused = true;
      _frozen = null;
    });
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (keyboard > 0) {
      _motion.focus(_now);
    } else {
      _motion.focusAfterKeyboard(_now);
    }
  }

  void _end() {
    _motion.unfocus(_now);
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    setState(() {
      _focused = false;
      _frozen = keyboard;
    });
    _ends.end();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = _frozen ?? media.viewInsets.bottom;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final theme = GlassTheme.of(context);
    final glyph = GlassDynamicColor.resolve(
      theme.toolbarStyle?.itemStyle?.foregroundColor?.resolve(const {}) ??
          theme.colorScheme?.label ??
          GlassColors.label,
      context,
    );
    Widget item(_Slot slot, Widget child) => LayoutId(
      id: slot,
      child: MotionTransition(scale: _swell, opacity: _fade, child: child),
    );
    return MotionScope(
      motion: _motion,
      child: SizedBox(
        height: math.max(
          SearchTuning.height + SearchTuning.restInset,
          keyboard + SearchTuning.keyboardGap + SearchTuning.height,
        ),
        child: SearchEnds(
          ends: _ends,
          child: CustomMultiChildLayout(
            delegate: _SearchLayout(
              progress: _progress,
              leading: widget.leading.length,
              trailing: widget.trailing.length,
              keyboard: keyboard,
              returning: _frozen != null,
              rtl: rtl,
            ),
            children: [
              for (var i = 0; i < widget.leading.length; i++)
                item((_SlotKind.leading, i), widget.leading[i]),
              LayoutId(
                id: (_SlotKind.field, 0),
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: _focusChanged,
                  child: widget.field,
                ),
              ),
              for (var i = 0; i < widget.trailing.length; i++)
                item((_SlotKind.trailing, i), widget.trailing[i]),
              LayoutId(
                id: (_SlotKind.close, 0),
                child: IgnorePointer(
                  ignoring: !_focused,
                  child: MotionTransition(
                    opacity: _progress,
                    scale: _arriveScale,
                    blur: _arriveBlur,
                    child: GlassButton(
                      onPressed: _end,
                      child: Semantics(
                        label: widget.closeSemanticLabel,
                        child: SizedBox.fromSize(
                          size: SearchTuning.closeGlyphSize,
                          child: CustomPaint(
                            painter: SearchCrossPainter(glyph),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SlotKind { leading, trailing, field, close }

typedef _Slot = (_SlotKind, int);

/// Places a bottom search bar's items, field and close button where the
/// transition's progress has them: the field between its resting and its
/// focused capsule; the close button with it on the way in and where it
/// stood on the way back; the items where they rest on the way in and
/// coming back from the focused layout without a keyboard.
class _SearchLayout extends MultiChildLayoutDelegate {
  _SearchLayout({
    required this.progress,
    required this.leading,
    required this.trailing,
    required this.keyboard,
    required this.returning,
    required this.rtl,
  }) : super(relayout: progress);

  final ValueListenable<double> progress;
  final int leading;
  final int trailing;
  final double keyboard;
  final bool returning;
  final bool rtl;

  @override
  void performLayout(Size size) {
    const h = SearchTuning.height;
    final item = BoxConstraints(
      minWidth: h,
      minHeight: h,
      maxHeight: h,
      maxWidth: size.width,
    );
    List<double> measure(int count, _SlotKind kind) => [
      for (var i = 0; i < count; i++) layoutChild((kind, i), item).width,
    ];
    final leadWidths = measure(leading, _SlotKind.leading);
    final trailWidths = measure(trailing, _SlotKind.trailing);
    final rest = searchBarLayout(
      width: size.width,
      bottom: size.height - SearchTuning.restInset,
      focused: false,
      leading: leadWidths,
      trailing: trailWidths,
      rtl: rtl,
    );
    SearchBarGeometry focusedAbove(double keyboard) => searchBarLayout(
      width: size.width,
      bottom: size.height - keyboard - SearchTuning.keyboardGap,
      focused: true,
      leading: leadWidths,
      trailing: trailWidths,
      rtl: rtl,
    );
    final focused = focusedAbove(keyboard);
    final bare = focusedAbove(0);
    final p = progress.value;
    Rect slotOf(Rect resting, Rect away) =>
        returning ? lerpRect(resting, away, p) : resting;
    for (var i = 0; i < leading; i++) {
      positionChild(
        (_SlotKind.leading, i),
        slotOf(rest.leading[i], bare.leading[i]).topLeft,
      );
    }
    for (var i = 0; i < trailing; i++) {
      positionChild(
        (_SlotKind.trailing, i),
        slotOf(rest.trailing[i], bare.trailing[i]).topLeft,
      );
    }
    final field = lerpRect(rest.field, focused.field, p);
    layoutChild((_SlotKind.field, 0), BoxConstraints.tight(field.size));
    positionChild((_SlotKind.field, 0), field.topLeft);
    final close = returning
        ? focused.close
        : lerpRect(rest.close, focused.close, p);
    layoutChild((_SlotKind.close, 0), BoxConstraints.tight(close.size));
    positionChild((_SlotKind.close, 0), close.topLeft);
  }

  @override
  bool shouldRelayout(_SearchLayout oldDelegate) =>
      leading != oldDelegate.leading ||
      trailing != oldDelegate.trailing ||
      keyboard != oldDelegate.keyboard ||
      returning != oldDelegate.returning ||
      rtl != oldDelegate.rtl ||
      progress != oldDelegate.progress;
}
