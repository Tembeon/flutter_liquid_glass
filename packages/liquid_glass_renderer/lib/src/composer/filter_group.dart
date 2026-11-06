part of 'backdrop_underlay.dart';

/// What a layer offers the frame's plan: to be drawn through one filter with
/// other layers, which costs the frame one offscreen pass where each alone
/// costs one, and one copy where each alone asks for one.
///
/// Every offer stands for a layer that drew from a copy in the frame last
/// time, or would. An offer the plan leaves alone asks for its own copy
/// ([askAlone]); one it groups hears of its group ([enter]).
@internal
abstract class FilterOffer {
  /// Creates the offer.
  FilterOffer({
    required this.anchor,
    required this.underlay,
    required this.devicePixelRatio,
    required this.drawn,
    required this.reads,
    required this.downscale,
    this.own,
  });

  /// The layer the offer begins with in paint order.
  final Layer anchor;

  /// The layer holding everything the offer paints with its glass.
  final OpacitySeedLayer? own;

  /// The copy of what lies under the offer, when it leads a group or is alone.
  final BackdropUnderlay underlay;

  /// The screen's device pixels per logical pixel.
  final double devicePixelRatio;

  /// What the offer paints, in the screen's logical pixels.
  final Rect drawn;

  /// What the offer reads, in the screen's logical pixels.
  final Rect reads;

  /// How many device pixels along each side one pixel of its copy can stand
  /// for.
  final int downscale;

  /// Asks for this offer's own copy.
  void askAlone();

  /// Tells the offer's layer it belongs to [group] this frame.
  void enter(FilterGroup group);
}

/// A scroll edge's frost, which glass over it can draw in its own filter.
///
/// NEAR, against the band in a filter of its own under the glass: the glass's
/// antialiased rim blends over one read of the copy rather than the band's
/// frost; the glass reads the band's fade as one color over its backdrop
/// rather than the fade's rows; and the frost and the color change of the band
/// stay out of what the glass reads, as they do without a group
/// ([BackdropUnderlay.debugDropsFrost]).
@internal
abstract class BandOffer extends FilterOffer {
  /// Creates the offer.
  BandOffer({
    required super.anchor,
    required super.underlay,
    required super.devicePixelRatio,
    required super.drawn,
    required super.reads,
    required super.downscale,
    required this.sigma,
    required this.origin,
    required this.paint,
  });

  /// The frost, in logical pixels.
  final double sigma;

  /// Where the band's layer lies on the screen.
  final Offset origin;

  /// What the band paints over its frost.
  final FrostBandPaint paint;
}

/// Glass, which can draw itself and the others of its group in one filter.
@internal
abstract class GlassOffer extends FilterOffer {
  /// Creates the offer.
  GlassOffer({
    required super.anchor,
    required super.underlay,
    required super.devicePixelRatio,
    required super.drawn,
    required super.reads,
    required super.downscale,
    required super.own,
    required this.key,
    required this.frost,
    required this.drawsBand,
  });

  /// Equal for glass one shader's uniforms can draw.
  final Object key;

  /// The frost the glass reads with, in logical pixels.
  final double frost;

  /// Whether the glass's shader can draw a band.
  final bool drawsBand;

  /// Gets the shader ready to draw [group], or returns false when it cannot.
  bool begin(FilterGroup group);

  /// The filter that draws [group] over [read].
  ui.ImageFilter filter(FilterGroup group, CornerRead read);
}

/// Layers of one frame drawn through one filter over one copy.
///
/// The first in paint order leads: its layer draws the filter and the others
/// draw nothing of their glass, so the glass of all moves back in paint order
/// to the leader's. [settle] checks at compositing that nothing is painted
/// where that shows.
@internal
final class FilterGroup {
  FilterGroup._(this.band, GlassOffer first) : _offered = [first];

  /// The scroll edge drawn with the glass, if there is one.
  final BandOffer? band;

  final List<GlassOffer> _offered;
  List<GlassOffer> _kept = const [];

  // How much of a screen of dead pixels one filter less is worth. The filter
  // spends GPU time on every pixel of a layer that holds all its members: on
  // the Pixel 6a a whole-screen layer costs 0.5 ms more than three apart, 0.6
  // ms less than twelve apart (tool/audit/2026-11-05-one-pass/results.md).
  static const double _deadPerFilter = 0.4;

