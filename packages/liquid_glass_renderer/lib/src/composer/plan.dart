import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/plan_input.dart';
import 'package:liquid_glass_renderer/src/composer/plan_ledger.dart';
import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:liquid_glass_renderer/src/plan/plan_policy.dart';
import 'package:liquid_glass_renderer/src/plan/plan_result.dart';
import 'package:liquid_glass_renderer/src/plan/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/plan/plan_site.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/plan/rects.dart';

/// The most times a read's wait for an image doubles after holds that ended
/// before the image paid: at most 64 times its rent.
const int _maxWaitDoublings = 6;

/// The device pixels drawing [site] with [read] copies and leaves dead,
/// against those of the two apart, less what one read is worth
/// ([PlanPolicy.passPixels]). Below zero, sharing pays.
double _mergeDelta(
  GlassRead read,
  SiteFacts site,
  PlanPolicy policy,
  double devicePixelRatio,
) {
  const copyPixels = PlanPolicy.copyPixels;
  final share = math.min(read.share, site.ask.look.need.share);
  final footprint = read.footprint.expandToInclude(site.ask.reads);
  final quad = read.quad.expandToInclude(site.ask.drawn);
  double area(Rect rect) => rect.width * rect.height;
  final together = copyPixels(footprint, share, devicePixelRatio);
  final apart =
      copyPixels(read.footprint, read.share, devicePixelRatio) +
      copyPixels(site.ask.reads, site.ask.look.need.share, devicePixelRatio);
  final dead =
      policy.deadWeight *
      math.max(0, area(quad) - area(read.quad) - area(site.ask.drawn)) *
      devicePixelRatio *
      devicePixelRatio;
  return together - apart + dead - policy.passPixels;
}

// A filter draws under its lead's clips, so the glass it draws must lie inside
// them, and inside its own, which the filter does not apply. Under the same
// clip the filter cuts it as it would itself.
bool _insideClips(GlassRead read, SiteFacts site) {
  final lead = read.lead.clip;
  final own = site.clip;
  if (lead == own) return true;
  return (lead == null || encloses(lead, site.ask.drawn)) &&
      (own == null || encloses(own, site.ask.drawn));
}

bool _lookFits(GlassRead read, SiteFacts site, double devicePixelRatio) {
  final lead = read.lead.ask.look;
  final look = site.ask.look;
  if (site.isBand) return false;
  if (read.lead.isBand) {
    return look.drawsBand &&
        meets(site.ask.drawn, read.lead.ask.drawn) &&
        lead.need.bandFits(look.need, devicePixelRatio: devicePixelRatio) &&
        switch (read.bandPainter?.ask.look) {
          null => true,
          final painter => painter.key == look.key && painter.tint == look.tint,
        };
  }
  return lead.key == look.key;
}

// Why a site does not join a read: of itself, whatever the read, or of the
// read it was held against. The verdict and the frame report's note are both
// read off one of these.
enum _Apart {
  noJoin,
  turned,
  limited,
  imageOnly,
  leadNoJoin,
  leadImageOnly,
  leadBackdrop,
  paintedOver,
  otherState,
  clipCut,
  otherLook,
  atlasFull,
  costsMore,
}

// Why [site], over content that leaves its read [limit], never joins a read,
// or null where it may.
_Apart? _alone(SiteFacts site, ReadLimit limit) {
  if (site.ask.noJoin != null) return _Apart.noJoin;
  if (limit == ReadLimit.backdropOnly) {
    return site.ask.place is Turned ? _Apart.turned : _Apart.limited;
  }
  if (site.ask.look.imageOnly) return _Apart.imageOnly;
  return null;
}

// Why [site] does not join [read], or null where it joins.
_Apart? _apart(
  GlassRead read,
  SiteFacts site,
  PlanScenery scene,
  PlanPolicy policy,
) {
  final bandLeads = read.lead.isBand;
  if (read.lead.ask.noJoin != null) return _Apart.leadNoJoin;
  if (read.lead.ask.look.imageOnly) return _Apart.leadImageOnly;
  if (read.source is BackdropRead) return _Apart.leadBackdrop;
  if (read.lead.order < site.floor) return _Apart.paintedOver;
  if (!site.state.same(read.lead.state)) return _Apart.otherState;
  if (!_insideClips(read, site)) return _Apart.clipCut;
  if (!_lookFits(read, site, scene.devicePixelRatio)) {
    return _Apart.otherLook;
  }
  if (read.shapes + site.ask.look.shapes > policy.maxShapes) {
    return _Apart.atlasFull;
  }
  if (!bandLeads &&
      !(_mergeDelta(read, site, policy, scene.devicePixelRatio) < 0)) {
    return _Apart.costsMore;
  }
  return null;
}

