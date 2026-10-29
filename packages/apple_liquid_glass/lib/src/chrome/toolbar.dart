import 'dart:math' as math;

import 'package:apple_liquid_glass/src/chrome/chrome.dart';
import 'package:apple_liquid_glass/src/controls/button.dart';
import 'package:apple_liquid_glass/src/controls/search_field.dart';
import 'package:apple_liquid_glass/src/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/motion/search_motion.dart';
import 'package:apple_liquid_glass/src/surface/group.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

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
///
/// A [GlassSearchField] among [children] makes it iOS 27's bottom search
/// bar (`UISearchController` in the toolbar): the field fills the room
/// between the items before and after it, 12 points from each, every item
/// 48 points tall. Focusing the field starts the search as the keyboard
/// starts to rise: on one spring (0.25 s, bounce 0.1) the field widens to
/// 8 points from the sides and rises to 10 points above the keyboard, the
/// other items swell to 1.2 and fade where they stand, and a close button
/// travels in with the field from its resting place, growing from 1.2 and
/// sharpening from a blur. The close button ends the search 0.067 s later:
/// the text clears, the keyboard leaves, the field and the close button
/// return from where they were, without following the keyboard down, and
/// the items come back from the focused layout. Tapping elsewhere leaves
/// the search active, as in UIKit (read from UIKit, notes private; search
/// passport, simulator and iPhone 16 Pro recordings). UIKit aims the field
/// at the keyboard's final top; Flutter reports the keyboard as it rises,
/// so the field follows it there. Without a keyboard the search starts
/// 0.3 s after the focus, a guard of the port: UIKit has no such wait.
class GlassToolbar extends StatelessWidget implements ChromeBarWidget {
  /// Creates a toolbar of [children].
  const GlassToolbar({
    required this.children,
    this.closeSemanticLabel,
    super.key,
  });

  /// The items, leading to trailing.
  final List<Widget> children;

  /// What accessibility reads for the search's close button; `Close` when
  /// null.
  final String? closeSemanticLabel;

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
    final search = children.indexWhere((child) => child is GlassSearchField);
    if (search >= 0) {
      return _SearchBar(
        leading: [
          for (final child in children.take(search))
            if (child is! Spacer) child,
        ],
        field: children[search],
        trailing: [
          for (final child in children.skip(search + 1))
            if (child is! Spacer) child,
        ],
        closeSemanticLabel: closeSemanticLabel ?? 'Close',
      );
    }
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

/// The focus transition of a bottom search bar, stepped on the motion clock
/// and published as its progress.
final class _SearchBody implements MotionDriver {
  final motion = SearchMotion();
  final progress = ValueNotifier<double>(0);

  /// When the field took the focus while no keyboard had risen yet.
  double? keyboardWait;

  double get _now => MotionClock.instance.now;

  @override
  bool get isActive =>
      keyboardWait != null ||
      !motion.isSettled ||
      progress.value != motion.progress;

  @override
  double? get wakeTime {
    final wait = keyboardWait;
    if (wait != null) return wait + SearchTuning.keyboardWaitLimit;
    return null;
  }

  @override
  void step(double time) {
    final wait = keyboardWait;
    if (wait != null && time - wait >= SearchTuning.keyboardWaitLimit) {
      keyboardWait = null;
      motion.focus(time, delay: 0);
    }
    motion.advance(time);
    motion.land(time);
    progress.value = motion.progress;
  }

  void input(void Function(double t) action) {
    final t = _now;
    motion.advance(t);
    action(t);
    MotionClock.instance.wake(this);
  }

  void dispose() => progress.dispose();
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
  final _body = _SearchBody();
  final _ends = _Ends();
  late final _swell = _Derived(
    _body.progress,
    (p) => 1 + (SearchTuning.appearScale - 1) * p,
  );
  late final _fade = _Derived(_body.progress, (p) => 1 - p);
  late final _arrive = _Derived(_body.progress, (p) => p);
  late final _arriveScale = _Derived(
    _body.progress,
    (p) => SearchTuning.appearScale + (1 - SearchTuning.appearScale) * p,
  );
  late final _arriveBlur = _Derived(
    _body.progress,
    (p) => SearchTuning.appearBlur * (1 - p),
  );
  bool _focused = false;

  // A search ended: the keyboard inset the bar keeps its layout at while
  // the field returns, so nothing follows the keyboard down.
  double? _frozen;

  @override
  void initState() {
    super.initState();
    _body.progress.addListener(_returned);
    MotionClock.instance.addDriver(_body);
  }

