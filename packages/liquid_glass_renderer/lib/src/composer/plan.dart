import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/read.dart'
    show BandLook, ReadPainter;
import 'package:meta/meta.dart';

/// All [compile] needs of a frame. A form answers from a layer tree; a test
/// answers from a generated scene, ten thousand scenes in seconds.
@internal
abstract interface class Scenery {
  /// The frame's sites in paint order.
  List<SiteFacts> get sites;

  /// What changed this frame.
  DirtyLog get dirty;

  /// The screen in logical pixels, the most room an image can take.
  Rect get screen;

  /// The screen's device pixels per logical pixel.
  double get devicePixelRatio;

  /// What the content under [site] allows a read over it to be.
  ReadLimit limitUnder(SiteFacts site);

  /// What makes [limitUnder] of [site] what it is, for a person, if anything.
  String? whyLimited(SiteFacts site);

  /// The frame something meeting [band] before [order] last changed, or the
  /// frame the scenery began.
  int lastChangedUnder(int order, Rect band);
}

/// What a kind of layer lets a read over it be.
@internal
enum ReadLimit {
  /// Anything: pictures and known containers.
  none,

  /// Added to the scene again but not recorded: a texture.
  sceneOnly,

  /// Cannot be drawn twice: a platform view, a foreign backdrop filter or a
  /// layer type the composer does not know.
  liveOnly,
}

/// Order and rect of what changed this frame: old and new bounds of a changed
/// leaf, every volatile leaf and a site whose output moved.
///
/// A read over the frame is unchanged when no span before its lead meets its
/// band and no read it holds changed. Past [capacity] spans merge, which only
/// ever says more changed than did.
@internal
final class DirtyLog {
  /// Spans kept before they merge.
  static const int capacity = 16;

  final _orders = List<int>.filled(capacity, 0);
  final _rects = List<Rect>.filled(capacity, Rect.zero);
  int _count = 0;

  /// Whether nothing changed.
  bool get isEmpty => _count == 0;

  /// How many spans are kept.
  int get length => _count;

  /// Forgets the last frame.
  void clear() => _count = 0;

  /// Notes that what lies at [order] changed inside [rect].
  void add(int order, Rect rect) {
    if (rect.isEmpty) return;
    if (_count < capacity) {
      _orders[_count] = order;
      _rects[_count] = rect;
      _count++;
      return;
    }
    final last = _count - 1;
    _orders[last] = math.min(_orders[last], order);
    _rects[last] = _rects[last].expandToInclude(rect);
  }

  /// Whether a span before [before] meets [band].
  bool meets(int before, Rect band) {
    for (var i = 0; i < _count; i++) {
      if (_orders[i] >= before) continue;
      if (_rects[i].overlaps(band)) return true;
    }
    return false;
  }
}

/// Inherited alpha, filters and clips, one link per layer that adds any.
///
/// Links are shared while a layer's value holds, so siblings compare by
/// identity first.
@internal
final class StateChain {
  /// Adds [token] under [parent].
  const StateChain(this.parent, this.token);

  /// The state outside every layer.
  static const StateChain root = StateChain(null, null);

  /// The link above.
  final StateChain? parent;

  /// The value this link adds.
  final Object? token;

  /// Whether both chains hold equal values in the same order.
  bool same(StateChain other) {
    StateChain? a = this;
    StateChain? b = other;
    while (true) {
      if (identical(a, b)) return true;
      if (a == null || b == null) return false;
      if (a.token != b.token) return false;
      a = a.parent;
      b = b.parent;
    }
  }
}

/// Why a site can never share a filter.
@internal
enum NoJoin {
  /// Shaded from its shapes, with no matte a group could add it to.
  analytic,

  /// Part of a fused field, or its shapes have appearances of their own.
  field,

  /// Its glow is drawn per surface.
  glow,

  /// Its backdrop shrinks towards its own center.
  shrink,

  /// Its shadows fade with their shape, cut outside a filter drawn later.
  fadingShadows,

  /// It has no matte yet, or draws through no filter it could share.
  noMatte,

  /// Scaled, so its shapes lie in no matte the others share.
  scaled,
}

/// What a read that can only come from an image does to it, past the plain
/// copy glass frosts by itself.
@internal
final class PageFilter {
  /// Creates the filter of a page.
  const PageFilter({
    this.filter,
    this.blur,
    this.clip,
    this.blendMode = BlendMode.src,
  });

