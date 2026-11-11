import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/presentations.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/foundation/typography.dart';
import 'package:apple_liquid_glass/src/motions/bar_layout.dart';
import 'package:apple_liquid_glass/src/motions/bar_motion.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart'
    show MenuCapsuleSource, MenuSource;
import 'package:apple_liquid_glass/src/motions/navigation_motion.dart';
import 'package:apple_liquid_glass/src/navigation/bar_entry.dart';
import 'package:apple_liquid_glass/src/navigation/navigation_bar.dart';
import 'package:apple_liquid_glass/src/navigation/toolbar.dart';
import 'package:apple_liquid_glass/src/surfaces/highlight.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

/// What a page declares to its navigator's bar.
@internal
@immutable
final class GlassBarDeclaration {
  /// Creates a declaration.
  const GlassBarDeclaration({
    this.leading = const [],
    this.trailing = const [],
    this.automaticallyImplyLeading = true,
    this.previousPageTitle,
    this.backButtonDisplayMode = GlassBackButtonDisplayMode.title,
    this.title,
  });

  /// The entries at the leading edge; they replace the back button.
  final List<GlassBarEntry> leading;

  /// The entries at the trailing edge.
  final List<GlassBarEntry> trailing;

  /// Whether the page gets a back button when [leading] is empty and a
  /// glass page lies below.
  final bool automaticallyImplyLeading;

  /// The back button's name for the page below, in place of its title.
  final String? previousPageTitle;

  /// How the back button names the page below.
  final GlassBackButtonDisplayMode backButtonDisplayMode;

  /// The page's title as text, which the back button of a page above
  /// shows; null when the title is not plain text.
  final String? title;
}

/// Where a page's inline title may sit in the bar's row, from the page's
/// final layout.
@internal
typedef GlassTitleRoom = ({double start, double end});

/// Whether the tab around [child] is the one its tab scaffold shows: the
/// bars of a tab left behind withdraw from the page's shared bar, and a
/// tab without bars of its own shows none.
@internal
class GlassTabShown extends InheritedWidget {
  /// Tells the bars below whether their tab shows.
  const GlassTabShown({required this.shown, required super.child, super.key});

  /// Whether the tab shows.
  final bool shown;

  /// Whether the tab around [context] shows; true outside a tab.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassTabShown>()?.shown ??
      true;

  @override
  bool updateShouldNotify(GlassTabShown oldWidget) => shown != oldWidget.shown;
}

/// One page's end of its navigator's shared bar.
///
/// The route creates it when it installs and drops it when it disposes (a
/// standalone host makes its own); the page's bars declare to it as they
/// build.
@internal
final class GlassPageBarLink {
  GlassPageBarLink._(this.host, this.route, this._presence);

  /// The bar this page belongs to.
  final GlassBarHost host;

  /// The page's route, or null for a page outside any glass page route.
  final ModalRoute<Object?>? route;

  final ValueListenable<double>? _presence;

  GlassPageBarLink? _below;
  GlassBarDeclaration? _declaration;
  Object? _declarer;
  List<GlassBarEntry>? _toolbar;
  Object? _toolbarDeclarer;
  bool _declaredToolbar = false;
  final Map<GlassBarKind, List<GlassBarCapsuleLayout>> _layouts = {};
  bool _coveredByForeign = false;
  ValueListenable<double>? _fade;

  /// The room of the page's inline title in its final layout.
  final ValueNotifier<GlassTitleRoom?> titleRoom = ValueNotifier(null);

  /// The link of the page [context] belongs to, without a dependency: a
  /// page never rebuilds because the bar moved.
  static GlassPageBarLink? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_LinkScope>()?.link;
}

// A change of the bar waiting for the layout it heads to.
final class _Change {
  _Change(this.page, this.time, this.spec, {this.fromEmpty = false});

  // The page whose layout the bar heads to; null is an empty bar.
  final GlassPageBarLink? page;
  final double time;

  // Null snaps.
  final GlassBarTransitionSpec? spec;

  // The bar starts empty: the page's groups appear in place.
  final bool fromEmpty;
}

// A button the bar builds: an item of a page or the back button.
final class _Button {
  _Button.item(this.item, this.kind) : back = null;
  _Button.back(_Back this.back) : item = null, kind = GlassBarButtonKind.back;

  final GlassBarItem? item;
  final _Back? back;
  final GlassBarButtonKind kind;
}

final class _Back {
  _Back({required this.title, required this.mode, required this.onPressed});

  // The page below's name, or null to say "Back".
  final String? title;
  final GlassBackButtonDisplayMode mode;
  final VoidCallback onPressed;

  // What the button shows beside its chevron: nothing when minimal.
  String? shownIn(BuildContext context) => switch (mode) {
    GlassBackButtonDisplayMode.minimal => null,
    GlassBackButtonDisplayMode.generic => _back(context),
    GlassBackButtonDisplayMode.title => title ?? _back(context),
  };

  // What assistive technology reads: the name it shows, or "Back".
  String labelIn(BuildContext context) => shownIn(context) ?? _back(context);

  static String _back(BuildContext context) =>
      GlassLocalizations.of(context).backButtonLabel;
}

// The back button keeps one identity across pages: it stays when both
// pages have one.
const Object _backId = 'glass.back';

// An identity derived from an item's content belongs to its page: only a
// key crosses a push.
@immutable
final class _PageId {
  const _PageId(this.page, this.id);

  final GlassPageBarLink page;
  final Object id;

  @override
  bool operator ==(Object other) =>
      other is _PageId && identical(other.page, page) && other.id == id;

  @override
  int get hashCode => Object.hash(identityHashCode(page), id);
}

/// Which bar of a page.
@internal
enum GlassBarKind {
  /// The navigation bar at the top.
  navigation,

  /// The toolbar at the bottom.
  toolbar,
}

/// The bars a navigator's glass pages share: the one owner of their state.
///
/// One per [NavigatorState], found through the route's navigator, with no
/// app wiring; a page outside any glass page route has a host of its own.
/// Routes report their events and pages their declarations synchronously,
/// and the host decides: it is the only writer of the bars' motion, of
/// which page's slot draws them ([painter]) and of what they head to.
/// Every change counts from the event that caused it (a push or pop call,
/// a finger's lift, a page's build), never from when a bar laid it out.
/// Nothing builds or lays out per frame: the clock steps each bar's motion
/// while its view shows, and the bar writes its frames as the motion
/// changes.
@internal
final class GlassBarHost {
  GlassBarHost._(this._navigator);

  /// A host for one page outside any glass page route, which draws its
  /// bar itself.
  GlassBarHost.standalone() : _navigator = null {
    final link = _standalone = GlassPageBarLink._(this, null, null);
    _pages.add(link);
    _show(link);
    _painter.value = link;
  }

  /// The bars of [navigator]'s glass pages.
  factory GlassBarHost.of(NavigatorState navigator) =>
      _hosts[navigator] ??= GlassBarHost._(navigator);

  final NavigatorState? _navigator;

  static final Expando<GlassBarHost> _hosts = Expando('GlassBarHost');

  /// The key of the one bar view, which moves between the pages' slots.
  final GlobalKey viewKey = GlobalKey(debugLabel: 'GlassBarView');

  /// The page whose slot draws the bars: the topmost live glass page.
  ValueListenable<GlassPageBarLink?> get painter => _painter;
  final _painter = ValueNotifier<GlassPageBarLink?>(null);

  late final GlassPageBarLink _standalone;

  /// The one page of a standalone host.
  GlassPageBarLink get standaloneLink => _standalone;

  // Live glass pages, bottom to top, the order of their overlay entries.
  final List<GlassPageBarLink> _pages = [];
  GlassPageBarLink? _shown;
  // The shown page's fade, which the navigation bar's capsules follow.
  final _fade = ValueNotifier<double>(1);
  ValueListenable<double>? _following;

  void _show(GlassPageBarLink? link) {
    _shown = link;
    _followFade();
  }

  void _followFade() {
    final fade = _shown?._fade;
    if (identical(fade, _following)) return;
    _following?.removeListener(_faded);
    _following = fade;
    fade?.addListener(_faded);
    _faded();
  }

  void _faded() {
    final fade = _following?.value ?? 1;
    if (fade == _fade.value) return;
    _fade.value = fade;
    final bar = _bars[GlassBarKind.navigation]!;
    if (bar.items != null) bar.publish();
  }

