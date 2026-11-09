import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';

const _screen = Rect.fromLTWH(0, 0, 411, 914);

final class _Scene implements Scenery {
  _Scene(this.sites);

  @override
  final List<SiteFacts> sites;

  @override
  final DirtyLog dirty = DirtyLog();

  @override
  Rect get screen => _screen;

  int texturesBefore = -1;
  int platformBefore = -1;
  int changedAt = 0;

  @override
  ReadLimit limitUnder(SiteFacts site) {
    if (site.order > platformBefore && platformBefore >= 0) {
      return ReadLimit.liveOnly;
    }
    if (site.order > texturesBefore && texturesBefore >= 0) {
      return ReadLimit.sceneOnly;
    }
    return ReadLimit.none;
  }

  @override
  String? whyLimited(SiteFacts site) => null;

  @override
  int lastChangedUnder(int order, Rect band) => changedAt;
}

Look _look(int look, {bool frost = true}) => Look(
  key: look,
  need: frost ? const CopyNeed(1, share: 2, frost: 8) : const CopyNeed.exact(1),
  drawsBand: frost,
);

SiteFacts _site(int order, Rect drawn, {int look = 0, int floor = -1}) {
  final site = SiteFacts(Object());
  site.order = order;
  site.drawn = drawn;
  site.reads = drawn.inflate(8);
  site.look = _look(look);
  site.floor = floor;
  return site;
}

int _newImages(Plan plan) => plan.reads
    .where((read) => read.source == const ImageRead(held: false))
    .length;

/// A row of [count] buttons, each 44 lp, in paint order from [order].
List<SiteFacts> _row(int count, {int order = 0, double top = 100}) => [
  for (var i = 0; i < count; i++)
    _site(order + i * 2, Rect.fromLTWH(8 + i * 52.0, top, 44, 44)),
];

// A random frame: lists of controls, cards under them that split groups,
// chrome, overlays that stack over what lies under them.
_Scene _generated(int seed) {
  final random = Random(seed);
  final sites = <SiteFacts>[];
  var order = 0;
  final looks = 1 + random.nextInt(6);
  final cards = random.nextInt(6);
  final controls = random.nextInt(40);
  for (var i = 0; i < controls; i++) {
    final card = cards == 0 ? 0 : i * cards ~/ max(controls, 1);
    final rect = Rect.fromLTWH(
      random.nextDouble() * 350,
      random.nextDouble() * 850,
      20 + random.nextDouble() * 60,
      20 + random.nextDouble() * 40,
    );
    final floor = cards == 0 ? -1 : order - 1 - (i % 3 == 0 ? 0 : 3);
    sites.add(_site(order, rect, look: random.nextInt(looks), floor: floor));
    order += 2 + card % 2;
    if (random.nextInt(9) == 0) sites.last.noJoin = NoJoin.field;
    if (random.nextInt(40) == 0) sites.last.turned = true;
    if (random.nextInt(30) == 0) sites.last.hidden = true;
  }
  for (var i = 0; i < random.nextInt(3); i++) {
    final depth = i * 90.0;
    sites.add(_site(order, Rect.fromLTWH(depth, 700 - depth, 300, 200)));
    order += 2;
  }
  final scene = _Scene(sites);
  if (random.nextInt(4) == 0) scene.texturesBefore = 0;
  if (random.nextInt(8) == 0) scene.platformBefore = 0;
  return scene;
}

Plan _plan(
  Scenery scene, {
  Prices prices = const Prices(),
  Policy policy = const Policy(),
  Ledger? ledger,
  int frame = 100,
}) {
  final used = ledger ?? Ledger();
  final (plan, edits) = compile(scene, used, prices, policy, frame);
  edits.applyTo(used, frame);
  return plan;
}