  /// A plain copy, which what reads it composites as it needs to.
  static const PageFilter none = PageFilter();

  /// A filter applied as a backdrop filter over the page.
  final ImageFilter? filter;

  /// A mirrored Gaussian blur by these sigmas in logical pixels, standing for
  /// [filter].
  final (double, double)? blur;

  /// Where [filter] applies, the whole page when null, on the screen.
  final Rect? clip;

  /// How [filter]'s output composites over the page.
  final BlendMode blendMode;

  /// What pages under one filter share.
  Object? get key => blur ?? filter;

  @override
  bool operator ==(Object other) =>
      other is PageFilter &&
      other.filter == filter &&
      other.blur == blur &&
      other.clip == clip &&
      other.blendMode == blendMode;

  @override
  int get hashCode => Object.hash(filter, blur, clip, blendMode);
}

/// What one filter's uniforms must share.
@internal
final class Look {
  /// Creates a look.
  const Look({
    required this.key,
    required this.need,
    this.drawsBand = false,
    this.tint,
    this.shapes = 1,
    this.page,
    this.anyGrid = false,
  });

  /// No look: a site that draws nothing through a filter.
  static const Look none = Look(key: null, need: CopyNeed.exact(1));

  /// Equal for glass one shader's uniforms can draw, its tint aside.
  final Object? key;

  /// What its read's copy has to be.
  final CopyNeed need;

  /// The frost a shader draws over its copy, in logical pixels.
  double get frost => need.frost;

  /// Whether this glass's shader can draw a scroll edge beside it.
  final bool drawsBand;

  /// The tint, which one filter can draw per shape, but not beside a band.
  final Object? tint;

  /// How many shapes it adds to a shared matte.
  final int shapes;

  /// What a read of this site that can only come from an image does to it,
  /// or null for glass that frosts a copy by itself.
  final PageFilter? page;

  /// Whether its shader draws it at the pixels of a coarser copy holding it,
  /// taking each fragment for as many device pixels.
  final bool anyGrid;

  @override
  bool operator ==(Object other) =>
      other is Look &&
      other.key == key &&
      other.need == need &&
      other.drawsBand == drawsBand &&
      other.tint == tint &&
      other.shapes == shapes &&
      other.page == page &&
      other.anyGrid == anyGrid;

  @override
  int get hashCode =>
      Object.hash(key, need, drawsBand, tint, shapes, page, anyGrid);
}

/// What a site asks of a frame, in the screen's logical pixels.
///
/// A site makes one each frame and the form keeps the last while they are
/// equal, so the plan's inputs from a site changed exactly when its ask did.
@internal
@immutable
final class SiteAsk {
  /// Creates the ask of a site that draws this frame.
  const SiteAsk({
    required this.drawn,
    required this.reads,
    this.look = Look.none,
    this.role,
    this.noJoin,
    this.turned = false,
    this.paints,
  }) : hidden = false;

  const SiteAsk._none()
    : drawn = Rect.zero,
      reads = Rect.zero,
      look = Look.none,
      role = null,
      noJoin = null,
      turned = false,
      paints = null,
      hidden = true;

  /// A site that draws nothing this frame.
  static const SiteAsk none = SiteAsk._none();

  /// What it paints.
  final Rect drawn;

  /// What it reads.
  final Rect reads;

  /// What its filter must share.
  final Look look;

  /// What the other sites of its read use of it, if they can use any.
  final SiteRole? role;

  /// What keeps it out of every group, if anything does.
  final NoJoin? noJoin;

  /// Whether a read of it must stay live: it is turned or skewed.
  final bool turned;

  /// Equal while what it paints is the same in place: what a read over it
  /// holds of it.
  final Object? paints;

  /// Whether it draws nothing this frame.
  final bool hidden;

  @override
  bool operator ==(Object other) =>
      other is SiteAsk &&
      other.drawn == drawn &&
      other.reads == reads &&
      other.look == look &&
      other.role == role &&
      other.noJoin == noJoin &&
      other.turned == turned &&
      other.paints == paints &&
      other.hidden == hidden;

  @override
  int get hashCode =>
      Object.hash(drawn, reads, look, role, noJoin, turned, paints, hidden);
}