  /// Tells which opacity [link]'s page's navigation bar fades by while its
  /// stacked search shows.
  void fadedBy(GlassPageBarLink link, ValueListenable<double>? fade) {
    if (identical(link._fade, fade)) return;
    link._fade = fade;
    if (identical(link, _shown)) _followFade();
  }

  /// Forgets [fade] as [link]'s page's fade if it still is: the bar that
  /// reported it goes away, and the fade with it.
  void dropFade(GlassPageBarLink link, ValueListenable<double> fade) {
    if (identical(link._fade, fade)) fadedBy(link, null);
  }

  GlassPageBarLink? _swiped;
  late final Map<GlassBarKind, _Bar> _bars = {
    for (final kind in GlassBarKind.values) kind: _Bar(this, kind),
  };

  double get _now => _bars[GlassBarKind.navigation]!.motion.clock.now;

  // --- the route's events -------------------------------------------------

  /// Registers [route]'s page, which moves by [presence].
  GlassPageBarLink attach(
    ModalRoute<Object?> route, {
    required ValueListenable<double> presence,
  }) {
    final link = GlassPageBarLink._(this, route, presence);
    _pages.add(link);
    return link;
  }

  /// Unregisters [link]'s page.
  void detach(GlassPageBarLink link) {
    _pages.remove(link);
    for (final page in _pages) {
      if (identical(page._below, link)) page._below = null;
    }
    if (identical(_shown, link)) _show(null);
    if (identical(_swiped, link)) _unswipe();
    if (identical(_painter.value, link)) {
      _painter.value = _pages.isEmpty ? null : _pages.last;
    }
    link.titleRoom.dispose();
    if (_pages.isEmpty) _dispose();
  }

  // The last page went: the host goes with it, and the navigator's next
  // glass page makes a new one.
  void _dispose() {
    _following?.removeListener(_faded);
    _following = null;
    _painter.dispose();
    _fade.dispose();
    if (_navigator case final navigator?
        when identical(_hosts[navigator], this)) {
      _hosts[navigator] = null;
    }
  }

  /// Reports that [link]'s page was presented at [time], the call, with
  /// [below] under it: pushed when [animated], else added or put in place
  /// of another. A [current] page takes the bars: their layouts follow the
  /// ones they show, or grow in place when they show nothing.
  void presented(
    GlassPageBarLink link, {
    required GlassPageBarLink? below,
    required bool current,
    required bool animated,
    required double time,
  }) {
    link._below = below;
    _pages.remove(link);
    if (current) {
      _pages.add(link);
    } else {
      final under = below == null ? -1 : _pages.indexOf(below);
      _pages.insert(under < 0 ? _pages.length : under + 1, link);
    }
    _painter.value = _pages.last;
    if (!current) {
      _refreshShown(time);
      return;
    }
    final shown = _shown;
    final empty = shown == null || shown._coveredByForeign;
    _show(link);
    for (final bar in _bars.values) {
      bar.enqueue(
        _Change(
          link,
          time,
          animated ? bar.navigationSpec : null,
          fromEmpty: empty,
        ),
      );
    }
  }

  /// Reports that the page below [link]'s page changed without a push of
  /// [link]: its back button follows.
  void previousChanged(
    GlassPageBarLink link, {
    required GlassPageBarLink? below,
    required double time,
  }) {
    if (identical(link._below, below)) return;
    link._below = below;
    if (identical(link, _shown)) _refreshShown(time);
  }

  /// Reports whether a route that is not a glass page covers [link]'s page.
  void coveredChanged(GlassPageBarLink link, {required bool covered}) {
    link._coveredByForeign = covered;
  }

  /// Reports that a route that is not a glass page left [link]'s page on
  /// top again: the bars, covered meanwhile, stand on its layouts.
  void revealed(GlassPageBarLink link) {
    link._coveredByForeign = false;
    if (identical(link, _shown)) return;
    _show(link);
    for (final bar in _bars.values) {
      bar.enqueue(_Change(link, _now, null));
    }
  }

  /// Reports that [link]'s page was popped or dismissed at [time]: the
  /// call, or the finger's lift after a swipe.
  void leaving(GlassPageBarLink link, {required double time}) {
    if (!identical(link, _shown)) return;
    final below = link._below;
    _show(below);
    _unswipe();
    for (final bar in _bars.values) {
      bar.enqueue(_Change(below, time, bar.navigationSpec));
    }
  }

  /// Reports that [link]'s page left the overlay: the topmost glass page
  /// left takes the bar view.
  void finished(GlassPageBarLink link) {
    _pages.remove(link);
    _painter.value = _pages.isEmpty ? null : _pages.last;
  }

  /// Reports that a finger began to drag [link]'s page toward a pop: until
  /// it ends, each navigation bar capsule the page below also has leans
  /// toward its place there by [NavigationTuning.barDrift] of the page's
  /// way out; the toolbar stays.
  void swipeStarted(GlassPageBarLink link) {
    if (!identical(link, _shown) || link._below == null) return;
    _unswipe();
    _swiped = link;
    link._presence?.addListener(_drift);
    _bars[GlassBarKind.navigation]!.rebuild();
    _drift();
  }

  /// Reports that the finger's drag of [link]'s page ended.
  void swipeEnded(GlassPageBarLink link) {
    if (!identical(_swiped, link)) return;
    _unswipe();
    _bars[GlassBarKind.navigation]!.motion.endDrift(_now);
  }

  void _unswipe() {
    _swiped?._presence?.removeListener(_drift);
    _swiped = null;
  }

  void _drift() {
    final presence = _swiped?._presence;
    if (presence == null) return;
    _bars[GlassBarKind.navigation]!.motion.setDrift(
      _swiped?._below?._layouts[GlassBarKind.navigation],
      NavigationTuning.barDrift * (1 - presence.value).clamp(0.0, 1.0),
    );
  }

  // --- the page's declarations --------------------------------------------

  /// Records what [link]'s page declares for its navigation bar as it
  /// builds; a declaration that changes only callbacks moves nothing.
  void declare(
    GlassPageBarLink link,
    GlassBarDeclaration declaration, {
    Object? by,
  }) {
    _keep(link, by);
    final previous = link._declaration;
    link._declaration = declaration;
    link._declarer = by;
    final bar = _bars[GlassBarKind.navigation]!;
    final same =
        previous != null &&
        previous.automaticallyImplyLeading ==
            declaration.automaticallyImplyLeading &&
        previous.previousPageTitle == declaration.previousPageTitle &&
        previous.backButtonDisplayMode == declaration.backButtonDisplayMode &&
        previous.title == declaration.title &&
        _sameEntries(previous.leading, declaration.leading) &&
        _sameEntries(previous.trailing, declaration.trailing);
    _declared(bar, link, first: previous == null, same: same);
    if (same) return;
    // A title the page above names its back button after.
    for (final page in _pages) {
      if (identical(page._below, link) && identical(page, _shown)) {
        bar.enqueue(_Change(page, _now, GlassBarTransitionSpec.standard));
      }
    }
  }

  /// Records the items [link]'s page declares for its toolbar as it
  /// builds, or null for none.
  void declareToolbar(
    GlassPageBarLink link,
    List<GlassBarEntry>? items, {
    Object? by,
  }) {
    _keep(link, by);
    final previous = link._toolbar;
    link._toolbar = items;
    link._toolbarDeclarer = by;
    final same =
        previous != null && items != null && _sameEntries(previous, items);
    _declared(
      _bars[GlassBarKind.toolbar]!,
      link,
      first: previous == null && !link._declaredToolbar,
      same: same || (previous == null && items == null),
    );
    link._declaredToolbar = true;
  }

  /// Withdraws what [declarer] declared for [link]'s page, and [fade] as
  /// its fade, if they still stand: its tab was left or it went away, and
  /// the page's bar empties unless another bar declared since. It happens
  /// in the bars' next layout, in this frame, once a bar that shows now
  /// has declared; a declaration of [declarer] before then cancels it.
  void withdraw(
    GlassPageBarLink link,
    Object declarer, {
    ValueListenable<double>? fade,
  }) {
    _withdrawals.add((link: link, declarer: declarer, fade: fade));
    for (final bar in _bars.values) {
      bar.rebuild();
    }
  }

  final List<
    ({GlassPageBarLink link, Object declarer, ValueListenable<double>? fade})
  >
  _withdrawals = [];

  void _keep(GlassPageBarLink link, Object? declarer) {
    if (declarer == null || _withdrawals.isEmpty) return;
    _withdrawals.removeWhere(
      (w) => identical(w.link, link) && identical(w.declarer, declarer),
    );
  }

