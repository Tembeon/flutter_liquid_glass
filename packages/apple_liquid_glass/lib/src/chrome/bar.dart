import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/src/chrome/bar_entry.dart';
import 'package:apple_liquid_glass/src/motion/bar_layout.dart';
import 'package:apple_liquid_glass/src/motion/bar_motion.dart';
import 'package:apple_liquid_glass/src/motion/navigation_motion.dart';
import 'package:apple_liquid_glass/src/surface/frame.dart';
import 'package:apple_liquid_glass/src/surface/group.dart';
import 'package:apple_liquid_glass/src/surface/surface.dart';
import 'package:apple_liquid_glass/src/theme/colors.dart';
import 'package:apple_liquid_glass/src/theme/theme.dart';
import 'package:apple_liquid_glass/src/theme/traits.dart';
import 'package:apple_liquid_glass/src/theme/typography.dart';
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

/// Where a page's inline title may sit in the bar's row: between the
/// page's leading and trailing capsules, 12 points from each
/// (`titleControlPadding`), from the page's final layout.
@internal
typedef GlassTitleRoom = ({double start, double end});

/// One page's end of its navigator's shared bar.
///
/// The route creates it when it installs and drops it when it disposes;
/// the page's navigation bar declares to it as it builds.
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
  List<GlassBarEntry>? _toolbar;
  bool _declaredToolbar = false;
  final Map<GlassBarKind, List<GlassBarCapsuleLayout>> _layouts = {};
  bool _coveredByForeign = false;

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
  _Back({required this.label, required this.onPressed});

  final String? label;
  final VoidCallback onPressed;
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
/// Nothing builds or lays out per frame: [step] advances the motions and
/// writes frames, and the view paints them.
@internal
final class GlassBarHost implements MotionDriver {
  GlassBarHost._();

  /// A host for one page outside any glass page route, which draws its
  /// bar itself.
  GlassBarHost.standalone() {
    final link = _standalone = GlassPageBarLink._(this, null, null);
    _pages.add(link);
    _shown = link;
    _painter.value = link;
    _registered = true;
    MotionClock.instance.addDriver(this);
  }

  /// The bars of [navigator]'s glass pages.
  factory GlassBarHost.of(NavigatorState navigator) =>
      _hosts[navigator] ??= GlassBarHost._();

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
  GlassPageBarLink? _swiped;
  late final Map<GlassBarKind, _Bar> _bars = {
    for (final kind in GlassBarKind.values) kind: _Bar(this, kind),
  };
  bool _registered = false;
  Color? _tint;

  double get _now => MotionClock.instance.now;

  // --- the route's events -------------------------------------------------

  /// Registers [route]'s page, which moves by [presence].
  GlassPageBarLink attach(
    ModalRoute<Object?> route, {
    required ValueListenable<double> presence,
  }) {
    final link = GlassPageBarLink._(this, route, presence);
    _pages.add(link);
    if (!_registered) {
      _registered = true;
      MotionClock.instance.addDriver(this);
    }
    return link;
  }

  /// Unregisters [link]'s page.
  void detach(GlassPageBarLink link) {
    _pages.remove(link);
    for (final page in _pages) {
      if (identical(page._below, link)) page._below = null;
    }
    if (identical(_shown, link)) _shown = null;
    if (identical(_swiped, link)) _swiped = null;
    if (identical(_painter.value, link)) {
      _painter.value = _pages.isEmpty ? null : _pages.last;
    }
    link.titleRoom.dispose();
    if (_pages.isEmpty && _registered) {
      _registered = false;
      MotionClock.instance.removeDriver(this);
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
    _shown = link;
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
    _shown = link;
    for (final bar in _bars.values) {
      bar.enqueue(_Change(link, _now, null));
    }
  }

  /// Reports that [link]'s page was popped or dismissed at [time]: the
  /// call, or the finger's lift after a swipe.
  void leaving(GlassPageBarLink link, {required double time}) {
    if (!identical(link, _shown)) return;
    final below = link._below;
    _shown = below;
    _swiped = null;
    for (final bar in _bars.values) {
      bar.enqueue(_Change(below, time, bar.navigationSpec));
    }
  }

  /// Reports that [link]'s page left the overlay: the next glass page down
  /// takes the bar view.
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
    _swiped = link;
    _bars[GlassBarKind.navigation]!.rebuild();
    MotionClock.instance.wake(this);
  }

  /// Reports that the finger's drag of [link]'s page ended.
  void swipeEnded(GlassPageBarLink link) {
    if (!identical(_swiped, link)) return;
    _swiped = null;
    _bars[GlassBarKind.navigation]!.motion.endDrift(_now);
    MotionClock.instance.wake(this);
  }

  // --- the page's declarations --------------------------------------------