  void _returned() {
    if (_frozen == null || _focused || _body.progress.value != 0) return;
    setState(() => _frozen = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _body.motion.reducedMotion = GlassTraits.of(context).reduceMotion;
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (_body.keyboardWait != null && keyboard > 0) {
      _body.keyboardWait = null;
      _body.input(
        (t) => _body.motion.focus(t, delay: SearchTuning.keyboardLag),
      );
    }
  }

  @override
  void dispose() {
    _body.progress.removeListener(_returned);
    MotionClock.instance.removeDriver(_body);
    _body.dispose();
    _ends.dispose();
    for (final value in [_swell, _fade, _arrive, _arriveScale, _arriveBlur]) {
      value.dispose();
    }
    super.dispose();
  }

  void _focusChanged(bool focused) {
    if (!focused || _body.motion.isFocused || _body.keyboardWait != null) {
      return;
    }
    setState(() {
      _focused = true;
      _frozen = null;
    });
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (keyboard > 0) {
      _body.input(_body.motion.focus);
    } else {
      _body.keyboardWait = MotionClock.instance.now;
      MotionClock.instance.wake(_body);
    }
  }

  void _end() {
    _body.keyboardWait = null;
    _body.input(_body.motion.unfocus);
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
    final glyph = GlassDynamicColor.resolve(GlassColors.label, context);
    Widget item(_Slot slot, Widget child) => LayoutId(
      id: slot,
      child: MotionTransition(scale: _swell, opacity: _fade, child: child),
    );
    return SizedBox(
      height: math.max(
        SearchTuning.height + SearchTuning.restInset,
        keyboard + SearchTuning.keyboardGap + SearchTuning.height,
      ),
      child: SearchEnds(
        ends: _ends,
        child: CustomMultiChildLayout(
          delegate: _SearchLayout(
            progress: _body.progress,
            leading: widget.leading.length,
            trailing: widget.trailing.length,
            keyboard: keyboard,
            returning: _frozen != null,
            rtl: rtl,
          ),
          children: [
            for (var i = 0; i < widget.leading.length; i++)
              item(_Slot.leading(i), widget.leading[i]),
            LayoutId(
              id: const _Slot.field(),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: _focusChanged,
                child: widget.field,
              ),
            ),
            for (var i = 0; i < widget.trailing.length; i++)
              item(_Slot.trailing(i), widget.trailing[i]),
            LayoutId(
              id: const _Slot.close(),
              child: IgnorePointer(
                ignoring: !_focused,
                child: MotionTransition(
                  opacity: _arrive,
                  scale: _arriveScale,
                  blur: _arriveBlur,
                  child: GlassButton(
                    onPressed: _end,
                    child: Semantics(
                      label: widget.closeSemanticLabel,
                      child: SizedBox.fromSize(
                        size: SearchTuning.closeGlyphSize,
                        child: CustomPaint(painter: SearchCrossPainter(glyph)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [ValueListenable] of a function of another one, recomputed when it
/// changes.
class _Derived<T, S> extends ChangeNotifier implements ValueListenable<T> {
  /// Follows [source] through [compute].
  _Derived(this.source, this.compute) : _value = compute(source.value) {
    source.addListener(_changed);
  }

  /// The value followed.
  final ValueListenable<S> source;

  /// What this value is of [source]'s.
  final T Function(S value) compute;

  T _value;

  @override
  T get value => _value;

  void _changed() {
    final next = compute(source.value);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    source.removeListener(_changed);
    super.dispose();
  }
}

@immutable
final class _Slot {
  const _Slot.leading(this.index) : kind = 0;
  const _Slot.trailing(this.index) : kind = 1;
  const _Slot.field() : kind = 2, index = 0;
  const _Slot.close() : kind = 3, index = 0;

  final int kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is _Slot && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

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
    List<double> measure(int count, _Slot Function(int) slot) => [
      for (var i = 0; i < count; i++)
        if (hasChild(slot(i))) layoutChild(slot(i), item).width else h,
    ];
    final leadWidths = measure(leading, _Slot.leading);
    final trailWidths = measure(trailing, _Slot.trailing);
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
        _Slot.leading(i),
        slotOf(rest.leading[i], bare.leading[i]).topLeft,
      );
    }
    for (var i = 0; i < trailing; i++) {
      positionChild(
        _Slot.trailing(i),
        slotOf(rest.trailing[i], bare.trailing[i]).topLeft,
      );
    }
    final field = lerpRect(rest.field, focused.field, p);
    layoutChild(const _Slot.field(), BoxConstraints.tight(field.size));
    positionChild(const _Slot.field(), field.topLeft);
    final close = returning
        ? focused.close
        : lerpRect(rest.close, focused.close, p);
    layoutChild(const _Slot.close(), BoxConstraints.tight(close.size));
    positionChild(const _Slot.close(), close.topLeft);
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

class _Ends extends ChangeNotifier {
  void end() => notifyListeners();
}