  void _drainWithdrawals() {
    if (_withdrawals.isEmpty) return;
    final pending = List.of(_withdrawals);
    _withdrawals.clear();
    for (final (:link, :declarer, :fade) in pending) {
      _withdraw(link, declarer);
      if (fade != null) dropFade(link, fade);
    }
  }

  void _withdraw(GlassPageBarLink link, Object declarer) {
    if (!_pages.contains(link)) return;
    if (identical(link._declarer, declarer)) {
      link._declarer = null;
      link._declaration = null;
      _declared(
        _bars[GlassBarKind.navigation]!,
        link,
        first: false,
        same: false,
      );
    }
    if (identical(link._toolbarDeclarer, declarer)) {
      link._toolbarDeclarer = null;
      link._toolbar = null;
      _declared(_bars[GlassBarKind.toolbar]!, link, first: false, same: false);
    }
  }

  void _declared(
    _Bar bar,
    GlassPageBarLink link, {
    required bool first,
    required bool same,
  }) {
    if (same) {
      bar.rememberButtons(link);
      return;
    }
    final shown = identical(link, _shown);
    if (shown && !first) {
      bar.enqueue(_Change(link, _now, GlassBarTransitionSpec.standard));
    } else if (shown && !bar.changes.any((c) => identical(c.page, link))) {
      // The page's first declaration with no change waiting for it (a
      // standalone page, or a bar added after its push was applied): it
      // stands.
      bar.enqueue(_Change(link, _now, null));
    } else {
      bar.rebuild();
    }
  }

  void _refreshShown(double time) {
    final shown = _shown;
    if (shown == null) return;
    _bars[GlassBarKind.navigation]!.enqueue(
      _Change(shown, time, GlassBarTransitionSpec.standard),
    );
  }

  static bool _sameEntries(List<GlassBarEntry> x, List<GlassBarEntry> y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      final p = x[i];
      final q = y[i];
      if (p.runtimeType != q.runtimeType) return false;
      if (p is GlassBarSpacer && q is GlassBarSpacer) {
        if (p.flexible != q.flexible) return false;
      }
      if (p is GlassBarItem && q is GlassBarItem) {
        if (_identity(p) != _identity(q) ||
            p.prominent != q.prominent ||
            (p.menuChildren == null) != (q.menuChildren == null) ||
            (p.onPressed == null) != (q.onPressed == null) ||
            p.child != q.child) {
          return false;
        }
      }
    }
    return true;
  }

  static Object _identity(GlassBarItem item) {
    final key = item.key;
    if (key != null) return key;
    final icon = item.icon;
    if (icon is Icon && icon.icon != null) return icon.icon!;
    final label = item.label;
    if (label is Text && label.data != null) return label.data!;
    return item.child?.runtimeType ?? GlassBarItem;
  }

  // The pages whose layout [bar] needs: the shown one, those its changes
  // head to, and, for the navigation bar, the page below a swiped one.
  Iterable<GlassPageBarLink> _measured(_Bar bar) sync* {
    final seen = <GlassPageBarLink>{};
    final shown = _shown;
    if (shown != null && seen.add(shown)) yield shown;
    for (final change in bar.changes) {
      final page = change.page;
      if (page != null && seen.add(page)) yield page;
    }
    if (bar.kind == GlassBarKind.navigation) {
      final below = _swiped?._below;
      if (below != null && seen.add(below)) yield below;
    }
  }
}

// One bar of a host: its motion, the changes waiting for their layouts,
// its glass and the buttons its view builds.
final class _Bar {
  _Bar(this.host, this.kind);

  final GlassBarHost host;
  final GlassBarKind kind;
  late final GlassBarMotion motion = GlassBarMotion(spec: navigationSpec);

  // Only the navigation bar fades for a stacked search.
  ValueListenable<double>? get fade =>
      kind == GlassBarKind.navigation ? host._fade : null;

  late final MotionSelection<Object?> _steps = motion.select<Object?>(
    (_) => null,
    equals: (_, _) => false,
  );
  final List<_Change> changes = [];
  final List<ValueNotifier<GlassFrame>> container = [];
  final List<ValueNotifier<GlassFrame>> apart = [];
  final Map<Object, GlassBarItemFrame> itemFrames = {};
  final Map<Object, double> widths = {};
  // The buttons the bar knows, by identity; a leaving one keeps its last.
  final Map<Object, _Button> buttons = {};
  // Which capsules are prominent, by their layout identity.
  final Set<Object> prominent = {};
  Set<Object> built = const {};
  Set<Object> measuredIds = const {};
  double width = 0;
  bool rtl = false;
  Element? view;
  // The capsule of a prominent item, from the theme.
  Color? tint;

  GlassBarItemStyle? itemStyleOf(BuildContext context) => switch (kind) {
    GlassBarKind.navigation => GlassNavigationBarStyle.maybeOf(
      context,
    )?.itemStyle,
    GlassBarKind.toolbar => GlassToolbarStyle.maybeOf(context)?.itemStyle,
  };

  // The frames follow the motion while the bar's items are on screen.
  _RenderBarItems? get items => _items;
  _RenderBarItems? _items;
  set items(_RenderBarItems? items) {
    if (_items == null && items != null) _steps.addRenderListener(publish);
    if (_items != null && items == null) _steps.removeRenderListener(publish);
    _items = items;
  }

  // A finger on a button lifts the button's whole capsule on the glass
  // button's motion (bars passport): the capsule's identity and where the
  // touched button's box sits in the capsule.
  Object? pressed;
  Offset _pressOrigin = Offset.zero;

  bool get _navigation => kind == GlassBarKind.navigation;

  GlassBarCapsuleFrame? _capsuleOf(Object item) => motion.capsuleOf(item);

  // The capsules whose glass a menu has taken over, by the item that opened
  // the menu.
  final Map<Object, Object> _menuCapsules = {};

  /// Hides or shows the capsule of [item], whose menu grows out of it.
  void menuShowing(Object item, {required bool showing}) {
    if (showing) {
      final capsule = _capsuleOf(item);
      if (capsule == null) return;
      _menuCapsules[item] = capsule.id;
    } else {
      _menuCapsules.remove(item);
    }
    if (items != null) publish();
  }

  /// Whether a menu has taken over the capsule [item] stands in.
  bool inMenuCapsule(Object item) =>
      _menuCapsules.isNotEmpty &&
      _menuCapsules.containsValue(_capsuleOf(item)?.id);

  /// Whether the menu of [item] shows.
  bool menuShows(Object item) => _menuCapsules.containsKey(item);

  /// What a menu of [item] grows out of, in [overlay]'s coordinates: the
  /// item's zone where the bar paints it, and the capsule around it.
  MenuSource? menuSource(Object item, RenderBox overlay) {
    final capsule = _capsuleOf(item);
    final zone = zoneRectOf(item);
    final global = zones?.sourceOf(item).geometry?.rect;
    if (capsule == null || zone == null || global == null || zone.isEmpty) {
      return null;
    }
    final sx = global.width / zone.width;
    final sy = global.height / zone.height;
    Rect place(Rect rect) => Rect.fromPoints(
      overlay.globalToLocal(
        global.topLeft +
            Offset((rect.left - zone.left) * sx, (rect.top - zone.top) * sy),
      ),
      overlay.globalToLocal(
        global.topLeft +
            Offset(
              (rect.right - zone.left) * sx,
              (rect.bottom - zone.top) * sy,
            ),
      ),
    );
    return MenuCapsuleSource(
      capsule: place(capsule.rect),
      item: place(zone),
      height: metrics.buttonHeight,
      alone: capsuleItems(item).length < 2,
    );
  }

  /// The smallest box a bar item takes touches in (Apple's 44 point
  /// target); its look does not grow.
  static const double minimumTarget = 44;

  /// The box [item] takes input in: its slot across the capsule's height,
  /// where the motion paints it now, without its scale.
  Rect? zoneRectOf(Object item) {
    final frame = itemFrames[item];
    if (frame == null) return null;
    return Rect.fromCenter(
      center: frame.center,
      width: math.max(frame.size.width, widths[item] ?? 0),
      height: metrics.capsuleHeight,
    );
  }

  /// Where [item] lies for input and accessibility now: it takes none
  /// while it leaves, and fades with the item and the bar.
  InputZoneFrame? zoneFrameOf(Object item) {
    final frame = itemFrames[item];
    final rect = zoneRectOf(item);
    if (frame == null || rect == null) return null;
    return InputZoneFrame(
      rect,
      opacity: frame.presence * (fade?.value ?? 1),
      takesInput: !frame.leaving,
      radius: BorderRadius.circular(metrics.capsuleHeight / 2),
    );
  }