// The frame report's note of [why] for [site], held against [read] where
// that is why.
String _note(
  _Apart why,
  SiteFacts site,
  GlassRead? read,
  PlanScenery scene,
  PlanPolicy policy,
) {
  final text = switch (why) {
    _Apart.noJoin => 'never joins: ${site.ask.noJoin!.name}',
    _Apart.turned => 'never joins: turned',
    _Apart.limited =>
      'never joins: '
          '${scene.whyLimited(site) ?? 'over glass that reads the backdrop'}',
    _Apart.imageOnly => 'never joins: reads an image',
    _Apart.leadNoJoin => 'its lead never joins: ${read!.lead.ask.noJoin!.name}',
    _Apart.leadImageOnly => 'its lead reads an image',
    _Apart.leadBackdrop => 'its lead reads the backdrop',
    _Apart.paintedOver => 'painted over after its lead',
    _Apart.otherState => 'other clip, alpha or filter',
    _Apart.clipCut => 'a clip would cut it',
    _Apart.otherLook => 'other look',
    _Apart.atlasFull => 'shared atlas is full',
    _Apart.costsMore =>
      'costs more together: ${_mergeDelta(
        read!,
        site,
        policy,
        scene.devicePixelRatio,
      ).round()} px',
  };
  return '${site.id}: $text';
}

/// The one decision function: every route is an output of it.
///
/// Sites are read in paint order, so when one is reached every lower site's
/// fate is decided, which is what lets a read know whether it holds glass.
/// First fit, because the cleverer groupings measured worse on the phone
/// (closest_groups +31.7 %, dead_free +27 % on the menu).
///
/// Without [copies], every read is the backdrop's.
///
/// Same inputs, same plan and same edits.
(GlassPlan, PlanLedgerEdits) compilePlan(
  PlanScenery scene,
  PlanLedger ledger,
  PlanPolicy policy,
  int frame, {
  bool copies = true,
  bool explain = false,
}) {
  final notes = <String>[];
  final reads = <GlassRead>[];
  final fates = <SiteFate>[];
  final limits = <ReadLimit?>[];
  final edits = PlanLedgerEdits();
  _decideFates(
    scene,
    policy,
    copies,
    reads,
    fates,
    limits,
    explain ? notes : null,
  );
  for (final read in reads) {
    read.geometryKind = geometryKindOf(read.glass);
  }
  _resolveLayouts(scene, reads);
  final dueAt = _chooseSources(
    scene,
    ledger,
    policy,
    frame,
    reads,
    edits,
  );
  final issued = _keepBudget(
    scene,
    ledger,
    policy,
    frame,
    reads,
    edits,
    explain ? notes : null,
  );
  _groupBackdropReads(reads);
  return (
    GlassPlan(
      reads,
      fates,
      issuedTargets: issued,
      dueAt: dueAt,
      notes: notes,
      limits: limits,
    ),
    edits,
  );
}