/// What the other sites of a read use of one of them.
@internal
@immutable
sealed class SiteRole {
  const SiteRole();
}

/// Glass, which draws the read it is the first glass of, with every site the
/// read holds.
@internal
final class GlassRole extends SiteRole {
  /// Creates the role of [painter].
  const GlassRole(this.painter);

  /// What draws the read.
  final ReadPainter painter;
}

/// A scroll edge that the glass over it can draw in its own filter.
@internal
final class BandRole extends SiteRole {
  /// Creates the role of a band that looks like [look].
  const BandRole(this.look);

  /// How it looks where it lies this frame.
  final BandLook look;

  @override
  bool operator ==(Object other) => other is BandRole && other.look == look;

  @override
  int get hashCode => look.hashCode;
}

/// One site of the frame: where the form found it and what it asks.
@internal
final class SiteFacts {
  /// Creates the facts of the site known as [id].
  SiteFacts(this.id);

  /// Stable while the site lives; the ledger's key.
  final Object id;

  /// Its place in paint order.
  int order = 0;

  /// The order of the last thing painted under its body.
  int floor = -1;

  /// Inherited alpha, filters and clips.
  StateChain state = StateChain.root;

  /// The [state], [clip] and [hidden] the dirty log last knew: glass draws no
  /// picture, so a fade or a clip around it reaches the log only through this.
  (StateChain, Rect?, bool) noted = (StateChain.root, null, false);

  /// The clip around it on the screen, if any.
  Rect? clip;

  /// Its index in the frame's sites and in [Plan.fates].
  int index = 0;

  /// What its site asks this frame.
  SiteAsk ask = SiteAsk.none;

  /// What it paints.
  Rect get drawn => ask.drawn;

  /// What it reads.
  Rect get reads => ask.reads;

  /// What its filter must share.
  Look get look => ask.look;

  /// What keeps it out of every group, if anything does.
  NoJoin? get noJoin => ask.noJoin;

  /// Whether it draws nothing this frame.
  bool get hidden => ask.hidden;

  /// Whether a read of it must stay live.
  bool get turned => ask.turned;

  /// Whether it is a scroll edge glass over it can draw.
  bool get isBand => ask.role is BandRole;
}

/// Where a read's backdrop comes from.
@internal
sealed class ReadSource {
  const ReadSource();
}

/// The copy's layers added again inside the read's filter: one target.
@internal
final class SceneRead extends ReadSource {
  /// Creates the source.
  const SceneRead();
}

/// An image: none in the frame's scene. A new one costs its own submit.
@internal
final class ImageRead extends ReadSource {
  /// Creates the source.
  const ImageRead({required this.held});

  /// Whether the image of an earlier frame still holds.
  final bool held;
}

/// A backdrop filter: the frame goes offscreen, and splits once per read.
@internal
final class LiveRead extends ReadSource {
  /// Creates the source.
  const LiveRead();
}

/// One backdrop and all the glass drawn from it.
@internal
final class Read {
  /// Opens a read at [lead].
  Read(this.lead)
    : band = lead.reads,
      quad = lead.drawn,
      share = lead.look.need.share,
      shapes = lead.isBand ? 0 : lead.look.shapes {
    members.add(lead);
  }

  /// The shapes in its members' shared matte.
  int shapes;

  /// The first member in paint order; the filter draws at its place.
  final SiteFacts lead;

  /// Everything drawn from this read, in paint order.
  final List<SiteFacts> members = [];

  /// What this read holds of what lies under it.
  Rect band;

  /// What its filter draws over.
  Rect quad;

  /// The most device pixels along each side one pixel of its copy can stand
  /// for, for every member.
  int share;

  /// Where the backdrop comes from.
  ReadSource source = const SceneRead();

  /// What the layers under its lead leave it.
  ReadLimit limit = ReadLimit.none;

  /// Earlier reads whose glass lies in [band]: each is drawn again inside this
  /// read, so nesting doubles a read's targets.
  final List<Read> holds = [];

  /// Zero over pictures alone, else one more than the highest read it holds.
  int level = 0;

  /// Where its backdrop's pixels lie, for a read that does not read live.
  late ReadGeometry geometry;

