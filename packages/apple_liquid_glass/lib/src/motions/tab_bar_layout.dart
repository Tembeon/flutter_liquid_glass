import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:meta/meta.dart';

/// What a tab bar hosts beside its tabs, which decides how wide it lays
/// out and where it stands in a wider box.
enum TabBarHost {
  /// Nothing: up to three tabs take only the width they need, centered.
  none,

  /// A bottom accessory: the bar spans the width it is given.
  accessory,

  /// A circle at the trailing end, a search tab's or an action's: two tabs
  /// keep their own width (188 points), three and more span the room (290
  /// points on a 402 point screen), and the bar starts at the leading side
  /// (search tab bar passport, iOS 27.2 simulator).
  circle,
}

/// The numbers a floating tab bar lays itself out by: a phone's [compact]
/// bar or the [wide] one, read from UIKit's layout records of iOS 27 (notes
/// private) and checked against the iOS 27.2 simulator (tab bar and tab bar
/// minimize passports).
///
/// UIKit lays the bar out wide where the window is regular across, or
/// compact up and down with the bar at least [wideFrom] wide: an iPhone in
/// landscape. This package also gives the wide bar to a tablet or desktop
/// window where a tab sidebar does not stand beside the content, where
/// UIKit puts a bar of the tabs at the top.
enum TabBarMetrics {
  /// A phone's bar: 62 points tall, the title under the glyph, 21 points
  /// from the window's sides and bottom.
  compact(
    height: 62,
    bottomInset: 21,
    sideInset: 21,
    titlesBeside: false,
    glyphSize: 24,
    glyphCenter: 24,
    slotInset: 24,
    crowdedSlotInset: 15,
    gap: 32,
    fillAdjustment: 12,
    sizesToContent: false,
    hostedMaximum: null,
    unboundWidth: 360,
    circleSize: 62,
    minimizedSize: 48,
    minimizedInset: 7,
    inlineAccessoryHeight: 48,
  ),

  /// The wide bar: 44 points tall, the title beside the glyph, the bar as
  /// wide as its tabs at the middle, 20 points above the window's bottom
  /// and at least 38 from its sides; hosting a circle or an accessory, the
  /// group is at most 640 wide and its tabs share the bar.
  wide(
    height: 44,
    bottomInset: 20,
    sideInset: 38,
    titlesBeside: true,
    glyphSize: 20,
    glyphCenter: 22,
    slotInset: 10,
    crowdedSlotInset: 10,
    gap: 16,
    fillAdjustment: 0,
    sizesToContent: true,
    hostedMaximum: 640,
    unboundWidth: 640,
    circleSize: 44,
    minimizedSize: 44,
    minimizedInset: 0,
    inlineAccessoryHeight: 44,
  );

  const TabBarMetrics({
    required this.height,
    required this.bottomInset,
    required this.sideInset,
    required this.titlesBeside,
    required this.glyphSize,
    required this.glyphCenter,
    required this.slotInset,
    required this.crowdedSlotInset,
    required this.gap,
    required this.fillAdjustment,
    required this.sizesToContent,
    required this.hostedMaximum,
    required this.unboundWidth,
    required this.circleSize,
    required this.minimizedSize,
    required this.minimizedInset,
    required this.inlineAccessoryHeight,
  });

  /// The metrics of a bar [width] wide in [environment].
  static TabBarMetrics of(GlassEnvironment environment, double width) =>
      environment.isRegularWidth ||
          (!environment.isRegularHeight && width >= wideFrom)
      ? wide
      : compact;

  /// The width from which a bar compact up and down lays out wide.
  static const double wideFrom = 568;

  /// The bar's height, whatever its titles.
  final double height;

  /// The space between the bar and the window's bottom.
  final double bottomInset;

  /// The least space between the bar group and the window's sides.
  final double sideInset;

  /// Whether a tab's title stands beside its glyph rather than under it.
  final bool titlesBeside;

  /// The size of a tab's glyph: 24 under the title, 20 beside it (the
  /// simulator's wide rows centre a glyph 20 wide; tab bar passport).
  final double glyphSize;

  /// The height of a tab's glyph center in the bar: 24 points under the
  /// title, read from UIKit; the bar's middle beside it.
  final double glyphCenter;