/// [last] again for a frame where nothing changed but what lies under the
/// glass, with the edits [compilePlan] would make: the same reads, each told
/// whether what it holds changed. Null where the frame plans anew: an image
/// it holds no longer stands, the layers under a site leave its read
/// something else or take another pass, or a read that held still is due its
/// image.
///
/// The glass is [last]'s: the same sites asking the same, under the same
/// clips and state, each over the same glass ([SiteFacts.floor]).
///
/// [compilePlan] of the frame gives a plan of the same values.
(GlassPlan, PlanLedgerEdits)? keepPlan(
  GlassPlan last,
  PlanScenery scene,
  PlanLedger ledger,
  int frame,
) {
  final sites = scene.sites;
  for (var at = 0; at < sites.length; at++) {
    final limit = last.limits[at];
    if (limit != null && scene.limitUnder(sites[at]) != limit) return null;
  }
  final edits = PlanLedgerEdits();
  final changes = Map<GlassRead, bool>.identity();
  var dueAt = _never;
  for (final read in last.reads) {
    if (read.source is BackdropRead) continue;
    final memo = ledger.reads[read.lead.id];
    if (memo == null ||
        scene.savedUnder(read.lead.order, read.footprint, flat: read.flat) !=
            read.inside) {
      return null;
    }
    final changed =
        scene.dirty.meets(
          read.lead.order,
          memo.layout?.room ?? read.footprint,
        ) ||
        read.holds.any((held) => changes[held]!);
    if (changed && read.source is ImageRead) return null;
    changes[read] = changed;
    final changedAt = changed ? frame : memo.changedAt;
    if (read.source is SceneRead && read.wait != null) {
      dueAt = math.min(dueAt, changedAt + read.wait!);
    }
    edits.writes[read.lead.id] = memo.seen(frame, changedAt: changedAt);
  }
  if (frame >= dueAt) return null;
  for (final MapEntry(key: read, value: changed) in changes.entries) {
    read.changed = changed;
    if (read.source is ImageRead) read.source = const ImageRead(held: true);
  }
  return (
    GlassPlan(
      last.reads,
      last.fates,
      issuedTargets: last.issuedTargets,
      dueAt: dueAt,
      notes: last.notes,
      limits: last.limits,
    ),
    edits,
  );
}

// Decides each site's fate in paint order: hidden, follower or lead.
void _decideFates(
  PlanScenery scene,
  PlanPolicy policy,
  bool copies,
  List<GlassRead> reads,
  List<SiteFate> fates,
  List<ReadLimit?> limits,
  List<String>? notes,
) {
  final screen = scene.screen;
  final sites = scene.sites;
  for (var at = 0; at < sites.length; at++) {
    final site = sites[at];
    if (site.ask.hidden ||
        !meets(site.ask.drawn, screen) ||
        (site.clip != null &&
            !meets(site.clip!, site.ask.drawn.intersect(screen)))) {
      fates.add(const HiddenFate());
      limits.add(null);
      continue;
    }
    final under = scene.limitUnder(site);
    limits.add(under);
    final limit = _limitOf(site, reads, under, copies);
    GlassRead? joined;
    if (_alone(site, limit) case final why?) {
      notes?.add(_note(why, site, null, scene, policy));
    } else {
      for (var i = reads.length - 1; i >= 0; i--) {
        final read = reads[i];
        final bandLeads = read.lead.isBand;
        final overGlass = read.glassMembers.any(
          (m) => meets(m.ask.drawn, site.ask.drawn),
        );
        if (overGlass) {
          notes?.add('${site.id}: overlaps');
          break;
        }
        final why = _apart(read, site, scene, policy);
        if (why == null) {
          joined = read;
          break;
        }
        notes?.add(_note(why, site, read, scene, policy));
        // Joining a read further down would draw this glass under the band.
        if (bandLeads && meets(read.lead.ask.drawn, site.ask.drawn)) break;
      }
    }
    if (joined != null) {
      joined.members.add(site);
      joined.shapes += site.ask.look.shapes;
      joined.footprint = joined.footprint.expandToInclude(site.ask.reads);
      joined.quad = joined.quad.expandToInclude(site.ask.drawn);
      joined.share = math.min(joined.share, site.ask.look.need.share);
      fates.add(FollowFate(joined));
      continue;
    }
    final read = GlassRead(site)..limit = limit;
    if (limit.keepsToBackdrop(noScene: site.readsNoScene)) {
      read.source = const BackdropRead();
    }
    reads.add(read);
    fates.add(LeadFate(read));
  }
}