  /// The zones of the items: their states, focus and the source a menu
  /// grows out of. The band that shows the bar owns it.
  InputZonesController<Object>? zones;

  /// Notifies when the items' frames move.
  final frames = _Frames();

  final Map<Object, _ItemInput> _inputs = {};

  /// The input of [item], kept across builds by its identity.
  _ItemInput inputOf(Object item) =>
      _inputs.putIfAbsent(item, () => _ItemInput(this, item));

  /// Grows the pools of capsule frames to [count] each.
  void grow(int count) {
    for (final pool in [container, apart]) {
      while (pool.length < count) {
        pool.add(ValueNotifier(const GlassFrame(rect: Rect.zero, opacity: 0)));
      }
    }
  }

  /// The band that owned [zones] goes: the bar's zones and capsule frames
  /// go with it.
  void letGo(InputZonesController<Object> zones) {
    if (!identical(this.zones, zones)) return;
    this.zones = null;
    for (final frame in [...container, ...apart]) {
      frame.dispose();
    }
    container.clear();
    apart.clear();
  }

  /// Forgets the input of items the bar no longer builds.
  void keepInputs(Iterable<Object> items) {
    final kept = items.toSet();
    _inputs.removeWhere((id, _) => !kept.contains(id));
  }

  /// The items of [item]'s capsule, [item] included, with their frames in it.
  List<(Object, Rect)> capsuleItems(Object item) {
    final capsule = _capsuleOf(item);
    if (capsule == null) return const [];
    return [
      for (final MapEntry(key: id, value: frame) in itemFrames.entries)
        if (_capsuleOf(id)?.id == capsule.id)
          (
            id,
            Rect.fromCenter(
              center: frame.center - capsule.rect.topLeft,
              width: frame.size.width,
              height: frame.size.height,
            ),
          ),
    ];
  }

  /// The size of [item]'s capsule.
  Size? capsuleSize(Object item) => _capsuleOf(item)?.rect.size;

  /// Lifts [item]'s capsule under a finger that touches the item's zone at
  /// [position], in the zone's coordinates, at time [t].
  void pressDown(Object item, double t, Offset position) {
    final zone = zoneRectOf(item);
    final capsule = _capsuleOf(item);
    if (zone == null || capsule == null) return;
    final lift = pressed == capsule.id ? motion.press : null;
    final press = lift ?? GlassPress(size: capsule.rect.size);
    press.size = capsule.rect.size;
    pressed = capsule.id;
    _pressOrigin = zone.topLeft - capsule.rect.topLeft;
    motion.pressDown(press, t, _pressOrigin + position);
  }

  void pressMove(double t, Offset position) =>
      motion.press?.pointerMove(t, _pressOrigin + position);

  void pressUp(double t, Offset position) =>
      motion.press?.pointerUp(t, _pressOrigin + position);

  void pressCancel(double t) => motion.press?.pointerCancel(t);

  /// How the pressed capsule moves [item] with it, in the bar's
  /// coordinates, or null when [item] is not in it.
  Matrix4? liftOf(Object item) {
    final motion = this.motion.press;
    if (motion == null || motion.isAtRest) return null;
    final capsule = _capsuleOf(item);
    if (capsule == null || capsule.id != pressed) return null;
    final center = capsule.rect.center;
    final transform = Matrix4.translationValues(
      center.dx + motion.lean.dx,
      center.dy + motion.lean.dy,
      0,
    );
    transform.scaleByDouble(motion.scaleX, motion.scaleY, 1, 1);
    transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    return transform;
  }

  GlassBarMetrics get metrics =>
      _navigation ? GlassBarMetrics.navigation : GlassBarMetrics.toolbar;

  /// The space between the screen's sides and the outer capsules.
  double get sideInset =>
      _navigation ? navigationSideInset : GlassToolbar.sideInset;

  /// The tuning of a change on a push or a pop: a navigation bar's own
  /// timing; for a toolbar, its item replacement timing (an approximation:
  /// a toolbar's push is filmed on the simulator only).
  GlassBarTransitionSpec get navigationSpec => _navigation
      ? GlassBarTransitionSpec.navigation
      : GlassBarTransitionSpec.standard;

  void enqueue(_Change change) {
    changes.add(change);
    rebuild();
  }

  // Whether the view builds again in its items' resolve phase.
  bool _rebuildInResolve = false;

  /// Builds the view again in this frame. While the framework builds or
  /// lays out (a page declares as it builds, maybe under the app's
  /// LayoutBuilder; the bar's own layout applies a change), marking the
  /// view would assert or wait for the next frame: the items' resolve phase
  /// marks it instead, and it builds and lays out again in the same frame.
  void rebuild() {
    final view = this.view;
    if (view == null || !view.mounted) return;
    final items = _items;
    if (items != null &&
        items.attached &&
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      _rebuildInResolve = true;
      items.scheduleResolve();
      return;
    }
    view.markNeedsBuild();
  }

  /// The items' resolve phase: withdrawals still waiting apply, the pages
  /// take their title rooms, and the view builds again if a change asked
  /// for it during the frame.
  void resolve() {
    host._drainWithdrawals();
    giveRooms();
    if (!_rebuildInResolve) return;
    _rebuildInResolve = false;
    final view = this.view;
    if (view != null && view.mounted) view.markNeedsBuild();
  }

  /// The runs of [page]'s bar, each a list of capsules with the identities
  /// of their buttons: a navigation bar's leading and trailing sides, a
  /// toolbar's runs between flexible spaces; a repeated identity is
  /// numbered across the whole bar.
  List<List<List<(Object, _Button)>>> runs(GlassPageBarLink page) {
    final seen = <Object, int>{};
    if (!_navigation) {
      final items = page._toolbar;
      if (items == null) return const [];
      final runs = <List<GlassBarEntry>>[[]];
      for (final entry in items) {
        if (entry is GlassBarSpacer && entry.flexible) {
          runs.add([]);
        } else {
          runs.last.add(entry);
        }
      }
      return [for (final run in runs) _capsules(page, run, seen)];
    }
    final declaration = page._declaration;
    if (declaration == null) return const [];
    final leading = declaration.leading.isEmpty
        ? _back(page, declaration)
        : _capsules(page, declaration.leading, seen);
    return [leading, _capsules(page, declaration.trailing, seen)];
  }

  List<List<(Object, _Button)>> _back(
    GlassPageBarLink page,
    GlassBarDeclaration declaration,
  ) {
    final below = page._below;
    if (below == null || !declaration.automaticallyImplyLeading) {
      return const [];
    }
    final route = page.route;
    return [
      [
        (
          _backId,
          _Button.back(
            _Back(
              title: declaration.previousPageTitle ?? below._declaration?.title,
              mode: declaration.backButtonDisplayMode,
              onPressed: () => route?.navigator?.maybePop<Object?>(),
            ),
          ),
        ),
      ],
    ];
  }

  List<List<(Object, _Button)>> _capsules(
    GlassPageBarLink page,
    List<GlassBarEntry> entries,
    Map<Object, int> seen,
  ) {
    final out = <List<(Object, _Button)>>[];
    var run = <(Object, _Button)>[];
    void close() {
      if (run.isNotEmpty) out.add(run);
      run = [];
    }

    for (final entry in entries) {
      switch (entry) {
        case GlassBarSpacer():
          close();
        case GlassBarItem():
          final derived = GlassBarHost._identity(entry);
          final n = seen[derived] = (seen[derived] ?? -1) + 1;
          final base = entry.key ?? _PageId(page, derived);
          final id = n == 0 ? base : GlassBarItemId(base, n);
          final kind = entry.child != null
              ? GlassBarButtonKind.custom
              : entry.icon != null
              ? GlassBarButtonKind.icon
              : GlassBarButtonKind.label;
          if (entry.prominent) {
            close();
            out.add([(id, _Button.item(entry, kind))]);
            continue;
          }
          run.add((id, _Button.item(entry, kind)));
      }
    }
    close();
    return out;
  }

  void rememberButtons(GlassPageBarLink page) {
    for (final run in runs(page)) {
      for (final capsule in run) {
        for (final (id, button) in capsule) {
          buttons[id] = button;
        }
      }
    }
  }