  /// Records what [link]'s page declares for its navigation bar as it
  /// builds; a declaration that changes only callbacks moves nothing.
  void declare(GlassPageBarLink link, GlassBarDeclaration declaration) {
    final previous = link._declaration;
    link._declaration = declaration;
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
  void declareToolbar(GlassPageBarLink link, List<GlassBarEntry>? items) {
    final previous = link._toolbar;
    link._toolbar = items;
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
      // A page that shows without a push, standalone: its bar stands.
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

  // --- MotionDriver -------------------------------------------------------

  @override
  bool get isActive =>
      _swiped != null || _bars.values.any((bar) => !bar.motion.isSettled);

  @override
  double? get wakeTime => null;

  @override
  void step(double time) {
    final swiped = _swiped;
    final presence = swiped?._presence;
    for (final bar in _bars.values) {
      final motion = bar.motion;
      motion.advance(time);
      if (bar.kind == GlassBarKind.navigation &&
          swiped != null &&
          presence != null) {
        motion.setDrift(
          swiped._below?._layouts[bar.kind],
          NavigationTuning.barDrift * (1 - presence.value).clamp(0.0, 1.0),
        );
      }
      if ((swiped == null || bar.kind == GlassBarKind.toolbar) &&
          motion.isSettled) {
        motion.settle();
      }
      bar.publish();
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
  _RenderBarItems? items;

  bool get _navigation => kind == GlassBarKind.navigation;

  GlassBarMetrics get metrics =>
      _navigation ? GlassBarMetrics.navigation : GlassBarMetrics.toolbar;

  /// The space between the screen's sides and the outer capsules: 16 for a
  /// navigation bar on a 402 point screen, 28 for a toolbar (bars
  /// passport).
  double get sideInset => _navigation ? 16 : 28;

  /// The tuning of a change on a push or a pop: a navigation bar's own
  /// timing; a toolbar's item replacement, as Morph's toolbar ran it (a
  /// toolbar's push was filmed on the simulator only).
  GlassBarTransitionSpec get navigationSpec => _navigation
      ? GlassBarTransitionSpec.navigation
      : GlassBarTransitionSpec.standard;

  void enqueue(_Change change) {
    changes.add(change);
    rebuild();
    MotionClock.instance.wake(host);
  }

  void rebuild() {
    final view = this.view;
    if (view == null || !view.mounted) return;
    var inLayout = false;
    assert(() {
      inLayout = view.renderObject?.owner?.debugDoingLayout ?? false;
      return true;
    }(), 'reads the layout phase in debug builds only');
    if (inLayout) {
      // A page built during another layout (under the app's LayoutBuilder)
      // reaches the bar a frame later.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (view.mounted) view.markNeedsBuild();
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    view.markNeedsBuild();
  }

  /// The runs of [page]'s bar, each a list of capsules with the identities
  /// of their buttons: a navigation bar's leading and trailing sides, a
  /// toolbar's runs between flexible spaces. Identities repeat across the
  /// whole bar.
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
    final label = switch (declaration.backButtonDisplayMode) {
      GlassBackButtonDisplayMode.minimal => null,
      GlassBackButtonDisplayMode.generic => 'Back',
      GlassBackButtonDisplayMode.title =>
        declaration.previousPageTitle ?? below._declaration?.title ?? 'Back',
    };
    return [
      [
        (
          _backId,
          _Button.back(
            _Back(
              label: label,
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
      final capsules = [for (final run in runs) ...run];
      for (var i = 0; i < layout.length && i < capsules.length; i++) {
        final first = capsules[i].first.$2.item;
        if (first != null && first.prominent) prominent.add(layout[i].id);
      }
      if (_navigation) {
        final room = _roomOf(layout);
        if (page.titleRoom.value != room) rooms.add((page, room));
      }
    }
    if (rooms.isNotEmpty) {
      // The titles are laid out in their pages, which this layout must
      // not touch: they take their room after the frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final (page, room) in rooms) {
          if (host._pages.contains(page)) page.titleRoom.value = room;
        }
      });
    }
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
        ], prominent: capsule.first.$2.item?.prominent ?? false),
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
    if (back.label == null) return 0;
    return math.max(
      0,
      built -
          metrics.backChevronInset -
          metrics.backChevronWidth -
          metrics.backChevronGap -
          metrics.backTrailingPadding,
    );
  }

  GlassTitleRoom _roomOf(List<GlassBarCapsuleLayout> layout) {
    const padding = 12.0;
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
        pool[i].value = GlassFrame(
          rect: frame.rect,
          opacity: frame.opacity,
          tint: prominent.contains(frame.id) ? host._tint : null,
        );
      }
    }

    write(container, joined);
    write(apart, apartFrames);
    itemFrames.clear();
    for (final frame in motion.items) {
      itemFrames[frame.id] = frame;
    }
    items?.markNeedsPaint();
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

  @override
  void initState() {
    super.initState();
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final host = link.host;
    return _LinkScope(
      link: link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => ValueListenableBuilder(
          valueListenable: host.painter,
          builder: (context, painter, _) => identical(painter, link)
              ? KeyedSubtree(
                  key: host.viewKey,
                  child: GlassBarView(host: host),
                )
              : const SizedBox.shrink(),
        ),
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
/// Each bar builds during its own layout, as [LayoutBuilder] does, so a
/// page that declares while it builds reaches it in the same frame.
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
    host._bars.values.first.motion.reducedMotion = GlassTraits.of(
      context,
    ).reduceMotion;
    host._bars.values.last.motion.reducedMotion = GlassTraits.of(
      context,
    ).reduceMotion;
    host._tint = GlassDynamicColor.resolve(
      GlassTheme.of(context).primaryColor ?? _prominentColor,
      context,
    );
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
          height: _navigationHeight,
          child: _Band(bar: host._bars[GlassBarKind.navigation]!),
        ),
        Positioned(
          bottom: keyboard > 0 ? keyboard + _keyboardInset : _bottomInset,
          left: 0,
          right: 0,
          height: GlassBarMetrics.toolbar.capsuleHeight,
          child: _Band(bar: host._bars[GlassBarKind.toolbar]!),
        ),
      ],
    );
  }

