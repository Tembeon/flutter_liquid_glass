import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/tab_bar_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// The bars of an iPhone 16 Pro (402 pt, 360 available): the title widths,
// the bar's width and each button's leading edge and width in the bar.
const _device = <(String, List<double>, double, List<(double, double)>)>[
  ('en 2', [29, 35], 188, [(4, 94), (90, 94)]),
  ('en 3', [29, 35, 28], 274, [(4, 94), (90, 94), (176, 94)]),
  (
    'en 4',
    [29, 35, 28, 36.33],
    360,
    [(4, 98), (88.67, 98), (173.33, 98), (258, 98)],
  ),
  (
    'en 5',
    [29, 35, 28, 36.33, 34.33],
    360,
    [(4, 77), (72.75, 77), (141.5, 77), (210.25, 77), (279, 77)],
  ),
  ('ru 2', [40.67, 56.33], 192.67, [(4, 96.33), (92.33, 96.33)]),
  (
    'ru 3',
    [40.67, 56.33, 56],
    281,
    [(4, 96.33), (92.33, 96.33), (180.67, 96.33)],
  ),
  (
    'ru 4',
    [40.67, 56.33, 56, 32],
    360,
    [(4, 96.33), (89.22, 96.33), (174.44, 96.33), (259.67, 96.33)],
  ),
  (
    'ru 5',
    [40.67, 56.33, 56, 32, 57],
    360,
    [
      (4, 77.22),
      (61.22, 92.4),
      (133.62, 92.05),
      (205.67, 77.22),
      (262.89, 93.11),
    ],
  ),
  ('long 2', [118.67, 119.33], 318.67, [(4, 159.33), (155.33, 159.33)]),
  (
    'long 3',
    [130, 130, 130],
    360,
    [(4, 122.67), (118.67, 122.67), (233.33, 122.67)],
  ),
];

void main() {
  for (final (name, naturals, width, buttons) in _device) {
    test('$name lays out as on the device', () {
      final layout = TabBarLayout.of(naturals, available: 360);
      expect(layout.width, closeTo(width, 0.02));
      for (final (i, (left, buttonWidth)) in buttons.indexed) {
        final button = layout.buttons[i];
        expect(button.width, closeTo(buttonWidth, 0.04), reason: 'width $i');
        expect(
          button.center - button.width / 2,
          closeTo(left, 0.04),
          reason: 'left $i',
        );
      }
    });
  }

  test('four tabs keep the bar across languages; their tabs adapt', () {
    final short = TabBarLayout.of(const [29, 35, 28, 36], available: 360);
    final long = TabBarLayout.of(const [120, 130, 140, 150], available: 360);
    expect(long.width, short.width);
    expect(long.buttons.last.center, lessThan(360));
  });

  test('a bar hosting an accessory fills its room with two tabs; one '
      'hosting a search tab only from three', () {
    double width(List<double> tabs, TabBarHost host) =>
        TabBarLayout.of(tabs, available: 290, host: host).width;
    expect(width(const [29, 35], TabBarHost.accessory), 290);
    expect(width(const [29, 35], TabBarHost.circle), 188);
    expect(width(const [29, 35, 30], TabBarHost.circle), 290);
  });

  test('tabs too long for the bar end up inside it', () {
    final layout = TabBarLayout.of(
      const [200, 200, 200, 200, 200],
      available: 360,
    );
    final last = layout.buttons.last;
    expect(last.center + last.width / 2, lessThanOrEqualTo(360 - 4 + 1e-6));
    expect(layout.buttons.first.center - layout.buttons.first.width / 2, 4);
  });

  group('wide', () {
    const wide = TabBarMetrics.wide;

    test('a bar hosting nothing is as wide as its tabs, 4 points between '
        'their buttons (iPhone in landscape, iOS 27.2 simulator)', () {
      const buttons = [80.67, 73, 86.33, 86, 73.67];
      final layout = TabBarLayout.of(
        [for (final button in buttons) button - 12],
        available: 674,
        metrics: wide,
      );
      expect(layout.width, closeTo(423.67, 0.01));
      var left = 4.0;
      for (final (i, width) in buttons.indexed) {
        final button = layout.buttons[i];
        expect(button.width, closeTo(width, 0.01), reason: 'width $i');
        expect(
          button.center - button.width / 2,
          closeTo(left, 0.01),
          reason: 'left $i',
        );
        left += width + 4;
      }
    });

    test('a bar hosting a circle shares 588 points among its tabs: four '
        'buttons 148 wide at a pitch of 144 (iOS 27.2 simulator rows)', () {
      final layout = TabBarLayout.of(
        const [62.67, 60.33, 65, 70],
        available: 874 - 2 * 62 - 2 * 38,
        host: TabBarHost.circle,
        metrics: wide,
      );
      expect(layout.width, 588);
      for (final (i, left) in const [4.0, 148, 292, 436].indexed) {
        final button = layout.buttons[i];
        expect(button.width, closeTo(148, 0.01), reason: 'width $i');
        expect(
          button.center - button.width / 2,
          closeTo(left, 0.01),
          reason: 'left $i',
        );
      }
    });

    test('a bar hosting an accessory is at most 640 wide', () {
      final layout = TabBarLayout.of(
        const [62.67, 60.33],
        available: 900,
        host: TabBarHost.accessory,
        metrics: wide,
      );
      expect(layout.width, 640);
    });

    test('tabs whose content does not fit share the room, inside it', () {
      final layout = TabBarLayout.of(
        const [300, 300, 300],
        available: 600,
        metrics: wide,
      );
      expect(layout.width, 600);
      final last = layout.buttons.last;
      expect(last.center + last.width / 2, lessThanOrEqualTo(596 + 1e-6));
      expect(layout.buttons.first.center - layout.buttons.first.width / 2, 4);
    });

    test('the buttons are 36 tall, the bar 44', () {
      expect(wide.height, 44);
      expect(wide.buttonHeight, 36);
      expect(TabBarMetrics.compact.buttonHeight, 54);
    });
  });

  test('a bar lays out wide where the window is regular across, or short '
      'and the bar at least 568 wide', () {
    TabBarMetrics of(
      GlassSizeClass horizontal,
      GlassSizeClass vertical,
      double width,
    ) => TabBarMetrics.of(
      GlassEnvironment(
        horizontalSizeClass: horizontal,
        verticalSizeClass: vertical,
      ),
      width,
    );
    const compact = GlassSizeClass.compact;
    const regular = GlassSizeClass.regular;
    expect(of(compact, regular, 402), TabBarMetrics.compact);
    expect(of(compact, regular, 669), TabBarMetrics.compact);
    expect(of(compact, compact, 874), TabBarMetrics.wide);
    expect(of(compact, compact, 567), TabBarMetrics.compact);
    expect(of(regular, compact, 956), TabBarMetrics.wide);
    expect(of(regular, regular, 834), TabBarMetrics.wide);
  });
}