// Decides the reads each copy holds and its lattice, rects and frost.
void _resolveLayouts(PlanScenery scene, List<GlassRead> reads) {
  for (var i = 0; i < reads.length; i++) {
    final read = reads[i];
    if (read.source is BackdropRead) continue;
    var frostLeftOut = 0.0;
    for (var j = 0; j < i; j++) {
      final below = reads[j];
      if (below.source is BackdropRead || !_under(below, read)) continue;
      // A band under glass that blurs at least as wide everywhere stays out
      // of the glass's copy, and the glass adds the band's frost to its own
      // blur. NEAR: a 44 pt glass with 3 px of frost over the hard scroll
      // edge at dpr 3 differs from a copy that holds the band by at most 13
      // channel levels on the host.
      if (below.lead.isBand &&
          below.members.length == 1 &&
          read.leadShaderBlur > 0 &&
          below.lead.ask.look.need.shaderFrost <= read.leadShaderBlur) {
        frostLeftOut = math.max(
          frostLeftOut,
          below.lead.ask.look.need.shaderFrost,
        );
        continue;
      }
      read.holds.add(below);
      read.level = math.max(read.level, below.level + 1);
    }
    final lead = read.lead.ask.look;
    final imageRead = lead.imageRead;
    read.layout = ReadLayout.resolve(
      devicePixelRatio: scene.devicePixelRatio,
      askedShare: read.share,
      atScreen: !_holdsAtOwnGrid(read),
      reads: read.footprint,
      screen: scene.screen,
      clip: read.lead.clip,
      holdsGlass: read.holds.isNotEmpty,
      edgeFrost: read.bandPainter == null ? lead.need.shaderFrost : 0,
      frostLeftOut: frostLeftOut,
      filter: imageRead == null ? null : (imageRead.key, imageRead.blendMode),
      imageBlur: switch (imageRead?.blur) {
        (final x, final y) => math.max(x, y),
        null => 0,
      },
      levels: read.lead.isBand
          ? read.bandPainter?.ask.look.need.levels
          : lead.need.levels,
    );
  }
}

// Decides each copy's source (scene, held or new image) and its memo.
int _chooseSources(
  PlanScenery scene,
  PlanLedger ledger,
  PlanPolicy policy,
  int frame,
  List<GlassRead> reads,
  PlanLedgerEdits edits,
) {
  final screen = scene.screen;
  var dueAt = _never;
  for (final read in reads) {
    if (read.source is BackdropRead) {
      read.changed = true;
      continue;
    }
    final id = read.lead.id;
    final memo = ledger.reads[id];
    final next = ReadMemo()
      ..seenAt = frame
      ..lastFootprint = read.footprint;
    final holds = [for (final held in read.holds) held.lead.id];
    next.holds = holds;
    final layout = read.layout;
    final last = memo?.layout;
    var room = last?.room;
    final watched = room ?? read.footprint;
    final changed =
        scene.dirty.meets(read.lead.order, watched) ||
        read.holds.any((held) => held.changed) ||
        (last != null && !last.drawsLike(layout));
    read.changed = changed;
    next
      ..changedAt = changed
          ? frame
          : memo?.changedAt ??
                scene.lastChangedUnder(read.lead.order, read.footprint)
      ..misses = memo?.misses ?? 0
      ..forBudget = memo?.forBudget ?? false;
    read.inside = scene.savedUnder(
      read.lead.order,
      read.footprint,
      flat: read.flat,
    );
    final rent = policy.imageRent(
      read.footprint,
      read.share,
      devicePixelRatio: scene.devicePixelRatio,
      targets: read.sceneTargets,
    );
    var boughtAt = memo?.boughtAt;
    if (room != null &&
        (changed ||
            !last!.servesAsImage(layout) ||
            !_sameIds(memo!.holds, holds))) {
      // A hold that ended before it paid makes the next wait longer, unless
      // the budget bought the image.
      final held = frame - boughtAt!;
      if (held >= rent) {
        next.misses = 0;
      } else if (!next.forBudget) {
        next.misses = math.min(next.misses + 1, _maxWaitDoublings);
      }
      next.forBudget = false;
      room = null;
      boughtAt = null;
    }
    final need = rent << next.misses;
    final allowed = read.limit == ReadLimit.none;
    if (room != null) {
      read.source = const ImageRead(held: true);
    } else if (allowed &&
        (read.lead.readsNoScene ||
            (!changed && frame - next.changedAt >= need))) {
      read.source = const ImageRead(held: false);
      room = _withRoom(read, memo, rent, screen);
      boughtAt = frame;
    } else if (allowed) {
      read.wait = need;
      dueAt = math.min(dueAt, next.changedAt + need);
    }
    if (room != null) {
      read.layout = layout.withRoom(room, screen);
    }
    next
      ..layout = read.layout
      ..boughtAt = boughtAt;
    edits.writes[id] = next;
  }
  return dueAt;
}