  /// The frost of the glass it leads, in logical pixels: 0 under a band.
  double get frost => lead.isBand ? 0 : lead.look.frost;

  /// Whether what it holds differs from the last frame.
  bool changed = false;

  /// The group of live reads that share one copy of the backdrop, taken at the
  /// first of them, or null for a read on its own.
  int? liveGroup;

  /// The targets this read issues, what it holds drawn again counted. A frost
  /// baked in place is left out: it adds a pass of a copy's few pixels.
  int get targets {
    if (source is ImageRead) return 0;
    var total = 1;
    for (final held in holds) {
      total += held.targets;
    }
    return total;
  }
}

/// What a site does this frame.
@internal
sealed class Fate {
  const Fate();
}

/// Idle, off screen or outside its clips.
@internal
final class Hidden extends Fate {
  /// Creates the fate.
  const Hidden();
}

/// Draws [read]'s filter at its own place.
@internal
final class Leads extends Fate {
  /// Creates the fate.
  const Leads(this.read);

  /// The read it leads.
  final Read read;
}

/// Another site's filter draws this glass.
@internal
final class Follows extends Fate {
  /// Creates the fate.
  const Follows(this.read);

  /// The read it follows.
  final Read read;
}

/// One frame's plan. Every route the frame takes is a value in here.
@internal
final class Plan {
  /// Creates a plan.
  Plan(
    this.reads,
    this.fates, {
    required this.issuedTargets,
    required this.dueAt,
    required this.notes,
  });

  /// The frame's reads in paint order.
  final List<Read> reads;

  /// Parallel to [Scenery.sites].
  final List<Fate> fates;

  /// Targets the frame issues, nested replays counted.
  final int issuedTargets;

  /// The first frame a read that holds still can buy its image, if none
  /// changes before it.
  final int dueAt;

  /// Why the frame is what it is; empty unless asked for.
  final List<String> notes;
}

/// What is kept between frames for the decisions, with one writer: [compile]
/// returns edits and the composer applies them.
@internal
final class Ledger {
  /// Per read's lead.
  final Map<Object, ReadMemo> reads = Map.identity();
}

/// What a read's lead remembers.
@internal
final class ReadMemo {
  /// The frame its band last changed.
  int changedAt = 0;

  /// Holds that ended before they paid for their image, in a row.
  int misses = 0;

  /// The frame its image was drawn, if it has one.
  int? boughtAt;

  /// Where its backdrop's pixels lay: its image's, if it has one.
  ReadGeometry? geometry;

  /// The frame this memo was last used, to forget leads that left.
  int seenAt = 0;

  /// The leads of the reads it holds.
  List<Object> holds = const [];

  /// Where its band was a frame ago, to see how fast it moves.
  Rect? lastBand;
}

/// Measured numbers the policy trades on. Only joining across space and buying
/// an image read them; everything else is dominance and needs no number.
///
/// In GPU ms per frame on the Pixel 6a (3.50 beta). Sources are in-launch pairs
/// from the 2026-11-05 one-pass results. Some are inferred from those pairs;
/// the sensitivity gate holds the plan to at most two targets more or less when
/// any of them is three times off.
@internal
final class Prices {
  /// Creates a price table.
  const Prices({
    this.rasterWeight = 0.3,
    this.passGpu = 0.04,
    this.passRaster = 0.27,
    this.copyGpuPerMpx = 0.35,
    this.deadGpuPerMpx = 0.15,
    this.imageGpu = 0.3,
    this.imageRaster = 2,
    this.pixelsPerLogical = 2.625,
  });

  /// GPU ms one raster ms is worth. At 0.3 the model signs the kept and
  /// rejected group verdicts of 2026-11-05 as they were decided; rails alone
  /// say nearer 0.1, but frame time comes first.
  final double rasterWeight;

  /// One offscreen pass with its pixels unchanged.
  final double passGpu;

  /// One filter on the raster thread: 12 buttons merged saved 0.24-0.31 each.
  final double passRaster;

  /// Copy pixels; about 0.3-0.4 per Mpx at full size, blur included.
  final double copyGpuPerMpx;

  /// Quad pixels nothing draws in: the 0.4 of a screen per filter that
  /// grouping shipped with, at 0.17 per pass.
  final double deadGpuPerMpx;

  /// One image drawn in a frame, its target and submit.
  final double imageGpu;