  /// The buttons the view builds: every item a measured page has and every
  /// item the motion still draws.
  Map<Object, _Button> roster() {
    final pages = host._measured(this).toList();
    for (final page in pages) {
      rememberButtons(page);
    }
    measuredIds = {
      for (final page in pages)
        for (final run in runs(page))
          for (final capsule in run)
            for (final (id, _) in capsule) id,
    };
    final ids = {...measuredIds, for (final frame in motion.items) frame.id};
    buttons.removeWhere((id, _) => !ids.contains(id));
    built = ids;
    return {for (final id in ids) id: buttons[id]!};
  }

  /// The title rooms the latest layout computed, which the pages take in
  /// the frame's resolve phase ([giveRooms]).
  List<(GlassPageBarLink, GlassTitleRoom)> pendingRooms = const [];

  /// Gives the pages the title rooms the latest layout computed.
  void giveRooms() {
    final rooms = pendingRooms;
    pendingRooms = const [];
    for (final (page, room) in rooms) {
      if (host._pages.contains(page)) page.titleRoom.value = room;
    }
  }

  /// Takes the content widths the view measured in a bar [width] wide and
  /// applies the waiting changes, each at its own time.
  void measured(
    Map<Object, double> widths,
    double width, {
    required bool rtl,
  }) {
    final resized = width != this.width || rtl != this.rtl;
    this.width = width;
    this.rtl = rtl;
    this.widths.addAll(widths);
    final pages = host._measured(this).toList();
    final rooms = <(GlassPageBarLink, GlassTitleRoom)>[];
    prominent.clear();
    for (final page in pages) {
      final runs = this.runs(page);
      final layout = page._layouts[kind] = _layoutOf(runs);
      // The layout lists trailing capsules from the edge in, so a capsule
      // is found by its buttons, not by its place in [runs].
      final tinted = {
        for (final run in runs)
          for (final capsule in run)
            if (capsule.first.$2.item?.prominent ?? false) capsule.first.$1,
      };
      for (final capsule in layout) {
        if (capsule.items.any((item) => tinted.contains(item.id))) {
          prominent.add(capsule.id);
        }
      }
      if (_navigation) {
        final room = _roomOf(layout);
        if (page.titleRoom.value != room) rooms.add((page, room));
      }
    }
    // The titles are laid out in their pages, which this layout must not
    // touch: they take their room in the frame's resolve phase, and lay
    // out again in this frame.
    pendingRooms = rooms;
    final pending = List.of(changes);
    changes.clear();
    for (final change in pending) {
      final target =
          change.page?._layouts[kind] ?? const <GlassBarCapsuleLayout>[];
      if (change.fromEmpty) {
        motion.setLayout(change.time, const [], animated: false);
      }
      motion.setLayout(
        change.time,
        target,
        animated: change.spec != null,
        transition: change.spec,
      );
    }
    if (pending.isEmpty && resized) {
      motion.setLayout(
        host._now,
        host._shown?._layouts[kind] ?? const [],
        animated: false,
      );
    }
    publish();
  }

  List<GlassBarCapsuleLayout> _layoutOf(
    List<List<List<(Object, _Button)>>> runs,
  ) {
    List<GlassBarCapsuleSpec> specs(List<List<(Object, _Button)>> run) => [
      for (final capsule in run)
        GlassBarCapsuleSpec([
          for (final (id, button) in capsule)
            GlassBarButtonSpec(
              id,
              button.kind == GlassBarButtonKind.back
                  ? _backLabelWidth(widths[id] ?? 0, button.back!)
                  : widths[id] ?? 0,
              button.kind,
            ),
        ]),
    ];
    if (runs.isEmpty) return const [];
    return layoutGlassBar(
      leading: specs(runs.first),
      trailing: runs.length > 1 ? specs(runs.last) : const [],
      center: [
        for (var i = 1; i < runs.length - 1; i++) specs(runs[i]),
      ],
      width: width,
      top: 0,
      leadingInset: sideInset,
      trailingInset: sideInset,
      metrics: metrics,
      rtl: rtl,
    );
  }

  static double _backLabelWidth(double built, _Back back) {
    const metrics = GlassBarMetrics.navigation;
    if (back.mode == GlassBackButtonDisplayMode.minimal) return 0;
    return math.max(
      0,
      built -
          metrics.backChevronInset -
          metrics.backChevronWidth -
          metrics.backChevronGap -
          metrics.backTrailingPadding,
    );
  }

  /// The space between an inline title and the capsules beside it
  /// (`titleControlPadding`, read from UIKit).
  static const double _titleControlPadding = 12;

  GlassTitleRoom _roomOf(List<GlassBarCapsuleLayout> layout) {
    const padding = _titleControlPadding;
    var start = sideInset;
    var end = width - sideInset;
    for (final capsule in layout) {
      final leading = capsule.segment == glassBarLeading;
      if (leading != rtl) {
        start = math.max(start, capsule.rect.right + padding);
      } else {
        end = math.min(end, capsule.rect.left - padding);
      }
    }
    return (start: start, end: end);
  }

  void publish() {
    final fade = this.fade?.value ?? 1;
    final press = motion.press;
    if (press == null) pressed = null;
    final joined = <GlassBarCapsuleFrame>[];
    final apartFrames = <GlassBarCapsuleFrame>[];
    for (final capsule in motion.capsules) {
      (capsule.apart ? apartFrames : joined).add(capsule);
    }
    void write(
      List<ValueNotifier<GlassFrame>> pool,
      List<GlassBarCapsuleFrame> frames,
    ) {
      for (var i = 0; i < pool.length; i++) {
        if (i >= frames.length) {
          pool[i].value = const GlassFrame(rect: Rect.zero, opacity: 0);
          continue;
        }
        final frame = frames[i];
        final lift = frame.id == pressed ? press : null;
        final glow = lift?.touchGlow;
        pool[i].value = GlassFrame(
          rect: lift == null ? frame.rect : frame.rect.shift(lift.lean),
          scaleX: lift?.scaleX ?? 1,
          scaleY: lift?.scaleY ?? 1,
          glow: glow == null
              ? null
              : GlassTouchGlow(
                  wash: glow.wash,
                  center: glow.center + frame.rect.topLeft,
                  radius: glow.radius,
                  spot: glow.spot,
                ),
          opacity: _menuCapsules.containsValue(frame.id)
              ? 0
              : frame.opacity * fade,
          tint: prominent.contains(frame.id) ? tint : null,
        );
      }
    }

    write(container, joined);
    write(apart, apartFrames);
    itemFrames.clear();
    for (final frame in motion.items) {
      itemFrames[frame.id] = frame;
    }
    items?.moved();
    frames.notify();
    final ids = {for (final f in motion.items) f.id};
    // A new item joins the roster; one that has left drops from it.
    if (joined.length > container.length ||
        apartFrames.length > apart.length ||
        !built.containsAll(ids) ||
        built.difference(ids).difference(measuredIds).isNotEmpty) {
      rebuild();
    }
  }
}

/// Tells the bar's zones that its items moved.
final class _Frames implements Listenable {
  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

/// One item's input: a press that lifts its capsule under the finger and
/// calls the item, or, for an item with a menu, the lift alone (the menu's
/// source takes the touch) and the keys that open the menu.
final class _ItemInput extends PointerFollower {
  _ItemInput(this.bar, this.id);

  final _Bar bar;
  final Object id;

  /// What a tap, Space or Enter calls; for an item with a menu, null opens
  /// the menu.
  VoidCallback? onPressed;

  /// Opens the item's menu from the keyboard and assistive technology.
  final menu = GlassMenuController();

  late final List<Interaction> press = [
    PressInteraction(
      releaseSlop: const EdgeInsets.all(GlassPress.highlightSlop),
      onTap: (_) => onPressed?.call(),
    ).simultaneously(FollowInteraction(this)),
  ];

  late final List<Interaction> menuSource = [
    _Activate(() => (onPressed ?? menu.open)()).simultaneously(
      FollowInteraction(this),
    ),
  ];

  @override
  void down(PointerDownInput input) =>
      bar.pressDown(id, input.time, input.position);

  @override
  void move(PointerMoveInput input) =>
      bar.pressMove(input.time, input.position);

  @override
  void up(PointerUpInput input) => bar.pressUp(input.time, input.position);

  @override
  void cancel(PointerCancelInput input) => bar.pressCancel(input.time);
}

/// Space, Enter and assistive technology's tap, with no touch: the menu's
/// source under the zone takes the touches.
final class _Activate extends Interaction {
  _Activate(this.onActivate);