  /// The space between the bar's edge and its first tab's slot.
  final double slotInset;

  /// [slotInset] for a bar of more than four tabs.
  final double crowdedSlotInset;

  /// The space between two tabs' slots where the tabs do not share the bar.
  final double gap;

  /// What a tab claims past its content where the tabs share the bar.
  final double fillAdjustment;

  /// Whether a bar that hosts nothing is as wide as its tabs' content.
  final bool sizesToContent;

  /// The widest a bar group hosting an accessory or a circle goes, or null
  /// for no limit.
  final double? hostedMaximum;

  /// The width of a bar without a bound: an iPhone's 402 points less 21 at
  /// each side, or a hosted wide group's limit.
  final double unboundWidth;

  /// The diameter of a search tab's or an action's circle beside the bar.
  final double circleSize;

  /// The diameter of the circle the minimized bar becomes.
  final double minimizedSize;

  /// The space between the minimized circle and the expanded bar's leading
  /// and bottom edges.
  final double minimizedInset;

  /// The height of the accessory beside the minimized bar.
  final double inlineAccessoryHeight;

  /// The height of a tab's button, and of the resting lens on it.
  double get buttonHeight => height - 2 * TabBarLayout.buttonInset;

  /// The widest a bar hosting [host] goes, or null for no limit: a hosted
  /// group's limit, less the circle and its gap beside a circle.
  double? barMaximum(TabBarHost host) => switch ((hostedMaximum, host)) {
    (null, _) || (_, TabBarHost.none) => null,
    (final group?, TabBarHost.accessory) => group,
    (final group?, TabBarHost.circle) =>
      group - TabBarLayout.circleGap - circleSize,
  };
}

/// How a floating tab bar sizes itself and its tabs, read from UIKit (iOS
/// 27; notes private) and checked against the bars of an iPhone 16 Pro with
/// 2 to 5 tabs and short, Russian and very long titles, and against the
/// wide bars of the iOS 27.2 simulator in landscape.
///
/// A [TabBarMetrics.compact] bar of four or more tabs, or one that hosts a
/// bottom accessory or a trailing circle, spans what is available whatever
/// its titles say, and its tabs adapt inside it. A bar of two or three tabs
/// is as wide as its widest title asks. A [TabBarMetrics.wide] bar is as
/// wide as its tabs' content, each tab as wide as its own, unless it hosts
/// an accessory or a circle, where its tabs share the bar up to the hosted
/// limit. Height never depends on the titles.
@immutable
final class TabBarLayout {
  const TabBarLayout._({required this.width, required this.buttons});

  /// Lays out tabs whose content is [naturals] wide in [available] points
  /// for a bar hosting [host], by [metrics].
  ///
  /// A wide bar whose tabs' content does not fit [available] shares it as a
  /// hosting bar does, the widest tabs giving room back first: this
  /// package's rule, UIKit's is not read.
  factory TabBarLayout.of(
    List<double> naturals, {
    required double available,
    TabBarHost host = TabBarHost.none,
    TabBarMetrics metrics = TabBarMetrics.compact,
  }) {
    final count = naturals.length;
    if (count == 0) return const TabBarLayout._(width: 0, buttons: []);
    if (metrics.sizesToContent && host == TabBarHost.none) {
      final sized = _sizedToContent(naturals, available, metrics);
      if (sized != null) return sized;
      return TabBarLayout._shared(naturals, available, metrics, fills: true);
    }
    final fills = switch (host) {
      TabBarHost.none => count > 3,
      TabBarHost.accessory => true,
      TabBarHost.circle => count > 2 || metrics.sizesToContent,
    };
    return TabBarLayout._shared(
      naturals,
      math.min(available, metrics.barMaximum(host) ?? double.infinity),
      metrics,
      fills: fills,
    );
  }