  /// One image drawn in a frame on the raster thread, inferred from snapshot
  /// shares of 20-46 %.
  final double imageRaster;

  /// Device pixels per logical pixel the areas are priced at.
  final double pixelsPerLogical;

  double _mpx(double logicalArea) =>
      logicalArea * pixelsPerLogical * pixelsPerLogical / 1e6;

  /// What one pass over [band] at [share] costs a frame.
  double passCost(Rect band, int share) =>
      passGpu +
      rasterWeight * passRaster +
      copyGpuPerMpx * _mpx(band.width * band.height) / (share * share);

  /// What one image costs, once.
  double get imageCost => imageGpu + rasterWeight * imageRaster;

  /// How many frames a read over [band] must hold still to pay for its image.
  int rent(Rect band, int share) =>
      math.max(1, (imageCost / passCost(band, share)).ceil());
}

/// Decisions a person made once.
@internal
final class Policy {
  /// Creates a policy.
  const Policy({
    this.maxTargets = 8,
    this.maxShapes = 16,
    this.bands = true,
    this.copies = true,
    this.dropsFrost = true,
  });

  /// Whether a band under glass that frosts as wide stays out of what the
  /// glass reads, the glass adding its frost to its own.
  final bool dropsFrost;

  /// Whether a read may come from anything but the live backdrop.
  final bool copies;

  /// Whether glass may draw a scroll edge under it in its own filter.
  final bool bands;

  /// Shapes one shared matte can hold.
  final int maxShapes;

  /// Targets a frame may issue before reads move to images.
  final int maxTargets;
}

/// Edits to a [Ledger] that [compile] asks for.
@internal
final class LedgerEdits {
  /// The memos to write, by lead.
  final Map<Object, ReadMemo> writes = Map.identity();

  /// Applies the edits, and forgets leads gone for a while.
  void applyTo(Ledger ledger, int frame) {
    ledger.reads.addAll(writes);
    if (ledger.reads.length <= writes.length) return;
    ledger.reads.removeWhere((_, memo) => frame - memo.seenAt > 120);
  }
}

/// The cost of drawing [site] with [read], minus that of one more read, in GPU
/// ms equivalents. Below zero, sharing pays.
///
/// Signs the record on the Pixel: 12 scattered buttons merge (-0.78 against
/// -0.9..-1.7 measured), a whole-screen group is rejected (+0.26 against
/// +0.6..+0.7), a band under glass joins it (about -0.1 against 0..-0.1) and
/// any dead area in a menu at full resolution loses (+0.43 against about +1).
/// The magnitudes disagree, so this is a join rule, not a prediction.
@internal
double mergeDelta(Read read, SiteFacts site, Prices prices) {
  final share = math.min(read.share, site.look.need.share);
  final band = read.band.expandToInclude(site.reads);
  final quad = read.quad.expandToInclude(site.drawn);
  double area(Rect rect) => rect.width * rect.height;
  double copy(Rect rect, int scale) =>
      prices.copyGpuPerMpx * prices._mpx(area(rect)) / (scale * scale);
  final together = copy(band, share);
  final apart =
      copy(read.band, read.share) + copy(site.reads, site.look.need.share);
  final dead =
      prices.deadGpuPerMpx *
      prices._mpx(math.max(0, area(quad) - area(read.quad) - area(site.drawn)));
  return together -
      apart +
      dead -
      prices.passGpu -
      prices.rasterWeight * prices.passRaster;
}