  final VoidCallback onActivate;

  @override
  bool get activates => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is! ActivateInput) return InteractionUpdate.none;
    onActivate();
    return InteractionUpdate(
      events: [ActivationEvent(time: input.time, source: input.source)],
    );
  }
}

// ===========================================================================
// The view
// ===========================================================================

class _LinkScope extends InheritedWidget {
  const _LinkScope({required this.link, required super.child});

  final GlassPageBarLink link;

  @override
  bool updateShouldNotify(_LinkScope oldWidget) => false;
}

/// The z-slot a glass page route gives its navigator's bars: an
/// [OverlayPortal] around the page's content, whose overlay child is the
/// bar view while the page is the host's painter.
///
/// The overlay child paints right above the route's page and below every
/// later route, inherits the route's themes, direction and media query,
/// and is neither painted nor hit while the route is offstage. It sits
/// outside the page's card and swipe: the bars stay while the page moves.
@internal
class GlassBarSlot extends StatefulWidget {
  /// Gives [link]'s page a slot around [child].
  const GlassBarSlot({required this.link, required this.child, super.key});

  /// The page's link.
  final GlassPageBarLink link;

  /// The page's content.
  final Widget child;

  @override
  State<GlassBarSlot> createState() => _GlassBarSlotState();
}

class _GlassBarSlotState extends State<GlassBarSlot> {
  final _portal = OverlayPortalController();
  ValueListenable<GlassPageBarLink?>? _painter;

  @override
  void initState() {
    super.initState();
    _portal.show();
    _follow();
  }

  @override
  void didUpdateWidget(GlassBarSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.link.host, widget.link.host)) _follow();
  }

  @override
  void dispose() {
    _painter?.removeListener(_painted);
    super.dispose();
  }

  void _follow() {
    _painter?.removeListener(_painted);
    _painter = widget.link.host.painter;
    _painter!.addListener(_painted);
  }

  // Another page's slot takes the bars, or this one does: a page's event,
  // not a frame of motion.
  void _painted() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final host = link.host;
    return _LinkScope(
      link: link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => identical(host.painter.value, link)
            ? KeyedSubtree(
                key: host.viewKey,
                child: GlassBarView(host: host),
              )
            : const SizedBox.shrink(),
        child: widget.child,
      ),
    );
  }
}

/// The bars of [host]: the navigation bar's row under the status bar and
/// the toolbar's row 28 points above the screen's bottom (8 above a
/// keyboard), each with its capsules and their buttons; with [only], that
/// bar alone, filling the box it is given.
///
/// Each bar builds in a [LayoutBuilder], so a page that declares while it
/// builds reaches it in the same frame.
@internal
class GlassBarView extends StatelessWidget {
  /// Creates the view of [host].
  const GlassBarView({required this.host, this.only, super.key});

  /// The bars.
  final GlassBarHost host;

  /// The one bar to draw in the given box, or null for both in their
  /// places on the screen.
  final GlassBarKind? only;

  @override
  Widget build(BuildContext context) {
    for (final bar in host._bars.values) {
      bar.tint = GlassDynamicColor.resolve(
        bar.itemStyleOf(context)?.prominentColor ??
            GlassTheme.primaryColorOf(context) ??
            _prominentColor,
        context,
      );
    }
    final only = this.only;
    if (only != null) return _Band(bar: host._bars[only]!);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: media.padding.top,
          left: 0,
          right: 0,
          height: GlassNavigationBar.height,
          child: _Band(bar: host._bars[GlassBarKind.navigation]!),
        ),
        Positioned(
          bottom: keyboard > 0
              ? keyboard + GlassToolbar.keyboardInset
              : GlassToolbar.bottomInset,
          left: 0,
          right: 0,
          height: GlassBarMetrics.toolbar.capsuleHeight,
          child: _Band(bar: host._bars[GlassBarKind.toolbar]!),
        ),
      ],
    );
  }

  /// The prominent capsule's tint without a primary color (device).
  static const _prominentColor = Color(0xFF0088FF);
}

/// The space between the screen's sides and a navigation bar's outer
/// items: 16 on a 402 point screen (bars passport); the Pro Max's 20 is not
/// followed (approximation).
@internal
const double navigationSideInset = 16;

/// Cuts off what moves above the clipped box's top, and nothing below: a
/// pulled large title still follows the content down.
@internal
class BelowTop extends CustomClipper<Rect> {
  /// Creates the clipper.
  const BelowTop();

  @override
  Rect getClip(Size size) => const Rect.fromLTRB(-100000, 0, 100000, 100000);

  @override
  bool shouldReclip(BelowTop oldClipper) => false;
}

// One bar's row: its glass and its buttons, rebuilt during its layout. It
// owns the zones of the bar's items while it shows them.
class _Band extends StatefulWidget {
  const _Band({required this.bar});

  final _Bar bar;

  @override
  State<_Band> createState() => _BandState();
}

class _BandState extends State<_Band> {
  final _zones = InputZonesController<Object>();

  _Bar get bar => widget.bar;

  @override
  void initState() {
    super.initState();
    bar.zones = _zones;
  }

  @override
  void didUpdateWidget(_Band oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bar, bar)) return;
    oldWidget.bar.letGo(_zones);
    bar.zones = _zones;
  }

  @override
  void dispose() {
    bar.letGo(_zones);
    _zones.dispose();
    super.dispose();
  }

  InputZone<Object> _zoneOf(BuildContext context, Object id, _Button button) {
    final input = bar.inputOf(id);
    final item = button.item;
    final menu = item?.menuChildren != null;
    input.onPressed = button.back?.onPressed ?? item?.onPressed;
    final hold = menu && item!.onPressed != null;
    return InputZone<Object>(
      id: id,
      interactions: menu ? input.menuSource : input.press,
      enabled: menu || input.onPressed != null,
      minimumHitSize: const Size.square(_Bar.minimumTarget),
      semanticLabel: switch (button.back) {
        final back? => back.labelIn(context),
        null => _labelOf(item!),
      },
      button: true,
      describeSemantics: menu
          ? (config) {
              config.isExpanded = bar.menuShows(id);
              if (hold) config.onLongPress = input.menu.open;
            }
          : null,
    );
  }

  static String? _labelOf(GlassBarItem item) =>
      item.semanticLabel ??
      switch (item.icon ?? item.label) {
        Text(:final data?) => data,
        Icon(:final semanticLabel?) => semanticLabel,
        _ => null,
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      bar.view = context as Element;
      final roster = bar.roster();
      bar.keepInputs(roster.keys);
      bar.grow(roster.length + 2);
      final items = InputZones<Object>(
        // An item no page declares any more is leaving: it gets no zone,
        // which also keeps a hidden zone's stale semantics out of a bar
        // that moves to another route's overlay.
        zones: [
          for (final MapEntry(key: id, value: button) in roster.entries)
            if (button.item?.child == null && bar.measuredIds.contains(id))
              _zoneOf(context, id, button),
        ],
        frameOf: bar.zoneFrameOf,
        frames: bar.frames,
        controller: _zones,
        excludeChildSemantics: false,
        child: _BarItems(
          bar: bar,
          zones: _zones,
          children: [
            for (final MapEntry(key: id, value: button) in roster.entries)
              _BarItem(
                key: ValueKey(id),
                bar: bar,
                id: id,
                button: button,
              ),
          ],
        ),
      );
      return MotionScope(
        motion: bar.motion,
        child: RepaintBoundary(
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              _Surfaces(
                frames: bar.container,
                merge: const GlassMerge.spacing(GlassToolbar.fusion),
              ),
              _Surfaces(frames: bar.apart, merge: const GlassMerge.none()),
              if (bar.fade case final fade?)
                MotionTransition(opacity: fade, child: items)
              else
                items,
            ],
          ),
        ),
      );
    },
  );
}

class _Surfaces extends StatelessWidget {
  const _Surfaces({required this.frames, required this.merge});