  static const double _navigationHeight = 54;

  /// The space between the screen's bottom and a toolbar's capsules
  /// (`_UIToolbarPaddingSpec` phoneBottom, read from UIKit).
  static const double _bottomInset = 28;

  /// The space between a keyboard and a toolbar's capsules (phoneKeyboard).
  static const double _keyboardInset = 8;

  /// The prominent capsule's tint without a primary color (device).
  static const _prominentColor = Color(0xFF0088FF);
}

// One bar's row: its glass and its buttons, rebuilt during its layout.
class _Band extends StatelessWidget {
  const _Band({required this.bar});

  final _Bar bar;

  /// The spacing of the glass container a bar's capsules share (bars
  /// passport: 12, constant through item changes).
  static const double _containerSpacing = 12;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      bar.view = context as Element;
      final roster = bar.roster();
      while (bar.container.length < roster.length + 2) {
        bar.container.add(
          ValueNotifier(const GlassFrame(rect: Rect.zero, opacity: 0)),
        );
      }
      while (bar.apart.length < roster.length + 2) {
        bar.apart.add(
          ValueNotifier(const GlassFrame(rect: Rect.zero, opacity: 0)),
        );
      }
      return RepaintBoundary(
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            _Surfaces(
              frames: bar.container,
              merge: const GlassMerge.spacing(_containerSpacing),
            ),
            _Surfaces(frames: bar.apart, merge: const GlassMerge.none()),
            _BarItems(
              bar: bar,
              children: [
                for (final MapEntry(key: id, value: button) in roster.entries)
                  _BarItem(
                    key: ValueKey(id),
                    id: id,
                    button: button,
                    metrics: bar.metrics,
                  ),
              ],
            ),
          ],
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
            GlassSurface.live(frame: frame, child: const SizedBox.expand()),
        ],
      ),
    ),
  );
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.id,
    required this.button,
    required this.metrics,
    super.key,
  });

  final Object id;
  final _Button button;
  final GlassBarMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final label = GlassDynamicColor.resolve(
      theme.colorScheme?.label ?? GlassColors.label,
      context,
    );
    final back = button.back;
    final item = button.item;
    final enabled =
        back != null || item?.onPressed != null || item?.child != null;
    final prominent = item?.prominent ?? false;
    final color = prominent
        ? const Color(0xFFFFFFFF)
        : enabled
        ? label
        : GlassDynamicColor.resolve(GlassColors.tertiaryLabel, context);
    final text = resolveGlassText(
      TextStyle(
        fontSize: 17,
        fontWeight: prominent ? FontWeight.w600 : FontWeight.w500,
        height: 1.2,
        color: color,
      ),
      context,
    );
    final Widget content;
    final String? semantics;
    final VoidCallback? onTap;
    if (back != null) {
      const metrics = GlassBarMetrics.navigation;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      content = Row(
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
          if (back.label case final title?) ...[
            SizedBox(width: metrics.backChevronGap),
            Text(title, style: text, maxLines: 1),
            SizedBox(width: metrics.backTrailingPadding),
          ] else
            SizedBox(width: metrics.backChevronInset),
        ],
      );
      semantics = back.label ?? 'Back';
      onTap = back.onPressed;
    } else {
      final it = item!;
      content =
          it.child ??
          IconTheme.merge(
            data: IconThemeData(size: metrics.iconSize, color: color),
            child: DefaultTextStyle(
              style: text,
              maxLines: 1,
              child: it.icon ?? it.label!,
            ),
          );
      semantics = it.semanticLabel;
      onTap = it.onPressed;
    }
    if (item?.child != null) return _ItemBox(id: id, child: content);
    return _ItemBox(
      id: id,
      child: Semantics(
        container: true,
        button: true,
        enabled: onTap != null,
        label: semantics,
        excludeSemantics: back != null,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }

  static const double _chevronHeight = 23;
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
  const _BarItems({required this.bar, required super.children});

  final _Bar bar;

  @override
  _RenderBarItems createRenderObject(BuildContext context) => _RenderBarItems(
    bar,
    rtl: Directionality.of(context) == TextDirection.rtl,
  );

  // The bar rebuilds only for a change, which its layout applies.
  @override
  void updateRenderObject(BuildContext context, _RenderBarItems renderObject) {
    renderObject.rtl = Directionality.of(context) == TextDirection.rtl;
    renderObject.markNeedsLayout();
  }
}