bool _contains(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

// A filter draws under its lead's clips, so the glass it draws must lie inside
// them, and inside its own, which the filter does not apply. Under the same
// clip the filter cuts it as it would itself.
bool _insideClips(Read read, SiteFacts site) {
  final lead = read.lead.clip;
  final own = site.clip;
  if (lead == own) return true;
  return (lead == null || _contains(lead, site.drawn)) &&
      (own == null || _contains(own, site.drawn));
}

bool _lookFits(Read read, SiteFacts site) {
  final lead = read.lead.look;
  final look = site.look;
  if (site.isBand) return false;
  if (read.lead.isBand) {
    return look.drawsBand &&
        site.drawn.overlaps(read.lead.drawn) &&
        lead.need.bandFits(look.need) &&
        (read.members.length == 1 ||
            read.members[1].look.key == look.key &&
                read.members[1].look.tint == look.tint);
  }
  return lead.key == look.key;
}

String _whyApart(Read read, SiteFacts site, Prices prices, Policy policy) {
  if (read.lead.noJoin case final reason?) {
    return 'its lead never joins: ${reason.name}';
  }
  if (read.lead.isBand && !policy.bands) return 'bands stay apart';
  if (read.lead.look.page != null) return 'its lead reads a page';
  if (read.source is LiveRead) return 'its lead reads live';
  if (read.lead.order < site.floor) return 'painted over after its lead';
  if (!site.state.same(read.lead.state)) return 'other clip, alpha or filter';
  if (!_insideClips(read, site)) return 'a clip would cut it';
  if (!_lookFits(read, site)) return 'other look';
  if (read.shapes + site.look.shapes > policy.maxShapes) return 'matte is full';
  return 'costs more together: '
      '${mergeDelta(read, site, prices).toStringAsFixed(2)}';
}

/// The one decision function: every route is an output of it.
///
/// Sites are read in paint order, so when one is reached every lower site's
/// fate is decided, which is what lets a read know whether it holds glass.
/// First fit, because the cleverer groupings measured worse on the phone
/// (closest_groups +31.7 %, dead_free +27 % on the menu).
///
/// Same inputs, same plan and same edits.
@internal
(Plan, LedgerEdits) compile(
  Scenery scene,
  Ledger ledger,
  Prices prices,
  Policy policy,
  int frame, {
  bool explain = false,
}) {
  final notes = <String>[];
  final reads = <Read>[];
  final fates = <Fate>[];
  final screen = scene.screen;
  final sites = scene.sites;
  for (var at = 0; at < sites.length; at++) {
    final site = sites[at];
    if (site.hidden ||
        !site.drawn.overlaps(screen) ||
        (site.clip != null &&
            !site.clip!.overlaps(site.drawn.intersect(screen)))) {
      fates.add(const Hidden());
      continue;
    }
    final limit = _limitOf(site, reads, scene, policy);
    final pageOnly = site.look.page != null;
    Read? joined;
    if (site.noJoin != null || pageOnly || limit == ReadLimit.liveOnly) {
      if (explain) {
        final why =
            site.noJoin?.name ??
            (site.turned
                ? 'turned'
                : scene.whyLimited(site) ?? 'over glass that reads live');
        notes.add('${site.id}: never joins: $why');
      }
    } else {
      for (var i = reads.length - 1; i >= 0; i--) {
        final read = reads[i];
        final band = read.lead.isBand;
        final overGlass = read.members
            .skip(band ? 1 : 0)
            .any((m) => m.drawn.overlaps(site.drawn));
        if (overGlass) {
          if (explain) notes.add('${site.id}: overlaps');
          break;
        }
        if (read.lead.noJoin == null &&
            (policy.bands || !band) &&
            read.source is! LiveRead &&
            read.lead.look.page == null &&
            read.lead.order >= site.floor &&
            site.state.same(read.lead.state) &&
            _insideClips(read, site) &&
            _lookFits(read, site) &&
            read.shapes + site.look.shapes <= policy.maxShapes &&
            (band || mergeDelta(read, site, prices) < 0)) {
          joined = read;
          break;
        }
        if (explain) {
          notes.add('${site.id}: ${_whyApart(read, site, prices, policy)}');
        }
        // Joining a read further down would draw this glass under the band.
        if (band && read.lead.drawn.overlaps(site.drawn)) break;
      }
    }
    if (joined != null) {
      joined.members.add(site);
      joined.shapes += site.look.shapes;
      joined.band = joined.band.expandToInclude(site.reads);
      joined.quad = joined.quad.expandToInclude(site.drawn);
      joined.share = math.min(joined.share, site.look.need.share);
      fates.add(Follows(joined));
      continue;
    }
    final read = Read(site);
    read.limit = limit;
    // A filter of a page has no scene read to fall back on.
    if (limit == ReadLimit.liveOnly || (pageOnly && limit != ReadLimit.none)) {
      read.source = const LiveRead();
    }
    reads.add(read);
    fates.add(Leads(read));
  }

  for (var i = 0; i < reads.length; i++) {
    final read = reads[i];
    if (read.source is LiveRead) continue;
    var frostLeftOut = 0.0;
    for (var j = 0; j < i; j++) {
      final below = reads[j];
      if (below.source is LiveRead || !_under(below, read)) continue;
      if (policy.dropsFrost &&
          below.lead.isBand &&
          below.members.length == 1 &&
          read.frost > 0 &&
          below.lead.look.frost <= read.frost) {
        frostLeftOut = math.max(frostLeftOut, below.lead.look.frost);
        continue;
      }
      read.holds.add(below);
      read.level = math.max(read.level, below.level + 1);
    }
    final lead = read.lead.look;
    final page = lead.page;
    read.geometry = ReadGeometry.resolve(
      asked: Lattice(scene.devicePixelRatio, read.share),
      atScreen: !_holdsAtOwnGrid(read),
      reads: read.band,
      screen: screen,
      clip: read.lead.clip,
      bakedFrost: bakedFrost(
        share: read.share,
        holdsGlass: read.holds.isNotEmpty,
        glassFrost: read.lead.isBand
            ? (read.members.length > 1 ? read.members[1].look.frost : 0)
            : lead.frost,
        bandFrost: read.lead.isBand ? lead.frost : null,
      ),
      frostLeftOut: frostLeftOut,
      filter: page == null ? null : (page.key, page.blendMode),
    );
  }

  final edits = LedgerEdits();
  var dueAt = _never;
  for (final read in reads) {
    if (read.source is LiveRead) {
      read.changed = true;
      continue;
    }
    final id = read.lead.id;
    final memo = ledger.reads[id];
    final next = ReadMemo();
    next.seenAt = frame;
    next.lastBand = read.band;
    final holds = [for (final held in read.holds) held.lead.id];
    next.holds = holds;
    final geometry = read.geometry;
    final last = memo?.geometry;
    var room = last?.room;
    final watched = room ?? read.band;
    final changed =
        scene.dirty.meets(read.lead.order, watched) ||
        read.holds.any((held) => held.changed) ||
        (last != null && !last.drawsLike(geometry));
    read.changed = changed;
    next.changedAt = changed
        ? frame
        : memo?.changedAt ?? scene.lastChangedUnder(read.lead.order, read.band);
    next.misses = memo?.misses ?? 0;
    final rent = prices.rent(read.band, read.share);
    var boughtAt = memo?.boughtAt;
    if (room != null &&
        (changed ||
            !last!.servesAsImage(geometry) ||
            !_sameIds(memo!.holds, holds))) {
      // A hold that ended before it paid makes the next wait longer.
      final held = frame - boughtAt!;
      next.misses = held < rent ? math.min(next.misses + 1, 6) : 0;
      room = null;
      boughtAt = null;
    }
    final pageOnly = read.lead.look.page != null;
    final need = rent << next.misses;
    final allowed = read.limit == ReadLimit.none;
    if (room != null) {
      read.source = const ImageRead(held: true);
    } else if (allowed &&
        (pageOnly || (!changed && frame - next.changedAt >= need))) {
      read.source = const ImageRead(held: false);
      room = _withRoom(read, memo, rent, screen);
      boughtAt = frame;
    } else if (allowed) {
      dueAt = math.min(dueAt, next.changedAt + need);
    }
    if (room != null) {
      read.geometry = geometry.withRoom(room, screen);
    }
    next.geometry = read.geometry;
    next.boughtAt = boughtAt;
    edits.writes[id] = next;
  }

  int targets() => reads.fold(0, (sum, read) => sum + read.targets);
  var issued = targets();
  if (issued > policy.maxTargets) {
    // The deepest read another holds first: doubling becomes linear. Then the
    // last in paint order, so the same frame always moves the same reads.
    final deepest = reads.where((read) => read.level > 0).toList();
    deepest.sort((a, b) => b.level.compareTo(a.level));
    final order = [...deepest, ...reads.reversed];
    for (final read in order) {
      if (issued <= policy.maxTargets) break;
      if (read.source is! SceneRead || read.limit != ReadLimit.none) continue;
      read.source = const ImageRead(held: false);
      read.geometry = read.geometry.withRoom(read.band, screen);
      edits.writes[read.lead.id]?.geometry = read.geometry;
      edits.writes[read.lead.id]?.boughtAt = frame;
      issued = targets();
      if (explain) notes.add('${read.lead.id}: over budget, reads an image');
    }
    if (explain && issued > policy.maxTargets) {
      notes.add('over budget at $issued: what is left can not use an image');
    }
  }
  _groupLiveReads(reads);
  return (
    Plan(
      reads,
      fates,
      issuedTargets: issued,
      dueAt: dueAt,
      notes: notes,
    ),
    edits,
  );
}

// No frame comes this far.
const _never = 1 << 52;

// Live reads with nothing painted under the later ones since the first share
// its copy of the backdrop: Impeller flips to a new target once, not per read
// (BackdropKey). A read over another's glass has to see that glass, so it starts
// a group of its own. Scroll edges and fake glass filter through a layer of
// their own, with no key to take.
void _groupLiveReads(List<Read> reads) {
  var groups = 0;
  final open = <Read>[];
  void close() {
    if (open.length > 1) {
      for (final read in open) {
        read.liveGroup = groups;
      }
      groups++;
    }
    open.clear();
  }

  for (final read in reads) {
    final lead = read.lead;
    if (read.source is! LiveRead ||
        lead.isBand ||
        lead.noJoin == NoJoin.noMatte) {
      continue;
    }
    if (open.isNotEmpty) {
      final first = open.first;
      final apart =
          first.lead.order >= lead.floor &&
          lead.state.same(first.lead.state) &&
          !open.any((other) => other.lead.drawn.overlaps(lead.reads));
      if (!apart) close();
    }
    open.add(read);
  }
  close();
}

// What the content and the glass under [site] allow a read of it to be. A
// read over a live read has to read live too: only the frame's own pass holds
// what that one drew.
ReadLimit _limitOf(
  SiteFacts site,
  List<Read> reads,
  Scenery scene,
  Policy policy,
) {
  if (site.turned || !policy.copies) return ReadLimit.liveOnly;
  for (final read in reads) {
    if (read.source is! LiveRead) continue;
    for (final member in read.members) {
      if (member.drawn.overlaps(site.reads)) return ReadLimit.liveOnly;
    }
  }
  return scene.limitUnder(site);
}

// Whether [below]'s glass lies under [read]'s rather than beside it: glass
// beside it stays out of what it reads, NEAR: it does not show a neighbour in
// what it reads at its rim.
bool _under(Read below, Read read) {
  for (final held in below.members) {
    for (final member in read.members) {
      if (held.drawn.overlaps(member.drawn)) return true;
    }
  }
  return false;
}

/// Whether [read]'s copy holds the glass under it at the copy's own pixels,
/// the glass's shader drawing a fragment for each of them, rather than at
/// the screen's: glass holding more glass in turn takes its fragments for
/// device pixels.
///
/// NEAR, judged by eye on the iPhone 16 Pro over the gallery's controls and
/// cards under the tab bar: the held glass's bevel squeezes what it refracts
/// past what one fragment per copy pixel resolves, and the copy's frost
/// hides it. Against the glass held at the screen's pixels under Impeller's
/// blur (host, dpr 2 and 3, clear glass held): 5 to 13 levels off under a
/// frost of 12 and 20 logical pixels, 40 to 51 under 6; drawn at the
/// screen's pixels and as a picture, 4 to 35. It saves 12 % of the fragment
/// work of a scroll with glass under the tab bar on the Pixel 6a.
bool _holdsAtOwnGrid(Read read) => read.holds.every(
  (held) => held.holds.isEmpty && held.members.every((m) => m.look.anyGrid),
);

bool _sameIds(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

// An image takes room for glass that moves in it: what the band moved in a
// frame times the frames the image has to hold to pay, at least twice the
// room that last ran out.
Rect _withRoom(Read read, ReadMemo? memo, int rent, Rect screen) {
  final last = memo?.lastBand;
  var room = 0.0;
  if (read.changed || read.lead.look.page?.clip != null) return read.band;
  if (last != null) {
    final moved = math.max(
      (last.left - read.band.left).abs(),
      (last.top - read.band.top).abs(),
    );
    room = moved * rent;
  }
  if (memo?.geometry?.room case final previous?) {
    room = math.max(room, 2 * (previous.width - read.band.width).abs());
  }
  return read.band.inflate(room).intersect(screen);
}