  /// The glass the filter draws, in paint order, once [settle] returned a copy.
  List<GlassOffer> get glass => _kept;

  /// The glass whose shader draws the filter.
  GlassOffer get painter => _kept.first;

  /// The layer that draws the filter.
  FilterOffer get lead => band ?? _offered.first;

  /// What the offers read, in the screen's logical pixels.
  Rect get reads {
    var rect = band?.reads ?? _offered.first.reads;
    for (final offer in _offered) {
      rect = rect.expandToInclude(offer.reads);
    }
    return rect;
  }

  /// What the filter paints, in the screen's logical pixels.
  Rect get drawn {
    var rect = band?.drawn ?? _kept.first.drawn;
    for (final offer in _kept) {
      rect = rect.expandToInclude(offer.drawn);
    }
    return rect;
  }

  /// Whether [offer] draws in this group's filter this frame.
  bool holds(FilterOffer offer) =>
      _kept.isNotEmpty && (identical(offer, band) || _kept.contains(offer));

  /// The hard edge around members far apart, in the screen's device pixels,
  /// or null where they fill most of [layer], the filter's layer on the
  /// screen: it rejects the pixels of the layer no member paints, which saved
  /// 0.6 ms of GPU time over twelve buttons on the Pixel 6a.
  ///
  /// A pixel at two corners keeps the edge's bounds at the layer's: Impeller
  /// cuts a layer a clip cuts by 30 % or more, and the fragment coordinates
  /// the glass reads start at the cut (see [BackdropUnderlay.keepsWhole]).
  ui.Path? clipIn(Rect layer) {
    if (band != null || _kept.length < 2) return null;
    if (_area(drawn) <= _areaOf(_kept) * 1.3) return null;
    final dpr = lead.devicePixelRatio;
    final path = ui.Path();
    void add(Rect rect) => path.addRect(
      Rect.fromLTRB(
        rect.left * dpr,
        rect.top * dpr,
        rect.right * dpr,
        rect.bottom * dpr,
      ),
    );
    for (final offer in _kept) {
      add(offer.drawn.inflate(2 / dpr));
    }
    add(layer.topLeft & Size.square(1 / dpr));
    add(
      Rect.fromPoints(
        layer.bottomRight - Offset(1 / dpr, 1 / dpr),
        layer.bottomRight,
      ),
    );
    return path;
  }

  static double _area(Rect rect) => rect.width * rect.height;

  static double _areaOf(List<FilterOffer> offers) {
    var sum = 0.0;
    for (final offer in offers) {
      sum += _area(offer.drawn);
    }
    return sum;
  }

  bool _admits(GlassOffer offer, double screen) {
    if (offer.key != _offered.first.key) return false;
    var all = offer.drawn;
    for (final other in _offered) {
      if (_meets(other.drawn, offer.drawn)) return false;
      all = all.expandToInclude(other.drawn);
    }
    final dead = _area(all) - _areaOf(_offered) - _area(offer.drawn);
    return dead <= screen * _deadPerFilter * _offered.length;
  }

  void _ask() {
    _request();
    band?.enter(this);
    for (final offer in _offered) {
      offer.enter(this);
    }
  }

  void _request() {
    final lead = this.lead;
    final band = this.band;
    var downscale = lead.downscale;
    for (final offer in _offered) {
      downscale = min(downscale, offer.downscale);
    }
    lead.underlay.request(
      anchor: lead.anchor,
      own: lead.own,
      devicePixelRatio: lead.devicePixelRatio,
      region: reads,
      downscale: downscale,
      frost: band == null ? _offered.first.frost : 0,
      parts: [?band?.reads, for (final offer in _offered) offer.reads],
      bodies: [?band?.drawn, for (final offer in _offered) offer.drawn],
    );
  }