void main() {
  group('joining', () {
    test('equal glass in a row shares one read', () {
      final plan = _plan(_Scene(_row(6)));
      expect(plan.reads, hasLength(1));
      expect(plan.reads.single.members, hasLength(6));
      expect(plan.fates.first, isA<Leads>());
      expect(plan.fates.skip(1), everyElement(isA<Follows>()));
    });

    test('says why glass stays apart when asked', () {
      final sites = _row(3);
      sites[1].floor = sites[0].order + 1;
      sites[2].noJoin = NoJoin.field;
      final (plan, _) = compile(
        _Scene(sites),
        Ledger(),
        const Prices(),
        const Policy(),
        100,
        explain: true,
      );
      expect(plan.notes, hasLength(2));
      expect(plan.notes.first, endsWith('painted over after its lead'));
      expect(plan.notes.last, endsWith('never joins: field'));
    });

    test('something painted under glass after the lead keeps it apart', () {
      final sites = _row(2);
      sites[1].floor = sites[0].order + 1;
      expect(_plan(_Scene(sites)).reads, hasLength(2));
    });

    test('other looks and overlapping glass stay apart', () {
      final looks = _row(2);
      looks[1].look = _look(1);
      expect(_plan(_Scene(looks)).reads, hasLength(2));
      final over = [
        _site(0, const Rect.fromLTWH(0, 0, 100, 100)),
        _site(2, const Rect.fromLTWH(50, 50, 100, 100)),
      ];
      final plan = _plan(_Scene(over));
      expect(plan.reads, hasLength(2));
      expect(plan.reads[1].level, 1);
    });

    test('a clip of the lead that would cut glass keeps it apart', () {
      final sites = _row(2);
      sites[0].clip = const Rect.fromLTWH(0, 0, 60, 200);
      expect(_plan(_Scene(sites)).reads, hasLength(2));
    });

    test('a band joins the glass over it that can draw it', () {
      final band = _site(0, const Rect.fromLTWH(0, 0, 411, 100));
      band.look = const Look(
        key: 'band',
        need: CopyNeed(1, share: 2, frost: 2),
        isBand: true,
      );
      final glass = _site(2, const Rect.fromLTWH(8, 50, 44, 44));
      glass.look = const Look(
        key: 'a',
        need: CopyNeed(1, share: 2, frost: 2),
        drawsBand: true,
      );
      final beside = _site(4, const Rect.fromLTWH(8, 110, 44, 44));
      beside.look = glass.look;
      expect(_plan(_Scene([band, glass])).reads, hasLength(1));
      expect(_plan(_Scene([band, beside])).reads, hasLength(2));
    });

    test('glass stays over the glass it overlaps', () {
      final low = _site(0, const Rect.fromLTWH(0, 0, 100, 100));
      final other = _site(2, const Rect.fromLTWH(200, 0, 100, 100));
      other.look = const Look(key: 'other', need: CopyNeed.exact(1));
      final top = _site(4, const Rect.fromLTWH(250, 50, 20, 20));
      top.look = low.look;
      top.floor = -1;
      expect(_plan(_Scene([low, other, top])).reads, hasLength(3));
    });

    test('a copy of few pixels still holds the glass under it', () {
      final low = _site(0, const Rect.fromLTWH(0, 0, 100, 100));
      final top = _site(2, const Rect.fromLTWH(20, 20, 300, 60));
      top.look = const Look(
        key: 'thick',
        need: CopyNeed(1, share: 4, frost: 20),
      );
      top.floor = -1;
      final plan = _plan(_Scene([low, top]));
      expect(plan.reads, hasLength(2));
      expect(plan.reads[1].holds, [plan.reads[0]]);
    });

    test('chrome at both ends of the screen does not share a whole screen', () {
      final top = _site(0, const Rect.fromLTWH(8, 40, 395, 60));
      final bottom = _site(2, const Rect.fromLTWH(8, 830, 395, 60));
      expect(_plan(_Scene([top, bottom])).reads, hasLength(2));
    });
  });

  group('holding', () {
    Ledger still(Scenery scene, int frames) {
      final ledger = Ledger();
      for (var frame = 1; frame <= frames; frame++) {
        _plan(scene, ledger: ledger, frame: frame);
      }
      return ledger;
    }

    test('glass over what holds still buys one image and keeps it', () {
      final scene = _Scene(_row(1));
      final ledger = Ledger();
      var images = 0;
      for (var frame = 1; frame <= 60; frame++) {
        images += _newImages(_plan(scene, ledger: ledger, frame: frame));
      }
      expect(images, 1);
      final read = _plan(scene, ledger: ledger, frame: 61).reads.single;
      expect(read.source, isA<ImageRead>());
      expect((read.source as ImageRead).held, isTrue);
    });

    Look look(double frost, {PageFilter? page}) => Look(
      key: 'glass',
      need: CopyNeed(2.625, share: 2, frost: frost),
      page: page,
    );

    test('glass whose read reaches past the screen keeps its image', () {
      final scene = _Scene([_site(0, const Rect.fromLTWH(-4, 200, 500, 90))]);
      final ledger = Ledger();
      for (var frame = 1; frame <= 60; frame++) {
        _plan(scene, ledger: ledger, frame: frame);
      }
      final read = _plan(scene, ledger: ledger, frame: 61).reads.single;
      expect(read.source, const ImageRead(held: true));
    });

    test('a held image goes when the frost baked into it changes', () {
      final site = _site(0, const Rect.fromLTWH(20, 200, 200, 90));
      site.look = look(4);
      final scene = _Scene([site]);
      final ledger = Ledger();
      for (var frame = 1; frame <= 60; frame++) {
        _plan(scene, ledger: ledger, frame: frame);
      }
      final held = _plan(scene, ledger: ledger, frame: 61).reads.single;
      expect(held.source, const ImageRead(held: true));
      site.look = look(5);
      final read = _plan(scene, ledger: ledger, frame: 62).reads.single;
      expect(read.changed, isTrue);
      expect(read.source, isA<SceneRead>());
    });

    test('a held image goes when the filter baked into it changes', () {
      final site = _site(0, const Rect.fromLTWH(20, 200, 200, 90));
      site.look = look(0, page: const PageFilter(blur: (4, 4)));
      final scene = _Scene([site]);
      final ledger = Ledger();
      _plan(scene, ledger: ledger, frame: 1);
      final held = _plan(scene, ledger: ledger, frame: 2).reads.single;
      expect(held.source, const ImageRead(held: true));
      site.look = look(0, page: const PageFilter(blur: (8, 8)));
      final read = _plan(scene, ledger: ledger, frame: 3).reads.single;
      expect(read.source, const ImageRead(held: false));
    });

    test('a filter of a page over a texture reads live, and so does '
        'what lies over it', () {
      final page = _site(2, const Rect.fromLTWH(20, 200, 200, 90));
      page.look = look(0, page: const PageFilter(blur: (4, 4)));
      final over = _site(4, const Rect.fromLTWH(20, 200, 200, 90));
      final scene = _Scene([page, over]);
      scene.texturesBefore = 1;
      final plan = _plan(scene, frame: 1);
      expect(plan.reads.first.source, isA<LiveRead>());
      expect(plan.reads.last.source, isA<LiveRead>());
    });

    test('a menu over a page long still buys in its first frame', () {
      final scene = _Scene([_site(0, const Rect.fromLTWH(20, 200, 300, 400))]);
      final read = _plan(scene, frame: 500).reads.single;
      expect(read.source, isA<ImageRead>());
    });

    test('what changed in the same frame is never served from an image', () {
      final scene = _Scene(_row(1));
      final ledger = still(scene, 60);
      scene.sites.first.order = 5;
      scene.dirty.add(1, const Rect.fromLTWH(0, 0, 100, 200));
      final read = _plan(scene, ledger: ledger, frame: 61).reads.single;
      expect(read.source, isA<SceneRead>());
      expect(read.changed, isTrue);
    });

    test('an image over a lower read that changed is never served', () {
      final lower = _site(0, const Rect.fromLTWH(0, 0, 100, 100));
      final upper = _site(4, const Rect.fromLTWH(50, 50, 100, 100));
      final scene = _Scene([lower, upper]);
      final ledger = still(scene, 60);
      scene.dirty.add(0, const Rect.fromLTWH(0, 0, 60, 60));
      lower.order = 1;
      final plan = _plan(scene, ledger: ledger, frame: 61);
      expect(plan.reads[1].source, isA<SceneRead>());
    });

    test('holds that do not pay make the next wait longer', () {
      final scene = _Scene(_row(1));
      scene.sites.first.order = 5;
      final ledger = Ledger();
      var frame = 0;
      int? firstNeed;
      int waitForImage() {
        var waited = 0;
        while (true) {
          frame++;
          waited++;
          final plan = _plan(scene, ledger: ledger, frame: frame);
          if (_newImages(plan) == 1) return waited;
          expect(waited, lessThan(2000));
        }
      }

      scene.dirty.add(0, const Rect.fromLTWH(0, 0, 100, 200));
      frame++;
      _plan(scene, ledger: ledger, frame: frame);
      for (var i = 0; i < 3; i++) {
        scene.dirty.clear();
        final waited = waitForImage();
        firstNeed ??= waited;
        scene.dirty.add(0, const Rect.fromLTWH(0, 0, 100, 200));
        frame++;
        _plan(scene, ledger: ledger, frame: frame);
      }
      scene.dirty.clear();
      expect(waitForImage(), greaterThan(firstNeed!));
    });

    test('over content that changes by itself nothing holds', () {
      final scene = _Scene(_row(1));
      scene.sites.first.order = 5;
      scene.texturesBefore = 0;
      final ledger = Ledger();
      for (var frame = 1; frame <= 60; frame++) {
        scene.dirty.clear();
        scene.dirty.add(0, _screen);
        final read = _plan(scene, ledger: ledger, frame: frame).reads.single;
        expect(read.source, isA<SceneRead>());
      }
    });
  });

  group('live groups', () {
    // Different looks keep the reads apart, so each one is a read of its own.
    _Scene live(List<SiteFacts> sites) {
      final scene = _Scene(sites);
      scene.platformBefore = 0;
      return scene;
    }

    List<SiteFacts> pair({double gap = 200}) => [
      _site(1, const Rect.fromLTWH(8, 100, 44, 44)),
      _site(3, Rect.fromLTWH(8 + gap, 100, 44, 44), look: 1),
    ];

    test('glass side by side shares one backdrop grab', () {
      final plan = _plan(live(pair()));
      expect(plan.reads, hasLength(2));
      expect(plan.reads.every((read) => read.source is LiveRead), isTrue);
      expect(plan.reads.first.liveGroup, isNotNull);
      expect(plan.reads.last.liveGroup, plan.reads.first.liveGroup);
    });

    test('keeps a read apart when something paints under it', () {
      final sites = pair();
      sites.last.floor = 2;
      final plan = _plan(live(sites));
      expect(plan.reads.map((read) => read.liveGroup), [null, null]);
    });

    test('keeps a read apart when it reads what the last one drew', () {
      final plan = _plan(live(pair(gap: 30)));
      expect(plan.reads.map((read) => read.liveGroup), [null, null]);
    });

    test('keeps a read apart under another clip', () {
      final sites = pair();
      sites.last.state = const StateChain(StateChain.root, 'clip');
      final plan = _plan(live(sites));
      expect(plan.reads.map((read) => read.liveGroup), [null, null]);
    });

    test('leaves out glass that has no matte', () {
      final sites = pair();
      sites.last.noJoin = NoJoin.noMatte;
      final plan = _plan(live(sites));
      expect(plan.reads.map((read) => read.liveGroup), [null, null]);
    });

    test('numbers runs apart', () {
      final sites = [
        ...pair(),
        _site(5, const Rect.fromLTWH(8, 300, 44, 44), look: 2, floor: 4),
        _site(7, const Rect.fromLTWH(208, 300, 44, 44), look: 3, floor: 4),
      ];
      final plan = _plan(live(sites));
      final groups = [for (final read in plan.reads) read.liveGroup];
      expect(groups, [0, 0, 1, 1]);
    });

    test('never groups a read that uses a scene copy or an image', () {
      final plan = _plan(_Scene(pair()));
      expect(plan.reads.map((read) => read.liveGroup), everyElement(isNull));
    });
  });

  group('every generated frame', () {
    const seeds = 3000;

    test('stays under the bound unless a read can not use an image', () {
      for (var seed = 0; seed < seeds; seed++) {
        final scene = _generated(seed);
        final plan = _plan(scene);
        if (plan.issuedTargets <= const Policy().maxTargets) continue;
        final stuck = plan.reads.where((read) => read.source is! ImageRead);
        for (final read in stuck) {
          expect(
            scene.limitUnder(read.lead) != ReadLimit.none ||
                read.source is LiveRead,
            isTrue,
            reason:
                'seed $seed left ${plan.issuedTargets} targets on a read '
                'that could use an image',
          );
        }
      }
    });

    test('holds a settings card of twelve rows to the bound', () {
      final rows = [
        for (var i = 0; i < 12; i++)
          _site(
            i * 2,
            Rect.fromLTWH(8, 60 + i * 60.0, 44, 44),
            floor: i * 2 - 1,
          ),
      ];
      final plan = _plan(_Scene(rows));
      expect(plan.reads, hasLength(12));
      expect(plan.issuedTargets, lessThanOrEqualTo(const Policy().maxTargets));
    });

    test('comes out the same twice', () {
      for (var seed = 0; seed < seeds; seed++) {
        final scene = _generated(seed);
        final a = _plan(scene);
        final b = _plan(scene);
        expect(b.reads.length, a.reads.length, reason: 'seed $seed');
        expect(b.issuedTargets, a.issuedTargets, reason: 'seed $seed');
        for (var i = 0; i < a.reads.length; i++) {
          expect(
            b.reads[i].members.length,
            a.reads[i].members.length,
            reason: 'seed $seed',
          );
        }
      }
    });

    test('gives every site exactly one fate', () {
      for (var seed = 0; seed < seeds; seed++) {
        final scene = _generated(seed);
        final plan = _plan(scene);
        expect(plan.fates, hasLength(scene.sites.length));
        final inReads = plan.reads.fold(0, (n, r) => n + r.members.length);
        final hidden = plan.fates.whereType<Hidden>().length;
        expect(inReads + hidden, scene.sites.length, reason: 'seed $seed');
      }
    });

    test('moves by at most two targets when a price is three times off', () {
      const base = Prices();
      final variants = <Prices>[
        for (final f in [1 / 3, 3.0]) ...[
          Prices(passGpu: base.passGpu * f, passRaster: base.passRaster * f),
          Prices(copyGpuPerMpx: base.copyGpuPerMpx * f),
          Prices(deadGpuPerMpx: base.deadGpuPerMpx * f),
          Prices(rasterWeight: base.rasterWeight * f),
          Prices(imageRaster: base.imageRaster * f),
        ],
      ];
      final moved = <int>[];
      for (var seed = 0; seed < 500; seed++) {
        final scene = _generated(seed);
        // Over a texture nothing can move to an image, and overlapping glass
        // doubles per level with no bound to hold it.
        if (scene.texturesBefore >= 0 || scene.platformBefore >= 0) continue;
        final targets = _plan(scene).issuedTargets;
        for (final prices in variants) {
          final other = _plan(_generated(seed), prices: prices);
          moved.add((other.issuedTargets - targets).abs());
        }
      }
      moved.sort();
      expect(moved[moved.length * 99 ~/ 100], lessThanOrEqualTo(2));
    });

    test('takes no more reads when disjoint glass of a look is added', () {
      final few = _row(3);
      final many = _row(7);
      expect(
        _plan(_Scene(many)).reads.length,
        _plan(_Scene(few)).reads.length,
      );
    });
  });

  group('prices', () {
    test('a large read pays for an image sooner than a small one', () {
      const prices = Prices();
      final large = prices.rent(const Rect.fromLTWH(0, 0, 400, 800), 1);
      final small = prices.rent(const Rect.fromLTWH(0, 0, 44, 44), 2);
      expect(large, lessThan(small));
    });
  });
}