  factory TabBarLayout._shared(
    List<double> naturals,
    double available,
    TabBarMetrics metrics, {
    required bool fills,
  }) {
    final count = naturals.length;
    var inset = count > 4 ? metrics.crowdedSlotInset : metrics.slotInset;
    final ideals = [
      for (final natural in naturals)
        math.max(minimumItem, natural + (fills ? metrics.fillAdjustment : 0)),
    ];
    final widest = ideals.reduce(math.max);
    final total = ideals.reduce((a, b) => a + b);
    final double width;
    if (fills) {
      width = available;
    } else {
      final asked =
          2 * inset +
          (count - 1) * metrics.gap +
          count * math.max(minimumItem, naturals.reduce(math.max));
      width = math.min(available, asked);
    }
    final room = width - 2 * inset;
    final even = (room - (count - 1) * (fills ? 2 : metrics.gap)) / count;
    final fitted = math.min(math.min(widest, room), even);
    List<double> uniform(double item) => List.filled(count, item);
    List<double> unequal() {
      final inner = width - 2 * inset;
      if (total >= inner) return ideals;
      return [for (final ideal in ideals) ideal * inner / total];
    }

    List<double> items;
    if (!fills) {
      items = uniform(fitted);
    } else if ((room - total) / (count - 1) < 14) {
      inset = math.min(inset, 14);
      items = unequal();
    } else if (widest <= minimumItem) {
      items = uniform(math.max(fitted, room / count - (inset - buttonInset)));
    } else {
      inset = math.min(inset, 18);
      items = widest <= even
          ? uniform(
              math.max(
                fitted,
                (width - 2 * inset) / count - (inset - buttonInset),
              ),
            )
          : unequal();
    }
    final inner = width - 2 * inset;
    items = _fit(items, inner);
    final used = items.reduce((a, b) => a + b);
    final gap = fills
        ? count == 1
              ? 0.0
              : (inner - used) / (count - 1)
        : metrics.gap;
    final outset = inset - buttonInset;
    final buttons = <({double center, double width})>[];
    var left = inset;
    for (final item in items) {
      buttons.add((center: left + item / 2, width: item + 2 * outset));
      left += item + gap;
    }
    return TabBarLayout._(width: width, buttons: buttons);
  }

  static TabBarLayout? _sizedToContent(
    List<double> naturals,
    double available,
    TabBarMetrics metrics,
  ) {
    final inset = metrics.slotInset;
    final slots = [
      for (final natural in naturals) math.max(minimumItem, natural),
    ];
    final width =
        2 * inset +
        slots.reduce((a, b) => a + b) +
        (slots.length - 1) * metrics.gap;
    if (width > available) return null;
    final outset = inset - buttonInset;
    final buttons = <({double center, double width})>[];
    var left = inset;
    for (final slot in slots) {
      buttons.add((center: left + slot / 2, width: slot + 2 * outset));
      left += slot + metrics.gap;
    }
    return TabBarLayout._(width: width, buttons: buttons);
  }

  // Tabs past the room give it back, the widest over the minimum first.
  static List<double> _fit(List<double> items, double room) {
    final fitted = List.of(items);
    var excess = fitted.reduce((a, b) => a + b) - room;
    while (excess > 1e-9) {
      final over = [
        for (final (i, item) in fitted.indexed)
          if (item > minimumItem) i,
      ];
      if (over.isEmpty) {
        final each = excess / fitted.length;
        return [for (final item in fitted) item - each];
      }
      final top = over.map((i) => fitted[i]).reduce(math.max);
      final widest = over.where((i) => fitted[i] >= top - 1e-9).toList();
      final next = over
          .map((i) => fitted[i])
          .where((item) => item < top - 1e-9)
          .fold(minimumItem, math.max);
      final take = math.min(top - next, excess / widest.length);
      for (final i in widest) {
        fitted[i] -= take;
      }
      excess -= take * widest.length;
    }
    return fitted;
  }

  /// The least width of a tab's content: UIKit's minimum item dimension.
  static const double minimumItem = 54;

  /// The space between a tab's button and the bar's edge.
  static const double buttonInset = 4;

  /// The space between a bar and the circle it hosts (search tab bar
  /// passport, iOS 27.2 simulator).
  static const double circleGap = 8;

  /// How much narrower than its button a title has to be: the button's
  /// rounded shape leaves it 21.72 points, read from UIKit.
  static const double titleMargin = 21.72;

  /// The bar's width.
  final double width;

  /// Each tab's button along the bar: UIKit's buttons, and the lens that
  /// rests on them, overlap their neighbours.
  final List<({double center, double width})> buttons;
}
