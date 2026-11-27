import 'dart:convert';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = GlassFormFactor.phone;
const _tablet = GlassFormFactor.tablet;
const _desktop = GlassFormFactor.desktop;
const _compact = GlassSizeClass.compact;
const _regular = GlassSizeClass.regular;

GlassEnvironment _environment(
  GlassFormFactor formFactor,
  GlassSizeClass horizontal,
) => GlassEnvironment(formFactor: formFactor, horizontalSizeClass: horizontal);

// Where the tabs go, whether the sidebar stands beside, and the list.
typedef _Row = (GlassTabPlacement, bool, GlassTabListMode);

_Row _rowOf(GlassTabLayout layout) =>
    (layout.placement, layout.sidebarBeside, layout.list);

const _bottom = GlassTabPlacement.bottom;
const _sidebar = GlassTabPlacement.sidebar;
const _stacked = GlassTabListMode.stacked;
const _hidden = GlassTabListMode.hidden;
const _beside = GlassTabListMode.beside;

void main() {
  test('automatic follows the table of devices and windows', () {
    const policy = GlassTabLayoutPolicy.automatic();
    final cases = <(String, GlassEnvironment, Size, _Row)>[
      (
        'iPhone portrait',
        _environment(_phone, _compact),
        const Size(402, 874),
        (_bottom, false, _stacked),
      ),
      (
        'iPhone landscape',
        _environment(_phone, _compact),
        const Size(874, 402),
        (_bottom, false, _stacked),
      ),
      (
        'iPhone Pro Max landscape',
        _environment(_phone, _regular),
        const Size(956, 440),
        (_bottom, false, _beside),
      ),
      (
        'Duo cover',
        _environment(_phone, _compact),
        const Size(466, 678),
        (_bottom, false, _stacked),
      ),
      (
        'Duo inner',
        _environment(_phone, _regular),
        const Size(951, 669),
        (_bottom, false, _beside),
      ),
      (
        'Duo inner portrait',
        _environment(_phone, _regular),
        const Size(669, 951),
        (_bottom, false, _beside),
      ),
      (
        'iPad window, compact',
        _environment(_tablet, _compact),
        const Size(667, 700),
        (_bottom, false, _stacked),
      ),
      (
        'iPad window, regular and narrow',
        _environment(_tablet, _regular),
        const Size(700, 834),
        (_bottom, false, _hidden),
      ),
      (
        'iPad window, short',
        _environment(_tablet, _regular),
        const Size(915, 486),
        (_bottom, false, _beside),
      ),
      (
        'iPad portrait',
        _environment(_tablet, _regular),
        const Size(1032, 1376),
        (_bottom, false, _beside),
      ),
      (
        'iPad landscape',
        _environment(_tablet, _regular),
        const Size(1210, 834),
        (_sidebar, true, _beside),
      ),
      (
        'a desktop window as an iPad window',
        _environment(_desktop, _regular),
        const Size(1024, 600),
        (_sidebar, true, _beside),
      ),
    ];
    for (final (name, environment, size, row) in cases) {
      expect(
        _rowOf(policy.resolve(environment, size)),
        row,
        reason: name,
      );
    }
    expect(policy.remembersSidebar, isFalse);
  });

  test('automatic takes its numbers as arguments', () {
    const range = GlassWidthRange(minimum: 280, preferred: 340, maximum: 480);
    const policy = GlassTabLayoutPolicy.automatic(
      sidebarBesideFrom: 900,
      listBesideFrom: 800,
      railWidth: 56,
      listWidth: range,
    );
    final environment = _environment(_tablet, _regular);
    final wide = policy.resolve(environment, const Size(900, 700));
    expect(_rowOf(wide), (_sidebar, true, _beside));
    expect(wide.railWidth, 56);
    expect(wide.listWidth, range);
    expect(
      _rowOf(policy.resolve(environment, const Size(799, 700))),
      (_bottom, false, _hidden),
    );
  });

  test('desktop stands the sidebar beside from 668 wide, folding and not '
      'hiding, and a list beside its pages where both columns fit', () {
    const policy = GlassTabLayoutPolicy.desktop();
    final environment = _environment(_desktop, _regular);
    expect(policy.remembersSidebar, isTrue);
    expect(
      _rowOf(policy.resolve(environment, const Size(667, 800))),
      (_bottom, false, _stacked),
    );
    final narrow = policy.resolve(environment, const Size(668, 800));
    expect(_rowOf(narrow), (_sidebar, true, _stacked));
    expect(narrow.sidebarHides, isFalse);
    expect(narrow.sidebarFolds, isTrue);
    // The sidebar's 280, the list's 240 and the detail's 448.
    expect(
      policy.resolve(environment, const Size(967, 800)).list,
      _stacked,
    );
    expect(policy.resolve(environment, const Size(968, 800)).list, _beside);

    const tuned = GlassTabLayoutPolicy.desktop(
      sidebarFrom: 600,
      hides: true,
      sidebarWidth: GlassWidthRange(minimum: 140, preferred: 220, maximum: 320),
      railWidth: 56,
    );
    final layout = tuned.resolve(environment, const Size(600, 800));
    expect(_rowOf(layout), (_sidebar, true, _stacked));
    expect(layout.sidebarHides, isTrue);
    expect(layout.sidebarWidth.preferred, 220);
    expect(layout.railWidth, 56);
  });

  test('custom gives what its function gives', () {
    final policy = GlassTabLayoutPolicy.custom(
      (environment, size) => size.width < 500
          ? const GlassTabLayout.bottom()
          : const GlassTabLayout.sidebar(beside: true),
      remembersSidebar: true,
    );
    final environment = _environment(_tablet, _regular);
    expect(
      policy.resolve(environment, const Size(499, 800)),
      const GlassTabLayout.bottom(),
    );
    expect(
      policy.resolve(environment, const Size(500, 800)),
      const GlassTabLayout.sidebar(beside: true),
    );
    expect(policy.remembersSidebar, isTrue);
  });

  test('a layout state goes through JSON and back, and reading leaves out '
      'what it does not recognize', () {
    const state = GlassTabLayoutState(
      sidebarShown: false,
      sidebarWidth: 340,
      sidebarRail: true,
      lists: {
        0: GlassTabListState(width: 360, shown: false),
        3: GlassTabListState(shown: true),
      },
    );
    final json = jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
    expect(GlassTabLayoutState.fromJson(json), state);
    expect(const GlassTabLayoutState().toJson(), isEmpty);

    expect(
      GlassTabLayoutState.fromJson(const {
        'sidebarShown': 'yes',
        'sidebarWidth': -4,
        'sidebarRail': 1,
        'lists': {
          'one': {'width': 300},
          '-1': {'width': 300},
          '2': 'wide',
          '4': {'width': 'wide', 'shown': true, 'extra': 1},
        },
        'unknown': true,
      }),
      const GlassTabLayoutState(lists: {4: GlassTabListState(shown: true)}),
    );
  });

  test('the controller keeps the layout state, leaving out whether the '
      'sidebar shows until a policy that remembers it lays it out', () {
    final controller = GlassTabController();
    addTearDown(controller.dispose);
    var heard = 0;
    controller.addListener(() => heard++);
    controller.layoutState = const GlassTabLayoutState(
      sidebarShown: false,
      sidebarWidth: 340,
      lists: {1: GlassTabListState(width: 300, shown: false)},
    );
    expect(heard, 1);
    expect(controller.sidebarShown, isFalse);
    expect(controller.sidebarWidth, 340);
    expect(controller.splitOf(1).primaryWidth, 300);
    expect(controller.splitOf(1).showsPrimary, isFalse);
    expect(
      controller.layoutState,
      const GlassTabLayoutState(
        sidebarWidth: 340,
        lists: {1: GlassTabListState(width: 300, shown: false)},
      ),
    );

    controller.layoutState = const GlassTabLayoutState();
    expect(heard, 2);
    expect(controller.splitOf(1).primaryWidth, isNull);
    expect(controller.splitOf(1).showsPrimary, isNull);
    expect(controller.layoutState, const GlassTabLayoutState());
  });
}