// Decides which scene reads become images to keep within the target budget.
int _keepBudget(
  PlanScenery scene,
  PlanLedger ledger,
  PlanPolicy policy,
  int frame,
  List<GlassRead> reads,
  PlanLedgerEdits edits,
  List<String>? notes,
) {
  var issued = _targets(reads);
  if (issued <= policy.maxTargets) return issued;
  final screen = scene.screen;
  // The deepest read another holds first: doubling becomes linear. Then the
  // last in paint order, so the same frame always moves the same reads.
  final deepest = reads.where((read) => read.level > 0).toList()
    ..sort((a, b) => b.level.compareTo(a.level));
  final order = [...deepest, ...reads.reversed];
  for (final read in order) {
    if (issued <= policy.maxTargets) break;
    if (read.source is! SceneRead || read.limit != ReadLimit.none) continue;
    final id = read.lead.id;
    final rent = policy.imageRent(
      read.footprint,
      read.share,
      devicePixelRatio: scene.devicePixelRatio,
      targets: read.sceneTargets,
    );
    read
      ..source = const ImageRead(held: false)
      ..wait = null
      ..layout = read.layout.withRoom(
        _withRoom(read, ledger.reads[id], rent, screen),
        screen,
      );
    edits.writes[id]!
      ..layout = read.layout
      ..boughtAt = frame
      ..forBudget = true;
    issued = _targets(reads);
    notes?.add('${read.lead.id}: over budget, reads an image');
  }
  if (issued > policy.maxTargets) {
    notes?.add('over budget at $issued: what is left can not use an image');
  }
  return issued;
}

int _targets(List<GlassRead> reads) {
  var sum = 0;
  for (final read in reads) {
    sum += read.targets;
  }
  return sum;
}

// No frame comes this far.
const _never = 1 << 52;

// Impeller flips to a new target once, not per read (BackdropKey).
void _groupBackdropReads(List<GlassRead> reads) {
  var groups = 0;
  final open = <GlassRead>[];
  void close() {
    if (open.length > 1) {
      for (final read in open) {
        read.backdropGroup = groups;
      }
      groups++;
    }
    open.clear();
  }

  for (final read in reads) {
    final lead = read.lead;
    if (read.source is! BackdropRead ||
        lead.isBand ||
        !lead.ask.groupsBackdrop) {
      continue;
    }
    if (open.isNotEmpty) {
      final first = open.first;
      final seesGrouped = open.any(
        (other) => meets(other.lead.ask.drawn, lead.ask.reads),
      );
      final joins =
          first.lead.order >= lead.floor &&
          lead.state.same(first.lead.state) &&
          !seesGrouped;
      if (!joins) close();
    }
    open.add(read);
  }
  close();
}

// What [site]'s read is left, over layers that leave it [under].
ReadLimit _limitOf(
  SiteFacts site,
  List<GlassRead> reads,
  ReadLimit under,
  bool copies,
) {
  if (site.ask.place is Turned || !copies || _seesBackdropGlass(site, reads)) {
    return ReadLimit.backdropOnly;
  }
  return under;
}

bool _seesBackdropGlass(SiteFacts site, List<GlassRead> reads) => reads.any(
  (read) =>
      read.source is BackdropRead &&
      read.members.any(
        (member) => meets(member.ask.drawn, site.ask.reads),
      ),
);

// Whether [below]'s glass lies under [read]'s rather than beside it: glass
// beside it stays out of what it reads, NEAR: it does not show a neighbour in
// what it reads at its rim.
bool _under(GlassRead below, GlassRead read) {
  for (final held in below.members) {
    for (final member in read.members) {
      if (meets(held.ask.drawn, member.ask.drawn)) return true;
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
/// work of a scroll with glass under the tab bar on the Pixel 6a. Glass that
/// frosts its own copy keeps it at the coarser of the two grids
/// (`CornerPlace.heldIn`).
bool _holdsAtOwnGrid(GlassRead read) => read.holds.every(
  (held) => held.holds.isEmpty && held.members.every((m) => m.ask.look.anyGrid),
);

bool _sameIds(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

Rect _withRoom(GlassRead read, ReadMemo? memo, int rent, Rect screen) {
  if (read.changed || read.lead.ask.look.imageRead?.clip != null) {
    return read.footprint;
  }
  final travel = switch (memo?.lastFootprint) {
    final last? =>
      math.max(
            (last.left - read.footprint.left).abs(),
            (last.top - read.footprint.top).abs(),
          ) *
          rent,
    null => 0.0,
  };
  final doubledLastRoom = switch (memo?.layout?.room) {
    final previous? => 2 * (previous.width - read.footprint.width).abs(),
    null => 0.0,
  };
  return read.footprint
      .inflate(math.max(travel, doubledLastRoom))
      .intersect(screen);
}