class _ItemData extends ContainerBoxParentData<RenderBox> {}

/// Lays the bar's buttons out to measure them, hands the widths to the
/// host, and paints each where the host's motion puts it: moved, scaled,
/// faded and blurred, without a layout per frame. Only resting buttons of
/// the shown page take touches, anywhere in their laid-out box.
class _RenderBarItems extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ItemData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ItemData> {
  _RenderBarItems(this.bar, {required this._rtl});

  final _Bar bar;

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsLayout();
  }

  final Map<RenderBox, LayerHandle<ContainerLayer>> _layers = {};

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ItemData) child.parentData = _ItemData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    bar.items = this;
  }

  @override
  void detach() {
    if (identical(bar.items, this)) bar.items = null;
    super.detach();
  }

  @override
  void dispose() {
    for (final handle in _layers.values) {
      handle.layer = null;
    }
    super.dispose();
  }

  Object? _idOf(RenderBox child) => child is _RenderItemBox ? child.id : null;

  @override
  void performLayout() {
    size = constraints.biggest;
    final widths = <Object, double>{};
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints(maxHeight: size.height),
        parentUsesSize: true,
      );
      final id = _idOf(child);
      if (id != null) widths[id] = child.size.width;
      child = childAfter(child);
    }
    bar.measured(widths, size.width, rtl: _rtl);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final id = _idOf(child);
    final frame = id == null ? null : bar.itemFrames[id];
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
      final id = _idOf(child);
      final frame = id == null ? null : bar.itemFrames[id];
      if (frame != null && !frame.leaving && frame.presence > 0.5) {
        final box = Rect.fromCenter(
          center: frame.center,
          width: math.max(frame.size.width, child.size.width),
          height: bar.metrics.capsuleHeight,
        );
        if (box.contains(position)) {
          final origin = frame.center - child.size.center(Offset.zero);
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

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final id = _idOf(child);
      final frame = id == null ? null : bar.itemFrames[id];
      final handle = _layers.putIfAbsent(child, LayerHandle.new);
      if (frame == null || frame.presence <= 0 || frame.scale <= 0) {
        handle.layer = null;
        child = childAfter(child);
        continue;
      }
      final box = child;
      final origin = offset + frame.center - box.size.center(Offset.zero);
      final transform = Matrix4.identity();
      if (frame.scale != 1) {
        final c = frame.center + offset;
        transform.translateByDouble(c.dx, c.dy, 0, 1);
        transform.scaleByDouble(frame.scale, frame.scale, 1, 1);
        transform.translateByDouble(-c.dx, -c.dy, 0, 1);
      }
      handle.layer = context.pushTransform(
        needsCompositing,
        Offset.zero,
        transform,
        (context, _) {
          void draw(PaintingContext context, Offset at) =>
              context.paintChild(box, at);
          void blurred(PaintingContext context, Offset at) {
            if (frame.blur <= 0.05) {
              draw(context, at);
              return;
            }
            context.pushLayer(
              ImageFilterLayer(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: frame.blur / 2,
                  sigmaY: frame.blur / 2,
                ),
              ),
              draw,
              at,
            );
          }

          if (frame.presence >= 1) {
            blurred(context, origin);
          } else {
            context.pushOpacity(
              origin,
              (frame.presence * 255).round(),
              blurred,
            );
          }
        },
        oldLayer: handle.layer is TransformLayer
            ? handle.layer! as TransformLayer
            : null,
      );
      child = childAfter(child);
    }
  }

  @override
  bool get alwaysNeedsCompositing => true;
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

// A button of the bar, which knows its identity.
class _RenderItemBox extends RenderProxyBox {
  _RenderItemBox(this.id);

  Object id;
}