  final List<ValueNotifier<GlassFrame>> frames;
  final GlassMerge merge;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: GlassGroup(
      merge: merge,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          for (final frame in frames)
            GlassSurface.written(
              frame: frame,
              child: const SizedBox.expand(),
            ),
        ],
      ),
    ),
  );
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.bar,
    required this.id,
    required this.button,
    super.key,
  });

  final _Bar bar;
  final Object id;
  final _Button button;

  // The item's zone in the bar's InputZones takes its input and speaks for
  // it, so its glyph is not read on its own.
  @override
  Widget build(BuildContext context) {
    if (button.item?.child case final child?) {
      return _ItemBox(id: id, child: child);
    }
    final item = button.item;
    final content = ExcludeSemantics(child: _glyphOf(context, button));
    final menu = item?.menuChildren;
    if (menu == null) return _ItemBox(id: id, child: content);
    // The menu's source takes the touches; its keys and focus are the
    // zone's, so it is no stop of its own. Its open menu lies in its
    // semantics, so they are read while it shows.
    return _ItemBox(
      id: id,
      child: _OpenMenuSemantics(
        bar: bar,
        id: id,
        child: ExcludeFocusTraversal(
          child: GlassMenuAnchor(
            menuChildren: menu,
            semanticLabel: _BandState._labelOf(item!),
            controller: bar.inputOf(id).menu,
            scalesOnPress: false,
            sourceOf: (overlay) => bar.menuSource(id, overlay),
            onOpen: () => bar.menuShowing(id, showing: true),
            onClose: () => bar.menuShowing(id, showing: false),
            child: _ItemSource(
              onPressed: item.onPressed ?? bar.inputOf(id).menu.open,
              semanticLabel: _BandState._labelOf(item),
              look: _CapsuleLook(
                bar: bar,
                item: id,
                glyphs: {
                  for (final MapEntry(key: id, value: button)
                      in bar.buttons.entries)
                    if (button.item?.child == null)
                      id: _glyphOf(context, button),
                },
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _glyphOf(BuildContext context, _Button button) {
    final look = bar.itemStyleOf(context);
    final item = button.item;
    final enabled =
        button.back != null ||
        item?.onPressed != null ||
        item?.menuChildren != null;
    final prominent = item?.prominent ?? false;
    final color = GlassDynamicColor.resolve(
      prominent
          ? look?.prominentForegroundColor ?? const Color(0xFFFFFFFF)
          : look?.foregroundColor?.resolve({
                  if (!enabled) WidgetState.disabled,
                }) ??
                (enabled
                    ? GlassTheme.labelColorOf(context)
                    : GlassTheme.tertiaryLabelColorOf(context)),
      context,
    );
    final text = resolveGlassText(
      TextStyle(
        fontSize: 17,
        fontWeight: prominent ? FontWeight.w600 : FontWeight.w500,
        height: 1.2,
      ).merge(look?.textStyle).copyWith(color: color),
      context,
    );
    if (button.back case final back?) {
      const metrics = GlassBarMetrics.navigation;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: metrics.backChevronInset),
          SizedBox(
            width: metrics.backChevronWidth,
            height: _chevronHeight,
            child: CustomPaint(
              painter: _ChevronPainter(color: color, mirrored: rtl),
            ),
          ),
          if (back.shownIn(context) case final title?) ...[
            SizedBox(width: metrics.backChevronGap),
            Text(title, style: text, maxLines: 1),
            SizedBox(width: metrics.backTrailingPadding),
          ] else
            SizedBox(width: metrics.backChevronInset),
        ],
      );
    }
    return IconTheme.merge(
      data: IconThemeData(size: bar.metrics.iconSize, color: color),
      child: DefaultTextStyle(
        style: text,
        maxLines: 1,
        child: item!.icon ?? item.label!,
      ),
    );
  }

  static const double _chevronHeight = 23;
}

/// The glyphs of [item]'s capsule, each where it stands in the capsule: what
/// rides the capsule's shape as it shrinks into a menu. An item with a custom
/// view has no copy to ride it, so it is left out.
class _CapsuleLook extends StatelessWidget {
  const _CapsuleLook({
    required this.bar,
    required this.item,
    required this.glyphs,
  });

  final _Bar bar;
  final Object item;
  final Map<Object, Widget> glyphs;

  @override
  Widget build(BuildContext context) {
    final size = bar.capsuleSize(item);
    if (size == null) return const SizedBox.shrink();
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          for (final (id, rect) in bar.capsuleItems(item))
            if (glyphs[id] case final glyph?)
              Positioned.fromRect(
                rect: rect,
                child: Center(child: glyph),
              ),
        ],
      ),
    );
  }
}

/// The back chevron, pointing to the leading edge; [mirrored] flips it.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.19;
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final left = stroke / 2 + size.width * 0.12;
    final right = size.width - stroke / 2 - size.width * 0.12;
    final path = Path();
    if (mirrored) {
      path.moveTo(left, stroke / 2);
      path.lineTo(right, size.height / 2);
      path.lineTo(left, size.height - stroke / 2);
    } else {
      path.moveTo(right, stroke / 2);
      path.lineTo(left, size.height / 2);
      path.lineTo(right, size.height - stroke / 2);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}

class _BarItems extends MultiChildRenderObjectWidget {
  const _BarItems({
    required this.bar,
    required this.zones,
    required super.children,
  });

  final _Bar bar;
  final InputZonesController<Object> zones;

  _Highlights _highlightsOf(BuildContext context) {
    final traits = GlassTraits.of(context);
    Color resolved(Color color) =>
        color is GlassDynamicColor ? color.resolvedWith(traits) : color;
    return _Highlights(
      zones: zones,
      ring: GlassHighlights.ringColor(
        null,
        resolved(GlassColors.systemBlue),
        highContrast: traits.highContrast,
      ),
      hover: GlassHighlights.hoverColor,
      reduceMotion: traits.reduceMotion,
    );
  }

  @override
  _RenderBarItems createRenderObject(BuildContext context) => _RenderBarItems(
    bar,
    rtl: Directionality.of(context) == TextDirection.rtl,
    highlights: _highlightsOf(context),
  );

  // The bar rebuilds only for a change, which its layout applies.
  @override
  void updateRenderObject(BuildContext context, _RenderBarItems renderObject) {
    renderObject.rtl = Directionality.of(context) == TextDirection.rtl;
    renderObject.highlights = _highlightsOf(context);
    renderObject.markNeedsLayout();
  }
}

/// How the items show the keyboard focus and the pointer over them.
@immutable
final class _Highlights {
  const _Highlights({
    required this.zones,
    required this.ring,
    required this.hover,
    required this.reduceMotion,
  });

  final InputZonesController<Object> zones;
  final Color ring;
  final Color hover;
  final bool reduceMotion;
}

/// One item's states, read from the zones of all of them.
final class _ZoneStates implements ValueListenable<Set<WidgetState>> {
  _ZoneStates(this.zones, this.id);

  final InputZonesController<Object> zones;
  final Object id;

  @override
  Set<WidgetState> get value => zones.statesOf(id);

  @override
  void addListener(VoidCallback listener) => zones.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => zones.removeListener(listener);
}

class _ItemData extends ContainerBoxParentData<RenderBox> {}