  /// Decides at the leader's compositing who stays, and draws the copy of
  /// what lies before the leader: null when the group came apart. Who leaves
  /// forms groups of its own, as controls in the next card do, and a member
  /// without one asks alone.
  ///
  /// A member stays when it lies under the leader's clips and opacity and
  /// nothing but the group's glass is painted under it between the leader and
  /// itself. NEAR: glass does not show what is painted beside it after the
  /// leader in what it reads at its rim, such as a neighbour's label or
  /// shadow, as glass drawn over one copy never does.
  InFrameCopy? settle() {
    final underlay = lead.underlay;
    var ask = underlay._ask;
    if (ask == null || ask.band.isEmpty) return null;
    final scan = BackdropUnderlay._scanOf(ask);
    final limit = scan.reach(ask.anchor);
    if (limit < 0) return null;
    final clip = scan.clip;
    final state = scan._cursors.last.state;
    final mark = scan._mark();
    final starts = <int>{limit};
    final owned = <Layer>{?lead.own};
    final kept = <GlassOffer>[];
    for (final offer in _offered) {
      if (identical(offer, lead)) {
        kept.add(offer);
        continue;
      }
      final at = scan.reach(offer.anchor);
      if (at >= 0 &&
          listEquals(scan._cursors.last.state, state) &&
          scan.onlyIslandBetween(
            limit,
            at,
            offer.reads,
            offer.drawn,
            starts: starts,
            owned: owned,
          )) {
        kept.add(offer);
        starts.add(at);
        if (offer.own case final own?) owned.add(own);
      }
    }
    scan._rewind(mark);
    if (kept.length < _offered.length) {
      final left = [
        for (final offer in _offered)
          if (!kept.contains(offer)) offer,
      ];
      final screen = ask.screen.size;
      for (final group in _openGroups(left, screen.width * screen.height)) {
        group._ask();
      }
    }
    if (kept.isEmpty || band == null && kept.length < 2) return null;
    if (kept.length < _offered.length) {
      _offered.retainWhere(kept.contains);
      _request();
      ask = underlay._ask!;
    }
    _kept = kept;
    if (!painter.begin(this)) {
      _kept = const [];
      return null;
    }
    underlay._ask = null;
    underlay._plan = null;
    final copy = underlay._drawInFrame(ask, scan, limit, clip);
    if (copy == null) _kept = const [];
    return copy;
  }
}

// The groups of a frame's offers: a band with the glass over it, then the
// other glass of equal looks that does not overlap, while the dead pixels
// between them are worth it.
List<FilterGroup> _groupsOf(List<FilterOffer> offers, double screen) {
  final groups = <FilterGroup>[];
  final grouped = Set<FilterOffer>.identity();
  if (BackdropUnderlay.debugBandGroups) {
    for (final (i, offer) in offers.indexed) {
      if (offer is! BandOffer) continue;
      FilterGroup? group;
      for (final other in offers.skip(i + 1)) {
        if (other is! GlassOffer ||
            !other.drawsBand ||
            !_meets(other.drawn, offer.drawn) ||
            _frostTexels(offer, other) > _bandFrostTexels) {
          continue;
        }
        if (group == null) {
          group = FilterGroup._(offer, other);
          grouped.add(offer);
          grouped.add(other);
        } else if (group._admits(other, double.infinity)) {
          group._offered.add(other);
          grouped.add(other);
        }
      }
      if (group != null) groups.add(group);
    }
  }
  groups.addAll(
    _openGroups(
      [
        for (final offer in offers)
          if (offer is GlassOffer && !grouped.contains(offer)) offer,
      ],
      screen,
    ),
  );
  return groups;
}

// The groups of [offers] with no band: each joins the first it can.
Iterable<FilterGroup> _openGroups(List<GlassOffer> offers, double screen) {
  final open = <FilterGroup>[];
  for (final offer in offers) {
    var joined = false;
    for (final group in open) {
      if (group._admits(offer, screen)) {
        group._offered.add(offer);
        joined = true;
        break;
      }
    }
    if (!joined) open.add(FilterGroup._(null, offer));
  }
  return open.where((group) => group._offered.length >= 2);
}

// A band's frost in the pixels of a copy it shares with [glass].
double _frostTexels(BandOffer band, GlassOffer glass) {
  final share = min(band.downscale, glass.downscale);
  return shaderFrostResidual(band.sigma * band.devicePixelRatio, share: share) /
      share;
}

// How far the band shader's eight written-out taps stay smooth, in a copy's
// pixels (the Mali model counts them in parallel, unlike a loop of twelve).
const double _bandFrostTexels = 2.8;