/// Lays the bar's buttons out to measure them, hands the widths to the
/// host, and paints each where the host's motion puts it: moved, scaled,
/// faded and blurred, without a layout per frame, with the keyboard focus
/// ring and the hover response of its zone by the rule of
/// [GlassHighlights]: the ring outside the button's capsule, the hover a
/// glass body's wash over it (approximations, not measured). The zones
/// take the buttons' input; a custom item's own widget is hit, and read
/// by assistive technology, while its zone frame is live.
class _RenderBarItems extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ItemData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ItemData>,
        MotionResolveHost {
  _RenderBarItems(
    this.bar, {
    required this._rtl,
    required this._highlights,
  });

  final _Bar bar;

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsLayout();
  }

  _Highlights _highlights;
  _Highlights get highlights => _highlights;
  set highlights(_Highlights value) {
    final old = _highlights;
    _highlights = value;
    if (!identical(old.zones, value.zones)) {
      for (final MapEntry(key: id, value: highlight) in _shown.entries) {
        highlight.states = _ZoneStates(value.zones, id);
      }
    }
    for (final highlight in _shown.values) {
      highlight.reduceMotion = value.reduceMotion;
    }
    if (old.ring != value.ring || old.hover != value.hover) markNeedsPaint();
  }

  final Map<RenderBox, LayerHandle<ContainerLayer>> _layers = {};
  final Map<Object, GlassHighlight> _shown = {};

  GlassHighlight _highlightOf(Object id) => _shown.putIfAbsent(id, () {
    final highlight = GlassHighlight(
      states: _ZoneStates(_highlights.zones, id),
      reduceMotion: _highlights.reduceMotion,
    );
    if (attached) highlight.addListener(markNeedsPaint);
    return highlight;
  });

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ItemData) child.parentData = _ItemData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    bar.items = this;
    for (final highlight in _shown.values) {
      highlight.addListener(markNeedsPaint);
    }
  }

  @override
  void detach() {
    if (identical(bar.items, this)) bar.items = null;
    for (final highlight in _shown.values) {
      highlight.removeListener(markNeedsPaint);
    }
    super.detach();
  }

  @override
  void dispose() {
    for (final handle in _layers.values) {
      handle.layer = null;
    }
    super.dispose();
  }

  Object _idOf(RenderBox child) => (child as _RenderItemBox).id;

  @override
  void performLayout() {
    bar.host._drainWithdrawals();
    size = constraints.biggest;
    final widths = <Object, double>{};
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints(maxHeight: size.height),
        parentUsesSize: true,
      );
      final id = _idOf(child);
      widths[id] = child.size.width;
      if (bar.buttons[id]?.item?.child == null) _highlightOf(id);
      child = childAfter(child);
    }
    for (final id in _shown.keys.toList()) {
      if (widths.containsKey(id)) continue;
      if (attached) _shown[id]!.removeListener(markNeedsPaint);
      _shown.remove(id);
    }
    bar.measured(widths, size.width, rtl: _rtl);
    if (bar.pendingRooms.isNotEmpty) scheduleResolve();
  }

  @override
  void resolve() => bar.resolve();

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final frame = bar.itemFrames[_idOf(child)];
    if (frame == null) return;
    final c = frame.center;
    transform.translateByDouble(c.dx, c.dy, 0, 1);
    transform.scaleByDouble(frame.scale, frame.scale, 1, 1);
    final half = child.size.center(Offset.zero);
    transform.translateByDouble(-half.dx, -half.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final frame = bar.zoneFrameOf(_idOf(child));
      if (frame != null && frame.live) {
        final rect = frame.rect;
        final box = Rect.fromCenter(
          center: rect.center,
          width: math.max(rect.width, _Bar.minimumTarget),
          height: math.max(rect.height, _Bar.minimumTarget),
        );
        if (box.contains(position)) {
          final origin = rect.center - child.size.center(Offset.zero);
          final local = position - origin;
          final inside = Offset(
            local.dx.clamp(0, math.max(0, child.size.width - 0.01)),
            local.dy.clamp(0, math.max(0, child.size.height - 0.01)),
          );
          final hit = result.addWithPaintOffset(
            offset: origin,
            position: origin + inside,
            hitTest: (result, transformed) =>
                child!.hitTest(result, position: transformed),
          );
          if (hit) return true;
        }
      }
      child = childBefore(child);
    }
    return false;
  }

  // The items assistive technology reads: those whose zone frame is live.
  Set<Object> _read = const {};

  /// The motion moved the items: they paint again, and assistive
  /// technology hears of an item that came or went.
  void moved() {
    markNeedsPaint();
    final read = <Object>{};
    var child = firstChild;
    while (child != null) {
      final id = _idOf(child);
      if (bar.zoneFrameOf(id)?.live ?? false) read.add(id);
      child = childAfter(child);
    }
    if (setEquals(read, _read)) return;
    _read = read;
    markNeedsSemanticsUpdate();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      if (_read.contains(_idOf(child))) visitor(child);
      child = childAfter(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final id = _idOf(child);
      final frame = bar.itemFrames[id];
      final handle = _layers.putIfAbsent(child, LayerHandle.new);
      if (frame == null ||
          frame.presence <= 0 ||
          frame.scale <= 0 ||
          bar.inMenuCapsule(id)) {
        handle.layer = null;
        child = childAfter(child);
        continue;
      }
      final box = child;
      final origin = offset + frame.center - box.size.center(Offset.zero);
      // The lift and the scale, in the coordinates of the item's origin.
      Matrix4? transform;
      if (bar.liftOf(id) case final lift?) {
        transform = Matrix4.translationValues(
          offset.dx - origin.dx,
          offset.dy - origin.dy,
          0,
        );
        transform.multiply(lift);
        transform.translateByDouble(
          origin.dx - offset.dx,
          origin.dy - offset.dy,
          0,
          1,
        );
      }
      if (frame.scale != 1) {
        final c = box.size.center(Offset.zero);
        transform ??= Matrix4.identity();
        transform.translateByDouble(c.dx, c.dy, 0, 1);
        transform.scaleByDouble(frame.scale, frame.scale, 1, 1);
        transform.translateByDouble(-c.dx, -c.dy, 0, 1);
      }
      final alpha = (frame.presence * 255).round();
      // The item's capsule, in the layer's coordinates.
      final body = Rect.fromCenter(
        center: box.size.center(Offset.zero),
        width: frame.size.width,
        height: bar.metrics.buttonHeight,
      );
      final highlight = _shown[id];
      // One layer whose blur the glass over the bar knows the reach of: an
      // item that blurs in then lies in the copies of the glass it is under,
      // not in every copy of the frame.
      final held = handle.layer;
      final layer = held is MotionTransitionLayer
          ? held
          : MotionTransitionLayer();
      layer.offset = origin;
      layer.update(
        transform: transform,
        clip: null,
        alpha: alpha >= 255 ? null : alpha,
        blur: frame.blur <= 0.05 ? 0 : frame.blur / 2,
      );
      handle.layer = layer;
      context.pushLayer(layer, (context, _) {
        context.paintChild(box, Offset.zero);
        if (highlight != null) _paintHighlight(context.canvas, highlight, body);
      }, Offset.zero);
      child = childAfter(child);
    }
  }

  void _paintHighlight(Canvas canvas, GlassHighlight highlight, Rect body) {
    final hovered = highlight.hovered;
    if (hovered > 0) {
      GlassHighlights.paintHover(
        canvas,
        GlassShape.capsule.pathIn(body),
        _highlights.hover,
        hovered,
      );
    }
    if (highlight.focused) {
      GlassHighlights.paintRing(
        canvas,
        _highlights.ring,
        shape: GlassShape.capsule,
        body: body,
      );
    }
  }

  @override
  bool get alwaysNeedsCompositing => true;
}

/// An item's source under its menu anchor: its own tap, and the capsule
/// look the menu's glass carries as it grows out of the glyph.
class _ItemSource extends StatefulWidget {
  const _ItemSource({
    required this.onPressed,
    required this.semanticLabel,
    required this.look,
    required this.child,
  });

  final VoidCallback onPressed;
  final String? semanticLabel;
  final Widget look;
  final Widget child;

  @override
  State<_ItemSource> createState() => _ItemSourceState();
}

class _ItemSourceState extends State<_ItemSource> {
  late final List<Interaction> _tap = [
    PressInteraction(
      releaseSlop: const EdgeInsets.all(GlassPress.highlightSlop),
      onTap: (_) => widget.onPressed(),
    ),
  ];

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _tap,
    semanticLabel: widget.semanticLabel,
    minimumHitSize: const Size.square(_Bar.minimumTarget),
    child: GlassSource(
      description: GlassSourceDescription(look: widget.look),
      child: widget.child,
    ),
  );
}

/// Reads its child, a menu and its source, to assistive technology only
/// while the menu shows: the item's zone speaks for the source otherwise.
class _OpenMenuSemantics extends SingleChildRenderObjectWidget {
  const _OpenMenuSemantics({
    required this.bar,
    required this.id,
    required super.child,
  });

  final _Bar bar;
  final Object id;

  @override
  _RenderOpenMenuSemantics createRenderObject(BuildContext context) =>
      _RenderOpenMenuSemantics(bar, id);
}

class _RenderOpenMenuSemantics extends RenderProxyBox {
  _RenderOpenMenuSemantics(this.bar, this.id);

  final _Bar bar;

  // The item's element is keyed by its id, so the id never changes.
  final Object id;

  bool _open = false;

  void _check() {
    final open = bar.menuShows(id);
    if (open == _open) return;
    _open = open;
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _open = bar.menuShows(id);
    bar.frames.addListener(_check);
  }

  @override
  void detach() {
    bar.frames.removeListener(_check);
    super.detach();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_open) super.visitChildrenForSemantics(visitor);
  }
}

class _ItemBox extends SingleChildRenderObjectWidget {
  const _ItemBox({required this.id, required super.child});

  final Object id;

  @override
  _RenderItemBox createRenderObject(BuildContext context) => _RenderItemBox(id);

  @override
  void updateRenderObject(BuildContext context, _RenderItemBox renderObject) {
    renderObject.id = id;
  }
}

class _RenderItemBox extends RenderProxyBox {
  _RenderItemBox(this.id);

  Object id;
}
